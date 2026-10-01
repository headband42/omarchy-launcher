#!/usr/bin/env python3
"""Open-Meteo conditions and forecast for the weather tile. Stdlib only.

    weather.py [--latitude N --longitude N [--label NAME] [--timezone TZ]]
               [--cache-first | --cache-only] [--no-air]
    weather.py --search QUERY     place matches for the settings panel
    weather.py --radar --latitude N --longitude N [--style dark|light] [--zoom N]
                                  radar frames and map tiles saved under the cache

Without coordinates it uses an approximate location. Air quality comes with the
forecast unless --no-air is given.
"""

import json
import math
import os
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen

FORECAST_ENDPOINT = "https://api.open-meteo.com/v1/forecast"
AIR_ENDPOINT = "https://air-quality-api.open-meteo.com/v1/air-quality"
RAINVIEWER_ENDPOINT = "https://api.rainviewer.com/public/weather-maps.json"
# Esri's gray canvas: a base layer, and labels drawn above the radar.
MAP_ENDPOINT = "https://server.arcgisonline.com/ArcGIS/rest/services/{layer}/MapServer/tile/{z}/{y}/{x}"
MAP_LAYERS = {
    "dark": ("Canvas/World_Dark_Gray_Base", "Canvas/World_Dark_Gray_Reference"),
    "light": ("Canvas/World_Light_Gray_Base", "Canvas/World_Light_Gray_Reference"),
}
GEOCODING_ENDPOINT = "https://geocoding-api.open-meteo.com/v1/search"
IP_LOCATION_ENDPOINT = "https://ipapi.co/json/"
USER_AGENT = "ande-launcher-weather/1.0"
CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME") or (Path.home() / ".cache")) / "ande.launcher" / "weather"
CACHE_TTL_SECONDS = 12 * 60
# RainViewer publishes a frame every 10 minutes and serves zoom 7 at most.
RADAR_TTL_SECONDS = 5 * 60
RADAR_KEEP_SECONDS = 3 * 60 * 60
RADAR_FRAMES = 6
RADAR_ZOOM = 6
RADAR_MAX_ZOOM = 7
RADAR_GRID = 3
TILE_SIZE = 256
# A RainViewer tile with no echoes is a ~330 byte transparent PNG.
EMPTY_TILE_BYTES = 600

CURRENT_VARIABLES = (
    "temperature_2m",
    "apparent_temperature",
    "relative_humidity_2m",
    "is_day",
    "precipitation",
    "rain",
    "showers",
    "snowfall",
    "weather_code",
    "cloud_cover",
    "pressure_msl",
    "surface_pressure",
    "wind_speed_10m",
    "wind_direction_10m",
    "wind_gusts_10m",
    "visibility",
    "uv_index",
)

HOURLY_VARIABLES = (
    "temperature_2m",
    "apparent_temperature",
    "precipitation_probability",
    "precipitation",
    "weather_code",
    "is_day",
    "uv_index",
)

DAILY_VARIABLES = (
    "weather_code",
    "temperature_2m_max",
    "temperature_2m_min",
    "sunrise",
    "sunset",
    "daylight_duration",
    "uv_index_max",
    "precipitation_probability_max",
    "precipitation_sum",
    "wind_speed_10m_max",
    "wind_gusts_10m_max",
    "wind_direction_10m_dominant",
)


def number(value, default=None):
    if isinstance(value, bool):
        return default
    try:
        result = float(value)
    except (TypeError, ValueError):
        return default
    return result if math.isfinite(result) else default


AIR_VARIABLES = (
    "us_aqi",
    "european_aqi",
    "pm2_5",
    "pm10",
    "ozone",
    "nitrogen_dioxide",
    "sulphur_dioxide",
    "carbon_monoxide",
    "dust",
)

# Open-Meteo has pollen for Europe only. Elsewhere these come back null.
POLLEN_TYPES = ("alder", "birch", "grass", "mugwort", "olive", "ragweed")


def text(value, limit=120):
    result = str(value or "").strip()
    return result[:limit]


def fetch_json(url, timeout=12):
    request = Request(url, headers={"Accept": "application/json", "User-Agent": USER_AGENT})
    with urlopen(request, timeout=timeout) as response:
        payload = response.read(2_000_001)
    if len(payload) > 2_000_000:
        raise ValueError("Weather response is too large")
    result = json.loads(payload.decode("utf-8"))
    if not isinstance(result, dict):
        raise ValueError("Weather response is not an object")
    return result


def valid_coordinates(latitude, longitude):
    lat = number(latitude)
    lon = number(longitude)
    if lat is None or lon is None:
        return None
    if not -90 <= lat <= 90 or not -180 <= lon <= 180:
        return None
    return lat, lon


def selected_location(settings):
    if not isinstance(settings, dict):
        return None
    place = settings.get("location")
    if not isinstance(place, dict):
        return None
    coordinates = valid_coordinates(place.get("latitude"), place.get("longitude"))
    if not coordinates:
        return None
    result = {
        "name": text(place.get("name") or place.get("label") or "Saved location", 80),
        "latitude": coordinates[0],
        "longitude": coordinates[1],
        "timezone": text(place.get("timezone"), 80),
        "admin1": text(place.get("admin1"), 80),
        "country": text(place.get("country"), 80),
        "countryCode": text(place.get("countryCode"), 4).upper(),
        "source": "selected",
    }
    return result


def approximate_location(fetch=fetch_json):
    payload = fetch(IP_LOCATION_ENDPOINT)
    coordinates = valid_coordinates(payload.get("latitude"), payload.get("longitude"))
    if not coordinates:
        raise ValueError("Approximate location is unavailable")
    city = text(payload.get("city"), 80)
    region = text(payload.get("region"), 80)
    country = text(payload.get("country_name") or payload.get("country"), 80)
    parts = [part for part in (city, region, country) if part]
    return {
        "name": " · ".join(parts[:2]) or text(payload.get("timezone"), 80) or "Approximate location",
        "latitude": coordinates[0],
        "longitude": coordinates[1],
        "timezone": text(payload.get("timezone"), 80),
        "admin1": region,
        "country": country,
        "countryCode": text(payload.get("country_code"), 4).upper(),
        "source": "approximate",
    }


def forecast_url(latitude, longitude, timezone=""):
    coordinates = valid_coordinates(latitude, longitude)
    if not coordinates:
        raise ValueError("Invalid coordinates")
    parameters = [
        ("latitude", coordinates[0]),
        ("longitude", coordinates[1]),
        ("timezone", timezone or "auto"),
        ("forecast_hours", 24),
        ("forecast_days", 6),
        ("temperature_unit", "celsius"),
        ("wind_speed_unit", "kmh"),
        ("precipitation_unit", "mm"),
        ("current", ",".join(CURRENT_VARIABLES)),
        ("hourly", ",".join(HOURLY_VARIABLES)),
        ("daily", ",".join(DAILY_VARIABLES)),
    ]
    return FORECAST_ENDPOINT + "?" + urlencode(parameters)


def geocoding_url(query):
    parameters = [
        ("name", query),
        ("count", 10),
        ("language", "en"),
        ("format", "json"),
    ]
    return GEOCODING_ENDPOINT + "?" + urlencode(parameters)


def air_quality_url(latitude, longitude, timezone=""):
    coordinates = valid_coordinates(latitude, longitude)
    if not coordinates:
        raise ValueError("Invalid coordinates")
    current = AIR_VARIABLES + tuple(name + "_pollen" for name in POLLEN_TYPES)
    parameters = [
        ("latitude", coordinates[0]),
        ("longitude", coordinates[1]),
        ("timezone", timezone or "auto"),
        ("forecast_hours", 12),
        ("current", ",".join(current)),
        ("hourly", "us_aqi"),
    ]
    return AIR_ENDPOINT + "?" + urlencode(parameters)


def weather_label(code):
    value = int(number(code, -1))
    if value == 0:
        return "Clear sky"
    if value == 1:
        return "Mostly clear"
    if value == 2:
        return "Partly cloudy"
    if value == 3:
        return "Overcast"
    if value in (45, 48):
        return "Fog"
    if value in (51, 53, 55):
        return "Drizzle"
    if value in (56, 57):
        return "Freezing drizzle"
    if value in (61, 63, 65, 80, 81, 82):
        return "Rain"
    if value in (66, 67):
        return "Freezing rain"
    if value in (71, 73, 75, 77, 85, 86):
        return "Snow"
    if value in (95, 96, 99):
        return "Thunderstorms"
    return "Mixed conditions"


def series_value(series, key, index, default=None):
    if not isinstance(series, dict):
        return default
    values = series.get(key)
    if not isinstance(values, list) or index >= len(values):
        return default
    return values[index]


def normalized_location(payload, requested):
    timezone = text(payload.get("timezone"), 80) or text(requested.get("timezone"), 80)
    result = dict(requested)
    result["timezone"] = timezone
    if not result.get("name"):
        result["name"] = timezone.rsplit("/", 1)[-1].replace("_", " ") or "Current location"
    return result


def normalize_current(raw):
    if not isinstance(raw, dict):
        return None
    code = int(number(raw.get("weather_code"), -1))
    temperature = number(raw.get("temperature_2m"))
    if temperature is None:
        return None
    return {
        "time": text(raw.get("time"), 40),
        "temperature": temperature,
        "apparent": number(raw.get("apparent_temperature"), temperature),
        "humidity": number(raw.get("relative_humidity_2m"), 0),
        "isDay": bool(number(raw.get("is_day"), 1)),
        "precipitation": number(raw.get("precipitation"), 0),
        "code": code,
        "label": weather_label(code),
        "cloud": number(raw.get("cloud_cover"), 0),
        "pressure": number(raw.get("pressure_msl"), number(raw.get("surface_pressure"), 0)),
        "wind": number(raw.get("wind_speed_10m"), 0),
        "windDirection": number(raw.get("wind_direction_10m"), 0),
        "gust": number(raw.get("wind_gusts_10m"), number(raw.get("wind_speed_10m"), 0)),
        "visibility": number(raw.get("visibility"), 0),
        "uv": number(raw.get("uv_index"), 0),
    }


def normalize_hourly(payload, current_time=""):
    hourly = payload.get("hourly") if isinstance(payload, dict) else None
    if not isinstance(hourly, dict):
        return []
    times = hourly.get("time")
    if not isinstance(times, list):
        return []
    rows = []
    for index, raw_time in enumerate(times):
        stamp = text(raw_time, 40)
        if current_time and stamp < current_time:
            continue
        temperature = number(series_value(hourly, "temperature_2m", index))
        if not stamp or temperature is None:
            continue
        code = int(number(series_value(hourly, "weather_code", index), -1))
        rows.append({
            "time": stamp,
            "temperature": temperature,
            "apparent": number(series_value(hourly, "apparent_temperature", index), temperature),
            "precipProbability": number(series_value(hourly, "precipitation_probability", index), 0),
            "precipitation": number(series_value(hourly, "precipitation", index), 0),
            "code": code,
            "label": weather_label(code),
            "isDay": bool(number(series_value(hourly, "is_day", index), 1)),
            "uv": number(series_value(hourly, "uv_index", index), 0),
        })
        if len(rows) == 12:
            break
    return rows


def normalize_daily(payload):
    daily = payload.get("daily") if isinstance(payload, dict) else None
    if not isinstance(daily, dict):
        return []
    times = daily.get("time")
    if not isinstance(times, list):
        return []
    rows = []
    for index, raw_date in enumerate(times):
        date = text(raw_date, 20)
        if not date:
            continue
        code = int(number(series_value(daily, "weather_code", index), -1))
        rows.append({
            "date": date,
            "code": code,
            "label": weather_label(code),
            "high": number(series_value(daily, "temperature_2m_max", index)),
            "low": number(series_value(daily, "temperature_2m_min", index)),
            "sunrise": text(series_value(daily, "sunrise", index), 40),
            "sunset": text(series_value(daily, "sunset", index), 40),
            "daylight": number(series_value(daily, "daylight_duration", index), 0),
            "uv": number(series_value(daily, "uv_index_max", index), 0),
            "precipProbability": number(series_value(daily, "precipitation_probability_max", index), 0),
            "precipitation": number(series_value(daily, "precipitation_sum", index), 0),
            "wind": number(series_value(daily, "wind_speed_10m_max", index), 0),
            "gust": number(series_value(daily, "wind_gusts_10m_max", index), 0),
            "windDirection": number(series_value(daily, "wind_direction_10m_dominant", index), 0),
        })
    return rows


def normalize_air(payload):
    current = payload.get("current") if isinstance(payload, dict) else None
    if not isinstance(current, dict):
        return None
    aqi = number(current.get("us_aqi"))
    if aqi is None:
        return None
    pollen = {}
    for name in POLLEN_TYPES:
        value = number(current.get(name + "_pollen"))
        if value is not None:
            pollen[name] = value
    hourly = payload.get("hourly") if isinstance(payload.get("hourly"), dict) else {}
    trend = [number(value) for value in (hourly.get("us_aqi") or [])[:12]]
    return {
        "time": text(current.get("time"), 40),
        "usAqi": aqi,
        "europeanAqi": number(current.get("european_aqi")),
        "pm25": number(current.get("pm2_5")),
        "pm10": number(current.get("pm10")),
        "ozone": number(current.get("ozone")),
        "no2": number(current.get("nitrogen_dioxide")),
        "so2": number(current.get("sulphur_dioxide")),
        "co": number(current.get("carbon_monoxide")),
        "dust": number(current.get("dust")),
        "pollen": pollen,
        "hourly": [value for value in trend if value is not None],
    }


def error_view(message="Weather unavailable", location=None):
    return {
        "ok": False,
        "error": text(message, 120) or "Weather unavailable",
        "location": location,
        "current": None,
        "hourly": [],
        "daily": [],
        "stale": False,
        "cached": False,
    }


def cache_key(location):
    requested = selected_location({"location": location}) if location else None
    if requested:
        return "{0:.4f}_{1:.4f}".format(requested["latitude"], requested["longitude"])
    return "approximate"


def cache_path(key):
    safe = "".join(ch if ch.isalnum() or ch in "._-+" else "_" for ch in str(key or "approximate"))
    return CACHE_DIR / (safe + ".json")


def read_cache(key, allow_stale=True, now=None):
    path = cache_path(key)
    try:
        raw = path.read_text(encoding="utf-8")
        envelope = json.loads(raw)
    except (OSError, ValueError, TypeError):
        return None
    if not isinstance(envelope, dict):
        return None
    payload = envelope.get("payload")
    saved_at = number(envelope.get("savedAt"), 0) or 0
    if not isinstance(payload, dict) or payload.get("ok") is not True or not payload.get("current"):
        return None
    stamp = time.time() if now is None else float(now)
    age = max(0, stamp - saved_at)
    stale = age > CACHE_TTL_SECONDS
    if stale and not allow_stale:
        return None
    result = dict(payload)
    result["stale"] = stale
    result["cached"] = True
    result["cacheAge"] = int(age)
    return result


def write_cache(key, payload, now=None):
    if not isinstance(payload, dict) or payload.get("ok") is not True or not payload.get("current"):
        return False
    path = cache_path(key)
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        body = {
            "savedAt": time.time() if now is None else float(now),
            "key": key,
            "payload": {
                "ok": True,
                "location": payload.get("location"),
                "current": payload.get("current"),
                "hourly": payload.get("hourly") or [],
                "daily": payload.get("daily") or [],
                "air": payload.get("air"),
                "units": payload.get("units") or {
                    "temperature": "celsius",
                    "wind": "kmh",
                    "precipitation": "mm",
                },
            },
        }
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(body, separators=(",", ":")), encoding="utf-8")
        tmp.replace(path)
        return True
    except OSError:
        return False


def fetch_air(coordinates, timezone, fetch):
    try:
        return normalize_air(fetch(air_quality_url(coordinates[0], coordinates[1], timezone)))
    except Exception:
        return None


def collect(location, fetch=fetch_json, cache_mode=None, air=True):
    """cache_mode: None | 'cache-only' | 'cache-first'

    cache-only: return disk cache (fresh or stale) or an error; never network.
    cache-first: return any disk cache immediately; otherwise live-fetch.
    None: live-fetch, write cache; on failure fall back to stale cache.

    air: also fetch air quality, alongside the forecast. A failed air request
    keeps the last cached reading and never fails the forecast.
    """
    requested = selected_location({"location": location})
    if not requested and location:
        return error_view("Choose a valid location", location)

    # Known selected coords → cache key before any IP lookup.
    if requested:
        key = cache_key(requested)
    else:
        key = "approximate"

    if cache_mode in ("cache-only", "cache-first"):
        cached = read_cache(key, allow_stale=True)
        if cached:
            return cached
        if cache_mode == "cache-only":
            return error_view("No cached forecast", requested)

    if not requested:
        try:
            requested = approximate_location(fetch)
            key = cache_key(requested)
            # Approximate resolves to real coords; prefer that city's cache if present.
            if cache_mode == "cache-first":
                cached = read_cache(key, allow_stale=True)
                if cached:
                    return cached
        except Exception:
            cached = read_cache("approximate", allow_stale=True)
            if cached:
                return cached
            return error_view("Location and forecast are unavailable")

    coordinates = valid_coordinates(requested.get("latitude"), requested.get("longitude"))
    if not coordinates:
        return error_view("Choose a valid location", requested)

    timezone = requested.get("timezone", "")
    with ThreadPoolExecutor(max_workers=2) as pool:
        pending_air = pool.submit(fetch_air, coordinates, timezone, fetch) if air else None
        try:
            payload = fetch(forecast_url(coordinates[0], coordinates[1], timezone))
        except Exception:
            payload = None
        air_now = pending_air.result() if pending_air else None
    if payload is None:
        cached = read_cache(key, allow_stale=True)
        if cached:
            return cached
        return error_view("Forecast is temporarily unavailable", requested)

    current = normalize_current(payload.get("current") if isinstance(payload, dict) else None)
    if not current:
        cached = read_cache(key, allow_stale=True)
        if cached:
            return cached
        return error_view("Forecast data was incomplete", requested)

    result = {
        "ok": True,
        "location": normalized_location(payload, requested),
        "current": current,
        "hourly": normalize_hourly(payload, current.get("time", "")),
        "daily": normalize_daily(payload),
        "air": air_now,
        "units": {
            "temperature": "celsius",
            "wind": "kmh",
            "precipitation": "mm",
        },
        "stale": False,
        "cached": False,
    }
    if air and not air_now:
        previous = read_cache(key, allow_stale=True)
        result["air"] = previous.get("air") if previous else None
    write_cache(key, result)
    # Also mirror approximate IP lookups under the approximate key for next cold start.
    if requested.get("source") == "approximate":
        write_cache("approximate", result)
    return result


def fetch_bytes(url, timeout=10, limit=1_000_000):
    request = Request(url, headers={"User-Agent": USER_AGENT})
    with urlopen(request, timeout=timeout) as response:
        payload = response.read(limit + 1)
    if len(payload) > limit:
        raise ValueError("Tile is too large")
    return payload


def tile_position(latitude, longitude, zoom):
    """Fractional Web Mercator tile coordinates of a point."""
    lat = max(-85.0511, min(85.0511, float(latitude)))
    count = 2 ** zoom
    x = (float(longitude) + 180.0) / 360.0 * count
    rad = math.radians(lat)
    y = (1 - math.log(math.tan(rad) + 1 / math.cos(rad)) / math.pi) / 2 * count
    return x, y


def tile_grid(x, y, zoom, size=RADAR_GRID):
    """The size x size tiles around (x, y), row by row.

    Returns the grid's top-left tile and a (column, row) per cell, wrapped
    across the antimeridian. A cell above or below the map is None.
    """
    count = 2 ** zoom
    left = int(math.floor(x)) - size // 2
    top = int(math.floor(y)) - size // 2
    cells = []
    for row in range(size):
        for column in range(size):
            tile_y = top + row
            cells.append(((left + column) % count, tile_y) if 0 <= tile_y < count else None)
    return left, top, cells


def radar_frames(payload, count=RADAR_FRAMES):
    """The newest past radar frames as (host, [{time, id, path}]), oldest first."""
    if not isinstance(payload, dict):
        return "", []
    host = text(payload.get("host"), 200)
    radar = payload.get("radar")
    past = radar.get("past") if isinstance(radar, dict) else None
    if not host.startswith("https://") or not isinstance(past, list):
        return "", []
    frames = []
    for frame in past:
        if not isinstance(frame, dict):
            continue
        stamp = number(frame.get("time"))
        path = text(frame.get("path"), 200)
        if stamp is None or not re.fullmatch(r"(/[A-Za-z0-9_-]+)+", path):
            continue
        frames.append({"time": int(stamp), "id": path.rsplit("/", 1)[-1], "path": path})
    frames.sort(key=lambda frame: frame["time"])
    return host, frames[-count:]


def save_tile(path, url, fetch=fetch_bytes):
    """Download url to path once. Returns the path, or "" when it failed."""
    try:
        if path.stat().st_size > 0:
            return str(path)
    except OSError:
        pass
    try:
        body = fetch(url)
        if not body:
            return ""
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_name("{0}.{1}.tmp".format(path.name, os.getpid()))
        tmp.write_bytes(body)
        tmp.replace(path)
        return str(path)
    except Exception:
        return ""


def radar_manifest_path(key):
    return CACHE_DIR / "radar" / "manifests" / (key + ".json")


def read_radar_manifest(key, now=None):
    """A recent radar answer whose tiles are all still on disk, or None."""
    try:
        envelope = json.loads(radar_manifest_path(key).read_text(encoding="utf-8"))
    except (OSError, ValueError, TypeError):
        return None
    if not isinstance(envelope, dict) or not isinstance(envelope.get("payload"), dict):
        return None
    stamp = time.time() if now is None else float(now)
    if stamp - (number(envelope.get("savedAt"), 0) or 0) > RADAR_TTL_SECONDS:
        return None
    payload = envelope["payload"]
    paths = list(payload.get("base") or []) + list(payload.get("labels") or [])
    for frame in payload.get("frames") or []:
        paths.extend(frame.get("tiles") or [])
    if any(path and not os.path.exists(path) for path in paths):
        return None
    return payload


def frame_is_dry(paths):
    """True when every tile of a frame is on disk and empty."""
    sizes = []
    for path in paths:
        if not path:
            continue
        try:
            sizes.append(os.path.getsize(path))
        except OSError:
            return False
    return bool(sizes) and all(size < EMPTY_TILE_BYTES for size in sizes)


def prune_radar_frames(keep, now=None):
    """Drop frame folders older than RADAR_KEEP_SECONDS that are not in keep."""
    root = CACHE_DIR / "radar" / "frames"
    stamp = time.time() if now is None else float(now)
    try:
        folders = list(root.iterdir())
    except OSError:
        return
    for folder in folders:
        try:
            if folder.name in keep or stamp - folder.stat().st_mtime < RADAR_KEEP_SECONDS:
                continue
            for child in folder.rglob("*"):
                if child.is_file():
                    child.unlink()
            for child in sorted(folder.rglob("*"), reverse=True):
                child.rmdir()
            folder.rmdir()
        except OSError:
            continue


def collect_radar(location, style="dark", zoom=RADAR_ZOOM, fetch=fetch_json, fetch_tile=fetch_bytes, now=None):
    """Radar frames and map tiles around a location, as local file paths.

    The tiles are a RADAR_GRID square around the location's tile. `offset` is
    the location, in tiles, from the grid's top-left corner. Each list of
    paths is row by row; "" marks a tile that could not be fetched.
    """
    requested = selected_location({"location": location})
    if not requested:
        return {"ok": False, "error": "Radar needs a location"}
    style = style if style in MAP_LAYERS else "dark"
    zoom = max(2, min(RADAR_MAX_ZOOM, int(number(zoom, RADAR_ZOOM))))
    key = "{0:.3f}_{1:.3f}_{2}_{3}".format(requested["latitude"], requested["longitude"], zoom, style)
    cached = read_radar_manifest(key, now)
    if cached:
        return cached

    x, y = tile_position(requested["latitude"], requested["longitude"], zoom)
    left, top, cells = tile_grid(x, y, zoom)
    try:
        host, frames = radar_frames(fetch(RAINVIEWER_ENDPOINT))
    except Exception:
        host, frames = "", []

    base_layer, label_layer = MAP_LAYERS[style]
    map_dir = CACHE_DIR / "radar" / "map" / style / str(zoom)
    frame_dir = CACHE_DIR / "radar" / "frames"
    jobs = []
    for cell in cells:
        if cell is None:
            jobs.extend([None, None])
            continue
        tile_x, tile_y = cell
        jobs.append((map_dir / "{0}_{1}.jpg".format(tile_x, tile_y),
                     MAP_ENDPOINT.format(layer=base_layer, z=zoom, x=tile_x, y=tile_y)))
        jobs.append((map_dir / "{0}_{1}_labels.png".format(tile_x, tile_y),
                     MAP_ENDPOINT.format(layer=label_layer, z=zoom, x=tile_x, y=tile_y)))
    for frame in frames:
        for cell in cells:
            if cell is None:
                jobs.append(None)
                continue
            tile_x, tile_y = cell
            jobs.append((frame_dir / frame["id"] / str(zoom) / "{0}_{1}.png".format(tile_x, tile_y),
                         "{0}{1}/{2}/{3}/{4}/{5}/2/1_1.png".format(host, frame["path"], TILE_SIZE, zoom, tile_x, tile_y)))

    def run(job):
        return save_tile(job[0], job[1], fetch_tile) if job else ""

    with ThreadPoolExecutor(max_workers=8) as pool:
        paths = list(pool.map(run, jobs))

    count = len(cells)
    result = {
        "ok": bool(frames),
        "style": style,
        "zoom": zoom,
        "tileSize": TILE_SIZE,
        "columns": RADAR_GRID,
        "offset": {"x": x - left, "y": y - top},
        "base": paths[0:count * 2:2],
        "labels": paths[1:count * 2:2],
        "frames": [
            {"time": frame["time"], "tiles": paths[count * 2 + index * count:count * 2 + (index + 1) * count]}
            for index, frame in enumerate(frames)
        ],
    }
    result["dry"] = bool(result["frames"]) and frame_is_dry(result["frames"][-1]["tiles"])
    if not frames:
        result["error"] = "Radar is unavailable"
        return result
    prune_radar_frames({frame["id"] for frame in frames}, now)
    try:
        manifest = radar_manifest_path(key)
        manifest.parent.mkdir(parents=True, exist_ok=True)
        tmp = manifest.with_name("{0}.{1}.tmp".format(manifest.name, os.getpid()))
        body = {"savedAt": time.time() if now is None else float(now), "payload": result}
        tmp.write_text(json.dumps(body, separators=(",", ":")), encoding="utf-8")
        tmp.replace(manifest)
    except OSError:
        pass
    return result


def search_locations(query, fetch=fetch_json):
    cleaned = text(query, 120)
    if len(cleaned) < 2:
        return []
    try:
        payload = fetch(geocoding_url(cleaned))
    except Exception:
        return []
    results = payload.get("results") if isinstance(payload, dict) else None
    if not isinstance(results, list):
        return []
    rows = []
    seen = set()
    for result in results:
        if not isinstance(result, dict):
            continue
        coordinates = valid_coordinates(result.get("latitude"), result.get("longitude"))
        name = text(result.get("name"), 80)
        if not coordinates or not name:
            continue
        key = (round(coordinates[0], 4), round(coordinates[1], 4), name.casefold())
        if key in seen:
            continue
        seen.add(key)
        admin1 = text(result.get("admin1"), 80)
        country = text(result.get("country"), 80)
        rows.append({
            "name": name,
            "detail": " · ".join(part for part in (admin1, country) if part),
            "latitude": coordinates[0],
            "longitude": coordinates[1],
            "timezone": text(result.get("timezone"), 80),
            "admin1": admin1,
            "country": country,
            "countryCode": text(result.get("country_code"), 4).upper(),
        })
        if len(rows) == 10:
            break
    return rows


def parse_location_args(args):
    location = {}
    for field in ("latitude", "longitude"):
        flag = "--" + field
        if flag in args:
            index = args.index(flag)
            location[field] = args[index + 1] if index + 1 < len(args) else ""
    if "--label" in args:
        index = args.index("--label")
        location["name"] = args[index + 1] if index + 1 < len(args) else ""
    if "--timezone" in args:
        index = args.index("--timezone")
        location["timezone"] = args[index + 1] if index + 1 < len(args) else ""
    return location


def flag_value(args, flag, default=""):
    if flag not in args:
        return default
    index = args.index(flag)
    return args[index + 1] if index + 1 < len(args) else default


def cache_mode_from_args(args):
    if "--cache-only" in args:
        return "cache-only"
    if "--cache-first" in args:
        return "cache-first"
    return None


def main(argv):
    args = argv[1:]
    if "--search" in args:
        index = args.index("--search")
        query = args[index + 1] if index + 1 < len(args) else ""
        json.dump(search_locations(query), sys.stdout)
        sys.stdout.write("\n")
        return 0
    location = parse_location_args(args)
    if "--radar" in args:
        result = collect_radar(location, flag_value(args, "--style", "dark"), flag_value(args, "--zoom", RADAR_ZOOM))
        json.dump(result, sys.stdout)
        sys.stdout.write("\n")
        return 0
    mode = cache_mode_from_args(args)
    air = "--no-air" not in args
    if "latitude" in location and "longitude" in location:
        result = collect(location, cache_mode=mode, air=air)
    else:
        result = collect({}, cache_mode=mode, air=air)
    json.dump(result, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
