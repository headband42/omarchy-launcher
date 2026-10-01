import io
import json
import os
import struct
import tempfile
import zlib
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


AIR = {
    "current": {
        "time": "2026-09-24T10:00",
        "us_aqi": 42,
        "european_aqi": 21,
        "pm2_5": 6.2,
        "pm10": 9.1,
        "ozone": 61.0,
        "nitrogen_dioxide": 12.0,
        "sulphur_dioxide": 0.6,
        "carbon_monoxide": 180.0,
        "dust": 0.0,
        "grass_pollen": 24.0,
        "birch_pollen": None,
    },
    "hourly": {"time": ["2026-09-24T10:00", "2026-09-24T11:00"], "us_aqi": [42, None]},
}

RAINVIEWER = {
    "host": "https://tilecache.example",
    "radar": {"past": [
        {"time": 1000 + index * 600, "path": "/v2/radar/frame{0}".format(index)} for index in range(8)
    ] + [{"time": 9999, "path": "../escape"}]},
}


def encode_png(rows, filters):
    """An 8-bit RGBA PNG of rows (bytes, 4 per pixel), one filter type per row."""
    def paeth(a, b, c):
        estimate = a + b - c
        pa, pb, pc = abs(estimate - a), abs(estimate - b), abs(estimate - c)
        return a if pa <= pb and pa <= pc else b if pb <= pc else c

    width = len(rows[0]) // 4
    previous = bytes(len(rows[0]))
    body = b""
    for row, kind in zip(rows, filters):
        out = bytearray()
        for i, value in enumerate(row):
            left = row[i - 4] if i >= 4 else 0
            up = previous[i]
            corner = previous[i - 4] if i >= 4 else 0
            guess = [0, left, up, (left + up) >> 1, paeth(left, up, corner)][kind]
            out.append((value - guess) & 255)
        body += bytes([kind]) + bytes(out)
        previous = row

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    header = struct.pack(">IIBBBBB", width, len(rows), 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(body)) + chunk(b"IEND", b"")


def tile_rows(size, pixels=()):
    """size x size transparent rows with (x, y, alpha) pixels set."""
    rows = [bytearray(size * 4) for _ in range(size)]
    for x, y, alpha in pixels:
        rows[y][x * 4:x * 4 + 4] = bytes((30, 160, 230, alpha))
    return [bytes(row) for row in rows]


def by_endpoint(url):
    if url.startswith(weather.AIR_ENDPOINT):
        return AIR
    return FORECAST


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
        }, fake, air=False)
        self.assertTrue(result["ok"])
        self.assertEqual(result["current"]["label"], "Partly cloudy")
        self.assertEqual(len(calls), 1)
        self.assertIn("api.open-meteo.com", calls[0])
        self.assertFalse(result.get("cached"))
        self.assertIsNone(result["air"])

    def test_collect_adds_air_quality_beside_the_forecast(self):
        calls = []

        def fake(url):
            calls.append(url)
            return by_endpoint(url)

        result = weather.collect({"name": "Oslo", "latitude": 59.91, "longitude": 10.75}, fake)
        self.assertTrue(result["ok"])
        self.assertEqual(len(calls), 2)
        air_url = [url for url in calls if url.startswith(weather.AIR_ENDPOINT)][0]
        query = parse_qs(urlparse(air_url).query)
        self.assertIn("us_aqi", query["current"][0])
        self.assertIn("grass_pollen", query["current"][0])
        air = result["air"]
        self.assertEqual(air["usAqi"], 42)
        self.assertEqual(air["pm25"], 6.2)
        self.assertEqual(air["no2"], 12.0)
        self.assertEqual(air["pollen"], {"grass": 24.0})
        self.assertEqual(air["hourly"], [42])
        cached = weather.read_cache(weather.cache_key({"latitude": 59.91, "longitude": 10.75}))
        self.assertEqual(cached["air"]["usAqi"], 42)

    def test_air_failure_keeps_the_forecast_and_the_last_reading(self):
        location = {"name": "Oslo", "latitude": 59.91, "longitude": 10.75}
        weather.collect(location, by_endpoint)

        def air_down(url):
            if url.startswith(weather.AIR_ENDPOINT):
                raise OSError("offline")
            return FORECAST

        result = weather.collect(location, air_down)
        self.assertTrue(result["ok"])
        self.assertFalse(result["cached"])
        self.assertEqual(result["air"]["usAqi"], 42)

        fresh = weather.collect({"name": "Rome", "latitude": 41.9, "longitude": 12.5}, air_down)
        self.assertTrue(fresh["ok"])
        self.assertIsNone(fresh["air"])
        self.assertIsNone(weather.normalize_air({"current": {"us_aqi": None}}))
        self.assertIsNone(weather.normalize_air(FORECAST))

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
        }, cache_mode=None, air=True)
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
            if url.startswith(weather.FORECAST_ENDPOINT):
                calls.append(url)
            return by_endpoint(url)

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

    def test_main_no_air_flag_and_radar_mode(self):
        with patch("weather.collect", return_value={"ok": True}) as collect:
            with redirect_stdout(io.StringIO()):
                weather.main(["weather.py", "--latitude", "1", "--longitude", "2", "--no-air"])
        self.assertFalse(collect.call_args.kwargs.get("air"))

        output = io.StringIO()
        with patch("weather.collect_radar", return_value={"ok": True}) as radar:
            with redirect_stdout(output):
                weather.main(["weather.py", "--radar", "--latitude", "1", "--longitude", "2", "--style", "light", "--zoom", "7"])
        radar.assert_called_once_with({"latitude": "1", "longitude": "2"}, "light", "7")
        self.assertTrue(json.loads(output.getvalue())["ok"])

    def test_tile_math(self):
        x, y = weather.tile_position(0, 0, 1)
        self.assertAlmostEqual(x, 1.0)
        self.assertAlmostEqual(y, 1.0)
        x, y = weather.tile_position(43.6134, -116.2036, 6)
        self.assertEqual((int(x), int(y)), (11, 23))
        left, top, cells = weather.tile_grid(x, y, 6)
        self.assertEqual((left, top), (10, 22))
        self.assertEqual(cells[0], (10, 22))
        self.assertEqual(cells[4], (11, 23))
        self.assertEqual(len(cells), 9)
        # Across the antimeridian x wraps; off the top of the map is None.
        left, top, cells = weather.tile_grid(0.2, 0.5, 2)
        self.assertEqual(cells[0], None)
        self.assertEqual(cells[3], (3, 0))
        self.assertEqual(cells[4], (0, 0))

    def test_radar_frames_keep_the_newest_safe_paths(self):
        host, frames = weather.radar_frames(RAINVIEWER, count=3)
        self.assertEqual(host, "https://tilecache.example")
        self.assertEqual([frame["id"] for frame in frames], ["frame5", "frame6", "frame7"])
        self.assertEqual(weather.radar_frames({"host": "http://insecure", "radar": RAINVIEWER["radar"]}), ("", []))
        self.assertEqual(weather.radar_frames(None), ("", []))

    def test_collect_radar_saves_tiles_and_reuses_them(self):
        tile_calls = []

        def tile(url):
            tile_calls.append(url)
            if "/6/22/10" in url:
                raise OSError("missing")
            return b"png"

        location = {"latitude": 43.6134, "longitude": -116.2036}
        result = weather.collect_radar(location, "dark", 6, lambda url: RAINVIEWER, tile, now=5000)
        self.assertTrue(result["ok"])
        self.assertEqual(result["zoom"], 6)
        self.assertEqual(len(result["base"]), 9)
        self.assertEqual(len(result["labels"]), 9)
        self.assertEqual(len(result["frames"]), weather.RADAR_FRAMES)
        self.assertEqual(result["frames"][-1]["time"], 1000 + 7 * 600)
        self.assertAlmostEqual(result["offset"]["x"], 1.3415, places=3)
        self.assertTrue(result["base"][4].endswith("map/night-lights/6/11_23.png"))
        self.assertTrue(result["labels"][4].endswith("map/dark-labels/6/11_23.png"))
        self.assertTrue(result["frames"][-1]["tiles"][4].endswith("frames/frame7/6/11_23.png"))
        self.assertTrue(os.path.exists(result["frames"][-1]["tiles"][4]))
        self.assertIn("VIIRS_Black_Marble/default/2016-01-01/GoogleMapsCompatible_Level8/6/23/11.png", "".join(tile_calls))
        self.assertIn("World_Dark_Gray_Reference/MapServer/tile/6/23/11", "".join(tile_calls))
        self.assertIn("https://tilecache.example/v2/radar/frame7/256/6/11/23/2/1_1.png", tile_calls)
        self.assertTrue(result["dry"])  # every radar tile is a tiny empty PNG
        self.assertIsNone(result["nearest"])
        self.assertEqual(result["credit"], "NASA · Esri · RainViewer")
        self.assertEqual(result["base"][0], "")  # a failed tile is blank, not an error
        self.assertEqual(result["labels"][0], "")
        first = len(tile_calls)

        again = weather.collect_radar(location, "dark", 6, lambda url: self.fail("refetched"), tile, now=5000 + 60)
        self.assertEqual(again["frames"], result["frames"])
        self.assertEqual(len(tile_calls), first)

        # After the manifest expires only tiles not on disk are fetched.
        later = weather.collect_radar(location, "dark", 6, lambda url: RAINVIEWER, tile,
                                      now=5000 + weather.RADAR_TTL_SECONDS + 1)
        self.assertTrue(later["ok"])
        self.assertEqual(len(tile_calls[first:]), 2)
        self.assertTrue(all("/6/22/10" in url for url in tile_calls[first:]))

    def test_collect_radar_without_frames_or_location(self):
        self.assertFalse(weather.collect_radar({}, "dark")["ok"])
        down = weather.collect_radar({"latitude": 1, "longitude": 2}, "sepia", 12,
                                     lambda url: (_ for _ in ()).throw(OSError("offline")), lambda url: b"x")
        self.assertFalse(down["ok"])
        self.assertEqual(down["style"], "dark")
        self.assertEqual(down["zoom"], weather.RADAR_MAX_ZOOM)
        self.assertEqual(down["frames"], [])

    def test_png_alpha_rows_undoes_every_filter(self):
        rows = [bytes((x * 13 + y * 7) % 256 for x in range(24)) for y in range(5)]
        decoded = weather.png_alpha_rows(encode_png(rows, [0, 1, 2, 3, 4]))
        self.assertEqual(decoded, [row[3::4] for row in rows])
        self.assertIsNone(weather.png_alpha_rows(b"not a png"))
        rgb = encode_png(rows, [0] * 5).replace(b"\x08\x06", b"\x08\x02", 1)
        self.assertIsNone(weather.png_alpha_rows(rgb))

    def test_nearest_echo_finds_the_closest_opaque_pixel(self):
        size = 8
        folder = self._cache_path / "echo"
        folder.mkdir()
        paths = []
        for index in range(9):
            pixels = []
            if index == 5:  # right of centre: an opaque pixel 6 px east
                pixels = [(2, 4, 255)]
            if index == 1:  # above: a nearer faint halo, which is not rain
                pixels = [(4, 6, 200)]
            if index == 6:  # bottom left: opaque but further, due southwest
                pixels = [(4, 4, 255)]
            path = folder / "{0}.png".format(index)
            path.write_bytes(encode_png(tile_rows(size, pixels), [4] * size))
            paths.append(str(path))
        with patch.object(weather, "EMPTY_TILE_BYTES", 0):
            nearest = weather.nearest_echo(paths, {"x": 1.5, "y": 1.5}, 0, 0, size=size)
            self.assertEqual(nearest["bearing"], "E")
            self.assertAlmostEqual(nearest["km"], round(weather.EARTH_CIRCUMFERENCE_KM / size * 6, 1))
            paths[5] = ""
            self.assertEqual(weather.nearest_echo(paths, {"x": 1.5, "y": 1.5}, 0, 0, size=size)["bearing"], "SW")
            self.assertIsNone(weather.nearest_echo([paths[1], paths[0]], {"x": 1.5, "y": 1.5}, 0, 0, size=size))

    def test_frame_is_dry_only_when_every_tile_is_empty(self):
        folder = self._cache_path / "tiles"
        folder.mkdir()
        empty = folder / "empty.png"
        empty.write_bytes(b"x" * 334)
        rain = folder / "rain.png"
        rain.write_bytes(b"x" * 9000)
        self.assertTrue(weather.frame_is_dry([str(empty), "", str(empty)]))
        self.assertFalse(weather.frame_is_dry([str(empty), str(rain)]))
        self.assertFalse(weather.frame_is_dry([str(folder / "missing.png")]))
        self.assertFalse(weather.frame_is_dry(["", ""]))

    def test_old_radar_frames_are_pruned(self):
        root = self._cache_path / "radar" / "frames"
        for name in ("old", "keep", "recent"):
            (root / name / "6").mkdir(parents=True)
            (root / name / "6" / "1_1.png").write_bytes(b"x")
        os.utime(root / "old", (1000, 1000))
        os.utime(root / "keep", (1000, 1000))
        weather.prune_radar_frames({"keep"}, now=1000 + weather.RADAR_KEEP_SECONDS + 1)
        self.assertFalse((root / "old").exists())
        self.assertTrue((root / "keep").exists())
        self.assertTrue((root / "recent").exists())


if __name__ == "__main__":
    unittest.main()
