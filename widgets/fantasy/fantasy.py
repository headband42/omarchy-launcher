#!/usr/bin/env python3
"""Fantasy football matchups for the launcher tile. Stdlib only.

    fantasy.py --leagues JSON    the tile: this week's matchup in each league
    fantasy.py --find JSON       the settings panel: a league's teams, or a
                                 Sleeper user's or a Yahoo account's leagues
    fantasy.py --yahoo-signin    trade a Yahoo sign-in code for tokens (beta)
    fantasy.py --forget KEY      drop the saved sign-in for one league

A league entry is {"p": platform, "id": league, "team": team}. Sleeper adds
"user", the owner's user id, so a league that rolled over into a new season
is followed to its new id. Every platform is reduced to one shape: my side
and the opponent's (score, projection, players left to play, players playing,
record), lineup alerts for my starters, and the league's name and link.

What each platform answers (checked against live leagues on 2026-10-01):

Sleeper      api.sleeper.app/v1, public. Week from /state/nfl. A starter
             id of "0" is an empty slot; a team code is a defense. Names and
             injuries come from /players/nfl, about 15 MB, which Sleeper asks
             to be fetched at most once a day, so a trimmed copy is cached.
             Projections come from api.sleeper.com/projections, which is not
             in Sleeper's documentation: when it fails there is no projection.
ESPN         lm-api-reads.fantasy.espn.com, public leagues. A private league
             answers 401 until it has the espn_s2 and SWID cookies (beta).
             X-Fantasy-Filter narrows the box score to this week and this team
             (about 100 KB instead of 400). Injuries are only in mRoster.
Fleaflicker  www.fleaflicker.com/api, public. A league that stopped playing
             answers a request for this season with its last season and no
             error. Only a live league says `activeForCurrentSeason: true` in
             the standings (a dead one leaves it out), so that is the gate.
             The box score refuses a `season` parameter with a 400. The injury
             field is spelled `typeAbbreviaition` by Fleaflicker.
MFL          api.myfantasyleague.com, public leagues. A call that names a
             league (L=) redirects to that league's own server; one that does
             not (players, injuries) must stay on api., or it is refused. A
             one-item list arrives as a bare object.
             A private league needs the owner's API key (beta).
Fantrax      www.fantrax.com/fxea, public. Schedule, standings and rosters
             only: the public API has no scores. An error is a 200 with
             {"error": ...}, so the body is the gate, not the status.
Yahoo        fantasysports.yahooapis.com, OAuth 2 only (beta, untested). The
             user registers an app with Yahoo, signs in once, and pastes the
             code. The tokens belong to this tile, so this file refreshes them.

CBS is left out: its API is deprecated, and the only working sign-in poses as
CBS's own mobile app with that app's built-in secret and the user's password.

Bye weeks and kickoff times for every platform come from ESPN's public NFL
schedule: one call, cached for half a day. A starter whose club has kicked off
counts as playing until four hours later; one whose club has not, as left.

Sign-ins live in $XDG_CONFIG_HOME/ande.launcher/fantasy-auth.json, mode 0600.
They are never in the launcher's config, the cache, argv, or stdout. The
settings panel hands a new one over in the ANDE_FANTASY_AUTH environment
variable. Nothing here reaches the network on its own: `fetch` is injected,
and the tests replace it.
"""

import base64
import gzip
import io
import json
import math
import os
import re
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen

MAX_LEAGUES = 6
USER_AGENT = "omarchy-launcher-fantasy"
TIMEOUT = 15
# Sleeper's player list is the largest reply: 2.6 MB on the wire, 15 MB unpacked.
MAX_WIRE = 8_000_000
MAX_BODY = 40_000_000

HOUR_MS = 3600 * 1000
DAY_MS = 24 * HOUR_MS
# Kickoff to final, overtime included.
GAME_MS = 4 * HOUR_MS
SCHEDULE_TTL_MS = 12 * HOUR_MS
PROJECTION_TTL_MS = 3 * HOUR_MS

POLL_LIVE_MS = 60000
POLL_SOON_MS = 300000
POLL_IDLE_MS = 1800000
SOON_MS = 2 * HOUR_MS

AUTH_ENV = "ANDE_FANTASY_AUTH"

PLATFORMS = {
    "sleeper": ("Sleeper", False),
    "espn": ("ESPN", False),
    "fleaflicker": ("Fleaflicker", False),
    "mfl": ("MyFantasyLeague", False),
    "fantrax": ("Fantrax", False),
    "yahoo": ("Yahoo", True),
}

# League and team ids, per platform. Every id ends up in a URL.
ID_PATTERNS = {
    "sleeper": (r"\d{1,24}", r"\d{1,4}"),
    "espn": (r"\d{1,12}", r"\d{1,4}"),
    "fleaflicker": (r"\d{1,12}", r"\d{1,12}"),
    "mfl": (r"\d{1,8}", r"\d{4}"),
    "fantrax": (r"[a-z0-9]{4,32}", r"[a-z0-9]{4,32}"),
    "yahoo": (r"\d{1,6}\.l\.\d{1,12}", r"\d{1,4}"),
}
SLEEPER_USER = re.compile(r"[A-Za-z0-9_]{1,40}")
SLEEPER_USER_ID = re.compile(r"\d{1,24}")

TEAMS = (
    "ARI", "ATL", "BAL", "BUF", "CAR", "CHI", "CIN", "CLE", "DAL", "DEN", "DET",
    "GB", "HOU", "IND", "JAX", "KC", "LAC", "LAR", "LV", "MIA", "MIN", "NE",
    "NO", "NYG", "NYJ", "PHI", "PIT", "SEA", "SF", "TB", "TEN", "WAS",
)
# Each platform spells a few clubs its own way. MFL: GBP, KCC, NEP, NOS,
# SFO, TBB, LVR, JAC. ESPN: WSH.
TEAM_ALIASES = {
    "WSH": "WAS", "JAC": "JAX", "KCC": "KC", "GBP": "GB", "NEP": "NE",
    "NOS": "NO", "SFO": "SF", "TBB": "TB", "LVR": "LV", "OAK": "LV",
    "SD": "LAC", "SDC": "LAC", "STL": "LAR", "LA": "LAR",
}

ESPN_POSITIONS = {1: "QB", 2: "RB", 3: "WR", 4: "TE", 5: "K", 16: "DEF"}
# ESPN lineup slots that are not starting: bench and injured reserve.
ESPN_RESERVE_SLOTS = {20, 21}
YAHOO_RESERVE_SLOTS = {"BN", "IR", "IR+", "NA"}
DEFENSE_POSITIONS = {"DEF", "D/ST", "DST", "DEF/ST"}

# The order alerts are listed in: what scores zero for sure comes first.
SEVERITY = {"empty": 0, "bye": 1, "out": 2, "ir": 2, "suspended": 2, "doubtful": 3, "questionable": 4}
OUT_CODES = {
    "O", "OUT", "PUP", "PUPR", "PUPP", "NFI", "NFIR", "NFIA", "NA", "COV",
    "COVID", "COVID19", "DNR", "HOLDOUT", "RETIRED", "INACTIVE",
}
NAME_SUFFIXES = {"JR", "SR", "II", "III", "IV", "V"}
NAME_PARTICLES = {"ST", "VAN", "VON", "DE", "DEL", "DA", "LA", "LE", "MC", "MAC"}

SLEEPER_API = "https://api.sleeper.app/v1"
SLEEPER_PROJECTIONS = "https://api.sleeper.com/projections/nfl/%s/%d"
ESPN_SCHEDULE = "https://lm-api-reads.fantasy.espn.com/apis/v3/games/ffl/seasons/%d?view=proTeamSchedules_wl"
ESPN_LEAGUE = "https://lm-api-reads.fantasy.espn.com/apis/v3/games/ffl/seasons/%d/segments/0/leagues/%s"
FLEA_API = "https://www.fleaflicker.com/api/"
MFL_API = "https://api.myfantasyleague.com/%d/export"
FANTRAX_API = "https://www.fantrax.com/fxea/general/"
YAHOO_API = "https://fantasysports.yahooapis.com/fantasy/v2"
YAHOO_TOKEN = "https://api.login.yahoo.com/oauth2/get_token"


class FetchError(Exception):
    """An HTTP answer that was not a 2xx. `status` is 0 for a bad body."""

    def __init__(self, status, message=""):
        super().__init__(message or "HTTP %s" % status)
        self.status = status


class LeagueError(Exception):
    """A message the tile shows in place of the matchup."""


# —— Small values ——


def number(value):
    if value is None or isinstance(value, bool):
        return None
    try:
        result = float(value)
    except (TypeError, ValueError):
        return None
    return result if math.isfinite(result) else None


def integer(value):
    n = number(value)
    return int(n) if n is not None else None


def points(value):
    n = number(value)
    return None if n is None else round(n, 2)


def text(value, limit=80):
    return re.sub(r"\s+", " ", str(value if value is not None else "")).strip()[:limit]


def as_list(value):
    """MFL turns a one-item list into the bare item."""
    if isinstance(value, list):
        return value
    if isinstance(value, dict):
        return [value]
    return []


def team_code(value):
    code = re.sub(r"[^A-Z]", "", str(value or "").upper())
    code = TEAM_ALIASES.get(code, code)
    return code if code in TEAMS else ""


def injury_kind(value):
    """A platform's injury designation as out, ir, suspended, doubtful,
    questionable, or None for a player expected to play."""
    code = re.sub(r"[^A-Z0-9]", "", str(value or "").upper())
    if not code:
        return None
    if code.startswith("IR") or code in ("INJURYRESERVE", "INJUREDRESERVE"):
        return "ir"
    if code.startswith("SUS"):
        return "suspended"
    if code in OUT_CODES:
        return "out"
    if code in ("D", "DOUBTFUL"):
        return "doubtful"
    if code in ("Q", "QUESTIONABLE", "DAYTODAY", "DTD", "GTD"):
        return "questionable"
    return None


def short_name(name, position="", team=""):
    """What fits in an alert: a surname, or a club for a defense."""
    if str(position or "").upper() in DEFENSE_POSITIONS:
        return (team + " D/ST") if team else "D/ST"
    words = [w for w in text(name, 60).split(" ") if w]
    while len(words) > 1 and words[-1].upper().strip(".") in NAME_SUFFIXES:
        words.pop()
    if not words:
        return ""
    if len(words) > 2 and words[-2].upper().strip(".") in NAME_PARTICLES:
        return words[-2] + " " + words[-1]
    return words[-1]


def flip_name(name):
    """MFL writes "Hurts, Jalen". The tile writes "Jalen Hurts"."""
    value = text(name, 60)
    if "," in value:
        last, first = value.split(",", 1)
        return text(first + " " + last, 60)
    return value


def record_text(wins, losses, ties):
    w, l, t = integer(wins) or 0, integer(losses) or 0, integer(ties) or 0
    return "%d-%d-%d" % (w, l, t) if t else "%d-%d" % (w, l)


def rank_of(team_id, rows):
    """1-based place by win percentage, then points for. rows: (id, w, l, t, pf)."""
    def key(row):
        _, w, l, t, pf = row
        games = (w or 0) + (l or 0) + (t or 0)
        pct = ((w or 0) + 0.5 * (t or 0)) / games if games else 0
        return (-pct, -(pf or 0))
    ordered = sorted(rows, key=key)
    for index, row in enumerate(ordered):
        if str(row[0]) == str(team_id):
            return index + 1
    return None


def current_season(now_ms):
    """The NFL season a date belongs to. January and February finish the
    previous year's season."""
    moment = datetime.fromtimestamp(now_ms / 1000, timezone.utc)
    return moment.year if moment.month >= 3 else moment.year - 1


def parse_time_ms(value):
    """An ISO stamp, including Fantrax's "2026-09-12T11:59:59.0-0400"."""
    stamp = text(value, 40)
    if not stamp:
        return None
    stamp = re.sub(r"\.\d+", "", stamp)
    stamp = re.sub(r"([+-]\d{2})(\d{2})$", r"\1:\2", stamp)
    if stamp.endswith("Z"):
        stamp = stamp[:-1] + "+00:00"
    try:
        moment = datetime.fromisoformat(stamp)
    except ValueError:
        return None
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=timezone.utc)
    return int(moment.timestamp() * 1000)


# —— Files ——


def cache_dir():
    root = os.environ.get("XDG_CACHE_HOME") or str(Path.home() / ".cache")
    return Path(root) / "ande.launcher"


def cache_path():
    return cache_dir() / "fantasy.json"


def auth_path():
    root = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(root) / "ande.launcher" / "fantasy-auth.json"


def read_json(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def write_json(path, data, private=False):
    target = Path(path)
    try:
        target.parent.mkdir(parents=True, exist_ok=True, mode=0o700 if private else 0o777)
        # The tile, the settings panel, and a league thread can all be writing.
        tmp = target.with_name(".%s.%d.%d.tmp" % (target.name, os.getpid(), threading.get_ident()))
        body = json.dumps(data, separators=(",", ":"))
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600 if private else 0o644)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(body)
        os.replace(tmp, target)
        return True
    except OSError:
        return False


AUTH_LOCK = threading.Lock()


def read_auth():
    data = read_json(auth_path())
    return data if isinstance(data, dict) else {}


def save_auth(key, value):
    """Store one sign-in, or drop it when `value` is empty."""
    with AUTH_LOCK:
        data = read_auth()
        if value:
            data[key] = value
        else:
            data.pop(key, None)
        return write_json(auth_path(), data, private=True)


def read_cache(path=None):
    data = read_json(path or cache_path())
    return data if isinstance(data, dict) and data.get("ok") is True else None


def write_cache(payload, path=None, now_ms=None):
    if not isinstance(payload, dict) or payload.get("ok") is not True:
        return False
    if not any(league.get("ok") for league in payload.get("leagues") or []):
        return False
    body = dict(payload)
    body["savedAt"] = int(time.time() * 1000 if now_ms is None else now_ms)
    return write_json(path or cache_path(), body)


# —— Network ——


def fetch_json(url, headers=None, data=None, timeout=TIMEOUT):
    """GET, or POST when `data` is given, and parse the JSON reply."""
    head = {"Accept": "application/json", "Accept-Encoding": "gzip", "User-Agent": USER_AGENT}
    head.update(headers or {})
    body = data.encode("utf-8") if isinstance(data, str) else data
    request = Request(url, data=body, headers=head, method="POST" if body is not None else "GET")
    try:
        with urlopen(request, timeout=timeout) as response:
            raw = response.read(MAX_WIRE + 1)
            encoding = str(response.headers.get("Content-Encoding") or "").lower()
    except HTTPError as error:
        raise FetchError(error.code) from None
    if len(raw) > MAX_WIRE:
        raise FetchError(0, "reply too large")
    if "gzip" in encoding:
        raw = gzip.GzipFile(fileobj=io.BytesIO(raw)).read(MAX_BODY + 1)
        if len(raw) > MAX_BODY:
            raise FetchError(0, "reply too large")
    try:
        return json.loads(raw.decode("utf-8"))
    except ValueError:
        raise FetchError(0, "not JSON") from None


# —— Entries ——


def clean_entry(raw):
    """A stored league entry with ids that are safe to put in a URL, or None."""
    if not isinstance(raw, dict):
        return None
    platform = str(raw.get("p") or "")
    if platform not in ID_PATTERNS:
        return None
    league_re, team_re = ID_PATTERNS[platform]
    league = text(raw.get("id"), 40)
    team = text(raw.get("team"), 40)
    if platform == "fantrax":
        league, team = league.lower(), team.lower()
    if not re.fullmatch(league_re, league) or not re.fullmatch(team_re, team):
        return None
    entry = {"p": platform, "id": league, "team": team}
    user = text(raw.get("user"), 30)
    if platform == "sleeper" and SLEEPER_USER_ID.fullmatch(user):
        entry["user"] = user
    return entry


def parse_entries(value):
    try:
        rows = json.loads(value) if isinstance(value, str) else value
    except ValueError:
        return []
    out, seen = [], set()
    for row in rows if isinstance(rows, list) else []:
        entry = clean_entry(row)
        if not entry or entry_key(entry) in seen:
            continue
        seen.add(entry_key(entry))
        out.append(entry)
        if len(out) >= MAX_LEAGUES:
            break
    return out


def entry_key(entry):
    return "%s:%s:%s" % (entry.get("p"), entry.get("id"), entry.get("team"))


def auth_key(platform, league=""):
    """Where a sign-in is filed: one Yahoo account, else one per league."""
    return "yahoo" if platform == "yahoo" else "%s:%s" % (platform, league)


# —— The NFL schedule ——


def parse_schedule(payload, season):
    """ESPN's pro-team schedule as club codes, bye weeks, and kickoffs by week."""
    settings = payload.get("settings") if isinstance(payload, dict) else None
    clubs = settings.get("proTeams") if isinstance(settings, dict) else None
    ids, byes, games = {}, {}, {}
    for club in clubs if isinstance(clubs, list) else []:
        if not isinstance(club, dict):
            continue
        code = team_code(club.get("abbrev"))
        if not code:
            continue
        ids[str(club.get("id"))] = code
        bye = integer(club.get("byeWeek"))
        if bye:
            byes[code] = bye
        weeks = club.get("proGamesByScoringPeriod")
        for week, rows in (weeks.items() if isinstance(weeks, dict) else []):
            for game in rows if isinstance(rows, list) else []:
                kickoff = integer(game.get("date")) if isinstance(game, dict) else None
                if kickoff and integer(week):
                    games.setdefault(str(integer(week)), {})[code] = kickoff
    return {"season": season, "ids": ids, "byes": byes, "games": games}


def load_schedule(season, fetch, now_ms, path=None):
    target = Path(path) if path else cache_dir() / "fantasy-nfl.json"
    cached = read_json(target)
    same = isinstance(cached, dict) and cached.get("season") == season and cached.get("games")
    if same and now_ms - (number(cached.get("savedAt")) or 0) < SCHEDULE_TTL_MS:
        return cached
    try:
        schedule = parse_schedule(fetch(ESPN_SCHEDULE % season), season)
    except Exception:  # noqa: BLE001 - an old schedule beats none
        schedule = None
    if schedule and schedule["games"]:
        schedule["savedAt"] = now_ms
        write_json(target, schedule)
        return schedule
    return cached if same else None


def game_state(schedule, week, team, now_ms):
    """pre, live, done, or bye for a club this week; "" when unknown."""
    if not schedule or not week or not team:
        return ""
    games = (schedule.get("games") or {}).get(str(week)) or {}
    if not games:
        return ""
    kickoff = games.get(team)
    if kickoff is None:
        return "bye" if team in TEAMS else ""
    if now_ms < kickoff:
        return "pre"
    if now_ms < kickoff + GAME_MS:
        return "live"
    return "done"


def schedule_week(schedule, now_ms):
    """The NFL week in play: the first whose last game is not long over."""
    weeks = (schedule or {}).get("games") or {}
    for week in sorted(weeks, key=int):
        kickoffs = list(weeks[week].values())
        if kickoffs and now_ms < max(kickoffs) + DAY_MS:
            return int(week)
    return None


def poll_ms(schedule, leagues, now_ms):
    if any(league.get("live") for league in leagues):
        return POLL_LIVE_MS
    for games in ((schedule or {}).get("games") or {}).values():
        for kickoff in games.values():
            if kickoff - SOON_MS <= now_ms < kickoff + GAME_MS:
                return POLL_LIVE_MS if now_ms >= kickoff else POLL_SOON_MS
    return POLL_IDLE_MS


# —— One side of a matchup ——


def starter(name, position, team, injury=None, actual=None, projected=None):
    return {
        "name": text(name, 60),
        "pos": text(position, 8).upper(),
        "team": team_code(team),
        "injury": injury,
        "points": number(actual),
        "proj": number(projected),
    }


def tally(starters, empty, schedule, week, now_ms):
    """Players left and playing, a projected total, and lineup alerts.

    A player whose club has kicked off is past fixing, so only players still
    to play raise an alert. A starter in a game counts at the larger of his
    points so far and his projection."""
    known = bool(((schedule or {}).get("games") or {}).get(str(week)))
    left = playing = 0
    total, have_projection = 0.0, False
    alerts = []
    for player in starters:
        state = game_state(schedule, week, player.get("team"), now_ms) if known else ""
        actual = player.get("points") or 0.0
        projected = player.get("proj")
        if projected is not None:
            have_projection = True
        if state == "pre":
            left += 1
        elif state == "live":
            playing += 1
        if state == "done":
            total += actual
        elif state == "live":
            total += max(actual, projected or 0.0)
        elif state != "bye":
            total += projected if projected is not None else actual
        if state in ("pre", "bye", ""):
            kind = "bye" if state == "bye" else injury_kind(player.get("injury"))
            if kind:
                alerts.append({
                    "kind": kind,
                    "name": short_name(player.get("name"), player.get("pos"), player.get("team")),
                    "pos": player.get("pos") or "",
                })
    if empty and int(empty) > 0:
        alerts.append({"kind": "empty", "name": "", "pos": "", "count": int(empty)})
    alerts.sort(key=lambda alert: SEVERITY.get(alert["kind"], 9))
    return {
        "left": left if known else None,
        "playing": playing if known else None,
        "projected": round(total, 2) if have_projection else None,
        "alerts": alerts,
    }


def side(name, score, counted, record="", projected=None, win=None, left=None, playing=None):
    """One team's line on the tile. A platform's own projection or counts win
    over the ones worked out from the schedule."""
    probability = number(win)
    if probability is not None and probability > 1:
        probability = probability / 100.0
    return {
        "name": text(name, 48),
        "score": points(score),
        "projected": points(projected) if number(projected) else counted.get("projected"),
        "left": left if left is not None else counted.get("left"),
        "playing": playing if playing is not None else counted.get("playing"),
        "record": record,
        "win": round(probability, 3) if probability is not None and 0 <= probability <= 1 else None,
    }


def league_base(entry):
    name, beta = PLATFORMS[entry["p"]]
    return {
        "key": entry_key(entry),
        "p": entry["p"],
        "provider": name,
        "beta": beta,
        "ok": True,
        "error": "",
        "note": "",
        "league": "",
        "url": "",
        "week": None,
        "teams": None,
        "rank": None,
        "me": None,
        "opp": None,
        "alerts": [],
        "live": False,
    }


def finish(league, me_counted=None):
    if me_counted:
        league["alerts"] = me_counted["alerts"][:8]
    league["live"] = any(
        (league.get(part) or {}).get("playing") for part in ("me", "opp")
    )
    return league


def failed(entry, message):
    league = league_base(entry)
    league["ok"] = False
    league["error"] = message
    return league


# —— Context shared by the leagues of one run ——


class Context:
    def __init__(self, fetch, now_ms, auth=None, schedule=None):
        self.fetch = fetch
        self.now_ms = now_ms
        self.season = current_season(now_ms)
        self.auth = read_auth() if auth is None else auth
        self.schedule = schedule
        self._lock = threading.Lock()
        self._memo = {}

    def once(self, key, make):
        """make() at most once per run, even across league threads."""
        with self._lock:
            slot = self._memo.setdefault(key, {"lock": threading.Lock()})
        with slot["lock"]:
            if "value" not in slot and "error" not in slot:
                try:
                    slot["value"] = make()
                except Exception as error:  # noqa: BLE001 - re-raised to each caller
                    slot["error"] = error
            if "error" in slot:
                raise slot["error"]
            return slot["value"]

    def week(self):
        return schedule_week(self.schedule, self.now_ms)


# —— Sleeper ——


def sleeper_state(ctx):
    return ctx.once("sleeper:state", lambda: ctx.fetch(SLEEPER_API + "/state/nfl"))


def trim_sleeper_players(payload):
    out = {}
    for pid, row in (payload.items() if isinstance(payload, dict) else []):
        if not isinstance(row, dict):
            continue
        team = team_code(row.get("team"))
        if not team and not row.get("active"):
            continue
        name = row.get("full_name") or "%s %s" % (row.get("first_name") or "", row.get("last_name") or "")
        out[str(pid)] = {"n": text(name, 48), "p": text(row.get("position"), 6), "t": team, "i": text(row.get("injury_status"), 16)}
    return out


def sleeper_players(ctx):
    path = cache_dir() / "fantasy-sleeper-players.json"

    def make():
        cached = read_json(path)
        if isinstance(cached, dict) and ctx.now_ms - (number(cached.get("savedAt")) or 0) < DAY_MS:
            return cached.get("players") or {}
        try:
            players = trim_sleeper_players(ctx.fetch(SLEEPER_API + "/players/nfl"))
        except Exception:  # noqa: BLE001 - yesterday's names beat ids
            players = {}
        if players:
            write_json(path, {"savedAt": ctx.now_ms, "players": players})
            return players
        return (cached or {}).get("players") or {} if isinstance(cached, dict) else {}

    return ctx.once("sleeper:players", make)


def trim_sleeper_projections(payload):
    out = {}
    for row in payload if isinstance(payload, list) else []:
        if not isinstance(row, dict) or not row.get("player_id"):
            continue
        stats = row.get("stats") if isinstance(row.get("stats"), dict) else {}
        player = row.get("player") if isinstance(row.get("player"), dict) else {}
        out[str(row["player_id"])] = {
            "ppr": number(stats.get("pts_ppr")),
            "half": number(stats.get("pts_half_ppr")),
            "std": number(stats.get("pts_std")),
            # Fresher than the once-a-day player list.
            "i": text(player.get("injury_status"), 16) if player else None,
        }
    return out


def sleeper_projections(ctx, season, week, kind):
    path = cache_dir() / "fantasy-sleeper-projections.json"
    key = "%s-%s-%s" % (season, week, kind)

    def make():
        cached = read_json(path)
        same = isinstance(cached, dict) and cached.get("key") == key
        if same and ctx.now_ms - (number(cached.get("savedAt")) or 0) < PROJECTION_TTL_MS:
            return cached.get("rows") or {}
        url = SLEEPER_PROJECTIONS % (quote(str(season)), int(week)) + "?" + urlencode(
            [("season_type", kind)] + [("position[]", p) for p in ("QB", "RB", "WR", "TE", "K", "DEF")])
        try:
            rows = trim_sleeper_projections(ctx.fetch(url))
        except Exception:  # noqa: BLE001 - undocumented; no projection is fine
            rows = {}
        if rows:
            write_json(path, {"key": key, "savedAt": ctx.now_ms, "rows": rows})
            return rows
        return (cached.get("rows") or {}) if same else {}

    return ctx.once("sleeper:proj:" + key, make)


def sleeper_scoring(league):
    rec = number(((league.get("scoring_settings") or {}) if isinstance(league, dict) else {}).get("rec")) or 0
    if rec >= 0.75:
        return "ppr"
    if rec >= 0.25:
        return "half"
    return "std"


def sleeper_team_names(users, rosters):
    by_user = {}
    for user in users if isinstance(users, list) else []:
        if isinstance(user, dict):
            meta = user.get("metadata") if isinstance(user.get("metadata"), dict) else {}
            by_user[str(user.get("user_id"))] = (
                text(meta.get("team_name") or user.get("display_name"), 48),
                text(user.get("display_name"), 48),
            )
    names = {}
    for roster in rosters if isinstance(rosters, list) else []:
        if isinstance(roster, dict):
            team, owner = by_user.get(str(roster.get("owner_id")), ("", ""))
            names[str(roster.get("roster_id"))] = {
                "name": team or "Team %s" % roster.get("roster_id"),
                "owner": owner,
                "user": str(roster.get("owner_id") or ""),
            }
    return names


def sleeper_owns(roster, user):
    owners = [str(roster.get("owner_id") or "")] + [str(x) for x in roster.get("co_owners") or []]
    return bool(user) and str(user) in owners


def sleeper_successor(ctx, user, old_id, season):
    rows = ctx.fetch("%s/user/%s/leagues/nfl/%s" % (SLEEPER_API, user, quote(str(season))))
    for row in rows if isinstance(rows, list) else []:
        if isinstance(row, dict) and str(row.get("previous_league_id") or "") == str(old_id):
            return row
    return None


def sleeper_lineup(row, players, projections, scoring):
    starters, empty = [], 0
    ids = row.get("starters") or []
    scored = row.get("starters_points") or []
    for index, pid in enumerate(ids):
        pid = str(pid or "")
        if pid in ("", "0"):
            empty += 1
            continue
        actual = scored[index] if index < len(scored) else None
        projection = projections.get(pid) or {}
        if team_code(pid) and not pid.isdigit():
            starters.append(starter(pid + " D/ST", "DEF", pid, None, actual, projection.get(scoring)))
            continue
        info = players.get(pid) or {}
        injury = projection.get("i") if projection.get("i") is not None else info.get("i")
        starters.append(starter(info.get("n") or pid, info.get("p"), info.get("t"), injury, actual, projection.get(scoring)))
    return starters, empty


def collect_sleeper(entry, ctx):
    state = sleeper_state(ctx)
    if not isinstance(state, dict):
        raise LeagueError("Sleeper did not answer")
    season = str(state.get("season") or ctx.season)
    kind = str(state.get("season_type") or "regular")
    week = integer(state.get("week")) or 0
    league_id = entry["id"]
    data = ctx.fetch("%s/league/%s" % (SLEEPER_API, league_id))
    if not isinstance(data, dict):
        raise LeagueError("Sleeper has no league %s" % league_id)
    if str(data.get("season")) != season and entry.get("user"):
        newer = sleeper_successor(ctx, entry["user"], league_id, season)
        if newer:
            data, league_id = newer, str(newer.get("league_id"))
    rosters = ctx.fetch("%s/league/%s/rosters" % (SLEEPER_API, league_id))
    users = ctx.fetch("%s/league/%s/users" % (SLEEPER_API, league_id))
    rosters = [r for r in rosters if isinstance(r, dict)] if isinstance(rosters, list) else []
    names = sleeper_team_names(users, rosters)
    mine = next((r for r in rosters if str(r.get("roster_id")) == entry["team"]), None)
    if entry.get("user") and (not mine or not sleeper_owns(mine, entry["user"])):
        mine = next((r for r in rosters if sleeper_owns(r, entry["user"])), mine)
    if not mine:
        raise LeagueError("That team is no longer in this league")
    my_id = str(mine.get("roster_id"))

    def record(roster):
        s = roster.get("settings") if isinstance(roster.get("settings"), dict) else {}
        return record_text(s.get("wins"), s.get("losses"), s.get("ties"))

    def points_for(roster):
        s = roster.get("settings") if isinstance(roster.get("settings"), dict) else {}
        return (number(s.get("fpts")) or 0) + (number(s.get("fpts_decimal")) or 0) / 100.0

    table = [(str(r.get("roster_id")), *(integer((r.get("settings") or {}).get(k)) or 0 for k in ("wins", "losses", "ties")), points_for(r)) for r in rosters]
    league = league_base(entry)
    league.update({
        "league": text(data.get("name"), 60),
        "url": "https://sleeper.com/leagues/%s/matchup" % league_id,
        "teams": len(rosters) or integer(data.get("total_rosters")),
        "rank": rank_of(my_id, table),
    })
    status = str(data.get("status") or "")
    me_name = names.get(my_id, {}).get("name", "")
    if status in ("pre_draft", "drafting"):
        league["note"] = "Drafting now" if status == "drafting" else "Draft not done yet"
        league["me"] = side(me_name, None, {}, record(mine))
        return league
    if status == "complete" or str(data.get("season")) != season or kind not in ("regular", "post") or week < 1:
        league["note"] = "Season over"
        league["me"] = side(me_name, None, {}, record(mine))
        return league
    league["week"] = week
    matchups = ctx.fetch("%s/league/%s/matchups/%d" % (SLEEPER_API, league_id, week))
    matchups = [m for m in matchups if isinstance(m, dict)] if isinstance(matchups, list) else []
    mine_m = next((m for m in matchups if str(m.get("roster_id")) == my_id), None)
    if not mine_m:
        league["note"] = "No matchup this week"
        league["me"] = side(me_name, None, {}, record(mine))
        return league
    players = sleeper_players(ctx)
    projections = sleeper_projections(ctx, season, week, kind)
    scoring = sleeper_scoring(data)
    lineup, empty = sleeper_lineup(mine_m, players, projections, scoring)
    counted = tally(lineup, empty, ctx.schedule, week, ctx.now_ms)
    league["me"] = side(me_name, mine_m.get("points"), counted, record(mine))
    opp_m = None
    if mine_m.get("matchup_id") is not None:
        opp_m = next((m for m in matchups if m is not mine_m and m.get("matchup_id") == mine_m.get("matchup_id")), None)
    if opp_m:
        opp_lineup, opp_empty = sleeper_lineup(opp_m, players, projections, scoring)
        opp_roster = next((r for r in rosters if str(r.get("roster_id")) == str(opp_m.get("roster_id"))), {})
        league["opp"] = side(names.get(str(opp_m.get("roster_id")), {}).get("name", ""), opp_m.get("points"),
                             tally(opp_lineup, opp_empty, ctx.schedule, week, ctx.now_ms), record(opp_roster) if opp_roster else "")
    else:
        league["note"] = "No head-to-head this week"
    return finish(league, counted)


def find_sleeper(spec, ctx):
    state = sleeper_state(ctx)
    season = str((state or {}).get("season") or ctx.season)
    if spec.get("user"):
        user = ctx.fetch("%s/user/%s" % (SLEEPER_API, quote(spec["user"])))
        if not isinstance(user, dict) or not user.get("user_id"):
            raise LeagueError("Sleeper has no user named %s" % spec["user"])
        uid = str(user["user_id"])
        rows = ctx.fetch("%s/user/%s/leagues/nfl/%s" % (SLEEPER_API, uid, quote(season)))
        rows = [r for r in rows if isinstance(r, dict) and r.get("league_id")] if isinstance(rows, list) else []
        if not rows:
            raise LeagueError("%s has no %s football leagues on Sleeper" % (text(user.get("display_name") or spec["user"], 40), season))

        def one(row):
            lid = str(row["league_id"])
            rosters = ctx.fetch("%s/league/%s/rosters" % (SLEEPER_API, lid))
            users = ctx.fetch("%s/league/%s/users" % (SLEEPER_API, lid))
            names = sleeper_team_names(users, rosters)
            mine = next((r for r in rosters or [] if isinstance(r, dict) and sleeper_owns(r, uid)), None)
            if not mine:
                return None
            rid = str(mine.get("roster_id"))
            return {"p": "sleeper", "id": lid, "name": text(row.get("name"), 60), "season": season,
                    "team": rid, "teamName": names.get(rid, {}).get("name", ""), "user": uid, "teams": []}

        with ThreadPoolExecutor(max_workers=6) as pool:
            found = [f for f in pool.map(one, rows[:20]) if f]
        return found
    data = ctx.fetch("%s/league/%s" % (SLEEPER_API, spec["id"]))
    if not isinstance(data, dict):
        raise LeagueError("Sleeper has no league %s" % spec["id"])
    rosters = ctx.fetch("%s/league/%s/rosters" % (SLEEPER_API, spec["id"]))
    users = ctx.fetch("%s/league/%s/users" % (SLEEPER_API, spec["id"]))
    names = sleeper_team_names(users, rosters)
    teams = [{"id": rid, "name": n["name"], "owner": n["owner"], "user": n["user"]} for rid, n in names.items()]
    return [{"p": "sleeper", "id": spec["id"], "name": text(data.get("name"), 60),
             "season": text(data.get("season"), 6), "teams": teams}]


# —— ESPN ——


def espn_headers(ctx, entry_id, extra=None):
    head = dict(extra or {})
    saved = ctx.auth.get(auth_key("espn", entry_id))
    if isinstance(saved, dict) and saved.get("espn_s2") and saved.get("swid"):
        head["Cookie"] = "espn_s2=%s; SWID=%s" % (saved["espn_s2"], saved["swid"])
    return head


def espn_fetch(ctx, entry_id, query, extra=None):
    try:
        return ctx.fetch(ESPN_LEAGUE % (ctx.season, entry_id) + query, headers=espn_headers(ctx, entry_id, extra))
    except FetchError as error:
        if error.status in (401, 403):
            if ctx.auth.get(auth_key("espn", entry_id)):
                raise LeagueError("ESPN refused the saved cookies. Paste fresh ones with the gear (beta).") from None
            raise LeagueError("This ESPN league is private. Add its cookies with the gear (beta).") from None
        if error.status == 404:
            raise LeagueError("ESPN has no league %s for %d" % (entry_id, ctx.season)) from None
        raise


def espn_team_name(team):
    name = team.get("name") or ("%s %s" % (team.get("location") or "", team.get("nickname") or "")).strip()
    return text(name or team.get("abbrev") or "Team %s" % team.get("id"), 48)


def espn_lineup(entries, week, ids, injuries=None):
    starters = []
    for item in entries if isinstance(entries, list) else []:
        if not isinstance(item, dict) or integer(item.get("lineupSlotId")) in ESPN_RESERVE_SLOTS:
            continue
        pool = item.get("playerPoolEntry") if isinstance(item.get("playerPoolEntry"), dict) else {}
        player = pool.get("player") if isinstance(pool.get("player"), dict) else {}
        actual = projected = None
        for stat in player.get("stats") or []:
            if not isinstance(stat, dict) or integer(stat.get("scoringPeriodId")) != week:
                continue
            if integer(stat.get("statSourceId")) == 0:
                actual = stat.get("appliedTotal")
            elif integer(stat.get("statSourceId")) == 1:
                projected = stat.get("appliedTotal")
        position = ESPN_POSITIONS.get(integer(player.get("defaultPositionId")), "")
        team = ids.get(str(player.get("proTeamId")), "")
        injury = (injuries or {}).get(str(item.get("playerId") or player.get("id")))
        starters.append(starter(player.get("fullName"), position, team, injury, actual, projected))
    return starters


def espn_required(settings):
    roster = settings.get("rosterSettings") if isinstance(settings.get("rosterSettings"), dict) else {}
    counts = roster.get("lineupSlotCounts") if isinstance(roster.get("lineupSlotCounts"), dict) else {}
    return sum(integer(v) or 0 for k, v in counts.items() if integer(k) not in ESPN_RESERVE_SLOTS)


def collect_espn(entry, ctx):
    team_id = int(entry["team"])
    flt = {"schedule": {"filterCurrentMatchupPeriod": {"value": True}, "filterTeamIds": {"value": [team_id]}}}
    data = espn_fetch(ctx, entry["id"], "?view=mBoxscore&view=mMatchupScore&view=mTeam&view=mSettings",
                      {"X-Fantasy-Filter": json.dumps(flt, separators=(",", ":"))})
    if not isinstance(data, dict):
        raise LeagueError("ESPN did not answer")
    try:
        roster = espn_fetch(ctx, entry["id"], "?view=mRoster&forTeamId=%d" % team_id)
    except Exception:  # noqa: BLE001 - injuries are extra; the score still shows
        roster = {}
    injuries = {}
    for team in (roster.get("teams") if isinstance(roster, dict) else None) or []:
        for item in ((team.get("roster") or {}).get("entries") or []) if isinstance(team, dict) else []:
            player = ((item.get("playerPoolEntry") or {}).get("player") or {}) if isinstance(item, dict) else {}
            injuries[str(item.get("playerId") or player.get("id"))] = player.get("injuryStatus")
    settings = data.get("settings") if isinstance(data.get("settings"), dict) else {}
    teams = {str(t.get("id")): t for t in data.get("teams") or [] if isinstance(t, dict)}
    mine = teams.get(str(team_id))
    if not mine:
        raise LeagueError("That team is no longer in this league")

    def record(team):
        overall = ((team or {}).get("record") or {}).get("overall") or {}
        return record_text(overall.get("wins"), overall.get("losses"), overall.get("ties"))

    table = []
    for tid, team in teams.items():
        overall = (team.get("record") or {}).get("overall") or {}
        table.append((tid, integer(overall.get("wins")) or 0, integer(overall.get("losses")) or 0,
                      integer(overall.get("ties")) or 0, number(overall.get("pointsFor")) or 0))
    league = league_base(entry)
    league.update({
        "league": text(settings.get("name"), 60),
        "url": "https://fantasy.espn.com/football/team?leagueId=%s&teamId=%d" % (entry["id"], team_id),
        "teams": len(teams),
        "rank": rank_of(str(team_id), table),
    })
    week = integer(data.get("scoringPeriodId"))
    status = data.get("status") if isinstance(data.get("status"), dict) else {}
    matchup = None
    for row in data.get("schedule") or []:
        if not isinstance(row, dict):
            continue
        for part in ("home", "away"):
            if integer((row.get(part) or {}).get("teamId")) == team_id:
                matchup, mine_part = row, part
    if status.get("isExpired"):
        league["note"] = "Season over"
    if not matchup or not week:
        league["note"] = league["note"] or "No matchup this week"
        league["me"] = side(espn_team_name(mine), None, {}, record(mine))
        return league
    league["week"] = week
    ids = (ctx.schedule or {}).get("ids") or {}

    def score_of(part):
        value = part.get("totalPointsLive")
        return value if value is not None else part.get("totalPoints")

    def projection_of(part):
        value = part.get("totalProjectedPointsLive")
        return value if value is not None else part.get("totalProjectedPoints")

    me_part = matchup.get(mine_part) or {}
    lineup = espn_lineup((me_part.get("rosterForCurrentScoringPeriod") or {}).get("entries"), week, ids, injuries)
    empty = max(0, espn_required(settings) - len(lineup)) if lineup or me_part.get("rosterForCurrentScoringPeriod") else 0
    counted = tally(lineup, empty, ctx.schedule, week, ctx.now_ms)
    league["me"] = side(espn_team_name(mine), score_of(me_part), counted, record(mine),
                        projection_of(me_part), me_part.get("winProbability"))
    opp_part = matchup.get("away" if mine_part == "home" else "home")
    if isinstance(opp_part, dict) and opp_part.get("teamId") is not None:
        opp = teams.get(str(opp_part.get("teamId"))) or {}
        opp_lineup = espn_lineup((opp_part.get("rosterForCurrentScoringPeriod") or {}).get("entries"), week, ids)
        league["opp"] = side(espn_team_name(opp) if opp else "", score_of(opp_part),
                             tally(opp_lineup, 0, ctx.schedule, week, ctx.now_ms), record(opp) if opp else "",
                             projection_of(opp_part), opp_part.get("winProbability"))
    else:
        league["note"] = league["note"] or "Bye week"
    return finish(league, counted)


def find_espn(spec, ctx):
    data = espn_fetch(ctx, spec["id"], "?view=mTeam&view=mSettings")
    if not isinstance(data, dict):
        raise LeagueError("ESPN did not answer")
    members = {}
    for member in data.get("members") or []:
        if isinstance(member, dict):
            full = "%s %s" % (member.get("firstName") or "", member.get("lastName") or "")
            members[str(member.get("id"))] = text(member.get("displayName") or full, 40)
    teams = []
    for team in data.get("teams") or []:
        if isinstance(team, dict):
            owners = team.get("owners") or []
            teams.append({"id": str(team.get("id")), "name": espn_team_name(team),
                          "owner": members.get(str(owners[0]), "") if owners else ""})
    name = text((data.get("settings") or {}).get("name"), 60)
    return [{"p": "espn", "id": spec["id"], "name": name, "season": str(ctx.season), "teams": teams}]


# —— Fleaflicker ——


def flea_fetch(ctx, method, **params):
    return ctx.fetch(FLEA_API + method + "?" + urlencode(dict({"sport": "NFL"}, **params)))


def flea_standings(ctx, league_id):
    data = flea_fetch(ctx, "FetchLeagueStandings", league_id=league_id, season=ctx.season)
    league = data.get("league") if isinstance(data, dict) else None
    if not isinstance(league, dict):
        raise LeagueError("Fleaflicker has no league %s" % league_id)
    # A league that stopped playing answers with its last season, no error,
    # and leaves `activeForCurrentSeason` out rather than setting it false.
    if league.get("activeForCurrentSeason") is not True:
        raise LeagueError("This Fleaflicker league isn't playing in %d" % ctx.season)
    teams = []
    for division in data.get("divisions") or []:
        for team in (division.get("teams") or []) if isinstance(division, dict) else []:
            if isinstance(team, dict):
                teams.append(team)
    return league, teams


def flea_player(slot):
    pro = slot.get("proPlayer") if isinstance(slot.get("proPlayer"), dict) else {}
    injury = pro.get("injury") if isinstance(pro.get("injury"), dict) else {}
    actual = (slot.get("viewingActualPoints") or {}).get("value") if isinstance(slot.get("viewingActualPoints"), dict) else None
    projected = (slot.get("viewingProjectedPoints") or {}).get("value") if isinstance(slot.get("viewingProjectedPoints"), dict) else None
    code = injury.get("typeAbbreviaition") or injury.get("typeAbbreviation") or injury.get("severity")
    return starter(pro.get("nameFull"), pro.get("position"), pro.get("proTeamAbbreviation"), code, actual, projected)


def flea_lineup(box, part):
    starters, empty = [], 0
    for group in box.get("lineups") or []:
        if not isinstance(group, dict) or group.get("group") != "START":
            continue
        for slot in group.get("slots") or []:
            mine = slot.get(part) if isinstance(slot, dict) else None
            if not isinstance(mine, dict) or not isinstance(mine.get("proPlayer"), dict):
                empty += 1
                continue
            starters.append(flea_player(mine))
    return starters, empty


def flea_record(team):
    record = team.get("recordOverall") if isinstance(team.get("recordOverall"), dict) else {}
    return record_text(record.get("wins"), record.get("losses"), record.get("ties"))


def collect_fleaflicker(entry, ctx):
    data, teams = flea_standings(ctx, entry["id"])
    by_id = {str(t.get("id")): t for t in teams}
    mine = by_id.get(entry["team"])
    if not mine:
        raise LeagueError("That team is no longer in this league")
    table = [(str(t.get("id")), integer((t.get("recordOverall") or {}).get("wins")) or 0,
              integer((t.get("recordOverall") or {}).get("losses")) or 0,
              integer((t.get("recordOverall") or {}).get("ties")) or 0,
              number((t.get("pointsFor") or {}).get("value")) or 0) for t in teams]
    league = league_base(entry)
    league.update({
        "league": text(data.get("name"), 60),
        "url": "https://www.fleaflicker.com/nfl/leagues/%s" % entry["id"],
        "teams": len(teams),
        "rank": rank_of(entry["team"], table),
    })
    board = flea_fetch(ctx, "FetchLeagueScoreboard", league_id=entry["id"], season=ctx.season)
    week = integer(((board or {}).get("schedulePeriod") or {}).get("value"))
    game = None
    for row in (board or {}).get("games") or []:
        if not isinstance(row, dict):
            continue
        for part in ("home", "away"):
            if str((row.get(part) or {}).get("id")) == entry["team"]:
                game, mine_part = row, part
    if not game or not week:
        league["note"] = "No matchup this week"
        league["me"] = side(mine.get("name"), None, {}, flea_record(mine))
        return league
    league["week"] = week
    league["url"] = "https://www.fleaflicker.com/nfl/leagues/%s/scores/%s" % (entry["id"], quote(str(game.get("id"))))
    # The box score takes no season; it is already this season's game.
    box = flea_fetch(ctx, "FetchLeagueBoxscore", league_id=entry["id"], fantasy_game_id=game.get("id"), scoring_period=week)
    box = box if isinstance(box, dict) else {}
    opp_part = "away" if mine_part == "home" else "home"

    def score_of(part):
        score = game.get(part + "Score") if isinstance(game.get(part + "Score"), dict) else {}
        return ((score.get("score") or {}).get("value")) if isinstance(score.get("score"), dict) else None

    def projection_of(part):
        total = (box.get("points" + part.capitalize()) or {}).get("total") or {}
        return (total.get("projected") or {}).get("value") if isinstance(total.get("projected"), dict) else None

    lineup, empty = flea_lineup(box, mine_part)
    counted = tally(lineup, empty, ctx.schedule, week, ctx.now_ms)
    league["me"] = side(mine.get("name"), score_of(mine_part) or 0, counted, flea_record(mine), projection_of(mine_part))
    opp = by_id.get(str((game.get(opp_part) or {}).get("id"))) or game.get(opp_part) or {}
    opp_lineup, opp_empty = flea_lineup(box, opp_part)
    league["opp"] = side(opp.get("name"), score_of(opp_part) or 0, tally(opp_lineup, opp_empty, ctx.schedule, week, ctx.now_ms),
                         flea_record(opp) if opp.get("recordOverall") else "", projection_of(opp_part))
    return finish(league, counted)


def find_fleaflicker(spec, ctx):
    data, teams = flea_standings(ctx, spec["id"])
    rows = []
    for team in teams:
        owners = team.get("owners") or []
        owner = owners[0].get("displayName") if owners and isinstance(owners[0], dict) else ""
        rows.append({"id": str(team.get("id")), "name": text(team.get("name"), 48), "owner": text(owner, 40)})
    return [{"p": "fleaflicker", "id": spec["id"], "name": text(data.get("name"), 60), "season": str(ctx.season), "teams": rows}]


# —— MyFantasyLeague ——


def mfl_fetch(ctx, league_id, kind, **params):
    """One MFL export. `league_id` "" leaves out L= for the calls that are not
    about a league; those are refused on a league's own server."""
    query = {"TYPE": kind}
    if league_id:
        query["L"] = league_id
    query.update(params)
    query["JSON"] = 1
    saved = ctx.auth.get(auth_key("mfl", league_id)) if league_id else None
    if isinstance(saved, dict) and saved.get("apikey"):
        query["APIKEY"] = saved["apikey"]
    try:
        data = ctx.fetch(MFL_API % ctx.season + "?" + urlencode(query))
    except FetchError as error:
        if error.status in (401, 403):
            raise LeagueError("This MFL league is private. Add its API key with the gear (beta).") from None
        raise
    if not isinstance(data, dict):
        raise LeagueError("MyFantasyLeague did not answer")
    problem = data.get("error")
    if problem:
        message = problem.get("$t") if isinstance(problem, dict) else problem
        raise LeagueError(text(message, 120) or "MyFantasyLeague refused the request")
    return data


def collect_mfl(entry, ctx):
    data = (mfl_fetch(ctx, entry["id"], "league").get("league")) or {}
    franchises = {str(f.get("id")): text(f.get("name"), 48) for f in as_list((data.get("franchises") or {}).get("franchise"))}
    if entry["team"] not in franchises:
        raise LeagueError("That team is no longer in this league")
    standings = mfl_fetch(ctx, entry["id"], "leagueStandings").get("leagueStandings") or {}
    table, records = [], {}
    for row in as_list(standings.get("franchise")):
        w, l, t = (integer(row.get(k)) or 0 for k in ("h2hw", "h2hl", "h2ht"))
        table.append((str(row.get("id")), w, l, t, number(row.get("pf")) or 0))
        records[str(row.get("id"))] = record_text(w, l, t)
    league = league_base(entry)
    league.update({
        "league": text(data.get("name"), 60),
        "url": "https://www.myfantasyleague.com/%d/home/%s" % (ctx.season, entry["id"]),
        "teams": len(franchises),
        "rank": rank_of(entry["team"], table),
    })
    live = mfl_fetch(ctx, entry["id"], "liveScoring", DETAILS=1).get("liveScoring") or {}
    week = integer(live.get("week"))
    pair = None
    for matchup in as_list(live.get("matchup")):
        sides = as_list(matchup.get("franchise"))
        if any(str(s.get("id")) == entry["team"] for s in sides):
            pair = sides
    if pair is None:
        alone = [s for s in as_list(live.get("franchise")) if str(s.get("id")) == entry["team"]]
        pair = alone or None
    if not pair or not week:
        league["note"] = "No matchup this week"
        league["me"] = side(franchises[entry["team"]], None, {}, records.get(entry["team"], ""))
        return league
    league["week"] = week
    mine = next(s for s in pair if str(s.get("id")) == entry["team"])
    opp = next((s for s in pair if s is not mine), None)
    ids = []
    for part in (mine, opp):
        for player in as_list(((part or {}).get("players") or {}).get("player")):
            if player.get("status") == "starter":
                ids.append(str(player.get("id")))
    info, injuries, projections = {}, {}, {}
    if ids:
        listed = mfl_fetch(ctx, "", "players", PLAYERS=",".join(ids)).get("players") or {}
        for row in as_list(listed.get("player")):
            info[str(row.get("id"))] = row
        for row in as_list((mfl_fetch(ctx, "", "injuries", W=week).get("injuries") or {}).get("injury")):
            injuries[str(row.get("id"))] = row.get("status")
        try:
            scored = mfl_fetch(ctx, entry["id"], "projectedScores", W=week, PLAYERS=",".join(ids)).get("projectedScores") or {}
            for row in as_list(scored.get("playerScore")):
                projections[str(row.get("id"))] = number(row.get("score"))
        except Exception:  # noqa: BLE001 - the score stands without a projection
            projections = {}

    def lineup(part, with_injuries):
        starters, projected, have = [], 0.0, False
        for player in as_list(((part or {}).get("players") or {}).get("player")):
            if player.get("status") != "starter":
                continue
            pid = str(player.get("id"))
            row = info.get(pid) or {}
            position = str(row.get("position") or "")
            name = flip_name(row.get("name"))
            team = team_code(row.get("team"))
            actual = number(player.get("score")) or 0.0
            remaining = number(player.get("gameSecondsRemaining"))
            guess = projections.get(pid)
            if guess is not None:
                have = True
                share = 1.0 if remaining is None else max(0.0, min(1.0, remaining / 3600.0))
                projected += actual + guess * share
            else:
                projected += actual
            starters.append(starter(name, "DEF" if position.upper() == "DEF" else position, team,
                                    injuries.get(pid) if with_injuries else None, actual))
        return starters, (round(projected, 2) if have else None)

    required = integer((data.get("starters") or {}).get("count")) or 0
    my_lineup, my_projection = lineup(mine, True)
    counted = tally(my_lineup, max(0, required - len(my_lineup)) if required else 0, ctx.schedule, week, ctx.now_ms)
    league["me"] = side(franchises[entry["team"]], mine.get("score"), counted, records.get(entry["team"], ""),
                        my_projection, None, integer(mine.get("playersYetToPlay")), integer(mine.get("playersCurrentlyPlaying")))
    if opp:
        opp_lineup, opp_projection = lineup(opp, False)
        league["opp"] = side(franchises.get(str(opp.get("id")), ""), opp.get("score"),
                             tally(opp_lineup, 0, ctx.schedule, week, ctx.now_ms), records.get(str(opp.get("id")), ""),
                             opp_projection, None, integer(opp.get("playersYetToPlay")), integer(opp.get("playersCurrentlyPlaying")))
    else:
        league["note"] = "No head-to-head this week"
    return finish(league, counted)


def find_mfl(spec, ctx):
    data = (mfl_fetch(ctx, spec["id"], "league").get("league")) or {}
    teams = []
    for row in as_list((data.get("franchises") or {}).get("franchise")):
        teams.append({"id": str(row.get("id")), "name": text(row.get("name"), 48), "owner": text(row.get("owner_name"), 40)})
    if not teams:
        raise LeagueError("MyFantasyLeague has no league %s for %d" % (spec["id"], ctx.season))
    return [{"p": "mfl", "id": spec["id"], "name": text(data.get("name"), 60), "season": str(ctx.season), "teams": teams}]


# —— Fantrax ——


def fantrax_fetch(ctx, method, **params):
    data = ctx.fetch(FANTRAX_API + method + "?" + urlencode(params))
    # Fantrax reports a bad league id as a 200 with an error object.
    if isinstance(data, dict) and data.get("error"):
        problem = data["error"]
        message = problem.get("message") if isinstance(problem, dict) else problem
        if "not found" in str(message).lower():
            raise LeagueError("Fantrax has no league %s" % params.get("leagueId", ""))
        raise LeagueError(text(message, 120) or "Fantrax refused the request")
    return data


def fantrax_period(periods, now_ms):
    """The scoring period in play: the current one, else the next, else the last."""
    rows = []
    for row in periods if isinstance(periods, list) else []:
        if isinstance(row, dict) and integer(row.get("number")):
            rows.append((integer(row["number"]), parse_time_ms(row.get("startDate")), parse_time_ms(row.get("endDate"))))
    rows.sort()
    for number_, start, end in rows:
        if end is not None and now_ms <= end:
            return number_, (start is not None and start <= now_ms)
    return (rows[-1][0], False) if rows else (None, False)


def collect_fantrax(entry, ctx):
    info = fantrax_fetch(ctx, "getLeagueInfo", leagueId=entry["id"], excludePlayerInfo="true")
    if not isinstance(info, dict):
        raise LeagueError("Fantrax did not answer")
    names = {}
    for tid, team in (info.get("teamInfo") or {}).items():
        if isinstance(team, dict):
            names[str(team.get("id") or tid)] = text(team.get("name"), 48)
    if entry["team"] not in names:
        raise LeagueError("That team is no longer in this league")
    table, records = [], {}
    rows = fantrax_fetch(ctx, "getStandings", leagueId=entry["id"])
    for row in rows if isinstance(rows, list) else []:
        if not isinstance(row, dict):
            continue
        parts = [integer(x) or 0 for x in str(row.get("points") or "0-0-0").split("-")] + [0, 0, 0]
        table.append((str(row.get("teamId")), parts[0], parts[1], parts[2], number(row.get("totalPointsFor")) or 0))
        records[str(row.get("teamId"))] = record_text(parts[0], parts[1], parts[2])
    league = league_base(entry)
    league.update({
        "league": text(info.get("leagueName"), 60),
        "url": "https://www.fantrax.com/fantasy/league/%s/home" % entry["id"],
        "teams": len(names),
        "rank": rank_of(entry["team"], table),
        "note": "Fantrax shares schedules, not scores",
    })
    period, _ = fantrax_period(info.get("scoringPeriods"), ctx.now_ms)
    end = parse_time_ms(info.get("endDate"))
    if end is not None and ctx.now_ms > end + DAY_MS:
        league["note"] = "Season over"
        league["me"] = side(names[entry["team"]], None, {}, records.get(entry["team"], ""))
        return league
    league["week"] = period
    opp_id = None
    for block in info.get("matchups") or []:
        if not isinstance(block, dict) or integer(block.get("period")) != period:
            continue
        for pair in block.get("matchupList") or []:
            home, away = str((pair.get("home") or {}).get("id")), str((pair.get("away") or {}).get("id"))
            if entry["team"] in (home, away):
                opp_id = away if home == entry["team"] else home
    league["me"] = side(names[entry["team"]], None, {}, records.get(entry["team"], ""))
    if opp_id:
        league["opp"] = side(names.get(opp_id, ""), None, {}, records.get(opp_id, ""))
    return finish(league)


def find_fantrax(spec, ctx):
    info = fantrax_fetch(ctx, "getLeagueInfo", leagueId=spec["id"], excludePlayerInfo="true")
    if not isinstance(info, dict):
        raise LeagueError("Fantrax did not answer")
    teams = [{"id": str(t.get("id") or tid), "name": text(t.get("name"), 48), "owner": ""}
             for tid, t in (info.get("teamInfo") or {}).items() if isinstance(t, dict)]
    return [{"p": "fantrax", "id": spec["id"], "name": text(info.get("leagueName"), 60),
             "season": text(info.get("seasonYear"), 6), "teams": teams}]


# —— Yahoo (beta) ——


def yahoo_flat(node):
    """Yahoo's JSON as plain objects and lists.

    Yahoo turns its XML into objects keyed "0", "1", ... with a "count", and
    splits one record into a list of one-key objects. Counted objects become
    lists; split records are merged back into one object."""
    if isinstance(node, list):
        merged = {}
        for item in node:
            item = yahoo_flat(item)
            if isinstance(item, dict):
                merged.update(item)
        return merged
    if isinstance(node, dict):
        keys = list(node.keys())
        if "count" in node and all(k == "count" or k.isdigit() for k in keys):
            return [yahoo_flat(node[k]) for k in sorted((k for k in keys if k.isdigit()), key=int)]
        return {k: yahoo_flat(v) for k, v in node.items()}
    return node


def yahoo_items(node, key):
    """Each `{key: value}` of a Yahoo list, as the values."""
    if isinstance(node, dict) and "0" in node:
        node = node.get("0")
    if isinstance(node, dict):
        node = [node]
    return [item[key] for item in node if isinstance(item, dict) and isinstance(item.get(key), dict)] if isinstance(node, list) else []


def yahoo_basic(saved):
    raw = "%s:%s" % (saved.get("client_id", ""), saved.get("client_secret", ""))
    return "Basic " + base64.b64encode(raw.encode("utf-8")).decode("ascii")


def yahoo_token_request(ctx, saved, form):
    reply = ctx.fetch(YAHOO_TOKEN, headers={"Authorization": yahoo_basic(saved),
                                            "Content-Type": "application/x-www-form-urlencoded"},
                      data=urlencode(form))
    if not isinstance(reply, dict) or not reply.get("access_token"):
        raise LeagueError("Yahoo did not sign in")
    expires = number(reply.get("expires_in")) or 3600
    return dict(saved, access_token=str(reply["access_token"]),
                refresh_token=str(reply.get("refresh_token") or saved.get("refresh_token") or ""),
                expires_at=int(ctx.now_ms + expires * 1000))


def yahoo_token(ctx):
    def make():
        saved = ctx.auth.get("yahoo")
        if not isinstance(saved, dict) or not saved.get("refresh_token"):
            raise LeagueError("Sign in to Yahoo with the gear (beta)")
        if (number(saved.get("expires_at")) or 0) - 120000 > ctx.now_ms and saved.get("access_token"):
            return saved["access_token"]
        try:
            fresh = yahoo_token_request(ctx, saved, {"grant_type": "refresh_token", "redirect_uri": "oob",
                                                     "refresh_token": saved["refresh_token"]})
        except FetchError:
            raise LeagueError("The Yahoo sign-in ran out. Sign in again with the gear (beta).") from None
        # These tokens are the tile's own, so the rotated refresh token is kept.
        save_auth("yahoo", fresh)
        ctx.auth["yahoo"] = fresh
        return fresh["access_token"]

    return ctx.once("yahoo:token", make)


def yahoo_get(ctx, path):
    token = yahoo_token(ctx)
    try:
        data = ctx.fetch(YAHOO_API + path + ("&" if "?" in path else "?") + "format=json",
                         headers={"Authorization": "Bearer " + token})
    except FetchError as error:
        if error.status == 401:
            raise LeagueError("The Yahoo sign-in ran out. Sign in again with the gear (beta).") from None
        raise
    content = yahoo_flat(data).get("fantasy_content") if isinstance(data, dict) else None
    if not isinstance(content, dict):
        raise LeagueError("Yahoo did not answer")
    return content


def yahoo_lineup(ctx, team_key, week):
    team = yahoo_get(ctx, "/team/%s/roster;week=%d/players" % (team_key, week)).get("team") or {}
    roster = team.get("roster") if isinstance(team.get("roster"), dict) else {}
    starters = []
    for player in yahoo_items((roster.get("0") or {}).get("players") if isinstance(roster.get("0"), dict) else None, "player"):
        slot = str((player.get("selected_position") or {}).get("position") or "")
        if slot in YAHOO_RESERVE_SLOTS:
            continue
        name = (player.get("name") or {}).get("full") if isinstance(player.get("name"), dict) else player.get("name")
        position = player.get("display_position") or slot
        if str(position).upper() in DEFENSE_POSITIONS:
            position = "DEF"
        starters.append(starter(name, position, player.get("editorial_team_abbr"), player.get("status")))
    return starters


def collect_yahoo(entry, ctx):
    league_key = entry["id"]
    team_key = "%s.t.%s" % (league_key, entry["team"])
    data = yahoo_get(ctx, "/league/%s/scoreboard" % league_key).get("league") or {}
    league = league_base(entry)
    league.update({
        "league": text(data.get("name"), 60),
        "url": text(data.get("url"), 200) if str(data.get("url") or "").startswith("https://football.fantasysports.yahoo.com/") else "",
        "teams": integer(data.get("num_teams")),
    })
    week = integer(data.get("current_week")) or integer((data.get("scoreboard") or {}).get("week"))
    standings = yahoo_get(ctx, "/league/%s/standings" % league_key).get("league") or {}
    table, records, names = [], {}, {}
    for team in yahoo_items((standings.get("standings") or {}).get("teams"), "team"):
        totals = ((team.get("team_standings") or {}).get("outcome_totals") or {})
        w, l, t = (integer(totals.get(k)) or 0 for k in ("wins", "losses", "ties"))
        key = str(team.get("team_key"))
        table.append((key, w, l, t, number((team.get("team_points") or {}).get("total")) or 0))
        records[key] = record_text(w, l, t)
        names[key] = text(team.get("name"), 48)
    league["rank"] = rank_of(team_key, table) if table else None
    matchup = None
    for row in yahoo_items((data.get("scoreboard") or {}).get("0", {}).get("matchups") if isinstance((data.get("scoreboard") or {}).get("0"), dict) else None, "matchup"):
        teams = yahoo_items((row.get("0") or {}).get("teams") if isinstance(row.get("0"), dict) else row.get("teams"), "team")
        if any(str(t.get("team_key")) == team_key for t in teams):
            matchup = teams
    if not matchup or not week:
        league["note"] = "No matchup this week"
        league["me"] = side(names.get(team_key, ""), None, {}, records.get(team_key, ""))
        return league
    league["week"] = week
    mine = next(t for t in matchup if str(t.get("team_key")) == team_key)
    opp = next((t for t in matchup if t is not mine), None)

    def total(team, key):
        value = team.get(key)
        return value.get("total") if isinstance(value, dict) else None

    lineup = yahoo_lineup(ctx, team_key, week)
    counted = tally(lineup, 0, ctx.schedule, week, ctx.now_ms)
    league["me"] = side(mine.get("name"), total(mine, "team_points"), counted, records.get(team_key, ""),
                        total(mine, "team_projected_points"), mine.get("win_probability"))
    if opp:
        opp_key = str(opp.get("team_key"))
        try:
            opp_lineup = yahoo_lineup(ctx, opp_key, week)
        except Exception:  # noqa: BLE001 - the score stands without their lineup
            opp_lineup = []
        league["opp"] = side(opp.get("name"), total(opp, "team_points"), tally(opp_lineup, 0, ctx.schedule, week, ctx.now_ms),
                             records.get(opp_key, ""), total(opp, "team_projected_points"), opp.get("win_probability"))
    return finish(league, counted)


def find_yahoo(ctx):
    games = (yahoo_get(ctx, "/users;use_login=1/games;game_keys=nfl/leagues").get("users") or [])
    user = games[0].get("user") if games and isinstance(games[0], dict) else {}
    game = (yahoo_items((user or {}).get("games"), "game") or [{}])[0]
    leagues = yahoo_items(game.get("leagues"), "league")
    if not leagues:
        raise LeagueError("This Yahoo account has no football leagues this season")
    owned = yahoo_get(ctx, "/users;use_login=1/games;game_keys=nfl/teams").get("users") or []
    owner = owned[0].get("user") if owned and isinstance(owned[0], dict) else {}
    teams = yahoo_items((yahoo_items((owner or {}).get("games"), "game") or [{}])[0].get("teams"), "team")
    found = []
    for row in leagues:
        key = str(row.get("league_key") or "")
        if not re.fullmatch(ID_PATTERNS["yahoo"][0], key):
            continue
        team = next((t for t in teams if str(t.get("team_key", "")).startswith(key + ".t.")), None)
        if not team:
            continue
        found.append({"p": "yahoo", "id": key, "name": text(row.get("name"), 60), "season": text(row.get("season"), 6),
                      "team": str(team.get("team_id")), "teamName": text(team.get("name"), 48), "teams": []})
    return found


def yahoo_signin(form, ctx):
    client_id = text(form.get("client_id"), 200)
    secret = text(form.get("client_secret"), 200)
    code = text(form.get("code"), 100)
    if not client_id or not secret or " " in client_id or " " in secret:
        raise LeagueError("Paste the app's client ID and client secret from developer.yahoo.com")
    if not re.fullmatch(r"[A-Za-z0-9_.~-]{4,100}", code):
        raise LeagueError("Paste the code Yahoo showed after you signed in")
    saved = {"client_id": client_id, "client_secret": secret}
    try:
        fresh = yahoo_token_request(ctx, saved, {"grant_type": "authorization_code", "redirect_uri": "oob", "code": code})
    except FetchError:
        raise LeagueError("Yahoo refused that code. Open the sign-in page again for a new one.") from None
    save_auth("yahoo", fresh)
    ctx.auth["yahoo"] = fresh
    return find_yahoo(ctx)


# —— Entry points ——


COLLECTORS = {
    "sleeper": collect_sleeper,
    "espn": collect_espn,
    "fleaflicker": collect_fleaflicker,
    "mfl": collect_mfl,
    "fantrax": collect_fantrax,
    "yahoo": collect_yahoo,
}


def collect_one(entry, ctx):
    name = PLATFORMS[entry["p"]][0]
    try:
        return COLLECTORS[entry["p"]](entry, ctx)
    except LeagueError as error:
        return failed(entry, str(error))
    except FetchError as error:
        return failed(entry, "%s answered %s" % (name, error.status) if error.status else "%s sent a reply the tile can't read" % name)
    except Exception:  # noqa: BLE001 - one league failing leaves the others up
        return failed(entry, "%s did not answer" % name)


def collect(request, now_ms, fetch, auth=None):
    """The tile payload for the --leagues argument."""
    entries = parse_entries(request)
    base = {"ok": True, "request": request if isinstance(request, str) else json.dumps(request), "leagues": []}
    if not entries:
        return dict(base, week=None, live=False, pollMs=POLL_IDLE_MS)
    ctx = Context(fetch, now_ms, auth)
    ctx.schedule = load_schedule(ctx.season, fetch, now_ms)
    with ThreadPoolExecutor(max_workers=len(entries)) as pool:
        leagues = list(pool.map(lambda entry: collect_one(entry, ctx), entries))
    weeks = [league["week"] for league in leagues if league.get("week")]
    return dict(base, leagues=leagues, week=weeks[0] if weeks else ctx.week(),
                live=any(league.get("live") for league in leagues),
                pollMs=poll_ms(ctx.schedule, leagues, now_ms))


def clean_spec(raw):
    """What the settings panel asks to look up, checked like a stored entry."""
    if not isinstance(raw, dict):
        return None
    platform = str(raw.get("p") or "")
    if platform == "yahoo":
        return {"p": "yahoo"}
    if platform == "sleeper" and raw.get("user"):
        user = text(raw.get("user"), 40)
        return {"p": "sleeper", "user": user} if SLEEPER_USER.fullmatch(user) else None
    if platform not in ID_PATTERNS:
        return None
    league = text(raw.get("id"), 40)
    league = league.lower() if platform == "fantrax" else league
    if not re.fullmatch(ID_PATTERNS[platform][0], league):
        return None
    spec = {"p": platform, "id": league}
    season = integer(raw.get("season"))
    if season and 2000 <= season <= 2100:
        spec["season"] = season
    return spec


def clean_secret(platform, form):
    """The fields a platform's sign-in needs, or {} for none."""
    if not isinstance(form, dict):
        return {}
    if platform == "espn":
        s2 = re.sub(r"\s+", "", str(form.get("espn_s2") or ""))
        swid = re.sub(r"\s+", "", str(form.get("swid") or ""))
        if not s2 and not swid:
            return {}
        if not re.fullmatch(r"[A-Za-z0-9%+/=_.-]{20,2000}", s2) or not re.fullmatch(r"\{?[A-Fa-f0-9-]{36}\}?", swid):
            raise LeagueError("Those don't look like ESPN's espn_s2 and SWID cookies")
        if not swid.startswith("{"):
            swid = "{" + swid + "}"
        return {"espn_s2": s2, "swid": swid.upper()}
    if platform == "mfl":
        key = re.sub(r"\s+", "", str(form.get("apikey") or ""))
        if not key:
            return {}
        if not re.fullmatch(r"[A-Za-z0-9+/=_-]{8,200}", key):
            raise LeagueError("That doesn't look like an MFL API key")
        return {"apikey": key}
    return {}


def find(raw, now_ms, fetch, form=None, auth=None):
    """Leagues and teams for the settings panel. A sign-in that works is saved."""
    spec = clean_spec(raw)
    if not spec:
        return {"ok": False, "error": "That isn't a league link or ID this platform uses", "leagues": []}
    ctx = Context(fetch, now_ms, auth)
    if spec.get("season"):
        ctx.season = spec["season"]
    try:
        secret = clean_secret(spec["p"], form)
        if secret:
            ctx.auth[auth_key(spec["p"], spec["id"])] = secret
        finder = {
            "sleeper": find_sleeper,
            "espn": find_espn,
            "fleaflicker": find_fleaflicker,
            "mfl": find_mfl,
            "fantrax": find_fantrax,
        }.get(spec["p"])
        leagues = find_yahoo(ctx) if spec["p"] == "yahoo" else finder(spec, ctx)
        if secret:
            save_auth(auth_key(spec["p"], spec["id"]), secret)
    except LeagueError as error:
        return {"ok": False, "error": str(error), "leagues": []}
    except FetchError as error:
        name = PLATFORMS[spec["p"]][0]
        if error.status == 404:
            return {"ok": False, "error": "%s has no league with that ID" % name, "leagues": []}
        return {"ok": False, "error": "%s answered %s" % (name, error.status or "with something unreadable"), "leagues": []}
    except Exception:  # noqa: BLE001
        return {"ok": False, "error": "%s did not answer" % PLATFORMS[spec["p"]][0], "leagues": []}
    if not leagues:
        return {"ok": False, "error": "No leagues found", "leagues": []}
    return {"ok": True, "error": "", "leagues": leagues}


def signin(now_ms, fetch, form, auth=None):
    ctx = Context(fetch, now_ms, auth)
    try:
        leagues = yahoo_signin(form if isinstance(form, dict) else {}, ctx)
    except LeagueError as error:
        return {"ok": False, "error": str(error), "leagues": []}
    except Exception:  # noqa: BLE001
        return {"ok": False, "error": "Yahoo did not answer", "leagues": []}
    return {"ok": True, "error": "", "leagues": leagues}


def forget(key):
    value = text(key, 60)
    if value != "yahoo" and not re.fullmatch(r"(espn|mfl):\d{1,12}", value):
        return {"ok": False}
    return {"ok": save_auth(value, None)}


def option(args, name):
    if name not in args:
        return None
    index = args.index(name)
    return args[index + 1] if index + 1 < len(args) else ""


def env_form():
    try:
        form = json.loads(os.environ.get(AUTH_ENV) or "{}")
    except ValueError:
        return {}
    return form if isinstance(form, dict) else {}


def emit(payload):
    json.dump(payload, sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")


def main(argv):
    args = argv[1:]
    now_ms = int(time.time() * 1000)
    if "--forget" in args:
        emit(forget(option(args, "--forget")))
        return 0
    if "--yahoo-signin" in args:
        emit(signin(now_ms, fetch_json, env_form()))
        return 0
    spec = option(args, "--find")
    if spec is not None:
        try:
            raw = json.loads(spec)
        except ValueError:
            raw = None
        emit(find(raw, now_ms, fetch_json, env_form()))
        return 0
    payload = collect(option(args, "--leagues") or "[]", now_ms, fetch_json)
    write_cache(payload, now_ms=now_ms)
    emit(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
