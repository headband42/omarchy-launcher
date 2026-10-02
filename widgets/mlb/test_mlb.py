#!/usr/bin/env python3
"""MLB tile model. Stdlib only.

Run from the repo root:  python3 widgets/mlb/test_mlb.py
"""

import unittest
from datetime import datetime
from zoneinfo import ZoneInfo

import mlb


NYY = (147, "NYY", "Yankees")
TB = (139, "TB", "Rays")
WSH = (120, "WSH", "Nationals")
DET = (116, "DET", "Tigers")
COL = (115, "COL", "Rockies")
CHICAGO = ZoneInfo("America/Chicago")
EASTERN = ZoneInfo("America/New_York")
# 1:00 PM CDT on a Wednesday. Tonight's 23:05Z first pitch is 6:05 PM here.
NOW = datetime(2026, 9, 23, 13, 0, tzinfo=CHICAGO)


def raw(*, pk, away, home, abstract="Final", detailed=None, when="2026-09-22T23:05:00Z",
        official="2026-09-22", away_score=0, home_score=0, balls=None, strikes=None, outs=None,
        bases=(), batter="", pitcher="", innings=None, scheduled=9, current=None, half="Top",
        tbd=False, number=1, public=True, broadcasts=()):
    if detailed is None:
        detailed = {"Final": "Final", "Live": "In Progress", "Preview": "Scheduled"}.get(abstract, abstract)

    def team(info, score):
        tid, abbr, name = info
        block = {"team": {"id": tid, "abbreviation": abbr, "name": name, "teamName": name}}
        if score is not None:
            block["score"] = score
        return block

    offense = {}
    if batter:
        offense["batter"] = {"id": 1, "fullName": batter}
    for base in bases:
        offense[base] = {"id": 9, "fullName": "Runner"}
    defense = {"pitcher": {"id": 3, "fullName": pitcher}} if pitcher else {}
    ls_innings = []
    for index, pair in enumerate(innings or []):
        cell = {"num": index + 1}
        if pair[0] is not None:
            cell["away"] = {"runs": pair[0]}
        if pair[1] is not None:
            cell["home"] = {"runs": pair[1]}
        ls_innings.append(cell)
    if current is None:
        current = len(ls_innings) or None
    linescore = {
        "currentInning": current,
        "inningState": half,
        "scheduledInnings": scheduled,
        "innings": ls_innings,
        "teams": {
            "away": {"runs": away_score, "hits": 2, "errors": 0},
            "home": {"runs": home_score, "hits": 4, "errors": 1},
        },
        "offense": offense,
        "defense": defense,
    }
    if balls is not None:
        linescore["balls"] = balls
        linescore["strikes"] = strikes
        linescore["outs"] = outs
    return {
        "gamePk": pk,
        "gameDate": when,
        "officialDate": official,
        "gameNumber": number,
        "publicFacing": public,
        "status": {
            "abstractGameState": abstract,
            "detailedState": detailed,
            "startTimeTBD": tbd,
        },
        "teams": {"away": team(away, away_score), "home": team(home, home_score)},
        "linescore": linescore,
        "broadcasts": list(broadcasts),
    }


def with_pitchers(game, *, winner="", loser="", save="", away_pitcher="", home_pitcher=""):
    if winner or loser or save:
        game["decisions"] = {}
        if winner:
            game["decisions"]["winner"] = {"fullName": winner}
        if loser:
            game["decisions"]["loser"] = {"fullName": loser}
        if save:
            game["decisions"]["save"] = {"fullName": save}
    if away_pitcher:
        game["teams"]["away"]["probablePitcher"] = {"fullName": away_pitcher}
    if home_pitcher:
        game["teams"]["home"]["probablePitcher"] = {"fullName": home_pitcher}
    return game


def schedule(games):
    return {"dates": [{"date": "2026-09-23", "games": games}]}


def team_payload(previous, upcoming):
    return {"teams": [{
        "previousGameSchedule": schedule(previous),
        "nextGameSchedule": schedule(upcoming),
    }]}


def season(start="2026-09-28", end="2026-10-31"):
    return {"seasons": [{
        "seasonId": "2026",
        "postSeasonStartDate": start,
        "postSeasonEndDate": end,
    }]}


# Postseason clubs carry their league; the series board groups by it.
CWS = (145, "CWS", "White Sox", 103)
CLE = (114, "CLE", "Guardians", 103)
TBR = (139, "TB", "Rays", 103)
NYA = (147, "NYY", "Yankees", 103)
LAD = (119, "LAD", "Dodgers", 104)
ATL = (144, "ATL", "Braves", 104)
AL_LOW = (5521, "AL Low", "AL Lower Seed", 103, True)
AL_HIGH = (5513, "AL High", "AL Higher Seed", 103, True)
NL_LOW = (5522, "NL Low", "NL Lower Seed", 104, True)
NL_HIGH = (5514, "NL High", "NL Higher Seed", 104, True)
WS_LOW = (5531, "Low", "Lower Seed", None, True)
WS_HIGH = (5532, "High", "Higher Seed", None, True)


def club(info):
    tid, abbr, name, league = info[:4]
    team = {"id": tid, "abbreviation": abbr, "name": name, "teamName": name}
    if league:
        team["league"] = {"id": league}
    if len(info) > 4:
        team["placeholder"] = True
    return team


def pgame(pk, kind, number, best, away, home, *, winner=None, score=(5, 3), live=None,
          when="2026-10-07T22:08:00Z", official="2026-10-07", tbd=False,
          away_p="", home_p="", tv="TBS"):
    """One postseason game. `winner` is the club that won it; None is still to play."""
    away_block = {"team": club(away)}
    home_block = {"team": club(home)}
    abstract, detailed = "Preview", "Scheduled"
    if winner is not None:
        abstract = detailed = "Final"
        won, lost = score
        away_won = winner == away
        away_block.update({"score": won if away_won else lost, "isWinner": away_won})
        home_block.update({"score": lost if away_won else won, "isWinner": not away_won})
    if live is not None:
        abstract, detailed = "Live", "In Progress"
        away_block["score"], home_block["score"] = live
    if away_p:
        away_block["probablePitcher"] = {"fullName": away_p}
    if home_p:
        home_block["probablePitcher"] = {"fullName": home_p}
    return {
        "gamePk": pk,
        "gameType": kind,
        "gameDate": when,
        "officialDate": official,
        "status": {"abstractGameState": abstract, "detailedState": detailed, "startTimeTBD": tbd},
        "teams": {"away": away_block, "home": home_block},
        "seriesGameNumber": number,
        "gamesInSeries": best,
        "seriesStatus": {"gameNumber": number, "totalGames": best},
        "linescore": {"currentInning": 6, "inningState": "Top"} if live is not None else {},
        "broadcasts": [{"type": "TV", "callSign": tv, "isNational": True, "homeAway": "home"}],
    }


def series_feed(*blocks):
    return {"series": [{"series": {"id": sid, "gameType": games[0]["gameType"]}, "games": games}
                       for sid, games in blocks]}


def wild_cards_done():
    """Both Wild Card rounds over: CWS and NYY, then ATL, advance."""
    return [
        ("F_1", [pgame(1, "F", 1, 3, CWS, CLE, winner=CWS), pgame(2, "F", 2, 3, CWS, CLE, winner=CWS)]),
        ("F_3", [pgame(3, "F", 1, 3, LAD, ATL, winner=ATL), pgame(4, "F", 2, 3, LAD, ATL, winner=LAD),
                 pgame(5, "F", 3, 3, LAD, ATL, winner=ATL, score=(6, 2))]),
    ]


# 12:00 PM MDT on Wednesday, Oct 7. A 22:08Z start is 4:08 PM here.
DENVER = ZoneInfo("America/Denver")
OCT7 = datetime(2026, 10, 7, 12, 0, tzinfo=DENVER)


class Fetch:
    def __init__(self, routes):
        self.urls = []
        self.routes = routes

    def __call__(self, url):
        self.urls.append(url)
        for pred, payload in self.routes:
            if pred(url):
                if isinstance(payload, Exception):
                    raise payload
                return payload
        if "/standings?" in url:
            return {"records": []}
        if "/people?" in url:
            return {"people": []}
        raise AssertionError(url)


class SettingsTest(unittest.TestCase):
    def test_team_id(self):
        self.assertIsNone(mlb.team_id_from_settings(None))
        self.assertIsNone(mlb.team_id_from_settings({}))
        self.assertIsNone(mlb.team_id_from_settings({"teamId": 0}))
        self.assertIsNone(mlb.team_id_from_settings({"teamId": True}))
        self.assertIsNone(mlb.team_id_from_settings({"teamId": "NYY"}))
        self.assertIsNone(mlb.team_id_from_settings({"teamId": 1.5}))
        self.assertEqual(mlb.team_id_from_settings({"teamId": 147}), 147)
        self.assertEqual(mlb.team_id_from_settings({"teamId": "147"}), 147)
        self.assertEqual(mlb.team_id_from_settings({"teamId": 147.0}), 147)

    def test_empty_settings_forget_the_club(self):
        self.assertEqual(mlb.settings_for_team(0), {})
        self.assertEqual(mlb.settings_for_team(147), {"teamId": 147})

    def test_catalog_sorts_active_mlb_clubs(self):
        rows = mlb.team_catalog({"teams": [
            {"id": 147, "name": "New York Yankees", "abbreviation": "NYY",
             "teamName": "Yankees", "locationName": "Bronx", "active": True, "sport": {"id": 1}},
            {"id": 158, "name": "Milwaukee Brewers", "abbreviation": "MIL", "active": False, "sport": {"id": 1}},
            {"id": 133, "name": "Athletics", "abbreviation": "ATH",
             "teamName": "Athletics", "locationName": "Sacramento", "sport": {"id": 1}},
            {"id": 1, "name": "Some College", "sport": {"id": 22}},
        ]})
        self.assertEqual([row["abbr"] for row in rows], ["ATH", "NYY"])
        self.assertEqual(rows[0]["location"], "Sacramento")


class PresentTest(unittest.TestCase):
    def test_gameday_url(self):
        self.assertEqual(mlb.gameday_url(824223), "https://www.mlb.com/gameday/824223")
        self.assertEqual(mlb.gameday_url(0), "")
        self.assertEqual(mlb.gameday_url("nope"), "")

    def test_live_game_has_count_bases_and_names(self):
        game = raw(
            pk=824223, away=WSH, home=DET, abstract="Live", half="Top", current=4,
            away_score=0, home_score=2, balls=0, strikes=1, outs=2,
            bases=("first", "third"), batter="James Wood", pitcher="Framber Valdez",
            innings=[(0, 0), (0, 1), (0, 0), (0, None)],
        )
        shown = mlb.present_game(game, 120)
        self.assertTrue(shown["live"])
        self.assertEqual(shown["status"], "Top 4")
        self.assertEqual(shown["countLine"], "0-1 · 2 outs")
        self.assertEqual(shown["bases"], [True, False, True])
        self.assertEqual(shown["batterLine"], "James Wood batting")
        self.assertEqual(shown["pitcherLine"], "Framber Valdez pitching")
        self.assertEqual(shown["rowNames"], "Wood · Valdez")
        self.assertEqual(shown["favorite"], "away")
        self.assertEqual(shown["gameday"], "https://www.mlb.com/gameday/824223")
        self.assertEqual(shown["away"]["innings"][3], "0")
        self.assertEqual(shown["home"]["innings"][3], "")
        self.assertEqual(shown["away"]["score"], "0")
        self.assertEqual(shown["home"]["hits"], "4")
        self.assertTrue(shown["hasLine"])
        self.assertEqual(shown["mark"], "@")
        self.assertEqual(shown["left"]["abbr"], "WSH")
        self.assertEqual(shown["right"]["abbr"], "DET")
        self.assertEqual(shown["away"]["record"], "")

    def test_handedness_on_the_live_lines(self):
        game = raw(
            pk=5, away=TB, home=NYY, abstract="Live",
            batter="Aaron Judge", pitcher="Shane Baz",
        )
        game["linescore"]["offense"]["batter"]["batSide"] = {"code": "R"}
        game["linescore"]["defense"]["pitcher"]["pitchHand"] = {"code": "s"}
        shown = mlb.present_game(game, 147)
        self.assertEqual(shown["batterLine"], "Aaron Judge (R) batting")
        self.assertEqual(shown["pitcherLine"], "Shane Baz (S) pitching")
        self.assertEqual(shown["rowNames"], "Judge (R) · Baz (S)")
        game["linescore"]["offense"]["batter"]["batSide"] = {"code": "B"}
        plain = mlb.present_game(game, 147)
        self.assertEqual(plain["batterLine"], "Aaron Judge batting")

    def test_attach_hands_fills_missing_sides(self):
        game = raw(
            pk=6, away=TB, home=NYY, abstract="Live",
            batter="Aaron Judge", pitcher="Shane Baz",
        )
        seen = []

        def fetch(url):
            seen.append(url)
            return {"people": [
                {"id": 1, "batSide": {"code": "L", "description": "Left"}},
                {"id": 3, "pitchHand": {"code": "R", "description": "Right"}},
            ]}

        mlb.attach_hands([game], fetch)
        self.assertEqual(seen, [mlb.people_url([1, 3])])
        shown = mlb.present_game(game, 147)
        self.assertEqual(shown["batterLine"], "Aaron Judge (L) batting")
        self.assertEqual(shown["pitcherLine"], "Shane Baz (R) pitching")

        def fail_fetch(url):
            raise AssertionError(url)

        mlb.attach_hands([game], fail_fetch)

    def test_tv_channel_prefers_national_then_the_club(self):
        broadcasts = [
            {"type": "TV", "name": "Root Sports", "callSign": "ROOT", "homeAway": "home", "isNational": False},
            {"type": "TV", "name": "Space City", "callSign": "SCHN", "homeAway": "away", "isNational": False},
            {"type": "AM", "name": "Seattle Sports", "callSign": "KIRO", "homeAway": "home", "isNational": False},
        ]
        self.assertEqual(mlb.tv_channel(broadcasts, "home"), "ROOT")
        self.assertEqual(mlb.tv_channel(broadcasts, "away"), "SCHN")
        self.assertEqual(mlb.tv_channel(broadcasts, ""), "")
        national = broadcasts + [
            {"type": "TV", "name": "ESPN/ESPN App", "callSign": "ESPN", "homeAway": "home", "isNational": True},
            {"type": "TV", "name": "ESPN/ESPN App", "callSign": "ESPN", "homeAway": "away", "isNational": True},
        ]
        self.assertEqual(mlb.tv_channel(national, "home"), "ESPN")
        self.assertEqual(mlb.tv_channel(national, "away"), "ESPN")
        unnamed = [{"type": "TV", "name": "Apple TV+/MLB.TV", "callSign": "", "homeAway": "home", "isNational": True}]
        self.assertEqual(mlb.tv_channel(unnamed, "away"), "Apple TV+")

        game = raw(pk=11, away=TB, home=NYY, abstract="Live")
        game["broadcasts"] = broadcasts
        self.assertEqual(mlb.present_game(game, 147)["tv"], "ROOT")
        self.assertEqual(mlb.present_game(game, 139)["tv"], "SCHN")

    def test_next_game_carries_the_tv_channel(self):
        national = [
            {"type": "TV", "name": "YES", "callSign": "YES", "homeAway": "home", "isNational": False},
            {"type": "TV", "name": "ESPN", "callSign": "ESPN", "homeAway": "away", "isNational": True},
        ]
        game = raw(pk=1, away=TB, home=NYY, abstract="Preview", broadcasts=national)
        self.assertEqual(mlb.present_next(game, 147, NOW, "Next")["tv"], "ESPN")
        local = [
            {"type": "TV", "name": "YES", "callSign": "YES", "homeAway": "home", "isNational": False},
            {"type": "TV", "name": "Sun", "callSign": "SUN", "homeAway": "away", "isNational": False},
        ]
        home_fan = raw(pk=1, away=TB, home=NYY, abstract="Preview", broadcasts=local)
        self.assertEqual(mlb.present_next(home_fan, 147, NOW, "Next")["tv"], "YES")
        away_fan = raw(pk=1, away=TB, home=NYY, abstract="Preview", broadcasts=local)
        self.assertEqual(mlb.present_next(away_fan, 139, NOW, "Next")["tv"], "SUN")
        quiet = raw(pk=1, away=TB, home=NYY, abstract="Preview")
        self.assertEqual(mlb.present_next(quiet, 147, NOW, "Next")["tv"], "")

    def test_scoreboard_sides_and_records(self):
        game = raw(pk=4, away=TB, home=NYY, abstract="Live", away_score=6, home_score=1)
        game["teams"]["away"]["leagueRecord"] = {"wins": 70, "losses": 86, "pct": ".449"}
        game["teams"]["home"]["leagueRecord"] = {"wins": 90, "losses": 66}
        home_view = mlb.present_game(game, 147)
        self.assertEqual(home_view["mark"], "vs")
        self.assertEqual(home_view["left"]["abbr"], "NYY")
        self.assertEqual(home_view["left"]["record"], "90-66")
        self.assertEqual(home_view["right"]["abbr"], "TB")
        self.assertEqual(home_view["right"]["record"], "70-86")
        away_view = mlb.present_game(game, 139)
        self.assertEqual(away_view["mark"], "@")
        self.assertEqual(away_view["left"]["abbr"], "TB")
        self.assertEqual(away_view["right"]["record"], "90-66")
        neutral = mlb.present_game(game, None)
        self.assertEqual(neutral["mark"], "@")
        self.assertEqual(neutral["left"]["id"], 139)
        self.assertEqual(neutral["home"]["record"], "90-66")

    def test_suffix_and_placeholder_names(self):
        self.assertEqual(mlb.last_name("George Lombard Jr."), "Lombard")
        team = {"id": 4944, "name": "AL Wild Card #3"}
        self.assertEqual(mlb.short_name(team), "AL#3")

    def test_final_hides_the_count_and_marks_extras(self):
        innings = [(0, 0)] * 12
        game = raw(
            pk=10, away=TB, home=NYY, abstract="Live", detailed="Game Over",
            innings=innings, current=12, scheduled=9, balls=3, strikes=2, outs=2,
            bases=("second",), batter="Someone",
        )
        shown = mlb.present_game(game, 147)
        self.assertFalse(shown["live"])
        self.assertEqual(shown["status"], "Final/12")
        self.assertEqual(shown["countLine"], "")
        self.assertEqual(shown["bases"], [False, False, False])
        self.assertEqual(shown["batterLine"], "")
        self.assertEqual(len(shown["labels"]), 11)
        self.assertEqual(shown["labels"][0], "2")
        self.assertEqual(shown["labels"][-1], "12")
        self.assertEqual(shown["favorite"], "home")

    def test_board_fields_for_a_live_game(self):
        game = raw(
            pk=11, away=TB, home=NYY, abstract="Live", half="Bottom", current=6,
            away_score=1, home_score=4, balls=0, strikes=2, outs=1,
            bases=("first", "third"), batter="Austin Wells", pitcher="Garrett Whitlock",
        )
        shown = mlb.present_game(game)
        self.assertEqual((shown["half"], shown["inning"]), ("bottom", 6))
        self.assertEqual(shown["leader"], "home")
        self.assertEqual(shown["note"], "")
        self.assertEqual(shown["series"], "")
        self.assertEqual((shown["batterShort"], shown["pitcherShort"]), ("Wells", "Whitlock"))
        tied = mlb.present_game(raw(pk=12, away=TB, home=NYY, abstract="Live", away_score=2, home_score=2))
        self.assertEqual(tied["leader"], "")
        final = mlb.present_game(raw(pk=13, away=TB, home=NYY, away_score=5, home_score=1))
        self.assertEqual((final["half"], final["inning"], final["leader"]), ("", 0, "away"))

    def test_warmup_has_no_count_and_says_so(self):
        game = raw(
            pk=14, away=TB, home=NYY, abstract="Live", detailed="Warmup",
            balls=0, strikes=0, outs=0, batter="Leadoff Man", pitcher="Starter",
        )
        shown = mlb.present_game(game)
        self.assertEqual(shown["note"], "Warmup")
        self.assertEqual(shown["countLine"], "")
        self.assertIsNone(shown["outs"])
        self.assertEqual(shown["rowDetail"], "Warmup")
        self.assertEqual(shown["batterShort"], "")

    def test_interruptions_get_a_short_note(self):
        game = raw(pk=15, away=TB, home=NYY, abstract="Live", detailed="Manager Challenge",
                   half="Top", current=3, balls=1, strikes=1, outs=0)
        shown = mlb.present_game(game)
        self.assertEqual(shown["note"], "Challenge")
        self.assertEqual((shown["half"], shown["inning"]), ("top", 3))
        self.assertEqual(shown["countLine"], "1-1 · 0 outs")

    def test_series_line_only_in_the_postseason(self):
        game = raw(pk=16, away=TB, home=NYY, abstract="Live")
        game["gameType"] = "F"
        game["seriesStatus"] = {"abbreviation": "ALWC", "gameNumber": 2, "wins": 1, "losses": 0,
                                "result": "NYY leads 1-0"}
        shown = mlb.present_game(game)
        self.assertEqual(shown["series"], "ALWC · Game 2 · NYY leads 1-0")
        self.assertEqual((shown["seriesRound"], shown["seriesGame"], shown["seriesResult"]),
                         ("ALWC", 2, "NYY leads 1-0"))
        game["seriesStatus"] = {"abbreviation": "ALDS", "gameNumber": 1, "wins": 0, "losses": 0,
                                "result": "Series tied 0-0"}
        self.assertEqual(mlb.present_game(game)["series"], "ALDS · Game 1")
        game["gameType"] = "R"
        game["seriesStatus"] = {"abbreviation": "RS", "gameNumber": 2, "wins": 1, "losses": 1,
                                "result": "Series tied 1-1"}
        self.assertEqual(mlb.present_game(game)["series"], "")

    def test_schedule_requests_carry_series_status(self):
        day = NOW.date()
        self.assertIn("seriesStatus", mlb.window_url(day))
        self.assertIn("seriesStatus", mlb.postseason_url(147, 2026))

    def test_seven_inning_line(self):
        game = raw(pk=3, away=TB, home=NYY, innings=[(0, 0)] * 7, scheduled=7, current=7)
        shown = mlb.present_game(game)
        self.assertEqual(shown["labels"], ["1", "2", "3", "4", "5", "6", "7"])
        self.assertEqual(shown["status"], "Final")

    def test_start_text(self):
        tonight = raw(pk=1, away=TB, home=NYY, abstract="Preview",
                      when="2026-09-23T23:05:00Z", official="2026-09-23")
        tomorrow = raw(pk=2, away=TB, home=NYY, abstract="Preview",
                       when="2026-09-24T23:05:00Z", official="2026-09-24")
        noon = raw(pk=3, away=TB, home=NYY, abstract="Preview",
                   when="2026-09-23T17:00:00Z", official="2026-09-23")
        midnight = raw(pk=4, away=TB, home=NYY, abstract="Preview",
                       when="2026-09-24T05:00:00Z", official="2026-09-24")
        later = raw(pk=5, away=(4944, "", "AL Wild Card #3"), home=NYY, abstract="Preview",
                    when="2026-09-29T07:33:00Z", official="2026-09-29", tbd=True, away_score=None, home_score=None)
        delayed = raw(pk=6, away=TB, home=NYY, abstract="Preview", detailed="Delayed Start",
                      when="2026-09-23T23:05:00Z", official="2026-09-23")
        self.assertEqual(mlb.format_start(tonight, NOW), "Today 6:05 PM")
        self.assertEqual(mlb.format_start(tomorrow, NOW), "Tomorrow 6:05 PM")
        self.assertEqual(mlb.format_start(noon, NOW), "Today 12:00 PM")
        self.assertEqual(mlb.format_start(midnight, NOW), "Tomorrow 12:00 AM")
        self.assertEqual(mlb.format_start(later, NOW), "Tue Sep 29, time TBD")
        nxt = mlb.present_next(later, 147, NOW, "Next")
        self.assertEqual(nxt["when"], "Tue Sep 29, time TBD")
        self.assertEqual(nxt["where"], "vs AL Wild Card #3")
        self.assertEqual(mlb.present_next(delayed, 147, NOW, "Next")["when"], "Delayed · Today 6:05 PM")
        self.assertEqual(mlb.present_next(tonight, 147, NOW, "Next")["where"], "vs Rays")
        self.assertEqual(mlb.present_next(tonight, 139, NOW, "Next")["where"], "at Yankees")
        projected = with_pitchers(tonight, away_pitcher="Mason Englert", home_pitcher="Gerrit Cole")
        nxt = mlb.present_next(projected, 147, NOW, "Next")
        self.assertEqual(nxt["pitchers"], "Englert vs Cole")
        self.assertEqual(nxt["homePitcher"], "Gerrit Cole")

    def test_winning_and_losing_pitchers(self):
        game = with_pitchers(
            raw(pk=2, away=TB, home=NYY, away_score=6, home_score=1),
            winner="Drew Rasmussen", loser="Max Fried", save="Camilo Doval",
        )
        shown = mlb.present_game(game, 147)
        self.assertEqual(shown["decisionLine"], "W Rasmussen · L Fried · S Doval")
        live = with_pitchers(
            raw(pk=3, away=TB, home=NYY, abstract="Live", balls=1, strikes=1, outs=1),
            winner="Drew Rasmussen", loser="Max Fried",
        )
        self.assertEqual(mlb.present_game(live)["decisionLine"], "")


class SeriesTest(unittest.TestCase):
    def test_series_feed_is_one_trimmed_request(self):
        url = mlb.series_url(2026)
        self.assertIn("/schedule/postseason/series?", url)
        self.assertIn("season=2026", url)
        self.assertIn("hydrate=team,seriesStatus,probablePitcher,broadcasts,linescore", url)
        fields = url.split("fields=", 1)[1].split("&", 1)[0].split(",")
        for key in ("seriesGameNumber", "gamesInSeries", "isWinner", "placeholder", "probablePitcher", "callSign"):
            self.assertIn(key, fields)

    def test_start_text_is_short(self):
        game = pgame(1, "D", 1, 5, CWS, CLE, when="2026-10-07T22:08:00Z")
        self.assertEqual(mlb.series_when(game, OCT7), ("Today 4:08 PM", True))
        game = pgame(1, "D", 1, 5, CWS, CLE, when="2026-10-08T22:08:00Z")
        self.assertEqual(mlb.series_when(game, OCT7), ("Tomorrow 4:08 PM", False))
        game = pgame(1, "D", 1, 5, CWS, CLE, when="2026-10-10T17:00:00Z")
        self.assertEqual(mlb.series_when(game, OCT7), ("Sat 11:00 AM", False))
        game = pgame(1, "L", 1, 7, AL_LOW, AL_HIGH, when="2026-10-15T07:33:00Z", official="2026-10-15", tbd=True)
        self.assertEqual(mlb.series_when(game, OCT7), ("Oct 15, TBD", False))

    def test_series_counts_wins_and_names_the_next_game(self):
        games = [
            pgame(11, "D", 1, 5, NYA, TBR, winner=TBR, score=(4, 2)),
            pgame(12, "D", 2, 5, NYA, TBR, winner=NYA, score=(5, 3)),
            # Game 3 is at the lower seed: the hosts are on the right of the
            # schedule but stay on the left of the card.
            pgame(13, "D", 3, 5, TBR, NYA, away_p="Drew Rasmussen", home_p="Carlos Rodón"),
            pgame(14, "D", 4, 5, TBR, NYA, when="2026-10-08T22:08:00Z"),
        ]
        row = mlb.present_series("D_1", "D", games, OCT7)
        self.assertEqual((row["left"]["abbr"], row["right"]["abbr"]), ("NYY", "TB"))
        self.assertEqual((row["left"]["wins"], row["right"]["wins"]), (1, 1))
        self.assertEqual((row["best"], row["need"]), (5, 3))
        self.assertEqual((row["state"], row["leader"], row["winner"]), ("active", "", ""))
        self.assertEqual(row["summary"], "Series tied 1-1")
        self.assertEqual(row["code"], "ALDS")
        self.assertEqual(row["next"]["game"], 3)
        self.assertEqual(row["next"]["when"], "Today 4:08 PM")
        self.assertTrue(row["next"]["today"])
        self.assertEqual(row["next"]["tv"], "TBS")
        self.assertEqual(row["next"]["pitchers"], "Rodón vs Rasmussen")
        self.assertEqual(row["last"], {"game": 2, "line": "NYY 5-3", "gameday": "https://www.mlb.com/gameday/12"})
        self.assertEqual(row["gameday"], "https://www.mlb.com/gameday/13")

    def test_one_probable_pitcher_leaves_the_other_tbd(self):
        game = pgame(1, "D", 1, 5, CWS, CLE, home_p="Parker Messick")
        row = mlb.present_series("D_2", "D", [game], OCT7)
        self.assertEqual(row["next"]["pitchers"], "TBD vs Messick")
        self.assertEqual(row["state"], "upcoming")
        self.assertEqual(row["summary"], "")

    def test_finished_series_points_at_the_winners_next_round(self):
        games = [
            pgame(21, "D", 1, 5, CWS, CLE, winner=CWS),
            pgame(22, "D", 2, 5, CWS, CLE, winner=CWS),
            pgame(23, "D", 3, 5, CLE, CWS, winner=CWS, score=(4, 0)),
        ]
        later = [pgame(30, "L", 1, 7, CWS, AL_HIGH, when="2026-10-12T00:08:00Z", official="2026-10-11")]
        row = mlb.present_series("D_2", "D", games, OCT7, later)
        self.assertEqual((row["state"], row["winner"], row["leader"]), ("over", "left", "left"))
        self.assertEqual(row["summary"], "CWS wins 3-0")
        self.assertIsNone(row["next"])
        self.assertEqual(row["advance"]["code"], "ALCS")
        self.assertEqual(row["advance"]["game"], 1)
        self.assertEqual(row["advance"]["when"], "Sun 6:08 PM")
        self.assertEqual(row["gameday"], "https://www.mlb.com/gameday/23")

    def test_undecided_seed_is_tbd(self):
        game = pgame(40, "L", 1, 7, AL_LOW, AL_HIGH, tbd=True)
        row = mlb.present_series("L_1", "L", [game], OCT7)
        self.assertEqual(row["left"], {"id": 0, "abbr": "TBD", "club": "TBD", "league": "AL", "wins": 0})
        self.assertEqual(row["league"], "AL")
        self.assertEqual(row["need"], 4)

    def test_live_game_takes_the_next_slot(self):
        games = [
            pgame(51, "D", 1, 5, LAD, ATL, winner=LAD),
            pgame(52, "D", 2, 5, LAD, ATL, live=(2, 1)),
        ]
        row = mlb.present_series("D_4", "D", games, OCT7)
        self.assertEqual(row["state"], "live")
        self.assertEqual(row["live"]["status"], "Top 6")
        self.assertEqual(row["live"]["line"], "LAD 2-1")
        self.assertIsNone(row["next"])
        self.assertEqual(row["gameday"], "https://www.mlb.com/gameday/52")

    def test_board_leads_with_the_round_being_played(self):
        feed = series_feed(
            *wild_cards_done(),
            ("D_2", [pgame(60, "D", 1, 5, CWS, TBR, when="2026-10-10T17:00:00Z")]),
            ("D_4", [pgame(61, "D", 1, 5, ATL, LAD)]),
            ("L_1", [pgame(62, "L", 1, 7, AL_LOW, AL_HIGH, tbd=True)]),
            ("W_1", [pgame(63, "W", 1, 7, WS_LOW, WS_HIGH, tbd=True)]),
        )
        board = mlb.postseason_board(feed, OCT7, 2026)
        self.assertEqual(board["title"], "Division Series")
        self.assertEqual(board["trailing"], "Best of 5")
        self.assertEqual([row["id"] for row in board["series"]], ["D_2", "D_4"])
        self.assertEqual([row["tag"] for row in board["series"]], ["AL", "NL"])
        self.assertEqual([group["title"] for group in board["earlier"]], ["Wild Card Series"])
        self.assertEqual([row["tag"] for row in board["earlier"][0]["series"]], ["ALWC", "NLWC"])
        self.assertIsNone(board["champion"])
        self.assertEqual(board["url"], "https://www.mlb.com/postseason")

    def test_an_unfinished_round_stays_up_until_every_series_in_it_ends(self):
        feed = series_feed(
            ("F_1", [pgame(1, "F", 1, 3, CWS, CLE, winner=CWS), pgame(2, "F", 2, 3, CWS, CLE, winner=CWS)]),
            ("F_2", [pgame(3, "F", 1, 3, NYA, TBR, winner=TBR), pgame(4, "F", 2, 3, NYA, TBR)]),
            ("D_2", [pgame(5, "D", 1, 5, CWS, AL_HIGH)]),
        )
        board = mlb.postseason_board(feed, OCT7, 2026)
        self.assertEqual(board["title"], "Wild Card Series")
        self.assertEqual([row["id"] for row in board["series"]], ["F_1", "F_2"])
        self.assertEqual(board["series"][0]["advance"]["code"], "ALDS")
        self.assertEqual(board["earlier"], [])

    def test_leagues_in_different_rounds_tag_each_series(self):
        feed = series_feed(
            *wild_cards_done(),
            ("D_2", [pgame(10, "D", n, 5, CWS, TBR, winner=TBR) for n in (1, 2, 3)]),
            ("D_4", [pgame(20, "D", 1, 5, ATL, LAD, winner=LAD), pgame(21, "D", 2, 5, ATL, LAD)]),
            ("L_1", [pgame(30, "L", 1, 7, NYA, TBR, winner=NYA)]),
            ("L_2", [pgame(40, "L", 1, 7, NL_LOW, LAD, tbd=True)]),
        )
        board = mlb.postseason_board(feed, OCT7, 2026)
        self.assertEqual(board["title"], "Postseason")
        self.assertEqual(board["trailing"], "")
        self.assertEqual([row["tag"] for row in board["series"]], ["ALCS", "NLDS"])
        self.assertEqual([group["round"] for group in board["earlier"]], ["D", "F"])
        self.assertEqual([row["id"] for row in board["earlier"][0]["series"]], ["D_2"])

    def test_a_pennant_winner_stays_up_until_the_world_series_is_set(self):
        feed = series_feed(
            ("L_1", [pgame(30 + n, "L", n, 7, NYA, TBR, winner=TBR) for n in (1, 2, 3, 4)]),
            ("L_2", [pgame(40, "L", 1, 7, ATL, LAD, winner=LAD), pgame(41, "L", 2, 7, ATL, LAD)]),
            ("W_1", [pgame(50, "W", 1, 7, NL_HIGH, TBR, when="2026-10-24T00:08:00Z", official="2026-10-23")]),
        )
        board = mlb.postseason_board(feed, OCT7, 2026)
        self.assertEqual(board["title"], "Championship Series")
        self.assertEqual([row["id"] for row in board["series"]], ["L_1", "L_2"])
        self.assertEqual(board["series"][0]["advance"]["code"], "WS")

    def test_world_series_then_the_champion(self):
        rounds = [
            ("L_1", [pgame(30 + n, "L", n, 7, NYA, TBR, winner=TBR) for n in (1, 2, 3, 4)]),
            ("L_2", [pgame(40 + n, "L", n, 7, ATL, LAD, winner=LAD) for n in (1, 2, 3, 4)]),
        ]
        playing = [pgame(50, "W", 1, 7, TBR, LAD, winner=LAD), pgame(51, "W", 2, 7, TBR, LAD)]
        board = mlb.postseason_board(series_feed(*rounds, ("W_1", playing)), OCT7, 2026)
        self.assertEqual(board["title"], "World Series")
        self.assertEqual(board["trailing"], "Best of 7")
        self.assertEqual([row["tag"] for row in board["series"]], [""])
        self.assertEqual([group["round"] for group in board["earlier"]], ["L"])
        self.assertIsNone(board["champion"])

        won = [pgame(60 + n, "W", n, 7, TBR, LAD, winner=TBR if n in (2, 5) else LAD) for n in range(1, 7)]
        board = mlb.postseason_board(series_feed(*rounds, ("W_1", won)), OCT7, 2026)
        self.assertEqual(board["champion"]["abbr"], "LAD")
        self.assertEqual(board["champion"]["club"], "Dodgers")
        self.assertEqual(board["champion"]["line"], "def. Rays 4-2")
        self.assertEqual(board["champion"]["gameday"], "https://www.mlb.com/gameday/66")
        self.assertEqual(board["trailing"], "2026")

    def test_empty_feed_has_no_board(self):
        self.assertIsNone(mlb.postseason_board({"series": []}, OCT7, 2026))
        self.assertIsNone(mlb.postseason_board(None, OCT7, 2026))


class StandingsTest(unittest.TestCase):
    def test_division_groups_follow_league_order(self):
        rows = [
            {"id": 147, "name": "New York Yankees", "divisionId": 201, "abbr": "NYY"},
            {"id": 111, "name": "Boston Red Sox", "divisionId": 201, "abbr": "BOS"},
            {"id": 136, "name": "Seattle Mariners", "divisionId": 200, "abbr": "SEA"},
            {"id": 119, "name": "Los Angeles Dodgers", "divisionId": 203, "abbr": "LAD"},
        ]
        groups = mlb.division_groups(rows)
        self.assertEqual([group["name"] for group in groups], ["AL East", "AL West", "NL West"])
        self.assertEqual([team["abbr"] for team in groups[0]["teams"]], ["BOS", "NYY"])
        bands = mlb.division_rows([
            {"id": 147, "name": "New York Yankees", "divisionId": 201, "abbr": "NYY"},
            {"id": 121, "name": "New York Mets", "divisionId": 204, "abbr": "NYM"},
            {"id": 114, "name": "Cleveland Guardians", "divisionId": 202, "abbr": "CLE"},
            {"id": 158, "name": "Milwaukee Brewers", "divisionId": 205, "abbr": "MIL"},
            {"id": 136, "name": "Seattle Mariners", "divisionId": 200, "abbr": "SEA"},
            {"id": 119, "name": "Los Angeles Dodgers", "divisionId": 203, "abbr": "LAD"},
        ])
        self.assertEqual([band["region"] for band in bands], ["East", "Central", "West"])
        self.assertEqual(bands[0]["al"]["name"], "AL East")
        self.assertEqual(bands[0]["nl"]["name"], "NL East")
        self.assertEqual(bands[1]["al"]["name"], "AL Central")
        self.assertEqual(bands[1]["nl"]["name"], "NL Central")
        self.assertEqual(bands[2]["al"]["name"], "AL West")
        self.assertEqual(bands[2]["nl"]["name"], "NL West")

    def test_standings_for_the_favorite_division(self):
        payload = {"records": [
            {"division": {"id": 201, "name": "American League East"}, "teamRecords": [
                {"divisionRank": "1", "wins": 96, "losses": 61, "gamesBack": "-",
                 "team": {"id": 139, "abbreviation": "TB", "name": "Tampa Bay Rays"}},
            ]},
            {"division": {"id": 200, "name": "American League West"}, "teamRecords": [
                {"divisionRank": "1", "wins": 78, "losses": 79, "gamesBack": "-",
                 "team": {"id": 117, "abbreviation": "HOU", "name": "Houston Astros"}},
                {"divisionRank": "3", "wins": 73, "losses": 84, "gamesBack": "5.0",
                 "team": {"id": 136, "abbreviation": "SEA", "name": "Seattle Mariners"}},
                {"divisionRank": "2", "wins": 78, "losses": 79, "gamesBack": "-",
                 "team": {"id": 140, "abbreviation": "TEX", "name": "Texas Rangers"}},
            ]},
        ]}
        table = mlb.present_standings(payload, 136)
        self.assertEqual(table["division"], "AL West")
        self.assertEqual([row["abbr"] for row in table["rows"]], ["HOU", "TEX", "SEA"])
        self.assertEqual(table["rows"][2]["record"], "73-84")
        self.assertEqual(table["rows"][2]["gb"], "5")
        self.assertTrue(table["rows"][2]["favorite"])
        self.assertEqual(table["rows"][0]["gb"], "—")
        self.assertEqual(table["line"], "3rd · 73-84 · 5 GB")

    def test_league_tables_default_to_the_favorite_division(self):
        reg = {"records": [
            {"division": {"id": 201, "name": "American League East"}, "teamRecords": [
                {"divisionRank": "1", "wins": 96, "losses": 61, "gamesBack": "-",
                 "team": {"id": 139, "abbreviation": "TB", "name": "Tampa Bay Rays"}},
                {"divisionRank": "2", "wins": 91, "losses": 67, "gamesBack": "5.0",
                 "team": {"id": 147, "abbreviation": "NYY", "name": "New York Yankees"}},
            ]},
            {"division": {"id": 202, "name": "American League Central"}, "teamRecords": [
                {"divisionRank": "1", "wins": 88, "losses": 70, "gamesBack": "-",
                 "team": {"id": 116, "abbreviation": "DET", "name": "Detroit Tigers"}},
            ]},
            {"division": {"id": 200, "name": "American League West"}, "teamRecords": [
                {"divisionRank": "1", "wins": 90, "losses": 68, "gamesBack": "-",
                 "team": {"id": 117, "abbreviation": "HOU", "name": "Houston Astros"}},
            ]},
            {"division": {"id": 204, "name": "National League East"}, "teamRecords": [
                {"divisionRank": "1", "wins": 95, "losses": 63, "gamesBack": "-",
                 "team": {"id": 121, "abbreviation": "NYM", "name": "New York Mets"}},
            ]},
            {"division": {"id": 205, "name": "National League Central"}, "teamRecords": [
                {"divisionRank": "1", "wins": 97, "losses": 61, "gamesBack": "-",
                 "team": {"id": 158, "abbreviation": "MIL", "name": "Milwaukee Brewers"}},
            ]},
            {"division": {"id": 203, "name": "National League West"}, "teamRecords": [
                {"divisionRank": "1", "wins": 96, "losses": 62, "gamesBack": "-",
                 "team": {"id": 119, "abbreviation": "LAD", "name": "Los Angeles Dodgers"}},
            ]},
        ]}
        wc = {"records": [
            {"league": {"id": 103}, "teamRecords": [
                {"wildCardRank": "1", "wins": 91, "losses": 67, "wildCardGamesBack": "+10.0",
                 "team": {"id": 147, "abbreviation": "NYY", "name": "New York Yankees"}},
                {"wildCardRank": "2", "wins": 85, "losses": 73, "wildCardGamesBack": "+4.0",
                 "team": {"id": 111, "abbreviation": "BOS", "name": "Boston Red Sox"}},
            ]},
            {"league": {"id": 104}, "teamRecords": [
                {"wildCardRank": "1", "wins": 88, "losses": 70, "wildCardGamesBack": "+1.0",
                 "team": {"id": 119, "abbreviation": "LAD", "name": "Los Angeles Dodgers"}},
            ]},
        ]}
        tables = mlb.present_tables(reg, wc, 147)
        self.assertEqual(tables["division"], "AL East")
        self.assertEqual(tables["divisionId"], 201)
        self.assertEqual(tables["defaultLeague"], "AL")
        self.assertEqual(tables["defaultTable"], 201)
        self.assertEqual([league["id"] for league in tables["leagues"]], ["AL", "NL"])
        al = tables["leagues"][0]
        self.assertEqual([table["label"] for table in al["tables"]], ["East", "Central", "West", "WC"])
        self.assertEqual(al["tables"][0]["title"], "AL East")
        self.assertEqual([row["abbr"] for row in al["tables"][0]["rows"]], ["TB", "NYY"])
        wild = al["tables"][3]
        self.assertEqual(wild["kind"], "wildcard")
        self.assertEqual(wild["title"], "AL Wild Card")
        self.assertEqual([row["abbr"] for row in wild["rows"]], ["NYY", "BOS"])
        self.assertEqual(wild["rows"][0]["gb"], "+10")
        self.assertEqual(wild["rows"][1]["gb"], "+4")
        self.assertTrue(wild["rows"][0]["favorite"])
        self.assertFalse(wild["rows"][1]["favorite"])
        nl = tables["leagues"][1]
        self.assertEqual([table["label"] for table in nl["tables"]], ["East", "Central", "West", "WC"])
        self.assertEqual(nl["tables"][3]["rows"][0]["abbr"], "LAD")

    def test_wild_card_table_sorts_and_caps_the_chase(self):
        clubs = [(147, "NYY"), (111, "BOS"), (145, "CWS"), (140, "TEX"),
                 (136, "SEA"), (114, "CLE"), (110, "BAL")]
        backs = ["+10.0", "+4.0", "-", "3.0", "4.5", "6.0", "9.0"]
        entries = [{
            "wildCardRank": str(rank), "wins": 90 - rank, "losses": 60 + rank,
            "wildCardGamesBack": back,
            "team": {"id": tid, "abbreviation": abbr, "name": abbr},
        } for rank, ((tid, abbr), back) in enumerate(zip(clubs, backs), start=1)]
        table = mlb.wild_card_table(list(reversed(entries)), "AL", 147)
        self.assertEqual(table["id"], "WC")
        self.assertEqual(len(table["rows"]), mlb.MAX_WC_ROWS)
        self.assertEqual([row["abbr"] for row in table["rows"]],
                         ["NYY", "BOS", "CWS", "TEX", "SEA", "CLE"])
        self.assertEqual([row["gb"] for row in table["rows"]],
                         ["+10", "+4", "—", "3", "4.5", "6"])
        self.assertEqual([row["rank"] for row in table["rows"]],
                         ["1", "2", "3", "4", "5", "6"])

    def test_missing_wild_card_feed_keeps_the_divisions(self):
        reg = {"records": [
            {"division": {"id": 201, "name": "American League East"}, "teamRecords": [
                {"divisionRank": "2", "wins": 91, "losses": 67, "gamesBack": "5.0",
                 "team": {"id": 147, "abbreviation": "NYY", "name": "New York Yankees"}},
            ]},
        ]}
        tables = mlb.present_tables(reg, None, 147)
        self.assertEqual(tables["defaultLeague"], "AL")
        self.assertEqual(tables["defaultTable"], 201)
        self.assertEqual([table["label"] for table in tables["leagues"][0]["tables"]], ["East"])
        self.assertEqual(tables["leagues"][1]["tables"], [])

    def test_tables_need_the_favorite_in_the_feed(self):
        reg = {"records": [{"division": {"id": 201, "name": "d"}, "teamRecords": []}]}
        self.assertIsNone(mlb.present_tables(reg, None, 999))
        self.assertIsNone(mlb.present_tables(reg, None, None))


class ChooseTest(unittest.TestCase):
    def test_no_club_lists_only_live_games(self):
        live_a = raw(pk=1, away=WSH, home=DET, abstract="Live", when="2026-09-23T17:10:00Z", balls=1, strikes=2, outs=0)
        live_b = raw(pk=2, away=TB, home=NYY, abstract="Live", when="2026-09-23T23:05:00Z", balls=0, strikes=0, outs=1)
        later = raw(pk=3, away=COL, home=NYY, abstract="Preview", when="2026-09-24T23:00:00Z", official="2026-09-24")
        hidden = raw(pk=4, away=WSH, home=DET, abstract="Live", public=False)
        view = mlb.choose_view(None, [live_b, later, live_a, hidden], [], missed_playoffs=False, now=NOW)
        self.assertEqual(view["mode"], "board")
        self.assertEqual(view["banner"], "Live")
        self.assertEqual([game["gamePk"] for game in view["games"]], [1, 2])
        self.assertEqual(view["pollMs"], mlb.POLL_LIVE_MS)
        self.assertEqual(view["games"][0]["countLine"], "1-2 · 0 outs")

    def test_one_live_game_uses_the_full_score(self):
        live = raw(pk=8, away=WSH, home=DET, abstract="Live", balls=0, strikes=0, outs=0)
        view = mlb.choose_view(None, [live], [], missed_playoffs=False, now=NOW)
        self.assertEqual(view["mode"], "live")
        self.assertEqual(view["focus"]["gamePk"], 8)
        self.assertEqual(view["games"], [])
        self.assertEqual(view["focus"]["countLine"], "0-0 · 0 outs")

    def test_no_live_games_offer_the_next_start(self):
        upcoming = raw(pk=9, away=TB, home=NYY, abstract="Preview",
                       when="2026-09-23T23:05:00Z", official="2026-09-23")
        view = mlb.choose_view(None, [upcoming], [], missed_playoffs=False, now=NOW)
        self.assertEqual(view["mode"], "empty")
        self.assertEqual(view["next"]["kicker"], "First pitch")
        self.assertEqual(view["next"]["when"], "Today 6:05 PM")
        self.assertEqual(view["next"]["where"], "TB at NYY")

    def test_favorite_live_game_ignores_the_rest_of_the_slate(self):
        theirs = raw(pk=1, away=WSH, home=DET, abstract="Live", when="2026-09-23T17:00:00Z")
        ours = raw(pk=2, away=TB, home=NYY, abstract="Live", when="2026-09-23T23:05:00Z",
                   balls=2, strikes=2, outs=1, batter="Aaron Judge", pitcher="Shane Baz")
        view = mlb.choose_view(147, [theirs, ours], [ours], missed_playoffs=False, now=NOW)
        self.assertEqual(view["mode"], "live")
        self.assertEqual(view["focus"]["gamePk"], 2)
        self.assertEqual(view["focus"]["favorite"], "home")
        self.assertEqual(view["focus"]["batter"], "Aaron Judge")
        self.assertIsNone(view["next"])

    def test_between_games_uses_the_later_final_and_the_next_start(self):
        early = raw(pk=1, away=TB, home=NYY, when="2026-09-22T17:05:00Z", official="2026-09-22",
                    away_score=0, home_score=2, number=1)
        late = raw(pk=2, away=TB, home=NYY, when="2026-09-22T23:05:00Z", official="2026-09-22",
                   away_score=6, home_score=1, number=2, innings=[(0, 0), (2, 1), (4, 0)])
        postponed = raw(pk=3, away=TB, home=NYY, abstract="Preview", detailed="Postponed",
                        when="2026-09-23T17:00:00Z", official="2026-09-23")
        nxt = raw(pk=4, away=TB, home=NYY, abstract="Preview",
                  when="2026-09-23T23:05:00Z", official="2026-09-23")
        view = mlb.choose_view(147, [], [early, postponed, nxt, late], missed_playoffs=False, now=NOW)
        self.assertEqual(view["mode"], "final")
        self.assertEqual(view["focus"]["gamePk"], 2)
        self.assertEqual(view["focus"]["status"], "Final")
        self.assertEqual(view["focus"]["away"]["score"], "6")
        self.assertEqual(view["focus"]["away"]["innings"], ["0", "2", "4", "", "", "", "", "", ""])
        self.assertEqual(view["next"]["gamePk"], 4)
        self.assertEqual(view["next"]["when"], "Today 6:05 PM")
        self.assertEqual(view["next"]["where"], "vs Rays")
        self.assertEqual(view["pollMs"], mlb.POLL_IDLE_MS)

    def test_no_live_games_in_the_postseason_show_the_series_board(self):
        board = mlb.postseason_board(series_feed(*wild_cards_done()), OCT7, 2026)
        upcoming = raw(pk=9, away=TB, home=NYY, abstract="Preview", when="2026-10-07T23:05:00Z")
        view = mlb.choose_view(None, [upcoming], [], missed_playoffs=False, now=OCT7, postseason=board)
        self.assertEqual(view["mode"], "series")
        self.assertEqual(view["banner"], "Postseason")
        self.assertIs(view["postseason"], board)
        self.assertEqual(view["pollMs"], mlb.POLL_IDLE_MS)
        live_a = raw(pk=1, away=WSH, home=DET, abstract="Live")
        live_b = raw(pk=2, away=TB, home=NYY, abstract="Live", when="2026-09-23T23:05:00Z")
        view = mlb.choose_view(None, [live_a, live_b], [], missed_playoffs=False, now=OCT7, postseason=board)
        self.assertEqual(view["mode"], "board")
        self.assertIsNone(view["postseason"])

    def test_club_that_missed_the_playoffs_gets_the_live_slate(self):
        old = raw(pk=1, away=COL, home=NYY, when="2026-09-22T20:00:00Z")
        live = raw(pk=2, away=WSH, home=DET, abstract="Live", balls=1, strikes=0, outs=2)
        other = raw(pk=3, away=TB, home=NYY, abstract="Live", when="2026-09-23T23:00:00Z")
        view = mlb.choose_view(115, [live, other], [old], missed_playoffs=True, now=NOW)
        self.assertEqual(view["mode"], "board")
        self.assertEqual(view["reason"], "playoffs")
        self.assertEqual(view["banner"], "Playoffs")
        self.assertEqual([game["gamePk"] for game in view["games"]], [2, 3])
        self.assertIsNone(view["focus"])


class CollectTest(unittest.TestCase):
    def test_regular_season_window_and_no_postseason_request(self):
        final = raw(pk=2, away=TB, home=NYY, when="2026-09-22T23:05:00Z", away_score=6, home_score=1)
        nxt = raw(pk=4, away=TB, home=NYY, abstract="Preview",
                  when="2026-09-23T23:05:00Z", official="2026-09-23")
        fetch = Fetch([
            (lambda url: "/seasons?" in url, season()),
            (lambda url: "/schedule?" in url and "gameTypes=" not in url, schedule([])),
            (lambda url: "/teams/147?" in url, team_payload([final], [nxt])),
        ])
        view = mlb.collect(147, NOW, fetch)
        self.assertEqual(view["mode"], "final")
        self.assertEqual(view["focus"]["gamePk"], 2)
        self.assertEqual(view["next"]["when"], "Today 6:05 PM")
        self.assertTrue(any("startDate=2026-09-22" in url and "endDate=2026-09-24" in url for url in fetch.urls))
        self.assertFalse(any("gameTypes=" in url for url in fetch.urls))
        self.assertFalse(any("/teams/147?" in url and "previousSchedule" not in url for url in fetch.urls))

    def test_final_view_loads_division_and_wild_card_standings(self):
        final = raw(pk=2, away=TB, home=NYY, when="2026-09-22T23:05:00Z", away_score=6, home_score=1)
        nxt = raw(pk=4, away=TB, home=NYY, abstract="Preview",
                  when="2026-09-23T23:05:00Z", official="2026-09-23")
        reg = {"records": [
            {"division": {"id": 201, "name": "American League East"}, "teamRecords": [
                {"divisionRank": "1", "wins": 96, "losses": 61, "gamesBack": "-",
                 "team": {"id": 139, "abbreviation": "TB", "name": "Tampa Bay Rays"}},
                {"divisionRank": "2", "wins": 91, "losses": 67, "gamesBack": "5.0",
                 "team": {"id": 147, "abbreviation": "NYY", "name": "New York Yankees"}},
            ]},
        ]}
        wc = {"records": [
            {"league": {"id": 103}, "teamRecords": [
                {"wildCardRank": "1", "wins": 91, "losses": 67, "wildCardGamesBack": "+10.0",
                 "team": {"id": 147, "abbreviation": "NYY", "name": "New York Yankees"}},
            ]},
        ]}
        fetch = Fetch([
            (lambda url: "/seasons?" in url, season()),
            (lambda url: "/schedule?" in url and "gameTypes=" not in url, schedule([])),
            (lambda url: "/teams/147?" in url, team_payload([final], [nxt])),
            (lambda url: "standingsTypes=regularSeason" in url, reg),
            (lambda url: "standingsTypes=wildCard" in url, wc),
        ])
        view = mlb.collect(147, NOW, fetch)
        self.assertEqual(view["mode"], "final")
        standings = view["standings"]
        self.assertEqual(standings["defaultLeague"], "AL")
        self.assertEqual(standings["defaultTable"], 201)
        self.assertEqual([league["id"] for league in standings["leagues"]], ["AL", "NL"])
        self.assertEqual([table["label"] for table in standings["leagues"][0]["tables"]], ["East", "WC"])
        self.assertTrue(any("standingsTypes=wildCard" in url for url in fetch.urls))

    def test_next_game_tv_comes_from_the_team_schedule(self):
        final = raw(pk=2, away=TB, home=NYY, when="2026-09-22T23:05:00Z", away_score=6, home_score=1)
        nxt = raw(pk=4, away=TB, home=NYY, abstract="Preview",
                  when="2026-09-23T23:05:00Z", official="2026-09-23",
                  broadcasts=[{"type": "TV", "name": "YES", "callSign": "YES",
                               "homeAway": "home", "isNational": False}])
        fetch = Fetch([
            (lambda url: "/seasons?" in url, season()),
            (lambda url: "/schedule?" in url and "gameTypes=" not in url, schedule([])),
            (lambda url: "/teams/147?" in url, team_payload([final], [nxt])),
        ])
        view = mlb.collect(147, NOW, fetch)
        self.assertEqual(view["mode"], "final")
        self.assertEqual(view["next"]["tv"], "YES")
        self.assertTrue(any("/teams/147?" in url and "broadcasts" in url for url in fetch.urls))

    def test_live_club_skips_the_team_hydrate(self):
        live = raw(pk=8, away=TB, home=NYY, abstract="Live", when="2026-09-23T18:00:00Z",
                   balls=3, strikes=1, outs=2, batter="Aaron Judge", pitcher="Drew Rasmussen")
        fetch = Fetch([
            (lambda url: "/seasons?" in url, season()),
            (lambda url: "/schedule?" in url and "gameTypes=" not in url, schedule([live])),
        ])
        view = mlb.collect(147, NOW, fetch)
        self.assertEqual(view["mode"], "live")
        self.assertEqual(view["focus"]["batter"], "Aaron Judge")
        self.assertEqual(view["focus"]["bases"], [False, False, False])
        self.assertFalse(any("/teams/147?" in url for url in fetch.urls))
        self.assertFalse(any("/standings?" in url for url in fetch.urls))
        self.assertIsNone(view["standings"])

    def test_after_midnight_eastern_the_window_includes_yesterday(self):
        now = datetime(2026, 9, 24, 2, 0, tzinfo=EASTERN)
        fetch = Fetch([
            (lambda url: "/seasons?" in url, season()),
            (lambda url: "/schedule?" in url, schedule([])),
        ])
        view = mlb.collect(0, now, fetch)
        self.assertEqual(view["mode"], "empty")
        self.assertTrue(any("startDate=2026-09-23" in url and "endDate=2026-09-25" in url for url in fetch.urls))
        self.assertFalse(any("/postseason/series?" in url for url in fetch.urls))

    def test_postseason_slate_with_nothing_live_loads_the_series(self):
        fetch = Fetch([
            (lambda url: "/seasons?" in url, season()),
            (lambda url: "/postseason/series?" in url, series_feed(*wild_cards_done())),
            (lambda url: "/schedule?" in url, schedule([])),
        ])
        view = mlb.collect(0, OCT7, fetch)
        self.assertEqual(view["mode"], "series")
        self.assertEqual(view["postseason"]["title"], "Wild Card Series")
        self.assertFalse(any("/standings?" in url for url in fetch.urls))

    def test_postseason_slate_with_live_games_skips_the_series(self):
        live = raw(pk=20, away=WSH, home=DET, abstract="Live")
        fetch = Fetch([
            (lambda url: "/seasons?" in url, season()),
            (lambda url: "/schedule?" in url, schedule([live])),
        ])
        view = mlb.collect(0, OCT7, fetch)
        self.assertEqual(view["mode"], "live")
        self.assertFalse(any("/seasons?" in url or "/postseason/series?" in url for url in fetch.urls))

    def test_series_feed_failure_keeps_the_empty_slate(self):
        fetch = Fetch([
            (lambda url: "/seasons?" in url, season()),
            (lambda url: "/postseason/series?" in url, OSError("down")),
            (lambda url: "/schedule?" in url, schedule([])),
        ])
        view = mlb.collect(0, OCT7, fetch)
        self.assertTrue(view["ok"])
        self.assertEqual(view["mode"], "empty")
        self.assertIsNone(view["postseason"])

    def test_club_out_of_the_playoffs_gets_the_series_board(self):
        fetch = Fetch([
            (lambda url: "/seasons?" in url, season()),
            (lambda url: "gameTypes=" in url, schedule([])),
            (lambda url: "/postseason/series?" in url, series_feed(*wild_cards_done())),
            (lambda url: "/schedule?" in url, schedule([])),
        ])
        view = mlb.collect(115, OCT7, fetch)
        self.assertEqual(view["mode"], "series")
        self.assertEqual(view["banner"], "Playoffs")
        self.assertEqual(view["reason"], "playoffs")
        self.assertEqual(sum("/seasons?" in url for url in fetch.urls), 1)
        self.assertIsNone(view["standings"])

    def test_missed_playoffs_does_not_load_the_club_schedule(self):
        now = datetime(2026, 9, 29, 14, 0, tzinfo=EASTERN)
        live = raw(pk=20, away=WSH, home=DET, abstract="Live")
        other = raw(pk=21, away=TB, home=NYY, abstract="Live", when="2026-09-29T20:00:00Z")
        fetch = Fetch([
            (lambda url: "/seasons?" in url, season()),
            (lambda url: "gameTypes=" in url, schedule([])),
            (lambda url: "/schedule?" in url and "gameTypes=" not in url, schedule([live, other])),
        ])
        view = mlb.collect(115, now, fetch)
        self.assertEqual(view["reason"], "playoffs")
        self.assertEqual(view["mode"], "board")
        self.assertEqual([game["gamePk"] for game in view["games"]], [20, 21])
        self.assertFalse(any("/teams/115?" in url for url in fetch.urls))

    def test_qualified_club_shows_the_next_series_when_the_time_is_tbd(self):
        now = datetime(2026, 9, 29, 14, 0, tzinfo=EASTERN)
        last = raw(pk=30, away=TB, home=NYY, when="2026-09-27T23:00:00Z", official="2026-09-27",
                   away_score=2, home_score=5)
        series = raw(pk=40, away=(4944, "", "AL Wild Card #3"), home=NYY, abstract="Preview",
                     when="2026-09-29T23:00:00Z", official="2026-09-29", tbd=True, away_score=None, home_score=None)
        fetch = Fetch([
            (lambda url: "/seasons?" in url, season()),
            (lambda url: "gameTypes=" in url, schedule([series])),
            (lambda url: "/schedule?" in url and "gameTypes=" not in url, schedule([])),
            (lambda url: "/teams/147?" in url, team_payload([last], [])),
        ])
        view = mlb.collect(147, now, fetch)
        self.assertEqual(view["mode"], "final")
        self.assertEqual(view["focus"]["gamePk"], 30)
        self.assertEqual(view["focus"]["home"]["score"], "5")
        self.assertEqual(view["next"]["when"], "Today, time TBD")
        self.assertEqual(view["next"]["where"], "vs AL Wild Card #3")
        self.assertEqual(view["next"]["gameday"], "https://www.mlb.com/gameday/40")

    def test_hidden_game_is_not_a_live_game(self):
        hidden = raw(pk=4, away=WSH, home=DET, abstract="Live", public=False)
        self.assertEqual(mlb.games_from_schedule(schedule([hidden])), [])

    def test_network_failure_is_an_error_view(self):
        fetch = Fetch([(lambda url: True, OSError("down"))])
        view = mlb.collect(147, NOW, fetch)
        self.assertFalse(view["ok"])
        self.assertEqual(view["error"], "Scores unavailable")
        self.assertIsNone(view["focus"])


if __name__ == "__main__":
    unittest.main()
