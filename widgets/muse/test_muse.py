#!/usr/bin/env python3
"""Regression tests for the Muse tile's sampler. Stdlib only.

Every test uses an auth file it made itself, and `fetch` is always
replaced: nothing here reads the real sign-in or reaches the network.

Run from the repo root:  python3 widgets/muse/test_muse.py
"""

import json
import os
import shutil
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from unittest.mock import patch
from urllib.error import HTTPError

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import muse

# The shape the mint endpoint answers with.
MINT = {
    "api_key": "minted-key-never-kept",
    "base_url": "https://api.meta.ai/v1",
    "has_payment_method": True,
    "require_payment": False,
    "is_subs_active": True,
    "subs_tier_name": "Muse Code Everyday Usage",
    "subs_usage": {
        "window": {"used_percent": 5, "window_duration_mins": 300,
                   "resets_at": 1791018093},
        "weekly": {"used_percent": 1, "resets_at": 1791158400},
        "tier": "27681393394859588",
    },
}


class Folder:
    """A throwaway config folder with an auth file in it."""

    def __init__(self, token="test-token", raw=None):
        self.path = tempfile.mkdtemp()
        self.file = os.path.join(self.path, "auth.json")
        if raw is not None:
            with open(self.file, "w") as handle:
                handle.write(raw)
        elif token is not None:
            with open(self.file, "w") as handle:
                json.dump({"providers": {"meta": {"access_token": token}}}, handle)

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        shutil.rmtree(self.path, ignore_errors=True)


def fetch(payload):
    def run(url, token):
        assert url == muse.MINT_URL
        assert token == "test-token"
        return json.loads(json.dumps(payload))

    return run


def meters(view):
    return {meter["id"]: meter for meter in view["meters"]}


class QuotaTest(unittest.TestCase):
    def test_window_and_week(self):
        with Folder() as home:
            view = muse.collect(fetch=fetch(MINT), path=home.file)
        self.assertTrue(view["ok"])
        self.assertEqual(view["plan"], "Everyday Usage")
        rows = meters(view)
        self.assertEqual(rows["window"]["label"], "5-HOUR WINDOW")
        self.assertEqual(rows["window"]["percent"], 5)
        self.assertEqual(rows["window"]["resetsAtMs"], 1791018093 * 1000)
        self.assertEqual(rows["window"]["caption"], "of this window")
        self.assertFalse(rows["window"]["idle"])
        self.assertEqual(rows["weekly"]["label"], "WEEK")
        self.assertEqual(rows["weekly"]["percent"], 1)
        self.assertEqual(rows["weekly"]["resetsAtMs"], 1791158400 * 1000)
        self.assertEqual(view["pollMs"], muse.POLL_MS)
        self.assertNotIn("test-token", json.dumps(view))
        self.assertNotIn("minted-key", json.dumps(view))

    def test_polls_faster_near_a_ceiling(self):
        hot = json.loads(json.dumps(MINT))
        hot["subs_usage"]["window"]["used_percent"] = 85
        with Folder() as home:
            view = muse.collect(fetch=fetch(hot), path=home.file)
        rows = meters(view)
        self.assertTrue(rows["window"]["near"])
        self.assertFalse(rows["window"]["over"])
        self.assertEqual(view["pollMs"], muse.POLL_BUSY_MS)
        hot["subs_usage"]["window"]["used_percent"] = 120
        with Folder() as home:
            view = muse.collect(fetch=fetch(hot), path=home.file)
        self.assertTrue(meters(view)["window"]["over"])

    def test_window_label_reads_its_duration(self):
        self.assertEqual(muse.window_label(300), "5-HOUR WINDOW")
        self.assertEqual(muse.window_label(60), "1-HOUR WINDOW")
        self.assertEqual(muse.window_label(90), "90-MIN WINDOW")
        self.assertEqual(muse.window_label(None), "WINDOW")
        self.assertEqual(muse.window_label(0), "WINDOW")

    def test_missing_reset_is_idle(self):
        quiet = json.loads(json.dumps(MINT))
        del quiet["subs_usage"]["window"]["resets_at"]
        with Folder() as home:
            view = muse.collect(fetch=fetch(quiet), path=home.file)
        window = meters(view)["window"]
        self.assertTrue(window["idle"])
        self.assertIsNone(window["resetsAtMs"])

    def test_partial_blocks(self):
        half = json.loads(json.dumps(MINT))
        half["subs_usage"]["weekly"] = None
        with Folder() as home:
            view = muse.collect(fetch=fetch(half), path=home.file)
        self.assertTrue(view["ok"])
        self.assertEqual([meter["id"] for meter in view["meters"]], ["window"])
        half["subs_usage"]["window"] = {"used_percent": "lots"}
        with Folder() as home:
            view = muse.collect(fetch=fetch(half), path=home.file)
        self.assertFalse(view["ok"])

    def test_plan_name(self):
        self.assertEqual(muse.plan_name("Muse Code Everyday Usage"), "Everyday Usage")
        self.assertEqual(muse.plan_name("Something Else"), "Something Else")
        self.assertEqual(muse.plan_name(""), "Muse")
        self.assertEqual(muse.plan_name(None), "Muse")


class SubscriptionTest(unittest.TestCase):
    def test_inactive_subscription(self):
        cold = json.loads(json.dumps(MINT))
        cold["is_subs_active"] = False
        with Folder() as home:
            view = muse.collect(fetch=fetch(cold), path=home.file)
        self.assertFalse(view["ok"])
        self.assertEqual(view["reason"], "plan")
        self.assertEqual(view["plan"], "Everyday Usage")

    def test_payment_needed(self):
        cold = json.loads(json.dumps(MINT))
        cold["is_subs_active"] = False
        cold["require_payment"] = True
        with Folder() as home:
            view = muse.collect(fetch=fetch(cold), path=home.file)
        self.assertEqual(view["reason"], "plan")
        self.assertIn("payment", view["error"].lower())

    def test_missing_usage(self):
        bare = json.loads(json.dumps(MINT))
        del bare["subs_usage"]
        with Folder() as home:
            view = muse.collect(fetch=fetch(bare), path=home.file)
        self.assertFalse(view["ok"])
        self.assertEqual(view["reason"], "error")

    def test_foreign_payload(self):
        with Folder() as home:
            view = muse.collect(fetch=fetch([1, 2]), path=home.file)
        self.assertFalse(view["ok"])


class SigninTest(unittest.TestCase):
    def test_no_sign_in(self):
        with Folder(token=None) as home:
            view = muse.collect(fetch=fetch(MINT), path=home.file)
        self.assertEqual(view["reason"], "signin")
        with Folder(raw="{oops") as home:
            view = muse.collect(fetch=fetch(MINT), path=home.file)
        self.assertEqual(view["reason"], "signin")
        with Folder(raw='{"providers": {}}') as home:
            view = muse.collect(fetch=fetch(MINT), path=home.file)
        self.assertEqual(view["reason"], "signin")
        view = muse.collect(fetch=fetch(MINT), path="/no/such/auth.json")
        self.assertEqual(view["reason"], "signin")

    def test_token_is_stripped(self):
        seen = []

        def run(url, token):
            seen.append(token)
            return json.loads(json.dumps(MINT))

        with Folder(token="  test-token\n") as home:
            view = muse.collect(fetch=run, path=home.file)
        self.assertTrue(view["ok"])
        self.assertEqual(seen, ["test-token"])

    def test_absurd_token_is_no_sign_in(self):
        with Folder(token="x" * 9000) as home:
            view = muse.collect(fetch=fetch(MINT), path=home.file)
        self.assertEqual(view["reason"], "signin")

    def test_auth_paths_honor_xdg(self):
        with patch.dict(os.environ, {"XDG_CONFIG_HOME": "/tmp/xdg"}):
            paths = muse.auth_paths()
        self.assertEqual(paths[0], "/tmp/xdg/muse/auth.json")

    def test_expired_sign_in(self):
        def gone(url, token):
            raise HTTPError(url, 401, "Unauthorized", {}, None)

        with Folder() as home:
            view = muse.collect(fetch=gone, path=home.file)
        self.assertEqual(view["reason"], "expired")

        def slow(url, token):
            raise HTTPError(url, 429, "Too Many", {}, None)

        with Folder() as home:
            view = muse.collect(fetch=slow, path=home.file)
        self.assertIn("slow down", view["error"])

        def broke(url, token):
            raise HTTPError(url, 500, "Broken", {}, None)

        with Folder() as home:
            view = muse.collect(fetch=broke, path=home.file)
        self.assertIn("500", view["error"])

    def test_fetch_refuses_other_urls(self):
        with self.assertRaises(ValueError):
            muse.fetch_json("https://api.meta.ai/v1/models", "test-token")
        with Folder() as home:
            view = muse.collect(path=home.file,
                                fetch=lambda url, token: muse.fetch_json(url, token))
        # The refusal surfaces as an error view, and the token stays out.
        self.assertFalse(view["ok"])
        self.assertNotIn("test-token", json.dumps(view))


class MainTest(unittest.TestCase):
    def test_caches_only_a_good_reply(self):
        cache = os.path.join(tempfile.mkdtemp(), "muse.json")
        self.addCleanup(shutil.rmtree, os.path.dirname(cache), True)
        good = {"ok": True, "reason": "", "plan": "Muse",
                "meters": [{"id": "window"}], "error": None, "pollMs": 1}
        out = StringIO()
        with redirect_stdout(out):
            code = muse.main([], collector=lambda: dict(good), cache=cache)
        self.assertEqual(code, 0)
        payload = json.loads(out.getvalue())
        self.assertTrue(payload["ok"])
        self.assertIn("savedAt", payload)
        with open(cache, encoding="utf-8") as handle:
            self.assertTrue(json.load(handle)["ok"])
        os.remove(cache)
        bad = {"ok": False, "reason": "empty", "plan": "Muse", "meters": [],
               "error": "none", "pollMs": 1}
        with redirect_stdout(StringIO()):
            muse.main([], collector=lambda: dict(bad), cache=cache)
        self.assertFalse(os.path.exists(cache))

    def test_collector_crash_is_a_view_not_a_traceback(self):
        def crash():
            raise RuntimeError("boom")

        out = StringIO()
        with redirect_stdout(out):
            code = muse.main([], collector=crash,
                             cache=os.path.join(tempfile.mkdtemp(), "muse.json"))
        self.assertEqual(code, 0)
        payload = json.loads(out.getvalue())
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["error"], "boom")

    def test_cache_lives_under_xdg_cache_home(self):
        folder = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, folder, True)
        with patch.dict(os.environ, {"XDG_CACHE_HOME": folder}):
            self.assertEqual(muse.cache_path(), os.path.join(folder, "ande.launcher", "muse.json"))


if __name__ == "__main__":
    unittest.main()
