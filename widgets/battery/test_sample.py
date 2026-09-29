#!/usr/bin/env python3
"""Regression tests for the battery tile logic. Stdlib only.

Run from the repo root:  python3 widgets/battery/test_sample.py
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import battery


UPOWER_DISCHARGING = """\
  native-path:          BAT0
  power supply:         yes
  battery
    present:             yes
    state:               discharging
    energy:              45.6 Wh
    energy-rate:         12.3 W
    time to empty:       3.7 hours
    percentage:          76%
    capacity:            100%
"""

UPOWER_CHARGING = """\
  native-path:          BAT0
  battery
    present:             yes
    state:               charging
    energy-rate:         25.1 W
    time to full:        45.2 minutes
    percentage:          41%
"""

UPOWER_FULL = """\
  native-path:          BAT0
  battery
    present:             yes
    state:               fully-charged
    percentage:          100%
"""

PROFILES = "power-saver\t0\nbalanced\t1\nperformance\t0\n"


class ParseTests(unittest.TestCase):
    def test_parse_upower_discharging(self):
        data = battery.parse_upower(UPOWER_DISCHARGING)
        self.assertEqual(data["percentage"], 76)
        self.assertEqual(data["state"], "discharging")
        self.assertEqual(data["minutes"], 222)
        self.assertEqual(data["rate"], 12.3)

    def test_parse_upower_charging(self):
        data = battery.parse_upower(UPOWER_CHARGING)
        self.assertEqual(data["percentage"], 41)
        self.assertEqual(data["state"], "charging")
        self.assertEqual(data["minutes"], 45)
        self.assertEqual(data["rate"], 25.1)

    def test_parse_upower_full(self):
        data = battery.parse_upower(UPOWER_FULL)
        self.assertEqual(data["percentage"], 100)
        self.assertEqual(data["state"], "fully-charged")
        self.assertEqual(data["minutes"], 0)
        self.assertEqual(data["rate"], 0.0)

    def test_parse_upower_garbage(self):
        data = battery.parse_upower("")
        self.assertEqual(data["percentage"], 0)
        self.assertEqual(data["state"], "")
        data = battery.parse_upower("percentage: bad%\ntime to empty: nope\nenergy-rate: x\n")
        self.assertEqual(data["percentage"], 0)
        self.assertEqual(data["minutes"], 0)
        self.assertEqual(data["rate"], 0.0)

    def test_parse_duration(self):
        self.assertEqual(battery.parse_duration("3.7 hours"), 222)
        self.assertEqual(battery.parse_duration("45.2 minutes"), 45)
        self.assertEqual(battery.parse_duration("1 hour"), 60)
        self.assertEqual(battery.parse_duration("90 seconds"), 2)
        self.assertEqual(battery.parse_duration(""), 0)
        self.assertEqual(battery.parse_duration("unknown"), 0)

    def test_parse_profiles(self):
        current, names = battery.parse_profiles(PROFILES)
        self.assertEqual(current, "balanced")
        self.assertEqual(names, ["power-saver", "balanced", "performance"])

    def test_parse_profiles_empty(self):
        self.assertEqual(battery.parse_profiles(""), ("", []))
        self.assertEqual(battery.parse_profiles("garbage\n"), ("", []))


class GatherTests(unittest.TestCase):
    def run_fake(self, answers):
        def run(argv, timeout):
            key = tuple(argv)
            self.assertIn(key, answers)
            return answers[key]
        return run

    def test_gather_with_battery(self):
        payload = battery.gather(self.run_fake({
            ("omarchy-battery-present",): (0, ""),
            ("upower", "-e"): (0, "/org/freedesktop/UPower/devices/DisplayDevice\n/org/freedesktop/UPower/devices/BAT0\n"),
            ("upower", "-i", "/org/freedesktop/UPower/devices/BAT0"): (0, UPOWER_DISCHARGING),
            ("omarchy-power-present",): (1, ""),
            ("omarchy-powerprofiles-list", "--active-state"): (0, PROFILES),
        }))
        self.assertTrue(payload["battery"])
        self.assertEqual(payload["percentage"], 76)
        self.assertEqual(payload["state"], "discharging")
        self.assertEqual(payload["minutesLeft"], 222)
        self.assertFalse(payload["onAc"])
        self.assertEqual(payload["profile"], "balanced")
        self.assertEqual(payload["profiles"], ["power-saver", "balanced", "performance"])

    def test_gather_desktop_without_battery(self):
        payload = battery.gather(self.run_fake({
            ("omarchy-battery-present",): (1, ""),
            ("omarchy-power-present",): (0, ""),
            ("omarchy-powerprofiles-list", "--active-state"): (0, PROFILES),
        }))
        self.assertFalse(payload["battery"])
        self.assertEqual(payload["percentage"], 0)
        self.assertEqual(payload["state"], "")
        self.assertTrue(payload["onAc"])
        self.assertEqual(payload["profile"], "balanced")


if __name__ == "__main__":
    unittest.main()
