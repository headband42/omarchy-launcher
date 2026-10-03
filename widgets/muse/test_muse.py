#!/usr/bin/env python3
"""Regression tests for the Muse tile's sampler. Stdlib only.

Every test builds its own sessions tree and catalog in a temporary folder:
nothing here reads the real Muse logs, and nothing reaches the network.

Run from the repo root:  python3 widgets/muse/test_muse.py
"""

import json
import os
import shutil
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from datetime import datetime, timezone
from io import StringIO
from unittest.mock import patch

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import muse

MODEL = "muse-spark-1.3-contributor"
LIMIT = 1007997

NOW_MS = int(datetime(2026, 10, 2, 12, 0, tzinfo=timezone.utc).timestamp() * 1000)
MIDNIGHT_MS = muse.midnight_ms(NOW_MS)


def event_line(at_ms, model=MODEL, input_tokens=1000, output_tokens=100,
               session="session-1", stamp=None, usage=None):
    completed = {
        "duration_ms": 10,
        "finish_reason": "stop",
        "kind": "model_completed",
        "model": model,
        "usage": {"input_tokens": input_tokens, "output_tokens": output_tokens,
                  "reasoning_tokens": 0, "cache_read_tokens": 0,
                  "cache_write_tokens": 0, "cached_tokens": 0}
        if usage is None else usage,
    }
    record = {
        "schema_version": 1, "id": "record-1",
        "stream": {"kind": "session", "id": session}, "sequence": 1,
        "recorded_at": at_ms * 1000 if stamp is None else stamp,
        "record_type": "event", "durability": "durable", "causation_id": None,
        "payload_type": "runtime.session", "payload_schema_version": 1,
        "payload": {"event": completed, "kind": "run", "run_id": "run-1"},
    }
    return json.dumps(record)


class Home:
    """A throwaway Muse data dir with sessions and a catalog."""

    def __init__(self, logs=None, catalog=True):
        self.path = tempfile.mkdtemp()
        for index, lines in enumerate(logs or []):
            folder = os.path.join(self.path, "sessions", "2026", "10", "02",
                                  "session-%d" % (index + 1))
            os.makedirs(folder, exist_ok=True)
            with open(os.path.join(folder, "session.jsonl"), "w") as handle:
                handle.write("\n".join(lines) + "\n" if lines else "")
        if catalog:
            folder = os.path.join(self.path, "model-catalog")
            os.makedirs(folder, exist_ok=True)
            with open(os.path.join(folder, "meta.json"), "w") as handle:
                json.dump({"rows": [{"model_id": MODEL, "context_limit": LIMIT}]}, handle)

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        shutil.rmtree(self.path, ignore_errors=True)


def meters(view):
    return {meter["id"]: meter for meter in view["meters"]}


class WindowsTest(unittest.TestCase):
    def test_today_week_and_context(self):
        first = MIDNIGHT_MS + 3600000
        lines = [event_line(first, input_tokens=30000, output_tokens=1000, session="s1"),
                 event_line(MIDNIGHT_MS - 3600000, input_tokens=10000,
                            output_tokens=500, session="s2"),
                 event_line(NOW_MS - 8 * muse.DAY_MS, input_tokens=5000,
                            output_tokens=500, session="s3")]
        with Home(logs=[lines]) as home:
            view = muse.collect(home=home.path, now_ms=NOW_MS)
        self.assertTrue(view["ok"])
        self.assertEqual(view["model"], MODEL)
        rows = meters(view)
        self.assertEqual(rows["today"]["detail"], "31K tokens · 1 session")
        self.assertEqual(rows["week"]["detail"], "42K tokens · 2 sessions")
        self.assertIsNone(rows["today"]["percent"])
        self.assertAlmostEqual(rows["context"]["percent"], 30000 / LIMIT * 100)
        self.assertEqual(rows["context"]["detail"], "30K of 1M · " + MODEL)
        self.assertFalse(rows["context"]["near"])
        self.assertEqual(view["pollMs"], muse.POLL_MS)

    def test_reasoning_is_not_added_on_top(self):
        usage = {"input_tokens": 100, "output_tokens": 879, "reasoning_tokens": 707}
        with Home(logs=[[event_line(MIDNIGHT_MS + 1000, usage=usage)]]) as home:
            view = muse.collect(home=home.path, now_ms=NOW_MS)
        self.assertEqual(meters(view)["today"]["detail"], "979 tokens · 1 session")

    def test_counts_a_copied_log_by_its_events_not_its_mtime(self):
        path = None
        with Home(logs=[[event_line(MIDNIGHT_MS + 1000)]]) as home:
            for dirpath, _names, files in os.walk(home.path):
                if "session.jsonl" in files:
                    path = os.path.join(dirpath, "session.jsonl")
            old = NOW_MS / 1000 - 30 * 24 * 3600
            os.utime(path, (old, old))
            view = muse.collect(home=home.path, now_ms=NOW_MS)
        self.assertTrue(view["ok"])
        self.assertEqual(meters(view)["today"]["detail"], "1K tokens · 1 session")


class NoiseTest(unittest.TestCase):
    def test_skips_junk_other_records_and_other_files(self):
        junk = event_line(MIDNIGHT_MS + 1000, input_tokens=1000, output_tokens=0)
        noise = [
            "this is not json",
            json.dumps({"payload": {"event": {"kind": "turn_started"}}}),
            json.dumps({"payload": {"kind": "run"}}),
            junk.replace("model_completed", "model_started"),
        ]
        with Home(logs=[noise]) as home:
            folder = os.path.join(home.path, "sessions", "2026", "10", "02", "session-1")
            with open(os.path.join(folder, "notes.txt"), "w") as handle:
                handle.write(junk + "\n")
            view = muse.collect(home=home.path, now_ms=NOW_MS)
        self.assertFalse(view["ok"])
        self.assertEqual(view["reason"], "empty")

    def test_reads_an_exact_duplicate_once(self):
        line = event_line(MIDNIGHT_MS + 1000, input_tokens=2000, output_tokens=0)
        with Home(logs=[[line], [line]]) as home:
            view = muse.collect(home=home.path, now_ms=NOW_MS)
        self.assertEqual(meters(view)["today"]["detail"], "2K tokens · 1 session")

    def test_missing_counters_are_zeros(self):
        with Home(logs=[[event_line(MIDNIGHT_MS + 1000, usage={})]]) as home:
            view = muse.collect(home=home.path, now_ms=NOW_MS)
        rows = meters(view)
        self.assertTrue(view["ok"])
        self.assertEqual(rows["today"]["detail"], "0 tokens · 1 session")
        self.assertEqual(rows["context"]["percent"], 0.0)

    def test_zero_token_completion_does_not_become_the_context(self):
        lines = [event_line(MIDNIGHT_MS + 1000, input_tokens=4000, output_tokens=100),
                 event_line(MIDNIGHT_MS + 2000, input_tokens=0, output_tokens=0)]
        with Home(logs=[lines]) as home:
            view = muse.collect(home=home.path, now_ms=NOW_MS)
        self.assertAlmostEqual(meters(view)["context"]["percent"], 4000 / LIMIT * 100)


class CatalogTest(unittest.TestCase):
    def test_unknown_model_keeps_absolutes_but_no_percent(self):
        with Home(logs=[[event_line(MIDNIGHT_MS + 1000, model="muse-future-9")]],
                  catalog=False) as home:
            view = muse.collect(home=home.path, now_ms=NOW_MS)
        context = meters(view)["context"]
        self.assertIsNone(context["percent"])
        self.assertEqual(context["detail"], "1K · muse-future-9")

    def test_broken_catalog_files_are_skipped(self):
        with Home(logs=[[event_line(MIDNIGHT_MS + 1000)]]) as home:
            folder = os.path.join(home.path, "model-catalog")
            with open(os.path.join(folder, "broken.json"), "w") as handle:
                handle.write("{oops")
            with open(os.path.join(folder, "notes.txt"), "w") as handle:
                handle.write("not a catalog")
            view = muse.collect(home=home.path, now_ms=NOW_MS)
        self.assertAlmostEqual(meters(view)["context"]["percent"], 1000 / LIMIT * 100)

    def test_no_usage_recorded_yet(self):
        with Home(logs=[]) as home:
            view = muse.collect(home=home.path, now_ms=NOW_MS)
        self.assertFalse(view["ok"])
        self.assertEqual(view["reason"], "empty")
        self.assertEqual(view["meters"], [])
        missing = os.path.join(home.path, "no-such-dir")
        view = muse.collect(home=missing, now_ms=NOW_MS)
        self.assertEqual(view["reason"], "empty")


class HelpersTest(unittest.TestCase):
    def test_compact(self):
        self.assertEqual(muse.compact(None), "—")
        self.assertEqual(muse.compact(0), "0")
        self.assertEqual(muse.compact(979), "979")
        self.assertEqual(muse.compact(1000), "1K")
        self.assertEqual(muse.compact(1499), "1K")
        self.assertEqual(muse.compact(1500), "2K")
        self.assertEqual(muse.compact(31494), "31K")
        self.assertEqual(muse.compact(999499), "999K")
        self.assertEqual(muse.compact(999500), "1M")
        self.assertEqual(muse.compact(1007997), "1M")
        self.assertEqual(muse.compact(1200000), "1.2M")
        self.assertEqual(muse.compact(2000000), "2M")

    def test_midnight_is_local_midnight(self):
        start = muse.midnight_ms(NOW_MS)
        moment = datetime.fromtimestamp(start / 1000)
        self.assertEqual((moment.hour, moment.minute, moment.second, moment.microsecond), (0, 0, 0, 0))
        self.assertLessEqual(start, NOW_MS)
        self.assertGreater(start, NOW_MS - muse.DAY_MS)

    def test_recorded_units(self):
        self.assertEqual(muse.recorded_ms(NOW_MS * 1000), NOW_MS)
        self.assertEqual(muse.recorded_ms(NOW_MS), NOW_MS)
        self.assertEqual(muse.recorded_ms(NOW_MS / 1000), NOW_MS)
        self.assertIsNone(muse.recorded_ms("yesterday"))
        self.assertIsNone(muse.recorded_ms(None))
        with Home(logs=[[event_line(0, stamp=NOW_MS)]]) as home:
            view = muse.collect(home=home.path, now_ms=NOW_MS)
        # Millis, not micros: still a moment this week.
        self.assertTrue(view["ok"])


class MainTest(unittest.TestCase):
    def test_caches_only_a_good_reply(self):
        cache = os.path.join(tempfile.mkdtemp(), "muse.json")
        self.addCleanup(shutil.rmtree, os.path.dirname(cache), True)
        good = {"ok": True, "reason": "", "plan": "Muse", "model": MODEL,
                "meters": [{"id": "today"}], "error": None, "pollMs": 1}
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
        bad = {"ok": False, "reason": "empty", "plan": "Muse", "model": "",
               "meters": [], "error": "none", "pollMs": 1}
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
