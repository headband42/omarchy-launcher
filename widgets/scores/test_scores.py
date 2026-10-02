#!/usr/bin/env python3
"""Tests for the scores sampler. Stdlib only; curl is never run.

Run from the repo root:  python3 widgets/scores/test_scores.py
"""

import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import scores

PNG = b"\x89PNG\r\n\x1a\n" + b"0" * 20

TEAMS = {"sports": [{"leagues": [{"teams": [
    {"team": {"id": "17", "abbreviation": "COL", "displayName": "Colorado Avalanche", "shortDisplayName": "Avalanche", "color": "6f263d",
              "logos": [{"rel": ["full", "default"], "href": "https://a.espncdn.com/i/teamlogos/nhl/500/col.png"},
                        {"rel": ["full", "dark"], "href": "https://a.espncdn.com/i/teamlogos/nhl/500-dark/col.png"}]}},
    {"team": {"id": "19", "abbreviation": "STL", "displayName": "St. Louis Blues", "shortDisplayName": "Blues",
              "logos": [{"rel": ["full", "default"], "href": "https://a.espncdn.com/i/teamlogos/nhl/500/stl.png"}]}},
    {"team": {"id": "bad", "abbreviation": "X"}},
]}]}]}


def event(event_id, date, state, home, away, home_score=None, away_score=None, detail="", winner=None, link=True):
    def comp(team_id, abbr, side, score, win):
        out = {"homeAway": side, "team": {"id": team_id, "abbreviation": abbr}, "records": [{"summary": "1-0-0"}]}
        if score is not None:
            out["score"] = score
        if win is not None:
            out["winner"] = win
        return out
    return {
        "id": event_id, "date": date,
        "links": [{"rel": ["summary", "desktop", "event"], "href": "https://www.espn.com/nhl/game/_/gameId/%s" % event_id}] if link else [],
        "competitions": [{
            "status": {"type": {"state": state, "shortDetail": detail, "completed": state == "post"}},
            "competitors": [comp(home[0], home[1], "home", home_score, winner == "home" if winner else None),
                            comp(away[0], away[1], "away", away_score, winner == "away" if winner else None)],
            "broadcasts": [{"names": ["ESPN+"]}],
        }],
    }


class ParseTests(unittest.TestCase):
    def test_teams(self):
        teams = scores.parse_teams(TEAMS)
        self.assertEqual(sorted(teams), ["17", "19"])
        self.assertEqual(teams["17"]["logo"], "/i/teamlogos/nhl/500/col.png")
        self.assertEqual(teams["17"]["logoDark"], "/i/teamlogos/nhl/500-dark/col.png")
        self.assertEqual(teams["19"]["logoDark"], "")
        self.assertEqual(scores.parse_teams({}), {})

    def test_scores_as_strings_or_objects(self):
        board = scores.parse_game(event("1", "2026-10-01T23:00Z", "post", ("17", "COL"), ("19", "STL"), "6", "3", "Final", "home"), {})
        self.assertEqual((board["home"]["score"], board["away"]["score"]), ("6", "3"))
        self.assertEqual((board["home"]["winner"], board["away"]["winner"]), (True, False))
        schedule = scores.parse_game(event("2", "2026-10-01T23:00Z", "post", ("17", "COL"), ("19", "STL"),
                                           {"value": 2.0, "displayValue": "2"}, {"displayValue": "1"}, "FT"), {})
        self.assertEqual((schedule["home"]["score"], schedule["away"]["score"]), ("2", "1"))

    def test_a_game_not_started_has_no_score(self):
        game = scores.parse_game(event("3", "2026-10-04T01:00Z", "pre", ("17", "COL"), ("19", "STL"), "0", "0", "10/3 - 9:00 PM EDT"), {})
        self.assertIsNone(game["home"]["score"])
        self.assertEqual(game["start"], 1791075600)
        self.assertEqual(game["network"], "ESPN+")
        self.assertFalse(game["tbd"])

    def test_tbd_and_bad_events(self):
        game = scores.parse_game(event("4", "2026-10-04T01:00Z", "pre", ("1", "A"), ("2", "B"), detail="TBD"), {})
        self.assertTrue(game["tbd"])
        self.assertIsNone(scores.parse_game({"competitions": []}, {}))
        self.assertIsNone(scores.parse_game(event("5", "x", "weird", ("1", "A"), ("2", "B")), {}))

    def test_links_must_be_espn(self):
        bad = event("6", "2026-10-04T01:00Z", "pre", ("1", "A"), ("2", "B"))
        bad["links"][0]["href"] = "https://evil.example/x"
        self.assertEqual(scores.parse_game(bad, {})["link"], "")


class FeaturedTests(unittest.TestCase):
    NOW = 1_790_900_000

    def game(self, state, offset):
        return {"id": state + str(offset), "state": state, "start": self.NOW + offset}

    def test_live_wins(self):
        games = [self.game("post", -3600), self.game("in", -1800), self.game("pre", 3600)]
        self.assertEqual(scores.featured_game(games, self.NOW)["state"], "in")

    def test_a_fresh_final_beats_the_next_game(self):
        games = [self.game("post", -5 * 3600), self.game("pre", 86400)]
        self.assertEqual(scores.featured_game(games, self.NOW)["state"], "post")

    def test_an_old_final_gives_way_to_the_next_game(self):
        games = [self.game("post", -30 * 3600), self.game("pre", 2 * 86400), self.game("pre", 86400)]
        self.assertEqual(scores.featured_game(games, self.NOW)["start"], self.NOW + 86400)

    def test_season_over_shows_the_last_game(self):
        games = [self.game("post", -90 * 86400), self.game("post", -60 * 86400)]
        self.assertEqual(scores.featured_game(games, self.NOW)["start"], self.NOW - 60 * 86400)
        self.assertIsNone(scores.featured_game([], self.NOW))


class CollectTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.folder = self.dir.name

    def tearDown(self):
        self.dir.cleanup()

    def fetcher(self, routes):
        self.calls = []

        def fetch(url):
            self.calls.append(url)
            if url not in routes:
                raise OSError("404")
            return json.dumps(routes[url])
        return fetch

    def test_slate_with_a_team_and_logos(self):
        site = scores.SITE + "hockey/nhl"
        board = {"day": {"date": "2026-10-01"}, "events": [
            event("10", "2026-10-01T23:00Z", "post", ("19", "STL"), ("17", "COL"), "2", "4", "Final", "away"),
            event("11", "2026-10-02T01:00Z", "in", ("5", "BUF"), ("6", "CBJ"), "1", "1", "2nd 10:21"),
        ]}
        schedule = {"events": [event("12", "2026-10-04T01:00Z", "pre", ("17", "COL"), ("19", "STL")),
                               event("10", "2026-10-01T23:00Z", "post", ("19", "STL"), ("17", "COL"), {"displayValue": "1"}, {"displayValue": "4"}, "Final")]}
        fetch = self.fetcher({site + "/teams?limit=1000": TEAMS, site + "/scoreboard": board, site + "/teams/17/schedule": schedule})
        logos = []

        def logo_fetch(url):
            logos.append(url)
            return PNG

        now = 1790900000 + 3600  # two hours after the COL final started
        out = scores.collect("nhl", "17", now, fetch, logo_fetch, self.folder)
        self.assertEqual(out["team"]["name"], "Colorado Avalanche")
        self.assertEqual(out["featured"]["id"], "10")
        self.assertEqual(out["featured"]["home"]["score"], "2", "the scoreboard's copy wins over the schedule's")
        self.assertEqual([g["id"] for g in out["games"]], ["11"])
        self.assertEqual(out["live"], 1)
        self.assertEqual(out["pollMs"], scores.LIVE_POLL_MS)
        self.assertTrue(out["featured"]["away"]["logo"].endswith("/logos/nhl/17.png"))
        self.assertTrue(out["featured"]["away"]["logoDark"].endswith("/logos/nhl/17-dark.png"))
        self.assertEqual(out["featured"]["home"]["logoDark"], "")
        self.assertEqual(len(logos), 3)
        self.assertTrue(all(u.startswith("https://a.espncdn.com/combiner/i?img=/i/teamlogos/") for u in logos))
        # Logos already on disk are not fetched again.
        logos.clear()
        scores.collect("nhl", "17", now, fetch, logo_fetch, self.folder)
        self.assertEqual(logos, [])

    def test_soccer_reads_results_and_fixtures(self):
        site = scores.SITE + "soccer/eng.1"
        fixture = {"events": [event("20", "2026-10-10T11:30Z", "pre", ("359", "ARS"), ("357", "LEE"))]}
        fetch = self.fetcher({site + "/teams?limit=1000": {}, site + "/scoreboard": {"events": []},
                              site + "/teams/359/schedule": {"events": []}, site + "/teams/359/schedule?fixture=true": fixture})
        out = scores.collect("epl", "359", 1790900000, fetch, lambda url: PNG, self.folder)
        self.assertEqual(out["featured"]["id"], "20")
        self.assertIn(site + "/teams/359/schedule?fixture=true", self.calls)

    def test_espn_down(self):
        out = scores.collect("nba", "", 0, self.fetcher({}), lambda url: PNG, self.folder)
        self.assertEqual((out["ok"], out["error"]), (False, "ESPN did not answer"))

    def test_bad_input_falls_back(self):
        site = scores.SITE + "basketball/nba"
        fetch = self.fetcher({site + "/scoreboard": {"events": []}})
        out = scores.collect("../../etc", "17; rm", 0, fetch, lambda url: PNG, self.folder)
        self.assertEqual(out["league"]["id"], "nba")
        self.assertIsNone(out["team"])

    def test_logo_that_is_not_a_png_is_not_saved(self):
        teams = scores.parse_teams(TEAMS)
        out = scores.ensure_logos("nhl", ["17"], teams, lambda url: b"<html>", self.folder)
        self.assertEqual(out["17"], {"logo": "", "logoDark": ""})

    def test_team_and_league_lists(self):
        site = scores.SITE + "hockey/nhl"
        out = scores.team_list("nhl", 0, self.fetcher({site + "/teams?limit=1000": TEAMS}), self.folder)
        self.assertEqual([t["abbr"] for t in out["teams"]], ["COL", "STL"])
        self.assertFalse(scores.team_list("nope")["ok"])
        self.assertIn({"id": "nhl", "name": "NHL"}, scores.league_list()["leagues"])


class CurlTests(unittest.TestCase):
    def test_refuses_unexpected_urls(self):
        for url in ("https://evil.example/x", "file:///etc/passwd", "https://site.api.espn.com/other/path", "https://a.espncdn.com/x y"):
            with self.assertRaises(ValueError):
                scores.curl(url)


if __name__ == "__main__":
    unittest.main()
