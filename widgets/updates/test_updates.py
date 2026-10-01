#!/usr/bin/env python3
"""Regression tests for the updates tile logic. Stdlib only.

Run from the repo root:  python3 widgets/updates/test_updates.py
"""

import os
import sys
import tempfile
import unittest
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import updates


CHECKUPDATES = """\
linux 6.9.1.arch1-1 -> 6.9.2.arch1-1
mesa 24.1.1-1 -> 24.1.2-1
quickshell 0.1.0-1 -> 0.1.1-1
"""

PACMAN_LOG = """\
[2026-09-20T08:00:00-0600] [PACMAN] Running 'pacman -Syu'
[2026-09-20T08:00:01-0600] [ALPM] transaction started
[2026-09-20T08:00:02-0600] [ALPM] upgraded linux (6.9.0-1 -> 6.9.1-1)
[2026-09-20T08:00:02-0600] [ALPM] transaction completed
[2026-09-23T19:21:56-0600] [ALPM] transaction started
[2026-09-23T19:21:57-0600] [ALPM] transaction completed
[2026-09-23T19:21:57-0600] [ALPM] running '35-systemd-update.hook'...
"""

LAST_STAMP = datetime.strptime("2026-09-23T19:21:57-0600", "%Y-%m-%dT%H:%M:%S%z").timestamp()


class ParseTests(unittest.TestCase):
    def test_parse_updates(self):
        rows = updates.parse_updates(CHECKUPDATES)
        self.assertEqual(len(rows), 3)
        self.assertEqual(rows[0], {"name": "linux", "old": "6.9.1.arch1-1", "new": "6.9.2.arch1-1"})
        self.assertEqual(rows[2]["name"], "quickshell")

    def test_parse_updates_skips_noise(self):
        self.assertEqual(updates.parse_updates(""), [])
        self.assertEqual(updates.parse_updates("\n\n"), [])
        self.assertEqual(updates.parse_updates("warning: something\n"), [])
        self.assertEqual(updates.parse_updates(" -> only-new\n"), [])

    def test_parse_last_upgrade(self):
        stamp = updates.parse_last_upgrade(PACMAN_LOG)
        self.assertGreater(stamp, 0)
        self.assertEqual(stamp, LAST_STAMP)

    def test_parse_last_upgrade_empty(self):
        self.assertEqual(updates.parse_last_upgrade(""), 0)
        self.assertEqual(updates.parse_last_upgrade("[2026-01-01T00:00:00+0000] [PACMAN] Running"), 0)

    def test_parse_omarchy(self):
        self.assertEqual(updates.parse_omarchy("Omarchy is up to date\n", 1), [])
        self.assertEqual(
            updates.parse_omarchy("omarchy-dev-checkout 2 new commits on origin/master\n", 0),
            ["omarchy-dev-checkout 2 new commits on origin/master"])
        self.assertEqual(updates.parse_omarchy("", 0), [])

    def test_first_line(self):
        self.assertEqual(updates.first_line("stable\n"), "stable")
        self.assertEqual(updates.first_line("\n\n  dev (abc1234)  \nmore\n"), "dev (abc1234)")
        self.assertEqual(updates.first_line(""), "")
        self.assertEqual(updates.first_line("\n \n"), "")
        self.assertEqual(updates.first_line(None), "")


class CollectTests(unittest.TestCase):
    def run_fake(self, answers):
        def run(argv, timeout):
            key = argv[0]
            self.assertIn(key, answers)
            return answers[key]
        return run

    def test_gather_counts_and_notes(self):
        payload = updates.gather(
            self.run_fake({
                "checkupdates": (0, CHECKUPDATES),
                "omarchy-update-available": (0, "omarchy 4.1-1 -> 4.2-1\n"),
                "omarchy-channel-current": (0, "stable\n"),
                "omarchy-version": (0, "4.0.4-1\n"),
            }),
            lambda path: PACMAN_LOG)
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["count"], 3)
        self.assertEqual(payload["names"], ["linux", "mesa", "quickshell"])
        self.assertEqual(payload["omarchy"], ["omarchy 4.1-1 -> 4.2-1"])
        self.assertEqual(payload["channel"], "stable")
        self.assertEqual(payload["version"], "4.0.4-1")
        self.assertEqual(payload["lastUpgradeAt"], LAST_STAMP)

    def test_gather_no_updates(self):
        payload = updates.gather(
            self.run_fake({
                "checkupdates": (2, ""),
                "omarchy-update-available": (1, "Omarchy is up to date\n"),
                "omarchy-channel-current": (0, "dev\n"),
                "omarchy-version": (1, ""),
            }),
            lambda path: "")
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["count"], 0)
        self.assertEqual(payload["names"], [])
        self.assertEqual(payload["omarchy"], [])
        self.assertEqual(payload["channel"], "dev")
        self.assertEqual(payload["version"], "")
        self.assertEqual(payload["lastUpgradeAt"], 0)

    def test_gather_checkupdates_failure(self):
        payload = updates.gather(
            self.run_fake({
                "checkupdates": (1, ""),
                "omarchy-update-available": (1, ""),
                "omarchy-channel-current": (1, ""),
                "omarchy-version": (1, ""),
            }),
            lambda path: "")
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["count"], 0)
        self.assertEqual(payload["channel"], "")
        self.assertEqual(payload["version"], "")

    def test_collect_uses_fresh_cache(self):
        with tempfile.TemporaryDirectory() as tmp:
            cache = os.path.join(tmp, "updates.json")
            # An old cache file: no channel or version keys at all.
            with open(cache, "w", encoding="utf-8") as fh:
                fh.write('{"ok": true, "count": 2, "names": ["a", "b"], "omarchy": [], "lastUpgradeAt": 0}')
            os.utime(cache, (1_700_000_000, 1_700_000_000))
            payload = updates.collect(
                run=self.run_fake({
                    "omarchy-channel-current": (0, "stable\n"),
                    "omarchy-version": (0, "4.0.4-1\n"),
                }),
                read_log=lambda path: PACMAN_LOG,
                cache_path=cache,
                max_age=3600,
                now=1_700_000_100)
            self.assertEqual(payload["count"], 2)
            self.assertEqual(payload["channel"], "stable")
            self.assertEqual(payload["version"], "4.0.4-1")
            self.assertEqual(payload["lastUpgradeAt"], LAST_STAMP)

    def test_collect_refreshes_stale_cache(self):
        with tempfile.TemporaryDirectory() as tmp:
            cache = os.path.join(tmp, "updates.json")
            with open(cache, "w", encoding="utf-8") as fh:
                fh.write('{"ok": true, "count": 2, "names": ["a", "b"], "omarchy": [], "lastUpgradeAt": 0}')
            os.utime(cache, (1_700_000_000, 1_700_000_000))
            payload = updates.collect(
                run=self.run_fake({
                    "checkupdates": (2, ""),
                    "omarchy-update-available": (1, ""),
                    "omarchy-channel-current": (0, "edge\n"),
                    "omarchy-version": (0, "dev (abc1234)\n"),
                }),
                read_log=lambda path: "",
                cache_path=cache,
                max_age=60,
                now=1_700_000_100)
            self.assertEqual(payload["count"], 0)
            self.assertEqual(payload["channel"], "edge")
            self.assertEqual(payload["version"], "dev (abc1234)")
            with open(cache, encoding="utf-8") as fh:
                self.assertIn('"count": 0', fh.read())

    def test_collect_without_cache(self):
        with tempfile.TemporaryDirectory() as tmp:
            cache = os.path.join(tmp, "updates.json")
            payload = updates.collect(
                run=self.run_fake({
                    "checkupdates": (0, "a 1 -> 2\n"),
                    "omarchy-update-available": (1, ""),
                    "omarchy-channel-current": (0, "stable\n"),
                    "omarchy-version": (0, "4.0.4-1\n"),
                }),
                read_log=lambda path: "",
                cache_path=cache,
                max_age=60,
                now=1_700_000_100)
            self.assertEqual(payload["count"], 1)
            self.assertTrue(os.path.exists(cache))


if __name__ == "__main__":
    unittest.main()
