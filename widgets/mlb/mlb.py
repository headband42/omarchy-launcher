#!/usr/bin/env python3
"""MLB tile model. Stdlib only. Tests call collect() with a fake fetch.

    mlb.py [--team ID]   the tile
    mlb.py --teams       the club list for the settings panel

The tile follows one club (`teamId` in the widget settings). A live game shows
the line score, count, bases, batter, and pitcher. Between games it shows the
last final line score and when the next game starts. With no club, or during
the postseason when that club has no postseason games, it shows the live slate.
When nothing is live during the postseason, the slate is the series board:
each series in the round being played, then earlier rounds' results.
"""

import json
import sys
from datetime import date, datetime, timedelta
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo

API = "https://statsapi.mlb.com/api/v1"
MLB_TZ = ZoneInfo("America/New_York")
# Short names and the order the settings grid uses. Ids are MLB's division ids.
DIVISIONS = (
    (201, "AL East"),
    (202, "AL Central"),
    (200, "AL West"),
    (204, "NL East"),
    (205, "NL Central"),
    (203, "NL West"),
)
POLL_LIVE_MS = 15000
POLL_IDLE_MS = 60000
MAX_INNINGS = 11
# League ids the standings feed uses, and the short names the switcher shows.
LEAGUES = ((103, "AL"), (104, "NL"))
DIVISION_LEAGUE = {201: "AL", 202: "AL", 200: "AL", 204: "NL", 205: "NL", 203: "NL"}
DIVISION_REGION = {201: "East", 202: "Central", 200: "West", 204: "East", 205: "Central", 203: "West"}
# A wild-card table much longer than a division table would push the box score off the tile.
MAX_WC_ROWS = 6

_WEEKDAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
_MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
_SUFFIXES = {"jr", "jr.", "sr", "sr.", "ii", "iii", "iv", "v"}
_HALF = {"Top": "Top", "Bottom": "Bot", "Middle": "Mid", "End": "End"}
_LIVE_DETAIL = {
    "Delayed": "Delay",
    "Delayed Start": "Delay",
    "Manager Challenge": "Challenge",
    "Game Advisory": "Advisory",
    "Instant Replay": "Review",
    "Review": "Review",
}


def error_view():
    return {
        "ok": False,
        "error": "Scores unavailable",
        "mode": "empty",
        "banner": "MLB",
        "reason": "",
        "pollMs": POLL_IDLE_MS,
        "focus": None,
        "games": [],
        "next": None,
        "standings": None,
        "postseason": None,
    }


def team_id_from_settings(settings):
    if not isinstance(settings, dict):
        return None
    raw = settings.get("teamId")
    if isinstance(raw, bool) or raw is None:
        return None
    if isinstance(raw, str):
        text = raw.strip()
        if not text.isdigit():
            return None
        raw = int(text)
    if isinstance(raw, float):
        if not raw.is_integer():
            return None
        raw = int(raw)
    if isinstance(raw, int) and 0 < raw <= 999999:
        return raw
    return None


def settings_for_team(team_id):
    pk = team_id_from_settings({"teamId": team_id})
    if not pk:
        return {}
    return {"teamId": pk}


def team_catalog(payload):
    rows = []
    for team in (payload or {}).get("teams") or []:
        if not isinstance(team, dict) or team.get("active") is False:
            continue
        sport = team.get("sport") if isinstance(team.get("sport"), dict) else {}
        sport_id = as_int(sport.get("id"))
        if sport_id not in (None, 1):
            continue
        pk = as_int(team.get("id"))
        name = str(team.get("name") or "").strip()
        if not pk or not name:
            continue
        division = team.get("division") if isinstance(team.get("division"), dict) else {}
        rows.append({
            "id": pk,
            "abbr": str(team.get("abbreviation") or "").strip(),
            "name": name,
            "location": str(team.get("locationName") or "").strip(),
            "club": str(team.get("teamName") or name).strip(),
            "divisionId": as_int(division.get("id")) or 0,
        })
    rows.sort(key=lambda row: (row["name"].casefold(), row["id"]))
    return rows


def division_groups(rows):
    known = {division_id for division_id, _name in DIVISIONS}
    buckets = {division_id: [] for division_id in known}
    other = []
    for row in rows or []:
        if not isinstance(row, dict):
            continue
        division_id = as_int(row.get("divisionId")) or 0
        if division_id in buckets:
            buckets[division_id].append(row)
        else:
            other.append(row)
    groups = []
    for division_id, name in DIVISIONS:
        teams = buckets[division_id]
        if teams:
            teams.sort(key=lambda row: (str(row.get("name") or "").casefold(), row.get("id") or 0))
            groups.append({"id": division_id, "name": name, "teams": teams})
    if other:
        other.sort(key=lambda row: (str(row.get("name") or "").casefold(), row.get("id") or 0))
        groups.append({"id": 0, "name": "Other", "teams": other})
    return groups


# Settings puts the American League in the left column and the National
# League in the right, with East, Central, and West sharing a row.
DIVISION_ROWS = (
    ("East", 201, 204),
    ("Central", 202, 205),
    ("West", 200, 203),
)


def division_rows(rows):
    by_id = {group["id"]: group for group in division_groups(rows)}
    bands = []
    for region, al_id, nl_id in DIVISION_ROWS:
        al = by_id.get(al_id)
        nl = by_id.get(nl_id)
        if not al and not nl:
            continue
        bands.append({"region": region, "al": al, "nl": nl})
    return bands


def as_int(value):
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, str):
        value = value.strip()
        if not value:
            return None
    try:
        number = float(value) if isinstance(value, str) else value
        if isinstance(number, float) and not float(number).is_integer():
            return None
        return int(number)
    except (TypeError, ValueError):
        return None


def gameday_url(game_pk):
    pk = as_int(game_pk)
    if pk is None or pk <= 0:
        return ""
    return f"https://www.mlb.com/gameday/{pk}"


def aware(now):
    if now.tzinfo is None:
        return now.replace(tzinfo=ZoneInfo("UTC"))
    return now


def mlb_day(now):
    return aware(now).astimezone(MLB_TZ).date()


def _quote(value, safe, encoding, errors):
    return quote(str(value), safe=f"{safe}(),", encoding=encoding, errors=errors)


def _url(path, **params):
    query = urlencode(params, quote_via=_quote)
    return f"{API}/{path}?{query}" if query else f"{API}/{path}"


def season_url(year):
    return _url("seasons", sportId=1, season=year)


def window_url(day):
    return _url(
        "schedule",
        sportId=1,
        startDate=(day - timedelta(days=1)).isoformat(),
        endDate=(day + timedelta(days=1)).isoformat(),
        hydrate="linescore,team,decisions,probablePitcher,broadcasts,seriesStatus",
    )


def postseason_url(team_id, year):
    return _url(
        "schedule",
        sportId=1,
        teamId=team_id,
        season=year,
        gameTypes="F,D,L,W",
        hydrate="linescore,team,decisions,probablePitcher,broadcasts,seriesStatus",
    )


# The series feed hydrates every club in full, about 500 KB a poll. These are
# the only fields the board reads; `fields` cuts the reply to under 100 KB.
# A name here matches that key at any depth.
SERIES_FIELDS = (
    "series", "id", "gameType", "games", "gamePk", "gameDate", "officialDate", "publicFacing",
    "status", "abstractGameState", "detailedState", "startTimeTBD",
    "teams", "away", "home", "team", "name", "abbreviation", "teamName", "placeholder", "league",
    "score", "isWinner", "probablePitcher", "fullName",
    "seriesStatus", "gameNumber", "totalGames", "isOver", "seriesGameNumber", "gamesInSeries",
    "broadcasts", "type", "callSign", "isNational", "homeAway",
    "linescore", "currentInning", "inningState",
)


def series_url(year):
    return _url(
        "schedule/postseason/series",
        sportId=1,
        season=year,
        hydrate="team,seriesStatus,probablePitcher,broadcasts,linescore",
        fields=",".join(SERIES_FIELDS),
    )


def people_url(ids):
    return _url("people", personIds=",".join(str(int(i)) for i in ids))


def team_url(team_id):
    # The next game needs broadcasts for its TV channel. The window hydrate
    # has them, but a game past the window only comes from here.
    return _url(
        f"teams/{int(team_id)}",
        hydrate="previousSchedule(linescore,team,decisions),nextSchedule(team,linescore,probablePitcher,broadcasts)",
    )


def teams_url(now):
    return _url("teams", sportId=1, season=mlb_day(now).year)


def standings_url(year, kinds="regularSeason"):
    return _url(
        "standings",
        leagueId="103,104",
        season=year,
        standingsTypes=kinds,
        hydrate="team,division",
    )


def fetch_json(url, timeout=12):
    request = Request(url, headers={"Accept": "application/json", "User-Agent": "omarchy-launcher-mlb"})
    with urlopen(request, timeout=timeout) as response:
        return json.load(response)


def games_from_schedule(payload):
    games = []
    for day in (payload or {}).get("dates") or []:
        if not isinstance(day, dict):
            continue
        for game in day.get("games") or []:
            if isinstance(game, dict) and game.get("publicFacing") is not False:
                games.append(game)
    return games


def games_from_team_payload(payload):
    teams = (payload or {}).get("teams") or []
    if not teams or not isinstance(teams[0], dict):
        return []
    games = []
    for key in ("previousGameSchedule", "nextGameSchedule"):
        games.extend(games_from_schedule(teams[0].get(key)))
    return games


def season_record(payload, year):
    rows = (payload or {}).get("seasons") or []
    for row in rows:
        if isinstance(row, dict) and str(row.get("seasonId") or "") == str(year):
            return row
    for row in rows:
        if isinstance(row, dict):
            return row
    return {}


def in_postseason(season, day):
    start = str((season or {}).get("postSeasonStartDate") or "")
    end = str((season or {}).get("postSeasonEndDate") or "")
    if not start or not end:
        return False
    iso = day.isoformat()
    return start <= iso <= end


def classify_game(game):
    status = game.get("status") if isinstance(game.get("status"), dict) else {}
    abstract = str(status.get("abstractGameState") or "")
    detailed = str(status.get("detailedState") or "")
    if detailed in {"Postponed", "Cancelled"}:
        return "skip", detailed
    if abstract == "Final" or detailed in {"Final", "Game Over", "Completed Early"}:
        return "final", detailed
    if abstract == "Live":
        return "live", detailed
    if abstract == "Preview":
        return "preview", detailed
    return "skip", detailed


def game_sort_key(game):
    status = game.get("status") if isinstance(game.get("status"), dict) else {}
    return (
        str(game.get("gameDate") or ""),
        as_int(game.get("gameNumber")) or 0,
        as_int(game.get("gamePk")) or 0,
        1 if status.get("startTimeTBD") else 0,
    )


def team_side_ids(game):
    teams = game.get("teams") if isinstance(game.get("teams"), dict) else {}
    found = []
    for side in ("away", "home"):
        block = teams.get(side) if isinstance(teams.get(side), dict) else {}
        team = block.get("team") if isinstance(block.get("team"), dict) else {}
        pk = as_int(team.get("id"))
        if pk:
            found.append(pk)
    return found


def involves(game, team_id):
    return bool(team_id) and team_id in team_side_ids(game)


def dedupe_games(games):
    seen = set()
    out = []
    for game in games:
        pk = as_int(game.get("gamePk"))
        key = ("pk", pk) if pk is not None else ("obj", id(game))
        if key in seen:
            continue
        seen.add(key)
        out.append(game)
    return out


def person_name(node):
    if not isinstance(node, dict):
        return ""
    return str(node.get("fullName") or node.get("name") or "").strip()


def last_name(full):
    raw = [part for part in str(full or "").replace(",", " ").split() if part]
    parts = [part for part in raw if part.lower() not in _SUFFIXES]
    if parts:
        return parts[-1]
    return raw[-1] if raw else ""


def short_name(team):
    if not isinstance(team, dict):
        return "TBD"
    abbr = str(team.get("abbreviation") or "").strip()
    if abbr:
        return abbr[:6]
    name = str(team.get("teamName") or team.get("name") or "").strip()
    if not name:
        return "TBD"
    if "#" in name:
        head = name.split()[0]
        tag = name[name.rfind("#"):].replace(" ", "")
        return f"{head}{tag}"[:6]
    if len(name) <= 6:
        return name
    return name[:3].upper()


def club_name(team):
    if not isinstance(team, dict):
        return "TBD"
    return str(team.get("teamName") or team.get("name") or short_name(team) or "TBD")


def num_text(value):
    number = as_int(value)
    if number is None:
        return "–"
    return str(number)


def side_info(game, linescore, side):
    teams = game.get("teams") if isinstance(game.get("teams"), dict) else {}
    block = teams.get(side) if isinstance(teams.get(side), dict) else {}
    team = block.get("team") if isinstance(block.get("team"), dict) else {}
    scored = linescore.get("teams") if isinstance(linescore, dict) and isinstance(linescore.get("teams"), dict) else {}
    line = scored.get(side) if isinstance(scored.get(side), dict) else {}
    runs = line.get("runs") if "runs" in line else block.get("score")
    return {
        "id": as_int(team.get("id")) or 0,
        "abbr": short_name(team),
        "club": club_name(team),
        "name": str(team.get("name") or club_name(team)),
        "score": num_text(runs),
        "hits": num_text(line.get("hits")) if "hits" in line else "–",
        "errors": num_text(line.get("errors")) if "errors" in line else "–",
        "record": record_text(block.get("leagueRecord")),
    }


def cell_runs(cell, side):
    block = cell.get(side) if isinstance(cell, dict) else None
    if not isinstance(block, dict) or block.get("runs") is None:
        return ""
    number = as_int(block.get("runs"))
    return "" if number is None else str(number)


def inning_columns(linescore):
    innings = linescore.get("innings") if isinstance(linescore, dict) else None
    if not isinstance(innings, list):
        innings = []
    scheduled = as_int(linescore.get("scheduledInnings")) if isinstance(linescore, dict) else None
    count = max(scheduled or 9, len(innings))
    labels, away, home = [], [], []
    for index in range(count):
        labels.append(str(index + 1))
        cell = innings[index] if index < len(innings) and isinstance(innings[index], dict) else {}
        away.append(cell_runs(cell, "away"))
        home.append(cell_runs(cell, "home"))
    # A long extra-inning game keeps the latest columns. The tile cannot show the 1st.
    if len(labels) > MAX_INNINGS:
        labels = labels[-MAX_INNINGS:]
        away = away[-MAX_INNINGS:]
        home = home[-MAX_INNINGS:]
    return labels, away, home


def half_label(linescore):
    if not isinstance(linescore, dict):
        return ""
    state = str(linescore.get("inningState") or "")
    inning = as_int(linescore.get("currentInning"))
    word = _HALF.get(state, state)
    if word and inning:
        return f"{word} {inning}"
    return word


def status_label(state, detailed, linescore):
    detailed = str(detailed or "")
    if state == "final":
        played = as_int((linescore or {}).get("currentInning")) if isinstance(linescore, dict) else None
        if not played:
            played = len((linescore or {}).get("innings") or []) if isinstance(linescore, dict) else 0
        scheduled = as_int((linescore or {}).get("scheduledInnings")) if isinstance(linescore, dict) else None
        if played and played > (scheduled or 9):
            return f"Final/{played}"
        return "Final"
    if state == "live":
        if detailed == "Warmup":
            return "Warmup"
        half = half_label(linescore)
        if detailed in ("", "In Progress"):
            return half or "Live"
        short = _LIVE_DETAIL.get(detailed, detailed)
        if half:
            return f"{short} · {half}"
        return short or "Live"
    return detailed or "Scheduled"


def games_back(value):
    text = str(value if value is not None else "").strip()
    if text in ("", "-", "—"):
        return "—"
    if text.endswith(".0"):
        return text[:-2]
    return text


def ordinal(value):
    number = as_int(value)
    if not number:
        return ""
    if 10 <= number % 100 <= 20:
        suffix = "th"
    else:
        suffix = {1: "st", 2: "nd", 3: "rd"}.get(number % 10, "th")
    return f"{number}{suffix}"


def decision_line(winner, loser, save):
    parts = []
    if winner:
        parts.append("W " + last_name(winner))
    if loser:
        parts.append("L " + last_name(loser))
    if save:
        parts.append("S " + last_name(save))
    return " · ".join(parts)


def pitcher_matchup(away_name, home_name):
    away = last_name(away_name)
    home = last_name(home_name)
    if away and home:
        return f"{away} vs {home}"
    return away or home


def record_text(league):
    if not isinstance(league, dict):
        return ""
    wins = as_int(league.get("wins"))
    losses = as_int(league.get("losses"))
    if wins is None or losses is None:
        return ""
    return f"{wins}-{losses}"


def channel_label(broadcast):
    sign = str(broadcast.get("callSign") or "").strip()
    if sign:
        return sign
    name = str(broadcast.get("name") or "").strip()
    if "/" in name:
        name = name.split("/", 1)[0].strip()
    return name


def tv_channel(broadcasts, favorite):
    # A national telecast replaces the club feed. Otherwise use the selected
    # club's side. Radio entries are not a channel.
    rows = []
    for item in broadcasts or []:
        if not isinstance(item, dict) or str(item.get("type") or "").upper() != "TV":
            continue
        label = channel_label(item)
        if label:
            rows.append((item, label))
    for item, label in rows:
        if item.get("isNational"):
            return label
    if favorite in ("home", "away"):
        for item, label in rows:
            if str(item.get("homeAway") or "") == favorite:
                return label
    return ""


def scoreboard_sides(away, home, favorite):
    # Home on the left reads "vs". Away on the left reads "@".
    if favorite == "home":
        return home, "vs", away
    return away, "@", home


def hand_code(person, which):
    if not isinstance(person, dict):
        return ""
    side = person.get(which)
    code = side.get("code") if isinstance(side, dict) else side
    code = str(code or "").strip().upper()
    return code if code in {"L", "R", "S"} else ""


def role_line(name, hand, role):
    name = str(name or "").strip()
    if not name:
        return ""
    mark = f" ({hand})" if hand else ""
    return f"{name}{mark} {role}"


def short_hand(full, hand):
    name = last_name(full)
    if not name:
        return ""
    return f"{name} ({hand})" if hand else name


def count_line(balls, strikes, outs):
    parts = []
    if balls is not None and strikes is not None:
        parts.append(f"{balls}-{strikes}")
    if outs is not None:
        parts.append("1 out" if outs == 1 else f"{outs} outs")
    return " · ".join(parts)


POSTSEASON_TYPES = {"F", "D", "L", "W"}
_HALF_KEY = {"Top": "top", "Bottom": "bottom", "Middle": "middle", "End": "end"}


def inning_half(linescore):
    """("top" | "bottom" | "middle" | "end" | "", inning number or 0)."""
    if not isinstance(linescore, dict):
        return "", 0
    half = _HALF_KEY.get(str(linescore.get("inningState") or ""), "")
    return half, as_int(linescore.get("currentInning")) or 0


def leader_side(away, home):
    a, h = as_int(away.get("score")), as_int(home.get("score"))
    if a is None or h is None or a == h:
        return ""
    return "away" if a > h else "home"


def live_note(state, detailed):
    """A word for a live game that is not simply being played: Warmup, Delay, Challenge."""
    detailed = str(detailed or "")
    if state != "live" or detailed in ("", "In Progress"):
        return ""
    return _LIVE_DETAIL.get(detailed, detailed)


def series_info(game):
    """{round, game, result} for a postseason game, e.g. ALWC, 2, 'NYY leads 1-0'.
    Empty for the regular season, which has a series status of its own."""
    if str(game.get("gameType") or "") not in POSTSEASON_TYPES:
        return {"round": "", "game": 0, "result": ""}
    status = game.get("seriesStatus") if isinstance(game.get("seriesStatus"), dict) else {}
    name = str(status.get("abbreviation") or status.get("shortName") or game.get("seriesDescription") or "").strip()
    number = as_int(status.get("gameNumber")) or as_int(game.get("seriesGameNumber")) or 0
    played = (as_int(status.get("wins")) or 0) + (as_int(status.get("losses")) or 0)
    result = str(status.get("result") or "").strip() if played else ""
    return {"round": name, "game": number, "result": result}


def series_line(info):
    """'ALWC · Game 2 · NYY leads 1-0'; '' outside the postseason."""
    parts = [info["round"]] if info["round"] else []
    if info["game"]:
        parts.append(f"Game {info['game']}")
    if info["result"]:
        parts.append(info["result"])
    return " · ".join(parts)


def present_game(game, team_id=None):
    state, detailed = classify_game(game)
    linescore = game.get("linescore") if isinstance(game.get("linescore"), dict) else {}
    away = side_info(game, linescore, "away")
    home = side_info(game, linescore, "home")
    labels, away_innings, home_innings = inning_columns(linescore)
    away["innings"] = away_innings
    home["innings"] = home_innings
    favorite = ""
    if team_id and team_id == away["id"]:
        favorite = "away"
    elif team_id and team_id == home["id"]:
        favorite = "home"
    balls = strikes = outs = None
    bases = [False, False, False]
    batter = pitcher = ""
    batter_hand = pitcher_hand = ""
    if state == "live" and detailed != "Warmup":
        balls = as_int(linescore.get("balls"))
        strikes = as_int(linescore.get("strikes"))
        outs = as_int(linescore.get("outs"))
        offense = linescore.get("offense") if isinstance(linescore.get("offense"), dict) else {}
        defense = linescore.get("defense") if isinstance(linescore.get("defense"), dict) else {}
        bases = [
            bool(offense.get("first")),
            bool(offense.get("second")),
            bool(offense.get("third")),
        ]
        batter_node = offense.get("batter")
        pitcher_node = defense.get("pitcher")
        batter = person_name(batter_node)
        pitcher = person_name(pitcher_node)
        batter_hand = hand_code(batter_node, "batSide")
        pitcher_hand = hand_code(pitcher_node, "pitchHand")
    status = status_label(state, detailed, linescore)
    detail_bits = [status]
    counted = count_line(balls, strikes, outs)
    if counted:
        detail_bits.append(counted)
    names = [short_hand(batter, batter_hand), short_hand(pitcher, pitcher_hand)]
    decisions = game.get("decisions") if isinstance(game.get("decisions"), dict) else {}
    winner = person_name(decisions.get("winner"))
    loser = person_name(decisions.get("loser"))
    save = person_name(decisions.get("save"))
    decided = decision_line(winner, loser, save) if state == "final" else ""
    pk = as_int(game.get("gamePk")) or 0
    left, mark, right = scoreboard_sides(away, home, favorite)
    half, inning = inning_half(linescore) if state == "live" else ("", 0)
    series = series_info(game)
    return {
        "gamePk": pk,
        "gameday": gameday_url(pk),
        "live": state == "live",
        "status": status,
        "favorite": favorite,
        "balls": balls,
        "strikes": strikes,
        "outs": outs,
        "bases": bases,
        "batter": batter,
        "pitcher": pitcher,
        "batterLine": role_line(batter, batter_hand, "batting"),
        "pitcherLine": role_line(pitcher, pitcher_hand, "pitching"),
        "decisionLine": decided,
        "countLine": counted,
        "labels": labels,
        "hasLine": any(cell != "" for cell in away_innings + home_innings),
        "away": away,
        "home": home,
        "left": left,
        "mark": mark,
        "right": right,
        "tv": tv_channel(game.get("broadcasts"), favorite),
        "rowTitle": f"{away['abbr']} {away['score']}  {home['abbr']} {home['score']}",
        "rowDetail": " · ".join(detail_bits),
        "rowNames": " · ".join(name for name in names if name),
        "half": half,
        "inning": inning,
        "leader": leader_side(away, home),
        "note": live_note(state, detailed),
        "series": series_line(series),
        "seriesRound": series["round"],
        "seriesGame": series["game"],
        "seriesResult": series["result"],
        "batterShort": last_name(batter),
        "pitcherShort": last_name(pitcher),
    }


def format_clock(hour, minute):
    suffix = "AM" if hour < 12 else "PM"
    shown = hour % 12 or 12
    return f"{shown}:{minute:02d} {suffix}"


def format_day(day, today):
    if day == today:
        return "Today"
    if day == today + timedelta(days=1):
        return "Tomorrow"
    return f"{_WEEKDAYS[day.weekday()]} {_MONTHS[day.month - 1]} {day.day}"


def format_start(game, now):
    now = aware(now)
    status = game.get("status") if isinstance(game.get("status"), dict) else {}
    today = now.date()
    if status.get("startTimeTBD") or not game.get("gameDate"):
        official = str(game.get("officialDate") or "")
        try:
            day = date.fromisoformat(official)
        except ValueError:
            return "Time TBD"
        label = format_day(day, today)
        if label in ("Today", "Tomorrow"):
            return f"{label}, time TBD"
        return f"{label}, time TBD"
    raw = str(game.get("gameDate")).replace("Z", "+00:00")
    try:
        instant = datetime.fromisoformat(raw)
    except ValueError:
        return "Time TBD"
    if instant.tzinfo is None:
        instant = instant.replace(tzinfo=ZoneInfo("UTC"))
    local = instant.astimezone(now.tzinfo)
    label = format_day(local.date(), today)
    clock = format_clock(local.hour, local.minute)
    if label in ("Today", "Tomorrow"):
        return f"{label} {clock}"
    return f"{label}, {clock}"


def matchup(away, home, team_id):
    if team_id and team_id == home["id"]:
        return f"vs {away['club']}"
    if team_id and team_id == away["id"]:
        return f"at {home['club']}"
    return f"{away['abbr']} at {home['abbr']}"


def present_next(game, team_id, now, kicker):
    if not game:
        return None
    state, detailed = classify_game(game)
    when = format_start(game, now)
    if state != "live" and "delay" in detailed.lower():
        when = f"Delayed · {when}"
    away = side_info(game, {}, "away")
    home = side_info(game, {}, "home")
    favorite = ""
    if team_id and team_id == away["id"]:
        favorite = "away"
    elif team_id and team_id == home["id"]:
        favorite = "home"
    teams = game.get("teams") if isinstance(game.get("teams"), dict) else {}
    away_block = teams.get("away") if isinstance(teams.get("away"), dict) else {}
    home_block = teams.get("home") if isinstance(teams.get("home"), dict) else {}
    away_pitcher = person_name(away_block.get("probablePitcher"))
    home_pitcher = person_name(home_block.get("probablePitcher"))
    pk = as_int(game.get("gamePk")) or 0
    return {
        "gamePk": pk,
        "gameday": gameday_url(pk),
        "when": when,
        "where": matchup(away, home, team_id),
        "kicker": kicker,
        "awayPitcher": away_pitcher,
        "homePitcher": home_pitcher,
        "pitchers": pitcher_matchup(away_pitcher, home_pitcher),
        "tv": tv_channel(game.get("broadcasts"), favorite),
    }


def standing_row(entry, team_id, rank, behind):
    team = entry.get("team") if isinstance(entry.get("team"), dict) else {}
    tid = as_int(team.get("id")) or 0
    wins = as_int(entry.get("wins"))
    losses = as_int(entry.get("losses"))
    return {
        "id": tid,
        "abbr": short_name(team),
        "wins": wins if wins is not None else 0,
        "losses": losses if losses is not None else 0,
        "record": f"{wins if wins is not None else 0}-{losses if losses is not None else 0}",
        "gb": games_back(behind),
        "rank": str(rank or ""),
        "favorite": tid == team_id,
    }


def division_back(entry):
    if entry.get("gamesBack") is not None:
        return entry.get("gamesBack")
    return entry.get("divisionGamesBack")


def wild_card_back(entry):
    return entry.get("wildCardGamesBack")


def sorted_table_rows(entries, team_id, rank_key, behind):
    rows = []
    for entry in entries or []:
        if not isinstance(entry, dict):
            continue
        rows.append(standing_row(entry, team_id, entry.get(rank_key), behind(entry)))
    rows.sort(key=lambda row: (as_int(row["rank"]) or 99, row["abbr"]))
    return rows


def present_standings(payload, team_id):
    if not team_id:
        return None
    for record in (payload or {}).get("records") or []:
        if not isinstance(record, dict):
            continue
        rows = sorted_table_rows(record.get("teamRecords"), team_id, "divisionRank", division_back)
        if not any(row["favorite"] for row in rows):
            continue
        favorite = next((row for row in rows if row["favorite"]), None)
        division = record.get("division") if isinstance(record.get("division"), dict) else {}
        division_id = as_int(division.get("id")) or 0
        short = dict(DIVISIONS).get(division_id) or str(division.get("name") or "")
        line = ""
        if favorite:
            bits = [ordinal(favorite["rank"]), favorite["record"]]
            if favorite["gb"] != "—":
                bits.append(favorite["gb"] + " GB")
            line = " · ".join(bit for bit in bits if bit)
        return {"divisionId": division_id, "division": short, "line": line, "rows": rows}
    return None


def division_table(record, team_id):
    division = record.get("division") if isinstance(record.get("division"), dict) else {}
    division_id = as_int(division.get("id")) or 0
    league = DIVISION_LEAGUE.get(division_id, "")
    region = DIVISION_REGION.get(division_id, "")
    title = f"{league} {region}".strip() or dict(DIVISIONS).get(division_id) or str(division.get("name") or "")
    return {
        "id": division_id,
        "kind": "division",
        "league": league,
        "label": region or title,
        "title": title,
        "rows": sorted_table_rows(record.get("teamRecords"), team_id, "divisionRank", division_back),
    }


def wild_card_table(entries, league, team_id):
    rows = sorted_table_rows(entries, team_id, "wildCardRank", wild_card_back)
    return {
        "id": "WC",
        "kind": "wildcard",
        "league": league,
        "label": "WC",
        "title": f"{league} Wild Card",
        "rows": rows[:MAX_WC_ROWS],
    }


def present_tables(reg_payload, wc_payload, team_id):
    """The favorite-division keys plus every league table the switcher can show."""
    base = present_standings(reg_payload, team_id)
    if base is None:
        return None
    by_division = {}
    for record in (reg_payload or {}).get("records") or []:
        if not isinstance(record, dict):
            continue
        table = division_table(record, team_id)
        if table["id"]:
            by_division[table["id"]] = table
    wc_by_league = {}
    for record in (wc_payload or {}).get("records") or []:
        if not isinstance(record, dict):
            continue
        league = record.get("league") if isinstance(record.get("league"), dict) else {}
        name = dict(LEAGUES).get(as_int(league.get("id")))
        if name and name not in wc_by_league:
            wc_by_league[name] = wild_card_table(record.get("teamRecords"), name, team_id)
    leagues = []
    for _league_id, name in LEAGUES:
        tables = []
        for division_id, _short in DIVISIONS:
            if DIVISION_LEAGUE.get(division_id) != name:
                continue
            if division_id in by_division:
                tables.append(by_division[division_id])
        if name in wc_by_league:
            tables.append(wc_by_league[name])
        leagues.append({"id": name, "label": name, "tables": tables})
    base.update({
        "defaultLeague": DIVISION_LEAGUE.get(base["divisionId"], ""),
        "defaultTable": base["divisionId"],
        "leagues": leagues,
    })
    return base


# Postseason rounds in the order they are played: Wild Card, Division Series,
# League Championship Series, World Series.
ROUND_ORDER = ("F", "D", "L", "W")
ROUND_TITLES = {"F": "Wild Card Series", "D": "Division Series", "L": "Championship Series", "W": "World Series"}
ROUND_CODES = {"F": "WC", "D": "DS", "L": "CS", "W": "WS"}
LEAGUE_NAMES = dict(LEAGUES)
POSTSEASON_PAGE = "https://www.mlb.com/postseason"


def short_day(day, today):
    """Today, Tomorrow, a weekday inside the week, else Oct 12."""
    if day == today:
        return "Today"
    if day == today + timedelta(days=1):
        return "Tomorrow"
    if today < day < today + timedelta(days=7):
        return _WEEKDAYS[day.weekday()]
    return f"{_MONTHS[day.month - 1]} {day.day}"


def series_when(game, now):
    """('Tue 6:08 PM', is it today). A game with no start time yet is 'Tue, TBD'."""
    now = aware(now)
    today = now.date()
    status = game.get("status") if isinstance(game.get("status"), dict) else {}
    if status.get("startTimeTBD") or not game.get("gameDate"):
        try:
            day = date.fromisoformat(str(game.get("officialDate") or ""))
        except ValueError:
            return "TBD", False
        return f"{short_day(day, today)}, TBD", day == today
    raw = str(game.get("gameDate")).replace("Z", "+00:00")
    try:
        instant = datetime.fromisoformat(raw)
    except ValueError:
        return "TBD", False
    if instant.tzinfo is None:
        instant = instant.replace(tzinfo=ZoneInfo("UTC"))
    local = instant.astimezone(now.tzinfo)
    return f"{short_day(local.date(), today)} {format_clock(local.hour, local.minute)}", local.date() == today


def series_entries(payload):
    """[(series id, round, games)] from the postseason series feed."""
    out = []
    for block in (payload or {}).get("series") or []:
        if not isinstance(block, dict):
            continue
        meta = block.get("series") if isinstance(block.get("series"), dict) else {}
        games = [game for game in block.get("games") or []
                 if isinstance(game, dict) and game.get("publicFacing") is not False]
        if not games:
            continue
        kind = str(meta.get("gameType") or games[0].get("gameType") or "")
        if kind in ROUND_ORDER:
            out.append((str(meta.get("id") or ""), kind, games))
    return out


def series_game_number(game):
    status = game.get("seriesStatus") if isinstance(game.get("seriesStatus"), dict) else {}
    return as_int(game.get("seriesGameNumber")) or as_int(status.get("gameNumber")) or 0


def series_game_key(game):
    return (series_game_number(game), str(game.get("gameDate") or ""), as_int(game.get("gamePk")) or 0)


def series_club(block):
    """One club in a series. A seed not decided yet ('AL Lower Seed') is TBD."""
    team = block.get("team") if isinstance(block, dict) and isinstance(block.get("team"), dict) else {}
    league = team.get("league") if isinstance(team.get("league"), dict) else {}
    pk = as_int(team.get("id")) or 0
    known = bool(pk) and not team.get("placeholder")
    return {
        "id": pk if known else 0,
        "abbr": short_name(team) if known else "TBD",
        "club": club_name(team) if known else "TBD",
        "league": LEAGUE_NAMES.get(as_int(league.get("id")), ""),
        "wins": 0,
    }


def game_side_id(game, side):
    teams = game.get("teams") if isinstance(game.get("teams"), dict) else {}
    block = teams.get(side) if isinstance(teams.get(side), dict) else {}
    team = block.get("team") if isinstance(block.get("team"), dict) else {}
    return as_int(team.get("id")) or 0


def game_winner_id(game):
    teams = game.get("teams") if isinstance(game.get("teams"), dict) else {}
    away = teams.get("away") if isinstance(teams.get("away"), dict) else {}
    home = teams.get("home") if isinstance(teams.get("home"), dict) else {}
    if away.get("isWinner") is True:
        return game_side_id(game, "away")
    if home.get("isWinner") is True:
        return game_side_id(game, "home")
    a, h = as_int(away.get("score")), as_int(home.get("score"))
    if a is None or h is None or a == h:
        return 0
    return game_side_id(game, "away" if a > h else "home")


def game_score_line(game, abbr_by_id):
    """'NYY 5-3': the club ahead and the score, higher first. 'Tied 2-2' while level."""
    teams = game.get("teams") if isinstance(game.get("teams"), dict) else {}
    sides = []
    for side in ("away", "home"):
        block = teams.get(side) if isinstance(teams.get(side), dict) else {}
        pk = game_side_id(game, side)
        score = as_int(block.get("score"))
        if score is None:
            return ""
        sides.append((score, abbr_by_id.get(pk) or short_name(block.get("team"))))
    sides.sort(key=lambda pair: -pair[0])
    (high, ahead), (low, _behind) = sides
    if high == low:
        return f"Tied {high}-{low}"
    return f"{ahead} {high}-{low}"


def probable_last(game, side):
    teams = game.get("teams") if isinstance(game.get("teams"), dict) else {}
    block = teams.get(side) if isinstance(teams.get(side), dict) else {}
    return last_name(person_name(block.get("probablePitcher")))


def series_pitchers(game, left_id):
    """'Fried vs Rasmussen' in the card's left-to-right order. TBD for a side not named yet."""
    away, home = probable_last(game, "away"), probable_last(game, "home")
    if not away and not home:
        return ""
    if game_side_id(game, "home") == left_id and left_id:
        away, home = home, away
    return f"{away or 'TBD'} vs {home or 'TBD'}"


def series_code(kind, league):
    """ALDS, NLCS, ALWC; WS for the World Series."""
    if kind == "W":
        return "WS"
    return f"{league}{ROUND_CODES.get(kind, '')}"


def present_series(series_id, kind, games, now, later=()):
    """One series card. `later` holds the next rounds' games, for the winner's next start."""
    games = sorted(games, key=series_game_key)
    first = games[0]
    teams = first.get("teams") if isinstance(first.get("teams"), dict) else {}
    # Game 1's visitor on the left, the higher seed on the right, as in "CWS @ CLE".
    left = series_club(teams.get("away"))
    right = series_club(teams.get("home"))
    league = "" if kind == "W" else (left["league"] or right["league"])
    best = 0
    clinched = False
    for game in games:
        status = game.get("seriesStatus") if isinstance(game.get("seriesStatus"), dict) else {}
        best = max(best, as_int(game.get("gamesInSeries")) or 0, as_int(status.get("totalGames")) or 0)
        if classify_game(game)[0] == "final" and status.get("isOver") is True:
            clinched = True
    best = best or len(games)
    need = best // 2 + 1
    finals, live, upcoming = [], [], []
    for game in games:
        state = classify_game(game)[0]
        if state == "final":
            finals.append(game)
            winner = game_winner_id(game)
            if winner and winner == left["id"]:
                left["wins"] += 1
            elif winner and winner == right["id"]:
                right["wins"] += 1
        elif state == "live":
            live.append(game)
        elif state == "preview":
            upcoming.append(game)
    over = clinched or left["wins"] >= need or right["wins"] >= need
    winner = ""
    if over and left["wins"] != right["wins"]:
        winner = "left" if left["wins"] > right["wins"] else "right"
    leader = winner
    if not leader and left["wins"] != right["wins"]:
        leader = "left" if left["wins"] > right["wins"] else "right"
    played = left["wins"] + right["wins"]
    high, low = (left, right) if left["wins"] >= right["wins"] else (right, left)
    if winner:
        summary = f"{high['abbr']} wins {high['wins']}-{low['wins']}"
    elif leader:
        summary = f"{high['abbr']} leads {high['wins']}-{low['wins']}"
    elif played:
        summary = f"Series tied {left['wins']}-{right['wins']}"
    else:
        summary = ""
    abbrs = {club["id"]: club["abbr"] for club in (left, right) if club["id"]}
    last = None
    if finals:
        game = finals[-1]
        number = series_game_number(game)
        last = {
            "game": number,
            "line": game_score_line(game, abbrs),
            "gameday": gameday_url(game.get("gamePk")),
        }
    current = None
    if live:
        game = live[0]
        linescore = game.get("linescore") if isinstance(game.get("linescore"), dict) else {}
        current = {
            "game": series_game_number(game),
            "status": status_label("live", classify_game(game)[1], linescore),
            "line": game_score_line(game, abbrs),
            "gameday": gameday_url(game.get("gamePk")),
        }
    nxt = None
    if not over and not live and upcoming:
        game = upcoming[0]
        when, today = series_when(game, now)
        nxt = {
            "game": series_game_number(game),
            "when": when,
            "today": today,
            "tv": tv_channel(game.get("broadcasts"), ""),
            "pitchers": series_pitchers(game, left["id"]),
            "gameday": gameday_url(game.get("gamePk")),
        }
    advance = None
    if winner:
        champ = high["id"]
        ahead = sorted(
            (game for game in later
             if champ and involves(game, champ) and classify_game(game)[0] in ("preview", "live")),
            key=game_sort_key,
        )
        if ahead:
            game = ahead[0]
            when, today = series_when(game, now)
            code = series_code(str(game.get("gameType") or ""), high["league"])
            number = series_game_number(game)
            advance = {
                "code": code,
                "game": number,
                "when": when,
                "today": today,
                "tv": tv_channel(game.get("broadcasts"), ""),
                "gameday": gameday_url(game.get("gamePk")),
            }
    if current:
        state = "live"
    elif over:
        state = "over"
    elif played:
        state = "active"
    else:
        state = "upcoming"
    link = (current or nxt or last or {}).get("gameday", "")
    return {
        "id": series_id,
        "round": kind,
        "league": league,
        "code": series_code(kind, league),
        "tag": "",
        "best": best,
        "need": need,
        "left": left,
        "right": right,
        "state": state,
        "over": over,
        "winner": winner,
        "leader": leader,
        "summary": summary,
        "next": nxt,
        "live": current,
        "last": last,
        "advance": advance,
        "gameday": link,
    }


def _league_rank(league):
    return {"AL": 0, "NL": 1}.get(league, 2)


def pick_rounds(rows):
    """The rows the board leads with. Each league shows the earliest round it is
    still playing; a league done with its rounds shows how it finished until the
    World Series is set. Earlier rounds come back as results."""
    tracks = sorted({row["league"] for row in rows if row["round"] != "W"}, key=_league_rank)
    world = [row for row in rows if row["round"] == "W"]
    showing = {}
    finished = {}
    for league in tracks:
        mine = [row for row in rows if row["league"] == league and row["round"] != "W"]
        played = [kind for kind in ROUND_ORDER if any(row["round"] == kind for row in mine)]
        still = next((kind for kind in played if any(not row["over"] for row in mine if row["round"] == kind)), None)
        if still:
            showing[league] = still
        elif played:
            finished[league] = played[-1]
    current = []
    earlier = []
    if world and tracks and not showing:
        current = list(world)
        for league in tracks:
            earlier.extend(row for row in rows if row["league"] == league and row["round"] != "W")
    else:
        for league in tracks:
            kind = showing.get(league) or finished.get(league)
            if not kind:
                continue
            cut = ROUND_ORDER.index(kind)
            for row in rows:
                if row["league"] != league or row["round"] == "W":
                    continue
                place = ROUND_ORDER.index(row["round"])
                if place == cut:
                    current.append(row)
                elif place < cut:
                    earlier.append(row)
    order = lambda row: (_league_rank(row["league"]), ROUND_ORDER.index(row["round"]), row["id"])
    current.sort(key=order)
    groups = []
    for kind in reversed(ROUND_ORDER):
        members = sorted((row for row in earlier if row["round"] == kind), key=order)
        if members:
            groups.append({"round": kind, "title": ROUND_TITLES[kind], "series": members})
    return current, groups


def postseason_board(payload, now, year):
    """The series board, or None when the feed has no series."""
    entries = series_entries(payload)
    if not entries:
        return None
    rows = []
    for series_id, kind, games in entries:
        place = ROUND_ORDER.index(kind)
        later = [game for _id, other, more in entries if ROUND_ORDER.index(other) > place for game in more]
        rows.append(present_series(series_id, kind, games, now, later))
    current, earlier = pick_rounds(rows)
    if not current:
        return None
    kinds = {row["round"] for row in current}
    single = len(kinds) == 1
    for row in current:
        row["tag"] = row["league"] if single else row["code"]
    for group in earlier:
        for row in group["series"]:
            row["tag"] = row["code"]
    title = ROUND_TITLES[next(iter(kinds))] if single else "Postseason"
    trailing = f"Best of {max(row['best'] for row in current)}" if single else ""
    champion = None
    if kinds == {"W"} and len(current) == 1 and current[0]["winner"]:
        row = current[0]
        won, lost = (row["left"], row["right"]) if row["winner"] == "left" else (row["right"], row["left"])
        champion = {
            "id": won["id"],
            "abbr": won["abbr"],
            "club": won["club"],
            "line": f"def. {lost['club']} {won['wins']}-{lost['wins']}",
            "year": str(year),
            "gameday": row["gameday"],
        }
        trailing = str(year)
    return {
        "title": title,
        "trailing": trailing,
        "series": current,
        "earlier": earlier,
        "champion": champion,
        "url": POSTSEASON_PAGE,
    }


def _view(**extra):
    base = {
        "ok": True,
        "error": "",
        "mode": "empty",
        "banner": "MLB",
        "reason": "",
        "pollMs": POLL_IDLE_MS,
        "focus": None,
        "games": [],
        "next": None,
        "standings": None,
        "postseason": None,
    }
    base.update(extra)
    return base


def choose_view(team_id, window, pool, *, missed_playoffs, now, postseason=None):
    window = [game for game in window if isinstance(game, dict) and game.get("publicFacing") is not False]
    pool = [game for game in pool if isinstance(game, dict) and game.get("publicFacing") is not False]
    if not team_id or missed_playoffs:
        live = sorted((game for game in window if classify_game(game)[0] == "live"), key=game_sort_key)
        reason = "playoffs" if missed_playoffs else ""
        if len(live) == 1:
            return _view(
                mode="live",
                banner="Playoffs" if missed_playoffs else "",
                reason=reason,
                pollMs=POLL_LIVE_MS,
                focus=present_game(live[0], team_id if not missed_playoffs else None),
            )
        if len(live) > 1:
            return _view(
                mode="board",
                banner="Playoffs" if missed_playoffs else "Live",
                reason=reason,
                pollMs=POLL_LIVE_MS,
                games=[present_game(game, None) for game in live],
            )
        if postseason and postseason.get("series"):
            return _view(
                mode="series",
                banner="Playoffs" if missed_playoffs else "Postseason",
                reason=reason,
                postseason=postseason,
            )
        upcoming = sorted((game for game in window if classify_game(game)[0] == "preview"), key=game_sort_key)
        nxt = present_next(upcoming[0], None, now, "First pitch") if upcoming else None
        return _view(mode="empty", banner="Playoffs" if missed_playoffs else "MLB", reason=reason, next=nxt)

    mine = [game for game in dedupe_games(list(pool) + list(window)) if involves(game, team_id)]
    live = sorted((game for game in mine if classify_game(game)[0] == "live"), key=game_sort_key)
    if live:
        return _view(mode="live", banner="", pollMs=POLL_LIVE_MS, focus=present_game(live[-1], team_id))
    finals = sorted((game for game in mine if classify_game(game)[0] == "final"), key=game_sort_key)
    last = finals[-1] if finals else None
    previews = sorted((game for game in mine if classify_game(game)[0] == "preview"), key=game_sort_key)
    if last is not None:
        cutoff = game_sort_key(last)
        previews = [game for game in previews if game_sort_key(game) > cutoff]
    nxt = present_next(previews[0], team_id, now, "Next") if previews else None
    if last is not None:
        return _view(mode="final", banner="", pollMs=POLL_IDLE_MS, focus=present_game(last, team_id), next=nxt)
    if nxt is not None:
        return _view(mode="upcoming", next=nxt)
    return _view(mode="empty")


def safe_fetch(fetch, url):
    try:
        return fetch(url)
    except (OSError, ValueError, TimeoutError):
        return None


def _live_player(game, side, key):
    if classify_game(game)[0] != "live":
        return None
    linescore = game.get("linescore") if isinstance(game.get("linescore"), dict) else {}
    block = linescore.get(side) if isinstance(linescore.get(side), dict) else {}
    person = block.get(key)
    return person if isinstance(person, dict) else None


def hands_needed(games):
    found = []
    seen = set()
    for game in games:
        checks = (
            (_live_player(game, "offense", "batter"), "batSide"),
            (_live_player(game, "defense", "pitcher"), "pitchHand"),
        )
        for person, which in checks:
            if person is None or hand_code(person, which):
                continue
            pk = as_int(person.get("id"))
            if pk and pk not in seen:
                seen.add(pk)
                found.append(pk)
    return found


def merge_hands(games, people):
    by_id = {}
    for person in people or []:
        if not isinstance(person, dict):
            continue
        pk = as_int(person.get("id"))
        if pk:
            by_id[pk] = person
    for game in games:
        batter = _live_player(game, "offense", "batter")
        pitcher = _live_player(game, "defense", "pitcher")
        if batter is not None:
            src = by_id.get(as_int(batter.get("id")) or 0)
            side = src.get("batSide") if isinstance(src, dict) else None
            if isinstance(side, dict):
                batter["batSide"] = side
        if pitcher is not None:
            src = by_id.get(as_int(pitcher.get("id")) or 0)
            hand = src.get("pitchHand") if isinstance(src, dict) else None
            if isinstance(hand, dict):
                pitcher["pitchHand"] = hand


def attach_hands(games, fetch):
    # The schedule names the batter and pitcher, but not which side they hit or throw.
    ids = hands_needed(games)
    if not ids:
        return
    payload = safe_fetch(fetch, people_url(ids))
    if not isinstance(payload, dict):
        return
    merge_hands(games, payload.get("people"))


def attach_standings(view, team_id, year, fetch):
    # Standings are for the gap between games. A live slate and the series board do not show them.
    if not team_id or view.get("mode") in ("live", "board", "series"):
        view["standings"] = None
        return view
    reg = safe_fetch(fetch, standings_url(year))
    if reg is None:
        view["standings"] = None
        return view
    # A missing wild-card feed still leaves the division tables.
    wc = safe_fetch(fetch, standings_url(year, kinds="wildCard"))
    view["standings"] = present_tables(reg, wc, team_id)
    return view


def load_season(fetch, day):
    payload = safe_fetch(fetch, season_url(day.year))
    return season_record(payload, day.year) if payload is not None else {}


def collect(team_id, now, fetch):
    now = aware(now)
    team_id = team_id_from_settings({"teamId": team_id})
    day = mlb_day(now)
    window_payload = safe_fetch(fetch, window_url(day))
    if window_payload is None:
        return error_view()
    window = games_from_schedule(window_payload)
    missed = False
    postseason_games = []
    season = None
    if team_id:
        season = load_season(fetch, day)
        if in_postseason(season, day):
            posted = safe_fetch(fetch, postseason_url(team_id, day.year))
            if posted is not None:
                postseason_games = games_from_schedule(posted)
                missed = len(postseason_games) == 0
    if not team_id or missed:
        attach_hands(window, fetch)
        board = None
        # The series board fills the slate between games. A live game keeps it.
        if not any(classify_game(game)[0] == "live" for game in window):
            if season is None:
                season = load_season(fetch, day)
            if in_postseason(season, day):
                board = postseason_board(safe_fetch(fetch, series_url(day.year)), now, day.year)
        view = choose_view(team_id, window, [], missed_playoffs=missed, now=now, postseason=board)
        return attach_standings(view, team_id, day.year, fetch)
    live_now = any(involves(game, team_id) and classify_game(game)[0] == "live" for game in window)
    pool = list(postseason_games)
    if not live_now:
        hydrated = safe_fetch(fetch, team_url(team_id))
        if hydrated is not None:
            pool.extend(games_from_team_payload(hydrated))
    pool.extend(game for game in window if involves(game, team_id))
    attach_hands(dedupe_games(list(window) + list(pool)), fetch)
    view = choose_view(team_id, window, pool, missed_playoffs=False, now=now)
    return attach_standings(view, team_id, day.year, fetch)


def main(argv):
    args = argv[1:]
    now = datetime.now().astimezone()
    if "--teams" in args:
        rows = team_catalog(fetch_json(teams_url(now)))
        # `divisions` is the flat list an already-open settings page still reads.
        # `rows` pairs AL and NL for the current page.
        json.dump({
            "divisions": division_groups(rows),
            "rows": division_rows(rows),
        }, sys.stdout)
        sys.stdout.write("\n")
        return 0
    team_id = 0
    if "--team" in args:
        index = args.index("--team")
        if index + 1 >= len(args):
            json.dump(error_view(), sys.stdout)
            sys.stdout.write("\n")
            return 0
        team_id = team_id_from_settings({"teamId": args[index + 1]}) or 0
    json.dump(collect(team_id, now, fetch_json), sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
