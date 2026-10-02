import copy
import json
import os
import stat
import tempfile
import unittest
from datetime import datetime, timezone

import fantasy

NOW = int(datetime(2026, 10, 4, 17, 0, tzinfo=timezone.utc).timestamp() * 1000)
HOUR = 3600 * 1000
DAY = 24 * HOUR


class FakeNet:
    """Answers by the first route whose text is in the URL. Nothing here
    reaches the network; an unrouted URL fails the test."""

    def __init__(self, routes):
        self.routes = routes
        self.calls = []

    def __call__(self, url, headers=None, data=None):
        self.calls.append({"url": url, "headers": dict(headers or {}), "data": data})
        for pattern, reply in self.routes:
            if pattern in url:
                if isinstance(reply, Exception):
                    raise reply
                return copy.deepcopy(reply(url) if callable(reply) else reply)
        raise AssertionError("unrouted URL " + url)

    def urls(self, text):
        return [call["url"] for call in self.calls if text in call["url"]]


def club(espn_id, abbrev, bye, weeks):
    return {
        "id": espn_id,
        "abbrev": abbrev,
        "byeWeek": bye,
        "proGamesByScoringPeriod": {str(week): [{"date": kickoff}] for week, kickoff in weeks.items()},
    }


# Week 4, Sunday 17:00 UTC: Dallas kicked off an hour ago, San Francisco is
# final, Philadelphia, Washington and Chicago are still to play, Kansas City
# is on its bye.
SCHEDULE = {"settings": {"proTeams": [
    club(0, "FA", 0, {}),
    club(21, "PHI", 10, {3: NOW - 7 * DAY, 4: NOW + 3 * HOUR}),
    club(6, "DAL", 14, {4: NOW - HOUR}),
    club(25, "SF", 8, {4: NOW - 6 * HOUR}),
    club(12, "KC", 4, {3: NOW - 7 * DAY, 5: NOW + 7 * DAY}),
    club(28, "WSH", 7, {4: NOW + 3 * HOUR}),
    club(3, "CHI", 5, {4: NOW + 3 * HOUR}),
]}}


def schedule():
    return fantasy.parse_schedule(SCHEDULE, 2026)


class TempHome(unittest.TestCase):
    """Cache and sign-in files go to a temporary folder, never the real ones."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.saved_env = {k: os.environ.get(k) for k in ("XDG_CACHE_HOME", "XDG_CONFIG_HOME")}
        os.environ["XDG_CACHE_HOME"] = os.path.join(self.tmp.name, "cache")
        os.environ["XDG_CONFIG_HOME"] = os.path.join(self.tmp.name, "config")

    def tearDown(self):
        for key, value in self.saved_env.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        self.tmp.cleanup()

    def ctx(self, net, auth=None):
        context = fantasy.Context(net, NOW, auth if auth is not None else {})
        context.schedule = schedule()
        return context


class SmallValues(unittest.TestCase):
    def test_team_codes_from_every_platform(self):
        self.assertEqual(fantasy.team_code("Wsh"), "WAS")
        self.assertEqual(fantasy.team_code("GBP"), "GB")
        self.assertEqual(fantasy.team_code("JAC"), "JAX")
        self.assertEqual(fantasy.team_code("lvr"), "LV")
        self.assertEqual(fantasy.team_code("Phi"), "PHI")
        self.assertEqual(fantasy.team_code("FA"), "")
        self.assertEqual(fantasy.team_code(None), "")

    def test_injury_designations(self):
        cases = {
            "Out": "out", "O": "out", "PUP-R": "out", "NA": "out", "COV": "out",
            "IR": "ir", "INJURY_RESERVE": "ir", "IR-R": "ir",
            "Sus": "suspended", "SUSPENSION": "suspended",
            "D": "doubtful", "DOUBTFUL": "doubtful",
            "Q": "questionable", "Questionable": "questionable", "DAY_TO_DAY": "questionable",
            "ACTIVE": None, "NORMAL": None, "P": None, "": None, None: None,
        }
        for value, kind in cases.items():
            self.assertEqual(fantasy.injury_kind(value), kind, value)

    def test_short_names(self):
        self.assertEqual(fantasy.short_name("George Kittle"), "Kittle")
        self.assertEqual(fantasy.short_name("Amon-Ra St. Brown Jr."), "St. Brown")
        self.assertEqual(fantasy.short_name("Odell Beckham Jr."), "Beckham")
        self.assertEqual(fantasy.short_name("Eagles", "DEF", "PHI"), "PHI D/ST")
        self.assertEqual(fantasy.flip_name("Hurts, Jalen"), "Jalen Hurts")

    def test_records_and_rank(self):
        self.assertEqual(fantasy.record_text(3, 1, 0), "3-1")
        self.assertEqual(fantasy.record_text("2", "1", "1"), "2-1-1")
        rows = [("a", 2, 1, 0, 300), ("b", 2, 1, 0, 320), ("c", 3, 0, 0, 100)]
        self.assertEqual(fantasy.rank_of("c", rows), 1)
        self.assertEqual(fantasy.rank_of("b", rows), 2)
        self.assertEqual(fantasy.rank_of("a", rows), 3)
        self.assertIsNone(fantasy.rank_of("z", rows))

    def test_season_runs_into_february(self):
        jan = int(datetime(2027, 1, 20, tzinfo=timezone.utc).timestamp() * 1000)
        self.assertEqual(fantasy.current_season(jan), 2026)
        self.assertEqual(fantasy.current_season(NOW), 2026)

    def test_fantrax_dates(self):
        self.assertEqual(fantasy.parse_time_ms("2026-10-06T11:59:59.0-0400"),
                         int(datetime(2026, 10, 6, 15, 59, 59, tzinfo=timezone.utc).timestamp() * 1000))
        self.assertIsNone(fantasy.parse_time_ms("soon"))

    def test_mfl_single_items(self):
        self.assertEqual(fantasy.as_list({"id": "1"}), [{"id": "1"}])
        self.assertEqual(fantasy.as_list([{"id": "1"}]), [{"id": "1"}])
        self.assertEqual(fantasy.as_list(None), [])


class Entries(unittest.TestCase):
    def test_ids_that_could_change_a_url_are_dropped(self):
        bad = [
            {"p": "espn", "id": "123/../../x", "team": "1"},
            {"p": "espn", "id": "123", "team": "1&view=x"},
            {"p": "sleeper", "id": "abc", "team": "1"},
            {"p": "mfl", "id": "10005", "team": "1"},
            {"p": "cbs", "id": "1", "team": "1"},
            {"p": "yahoo", "id": "461.l.1;x", "team": "1"},
            "not an object",
        ]
        for entry in bad:
            self.assertIsNone(fantasy.clean_entry(entry), entry)

    def test_good_entries(self):
        self.assertEqual(fantasy.clean_entry({"p": "fantrax", "id": "W9DCE4PFJ19MXF1U", "team": "ABCD1234"}),
                         {"p": "fantrax", "id": "w9dce4pfj19mxf1u", "team": "abcd1234"})
        self.assertEqual(fantasy.clean_entry({"p": "sleeper", "id": "111", "team": "1", "user": "900", "name": "x"}),
                         {"p": "sleeper", "id": "111", "team": "1", "user": "900"})
        self.assertEqual(fantasy.clean_entry({"p": "yahoo", "id": "461.l.555", "team": "3"})["id"], "461.l.555")

    def test_duplicates_and_extra_leagues_are_dropped(self):
        rows = [{"p": "espn", "id": str(i), "team": "1"} for i in range(1, 10)]
        rows.insert(1, {"p": "espn", "id": "1", "team": "1"})
        out = fantasy.parse_entries(json.dumps(rows))
        self.assertEqual(len(out), fantasy.MAX_LEAGUES)
        self.assertEqual([e["id"] for e in out[:2]], ["1", "2"])
        self.assertEqual(fantasy.parse_entries("not json"), [])


class Schedule(unittest.TestCase):
    def test_parse(self):
        parsed = schedule()
        self.assertEqual(parsed["ids"]["28"], "WAS")
        self.assertNotIn("0", parsed["ids"])
        self.assertEqual(parsed["byes"]["KC"], 4)
        self.assertEqual(parsed["games"]["4"]["DAL"], NOW - HOUR)

    def test_states(self):
        parsed = schedule()
        self.assertEqual(fantasy.game_state(parsed, 4, "PHI", NOW), "pre")
        self.assertEqual(fantasy.game_state(parsed, 4, "DAL", NOW), "live")
        self.assertEqual(fantasy.game_state(parsed, 4, "SF", NOW), "done")
        self.assertEqual(fantasy.game_state(parsed, 4, "KC", NOW), "bye")
        self.assertEqual(fantasy.game_state(parsed, 4, "", NOW), "")
        self.assertEqual(fantasy.game_state(parsed, 9, "PHI", NOW), "")
        self.assertEqual(fantasy.game_state(None, 4, "PHI", NOW), "")

    def test_week_in_play(self):
        self.assertEqual(fantasy.schedule_week(schedule(), NOW), 4)

    def test_poll_speed(self):
        parsed = schedule()
        self.assertEqual(fantasy.poll_ms(parsed, [], NOW), fantasy.POLL_LIVE_MS)
        quiet = NOW + 2 * DAY
        self.assertEqual(fantasy.poll_ms(parsed, [], quiet), fantasy.POLL_IDLE_MS)
        self.assertEqual(fantasy.poll_ms(parsed, [], NOW + 7 * DAY - HOUR), fantasy.POLL_SOON_MS)
        self.assertEqual(fantasy.poll_ms(None, [{"live": True}], quiet), fantasy.POLL_LIVE_MS)


class Tally(unittest.TestCase):
    def test_counts_projection_and_alerts(self):
        starters = [
            fantasy.starter("Dallas Back", "RB", "DAL", "Out", 20.5, 15),      # live: past fixing
            fantasy.starter("Phil Wideout", "WR", "PHI", "Q", None, 12),       # pre
            fantasy.starter("Kay Cee", "TE", "KC", None, None, 9),             # bye
            fantasy.starter("Sam Francisco", "QB", "SF", "Doubtful", 18, 20),  # done
            fantasy.starter("Wash Guy", "WR", "WSH", "IR", None, 7),           # pre, IR
        ]
        out = fantasy.tally(starters, 2, schedule(), 4, NOW)
        self.assertEqual(out["left"], 2)
        self.assertEqual(out["playing"], 1)
        # live max(20.5, 15) + pre 12 + bye 0 + done 18 + pre 7
        self.assertEqual(out["projected"], 57.5)
        self.assertEqual([a["kind"] for a in out["alerts"]], ["empty", "bye", "ir", "questionable"])
        self.assertEqual(out["alerts"][0]["count"], 2)
        self.assertEqual(out["alerts"][1]["name"], "Cee")
        self.assertEqual(out["alerts"][2]["name"], "Guy")

    def test_unknown_schedule(self):
        out = fantasy.tally([fantasy.starter("A B", "RB", "DAL", "Out", 3, None)], 0, None, 4, NOW)
        self.assertIsNone(out["left"])
        self.assertIsNone(out["playing"])
        self.assertIsNone(out["projected"])
        self.assertEqual(out["alerts"][0]["kind"], "out")

    def test_side_prefers_the_platform(self):
        counted = {"projected": 50.0, "left": 2, "playing": 1}
        line = fantasy.side("Team", 10, counted, "1-0", projected=99, win=62, left=4, playing=0)
        self.assertEqual((line["projected"], line["left"], line["playing"], line["win"]), (99, 4, 0, 0.62))
        self.assertEqual(fantasy.side("Team", None, counted)["projected"], 50.0)


SLEEPER_STATE = {"season": "2026", "week": 4, "season_type": "regular"}
SLEEPER_LEAGUE = {"league_id": "111", "name": "Dynasty Bros", "season": "2026", "status": "in_season",
                  "total_rosters": 2, "scoring_settings": {"rec": 1}}
SLEEPER_ROSTERS = [
    {"roster_id": 1, "owner_id": "900", "co_owners": None, "settings": {"wins": 3, "losses": 1, "ties": 0, "fpts": 400, "fpts_decimal": 50}},
    {"roster_id": 2, "owner_id": "901", "settings": {"wins": 1, "losses": 3, "fpts": 300}},
]
SLEEPER_USERS = [
    {"user_id": "900", "display_name": "ande", "metadata": {"team_name": "Gridiron Gods"}},
    {"user_id": "901", "display_name": "rival", "metadata": {}},
]
SLEEPER_MATCHUPS = [
    {"roster_id": 1, "matchup_id": 1, "points": 20.5, "starters": ["p1", "p2", "0", "PHI"], "starters_points": [20.5, 0, 0, 0]},
    {"roster_id": 2, "matchup_id": 1, "points": 30, "starters": ["p3"], "starters_points": [30]},
]
SLEEPER_PLAYERS = {
    "p1": {"full_name": "Dallas Back", "position": "RB", "team": "DAL", "injury_status": None, "active": True},
    "p2": {"full_name": "Amon-Ra St. Brown Jr.", "position": "WR", "team": "PHI", "injury_status": "Questionable", "active": True},
    "p3": {"full_name": "Niner Guy", "position": "WR", "team": "SF", "active": True},
    "old": {"full_name": "Long Gone", "position": "WR", "team": None, "active": False},
}
SLEEPER_PROJECTIONS = [
    {"player_id": "p1", "stats": {"pts_ppr": 15, "pts_half_ppr": 13, "pts_std": 11}, "player": {"injury_status": None}},
    # The weekly projection's injury is fresher than the daily player list.
    {"player_id": "p2", "stats": {"pts_ppr": 12, "pts_half_ppr": 10, "pts_std": 8}, "player": {"injury_status": "Out"}},
    {"player_id": "PHI", "stats": {"pts_ppr": 8, "pts_half_ppr": 8, "pts_std": 8}},
    {"player_id": "p3", "stats": {"pts_ppr": 10}},
]


def sleeper_routes(**extra):
    routes = [
        ("/state/nfl", SLEEPER_STATE),
        ("/players/nfl", SLEEPER_PLAYERS),
        ("/projections/nfl/", SLEEPER_PROJECTIONS),
        ("/league/111/rosters", SLEEPER_ROSTERS),
        ("/league/111/users", SLEEPER_USERS),
        ("/league/111/matchups/4", SLEEPER_MATCHUPS),
        ("/league/111", SLEEPER_LEAGUE),
    ]
    return list(extra.get("before", [])) + routes


class SleeperTests(TempHome):
    def test_matchup(self):
        net = FakeNet(sleeper_routes())
        league = fantasy.collect_sleeper({"p": "sleeper", "id": "111", "team": "1", "user": "900"}, self.ctx(net))
        self.assertTrue(league["ok"])
        self.assertEqual(league["league"], "Dynasty Bros")
        self.assertEqual(league["url"], "https://sleeper.com/leagues/111/matchup")
        self.assertEqual((league["week"], league["rank"], league["teams"]), (4, 1, 2))
        me, opp = league["me"], league["opp"]
        self.assertEqual((me["name"], me["score"], me["record"]), ("Gridiron Gods", 20.5, "3-1"))
        self.assertEqual((me["left"], me["playing"]), (2, 1))
        self.assertEqual(me["projected"], 40.5)  # live 20.5 + p2 12 + defense 8
        self.assertEqual([a["kind"] for a in league["alerts"]], ["empty", "out"])
        self.assertEqual(league["alerts"][1]["name"], "St. Brown")
        self.assertEqual((opp["name"], opp["score"], opp["left"], opp["projected"]), ("rival", 30, 0, 30))
        self.assertTrue(league["live"])

    def test_player_list_is_trimmed_and_cached_for_a_day(self):
        net = FakeNet(sleeper_routes())
        fantasy.collect_sleeper({"p": "sleeper", "id": "111", "team": "1"}, self.ctx(net))
        fantasy.collect_sleeper({"p": "sleeper", "id": "111", "team": "1"}, self.ctx(net))
        self.assertEqual(len(net.urls("/players/nfl")), 1)
        self.assertEqual(len(net.urls("/projections/nfl/")), 1)
        saved = json.loads((fantasy.cache_dir() / "fantasy-sleeper-players.json").read_text())
        self.assertNotIn("old", saved["players"])
        self.assertEqual(saved["players"]["p1"], {"n": "Dallas Back", "p": "RB", "t": "DAL", "i": ""})

    def test_projections_failing_leaves_the_score(self):
        routes = sleeper_routes(before=[("/projections/nfl/", fantasy.FetchError(500))])
        league = fantasy.collect_sleeper({"p": "sleeper", "id": "111", "team": "1"}, self.ctx(FakeNet(routes)))
        self.assertTrue(league["ok"])
        self.assertIsNone(league["me"]["projected"])
        self.assertEqual(league["alerts"][1]["kind"], "questionable")

    def test_rolled_over_league_is_followed(self):
        old = dict(SLEEPER_LEAGUE, league_id="100", season="2025")
        newer = dict(SLEEPER_LEAGUE, previous_league_id="100")
        routes = sleeper_routes(before=[
            ("/league/100", old),
            ("/user/900/leagues/nfl/2026", [dict(newer, previous_league_id="99", league_id="5"), newer]),
        ])
        net = FakeNet(routes)
        league = fantasy.collect_sleeper({"p": "sleeper", "id": "100", "team": "1", "user": "900"}, self.ctx(net))
        self.assertEqual(league["url"], "https://sleeper.com/leagues/111/matchup")
        self.assertEqual(league["me"]["score"], 20.5)

    def test_guillotine_league_has_no_opponent(self):
        lone = [dict(SLEEPER_MATCHUPS[0], matchup_id=None)]
        routes = sleeper_routes(before=[("/league/111/matchups/4", lone)])
        league = fantasy.collect_sleeper({"p": "sleeper", "id": "111", "team": "1"}, self.ctx(FakeNet(routes)))
        self.assertIsNone(league["opp"])
        self.assertEqual(league["note"], "No head-to-head this week")

    def test_before_the_draft(self):
        routes = sleeper_routes(before=[("/league/111/rosters", SLEEPER_ROSTERS), ("/league/111/users", SLEEPER_USERS),
                                        ("/league/111", dict(SLEEPER_LEAGUE, status="pre_draft"))])
        league = fantasy.collect_sleeper({"p": "sleeper", "id": "111", "team": "1"}, self.ctx(FakeNet(routes)))
        self.assertEqual(league["note"], "Draft not done yet")
        self.assertIsNone(league["week"])

    def test_unknown_league(self):
        routes = [("/state/nfl", SLEEPER_STATE), ("/league/222", None)]
        with self.assertRaises(fantasy.LeagueError):
            fantasy.collect_sleeper({"p": "sleeper", "id": "222", "team": "1"}, self.ctx(FakeNet(routes)))

    def test_find_by_username(self):
        routes = sleeper_routes(before=[
            ("/user/ande", {"user_id": "900", "display_name": "ande"}),
            ("/user/900/leagues/nfl/2026", [SLEEPER_LEAGUE, {"league_id": "333", "name": "Not mine"}]),
            ("/league/333/rosters", [{"roster_id": 4, "owner_id": "777"}]),
            ("/league/333/users", []),
        ])
        found = fantasy.find_sleeper({"p": "sleeper", "user": "ande"}, self.ctx(FakeNet(routes)))
        self.assertEqual(found, [{"p": "sleeper", "id": "111", "name": "Dynasty Bros", "season": "2026", "team": "1",
                                  "teamName": "Gridiron Gods", "user": "900", "teams": []}])

    def test_find_by_league_lists_teams_and_owners(self):
        found = fantasy.find_sleeper({"p": "sleeper", "id": "111"}, self.ctx(FakeNet(sleeper_routes())))
        self.assertEqual(found[0]["teams"][0], {"id": "1", "name": "Gridiron Gods", "owner": "ande", "user": "900"})


def espn_entry(slot, player_id, name, position, team, actual=None, projected=None):
    stats = []
    if actual is not None:
        stats.append({"statSourceId": 0, "scoringPeriodId": 4, "appliedTotal": actual})
    if projected is not None:
        stats.append({"statSourceId": 1, "scoringPeriodId": 4, "appliedTotal": projected})
    stats.append({"statSourceId": 0, "scoringPeriodId": 3, "appliedTotal": 99})
    return {"lineupSlotId": slot, "playerId": player_id, "playerPoolEntry": {"player": {
        "id": player_id, "fullName": name, "defaultPositionId": position, "proTeamId": team, "stats": stats}}}


ESPN_BOX = {
    "scoringPeriodId": 4,
    "status": {"currentMatchupPeriod": 4, "isExpired": False},
    "settings": {"name": "Office League", "rosterSettings": {"lineupSlotCounts": {"0": 1, "2": 2, "20": 5, "21": 1, "3": 0}}},
    "teams": [
        {"id": 1, "name": "Mine", "record": {"overall": {"wins": 2, "losses": 1, "ties": 0, "pointsFor": 300}}},
        {"id": 2, "location": "Old", "nickname": "Style", "record": {"overall": {"wins": 3, "losses": 0, "pointsFor": 350}}},
    ],
    "schedule": [{
        "matchupPeriodId": 4,
        "home": {"teamId": 2, "totalPoints": 0, "totalPointsLive": 12.5, "totalProjectedPointsLive": 101.2,
                 "winProbability": 0.4, "rosterForCurrentScoringPeriod": {"entries": [
                     espn_entry(0, 30, "Their Passer", 1, 6, 12.5, 20)]}},
        "away": {"teamId": 1, "totalPoints": 0, "totalPointsLive": 20.0, "totalProjectedPointsLive": 110.7,
                 "winProbability": 0.6, "rosterForCurrentScoringPeriod": {"entries": [
                     espn_entry(0, 10, "Phil Passer", 1, 21, None, 18),
                     espn_entry(2, 11, "Dallas Runner", 2, 6, 20, 14),
                     espn_entry(20, 12, "Bench Chief", 2, 12),
                 ]}},
    }],
}
ESPN_ROSTER = {"teams": [{"id": 1, "roster": {"entries": [
    {"playerId": 10, "playerPoolEntry": {"player": {"id": 10, "injuryStatus": "DOUBTFUL"}}},
    {"playerId": 12, "playerPoolEntry": {"player": {"id": 12, "injuryStatus": "OUT"}}},
]}}]}


def espn_routes(box=ESPN_BOX, roster=ESPN_ROSTER):
    return [
        ("view=mRoster", roster),
        ("view=mBoxscore", box),
        ("view=mTeam&view=mSettings", {"settings": {"name": "Office League"}, "teams": ESPN_BOX["teams"],
                                       "members": [{"id": "{A}", "displayName": "ande"}]}),
    ]


class EspnTests(TempHome):
    def test_matchup(self):
        net = FakeNet(espn_routes())
        league = fantasy.collect_espn({"p": "espn", "id": "222", "team": "1"}, self.ctx(net))
        me, opp = league["me"], league["opp"]
        self.assertEqual((league["league"], league["week"], league["rank"]), ("Office League", 4, 2))
        self.assertEqual((me["score"], me["projected"], me["win"], me["record"]), (20.0, 110.7, 0.6, "2-1"))
        self.assertEqual((me["left"], me["playing"]), (1, 1))
        self.assertEqual((opp["name"], opp["score"], opp["playing"]), ("Old Style", 12.5, 1))
        # One empty slot (three to start, two started); the benched OUT player is not an alert.
        self.assertEqual([(a["kind"], a["name"]) for a in league["alerts"]], [("empty", ""), ("doubtful", "Passer")])
        self.assertEqual(league["url"], "https://fantasy.espn.com/football/team?leagueId=222&teamId=1")

    def test_request_is_narrowed_to_this_team(self):
        net = FakeNet(espn_routes())
        fantasy.collect_espn({"p": "espn", "id": "222", "team": "1"}, self.ctx(net))
        box = [c for c in net.calls if "mBoxscore" in c["url"]][0]
        self.assertIn("/seasons/2026/segments/0/leagues/222?", box["url"])
        flt = json.loads(box["headers"]["X-Fantasy-Filter"])
        self.assertEqual(flt["schedule"]["filterTeamIds"]["value"], [1])
        self.assertNotIn("Cookie", box["headers"])
        self.assertTrue(net.urls("forTeamId=1"))

    def test_private_league_cookies(self):
        auth = {"espn:222": {"espn_s2": "AEB" * 10, "swid": "{1234}"}}
        net = FakeNet(espn_routes())
        fantasy.collect_espn({"p": "espn", "id": "222", "team": "1"}, self.ctx(net, auth))
        self.assertEqual(net.calls[0]["headers"]["Cookie"], "espn_s2=%s; SWID={1234}" % ("AEB" * 10))

    def test_private_league_without_cookies(self):
        net = FakeNet([("leagues/222", fantasy.FetchError(401))])
        league = fantasy.collect_one({"p": "espn", "id": "222", "team": "1"}, self.ctx(net))
        self.assertFalse(league["ok"])
        self.assertIn("private", league["error"])
        self.assertIn("beta", league["error"])

    def test_injuries_failing_leaves_the_score(self):
        net = FakeNet([("view=mRoster", fantasy.FetchError(500))] + espn_routes())
        league = fantasy.collect_espn({"p": "espn", "id": "222", "team": "1"}, self.ctx(net))
        self.assertEqual(league["me"]["score"], 20.0)
        self.assertEqual([a["kind"] for a in league["alerts"]], ["empty"])

    def test_bye_in_the_fantasy_schedule(self):
        box = copy.deepcopy(ESPN_BOX)
        del box["schedule"][0]["home"]
        league = fantasy.collect_espn({"p": "espn", "id": "222", "team": "1"}, self.ctx(FakeNet(espn_routes(box))))
        self.assertIsNone(league["opp"])
        self.assertEqual(league["note"], "Bye week")

    def test_find(self):
        found = fantasy.find_espn({"p": "espn", "id": "222"}, self.ctx(FakeNet(espn_routes())))
        self.assertEqual(found[0]["name"], "Office League")
        self.assertEqual([t["name"] for t in found[0]["teams"]], ["Mine", "Old Style"])


FLEA_STANDINGS = {
    "league": {"id": 5, "name": "Flea League", "activeForCurrentSeason": True},
    "divisions": [{"teams": [
        {"id": 100, "name": "Mine", "recordOverall": {"wins": 2, "losses": 1}, "pointsFor": {"value": 250},
         "owners": [{"displayName": "me"}]},
        {"id": 200, "name": "Them", "recordOverall": {"wins": 1, "losses": 2}, "pointsFor": {"value": 200}},
    ]}],
}
FLEA_BOARD = {"schedulePeriod": {"value": 4}, "games": [{
    "id": 77, "home": {"id": 200, "name": "Them"}, "away": {"id": 100, "name": "Mine"},
    "homeScore": {"score": {"value": 5.5}}, "awayScore": {"score": {"value": 12.25}}, "isInProgress": True}]}
FLEA_BOX = {
    "pointsAway": {"total": {"projected": {"value": 99.5}}},
    "pointsHome": {"total": {"projected": {"value": 88.0}}},
    "lineups": [
        {"group": "START", "slots": [
            {"position": {"label": "QB"},
             # Fleaflicker's own spelling of the field.
             "away": {"proPlayer": {"nameFull": "Kay Cee", "position": "QB", "proTeamAbbreviation": "KC",
                                    "injury": {"typeAbbreviaition": "Q", "severity": "QUESTIONABLE"}},
                      "viewingProjectedPoints": {"value": 17}},
             "home": {"proPlayer": {"nameFull": "Phil Starter", "position": "QB", "proTeamAbbreviation": "PHI",
                                    "injury": {"typeAbbreviaition": "O"}}}},
            {"position": {"label": "RB"},
             "home": {"proPlayer": {"nameFull": "Dal Runner", "position": "RB", "proTeamAbbreviation": "DAL"},
                      "viewingActualPoints": {"value": 5.5}}},
            {"position": {"label": "WR"},
             "away": {"proPlayer": {"nameFull": "Chi Wide", "position": "WR", "proTeamAbbreviation": "CHI",
                                    "injury": {"typeAbbreviaition": "O", "severity": "OUT"}},
                      "viewingProjectedPoints": {"value": 9}}},
        ]},
        {"group": None, "slots": [{"position": {"label": "BN"}, "away": {"proPlayer": {
            "nameFull": "Bench", "position": "RB", "proTeamAbbreviation": "SF", "injury": {"typeAbbreviaition": "IR"}}}}]},
    ],
}


def flea_routes(standings=FLEA_STANDINGS):
    return [
        ("FetchLeagueStandings", standings),
        ("FetchLeagueScoreboard", FLEA_BOARD),
        ("FetchLeagueBoxscore", FLEA_BOX),
    ]


class FleaflickerTests(TempHome):
    def test_matchup(self):
        net = FakeNet(flea_routes())
        league = fantasy.collect_fleaflicker({"p": "fleaflicker", "id": "5", "team": "100"}, self.ctx(net))
        me, opp = league["me"], league["opp"]
        self.assertEqual((me["name"], me["score"], me["projected"], me["record"]), ("Mine", 12.25, 99.5, "2-1"))
        self.assertEqual((opp["name"], opp["score"], opp["projected"], opp["playing"]), ("Them", 5.5, 88.0, 1))
        self.assertEqual([(a["kind"], a.get("count", 0)) for a in league["alerts"]], [("empty", 1), ("bye", 0), ("out", 0)])
        self.assertEqual(league["url"], "https://www.fleaflicker.com/nfl/leagues/5/scores/77")
        self.assertEqual((league["rank"], league["teams"], league["week"]), (1, 2, 4))

    def test_box_score_is_asked_without_a_season(self):
        net = FakeNet(flea_routes())
        fantasy.collect_fleaflicker({"p": "fleaflicker", "id": "5", "team": "100"}, self.ctx(net))
        self.assertNotIn("season=", net.urls("FetchLeagueBoxscore")[0])
        self.assertIn("season=2026", net.urls("FetchLeagueScoreboard")[0])

    def test_a_league_that_stopped_playing_is_refused(self):
        dead = copy.deepcopy(FLEA_STANDINGS)
        del dead["league"]["activeForCurrentSeason"]
        net = FakeNet(flea_routes(dead))
        league = fantasy.collect_one({"p": "fleaflicker", "id": "5", "team": "100"}, self.ctx(net))
        self.assertFalse(league["ok"])
        self.assertIn("isn't playing in 2026", league["error"])
        self.assertFalse(net.urls("FetchLeagueScoreboard"))

    def test_find(self):
        found = fantasy.find_fleaflicker({"p": "fleaflicker", "id": "5"}, self.ctx(FakeNet(flea_routes())))
        self.assertEqual(found[0]["teams"][0], {"id": "100", "name": "Mine", "owner": "me"})


MFL_LEAGUE = {"league": {"name": "MFL League", "starters": {"count": "3"}, "franchises": {"franchise": [
    {"id": "0001", "name": "Mine", "owner_name": "ande"}, {"id": "0002", "name": "Them"}]}}}
MFL_STANDINGS = {"leagueStandings": {"franchise": [
    {"id": "0001", "h2hw": "2", "h2hl": "1", "h2ht": "0", "pf": "300"},
    {"id": "0002", "h2hw": "3", "h2hl": "0", "h2ht": "0", "pf": "280"}]}}
# One matchup and a one-player lineup arrive as bare objects, not lists.
MFL_LIVE = {"liveScoring": {"week": "4", "matchup": {"franchise": [
    {"id": "0001", "score": "10.5", "playersYetToPlay": "1", "playersCurrentlyPlaying": "1", "players": {"player": [
        {"id": "1", "status": "starter", "score": "10.5", "gameSecondsRemaining": "1800"},
        {"id": "2", "status": "starter", "score": "0", "gameSecondsRemaining": "3600"},
        {"id": "3", "status": "nonstarter", "score": "0", "gameSecondsRemaining": "3600"}]}},
    {"id": "0002", "score": "7", "playersYetToPlay": "0", "playersCurrentlyPlaying": "0", "players": {"player":
        {"id": "4", "status": "starter", "score": "7", "gameSecondsRemaining": "0"}}},
]}}}
MFL_PLAYERS = {"players": {"player": [
    {"id": "1", "name": "Back, Dallas", "team": "DAL", "position": "RB"},
    {"id": "2", "name": "Eagle, Phil", "team": "PHI", "position": "WR"},
    {"id": "4", "name": "Bears, Chicago", "team": "CHI", "position": "Def"}]}}


def mfl_routes(**extra):
    return list(extra.get("before", [])) + [
        ("TYPE=leagueStandings", MFL_STANDINGS),
        ("TYPE=liveScoring", MFL_LIVE),
        ("TYPE=projectedScores", {"projectedScores": {"playerScore": [
            {"id": "1", "score": "20"}, {"id": "2", "score": "8"}, {"id": "4", "score": "6"}]}}),
        ("TYPE=players", MFL_PLAYERS),
        ("TYPE=injuries", {"injuries": {"injury": {"id": "2", "status": "Out"}}}),
        ("TYPE=league", MFL_LEAGUE),
    ]


class MflTests(TempHome):
    def test_matchup(self):
        net = FakeNet(mfl_routes())
        league = fantasy.collect_mfl({"p": "mfl", "id": "10005", "team": "0001"}, self.ctx(net))
        me, opp = league["me"], league["opp"]
        # MFL counts its own players left and playing.
        self.assertEqual((me["score"], me["left"], me["playing"]), (10.5, 1, 1))
        # 10.5 so far + 20 x half a game + 8 for a game not started
        self.assertEqual(me["projected"], 28.5)
        self.assertEqual((opp["name"], opp["score"], opp["projected"], opp["record"]), ("Them", 7, 7.0, "3-0"))
        self.assertEqual([(a["kind"], a["name"]) for a in league["alerts"]], [("empty", ""), ("out", "Eagle")])
        self.assertEqual((league["rank"], league["url"]), (2, "https://www.myfantasyleague.com/2026/home/10005"))

    def test_calls_not_about_a_league_stay_on_api(self):
        net = FakeNet(mfl_routes())
        fantasy.collect_mfl({"p": "mfl", "id": "10005", "team": "0001"}, self.ctx(net))
        for call in net.urls("TYPE=players") + net.urls("TYPE=injuries"):
            self.assertNotIn("L=", call)
            self.assertTrue(call.startswith("https://api.myfantasyleague.com/2026/export?"))
        self.assertIn("L=10005", net.urls("TYPE=liveScoring")[0])

    def test_api_key_goes_only_to_league_calls(self):
        net = FakeNet(mfl_routes())
        fantasy.collect_mfl({"p": "mfl", "id": "10005", "team": "0001"}, self.ctx(net, {"mfl:10005": {"apikey": "abcdefgh12"}}))
        self.assertIn("APIKEY=abcdefgh12", net.urls("TYPE=liveScoring")[0])
        self.assertNotIn("APIKEY", net.urls("TYPE=players")[0])

    def test_error_object(self):
        net = FakeNet(mfl_routes(before=[("TYPE=league", {"error": {"$t": "Invalid league ID"}})]))
        league = fantasy.collect_one({"p": "mfl", "id": "10005", "team": "0001"}, self.ctx(net))
        self.assertEqual(league["error"], "Invalid league ID")

    def test_find(self):
        found = fantasy.find_mfl({"p": "mfl", "id": "10005"}, self.ctx(FakeNet(mfl_routes())))
        self.assertEqual(found[0]["teams"][0], {"id": "0001", "name": "Mine", "owner": "ande"})


FANTRAX_INFO = {
    "leagueName": "FX League", "seasonYear": 2026, "endDate": "2027-01-05",
    "teamInfo": {"a1b2c3d4": {"name": "Mine", "id": "a1b2c3d4"}, "z9y8x7w6": {"name": "Them", "id": "z9y8x7w6"}},
    "scoringPeriods": [
        {"number": 3, "startDate": "2026-09-24T20:00:00.0-0400", "endDate": "2026-09-29T11:59:59.0-0400"},
        {"number": 4, "startDate": "2026-10-01T20:00:00.0-0400", "endDate": "2026-10-06T11:59:59.0-0400"},
        {"number": 5, "startDate": "2026-10-08T20:00:00.0-0400", "endDate": "2026-10-13T11:59:59.0-0400"},
    ],
    "matchups": [{"period": 4, "matchupList": [{"away": {"id": "z9y8x7w6"}, "home": {"id": "a1b2c3d4"}}]}],
}
FANTRAX_STANDINGS = [
    {"teamId": "a1b2c3d4", "points": "3-0-0", "totalPointsFor": 300},
    {"teamId": "z9y8x7w6", "points": "1-2-0", "totalPointsFor": 200},
]


class FantraxTests(TempHome):
    def routes(self, info=FANTRAX_INFO):
        return [("getLeagueInfo", info), ("getStandings", FANTRAX_STANDINGS)]

    def test_schedule_without_scores(self):
        league = fantasy.collect_fantrax({"p": "fantrax", "id": "abcd1234", "team": "a1b2c3d4"}, self.ctx(FakeNet(self.routes())))
        self.assertEqual((league["week"], league["rank"]), (4, 1))
        self.assertEqual((league["me"]["record"], league["opp"]["name"], league["opp"]["record"]), ("3-0", "Them", "1-2"))
        self.assertIsNone(league["me"]["score"])
        self.assertIn("not scores", league["note"])

    def test_season_over(self):
        league = fantasy.collect_fantrax({"p": "fantrax", "id": "abcd1234", "team": "a1b2c3d4"},
                                         self.ctx(FakeNet(self.routes(dict(FANTRAX_INFO, endDate="2017-12-31")))))
        self.assertEqual(league["note"], "Season over")

    def test_error_inside_a_200(self):
        bad = {"error": {"code": "WARNING", "message": "Invalid 'leagueId' parameter - league ID: x not found"}}
        league = fantasy.collect_one({"p": "fantrax", "id": "abcd1234", "team": "a1b2c3d4"}, self.ctx(FakeNet(self.routes(bad))))
        self.assertEqual(league["error"], "Fantrax has no league abcd1234")

    def test_period_choice(self):
        periods = FANTRAX_INFO["scoringPeriods"]
        self.assertEqual(fantasy.fantrax_period(periods, NOW), (4, True))
        self.assertEqual(fantasy.fantrax_period(periods, NOW + 4 * DAY), (5, False))
        self.assertEqual(fantasy.fantrax_period(periods, NOW + 30 * DAY), (5, False))


def yahoo_team(key, name, points=None, projected=None, extra=None):
    meta = [{"team_key": key}, {"team_id": key.rsplit(".", 1)[-1]}, {"name": name}, []]
    rest = {}
    if points is not None:
        rest["team_points"] = {"coverage_type": "week", "week": "4", "total": points}
    if projected is not None:
        rest["team_projected_points"] = {"coverage_type": "week", "week": "4", "total": projected}
    rest.update(extra or {})
    return {"team": [meta, rest]}


YAHOO_SCOREBOARD = {"fantasy_content": {"league": [
    {"league_key": "461.l.555", "name": "Yahoo League", "url": "https://football.fantasysports.yahoo.com/f1/555",
     "num_teams": 2, "current_week": 4},
    {"scoreboard": {"0": {"matchups": {"0": {"matchup": {"week": "4", "0": {"teams": {
        "0": yahoo_team("461.l.555.t.1", "Mine", "30.5", "101.5", {"win_probability": 0.71}),
        "1": yahoo_team("461.l.555.t.2", "Them", "22", "95"),
        "count": 2}}}}, "count": 1}}, "week": "4"}},
]}}
YAHOO_STANDINGS = {"fantasy_content": {"league": [{"league_key": "461.l.555"}, {"standings": [{"teams": {
    "0": {"team": [[{"team_key": "461.l.555.t.1"}, {"name": "Mine"}], {"team_points": {"total": "300"}},
                   {"team_standings": {"rank": 1, "outcome_totals": {"wins": "3", "losses": "1", "ties": 0}}}]},
    "1": {"team": [[{"team_key": "461.l.555.t.2"}, {"name": "Them"}], {"team_points": {"total": "250"}},
                   {"team_standings": {"outcome_totals": {"wins": 1, "losses": 3, "ties": 0}}}]},
    "count": 2}}]}]}}


def yahoo_roster(players):
    listed = {str(i): {"player": [
        [{"player_key": "461.p.%d" % i}, {"name": {"full": name}}, {"status": status} if status else [],
         {"editorial_team_abbr": team}, {"display_position": pos}],
        {"selected_position": [{"coverage_type": "week"}, {"week": "4"}, {"position": slot}]},
    ]} for i, (name, status, team, pos, slot) in enumerate(players)}
    listed["count"] = len(players)
    return {"fantasy_content": {"team": [[{"team_key": "x"}], {"roster": {"coverage_type": "week", "week": "4",
                                                                       "0": {"players": listed}}}]}}


def yahoo_routes():
    return [
        ("get_token", {"access_token": "new", "refresh_token": "r2", "expires_in": 3600}),
        ("/scoreboard", YAHOO_SCOREBOARD),
        ("/standings", YAHOO_STANDINGS),
        ("/team/461.l.555.t.1/roster", yahoo_roster([
            ("Phil Eagle", "Q", "Phi", "WR", "WR"), ("Dal Back", None, "DAL", "RB", "RB"),
            ("Bench Guy", "O", "KC", "RB", "BN"), ("Hurt Guy", "IR", "SF", "WR", "IR")])),
        ("/team/461.l.555.t.2/roster", yahoo_roster([("Their Guy", None, "SF", "QB", "QB")])),
    ]


YAHOO_AUTH = {"client_id": "cid", "client_secret": "sec", "access_token": "old", "refresh_token": "r1", "expires_at": NOW - 1}


class YahooTests(TempHome):
    def test_flatten(self):
        flat = fantasy.yahoo_flat(YAHOO_STANDINGS)["fantasy_content"]["league"]
        teams = fantasy.yahoo_items(flat["standings"]["teams"], "team")
        self.assertEqual([t["team_key"] for t in teams], ["461.l.555.t.1", "461.l.555.t.2"])
        self.assertEqual(teams[0]["team_standings"]["outcome_totals"]["wins"], "3")

    def test_matchup_after_a_token_refresh(self):
        net = FakeNet(yahoo_routes())
        league = fantasy.collect_yahoo({"p": "yahoo", "id": "461.l.555", "team": "1"}, self.ctx(net, {"yahoo": dict(YAHOO_AUTH)}))
        me, opp = league["me"], league["opp"]
        self.assertEqual((me["score"], me["projected"], me["win"], me["record"]), (30.5, 101.5, 0.71, "3-1"))
        self.assertEqual((me["left"], me["playing"]), (1, 1))
        self.assertEqual([(a["kind"], a["name"]) for a in league["alerts"]], [("questionable", "Eagle")])
        self.assertEqual((opp["name"], opp["score"], opp["record"]), ("Them", 22.0, "1-3"))
        self.assertEqual((league["rank"], league["url"]), (1, "https://football.fantasysports.yahoo.com/f1/555"))
        refresh = net.calls[0]
        self.assertIn("grant_type=refresh_token", refresh["data"])
        self.assertTrue(refresh["headers"]["Authorization"].startswith("Basic "))
        for call in net.calls[1:]:
            self.assertEqual(call["headers"]["Authorization"], "Bearer new")
            self.assertIn("format=json", call["url"])
        # The refresh token rotated, and the new one is what is kept.
        saved = fantasy.read_auth()["yahoo"]
        self.assertEqual((saved["refresh_token"], saved["access_token"]), ("r2", "new"))
        self.assertEqual(len(net.urls("get_token")), 1)

    def test_no_sign_in(self):
        league = fantasy.collect_one({"p": "yahoo", "id": "461.l.555", "team": "1"}, self.ctx(FakeNet([])))
        self.assertIn("Sign in to Yahoo", league["error"])

    def test_signin_checks_the_code_before_calling(self):
        net = FakeNet(yahoo_routes())
        result = fantasy.signin(NOW, net, {"client_id": "cid", "client_secret": "sec", "code": "bad code!"}, auth={})
        self.assertFalse(result["ok"])
        self.assertEqual(net.calls, [])

    def test_signin_saves_tokens_and_lists_leagues(self):
        users_leagues = {"fantasy_content": {"users": {"0": {"user": [{"guid": "G"}, {"games": {"0": {"game": [
            {"game_key": "461", "code": "nfl"},
            {"leagues": {"0": {"league": [{"league_key": "461.l.555", "name": "Yahoo League", "season": "2026"}]},
                         "count": 1}}]}, "count": 1}}]}, "count": 1}}}
        users_teams = {"fantasy_content": {"users": {"0": {"user": [{"guid": "G"}, {"games": {"0": {"game": [
            {"game_key": "461"}, {"teams": {"0": {"team": [[{"team_key": "461.l.555.t.3"}, {"team_id": "3"}, {"name": "Mine"}]]},
                                            "count": 1}}]}, "count": 1}}]}, "count": 1}}}
        net = FakeNet([("get_token", {"access_token": "a1", "refresh_token": "r1", "expires_in": 3600}),
                       ("/leagues", users_leagues), ("/teams", users_teams)])
        result = fantasy.signin(NOW, net, {"client_id": "cid", "client_secret": "sec", "code": "abc123"}, auth={})
        self.assertTrue(result["ok"], result)
        self.assertEqual(result["leagues"], [{"p": "yahoo", "id": "461.l.555", "name": "Yahoo League", "season": "2026",
                                              "team": "3", "teamName": "Mine", "teams": []}])
        self.assertIn("grant_type=authorization_code", net.calls[0]["data"])
        self.assertEqual(fantasy.read_auth()["yahoo"]["refresh_token"], "r1")


class CollectTests(TempHome):
    def test_payload_and_one_failure(self):
        routes = [("proTeamSchedules_wl", SCHEDULE)] + espn_routes() + flea_routes()
        routes.insert(0, ("FetchLeagueBoxscore", RuntimeError("boom")))
        request = json.dumps([{"p": "espn", "id": "222", "team": "1"}, {"p": "fleaflicker", "id": "5", "team": "100"},
                              {"p": "cbs", "id": "1", "team": "1"}])
        payload = fantasy.collect(request, NOW, FakeNet(routes), auth={})
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["request"], request)
        self.assertEqual(len(payload["leagues"]), 2)
        espn, flea = payload["leagues"]
        self.assertTrue(espn["ok"])
        self.assertEqual((flea["ok"], flea["error"]), (False, "Fleaflicker did not answer"))
        self.assertEqual((payload["week"], payload["live"], payload["pollMs"]), (4, True, fantasy.POLL_LIVE_MS))

    def test_schedule_is_cached(self):
        net = FakeNet([("proTeamSchedules_wl", SCHEDULE)] + espn_routes())
        request = json.dumps([{"p": "espn", "id": "222", "team": "1"}])
        fantasy.collect(request, NOW, net, auth={})
        fantasy.collect(request, NOW + HOUR, net, auth={})
        self.assertEqual(len(net.urls("proTeamSchedules_wl")), 1)

    def test_schedule_failing_keeps_the_scores(self):
        net = FakeNet([("proTeamSchedules_wl", fantasy.FetchError(503))] + espn_routes())
        payload = fantasy.collect(json.dumps([{"p": "espn", "id": "222", "team": "1"}]), NOW, net, auth={})
        league = payload["leagues"][0]
        self.assertEqual(league["me"]["score"], 20.0)
        self.assertIsNone(league["me"]["left"])

    def test_nothing_set_up(self):
        payload = fantasy.collect("[]", NOW, FakeNet([]), auth={})
        self.assertEqual((payload["ok"], payload["leagues"]), (True, []))

    def test_cache_only_with_a_good_league(self):
        self.assertFalse(fantasy.write_cache({"ok": True, "leagues": [{"ok": False}]}, now_ms=NOW))
        self.assertTrue(fantasy.write_cache({"ok": True, "leagues": [{"ok": True}]}, now_ms=NOW))
        self.assertEqual(fantasy.read_cache()["savedAt"], NOW)


class FindTests(TempHome):
    def test_bad_specs(self):
        for spec in (None, {"p": "espn", "id": "1/2"}, {"p": "sleeper", "user": "a b"}, {"p": "cbs", "id": "1"}):
            result = fantasy.find(spec, NOW, FakeNet([]), auth={})
            self.assertFalse(result["ok"], spec)

    def test_cookies_are_saved_only_when_they_work(self):
        form = {"espn_s2": "AEB%2Bx" * 10, "swid": "abcdef01-2345-6789-abcd-ef0123456789"}
        failing = FakeNet([("leagues/222", fantasy.FetchError(401))])
        result = fantasy.find({"p": "espn", "id": "222"}, NOW, failing, form, auth={})
        self.assertFalse(result["ok"])
        self.assertIn("refused the saved cookies", result["error"])
        self.assertEqual(fantasy.read_auth(), {})
        working = FakeNet(espn_routes())
        result = fantasy.find({"p": "espn", "id": "222"}, NOW, working, form, auth={})
        self.assertTrue(result["ok"])
        self.assertIn("SWID={ABCDEF01-2345-6789-ABCD-EF0123456789}", working.calls[0]["headers"]["Cookie"])
        self.assertEqual(fantasy.read_auth()["espn:222"]["swid"], "{ABCDEF01-2345-6789-ABCD-EF0123456789}")
        mode = stat.S_IMODE(os.stat(fantasy.auth_path()).st_mode)
        self.assertEqual(mode, 0o600)

    def test_cookies_that_are_not_cookies(self):
        result = fantasy.find({"p": "espn", "id": "222"}, NOW, FakeNet(espn_routes()), {"espn_s2": "x", "swid": "y"}, auth={})
        self.assertFalse(result["ok"])
        self.assertEqual(fantasy.read_auth(), {})

    def test_not_found(self):
        result = fantasy.find({"p": "espn", "id": "222"}, NOW, FakeNet([("leagues/222", fantasy.FetchError(404))]), auth={})
        self.assertEqual(result["error"], "ESPN has no league 222 for 2026")

    def test_season_from_an_mfl_link(self):
        net = FakeNet(mfl_routes())
        fantasy.find({"p": "mfl", "id": "10005", "season": 2025}, NOW, net, auth={})
        self.assertTrue(net.calls[0]["url"].startswith("https://api.myfantasyleague.com/2025/"))

    def test_forget(self):
        fantasy.save_auth("espn:222", {"espn_s2": "x", "swid": "y"})
        fantasy.save_auth("yahoo", {"refresh_token": "r"})
        self.assertEqual(fantasy.forget("espn:222"), {"ok": True})
        self.assertEqual(fantasy.forget("../../etc"), {"ok": False})
        self.assertEqual(list(fantasy.read_auth()), ["yahoo"])
        fantasy.forget("yahoo")
        self.assertEqual(fantasy.read_auth(), {})


if __name__ == "__main__":
    unittest.main()
