import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch
from urllib.parse import parse_qs, urlparse

import weather


FORECAST = {
    "timezone": "America/New_York",
    "current": {
        "time": "2026-09-24T10:30",
        "temperature_2m": 21.4,
        "apparent_temperature": 22.1,
        "relative_humidity_2m": 63,
        "is_day": 1,
        "precipitation": 0.0,
        "weather_code": 2,
        "cloud_cover": 41,
        "pressure_msl": 1014.2,
        "wind_speed_10m": 18.5,
        "wind_direction_10m": 225,
        "wind_gusts_10m": 31.0,
        "visibility": 16000,
        "uv_index": 4.2,
    },
    "hourly": {
        "time": ["2026-09-24T09:00", "2026-09-24T10:00", "2026-09-24T11:00", "2026-09-24T12:00"],
        "temperature_2m": [19.0, 20.1, 21.4, 22.2],
        "apparent_temperature": [19.0, 20.1, 22.0, 22.9],
        "precipitation_probability": [5, 10, 35, 48],
        "precipitation": [0, 0, 0.1, 0.2],
        "weather_code": [1, 2, 2, 3],
        "is_day": [1, 1, 1, 1],
        "uv_index": [2.0, 3.0, 4.2, 5.1],
    },
    "daily": {
        "time": ["2026-09-24", "2026-09-25"],
        "weather_code": [2, 61],
        "temperature_2m_max": [24.1, 22.0],
        "temperature_2m_min": [15.0, 14.0],
        "sunrise": ["2026-09-24T06:44", "2026-09-25T06:45"],
        "sunset": ["2026-09-24T19:05", "2026-09-25T19:04"],
        "daylight_duration": [44220, 44180],
        "uv_index_max": [5.2, 3.1],
        "precipitation_probability_max": [48, 82],
        "precipitation_sum": [0.3, 7.2],
        "wind_speed_10m_max": [24, 31],
        "wind_gusts_10m_max": [39, 48],
        "wind_direction_10m_dominant": [225, 200],
    },
}


class WeatherTest(unittest.TestCase):
    def setUp(self):
        self._cache = tempfile.TemporaryDirectory()
        self._cache_path = Path(self._cache.name)
        self._cache_patch = patch.object(weather, "CACHE_DIR", self._cache_path)
        self._cache_patch.start()

    def tearDown(self):
        self._cache_patch.stop()
        self._cache.cleanup()

    def test_normalizes_current_conditions(self):
        current = weather.normalize_current(FORECAST["current"])
        self.assertEqual(current["label"], "Partly cloudy")
        self.assertAlmostEqual(current["temperature"], 21.4)
        self.assertEqual(current["windDirection"], 225)
        self.assertEqual(current["uv"], 4.2)

    def test_normalizes_future_hours_and_daily_rows(self):
        current = weather.normalize_current(FORECAST["current"])
        hourly = weather.normalize_hourly(FORECAST, current["time"])
        daily = weather.normalize_daily(FORECAST)
        self.assertEqual([row["time"] for row in hourly], ["2026-09-24T11:00", "2026-09-24T12:00"])
        self.assertEqual(hourly[0]["precipProbability"], 35)
        self.assertEqual(daily[0]["date"], "2026-09-24")
        self.assertEqual(daily[1]["precipProbability"], 82)

    def test_collect_selected_location_uses_forecast_once(self):
        calls = []

        def fake(url):
            calls.append(url)
            return FORECAST

        result = weather.collect({
            "name": "New York",
            "latitude": 40.7128,
            "longitude": -74.006,
            "timezone": "America/New_York",
        }, fake)
        self.assertTrue(result["ok"])
        self.assertEqual(result["current"]["label"], "Partly cloudy")
        self.assertEqual(len(calls), 1)
        self.assertIn("api.open-meteo.com", calls[0])
        self.assertFalse(result.get("cached"))

    def test_collect_uses_approximate_location_without_settings(self):
        calls = []

        def fake(url):
            calls.append(url)
            if url == weather.IP_LOCATION_ENDPOINT:
                return {
                    "latitude": 51.5072,
                    "longitude": -0.1276,
                    "city": "London",
                    "region": "England",
                    "country_name": "United Kingdom",
                    "country_code": "GB",
                    "timezone": "Europe/London",
                }
            return FORECAST

        result = weather.collect({}, fake)
        self.assertTrue(result["ok"])
        self.assertEqual(result["location"]["source"], "approximate")
        self.assertIn("London", result["location"]["name"])
        self.assertEqual(calls[0], weather.IP_LOCATION_ENDPOINT)

    def test_search_normalizes_and_deduplicates_results(self):
        def fake(url):
            query = parse_qs(urlparse(url).query)
            self.assertEqual(query["name"], ["Paris, France"])
            return {"results": [
                {
                    "name": "Paris",
                    "latitude": 48.8566,
                    "longitude": 2.3522,
                    "admin1": "Île-de-France",
                    "country": "France",
                    "country_code": "fr",
                    "timezone": "Europe/Paris",
                },
                {
                    "name": "Paris",
                    "latitude": 48.8566,
                    "longitude": 2.3522,
                    "country": "France",
                    "timezone": "Europe/Paris",
                },
                {"name": "Invalid", "latitude": 200, "longitude": 0},
            ]}

        rows = weather.search_locations("Paris, France", fake)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["countryCode"], "FR")
        self.assertIn("France", rows[0]["detail"])

    def test_network_and_payload_errors_are_stable(self):
        def failed(url):
            raise OSError("offline")

        result = weather.collect({"latitude": 1, "longitude": 2}, failed)
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"], "Forecast is temporarily unavailable")
        self.assertEqual(result["hourly"], [])

        location_failed = weather.collect({}, failed)
        self.assertFalse(location_failed["ok"])
        self.assertEqual(location_failed["error"], "Location and forecast are unavailable")

        incomplete = weather.collect({"latitude": 1, "longitude": 2}, lambda url: {"current": {}})
        self.assertFalse(incomplete["ok"])
        self.assertEqual(incomplete["error"], "Forecast data was incomplete")

    def test_coordinate_validation_rejects_bad_values(self):
        self.assertEqual(weather.valid_coordinates(91, 0), None)
        self.assertEqual(weather.valid_coordinates(0, -181), None)
        self.assertEqual(weather.valid_coordinates("51.5", "-0.1"), (51.5, -0.1))

    def test_main_passes_selected_location_to_collector(self):
        output = io.StringIO()
        with patch("weather.collect", return_value={"ok": True, "current": {}}) as collect:
            with redirect_stdout(output):
                result = weather.main([
                    "weather.py",
                    "--latitude", "48.8566",
                    "--longitude", "2.3522",
                    "--label", "Paris",
                    "--timezone", "Europe/Paris",
                ])
        self.assertEqual(result, 0)
        collect.assert_called_once_with({
            "latitude": "48.8566",
            "longitude": "2.3522",
            "name": "Paris",
            "timezone": "Europe/Paris",
        }, cache_mode=None)
        self.assertTrue(json.loads(output.getvalue())["ok"])

    def test_cache_key_and_roundtrip(self):
        key = weather.cache_key({
            "name": "Seattle",
            "latitude": 47.6062,
            "longitude": -122.3321,
        })
        self.assertEqual(key, "47.6062_-122.3321")
        self.assertEqual(weather.cache_key({}), "approximate")

        payload = weather.collect({
            "name": "Seattle",
            "latitude": 47.6062,
            "longitude": -122.3321,
            "timezone": "America/Los_Angeles",
        }, lambda url: FORECAST)
        self.assertTrue(payload["ok"])
        cached = weather.read_cache(key, allow_stale=True)
        self.assertTrue(cached["ok"])
        self.assertTrue(cached["cached"])
        self.assertFalse(cached["stale"])
        self.assertEqual(cached["current"]["temperature"], 21.4)

    def test_cache_only_and_cache_first_modes(self):
        calls = []

        def fake(url):
            calls.append(url)
            return FORECAST

        location = {
            "name": "Seattle",
            "latitude": 47.6062,
            "longitude": -122.3321,
            "timezone": "America/Los_Angeles",
        }
        missing = weather.collect(location, fake, cache_mode="cache-only")
        self.assertFalse(missing["ok"])
        self.assertEqual(calls, [])

        live = weather.collect(location, fake)
        self.assertTrue(live["ok"])
        self.assertEqual(len(calls), 1)

        cached = weather.collect(location, fake, cache_mode="cache-only")
        self.assertTrue(cached["ok"])
        self.assertTrue(cached["cached"])
        self.assertEqual(len(calls), 1)

        first = weather.collect(location, fake, cache_mode="cache-first")
        self.assertTrue(first["ok"])
        self.assertTrue(first["cached"])
        self.assertEqual(len(calls), 1)

    def test_stale_cache_is_marked_and_usable(self):
        location = {
            "name": "Seattle",
            "latitude": 47.6062,
            "longitude": -122.3321,
        }
        weather.collect(location, lambda url: FORECAST)
        key = weather.cache_key(location)
        path = weather.cache_path(key)
        envelope = json.loads(path.read_text(encoding="utf-8"))
        envelope["savedAt"] = 1
        path.write_text(json.dumps(envelope), encoding="utf-8")
        cached = weather.read_cache(key, allow_stale=True, now=1 + weather.CACHE_TTL_SECONDS + 5)
        self.assertTrue(cached["stale"])
        fresh_only = weather.read_cache(key, allow_stale=False, now=1 + weather.CACHE_TTL_SECONDS + 5)
        self.assertIsNone(fresh_only)

    def test_live_failure_falls_back_to_stale_cache(self):
        location = {"name": "Seattle", "latitude": 47.6062, "longitude": -122.3321}
        weather.collect(location, lambda url: FORECAST)

        def failed(url):
            raise OSError("offline")

        result = weather.collect(location, failed)
        self.assertTrue(result["ok"])
        self.assertTrue(result["cached"])

    def test_main_cache_flags_reach_collector(self):
        output = io.StringIO()
        with patch("weather.collect", return_value={"ok": True, "current": {}}) as collect:
            with redirect_stdout(output):
                weather.main([
                    "weather.py",
                    "--latitude", "47.6062",
                    "--longitude", "-122.3321",
                    "--cache-first",
                ])
        collect.assert_called_once()
        self.assertEqual(collect.call_args.kwargs.get("cache_mode"), "cache-first")


if __name__ == "__main__":
    unittest.main()
