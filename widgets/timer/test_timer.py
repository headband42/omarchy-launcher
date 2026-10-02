#!/usr/bin/env python3
"""Tests for the timer sampler. Stdlib only; no real timer is touched.

Run from the repo root:  python3 widgets/timer/test_timer.py
"""

import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import timer

NOW = 1_790_000_000

SHOW = {
    "count": 3,
    "active": True,
    "reminders": [
        {"unit": "omarchy-reminder-60m-1789999000", "minutes": 60, "message": "Tea", "at": NOW + 2600},
        {"unit": "omarchy-reminder-5m-1789999900", "minutes": 5, "message": "", "at": NOW + 200},
        {"unit": "omarchy-reminder-5m-1789990000", "minutes": 5, "message": "", "at": NOW - 10},
        {"unit": "something-else", "at": NOW + 50},
        {"unit": "omarchy-reminder-10m-1789999999", "at": "soon"},
        "junk",
    ],
}


class Calls:
    def __init__(self, answers=None):
        self.argv = []
        self.answers = answers or {}

    def __call__(self, argv, timeout=None):
        self.argv.append(argv)
        return self.answers.get(argv[0], "")


class ParseTests(unittest.TestCase):
    def test_parse_unit(self):
        self.assertEqual(timer.parse_unit("omarchy-reminder-25m-1790000000"), (25, 1790000000))
        self.assertEqual(timer.parse_unit("omarchy-reminder-25m-1790000000.timer"), (25, 1790000000))
        self.assertIsNone(timer.parse_unit("omarchy-reminder-25m-1790000000; rm -rf ~"))
        self.assertIsNone(timer.parse_unit("omarchy-reminder-m-1790000000"))
        self.assertIsNone(timer.parse_unit(""))
        self.assertIsNone(timer.parse_unit(None))

    def test_normalize_keeps_pending_reminders_soonest_first(self):
        rows = timer.normalize(SHOW, NOW)
        self.assertEqual([r["minutes"] for r in rows], [5, 60])
        self.assertEqual(rows[0]["started"], 1789999900)
        self.assertEqual(rows[1]["message"], "Tea")

    def test_normalize_bad_payloads(self):
        self.assertEqual(timer.normalize(None, NOW), [])
        self.assertEqual(timer.normalize({"reminders": "x"}, NOW), [])
        self.assertEqual(timer.normalize([], NOW), [])


class CollectTests(unittest.TestCase):
    def test_collect(self):
        calls = Calls({"omarchy-reminder": json.dumps(SHOW)})
        out = timer.collect(calls, NOW)
        self.assertTrue(out["ok"])
        self.assertEqual(len(out["reminders"]), 2)
        self.assertEqual(calls.argv[0], ["omarchy-reminder", "show", "--json"])

    def test_collect_unreadable(self):
        out = timer.collect(Calls({"omarchy-reminder": "not json"}), NOW)
        self.assertFalse(out["ok"])
        self.assertEqual(out["reminders"], [])

    def test_collect_no_answer(self):
        out = timer.collect(lambda argv, timeout=None: None, NOW)
        self.assertFalse(out["ok"])


class CancelTests(unittest.TestCase):
    def test_cancel_stops_the_unit_and_drops_its_message(self):
        calls = Calls({"systemctl": ""})
        removed = []
        out = timer.cancel("omarchy-reminder-5m-1789999900", calls, removed.append, "/run/x")
        self.assertTrue(out["ok"])
        self.assertEqual(calls.argv[0], ["systemctl", "--user", "stop", "omarchy-reminder-5m-1789999900.timer"])
        self.assertEqual(removed, ["/run/x/omarchy-reminder-5m-1789999900.message"])

    def test_cancel_accepts_a_timer_suffix(self):
        calls = Calls({"systemctl": ""})
        timer.cancel("omarchy-reminder-5m-1789999900.timer", calls, lambda path: None, "/run/x")
        self.assertEqual(calls.argv[0][-1], "omarchy-reminder-5m-1789999900.timer")

    def test_cancel_refuses_other_units(self):
        for bad in ("", "sshd", "omarchy-reminder-5m-1789999900 x", "../omarchy-reminder-5m-1789999900", "-omarchy-reminder-5m-1"):
            calls = Calls()
            self.assertEqual(timer.cancel(bad, calls, lambda path: None, "/run/x"), {"ok": False}, bad)
            self.assertEqual(calls.argv, [], bad)

    def test_cancel_reports_a_failed_stop(self):
        out = timer.cancel("omarchy-reminder-5m-1789999900", lambda argv, timeout=None: None, lambda path: None, "/run/x")
        self.assertFalse(out["ok"])


if __name__ == "__main__":
    unittest.main()
