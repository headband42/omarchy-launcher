#!/usr/bin/env python3
"""X (Twitter) tile model. Stdlib only. Network lives behind fetch helpers.

Cookie-less path: guest activate + trends/place.json (public web bearer).
That surfaces Explore-adjacent trending headlines, not the signed-in AI
"Today's News" article feed or notification badges.

Optional cookies file (Netscape or JSON with auth_token + ct0) unlocks
Today's News and the notification badge. Secrets stay in user config.
"""

from __future__ import annotations

import json
import os
import re
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen

# Bearer token embedded in X's web client. Same value many logged-out tools use.
WEB_BEARER = (
    "AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs"
    "%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"
)
USER_AGENT = "ande-launcher-x/0.1 (+https://github.com/headband42/omarchy-launcher; tile widget)"
GUEST_ACTIVATE = "https://api.twitter.com/1.1/guest/activate.json"
TRENDS_PLACE = "https://api.twitter.com/1.1/trends/place.json"
TRENDS_AVAILABLE = "https://api.twitter.com/1.1/trends/available.json"
BADGE_COUNT = "https://twitter.com/i/api/2/badge_count/badge_count.json?supports_ntab_urt=1"
# AI home-news GraphQL (Explore / Today's News). Needs a signed-in session.
NEWS_QUERY_ID = "gTItUBXHQzDYz5zGcfHOSw"
NEWS_QUERY_NAME = "useHomeNewsArticlesQuery"
NEWS_GRAPHQL = (
    "https://twitter.com/i/api/graphql/"
    + NEWS_QUERY_ID
    + "/"
    + NEWS_QUERY_NAME
)

CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME") or (Path.home() / ".cache")) / "ande.launcher" / "x"
CACHE_TTL_SECONDS = 5 * 60
POLL_MS = 5 * 60 * 1000
MAX_HEADLINES = 10
DEFAULT_WOEID = 1
# Written by widgets/x/export-browser-cookies.py (user-run). Never commit secrets.
DEFAULT_COOKIES_PATH = (
    Path(os.environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config"))
    / "ande.launcher"
    / "x-cookies.json"
)

# Small built-in place list so settings work offline. Full catalog comes from
# trends/available.json when the network is up.
PLACE_PRESETS = (
    {"woeid": 1, "name": "Worldwide", "countryCode": ""},
    {"woeid": 23424977, "name": "United States", "countryCode": "US"},
    {"woeid": 23424975, "name": "United Kingdom", "countryCode": "GB"},
    {"woeid": 23424775, "name": "Canada", "countryCode": "CA"},
    {"woeid": 23424748, "name": "Australia", "countryCode": "AU"},
    {"woeid": 2459115, "name": "New York", "countryCode": "US"},
    {"woeid": 2442047, "name": "Los Angeles", "countryCode": "US"},
    {"woeid": 2379574, "name": "Chicago", "countryCode": "US"},
    {"woeid": 2487956, "name": "San Francisco", "countryCode": "US"},
    {"woeid": 2358820, "name": "Baltimore", "countryCode": "US"},
    {"woeid": 44418, "name": "London", "countryCode": "GB"},
    {"woeid": 1105779, "name": "Sydney", "countryCode": "AU"},
    {"woeid": 4118, "name": "Toronto", "countryCode": "CA"},
)


def text(value, limit=160):
    result = str(value or "").strip()
    return result[:limit]


def number(value, default=None):
    if isinstance(value, bool):
        return default
    try:
        result = float(value)
    except (TypeError, ValueError):
        return default
    if result != result:  # NaN
        return default
    return result


def woeid_of(value, default=DEFAULT_WOEID):
    raw = number(value, None)
    if raw is None:
        return int(default)
    if isinstance(value, str) and not value.strip().isdigit():
        return int(default)
    n = int(raw)
    return n if n > 0 else int(default)


def max_headlines_of(settings):
    n = number((settings or {}).get("maxHeadlines"), 8)
    if n is None:
        return 8
    return max(3, min(MAX_HEADLINES, int(n)))


def cookies_path_of(settings):
    """Return an expanded cookies path.

    An explicit settings.cookiesPath wins. Otherwise use the exporter default
    (~/.config/ande.launcher/x-cookies.json) so a user who ran the helper does
    not need to paste the path into Settings. Missing files still yield no
    session (load_session_cookies returns None).
    """
    raw = text((settings or {}).get("cookiesPath"), 512)
    if raw:
        return str(Path(raw).expanduser())
    return str(DEFAULT_COOKIES_PATH)


def place_from_settings(settings):
    settings = settings if isinstance(settings, dict) else {}
    woeid = woeid_of(settings.get("woeid"), DEFAULT_WOEID)
    name = text(settings.get("placeName"), 80)
    if not name:
        for row in PLACE_PRESETS:
            if row["woeid"] == woeid:
                name = row["name"]
                break
    if not name:
        name = "WOEID " + str(woeid)
    return {"woeid": woeid, "name": name, "countryCode": text(settings.get("countryCode"), 4)}


def settings_normalized(settings):
    place = place_from_settings(settings)
    return {
        "woeid": place["woeid"],
        "placeName": place["name"],
        "countryCode": place.get("countryCode") or "",
        "maxHeadlines": max_headlines_of(settings),
        "cookiesPath": cookies_path_of(settings),
    }


def error_view(message="X unavailable", place=None, notifications=None):
    return {
        "ok": False,
        "error": text(message, 120) or "X unavailable",
        "source": "",
        "sourceLabel": "X",
        "place": place,
        "headlines": [],
        "notifications": notifications,
        "stale": False,
        "cached": False,
        "cacheAge": 0,
        "fetchedAt": 0,
        "pollMs": POLL_MS,
        "newsBlocked": True,
        "notificationsBlocked": notifications is None,
    }


def fetch_bytes(url, headers=None, data=None, method=None, timeout=15):
    request_headers = {
        "Accept": "application/json",
        "User-Agent": USER_AGENT,
    }
    if headers:
        request_headers.update(headers)
    request = Request(url, data=data, headers=request_headers, method=method)
    with urlopen(request, timeout=timeout) as response:
        payload = response.read(2_000_001)
    if len(payload) > 2_000_000:
        raise ValueError("X response is too large")
    return payload


def fetch_json(url, headers=None, data=None, method=None, timeout=15):
    payload = fetch_bytes(url, headers=headers, data=data, method=method, timeout=timeout)
    result = json.loads(payload.decode("utf-8"))
    return result


def guest_headers(guest_token):
    token = text(guest_token, 80)
    return {
        "Authorization": "Bearer " + WEB_BEARER,
        "x-guest-token": token,
        "x-twitter-active-user": "yes",
        "x-twitter-client-language": "en",
        "Cookie": "guest_id=v1%3A" + token,
    }


def activate_guest(fetch=fetch_json):
    payload = fetch(
        GUEST_ACTIVATE,
        headers={"Authorization": "Bearer " + WEB_BEARER},
        data=b"",
        method="POST",
    )
    if not isinstance(payload, dict):
        raise ValueError("Guest activate failed")
    token = text(payload.get("guest_token"), 80)
    if not token:
        raise ValueError("Guest token missing")
    return token


def headline_url(name, url=""):
    raw = text(url, 300)
    if raw.startswith("http://twitter.com/") or raw.startswith("https://twitter.com/"):
        return "https://x.com/" + raw.split("twitter.com/", 1)[1]
    if raw.startswith("http://x.com/") or raw.startswith("https://x.com/"):
        return raw
    query = quote(str(name or ""), safe="")
    return "https://x.com/search?q=" + query if query else "https://x.com/explore"


def normalize_trends(payload, limit=8):
    if not isinstance(payload, list) or not payload:
        return []
    block = payload[0] if isinstance(payload[0], dict) else {}
    rows = block.get("trends")
    if not isinstance(rows, list):
        return []
    out = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        title = text(row.get("name"), 120)
        if not title:
            continue
        volume = number(row.get("tweet_volume"), None)
        out.append({
            "title": title,
            "url": headline_url(title, row.get("url")),
            "volume": int(volume) if volume is not None else None,
            "category": "",
            "kind": "trend",
        })
        if len(out) >= limit:
            break
    return out


def volume_label(volume):
    n = number(volume, None)
    if n is None:
        return ""
    n = int(n)
    if n >= 1_000_000:
        return "{0:.1f}M".format(n / 1_000_000).replace(".0M", "M")
    if n >= 1_000:
        return "{0:.1f}K".format(n / 1_000).replace(".0K", "K")
    return str(n)


def parse_netscape_cookies(raw):
    """Return {name: value} from a Netscape cookie export or simple KEY=VAL lines."""
    cookies = {}
    for line in str(raw or "").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "\t" in line:
            parts = line.split("\t")
            if len(parts) >= 7:
                cookies[parts[5]] = parts[6]
            continue
        if "=" in line and "\t" not in line:
            key, _, value = line.partition("=")
            key = key.strip()
            if key in ("auth_token", "ct0", "kdt", "twid"):
                cookies[key] = value.strip()
    return cookies


def load_session_cookies(path):
    path = Path(str(path or "")).expanduser()
    if not path.is_file():
        return None
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError:
        return None
    stripped = raw.strip()
    if stripped.startswith("{"):
        try:
            data = json.loads(stripped)
        except ValueError:
            data = None
        if isinstance(data, dict):
            auth = text(data.get("auth_token"), 200)
            ct0 = text(data.get("ct0"), 200)
            if auth and ct0:
                return {"auth_token": auth, "ct0": ct0}
    cookies = parse_netscape_cookies(raw)
    auth = text(cookies.get("auth_token"), 200)
    ct0 = text(cookies.get("ct0"), 200)
    if auth and ct0:
        return {"auth_token": auth, "ct0": ct0}
    return None


def session_headers(cookies):
    auth = text(cookies.get("auth_token"), 200)
    ct0 = text(cookies.get("ct0"), 200)
    return {
        "Authorization": "Bearer " + WEB_BEARER,
        "x-csrf-token": ct0,
        "x-twitter-active-user": "yes",
        "x-twitter-auth-type": "OAuth2Session",
        "x-twitter-client-language": "en",
        "Cookie": "auth_token=" + auth + "; ct0=" + ct0,
    }


def fetch_badge_count(cookies, fetch=fetch_json):
    if not cookies:
        return {
            "ok": False,
            "count": None,
            "reason": "Signed-in cookies required for notification count",
        }
    try:
        payload = fetch(BADGE_COUNT, headers=session_headers(cookies))
    except (HTTPError, URLError, TimeoutError, ValueError, TypeError) as exc:
        return {"ok": False, "count": None, "reason": text(exc, 120) or "Badge request failed"}
    if not isinstance(payload, dict):
        return {"ok": False, "count": None, "reason": "Badge response invalid"}
    # Shape varies; accept a few known keys.
    for key in ("ntab_unread_count", "total_unread_count", "badge_count"):
        if key in payload:
            count = number(payload.get(key), None)
            if count is not None:
                return {"ok": True, "count": int(count), "reason": ""}
    # Nested urt-style
    for key, value in payload.items():
        count = number(value, None)
        if count is not None and "count" in key.lower():
            return {"ok": True, "count": int(count), "reason": ""}
    return {"ok": False, "count": None, "reason": "Badge fields missing", "rawKeys": sorted(payload.keys())[:12]}


def walk_news_titles(node, out, limit):
    if len(out) >= limit:
        return
    if isinstance(node, dict):
        typename = text(node.get("__typename"), 40).lower()
        titled = text(node.get("title") or node.get("headline"), 160)
        # AiTrend stories put the headline on deepsearch_news_articles, which
        # has a title plus sections or a summary and no rest_id.
        story = bool(titled) and (
            node.get("sections") is not None or node.get("summary") or node.get("sources") is not None
        )
        article = bool(node.get("rest_id")) or "article" in typename
        title = titled if (story or article) else ""
        if not title and article:
            title = text(node.get("name"), 160)
        if title and not any(row["title"] == title for row in out):
            url = text(node.get("url") or node.get("share_url"), 300)
            story_id = text(node.get("id"), 40)
            if not url and story and story_id.isdigit():
                url = "https://x.com/i/trending/" + story_id
            elif not url and node.get("rest_id"):
                url = "https://x.com/i/news/" + text(node.get("rest_id"), 40)
            out.append({
                "title": title,
                "url": url or "https://x.com/explore/tabs/news",
                "volume": None,
                "category": text(node.get("category") or node.get("caption"), 80),
                "kind": "news",
            })
        for value in node.values():
            walk_news_titles(value, out, limit)
    elif isinstance(node, list):
        for item in node:
            walk_news_titles(item, out, limit)


def fetch_home_news(cookies, limit=8, fetch=fetch_json):
    """Best-effort Today's News via GraphQL. Usually needs a real session."""
    if not cookies:
        return None, "Signed-in cookies required for Today's News articles"
    features = {
        "responsive_web_graphql_exclude_directive_enabled": True,
        "verified_phone_label_enabled": False,
        "responsive_web_graphql_skip_user_profile_image_extensions_enabled": False,
        "responsive_web_graphql_timeline_navigation_enabled": True,
    }
    params = urlencode({
        "variables": json.dumps({"limit": int(limit)}),
        "features": json.dumps(features),
    })
    url = NEWS_GRAPHQL + "?" + params
    try:
        payload = fetch(url, headers=session_headers(cookies))
    except (HTTPError, URLError, TimeoutError, ValueError, TypeError) as exc:
        return None, text(exc, 120) or "News GraphQL failed"
    headlines = []
    walk_news_titles(payload, headlines, limit)
    if not headlines:
        return None, "News GraphQL returned no headlines"
    return headlines, ""


def fetch_trends(woeid, limit=8, fetch=fetch_json):
    guest = activate_guest(fetch=fetch)
    headers = guest_headers(guest)
    url = TRENDS_PLACE + "?" + urlencode({"id": int(woeid)})
    payload = fetch(url, headers=headers)
    return normalize_trends(payload, limit=limit)


def available_places(fetch=fetch_json):
    guest = activate_guest(fetch=fetch)
    headers = guest_headers(guest)
    payload = fetch(TRENDS_AVAILABLE, headers=headers)
    if not isinstance(payload, list):
        return list(PLACE_PRESETS)
    out = []
    seen = set()
    for row in payload:
        if not isinstance(row, dict):
            continue
        woeid = woeid_of(row.get("woeid"), 0)
        name = text(row.get("name"), 80)
        if not woeid or not name or woeid in seen:
            continue
        seen.add(woeid)
        out.append({
            "woeid": woeid,
            "name": name,
            "countryCode": text(row.get("countryCode"), 4),
            "country": text(row.get("country"), 80),
            "placeType": text((row.get("placeType") or {}).get("name"), 40),
        })
    # Worldwide has no country code. Keep it first, not after every country.
    out.sort(key=lambda row: (
        row["woeid"] != DEFAULT_WOEID,
        row.get("countryCode") or "ZZZ",
        row["name"].lower(),
    ))
    return out or list(PLACE_PRESETS)


def cache_key(place):
    return "woeid_" + str(woeid_of((place or {}).get("woeid"), DEFAULT_WOEID))


def cache_path(key):
    safe = "".join(ch if ch.isalnum() or ch in "._-+" else "_" for ch in str(key or "woeid_1"))
    return CACHE_DIR / (safe + ".json")


def read_cache(key, allow_stale=True, now=None):
    path = cache_path(key)
    try:
        envelope = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError, TypeError):
        return None
    if not isinstance(envelope, dict):
        return None
    payload = envelope.get("payload")
    saved_at = number(envelope.get("savedAt"), 0) or 0
    if not isinstance(payload, dict) or payload.get("ok") is not True:
        return None
    if not payload.get("headlines"):
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
    result["cachedAt"] = saved_at
    return result


def write_cache(key, payload, now=None):
    if not isinstance(payload, dict) or payload.get("ok") is not True or not payload.get("headlines"):
        return False
    path = cache_path(key)
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        body = {
            "savedAt": time.time() if now is None else float(now),
            "key": key,
            "payload": {
                "ok": True,
                "source": payload.get("source"),
                "sourceLabel": payload.get("sourceLabel"),
                "place": payload.get("place"),
                "headlines": payload.get("headlines") or [],
                "notifications": payload.get("notifications"),
                "newsBlocked": bool(payload.get("newsBlocked")),
                "notificationsBlocked": bool(payload.get("notificationsBlocked")),
                "signedIn": bool(payload.get("signedIn")),
                "fetchedAt": payload.get("fetchedAt") or 0,
                "pollMs": payload.get("pollMs") or POLL_MS,
            },
        }
        path.write_text(json.dumps(body), encoding="utf-8")
        return True
    except OSError:
        return False


def cookies_mtime(path):
    try:
        return float(Path(path).stat().st_mtime)
    except OSError:
        return 0.0


def collect(settings=None, cache_mode="live", fetch=fetch_json, now=None):
    options = settings_normalized(settings)
    place = place_from_settings(options)
    key = cache_key(place)
    stamp = time.time() if now is None else float(now)
    cookies = load_session_cookies(options["cookiesPath"])

    if cache_mode == "cache-only":
        cached = read_cache(key, allow_stale=True, now=stamp)
        return cached or error_view("No cached headlines", place=place)

    if cache_mode == "cache-first":
        cached = read_cache(key, allow_stale=False, now=stamp)
        # A just-imported session is newer than the guest cache. Read it now.
        if cached and cookies_mtime(options["cookiesPath"]) <= float(cached.get("cachedAt") or 0):
            return cached

    notifications = None
    notifications_blocked = True
    if cookies:
        notifications = fetch_badge_count(cookies, fetch=fetch)
        notifications_blocked = not bool(notifications and notifications.get("ok"))
    else:
        notifications = {
            "ok": False,
            "count": None,
            "reason": "Sign in from the tile settings",
        }

    news_blocked = True
    headlines = []
    source = "trends"
    source_label = "Trending"
    news_error = ""

    if cookies:
        news_rows, news_error = fetch_home_news(cookies, limit=options["maxHeadlines"], fetch=fetch)
        if news_rows:
            headlines = news_rows
            source = "news"
            source_label = "Today's News"
            news_blocked = False

    try:
        if not headlines:
            headlines = fetch_trends(place["woeid"], limit=options["maxHeadlines"], fetch=fetch)
            source = "trends"
            source_label = "Trending"
            news_blocked = True
    except (HTTPError, URLError, TimeoutError, ValueError, TypeError, json.JSONDecodeError) as exc:
        cached = read_cache(key, allow_stale=True, now=stamp)
        if cached:
            cached = dict(cached)
            cached["stale"] = True
            cached["error"] = text(exc, 120) or "X fetch failed"
            if notifications is not None:
                cached["notifications"] = notifications
            return cached
        return error_view(text(exc, 120) or "X fetch failed", place=place, notifications=notifications)

    if not headlines:
        cached = read_cache(key, allow_stale=True, now=stamp)
        if cached:
            return cached
        reason = news_error or "No headlines"
        return error_view(reason, place=place, notifications=notifications)

    result = {
        "ok": True,
        "error": "",
        "source": source,
        "sourceLabel": source_label,
        "place": place,
        "headlines": headlines,
        "notifications": notifications,
        "stale": False,
        "cached": False,
        "cacheAge": 0,
        "fetchedAt": int(stamp),
        "pollMs": POLL_MS,
        "newsBlocked": news_blocked,
        "notificationsBlocked": notifications_blocked,
        "signedIn": bool(cookies),
        "newsError": text(news_error, 160) if news_blocked and news_error else "",
    }
    write_cache(key, result, now=stamp)
    return result


def cache_mode_from_args(args):
    if "--cache-only" in args:
        return "cache-only"
    if "--cache-first" in args:
        return "cache-first"
    return "live"


def places_payload(fetch=fetch_json):
    try:
        rows = available_places(fetch=fetch)
        return {"ok": True, "places": rows, "presets": list(PLACE_PRESETS)}
    except (HTTPError, URLError, TimeoutError, ValueError, TypeError, json.JSONDecodeError) as exc:
        return {
            "ok": False,
            "error": text(exc, 120) or "Places unavailable",
            "places": list(PLACE_PRESETS),
            "presets": list(PLACE_PRESETS),
        }
