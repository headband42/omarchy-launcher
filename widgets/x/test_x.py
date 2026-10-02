#!/usr/bin/env python3
import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

import sample
import x as xmod


TRENDS = [{
    "trends": [
        {"name": "#AEWAllOut", "url": "http://twitter.com/search?q=%23AEWAllOut", "tweet_volume": 120000},
        {"name": "Lincoln Riley", "url": "http://twitter.com/search?q=%22Lincoln+Riley%22", "tweet_volume": None},
        {"name": "Oregon", "url": "http://twitter.com/search?q=Oregon", "tweet_volume": 5400},
    ],
    "as_of": "2026-09-26T00:00:00Z",
    "locations": [{"name": "Worldwide", "woeid": 1}],
}]


class FakeFetch:
    def __init__(self):
        self.calls = []

    def __call__(self, url, headers=None, data=None, method=None, timeout=15):
        self.calls.append({"url": url, "method": method, "headers": headers or {}, "data": data})
        if "guest/activate" in url:
            return {"guest_token": "guest-token-1"}
        if "trends/place.json" in url:
            return TRENDS
        if "trends/available.json" in url:
            return [
                {"name": "Worldwide", "woeid": 1, "countryCode": None, "country": "", "placeType": {"name": "Supername"}},
                {"name": "United States", "woeid": 23424977, "countryCode": "US", "country": "United States", "placeType": {"name": "Country"}},
            ]
        if "badge_count" in url:
            return {"ntab_unread_count": 3}
        if "useHomeNewsArticlesQuery" in url:
            raise xmod.HTTPError(url, 404, "Not Found", hdrs=None, fp=io.BytesIO(b""))
        raise AssertionError("unexpected url " + url)


class XWidgetTest(unittest.TestCase):
    def setUp(self):
        self._cache = tempfile.TemporaryDirectory()
        self._cache_path = Path(self._cache.name)
        self._cache_patch = patch.object(xmod, "CACHE_DIR", self._cache_path)
        self._cache_patch.start()
        self.fetch = FakeFetch()

    def tearDown(self):
        self._cache_patch.stop()
        self._cache.cleanup()

    def test_normalizes_trends_and_rewrites_urls(self):
        rows = xmod.normalize_trends(TRENDS, limit=2)
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]["title"], "#AEWAllOut")
        self.assertTrue(rows[0]["url"].startswith("https://x.com/search"))
        self.assertEqual(rows[0]["volume"], 120000)

    def test_collect_guest_trends(self):
        payload = xmod.collect({"woeid": 1, "maxHeadlines": 5}, fetch=self.fetch, now=1_000_000)
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["source"], "trends")
        self.assertEqual(payload["sourceLabel"], "Trending")
        self.assertEqual(len(payload["headlines"]), 3)
        self.assertTrue(payload["newsBlocked"])
        self.assertTrue(payload["notificationsBlocked"])
        self.assertIsNone(payload["notifications"]["count"])
        cached = xmod.read_cache("woeid_1", allow_stale=False, now=1_000_030)
        self.assertTrue(cached["ok"])
        self.assertEqual(cached["headlines"][0]["title"], "#AEWAllOut")

    def test_cache_first_skips_network_when_fresh(self):
        xmod.collect({"woeid": 1}, fetch=self.fetch, now=1_000_000)
        calls = len(self.fetch.calls)
        again = xmod.collect({"woeid": 1}, cache_mode="cache-first", fetch=self.fetch, now=1_000_030)
        self.assertEqual(len(self.fetch.calls), calls)
        self.assertTrue(again["cached"])
        self.assertFalse(again["stale"])

    def test_network_failure_falls_back_to_stale_cache(self):
        xmod.collect({"woeid": 1}, fetch=self.fetch, now=1_000_000)

        def boom(url, headers=None, data=None, method=None, timeout=15):
            raise xmod.URLError("down")

        payload = xmod.collect({"woeid": 1}, fetch=boom, now=1_000_000 + 10_000)
        self.assertTrue(payload["ok"])
        self.assertTrue(payload["stale"])
        self.assertTrue(payload["headlines"])

    def test_notifications_from_cookies_file(self):
        cookies = self._cache_path / "cookies.json"
        cookies.write_text(json.dumps({"auth_token": "tok", "ct0": "csrf"}), encoding="utf-8")
        payload = xmod.collect(
            {"woeid": 1, "cookiesPath": str(cookies)},
            fetch=self.fetch,
            now=1_000_000,
        )
        self.assertTrue(payload["notifications"]["ok"])
        self.assertEqual(payload["notifications"]["count"], 3)
        self.assertFalse(payload["notificationsBlocked"])
        # News GraphQL still 404 in FakeFetch → trends fallback
        self.assertEqual(payload["source"], "trends")
        self.assertTrue(payload["newsBlocked"])

    def test_parse_netscape_cookies(self):
        raw = "# Netscape\n.x.com\tTRUE\t/\tTRUE\t0\tauth_token\tabc\n.x.com\tTRUE\t/\tTRUE\t0\tct0\tdef\n"
        cookies = xmod.parse_netscape_cookies(raw)
        self.assertEqual(cookies["auth_token"], "abc")
        self.assertEqual(cookies["ct0"], "def")

    def test_places_payload(self):
        payload = xmod.places_payload(fetch=self.fetch)
        self.assertTrue(payload["ok"])
        self.assertGreaterEqual(len(payload["places"]), 2)

    def test_sample_cli_emits_json(self):
        with patch.object(xmod, "collect", return_value={"ok": True, "headlines": []}):
            buf = io.StringIO()
            with redirect_stdout(buf):
                code = sample.main(["sample.py", "--woeid", "1", "--max", "5"])
            self.assertEqual(code, 0)
            self.assertTrue(json.loads(buf.getvalue())["ok"])

    def test_cookies_path_defaults_to_exporter_file(self):
        options = xmod.settings_normalized({})
        self.assertEqual(options["cookiesPath"], str(xmod.DEFAULT_COOKIES_PATH))
        options = xmod.settings_normalized({"cookiesPath": "~/custom/x.json"})
        self.assertTrue(options["cookiesPath"].endswith("custom/x.json"))

    def test_settings_normalized_clamps_max(self):
        options = xmod.settings_normalized({"woeid": "23424977", "maxHeadlines": 99, "placeName": "United States"})
        self.assertEqual(options["woeid"], 23424977)
        self.assertEqual(options["maxHeadlines"], 10)
        self.assertEqual(options["placeName"], "United States")


if __name__ == "__main__":
    raise SystemExit(unittest.main())
