import io
import json
import os
import subprocess
import sys
import time
import unittest
from contextlib import redirect_stdout
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

# The tile prints kickoff times on this computer's wall clock. Pin the zone so
# the expected strings below are the same on every machine.
os.environ["TZ"] = "UTC"
time.tzset()

import nfl
import sample

NOW = datetime(2026, 9, 27, 18, 0, tzinfo=timezone.utc)

KC = 12
LV = 13
DEN = 7
LAR = 14

STATUS_LIVE = {
    "period": 2,
    "displayClock": "6:33",
    "clock": 393.0,
    "type": {
        "id": "2",
        "name": "STATUS_IN_PROGRESS",
        "state": "in",
        "completed": False,
        "detail": "6:33 - 2nd Quarter",
        "shortDetail": "6:33 - 2nd",
    },
}

STATUS_POST = {
    "period": 4,
    "displayClock": "0:00",
    "clock": 0.0,
    "type": {
        "id": "3",
        "name": "STATUS_FINAL",
        "state": "post",
        "completed": True,
        "detail": "Final",
        "shortDetail": "Final",
    },
}

STATUS_PRE = {
    "period": 0,
    "displayClock": "0:00",
    "clock": 0.0,
    "type": {
        "id": "1",
        "name": "STATUS_SCHEDULED",
        "state": "pre",
        "completed": False,
        "detail": "Sun 1:00 PM",
        "shortDetail": "1/25 1:00 PM",
    },
}


def competitor(team_id, abbr, home_away, score, record="0-0", winner=None):
    return {
        "homeAway": home_away,
        "score": score,
        "winner": winner,
        "records": [
            {"name": "overall", "abbreviation": "Any", "type": "total", "summary": record},
        ],
        "team": {
            "id": str(team_id),
            "abbreviation": abbr,
            "displayName": abbr,
            "location": abbr,
            "name": abbr,
        },
    }


def event(event_id, kickoff, away, home, status, situation=None, broadcasts=None,
          neutral=False, season_type=2, week=3, season_year=2026):
    competition = {
        "id": event_id,
        "neutralSite": neutral,
        "broadcasts": broadcasts if broadcasts is not None else [],
        "competitors": [competitor(*away), competitor(*home)],
        "status": status,
    }
    if situation is not None:
        competition["situation"] = situation
    return {
        "id": event_id,
        "uid": "s:40~l:" + event_id,
        "date": kickoff,
        "name": away[1] + " at " + home[1],
        "season": {"year": season_year, "type": season_type, "slug": "regular-season"},
        "week": {"number": week},
        "status": status,
        "competitions": [competition],
    }


DRIVE = {
    "down": 2,
    "yardLine": 20,
    "distance": 15,
    "downDistanceText": "2nd & 15 at DEN 20",
    "shortDownDistanceText": "2nd & 15",
    "possessionText": "DEN 20",
    "isRedZone": True,
    "possession": str(DEN),
    "lastPlay": {
        "id": "4018729621639",
        "type": {"id": "3", "text": "Pass Incompletion"},
        "text": " (Shotgun) M.Stafford pass incomplete short left to B.Corum (M.Roach).",
    },
}

# A live Rams-Broncos game, one day after NOW, in week 3.
LIVE = event(
    "401872962", "2026-09-28T00:20Z",
    (LAR, "LAR", "away", "10", "1-1", None),
    (DEN, "DEN", "home", "0", "1-1", None),
    STATUS_LIVE, situation=DRIVE,
    broadcasts=[{"market": "national", "names": ["NBC"]}])

# A Chiefs game the club has already played, and one it has not.
KC_FINAL = event(
    "401872900", "2026-09-21T00:20Z",
    (KC, "KC", "away", "24", "2-0", True),
    (15, "MIA", "home", "10", "1-2", False),
    STATUS_POST, week=2)

KC_NEXT = event(
    "401872976", "2026-10-04T20:25Z",
    (LV, "LV", "home", None, "0-3", None),
    (KC, "KC", "away", None, "3-0", None),
    STATUS_PRE, week=4,
    broadcasts=[{"market": "national", "names": ["FOX"]}])

# A finished game from earlier today: fresh enough to show as a final.
LV_FRESH = event(
    "401872800", "2026-09-27T14:00Z",
    (LV, "LV", "away", "20", "2-2", True),
    (16, "MIN", "home", "17", "2-2", False),
    STATUS_POST, week=3)

# A finished game from last month: too old to keep on the tile.
LV_OLD = event(
    "401872700", "2026-09-13T17:00Z",
    (LV, "LV", "away", "10", "1-3", False),
    (25, "SF", "home", "24", "3-0", True),
    STATUS_POST, week=1)


def standings(entries):
    return {
        "children": [
            {
                "name": "American Football Conference",
                "abbreviation": "AFC",
                "standings": {"entries": entries},
            },
            {
                "name": "National Football Conference",
                "abbreviation": "NFC",
                "standings": {"entries": []},
            },
        ]
    }


def parsed(events, team_id=0, now=NOW):
    """What the collector hands to build(): parsed games, not raw events."""
    return [game for game in (nfl.parse_game(e, now, team_id) for e in events) if game]


def entry(team_id, abbr, seed, streak, rank_stats=None):
    stats = {"playoffSeed": str(seed), "streak": streak, "overall": "3-0"}
    stats.update(rank_stats or {})
    return {
        "team": {"id": str(team_id), "abbreviation": abbr, "displayName": abbr},
        "stats": [
            {"name": name, "displayValue": value}
            for name, value in sorted(stats.items())
        ],
    }


class GameParsingTest(unittest.TestCase):
    def test_live_game_reports_quarter_clock_and_drive(self):
        game = nfl.parse_game(LIVE, NOW, KC)
        self.assertEqual(game["away"]["abbr"], "LAR")
        self.assertEqual(game["home"]["abbr"], "DEN")
        self.assertEqual(game["awayScore"], 10)
        self.assertEqual(game["homeScore"], 0)
        self.assertTrue(game["live"])
        self.assertEqual(game["quarter"], "2nd")
        self.assertEqual(game["clock"], "6:33")
        self.assertEqual(game["time"], "2nd 6:33")
        # The three numbers that turn a pair of scores into a game.
        self.assertEqual(game["down"], 2)
        self.assertEqual(game["distance"], 15)
        self.assertEqual(game["downDistance"], "2nd & 15")
        self.assertEqual(game["ball"], "DEN 20")
        self.assertEqual(game["possession"], "DEN")
        self.assertTrue(game["redZone"])
        self.assertIn("pass incomplete", game["lastPlay"])
        self.assertEqual(game["network"], "NBC")
        self.assertEqual(game["away"]["record"], "1-1")
        self.assertEqual(game["away"]["color"], "#003594")

    def test_pregame_game_has_kickoff_and_no_drive(self):
        game = nfl.parse_game(KC_NEXT, NOW, KC)
        self.assertEqual(game["state"], "pre")
        self.assertFalse(game["live"])
        self.assertIsNone(game["down"])
        self.assertEqual(game["downDistance"], "")
        self.assertEqual(game["time"], "Oct 4 8:25 PM")
        self.assertEqual(game["favorite"], "away")
        self.assertIsNone(game["awayScore"])
        self.assertEqual(game["network"], "FOX")

    def test_final_game_reports_the_winner(self):
        game = nfl.parse_game(KC_FINAL, NOW, KC)
        self.assertTrue(game["finished"])
        self.assertEqual(game["time"], "FINAL")
        self.assertEqual(game["won"], "away")
        # A final reads FINAL, so the quarter is not reported.
        self.assertEqual(game["quarter"], "")
        self.assertEqual(game["clock"], "")

    def test_game_url_matches_nfl_com(self):
        game = nfl.parse_game(LIVE, NOW, KC)
        self.assertEqual(game["url"],
                         "https://www.nfl.com/games/rams-at-broncos-2026-reg-3")
        self.assertEqual(
            nfl.game_url(nfl.TEAMS[LV], nfl.TEAMS[KC], 2026, nfl.POST, 1),
            "https://www.nfl.com/games/raiders-at-chiefs-2026-post-1")
        self.assertEqual(
            nfl.game_url(nfl.TEAMS[LV], nfl.TEAMS[KC], 2026, nfl.PRE, 2),
            "https://www.nfl.com/games/raiders-at-chiefs-2026-pre-2")

    def test_game_url_refuses_an_unknown_season_or_week(self):
        self.assertEqual(nfl.game_url(nfl.TEAMS[LV], nfl.TEAMS[KC], 2026, 9, 1), "")
        self.assertEqual(nfl.game_url(nfl.TEAMS[LV], nfl.TEAMS[KC], 2026, nfl.REGULAR, 0), "")
        self.assertEqual(nfl.game_url(None, nfl.TEAMS[KC], 2026, nfl.REGULAR, 1), "")

    def test_neutral_site_and_unknown_clubs_are_survivable(self):
        neutral = event(
            "401872600", "2026-01-11T18:00Z",
            (2, "BUF", "away", "27", None, None),
            (30, "JAX", "home", "21", None, None),
            STATUS_POST, neutral=True, season_type=3, week=1)
        game = nfl.parse_game(neutral, datetime(2026, 1, 12, tzinfo=timezone.utc), KC)
        self.assertTrue(game["neutral"])
        self.assertEqual(game["quarter"], "")
        # Postseason paths are built, not guessed at click time.
        self.assertEqual(game["url"], "https://www.nfl.com/games/bills-at-jaguars-2026-post-1")

        unknown = event(
            "401872500", "2026-09-27T14:00Z",
            (900, "XXX", "away", "7", "0-0", None),
            (901, "YYY", "home", "3", "0-0", None),
            STATUS_POST)
        game = nfl.parse_game(unknown, NOW, KC)
        self.assertEqual(game["away"]["abbr"], "XXX")
        self.assertEqual(game["awayScore"], 7)
        # An unknown club has no NFL.com path, so the link falls back to the
        # safe team page rather than a URL that cannot exist.
        self.assertTrue(game["url"].startswith("https://www.nfl.com/teams/"))

    def test_broken_events_are_dropped(self):
        self.assertIsNone(nfl.parse_game(None, NOW, KC))
        self.assertIsNone(nfl.parse_game({}, NOW, KC))
        self.assertIsNone(nfl.parse_game({"competitions": []}, NOW, KC))
        one_sided = {"competitions": [{"competitors": [competitor(KC, "KC", "home", "1")]}]}
        self.assertIsNone(nfl.parse_game(one_sided, NOW, KC))


class LabelTest(unittest.TestCase):
    def test_clock_and_quarter(self):
        self.assertEqual(nfl.clock_label(393), "6:33")
        self.assertEqual(nfl.clock_label(59), "0:59")
        self.assertEqual(nfl.clock_label(900), "15:00")
        self.assertEqual(nfl.clock_label(0), "0:00")
        self.assertEqual(nfl.clock_label(None), "")
        self.assertEqual(nfl.clock_label("bad"), "")

        self.assertEqual(nfl.quarter_label(1), "1st")
        self.assertEqual(nfl.quarter_label(4), "4th")
        self.assertEqual(nfl.quarter_label(5), "OT")
        self.assertEqual(nfl.quarter_label(6), "2OT")
        self.assertEqual(nfl.quarter_label(0), "")

    def test_down_and_distance(self):
        self.assertEqual(nfl.down_label(1, 10), "1st & 10")
        self.assertEqual(nfl.down_label(2, 15), "2nd & 15")
        self.assertEqual(nfl.down_label(3, 4), "3rd & 4")
        self.assertEqual(nfl.down_label(4, 1), "4th & 1")
        self.assertEqual(nfl.down_label(4, 0), "4th & Goal")
        self.assertEqual(nfl.down_label(0, 10), "")

    def test_day_and_kickoff_labels(self):
        today = datetime(2026, 9, 27, 16, 25, tzinfo=timezone.utc)
        tomorrow = datetime(2026, 9, 28, 16, 25, tzinfo=timezone.utc)
        self.assertEqual(nfl.hour_label(today, NOW), "4:25 PM")
        self.assertEqual(nfl.hour_label(datetime(2026, 9, 27, 9, 5, tzinfo=timezone.utc), NOW), "9:05 AM")
        self.assertEqual(nfl.hour_label(datetime(2026, 9, 27, 12, 0, tzinfo=timezone.utc), NOW), "12 PM")
        self.assertEqual(nfl.day_label(today, NOW), "TODAY")
        self.assertEqual(nfl.day_label(tomorrow, NOW), "TOM")
        self.assertEqual(nfl.day_label(datetime(2026, 10, 1, tzinfo=timezone.utc), NOW), "THU")
        self.assertEqual(nfl.day_label(datetime(2026, 12, 25, tzinfo=timezone.utc), NOW), "Dec 25")
        self.assertEqual(nfl.day_label(None, NOW), "")

    def test_stamp_parsing_survives_shapes(self):
        self.assertEqual(nfl.parse_stamp("2026-09-28T00:20Z"),
                         datetime(2026, 9, 28, 0, 20, tzinfo=timezone.utc))
        self.assertEqual(nfl.parse_stamp("2026-09-28T00:20:00+00:00"),
                         datetime(2026, 9, 28, 0, 20, tzinfo=timezone.utc))
        naive = nfl.parse_stamp("2026-09-28T00:20:00")
        self.assertEqual(naive.tzinfo, timezone.utc)
        self.assertIsNone(nfl.parse_stamp("not a date"))
        self.assertIsNone(nfl.parse_stamp(""))
        self.assertIsNone(nfl.parse_stamp(None))


class ScheduleTest(unittest.TestCase):
    def test_record_comes_from_played_games_without_a_status(self):
        # A club's schedule sends no status at all, so the calendar decides
        # which games are done. That is the path that produced a 0-0 record.
        schedule = {
            "season": {"year": 2026, "type": 2, "name": "Regular Season"},
            "byeWeek": 5,
            "events": [
                {k: v for k, v in KC_FINAL.items() if k != "status"},
                {k: v for k, v in event(
                    "401872901", "2026-09-14T00:20Z",
                    (KC, "KC", "away", "21", None, True),
                    (30, "JAX", "home", "24", None, False),
                    STATUS_POST, week=1).items() if k != "status"},
                {k: v for k, v in KC_NEXT.items() if k != "status"},
            ],
        }
        context = nfl.parse_schedule(schedule, KC, NOW)
        self.assertEqual(context["season"], 2026)
        self.assertEqual(context["record"], "1-1")
        self.assertEqual(context["games"], 2)
        self.assertEqual(context["pointsFor"], 45)
        self.assertEqual(context["pointsAgainst"], 34)
        self.assertEqual(context["differential"] if "differential" in context else 11, 11)
        self.assertEqual(context["streak"], "W1")
        self.assertEqual(context["last"]["id"], "401872900")
        self.assertIsNotNone(context["next"])
        self.assertEqual(context["next"]["id"], "401872976")
        self.assertEqual(context["byeWeek"], 5)

    def test_ties_are_counted_and_shown(self):
        schedule = {"season": {"year": 2026}, "events": [
            {k: v for k, v in event(
                "1", "2026-09-14T00:20Z",
                (KC, "KC", "away", "21", None, None),
                (30, "JAX", "home", "21", None, None),
                STATUS_POST, week=1).items() if k != "status"}]}
        context = nfl.parse_schedule(schedule, KC, NOW)
        self.assertEqual(context["record"], "0-0-1")
        self.assertEqual(context["ties"], 1)
        self.assertEqual(context["streak"], "T1")

    def test_streak_counts_the_current_run(self):
        self.assertEqual(nfl.streak_text(["W", "W", "W", "L", "W", "W"]), "W2")
        self.assertEqual(nfl.streak_text(["L", "L"]), "L2")
        self.assertEqual(nfl.streak_text(["W", "T", "W"]), "W1")
        self.assertEqual(nfl.streak_text([]), "")

    def test_junk_schedules_do_not_raise(self):
        for payload in (None, {}, {"events": None}, {"events": [{}, None, 7]},
                        {"events": [{"competitions": []}]}):
            context = nfl.parse_schedule(payload, KC, NOW)
            self.assertEqual(context["record"], "")
            self.assertIsNone(context["next"])
            self.assertEqual(context["games"], 0)


class StandingsTest(unittest.TestCase):
    def test_seed_and_place_come_from_the_conference_list(self):
        table = standings([
            entry(LV, "LV", 5, "L1"),
            entry(KC, "KC", 1, "W3"),
        ])
        row = nfl.parse_standings(table, KC)
        self.assertEqual(row["seed"], 1)
        self.assertEqual(row["conference"], "AFC")
        self.assertEqual(row["conferenceRank"], 2)
        self.assertEqual(row["streak"], "W3")
        self.assertEqual(row["divisionName"], "AFC West")

    def test_a_missing_or_empty_standings_call_is_harmless(self):
        for payload in (None, {}, {"children": []}, {"children": [{"standings": {}}]}):
            row = nfl.parse_standings(payload, KC)
            self.assertEqual(row["seed"], 0)
            self.assertEqual(row["streak"], "")
        self.assertEqual(nfl.parse_standings(standings([]), 0)["seed"], 0)


class ViewTest(unittest.TestCase):
    def test_live_mode_focuses_on_the_club_game(self):
        view = nfl.build(parsed([LIVE], DEN), None, None, DEN, NOW)
        self.assertEqual(view["mode"], "live")
        self.assertEqual(view["reason"], "live")
        self.assertEqual(view["focus"]["id"], "401872962")
        self.assertEqual(view["focus"]["favorite"], "home")
        self.assertEqual(view["pollMs"], nfl.POLL_LIVE_MS)
        self.assertEqual(view["summary"], "")

    def test_other_games_go_to_the_slate_behind_the_club(self):
        view = nfl.build(parsed([LIVE], KC), None, None, KC, NOW)
        self.assertEqual(view["mode"], "board")
        self.assertEqual(view["summary"], "")
        # Live games lead the list.
        self.assertEqual(view["games"][0]["id"], "401872962")
        self.assertEqual(view["pollMs"], nfl.POLL_LIVE_MS)
        self.assertLessEqual(len(view["games"]), 8)

    def test_board_mode_without_a_club_sorts_live_first(self):
        view = nfl.build(parsed([LV_OLD, KC_FINAL, LIVE]), None, None, 0, NOW)
        self.assertEqual(view["mode"], "board")
        self.assertIsNone(view["focus"])
        self.assertIsNone(view["team"])
        self.assertEqual(view["games"][0]["id"], "401872962")
        self.assertEqual(view["games"][1]["id"], "401872700")

    def test_fresh_final_stays_on_the_tile_then_gives_way(self):
        view = nfl.build(parsed([LV_FRESH], LV), None, None, LV, NOW)
        self.assertEqual(view["mode"], "final")
        self.assertEqual(view["focus"]["id"], "401872800")
        self.assertEqual(view["reason"], "final")

        stale = nfl.build(parsed([LV_OLD], LV), None, None, LV, NOW)
        self.assertNotEqual(stale["mode"], "final")

    def test_upcoming_comes_from_the_schedule(self):
        schedule = {"season": {"year": 2026}, "events": [
            {k: v for k, v in KC_FINAL.items() if k != "status"},
            {k: v for k, v in KC_NEXT.items() if k != "status"}]}
        view = nfl.build(parsed([KC_FINAL], KC), schedule, None, KC, NOW)
        self.assertEqual(view["mode"], "upcoming")
        self.assertEqual(view["reason"], "schedule")
        self.assertEqual(view["focus"]["id"], "401872976")
        self.assertEqual(view["next"]["id"], "401872976")
        self.assertEqual(view["team"]["record"], "1-0")
        self.assertEqual(view["team"]["abbr"], "KC")
        self.assertEqual(view["team"]["divisionName"], "AFC West")
        self.assertEqual(view["pollMs"], nfl.POLL_IDLE_MS)

    def test_closed_when_the_season_has_nothing_left(self):
        schedule = {"season": {"year": 2026}, "events": [
            {k: v for k, v in LV_OLD.items() if k != "status"}]}
        view = nfl.build([], schedule, None, LV, NOW)
        self.assertEqual(view["mode"], "closed")
        self.assertEqual(view["summary"], "Season complete")
        self.assertEqual(view["pollMs"], nfl.POLL_OFF_MS)
        self.assertEqual(view["team"]["record"], "0-1")
        self.assertIsNone(view["focus"])

    def test_a_playoff_game_the_schedule_cannot_see_still_counts(self):
        # Playoff games are not in a club's regular-season schedule, so the
        # slate is the only place they can come from.
        playoff = event(
            "401872600", "2026-01-11T18:00Z",
            (2, "BUF", "away", None, None, None),
            (30, "JAX", "home", None, None, None),
            STATUS_PRE, season_type=3, week=1)
        early = datetime(2026, 1, 8, tzinfo=timezone.utc)
        view = nfl.build(parsed([playoff], 2, early), None, None, 2, early)
        self.assertEqual(view["mode"], "upcoming")
        self.assertEqual(view["focus"]["id"], "401872600")

    def test_empty_when_there_is_nothing_at_all(self):
        view = nfl.build([], None, None, 0, NOW)
        self.assertEqual(view["mode"], "empty")
        self.assertEqual(view["games"], [])
        self.assertEqual(view["pollMs"], nfl.POLL_OFF_MS)

    def test_the_view_never_carries_a_bad_link(self):
        for team_id in (0, KC):
            view = nfl.build(parsed([LIVE], team_id), None, None, team_id, NOW)
            for url in [view["standingsUrl"]] + [g["url"] for g in view["games"]]:
                self.assertTrue(url.startswith("https://www.nfl.com/"), url)


class CollectTest(unittest.TestCase):
    def test_a_club_costs_the_slate_and_its_own_schedule(self):
        calls = []

        def fake(url):
            calls.append(url)
            if url == nfl.SITE + "/scoreboard":
                return {"season": {"year": 2026, "type": 2}, "week": {"number": 3},
                        "events": [LIVE]}
            if "/teams/kc/schedule" in url:
                return {"season": {"year": 2026}, "events": [KC_NEXT]}
            raise AssertionError("unexpected call " + url)

        view = nfl.collect(KC, NOW, fake)
        self.assertTrue(view["ok"])
        self.assertEqual(view["mode"], "upcoming")
        self.assertEqual(len(calls), 2)
        self.assertIn("season=2026", calls[1])

    def test_standings_add_a_seed_when_the_club_is_idle(self):
        calls = []

        def fake(url):
            calls.append(url)
            if url == nfl.SITE + "/scoreboard":
                return {"season": {"year": 2026}, "events": [KC_FINAL]}
            if "/teams/kc/schedule" in url:
                return {"season": {"year": 2026}, "events": [KC_FINAL, KC_NEXT]}
            if url.startswith(nfl.STANDINGS_API):
                return standings([entry(KC, "KC", 1, "W3")])
            raise AssertionError("unexpected call " + url)

        view = nfl.collect(KC, NOW, fake)
        self.assertEqual(len(calls), 3)
        self.assertEqual(view["team"]["seed"], 1)
        self.assertEqual(view["team"]["conferenceRank"], 1)

    def test_standings_are_skipped_while_the_club_is_playing(self):
        calls = []

        def fake(url):
            calls.append(url)
            if url == nfl.SITE + "/scoreboard":
                return {"season": {"year": 2026}, "events": [LIVE]}
            if "/teams/den/schedule" in url:
                return {"season": {"year": 2026}, "events": [LIVE]}
            if url.startswith(nfl.STANDINGS_API):
                raise AssertionError("standings should be skipped mid-game")
            raise AssertionError("unexpected call " + url)

        view = nfl.collect(DEN, NOW, fake)
        self.assertEqual(view["mode"], "live")
        self.assertEqual(len(calls), 2)

    def test_no_club_costs_one_call(self):
        calls = []

        def fake(url):
            calls.append(url)
            return {"season": {"year": 2026}, "events": [LIVE, KC_FINAL]}

        view = nfl.collect(0, NOW, fake)
        self.assertEqual(len(calls), 1)
        self.assertEqual(view["mode"], "board")

    def test_a_dead_feed_becomes_an_error_not_a_crash(self):
        def failed(url):
            raise OSError("offline")

        view = nfl.collect(KC, NOW, failed)
        self.assertFalse(view["ok"])
        self.assertEqual(view["mode"], "empty")
        self.assertEqual(view["games"], [])
        # The club survives, so the tile can still name it and link its page.
        self.assertEqual(view["team"]["abbr"], "KC")
        self.assertEqual(view["team"]["record"], "")
        self.assertTrue(view["team"]["url"].startswith("https://www.nfl.com/teams/"))

        bare = nfl.collect(0, NOW, failed)
        self.assertFalse(bare["ok"])
        self.assertIsNone(bare["team"])

    def test_a_slide_without_teams_is_an_error(self):
        view = nfl.collect(0, NOW, lambda url: {"season": {"year": 2026}, "events": []})
        self.assertFalse(view["ok"])
        self.assertEqual(view["error"], "Scores unavailable")

    def test_garbage_from_the_feed_is_not_fatal(self):
        for payload in ({}, {"events": None}, {"events": [None, 7, {}]}, {"events": [{"id": "1"}]}):
            view = nfl.collect(0, NOW, lambda url, p=payload: p)
            self.assertIn(view["mode"], ("board", "empty"))
            self.assertIsInstance(view["games"], list)


class RequestGuardTest(unittest.TestCase):
    def test_only_the_expected_https_hosts_are_allowed(self):
        self.assertTrue(nfl.allowed_url(nfl.SITE + "/scoreboard"))
        self.assertTrue(nfl.allowed_url(nfl.STANDINGS_API + "?season=2026"))
        self.assertEqual(nfl.allowed_url("http://site.api.espn.com/x"), "")
        self.assertEqual(nfl.allowed_url("https://evil.example/scoreboard"), "")
        self.assertEqual(nfl.allowed_url("https://site.api.espn.com.evil.example/x"), "")
        self.assertEqual(nfl.allowed_url("file:///etc/passwd"), "")
        self.assertEqual(nfl.allowed_url(""), "")
        self.assertEqual(nfl.allowed_url(None), "")

    def test_the_guard_runs_before_the_shell_tool(self):
        with patch("nfl.subprocess.run") as run:
            with self.assertRaises(ValueError):
                nfl.fetch_json("https://evil.example/x")
        run.assert_not_called()


class CatalogTest(unittest.TestCase):
    def test_the_launcher_finds_this_widget(self):
        # The catalog is a directory scan, so a folder that is not wired up
        # simply never appears. This is the check that it does.
        here = os.path.dirname(os.path.abspath(__file__))
        widgets = os.path.dirname(here)
        script = os.path.join(os.path.dirname(widgets), "scripts", "list-widgets.py")
        rows = subprocess.run(
            [sys.executable, script, widgets],
            capture_output=True, text=True, timeout=30, check=True).stdout
        found = {row["id"]: row for row in json.loads(rows)}
        self.assertIn("nfl", found)
        row = found["nfl"]
        self.assertTrue(row["qml"].endswith("/widgets/nfl/Widget.qml"))
        self.assertTrue(row["settingsQml"].endswith("/widgets/nfl/Settings.qml"))
        self.assertTrue(os.path.isfile(row["qml"]))
        self.assertTrue(os.path.isfile(row["settingsQml"]))
        # Keys TileModel reads off widget.json.
        self.assertEqual(row["name"], "NFL")
        self.assertTrue(row["defaultUrl"].startswith("https://www.nfl.com"))
        self.assertTrue(row["defaultLabel"])
        self.assertTrue(row["icon"])
        self.assertTrue(row["description"])

    def test_every_club_is_listed_once_in_order(self):
        rows = nfl.catalog()
        self.assertEqual(len(rows), 32)
        self.assertEqual(len(nfl.TEAMS), 32)
        self.assertEqual(len(nfl.TEAM_IDS), 32)
        ids = [row["id"] for row in rows]
        self.assertEqual(len(set(ids)), 32)
        self.assertEqual(rows[0]["conference"], "AFC")
        self.assertEqual(rows[0]["divisionName"], "AFC East")
        self.assertEqual(rows[-1]["conference"], "NFC")
        self.assertEqual(rows[-1]["divisionName"], "NFC West")
        for row in rows:
            self.assertTrue(row["url"].startswith("https://www.nfl.com/teams/"))

    def test_the_table_is_internally_consistent(self):
        for row in nfl.TEAMS.values():
            self.assertIn(row["conference"], ("AFC", "NFC"))
            self.assertIn(row["division"], ("East", "North", "South", "West"))
            self.assertTrue(1 <= len(row["abbr"]) <= 3)
            for key in ("color", "alt"):
                self.assertRegex(row[key], r"^#[0-9a-f]{6}$")
            self.assertEqual(row["slug"], (row["city"] + "-" + row["nickname"]).lower().replace(" ", "-"))
            self.assertIs(nfl.team(row["id"]), row)
            self.assertIs(nfl.team_by_abbr(row["abbr"]), row)
        self.assertIsNone(nfl.team(0))
        self.assertIsNone(nfl.team(9999))
        self.assertIsNone(nfl.team_by_abbr("XXX"))
        # Every division holds four clubs.
        for conference in ("AFC", "NFC"):
            for division in ("East", "North", "South", "West"):
                count = sum(1 for row in nfl.TEAMS.values()
                            if row["conference"] == conference and row["division"] == division)
                self.assertEqual(count, 4)


class SampleTest(unittest.TestCase):
    def test_sample_passes_the_club_to_the_collector(self):
        output = io.StringIO()
        with patch("sample.nfl.collect", return_value={"ok": True}) as collect:
            with redirect_stdout(output):
                result = sample.main(["sample.py", "--team", "12"])
        self.assertEqual(result, 0)
        collect.assert_called_once()
        self.assertEqual(collect.call_args[0][0], 12)
        self.assertTrue(json.loads(output.getvalue())["ok"])

    def test_sample_serves_the_settings_catalog(self):
        output = io.StringIO()
        with redirect_stdout(output):
            result = sample.main(["sample.py", "--teams"])
        self.assertEqual(result, 0)
        payload = json.loads(output.getvalue())
        self.assertTrue(payload["ok"])
        self.assertEqual(len(payload["rows"]), 32)

    def test_sample_survives_a_raising_collector(self):
        output = io.StringIO()
        with patch("sample.nfl.collect", side_effect=RuntimeError("no route")):
            with redirect_stdout(output):
                result = sample.main(["sample.py", "--team", "12"])
        self.assertEqual(result, 0)
        payload = json.loads(output.getvalue())
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["error"], "no route")

    def test_a_bad_club_id_is_not_fatal(self):
        output = io.StringIO()
        with patch("sample.nfl.collect", return_value={"ok": True}) as collect:
            with redirect_stdout(output):
                sample.main(["sample.py", "--team", "junk"])
        self.assertEqual(collect.call_args[0][0], 0)


if __name__ == "__main__":
    unittest.main()
