"""NFL tile model.

The tile is read-only news about one club, so this module only has to answer a
short list of questions well:

  * Is my team playing right now, and what is happening in the drive?
  * If not, when is the next game, and who is the opponent?
  * Where does the club sit in its division and the playoff picture?
  * If nothing is scheduled, did the season finish and how did it go?

A football score on its own says almost nothing. The quarter and clock tell
you whether a 21-7 lead is safe, and the down and distance tell you whether a
team is about to score or has stalled at its own 5. Both live in the scoreboard
feed, so they are fetched once and parsed here.

No network calls live in this file. Every fetch goes through the `fetch`
argument the caller supplies, which is what the tests replace.
"""

import json
import math
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from urllib.parse import urlparse

CURL = "/usr/bin/curl"
ALLOWED_HOSTS = ("site.api.espn.com", "sports.core.api.espn.com", "site.web.api.espn.com")
SITE = "https://site.api.espn.com/apis/site/v2/sports/football/nfl"
STANDINGS_API = "https://site.api.espn.com/apis/v2/sports/football/nfl/standings"
NFL_SITE = "https://www.nfl.com"
MAX_BYTES = 4000000

POLL_LIVE_MS = 15000
POLL_IDLE_MS = 60000
POLL_OFF_MS = 300000

# ESPN season types. The token also names the NFL.com game path.
PRE = 1
REGULAR = 2
POST = 3
SEASON_TOKENS = {PRE: "pre", REGULAR: "reg", POST: "post"}
SEASON_NAMES = {PRE: "Preseason", REGULAR: "Regular Season", POST: "Postseason"}

# id, abbreviation, city, nickname, division, conference, color, alt color.
# Colors are the club's own, so a tile can wear them without another lookup.
# The nickname is what NFL.com puts in a game path, which is why it is kept
# separate from the abbreviation: "LAR" is the ticker, "rams" is the URL.
TEAM_ROWS = (
    (1, "ATL", "Atlanta", "Falcons", "South", "NFC", "a71930", "000000"),
    (22, "ARI", "Arizona", "Cardinals", "West", "NFC", "a40227", "ffffff"),
    (33, "BAL", "Baltimore", "Ravens", "North", "AFC", "29126f", "000000"),
    (2, "BUF", "Buffalo", "Bills", "East", "AFC", "00338d", "d50a0a"),
    (29, "CAR", "Carolina", "Panthers", "South", "NFC", "0085ca", "000000"),
    (3, "CHI", "Chicago", "Bears", "North", "NFC", "0b1c3a", "e64100"),
    (4, "CIN", "Cincinnati", "Bengals", "North", "AFC", "fb4f14", "000000"),
    (5, "CLE", "Cleveland", "Browns", "North", "AFC", "472a08", "ff3c00"),
    (6, "DAL", "Dallas", "Cowboys", "East", "NFC", "002a5c", "b0b7bc"),
    (7, "DEN", "Denver", "Broncos", "West", "AFC", "0a2343", "fc4c02"),
    (8, "DET", "Detroit", "Lions", "North", "NFC", "0076b6", "bbbbbb"),
    (9, "GB", "Green Bay", "Packers", "North", "NFC", "204e32", "ffb612"),
    (34, "HOU", "Houston", "Texans", "South", "AFC", "021018", "eb0028"),
    (11, "IND", "Indianapolis", "Colts", "South", "AFC", "003b75", "ffffff"),
    (30, "JAX", "Jacksonville", "Jaguars", "South", "AFC", "007487", "d7a22a"),
    (12, "KC", "Kansas City", "Chiefs", "West", "AFC", "e31837", "ffb612"),
    (13, "LV", "Las Vegas", "Raiders", "West", "AFC", "000000", "a5acaf"),
    (24, "LAC", "Los Angeles", "Chargers", "West", "AFC", "0080c6", "ffc20e"),
    (14, "LAR", "Los Angeles", "Rams", "West", "NFC", "003594", "ffd100"),
    (15, "MIA", "Miami", "Dolphins", "East", "AFC", "008e97", "fc4c02"),
    (16, "MIN", "Minnesota", "Vikings", "North", "NFC", "4f2683", "ffc62f"),
    (17, "NE", "New England", "Patriots", "East", "AFC", "002a5c", "c60c30"),
    (18, "NO", "New Orleans", "Saints", "South", "NFC", "d3bc8d", "000000"),
    (19, "NYG", "New York", "Giants", "East", "NFC", "003c7f", "c9243f"),
    (20, "NYJ", "New York", "Jets", "East", "AFC", "115740", "ffffff"),
    (21, "PHI", "Philadelphia", "Eagles", "East", "NFC", "06424d", "000000"),
    (23, "PIT", "Pittsburgh", "Steelers", "North", "AFC", "000000", "ffb612"),
    (25, "SF", "San Francisco", "49ers", "West", "NFC", "aa0000", "b3995d"),
    (26, "SEA", "Seattle", "Seahawks", "West", "NFC", "002a5c", "69be28"),
    (27, "TB", "Tampa Bay", "Buccaneers", "South", "NFC", "bd1c36", "3e3a35"),
    (10, "TEN", "Tennessee", "Titans", "South", "AFC", "4495d2", "001532"),
    (28, "WSH", "Washington", "Commanders", "East", "NFC", "5a1414", "ffb612"),
)

DIVISION_ORDER = ("AFC East", "AFC North", "AFC South", "AFC West",
                  "NFC East", "NFC North", "NFC South", "NFC West")
CONFERENCE_ORDER = ("AFC", "NFC")


def _build_teams():
    teams = {}
    for team_id, abbr, city, nickname, division, conference, color, alt in TEAM_ROWS:
        teams[team_id] = {
            "id": team_id,
            "abbr": abbr,
            "city": city,
            "nickname": nickname,
            "name": nickname,
            "division": division,
            "conference": conference,
            "divisionName": conference + " " + division,
            "color": "#" + color,
            "alt": "#" + alt,
            "slug": (city + "-" + nickname).lower().replace(" ", "-"),
        }
    return teams


TEAMS = _build_teams()
TEAM_IDS = frozenset(TEAMS)


def team(team_id):
    """The team record for an id, or None for anything unknown."""
    value = int(number(team_id, 0) or 0)
    return TEAMS.get(value)


def team_by_abbr(abbr):
    for row in TEAMS.values():
        if row["abbr"] == abbr:
            return row
    return None


def number(value, default=None):
    if isinstance(value, bool):
        return default
    if isinstance(value, dict):
        value = value.get("displayValue", value.get("value"))
    try:
        result = float(value)
    except (TypeError, ValueError):
        return default
    return result if math.isfinite(result) else default


def text(value, limit=120):
    result = str(value or "").strip()
    return result[:limit]


def allowed_url(url):
    """Only the feeds this widget is built around.

    Every URL here is built from constants and a team abbreviation, never from
    anything the user typed, but a request is still worth gating: the process
    runs a shell tool, and a refactor should not quietly widen that.
    """
    parsed = urlparse(text(url, 500))
    if parsed.scheme != "https" or parsed.hostname not in ALLOWED_HOSTS:
        return ""
    return url


def fetch_json(url, timeout=12):
    """The JSON feed, fetched with curl.

    ESPN answers curl and refuses Python's own TLS client with a 403, so this
    shells out rather than pretending urllib works. Everything else in the
    plugin runs system tools the same way.
    """
    target = allowed_url(url)
    if not target:
        raise ValueError("Refusing an unexpected request")
    result = subprocess.run(
        [CURL, "--silent", "--show-error", "--location", "--fail",
         "--compressed", "--max-filesize", str(MAX_BYTES),
         "--max-time", str(int(timeout)),
         "--header", "Accept: application/json", target],
        capture_output=True, text=True, timeout=timeout + 5, check=False)
    if result.returncode != 0:
        detail = text(result.stderr, 200)
        raise OSError(detail or "curl could not read the feed")
    payload = json.loads(result.stdout)
    if not isinstance(payload, dict):
        raise ValueError("Feed did not return an object")
    return payload


# --------------------------------------------------------------------- links


def team_url(row):
    """The club's own page. Always valid, so it is the safe link."""
    if not row:
        return NFL_SITE + "/teams/"
    return NFL_SITE + "/teams/" + row["slug"] + "/"


def standings_url():
    return NFL_SITE + "/standings"


def club_schedule_url(abbr, year):
    return SITE + "/teams/" + str(abbr).lower() + "/schedule?season=" + str(int(year))


def game_url(away, home, year, season_type, week):
    """NFL.com's gamecast path: /games/broncos-at-chiefs-2026-reg-1.

    Verified against nfl.com for the regular season. The postseason and
    preseason tokens come from the same path convention NFL uses in its own
    schedule links (/schedule/2026/POST1/), and the tile falls back to the
    club page rather than a dead link if one ever drifts.
    """
    if not away or not home:
        return ""
    token = SEASON_TOKENS.get(int(season_type or 0))
    if not token or not week:
        return ""
    week = int(week)
    if week < 1:
        return ""
    return NFL_SITE + "/games/{}-at-{}-{}-{}-{}".format(
        away["nickname"].lower(), home["nickname"].lower(),
        int(year), token, week)


# ----------------------------------------------------------------- calendar


def parse_stamp(value):
    stamp = text(value, 40)
    if not stamp:
        return None
    if stamp.endswith("Z"):
        stamp = stamp[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(stamp)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def local(moment, now=None):
    """A UTC stamp as this computer's wall clock."""
    if moment is None:
        return None
    return moment.astimezone()


def hour_label(moment, now=None):
    """A kickoff time the way a schedule lists it: 1:05 PM."""
    if moment is None:
        return ""
    hour = moment.hour % 12 or 12
    suffix = "AM" if moment.hour < 12 else "PM"
    if moment.minute:
        return "{}:{:02d} {}".format(hour, moment.minute, suffix)
    return "{} {}".format(hour, suffix)


def day_label(moment, now):
    """TODAY, TOM, or a weekday, from the local calendar."""
    if moment is None or now is None:
        return ""
    days = (moment.date() - now.date()).days
    if days == 0:
        return "TODAY"
    if days == 1:
        return "TOM"
    if -6 <= days <= 6:
        return ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"][moment.weekday()]
    return moment.strftime("%b %-d")


def clock_label(seconds):
    """Game clock as M:SS. A quarter is 15 minutes, so this is never big."""
    value = number(seconds)
    if value is None or value < 0:
        return ""
    total = int(value)
    return "{}:{:02d}".format(total // 60, total % 60)


def quarter_label(period):
    """1st through 4th, then OT. Extra quarters keep their count."""
    value = int(number(period, 0) or 0)
    if value < 1:
        return ""
    if value <= 4:
        return ["", "1st", "2nd", "3rd", "4th"][value]
    if value == 5:
        return "OT"
    return str(value - 4) + "OT"


def down_label(down, distance):
    """The ordinal plus the yards, the way a broadcast says it."""
    value = int(number(down, 0) or 0)
    if value < 1:
        return ""
    if value == 1:
        first = "1st"
    elif value == 2:
        first = "2nd"
    elif value == 3:
        first = "3rd"
    elif value == 4:
        first = "4th"
    else:
        first = str(value) + "th"
    yards = int(number(distance, 0) or 0)
    if yards > 0:
        return first + " & " + str(yards)
    return first + " & Goal"


# -------------------------------------------------------------------- games


def _score_of(competitor):
    value = number(competitor.get("score"))
    return int(value) if value is not None else None


def _record_of(competitor):
    records = competitor.get("records")
    if not isinstance(records, list):
        return ""
    for record in records:
        if isinstance(record, dict) and record.get("type") == "total":
            return text(record.get("summary"), 12)
    for record in records:
        if isinstance(record, dict) and record.get("name") == "overall":
            return text(record.get("summary"), 12)
    return ""


def _side(competitor, score):
    """One team on the tile, filled out from the table when it is known."""
    raw = competitor.get("team") if isinstance(competitor, dict) else None
    raw = raw if isinstance(raw, dict) else {}
    team_id = int(number(raw.get("id"), 0) or 0)
    known = TEAMS.get(team_id)
    abbr = text(raw.get("abbreviation"), 6) or text(raw.get("shortDisplayName"), 6)
    if known:
        return {
            "id": team_id,
            "abbr": known["abbr"],
            "city": known["city"],
            "nickname": known["nickname"],
            "name": known["nickname"],
            "color": known["color"],
            "alt": known["alt"],
            "score": score,
            "record": _record_of(competitor) if isinstance(competitor, dict) else "",
            "winner": bool(competitor.get("winner")) if isinstance(competitor, dict) else False,
        }
    return {
        "id": team_id,
        "abbr": abbr,
        "city": text(raw.get("location"), 24),
        "nickname": text(raw.get("name"), 24),
        "name": text(raw.get("name"), 24) or abbr,
        "color": "",
        "alt": "",
        "score": score,
        "record": _record_of(competitor) if isinstance(competitor, dict) else "",
        "winner": bool(competitor.get("winner")) if isinstance(competitor, dict) else False,
    }


def _broadcast_name(competition):
    """The TV call, when the feed carries one. Never required.

    The scoreboard offers it twice: a string on the competition and a list of
    networks per market. The list is preferred because a national game is
    named there.
    """
    broadcasts = competition.get("broadcasts")
    if isinstance(broadcasts, list):
        for entry in broadcasts:
            if not isinstance(entry, dict):
                continue
            names = entry.get("names")
            if isinstance(names, list):
                for name in names:
                    value = text(name, 24)
                    if value:
                        return value
            for key in ("shortName", "name"):
                value = text(entry.get(key), 24)
                if value:
                    return value
    single = text(competition.get("broadcast"), 24)
    return single


def _situation(competition, sides):
    """Down, distance and field position, the parts of a drive that matter.

    `possession` arrives as a team id, so it is resolved to a ticker for the
    ball marker. Missing pieces stay null rather than becoming a fake 0.

    `yardLine` is the line of scrimmage measured from the offence's own goal
    line, so 20 is their own 20 and 80 is the opponent's 20. The tile draws it
    on a field, which is why it is carried through rather than only shown as
    text.
    """
    raw = competition.get("situation")
    if not isinstance(raw, dict):
        return {"down": None, "distance": None, "downDistance": "",
                "ball": "", "possession": "", "yardLine": None, "lastPlay": "",
                "redZone": False}
    down = number(raw.get("down"))
    distance = number(raw.get("distance"))
    yard = number(raw.get("yardLine"))
    possession_id = int(number(raw.get("possession"), 0) or 0)
    holder = TEAMS.get(possession_id)
    down_distance = text(raw.get("shortDownDistanceText"), 12)
    if not down_distance:
        down_distance = down_label(down, distance)
    ball = text(raw.get("possessionText"), 16)
    if not ball and holder:
        ball = holder["abbr"]
    return {
        "down": int(down) if down is not None else None,
        "distance": int(distance) if distance is not None else None,
        "downDistance": down_distance,
        "ball": ball,
        "possession": holder["abbr"] if holder else "",
        "yardLine": int(yard) if yard is not None else None,
        "lastPlay": text(raw.get("lastPlay", {}).get("text")
                         if isinstance(raw.get("lastPlay"), dict) else "", 160),
        "redZone": bool(raw.get("isRedZone")),
    }


def parse_game(event, now, favorite_id=0):
    """One scoreboard or schedule event as a tile game, or None if unusable."""
    if not isinstance(event, dict):
        return None
    competitions = event.get("competitions")
    if not isinstance(competitions, list) or not competitions:
        return None
    competition = competitions[0]
    if not isinstance(competition, dict):
        return None
    competitors = competition.get("competitors")
    if not isinstance(competitors, list) or len(competitors) < 2:
        return None

    away = home = None
    for competitor in competitors:
        if not isinstance(competitor, dict):
            continue
        side = _side(competitor, _score_of(competitor))
        if competitor.get("homeAway") == "home":
            home = side
        elif away is None:
            away = side
    if not away or not home or not home.get("abbr"):
        return None

    status = event.get("status") if isinstance(event.get("status"), dict) else {}
    kind = status.get("type") if isinstance(status.get("type"), dict) else {}
    state = text(kind.get("state"), 8)

    start = parse_stamp(event.get("date") or competition.get("date"))
    period = int(number(status.get("period"), 0) or 0)
    # displayClock is already "6:33". Only the raw seconds need formatting.
    clock = text(status.get("displayClock"), 8) or clock_label(status.get("clock"))
    scored = any(s.get("score") is not None for s in (away, home))

    if state not in ("pre", "in", "post"):
        # A club's schedule carries no status at all, so the calendar decides:
        # a game with a date in the past and both scores posted is done. Live
        # games always come from the scoreboard, which does send a status.
        state = "post" if (start and scored and start <= now) else "pre"
    elif not state and kind.get("completed"):
        state = "post"
    if not state:
        state = "pre"

    start_local = local(start, now)
    live = state == "in"
    finished = state == "post"

    # Between plays the feed reports the period with a 0:00 clock and no
    # possession at all. A clock of zero is not a time anyone wants to read,
    # so the period stands on its own instead.
    if live and clock in ("0:00", "0:00.0", ""):
        clock = ""

    season = event.get("season") if isinstance(event.get("season"), dict) else {}
    week_block = event.get("week") if isinstance(event.get("week"), dict) else {}
    year = int(number(season.get("year"), number(week_block.get("year"), 0)) or 0)
    season_type = int(number(season.get("type"), REGULAR) or REGULAR)
    week = int(number(week_block.get("number"), 0) or 0)

    away_row = TEAMS.get(away["id"])
    home_row = TEAMS.get(home["id"])
    link = game_url(away_row, home_row, year, season_type, week) if year and week else ""

    favorite = ""
    if favorite_id and away["id"] == favorite_id:
        favorite = "away"
    elif favorite_id and home["id"] == favorite_id:
        favorite = "home"
    won = ""
    if finished and (away["score"] is not None and home["score"] is not None):
        if away["score"] > home["score"]:
            won = "away"
        elif home["score"] > away["score"]:
            won = "home"
        else:
            won = "tie"

    game = {
        "id": text(event.get("id"), 24),
        "url": link or team_url(home_row or away_row),
        "date": start.isoformat() if start else "",
        "state": state,
        "live": live,
        "finished": finished,
        "day": day_label(start_local, now),
        # The quarter and clock only mean something while a game is running.
        # A final reads FINAL, not "4th 0:00".
        "quarter": quarter_label(period) if (period and live) else "",
        "clock": clock if live else "",
        "kickoff": hour_label(start_local, now),
        "neutral": bool(competition.get("neutralSite")),
        "network": _broadcast_name(competition),
        "away": away,
        "home": home,
        "awayScore": away["score"],
        "homeScore": home["score"],
        "favorite": favorite,
        "won": won,
        "year": year,
        "seasonType": season_type,
        "week": week,
    }
    game["time"] = game_time(game)
    # Only a running game has a drive to describe. Before kickoff and after
    # the whistle there is no line of scrimmage to draw, and inventing one
    # would put a ball marker on a field nobody is on.
    game.update(_situation(competition, game) if live else
                {"down": None, "distance": None, "downDistance": "", "ball": "",
                 "possession": "", "yardLine": None, "lastPlay": "",
                 "redZone": False})
    return game


def game_time(game):
    """One line that says when this game is, or where it stands."""
    if not game:
        return ""
    if game.get("live"):
        quarter = game.get("quarter") or ""
        clock = game.get("clock") or ""
        if quarter and clock:
            return quarter + " " + clock
        return quarter or clock or "LIVE"
    if game.get("finished"):
        return "FINAL"
    kickoff = game.get("kickoff") or ""
    day = game.get("day") or ""
    if day == "TODAY":
        return kickoff
    if day and kickoff:
        return day + " " + kickoff
    return day or kickoff


def _stamp_of(game):
    return parse_stamp(game.get("date")) if game else None


# ------------------------------------------------------------------ schedule


def parse_schedule(payload, team_id, now):
    """The club's season: record, last result, and the next game.

    The record is summed from played games rather than read from the standings
    feed, so the tile still has a record if that request fails.
    """
    result = {
        "season": 0,
        "record": "",
        "wins": 0,
        "losses": 0,
        "ties": 0,
        "pointsFor": 0,
        "pointsAgainst": 0,
        "games": 0,
        "streak": "",
        "last": None,
        "next": None,
        "byeWeek": None,
    }
    if not isinstance(payload, dict):
        return result
    if not team(team_id):
        return result
    season = payload.get("season") if isinstance(payload.get("season"), dict) else {}
    result["season"] = int(number(season.get("year"), 0) or 0)
    events = payload.get("events")
    if not isinstance(events, list):
        return result
    games = []
    for event in events:
        game = parse_game(event, now, team_id)
        if game:
            games.append(game)
    games.sort(key=lambda g: (_stamp_of(g) or now))

    results = []
    for game in games:
        if not game["finished"] or game["awayScore"] is None or game["homeScore"] is None:
            continue
        if game["favorite"] not in ("away", "home"):
            continue
        mine = game["awayScore"] if game["favorite"] == "away" else game["homeScore"]
        theirs = game["homeScore"] if game["favorite"] == "away" else game["awayScore"]
        result["pointsFor"] += int(mine)
        result["pointsAgainst"] += int(theirs)
        result["games"] += 1
        if mine > theirs:
            result["wins"] += 1
            results.append("W")
        elif theirs > mine:
            result["losses"] += 1
            results.append("L")
        else:
            result["ties"] += 1
            results.append("T")
        result["last"] = game

    if result["games"]:
        result["record"] = "{}-{}".format(result["wins"], result["losses"])
        if result["ties"]:
            result["record"] += "-{}".format(result["ties"])
    result["streak"] = streak_text(results)

    # A club's own schedule cannot describe a playoff game, but the calendar
    # still orders whatever the feed gave us.
    upcoming = [g for g in games if g["state"] == "pre" and _stamp_of(g)]
    upcoming = [g for g in upcoming if (_stamp_of(g) or now) > now]
    if upcoming:
        result["next"] = upcoming[0]
    bye = int(number(payload.get("byeWeek"), 0) or 0)
    result["byeWeek"] = bye or None
    return result


def streak_text(results):
    """The current run, as W3 or L2. A tie breaks the run."""
    if not results:
        return ""
    last = results[-1]
    count = 0
    for mark in reversed(results):
        if mark != last:
            break
        count += 1
    return last + str(count)


# ----------------------------------------------------------------- standings


def parse_standings(payload, team_id):
    """Seed, division place and streak for one club.

    A miss here is survivable, so every field has a safe empty default and the
    tile keeps the record it already summed from the schedule.
    """
    result = {"seed": 0, "divisionRank": 0, "conferenceRank": 0,
              "streak": "", "division": "", "conference": "",
              "divisionName": "", "playoffSeed": 0}
    if not isinstance(payload, dict) or not team_id:
        return result
    children = payload.get("children")
    if not isinstance(children, list):
        return result
    for conference in children:
        if not isinstance(conference, dict):
            continue
        entries = (conference.get("standings") or {}).get("entries")
        if not isinstance(entries, list):
            continue
        abbr = conference.get("abbreviation") or ""
        for index, entry in enumerate(entries):
            if not isinstance(entry, dict):
                continue
            row = entry.get("team") if isinstance(entry.get("team"), dict) else {}
            if int(number(row.get("id"), 0) or 0) != team_id:
                continue
            stats = {}
            for stat in entry.get("stats") or []:
                if isinstance(stat, dict) and stat.get("name"):
                    stats[stat["name"]] = stat.get("displayValue")
            seed = int(number(stats.get("playoffSeed"), 0) or 0)
            result["seed"] = seed
            result["conference"] = abbr
            result["conferenceRank"] = index + 1
            result["streak"] = text(stats.get("streak"), 6)
            own = TEAMS.get(team_id)
            if own:
                result["division"] = own["division"]
                result["divisionName"] = own["divisionName"]
            return result
    return result


# --------------------------------------------------------------------- view


def _sort_key(game, now):
    """Live games first, then finished, then by kickoff."""
    order = {"in": 0, "post": 2, "pre": 1}
    stamp = _stamp_of(game) or now
    return (order.get(game.get("state"), 3), stamp)


def _finished_recently(game, now):
    """A final score is worth showing for a few hours, not all week."""
    stamp = _stamp_of(game)
    if stamp is None:
        return False
    return timedelta(0) <= (now - stamp) <= timedelta(hours=6)


def build(slate, schedule, standings, team_id, now):
    """The whole tile payload, from three parsed feeds."""
    team_id = int(team_id or 0)
    home_row = team(team_id)
    games = [g for g in slate if isinstance(g, dict)]
    games.sort(key=lambda g: _sort_key(g, now))

    mine = [g for g in games if g.get("favorite") in ("away", "home")]
    live = [g for g in games if g.get("live")]
    context = parse_schedule(schedule, team_id, now) if team_id else {}
    standing = parse_standings(standings, team_id) if team_id else {}

    focus = None
    mode = "empty"
    if home_row:
        for game in mine:
            if game.get("live"):
                focus = game
                mode = "live"
                break
        if focus is None:
            for game in mine:
                if _finished_recently(game, now) and not live:
                    focus = game
                    mode = "final"
                    break
        if focus is None:
            upcoming = context.get("next")
            if upcoming is None:
                # A playoff game is not in the club's regular-season schedule,
                # so the slate is the only place it can come from.
                for game in mine:
                    if game.get("state") == "pre" and (_stamp_of(game) or now) > now:
                        upcoming = game
                        break
            if upcoming:
                focus = upcoming
                mode = "upcoming"
            elif context.get("games"):
                mode = "closed"
            elif live:
                mode = "board"
            else:
                mode = "empty"
    else:
        if live:
            mode = "board"
        elif games:
            mode = "board"
        else:
            mode = "empty"

    board = live + [g for g in games if g not in live]
    summary = ""
    if home_row:
        record = text(context.get("record"), 12)
        if mode == "closed":
            summary = "Season complete"
        elif record:
            summary = record
    elif mode == "board":
        summary = "Week slate"

    reason = ""
    if mode == "closed":
        reason = "complete"
    elif mode == "upcoming" and focus:
        reason = "schedule"
    elif mode == "live":
        reason = "live"
    elif mode == "final":
        reason = "final"

    poll_ms = POLL_OFF_MS
    if mode == "live":
        poll_ms = POLL_LIVE_MS
    elif mode == "board" and live:
        poll_ms = POLL_LIVE_MS
    elif mode in ("upcoming", "board", "final"):
        poll_ms = POLL_IDLE_MS
    else:
        poll_ms = POLL_OFF_MS

    team_payload = None
    if home_row:
        team_payload = {
            "id": home_row["id"],
            "abbr": home_row["abbr"],
            "city": home_row["city"],
            "nickname": home_row["nickname"],
            "name": home_row["nickname"],
            "color": home_row["color"],
            "alt": home_row["alt"],
            "division": home_row["division"],
            "conference": home_row["conference"],
            "divisionName": home_row["divisionName"],
            "record": text(context.get("record"), 12),
            "wins": context.get("wins", 0),
            "losses": context.get("losses", 0),
            "ties": context.get("ties", 0),
            "games": context.get("games", 0),
            "streak": text(context.get("streak") or standing.get("streak"), 6),
            "pointsFor": context.get("pointsFor", 0),
            "pointsAgainst": context.get("pointsAgainst", 0),
            "differential": context.get("pointsFor", 0) - context.get("pointsAgainst", 0),
            "seed": standing.get("seed", 0),
            "conferenceRank": standing.get("conferenceRank", 0),
            "url": team_url(home_row),
            "standingsUrl": standings_url(),
        }

    return {
        "ok": True,
        "mode": mode,
        "banner": "NFL",
        "reason": reason,
        "summary": summary,
        "error": None,
        "pollMs": poll_ms,
        "season": context.get("season", 0) if home_row else 0,
        "seasonName": SEASON_NAMES.get(REGULAR) if home_row else "",
        "focus": focus,
        "games": board[:8],
        "next": context.get("next"),
        "last": context.get("last"),
        "team": team_payload,
        "standingsUrl": standings_url(),
    }


def error_view(message="NFL scores unavailable", team_id=0, now=None):
    home_row = team(team_id)
    return {
        "ok": False,
        "mode": "empty",
        "banner": "NFL",
        "reason": "error",
        "summary": "",
        "error": text(message, 120) or "NFL scores unavailable",
        "pollMs": POLL_OFF_MS,
        "season": 0,
        "seasonName": "",
        "focus": None,
        "games": [],
        "next": None,
        "last": None,
        "team": {
            "id": home_row["id"],
            "abbr": home_row["abbr"],
            "city": home_row["city"],
            "nickname": home_row["nickname"],
            "name": home_row["nickname"],
            "color": home_row["color"],
            "alt": home_row["alt"],
            "division": home_row["division"],
            "conference": home_row["conference"],
            "divisionName": home_row["divisionName"],
            "record": "",
            "wins": 0,
            "losses": 0,
            "ties": 0,
            "games": 0,
            "streak": "",
            "pointsFor": 0,
            "pointsAgainst": 0,
            "differential": 0,
            "seed": 0,
            "conferenceRank": 0,
            "url": team_url(home_row),
            "standingsUrl": standings_url(),
        } if home_row else None,
        "standingsUrl": standings_url(),
    }


def collect(team_id, now, fetch=fetch_json):
    """Slate, then the club's season, then standings.

    Standings are the one optional call: they only add a seed and a place, so
    they are skipped while a game is live rather than spend a request on a
    number that cannot change before the next snap.
    """
    team_id = int(team_id or 0)
    home_row = team(team_id)
    slate_payload = None
    try:
        slate_payload = fetch(SITE + "/scoreboard")
    except Exception:
        slate_payload = None
    events = slate_payload.get("events") if isinstance(slate_payload, dict) else None
    slate = []
    now_epoch = None
    for event in events or []:
        game = parse_game(event, now, team_id)
        if game:
            slate.append(game)
            if now_epoch is None and game.get("date"):
                now_epoch = parse_stamp(game["date"])

    if not slate and not home_row:
        return error_view("Scores unavailable", team_id, now)

    schedule_payload = None
    if home_row:
        season = 0
        if isinstance(slate_payload, dict):
            season = int((slate_payload.get("season") or {}).get("year") or 0)
        if not season:
            season = now.year
        try:
            schedule_payload = fetch(club_schedule_url(home_row["abbr"], season))
        except Exception:
            schedule_payload = None

    context = parse_schedule(schedule_payload, team_id, now)
    team_live = any(g.get("live") and g.get("favorite") for g in slate)

    standings_payload = None
    if home_row and context.get("games") and not team_live:
        season = context.get("season") or now.year
        try:
            standings_payload = fetch(STANDINGS_API + "?season=" + str(season) + "&seasontype=2")
        except Exception:
            standings_payload = None

    if not slate and not home_row:
        return error_view("Scores unavailable", team_id, now)
    if home_row and not slate and not context.get("games") and not context.get("next"):
        return error_view("Scores unavailable", team_id, now)

    return build(slate, schedule_payload, standings_payload, team_id, now)


# ------------------------------------------------------------------ catalog


def catalog():
    """The settings panel list: conference, division, club."""
    rows = []
    for conference in CONFERENCE_ORDER:
        for division in ("East", "North", "South", "West"):
            for row in sorted(TEAMS.values(), key=lambda r: r["city"]):
                if row["conference"] != conference or row["division"] != division:
                    continue
                rows.append({
                    "id": row["id"],
                    "abbr": row["abbr"],
                    "name": row["city"],
                    "nickname": row["nickname"],
                    "full": row["city"] + " " + row["nickname"],
                    "division": row["division"],
                    "divisionName": row["divisionName"],
                    "conference": row["conference"],
                    "color": row["color"],
                    "alt": row["alt"],
                    "url": team_url(row),
                })
    return rows


def main(argv):
    args = argv[1:]
    now = datetime.now(timezone.utc)
    if "--teams" in args:
        json.dump(catalog(), sys.stdout)
        sys.stdout.write("\n")
        return 0
    team_id = 0
    for flag in ("--team",):
        if flag in args:
            index = args.index(flag)
            team_id = int(number(args[index + 1] if index + 1 < len(args) else 0, 0) or 0)
    try:
        payload = collect(team_id, now)
    except Exception as error:
        payload = error_view(text(error, 120) or "Scores unavailable", team_id, now)
    json.dump(payload, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
