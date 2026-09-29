#!/usr/bin/env python3
"""Regression tests for the toggles tile logic. Stdlib only.

Run from the repo root:  python3 widgets/toggles/test_sample.py
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import toggles


class ParseTests(unittest.TestCase):
    def test_parse_enabled(self):
        self.assertTrue(toggles.parse_enabled('{"enabled": true, "temperature": 4000}'))
        self.assertFalse(toggles.parse_enabled('{"enabled": false, "temperature": null}'))
        self.assertFalse(toggles.parse_enabled('{"temperature": 4000}'))
        self.assertFalse(toggles.parse_enabled(""))
        self.assertFalse(toggles.parse_enabled("not json"))
        self.assertFalse(toggles.parse_enabled("[1, 2]"))

    def test_parse_dnd(self):
        self.assertTrue(toggles.parse_dnd('{"version": 3, "dnd": true}'))
        self.assertFalse(toggles.parse_dnd('{"version": 3, "dnd": false}'))
        self.assertFalse(toggles.parse_dnd('{"version": 3}'))
        self.assertFalse(toggles.parse_dnd(""))
        self.assertFalse(toggles.parse_dnd("nope"))


class GatherTests(unittest.TestCase):
    def test_gather_reads_every_row(self):
        answers = {
            "omarchy-toggle-nightlight": (0, '{"enabled": true, "temperature": 4000}'),
            "omarchy-toggle-idle": (0, '{"enabled": true, "class": "enabled"}'),
        }

        def run(argv, timeout):
            return answers[argv[0]]

        payload = toggles.gather(run, lambda path: '{"version": 3, "dnd": true}')
        self.assertEqual(payload, {"nightlight": True, "stayAwake": True, "dnd": True})

    def test_gather_tolerates_failures(self):
        def run(argv, timeout):
            return 127, ""

        payload = toggles.gather(run, lambda path: "")
        self.assertEqual(payload, {"nightlight": False, "stayAwake": False, "dnd": False})


if __name__ == "__main__":
    unittest.main()
