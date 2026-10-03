#!/usr/bin/env python3
"""Time zone catalog and offsets. Stdlib only.

Run from the repo root:  python3 widgets/timezones/test_timezones.py
"""

import importlib.util
import unittest
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import timezones as zones


ROOT = Path(__file__).resolve().parents[2]


def load_list_widgets():
    path = ROOT / "scripts" / "list-widgets.py"
    spec = importlib.util.spec_from_file_location("list_widgets", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ZonesTest(unittest.TestCase):
    def test_city_region(self):
        self.assertEqual(zones.city_region("America/Argentina/Buenos_Aires"),
                         ("Buenos Aires", "America · Argentina"))
        self.assertEqual(zones.city_region("America/New_York"), ("New York", "America"))
        self.assertEqual(zones.city_region("UTC"), ("UTC", ""))

    def test_dst_offsets(self):
        winter = datetime(2026, 1, 15, 12, tzinfo=ZoneInfo("UTC"))
        summer = datetime(2026, 7, 15, 12, tzinfo=ZoneInfo("UTC"))
        self.assertEqual(zones.offset_minutes_at("America/Denver", winter), -420)
        self.assertEqual(zones.offset_minutes_at("America/Denver", summer), -360)
        self.assertEqual(zones.offset_minutes_at("Asia/Tokyo", winter), 540)
        self.assertEqual(zones.offset_minutes_at("UTC", summer), 0)

    def test_snapshot_matches_zoneinfo(self):
        when = datetime(2026, 9, 23, 18, tzinfo=ZoneInfo("UTC"))
        snap = zones.zone_snapshot("America/New_York", when)
        self.assertEqual(snap["label"], "New York")
        self.assertEqual(snap["abbr"], "EDT")
        self.assertEqual(snap["offsetMinutes"], -240)
        self.assertIsNone(zones.zone_snapshot("Not/AZone", when))

    def test_clocks_skip_unknown_and_cap_at_three(self):
        when = datetime(2026, 9, 23, 18, tzinfo=ZoneInfo("UTC"))
        payload = zones.clocks(
            ["UTC", "UTC", "Not/AZone", "Asia/Tokyo", "Europe/London", "Pacific/Auckland"],
            when,
        )
        self.assertEqual([zone["id"] for zone in payload["zones"]],
                         ["UTC", "Asia/Tokyo", "Europe/London"])
        self.assertIn("offsetMinutes", payload["local"])
        self.assertTrue(payload["local"]["label"])

    def test_list_includes_cities_and_utc(self):
        listed = zones.list_zones()
        by_id = {zone["id"]: zone for zone in listed}
        self.assertEqual(len(by_id), len(listed))
        self.assertEqual(by_id["America/New_York"]["label"], "New York")
        self.assertEqual(by_id["Europe/Stockholm"]["label"], "Stockholm")
        self.assertEqual(by_id["Europe/Amsterdam"]["label"], "Amsterdam")
        self.assertEqual(by_id["UTC"]["label"], "UTC")
        self.assertEqual(by_id["UTC"]["offsetMinutes"], 0)
        self.assertIsInstance(by_id["America/New_York"]["offsetMinutes"], int)
        self.assertGreater(len(listed), 400)

    def test_local_zone_resolves(self):
        zone_id = zones.local_zone_id()
        self.assertTrue(zone_id)
        snap = zones.local_snapshot()
        self.assertEqual(snap["id"], zone_id)
        self.assertEqual(snap["offsetMinutes"], zones.offset_minutes_at(zone_id, datetime.now(ZoneInfo("UTC"))))

    def test_timezones_widget_publishes_a_settings_panel(self):
        rows = load_list_widgets().load_dir(ROOT / "widgets")
        by_id = {row["id"]: row for row in rows}
        self.assertTrue(str(by_id["timezones"]["settingsQml"]).endswith("/widgets/timezones/Settings.qml"))
        self.assertTrue(str(by_id["weather"]["settingsQml"]).endswith("/widgets/weather/Settings.qml"))
        self.assertNotIn("settingsQml", by_id["sysdisk"])


if __name__ == "__main__":
    unittest.main()
