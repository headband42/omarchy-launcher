#!/usr/bin/env python3
"""Regression tests for the Claude tile's sampler. Stdlib only.

Every test uses a credentials file it made itself, and `fetch` is always
replaced: nothing here reads the real sign-in or reaches the network.

Run from the repo root:  python3 widgets/claude/test_claude.py
"""

import io
import json
import os
import shutil
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from datetime import datetime, timezone
from unittest.mock import patch
from urllib.error import HTTPError

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import claude


def ms(*args):
    return int(datetime(*args, tzinfo=timezone.utc).timestamp() * 1000)


NOW_MS = ms(2026, 10, 1, 17, 0)

# The shape the usage endpoint answers with.
USAGE = {
    "five_hour": {"utilization": 12.0, "resets_at": "2026-10-01T19:59:59.943648+00:00"},
    "seven_day": {"utilization": 41.0, "resets_at": "2026-10-03T03:59:59.943679+00:00"},
    "seven_day_oauth_apps": None,
    "seven_day_opus": {"utilization": 0.0, "resets_at": None},
    "seven_day_sonnet": {"utilization": 3.0, "resets_at": "2026-10-03T03:59:59Z"},
    "extra_usage": {"is_enabled": False, "monthly_limit": None, "used_credits": None, "utilization": None},
}


class Folder:
    """A throwaway config folder with a credentials file in it."""

    def __init__(self, oauth=None, raw=None):
        self.path = tempfile.mkdtemp()
        self.file = os.path.join(self.path, ".credentials.json")
        if raw is not None:
            with open(self.file, "w") as handle:
                handle.write(raw)
        elif oauth is not None:
            with open(self.file, "w") as handle:
                json.dump({"claudeAiOauth": oauth}, handle)

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        shutil.rmtree(self.path)


def oauth(**extra):
    data = {"accessToken": "tok-test", "refreshToken": "ref-test", "expiresAt": NOW_MS + 3600000,
            "scopes": ["user:inference", "user:profile"], "subscriptionType": "max",
            "rateLimitTier": "default_claude_max_20x"}
    data.update(extra)
    return data


class CredentialsTest(unittest.TestCase):
    def test_reads_the_token_and_plan(self):
        with Folder(oauth()) as folder:
            account = claude.credentials(folder.file)
        self.assertEqual(account, {"token": "tok-test", "expiresAt": NOW_MS + 3600000,
                                   "subscription": "max", "tier": "default_claude_max_20x"})

    def test_a_sign_in_without_a_token_is_none(self):
        for broken in (oauth(accessToken=""), oauth(accessToken=None), oauth(accessToken="x" * 9000)):
            with Folder(broken) as folder:
                self.assertIsNone(claude.credentials(folder.file))
        for raw in ("not json", "[]", "{}", '{"claudeAiOauth": "x"}'):
            with Folder(raw=raw) as folder:
                self.assertIsNone(claude.credentials(folder.file))
        self.assertIsNone(claude.credentials("/nonexistent/.credentials.json"))

    def test_an_odd_expiry_is_left_out(self):
        with Folder(oauth(expiresAt="soon")) as folder:
            self.assertIsNone(claude.credentials(folder.file)["expiresAt"])

    def test_the_config_dir_comes_first(self):
        home = tempfile.mkdtemp()
        try:
            with patch.dict(os.environ, {"HOME": home, "CLAUDE_CONFIG_DIR": "/srv/claude"}):
                self.assertEqual(claude.credential_paths(),
                                 ["/srv/claude/.credentials.json",
                                  os.path.join(home, ".claude", ".credentials.json")])
            with patch.dict(os.environ, {"HOME": home, "CLAUDE_CONFIG_DIR": ""}):
                self.assertEqual(claude.credential_paths(),
                                 [os.path.join(home, ".claude", ".credentials.json")])
                # Nothing there yet: signed out, not an error.
                self.assertIsNone(claude.credentials())
        finally:
            shutil.rmtree(home)

    def test_names_the_plan(self):
        self.assertEqual(claude.plan_name("max", "default_claude_max_20x"), "Claude Max 20x")
        self.assertEqual(claude.plan_name("max", "default_claude_max_5x"), "Claude Max 5x")
        self.assertEqual(claude.plan_name("max", ""), "Claude Max")
        self.assertEqual(claude.plan_name("pro", "default_claude_ai"), "Claude Pro")
        self.assertEqual(claude.plan_name("team", ""), "Claude Team")
        self.assertEqual(claude.plan_name("", ""), "Claude")


class ParseTest(unittest.TestCase):
    def test_reads_each_limit_in_order(self):
        payload = claude.parse_usage(USAGE, {"subscription": "max", "tier": "default_claude_max_20x"})
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["plan"], "Claude Max 20x")
        self.assertEqual([m["id"] for m in payload["meters"]],
                         ["five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet"])
        session = payload["meters"][0]
        self.assertEqual(session["label"], "5-HOUR SESSION")
        self.assertEqual(session["caption"], "of this session")
        self.assertEqual(session["percent"], 12.0)
        self.assertEqual(session["resetsAtMs"], ms(2026, 10, 1, 19, 59, 59) + 943)
        self.assertFalse(session["idle"])
        self.assertFalse(session["near"])
        self.assertEqual(payload["pollMs"], claude.POLL_MS)

    def test_a_limit_with_no_window_is_idle(self):
        opus = claude.parse_usage(USAGE)["meters"][2]
        self.assertEqual(opus["percent"], 0.0)
        self.assertIsNone(opus["resetsAtMs"])
        self.assertTrue(opus["idle"])

    def test_near_and_over(self):
        payload = claude.parse_usage({"five_hour": {"utilization": 104.5, "resets_at": "2026-10-01T19:00:00Z"},
                                      "seven_day": {"utilization": 85, "resets_at": "2026-10-03T04:00:00Z"}})
        self.assertTrue(payload["meters"][0]["over"])
        self.assertTrue(payload["meters"][1]["near"])
        self.assertFalse(payload["meters"][1]["over"])
        self.assertEqual(payload["pollMs"], claude.POLL_BUSY_MS)

    def test_extra_usage_only_when_turned_on(self):
        on = dict(USAGE, extra_usage={"is_enabled": True, "monthly_limit": 5000, "used_credits": 1234,
                                      "utilization": 24.68})
        meters = claude.parse_usage(on)["meters"]
        extra = meters[-1]
        self.assertEqual(extra["id"], "extra_usage")
        self.assertEqual(extra["label"], "EXTRA USAGE")
        self.assertEqual(extra["percent"], 24.68)
        self.assertFalse(extra["idle"])
        on["extra_usage"]["utilization"] = None
        self.assertNotIn("extra_usage", [m["id"] for m in claude.parse_usage(on)["meters"]])

    def test_a_new_limit_still_shows(self):
        payload = claude.parse_usage({"five_hour": {"utilization": 1, "resets_at": None},
                                      "seven_day_haiku": {"utilization": 7, "resets_at": "2026-10-03T04:00:00Z"},
                                      "monthly_thing": {"utilization": 2}})
        by_id = {m["id"]: m for m in payload["meters"]}
        self.assertEqual(by_id["seven_day_haiku"]["label"], "WEEK · HAIKU")
        self.assertEqual(by_id["monthly_thing"]["label"], "MONTHLY THING")
        self.assertEqual(by_id["seven_day_haiku"]["caption"], "of week · haiku")

    def test_junk_is_dropped(self):
        for junk in (None, 7, "x", [], {}, {"utilization": None}, {"utilization": "lots"},
                     {"utilization": True}):
            self.assertIsNone(claude.parse_limit("five_hour", junk), junk)

    def test_no_limits_is_a_plan_message(self):
        for payload in ({}, {"five_hour": None, "seven_day": None}):
            view = claude.parse_usage(payload)
            self.assertFalse(view["ok"])
            self.assertEqual(view["reason"], "plan")
        self.assertEqual(claude.parse_usage(["x"])["reason"], "error")

    def test_stamps(self):
        self.assertEqual(claude.epoch_ms("2026-10-03T04:00:00Z"), ms(2026, 10, 3, 4))
        self.assertEqual(claude.epoch_ms("2026-10-03T04:00:00"), ms(2026, 10, 3, 4))
        self.assertIsNone(claude.epoch_ms(None))
        self.assertIsNone(claude.epoch_ms("later"))


class CollectTest(unittest.TestCase):
    def test_a_signed_in_account_becomes_a_payload(self):
        seen = {}

        def fetch(url, token):
            seen["url"] = url
            seen["token"] = token
            return USAGE

        with Folder(oauth()) as folder:
            payload = claude.collect(fetch=fetch, path=folder.file, now_ms=NOW_MS)
        self.assertTrue(payload["ok"])
        self.assertEqual(seen, {"url": claude.USAGE_URL, "token": "tok-test"})
        self.assertEqual(payload["plan"], "Claude Max 20x")
        # The token never rides along in what the tile (and the cache) gets.
        self.assertNotIn("tok-test", json.dumps(payload))

    def test_no_sign_in(self):
        payload = claude.collect(fetch=lambda *a: USAGE, path="/nonexistent/.credentials.json")
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["reason"], "signin")

    def test_an_expired_token_is_not_sent(self):
        def fetch(*args):
            raise AssertionError("an expired token must not be sent")

        with Folder(oauth(expiresAt=NOW_MS - 1)) as folder:
            payload = claude.collect(fetch=fetch, path=folder.file, now_ms=NOW_MS)
        self.assertEqual(payload["reason"], "expired")
        self.assertEqual(payload["plan"], "Claude Max 20x")

    def test_errors_by_status(self):
        cases = ((401, "expired", "expired"), (403, "expired", "expired"),
                 (429, "error", "slow down"), (500, "error", "Anthropic answered 500"))
        for code, reason, words in cases:
            error = HTTPError(claude.USAGE_URL, code, "x", {}, None)
            with Folder(oauth()) as folder:
                payload = claude.collect(fetch=lambda *a, e=error: (_ for _ in ()).throw(e),
                                         path=folder.file, now_ms=NOW_MS)
            self.assertEqual(payload["reason"], reason, code)
            self.assertIn(words, payload["error"])

    def test_a_network_failure_is_drawn(self):
        with Folder(oauth()) as folder:
            payload = claude.collect(fetch=lambda *a: (_ for _ in ()).throw(OSError("offline")),
                                     path=folder.file, now_ms=NOW_MS)
        self.assertEqual(payload["reason"], "error")
        self.assertEqual(payload["error"], "offline")


class RequestTest(unittest.TestCase):
    def test_only_the_usage_call_is_allowed(self):
        with self.assertRaises(ValueError):
            claude.fetch_json("https://example.com/api/oauth/usage", "tok")

    def test_the_request_carries_the_token_and_beta(self):
        seen = {}

        class Response:
            def __enter__(self):
                return self

            def __exit__(self, *exc):
                return False

            def read(self, size):
                return json.dumps(USAGE).encode()

        def opener(request, timeout):
            seen["url"] = request.full_url
            seen["auth"] = request.get_header("Authorization")
            seen["beta"] = request.get_header("Anthropic-beta")
            return Response()

        payload = claude.fetch_json(claude.USAGE_URL, "tok-test", opener=opener)
        self.assertEqual(payload["seven_day"]["utilization"], 41.0)
        self.assertEqual(seen, {"url": claude.USAGE_URL, "auth": "Bearer tok-test", "beta": claude.BETA})

    def test_an_oversized_reply_is_refused(self):
        class Big:
            def __enter__(self):
                return self

            def __exit__(self, *exc):
                return False

            def read(self, size):
                return b"x" * size

        with self.assertRaises(OSError):
            claude.fetch_json(claude.USAGE_URL, "tok", opener=lambda request, timeout: Big())


class MainTest(unittest.TestCase):
    def run_main(self, collector, cache):
        output = io.StringIO()
        with redirect_stdout(output):
            self.assertEqual(claude.main(["claude.py"], collector=collector, cache=cache), 0)
        return json.loads(output.getvalue())

    def test_a_good_reply_is_printed_and_cached(self):
        folder = tempfile.mkdtemp()
        try:
            cache = os.path.join(folder, "nested", "claude.json")
            payload = self.run_main(lambda: claude.parse_usage(USAGE), cache)
            self.assertTrue(payload["ok"])
            self.assertGreater(payload["savedAt"], 0)
            with open(cache) as handle:
                self.assertEqual(json.load(handle)["meters"], payload["meters"])
        finally:
            shutil.rmtree(folder)

    def test_a_failure_is_printed_not_cached(self):
        folder = tempfile.mkdtemp()
        try:
            cache = os.path.join(folder, "claude.json")
            payload = self.run_main(lambda: (_ for _ in ()).throw(RuntimeError("boom")), cache)
            self.assertFalse(payload["ok"])
            self.assertEqual(payload["error"], "boom")
            self.assertFalse(os.path.exists(cache))
        finally:
            shutil.rmtree(folder)


if __name__ == "__main__":
    unittest.main()
