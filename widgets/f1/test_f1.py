#!/usr/bin/env python3
"""Tests for the F1 sampler. Stdlib only; nothing here reaches the network.

Run from the repo root:  python3 widgets/f1/test_f1.py
"""

import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import f1

NEXT = {"MRData": {"RaceTable": {"Races": [{
    "season": "2026", "round": "16", "raceName": "Singapore Grand Prix", "url": "https://en.wikipedia.org/wiki/2026_Singapore_Grand_Prix",
    "Circuit": {"circuitName": "Marina Bay Street Circuit", "Location": {"locality": "Marina Bay", "country": "Singapore"}},
    "date": "2026-10-04", "time": "12:00:00Z",
    "FirstPractice": {"date": "2026-10-02", "time": "09:30:00Z"},
    "SprintQualifying": {"date": "2026-10-02", "time": "13:30:00Z"},
    "Sprint": {"date": "2026-10-03", "time": "09:00:00Z"},
    "Qualifying": {"date": "2026-10-03", "time": "13:00:00Z"},
}]}}}

LAST = {"MRData": {"RaceTable": {"Races": [{
    "season": "2026", "round": "15", "raceName": "Azerbaijan Grand Prix", "date": "2026-09-26", "time": "11:00:00Z",
    "Results": [
        {"position": "1", "points": "25", "Driver": {"code": "RUS", "familyName": "Russell"}, "Constructor": {"name": "Mercedes"}, "Time": {"time": "1:38:02.143"}, "status": "Finished"},
        {"position": "2", "points": "18", "Driver": {"code": "VER", "familyName": "Verstappen"}, "Constructor": {"name": "Red Bull"}, "Time": {"time": "+0.196"}, "status": "Finished"},
        {"position": "3", "points": "0", "Driver": {"familyName": "Nobody"}, "Constructor": {"name": "X"}, "status": "Retired"},
    ]}]}}}

DRIVERS = {"MRData": {"StandingsTable": {"StandingsLists": [{"DriverStandings": [
    {"position": "1", "points": "302", "wins": "5", "Driver": {"code": "ANT", "familyName": "Antonelli"}, "Constructors": [{"name": "Mercedes"}]},
    {"position": "2", "points": "236", "wins": "3", "Driver": {"code": "RUS", "familyName": "Russell"}, "Constructors": [{"name": "Mercedes"}]},
]}]}}}

TEAMS = {"MRData": {"StandingsTable": {"StandingsLists": [{"ConstructorStandings": [
    {"position": "1", "points": "538", "wins": "8", "Constructor": {"name": "Mercedes"}},
    {"position": "2", "points": "378", "wins": "2", "Constructor": {"name": "Ferrari"}},
]}]}}}

OPENF1_DRIVERS = [
    {"driver_number": 12, "name_acronym": "ANT", "team_name": "Mercedes", "team_colour": "00D7B6"},
    {"driver_number": 63, "name_acronym": "RUS", "team_name": "Mercedes", "team_colour": "00D7B6"},
    {"driver_number": 1, "name_acronym": "VER", "team_name": "Red Bull Racing", "team_colour": "bad"},
]

POSITIONS = [
    {"date": "2026-10-02T09:31:00Z", "driver_number": 12, "position": 1},
    {"date": "2026-10-02T09:31:00Z", "driver_number": 63, "position": 2},
    {"date": "2026-10-02T09:31:00Z", "driver_number": 1, "position": 3},
    {"date": "2026-10-02T09:40:00Z", "driver_number": 1, "position": 1},
    {"date": "2026-10-02T09:40:00Z", "driver_number": 12, "position": 2},
    {"date": "2026-10-02T09:40:00Z", "driver_number": 63, "position": 3},
    {"date": "2026-10-02T09:39:00Z", "driver_number": 63, "position": None},
]


def routes(extra=None):
    table = {
        f1.JOLPICA + "current/next.json": NEXT,
        f1.JOLPICA + "current/last/results.json": LAST,
        f1.JOLPICA + "current/driverStandings.json": DRIVERS,
        f1.JOLPICA + "current/constructorStandings.json": TEAMS,
        f1.OPENF1 + "sessions?session_key=latest": [{"session_key": 9001, "session_name": "Practice 1",
                                                     "date_start": "2026-10-02T09:30:00+00:00", "date_end": "2026-10-02T10:30:00+00:00"}],
        f1.OPENF1 + "drivers?session_key=9001": OPENF1_DRIVERS,
        f1.OPENF1 + "position?session_key=9001": POSITIONS,
    }
    table.update(extra or {})
    calls = []

    def fetch(url, timeout=None):
        calls.append(url)
        if url not in table:
            raise f1.F1Error("answered 404")
        value = table[url]
        if isinstance(value, Exception):
            raise value
        return json.loads(json.dumps(value))
    return fetch, calls


class ParseTests(unittest.TestCase):
    def test_weekend_lists_sessions_in_order(self):
        weekend = f1.weekend(f1.races_of(NEXT)[0])
        self.assertEqual(weekend["round"], "16")
        self.assertEqual([s["name"] for s in weekend["sessions"]], ["FP1", "Sprint Qualifying", "Sprint", "Qualifying", "Race"])
        self.assertEqual(weekend["sessions"][-1]["start"], 1791115200)
        self.assertEqual(weekend["sessions"][-1]["end"] - weekend["sessions"][-1]["start"], 7200)
        self.assertEqual(weekend["sessions"][1]["end"] - weekend["sessions"][1]["start"], 2700)
        self.assertEqual(weekend["locality"], "Marina Bay")
        self.assertIsNone(f1.weekend(None))

    def test_results_and_standings(self):
        rows = f1.result_rows(f1.races_of(LAST)[0])
        self.assertEqual([(r["pos"], r["code"], r["time"]) for r in rows], [("1", "RUS", "1:38:02.143"), ("2", "VER", "+0.196"), ("3", "NOB", "Retired")])
        drivers = f1.standings(DRIVERS, "DriverStandings")
        self.assertEqual((drivers[0]["code"], drivers[0]["team"], drivers[0]["points"]), ("ANT", "Mercedes", "302"))
        teams = f1.standings(TEAMS, "ConstructorStandings")
        self.assertEqual([t["name"] for t in teams], ["Mercedes", "Ferrari"])
        self.assertEqual(f1.standings({}, "DriverStandings"), [])

    def test_live_order_takes_each_cars_latest_position(self):
        order = f1.live_order(POSITIONS, OPENF1_DRIVERS)
        self.assertEqual([(r["pos"], r["code"]) for r in order], [(1, "VER"), (2, "ANT"), (3, "RUS")])
        self.assertEqual(order[0]["colour"], "")
        self.assertEqual(order[1]["colour"], "00D7B6")
        self.assertEqual(f1.live_order(None, None), [])

    def test_current_session_window(self):
        sessions = [{"name": "FP1", "start": 1000, "end": 4600}]
        self.assertIsNone(f1.current_session(sessions, 1000 - f1.LEAD - 1))
        self.assertEqual(f1.current_session(sessions, 1000 - f1.LEAD)["name"], "FP1")
        self.assertEqual(f1.current_session(sessions, 4600 + f1.TAIL)["name"], "FP1")
        self.assertIsNone(f1.current_session(sessions, 4600 + f1.TAIL + 1))

    def test_stamps(self):
        self.assertEqual(f1.stamp("2026-10-04", "12:00:00Z"), 1791115200)
        self.assertEqual(f1.stamp("2026-10-04", None), 1791072000)
        self.assertIsNone(f1.stamp("", "12:00:00Z"))
        self.assertIsNone(f1.stamp("soon", "x"))


class CollectTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.folder = self.dir.name

    def tearDown(self):
        self.dir.cleanup()

    def test_quiet_week(self):
        fetch, calls = routes()
        now = 1790500000  # days before the weekend
        out = f1.collect(now, fetch, self.folder)
        self.assertTrue(out["ok"])
        self.assertEqual(out["season"], "2026")
        self.assertEqual(out["next"]["name"], "Singapore Grand Prix")
        self.assertEqual(out["last"]["results"][0]["colour"], "00D7B6")
        self.assertEqual(out["drivers"][0]["colour"], "00D7B6")
        self.assertEqual(out["teams"][0]["colour"], "00D7B6")
        self.assertEqual(out["teams"][1]["colour"], "")
        self.assertIsNone(out["live"])
        self.assertEqual(out["pollMs"], f1.IDLE_POLL_MS)
        self.assertNotIn(f1.OPENF1 + "position?session_key=9001", calls)

    def test_live_session(self):
        fetch, calls = routes()
        now = 1790933400 + 1200  # twenty minutes into FP1
        out = f1.collect(now, fetch, self.folder)
        self.assertEqual(out["live"]["session"], "FP1")
        self.assertEqual(out["live"]["name"], "Practice 1")
        self.assertEqual([r["code"] for r in out["live"]["order"]], ["VER", "ANT", "RUS"])
        self.assertFalse(out["live"]["finished"])
        self.assertEqual(out["pollMs"], f1.LIVE_POLL_MS)

    def test_a_locked_session_waits_and_polls_slowly(self):
        locked = f1.F1Error("answered 401", 401)
        fetch, calls = routes({f1.OPENF1 + "sessions?session_key=latest": locked})
        out = f1.collect(1790933400 + 1200, fetch, self.folder)
        self.assertEqual(out["locked"], {"session": "FP1"})
        self.assertIsNone(out["live"])
        self.assertEqual(out["pollMs"], f1.LOCKED_POLL_MS)
        self.assertNotIn(f1.OPENF1 + "position?session_key=9001", calls)

    def test_a_lock_after_an_earlier_session_keeps_its_colors(self):
        fetch, _ = routes()
        f1.collect(1790500000, fetch, self.folder)
        locked, calls = routes({f1.OPENF1 + "sessions?session_key=latest": f1.F1Error("answered 401", 401)})
        out = f1.collect(1790933400 + 1200, locked, self.folder)
        self.assertEqual(out["locked"], {"session": "FP1"})
        self.assertEqual(out["drivers"][0]["colour"], "00D7B6")
        self.assertNotIn(f1.OPENF1 + "position?session_key=9001", calls)

    def test_a_finished_session_shows_its_final_order(self):
        fetch, _ = routes()
        end = 1790937000  # FP1 ends 10:30 UTC
        out = f1.collect(end + 2 * 3600, fetch, self.folder)
        self.assertTrue(out["live"]["finished"])
        self.assertEqual(out["live"]["session"], "FP1")
        self.assertEqual([r["code"] for r in out["live"]["order"]], ["VER", "ANT", "RUS"])
        self.assertIsNone(out["locked"])
        later = f1.collect(end + f1.FINAL_KEEP + 60, fetch, self.folder)
        self.assertIsNone(later["live"])

    def test_a_session_from_another_weekend_is_not_shown(self):
        old = [{"session_key": 9001, "session_name": "Race", "date_start": "2026-09-26T11:00:00+00:00", "date_end": "2026-09-26T13:00:00+00:00"}]
        fetch, _ = routes({f1.OPENF1 + "sessions?session_key=latest": old})
        # An hour after that race ended: recent, but not this weekend's.
        out = f1.collect(1790431200, fetch, self.folder)
        self.assertIsNone(out["live"])

    def test_weekend_name(self):
        sessions = [{"name": "FP1", "start": 1000}, {"name": "Qualifying", "start": 90000}]
        self.assertEqual(f1.weekend_name(sessions, 1600), "FP1")
        self.assertEqual(f1.weekend_name(sessions, 50000), "")

    def test_season_is_cached(self):
        fetch, calls = routes()
        f1.collect(1790500000, fetch, self.folder)
        first = len([c for c in calls if c.startswith(f1.JOLPICA)])
        f1.collect(1790500000 + 60, fetch, self.folder)
        self.assertEqual(len([c for c in calls if c.startswith(f1.JOLPICA)]), first)

    def test_a_stale_season_stands_in_when_jolpica_is_down(self):
        fetch, _ = routes()
        f1.collect(1790500000, fetch, self.folder)
        down, _ = routes({f1.JOLPICA + "current/next.json": f1.F1Error("did not answer")})
        out = f1.collect(1790500000 + 30 * 86400, down, self.folder)
        self.assertTrue(out["ok"])
        self.assertEqual(out["next"]["round"], "16")

    def test_jolpica_down_with_no_cache(self):
        down, _ = routes({f1.JOLPICA + "current/next.json": f1.F1Error("did not answer")})
        out = f1.collect(1790500000, down, self.folder)
        self.assertEqual((out["ok"], out["error"]), (False, "Jolpica did not answer"))

    def test_openf1_down_leaves_the_rest(self):
        fetch, _ = routes({f1.OPENF1 + "sessions?session_key=latest": f1.F1Error("answered 500")})
        out = f1.collect(1790933400 + 1200, fetch, self.folder)
        self.assertTrue(out["ok"])
        self.assertIsNone(out["live"])
        self.assertEqual(out["drivers"][0]["colour"], "")


if __name__ == "__main__":
    unittest.main()
