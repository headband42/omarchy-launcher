#!/usr/bin/env python3
"""Scores from ESPN's public feeds for the leagues the NFL and MLB tiles leave
out. Stdlib only.

    scores.py --league nba [--team ID]   the tile: the slate, and one team's game
    scores.py --teams nba                 the settings panel: that league's teams
    scores.py --leagues                   the settings panel: the leagues

ESPN answers curl and refuses Python's own TLS client with a 403 (the NFL tile
found this first), so every request goes through curl. A team's game is its
live game, else a final from the last twelve hours, else its next game, else
its last one. Soccer schedules list results unless asked for fixtures, so both
are read. A score arrives as a string on the scoreboard and as an object in a
team schedule; both are read the same. Team logos are fetched once, 64 px,
into the cache, with ESPN's dark-background mark when the team has one.
"""

import json
import os
import re
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime

CURL = "/usr/bin/curl"
SITE = "https://site.api.espn.com/apis/site/v2/sports/"
COMBINER = "https://a.espncdn.com/combiner/i?img=%s&h=64&w=64"
MAX_BYTES = 8_000_000
TEAMS_TTL = 86400
SCHEDULE_TTL = 600
LOGO_BATCH = 48
RECENT_FINAL = 12 * 3600
LIVE_POLL_MS = 30000
IDLE_POLL_MS = 300000

# id: (name, ESPN sport/league path, soccer?)
LEAGUES = {
    "nba": ("NBA", "basketball/nba", False),
    "wnba": ("WNBA", "basketball/wnba", False),
    "nhl": ("NHL", "hockey/nhl", False),
    "mls": ("MLS", "soccer/usa.1", True),
    "nwsl": ("NWSL", "soccer/usa.nwsl", True),
    "epl": ("Premier League", "soccer/eng.1", True),
    "laliga": ("LaLiga", "soccer/esp.1", True),
    "bundesliga": ("Bundesliga", "soccer/ger.1", True),
    "seriea": ("Serie A", "soccer/ita.1", True),
    "ligue1": ("Ligue 1", "soccer/fra.1", True),
    "ligamx": ("Liga MX", "soccer/mex.1", True),
    "ucl": ("Champions League", "soccer/uefa.champions", True),
    "cfb": ("College Football", "football/college-football", False),
    "mcbb": ("Men's College Basketball", "basketball/mens-college-basketball", False),
    "wcbb": ("Women's College Basketball", "basketball/womens-college-basketball", False),
}
DEFAULT_LEAGUE = "nba"

ALLOWED = re.compile(r"https://(site\.api\.espn\.com/apis/site/v2/sports/|a\.espncdn\.com/)[A-Za-z0-9_./?=&%:-]+")
TEAM_ID = re.compile(r"\d{1,8}")


def text(value, limit=80):
    return " ".join(str(value or "").split())[:limit]


def curl(url, timeout=12, binary=False):
    if not ALLOWED.fullmatch(url):
        raise ValueError("Refusing an unexpected request")
    result = subprocess.run(
        [CURL, "--silent", "--show-error", "--location", "--fail", "--compressed",
         "--max-filesize", str(MAX_BYTES), "--max-time", str(int(timeout)), url],
        capture_output=True, timeout=timeout + 5, check=False)
    if result.returncode != 0:
        raise OSError(text(result.stderr.decode("utf-8", "replace"), 200) or "curl could not read the feed")
    return result.stdout if binary else result.stdout.decode("utf-8", "replace")


def fetch_json(url, fetcher=None):
    body = (fetcher or curl)(url)
    payload = json.loads(body)
    if not isinstance(payload, dict):
        raise ValueError("Feed did not return an object")
    return payload


def epoch(value):
    raw = str(value or "")
    try:
        return int(datetime.fromisoformat(raw.replace("Z", "+00:00")).timestamp())
    except ValueError:
        return None


# —— Cache ——


def cache_dir():
    root = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return os.path.join(root, "ande.launcher", "scores")


def read_cached(name, ttl, now, folder=None):
    path = os.path.join(folder or cache_dir(), name)
    try:
        if not 0 <= now - os.path.getmtime(path) < ttl:
            return None
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def write_cached(name, data, folder=None):
    folder = folder or cache_dir()
    try:
        os.makedirs(folder, exist_ok=True)
        tmp = os.path.join(folder, name + ".tmp")
        with open(tmp, "w", encoding="utf-8") as handle:
            json.dump(data, handle)
        os.replace(tmp, os.path.join(folder, name))
    except OSError:
        pass


# —— Teams and logos ——


def logo_path(url):
    """The path part of an ESPN logo URL, for the resizing combiner."""
    match = re.match(r"https://a\.espncdn\.com(/i/teamlogos/[A-Za-z0-9_./-]+\.png)$", str(url or ""))
    return match.group(1) if match else ""


def parse_teams(payload):
    teams = {}
    try:
        rows = payload["sports"][0]["leagues"][0]["teams"]
    except (KeyError, IndexError, TypeError):
        return teams
    for row in rows:
        team = (row or {}).get("team") or {}
        team_id = str(team.get("id") or "")
        if not TEAM_ID.fullmatch(team_id):
            continue
        light = dark = ""
        for logo in team.get("logos") or []:
            rel = logo.get("rel") or []
            if "dark" in rel and not dark:
                dark = logo_path(logo.get("href"))
            elif "default" in rel and not light:
                light = logo_path(logo.get("href"))
        teams[team_id] = {
            "id": team_id,
            "abbr": text(team.get("abbreviation"), 8),
            "name": text(team.get("displayName"), 60),
            "short": text(team.get("shortDisplayName") or team.get("name"), 30),
            "color": text(team.get("color"), 6) if re.fullmatch(r"[0-9a-fA-F]{6}", str(team.get("color") or "")) else "",
            "logo": light,
            "logoDark": dark,
        }
    return teams


def load_teams(league, now, fetcher=None, folder=None):
    name = "%s-teams.json" % league
    cached = read_cached(name, TEAMS_TTL, now, folder)
    if isinstance(cached, dict) and cached:
        return cached
    _, path, _ = LEAGUES[league]
    teams = parse_teams(fetch_json(SITE + path + "/teams?limit=1000", fetcher))
    if teams:
        write_cached(name, teams, folder)
    return teams


def logo_file(league, team_id, dark, folder=None):
    return os.path.join(folder or cache_dir(), "logos", league, "%s%s.png" % (team_id, "-dark" if dark else ""))


def ensure_logos(league, team_ids, teams, fetcher=None, folder=None):
    """Fetch the logos not cached yet; return {team id: {logo, logoDark}} for those on disk."""
    wanted = []
    for team_id in team_ids:
        team = teams.get(team_id) or {}
        for dark, source in ((False, team.get("logo")), (True, team.get("logoDark"))):
            if source and not os.path.exists(logo_file(league, team_id, dark, folder)):
                wanted.append((team_id, dark, source))
    get = fetcher or (lambda url: curl(url, timeout=8, binary=True))

    def download(item):
        team_id, dark, source = item
        try:
            body = get(COMBINER % source)
        except (OSError, ValueError, subprocess.SubprocessError):
            return
        if not isinstance(body, bytes) or not body.startswith(b"\x89PNG"):
            return
        path = logo_file(league, team_id, dark, folder)
        try:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path + ".tmp", "wb") as handle:
                handle.write(body)
            os.replace(path + ".tmp", path)
        except OSError:
            pass

    if wanted:
        with ThreadPoolExecutor(max_workers=8) as pool:
            list(pool.map(download, wanted[:LOGO_BATCH]))
    out = {}
    for team_id in team_ids:
        light = logo_file(league, team_id, False, folder)
        dark = logo_file(league, team_id, True, folder)
        out[team_id] = {"logo": light if os.path.exists(light) else "", "logoDark": dark if os.path.exists(dark) else ""}
    return out


# —— Games ——


def score_of(value):
    if isinstance(value, dict):
        value = value.get("displayValue")
    value = text(value, 6)
    return value if value != "" else None


def side(competitor, teams):
    team = competitor.get("team") or {}
    team_id = str(team.get("id") or "")
    known = teams.get(team_id) or {}
    records = competitor.get("records") or competitor.get("record") or []
    record = ""
    if isinstance(records, list) and records and isinstance(records[0], dict):
        record = text(records[0].get("summary") or records[0].get("displayValue"), 12)
    winner = competitor.get("winner")
    return {
        "id": team_id,
        "abbr": text(team.get("abbreviation") or known.get("abbr"), 8),
        "name": text(team.get("shortDisplayName") or known.get("short") or team.get("displayName"), 30),
        "score": score_of(competitor.get("score")),
        "winner": winner if isinstance(winner, bool) else None,
        "record": record,
        "logo": "",
        "logoDark": "",
    }


def game_link(event):
    for link in event.get("links") or []:
        rel = link.get("rel") or []
        href = str(link.get("href") or "")
        if "summary" in rel and re.fullmatch(r"https://www\.espn\.com/[A-Za-z0-9_./?=&%-]+", href):
            return href
    return ""


def parse_game(event, teams):
    """One event in the tile's shape, or None."""
    if not isinstance(event, dict):
        return None
    competitions = event.get("competitions") or []
    if not competitions:
        return None
    comp = competitions[0]
    status = comp.get("status") or event.get("status") or {}
    kind = status.get("type") or {}
    state = str(kind.get("state") or "")
    if state not in ("pre", "in", "post"):
        return None
    sides = {c.get("homeAway"): side(c, teams) for c in comp.get("competitors") or [] if isinstance(c, dict)}
    if "home" not in sides or "away" not in sides:
        return None
    if state == "pre":
        sides["home"]["score"] = sides["away"]["score"] = None
    networks = []
    for broadcast in comp.get("broadcasts") or []:
        names = broadcast.get("names") or ([broadcast.get("media", {}).get("shortName")] if isinstance(broadcast.get("media"), dict) else [])
        for name in names or []:
            if name and text(name, 20) not in networks:
                networks.append(text(name, 20))
    detail = text(kind.get("shortDetail") or kind.get("detail") or kind.get("description"), 30)
    return {
        "id": text(event.get("id"), 20),
        "start": epoch(event.get("date") or comp.get("date")),
        "state": state,
        "detail": detail,
        "tbd": "TBD" in detail.upper() or bool(comp.get("timeValid") is False),
        "completed": bool(kind.get("completed")),
        "away": sides["away"],
        "home": sides["home"],
        "network": networks[0] if networks else "",
        "link": game_link(event),
    }


def featured_game(games, now):
    """Live, else a recent final, else the next game, else the last one."""
    games = [g for g in games if g and g.get("start")]
    live = [g for g in games if g["state"] == "in"]
    if live:
        return live[0]
    finals = sorted((g for g in games if g["state"] == "post"), key=lambda g: g["start"])
    upcoming = sorted((g for g in games if g["state"] == "pre"), key=lambda g: g["start"])
    if finals and now - finals[-1]["start"] < RECENT_FINAL + 4 * 3600:
        return finals[-1]
    if upcoming:
        return upcoming[0]
    return finals[-1] if finals else None


def team_games(league, team_id, now, fetcher=None, folder=None):
    name = "%s-%s-schedule.json" % (league, team_id)
    cached = read_cached(name, SCHEDULE_TTL, now, folder)
    if isinstance(cached, list):
        return cached
    _, path, soccer = LEAGUES[league]
    events = list(fetch_json(SITE + path + "/teams/%s/schedule" % team_id, fetcher).get("events") or [])
    if soccer:
        events += list(fetch_json(SITE + path + "/teams/%s/schedule?fixture=true" % team_id, fetcher).get("events") or [])
    write_cached(name, events, folder)
    return events


def collect(league, team_id="", now=None, fetcher=None, logo_fetcher=None, folder=None):
    now = time.time() if now is None else now
    league = league if league in LEAGUES else DEFAULT_LEAGUE
    team_id = str(team_id or "")
    team_id = team_id if TEAM_ID.fullmatch(team_id) else ""
    name, path, soccer = LEAGUES[league]
    out = {"ok": True, "error": "", "league": {"id": league, "name": name, "soccer": soccer},
           "team": None, "featured": None, "games": [], "live": 0, "pollMs": IDLE_POLL_MS, "day": ""}
    try:
        teams = load_teams(league, now, fetcher, folder)
    except (OSError, ValueError, subprocess.SubprocessError):
        teams = {}
    try:
        board = fetch_json(SITE + path + "/scoreboard", fetcher)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        out.update(ok=False, error="ESPN did not answer")
        return out
    games = [g for g in (parse_game(e, teams) for e in board.get("events") or []) if g]
    out["day"] = text((board.get("day") or {}).get("date"), 10)
    if team_id:
        info = teams.get(team_id) or {}
        out["team"] = {"id": team_id, "name": info.get("name") or "", "short": info.get("short") or "", "abbr": info.get("abbr") or ""}
        on_board = [g for g in games if team_id in (g["home"]["id"], g["away"]["id"])]
        try:
            schedule = [g for g in (parse_game(e, teams) for e in team_games(league, team_id, now, fetcher, folder)) if g]
        except (OSError, ValueError, subprocess.SubprocessError):
            schedule = []
        # The scoreboard's copy is live; the schedule's can be minutes old.
        by_id = {g["id"]: g for g in schedule}
        by_id.update({g["id"]: g for g in on_board})
        out["featured"] = featured_game(list(by_id.values()), now)
    featured_id = (out["featured"] or {}).get("id")
    games = [g for g in games if g["id"] != featured_id]
    games.sort(key=lambda g: ({"in": 0, "pre": 1, "post": 2}[g["state"]], g["start"] or 0))
    out["games"] = games[:40]
    out["live"] = sum(1 for g in games if g["state"] == "in") + (1 if (out["featured"] or {}).get("state") == "in" else 0)
    out["pollMs"] = LIVE_POLL_MS if out["live"] else IDLE_POLL_MS
    ids = set()
    for game in ([out["featured"]] if out["featured"] else []) + out["games"]:
        ids.update((game["home"]["id"], game["away"]["id"]))
    logos = ensure_logos(league, sorted(i for i in ids if i), teams, logo_fetcher, folder)
    for game in ([out["featured"]] if out["featured"] else []) + out["games"]:
        for part in ("home", "away"):
            found = logos.get(game[part]["id"]) or {}
            game[part]["logo"] = found.get("logo", "")
            game[part]["logoDark"] = found.get("logoDark", "")
    return out


def team_list(league, now=None, fetcher=None, folder=None):
    now = time.time() if now is None else now
    if league not in LEAGUES:
        return {"ok": False, "error": "Unknown league", "teams": []}
    try:
        teams = load_teams(league, now, fetcher, folder)
    except (OSError, ValueError, subprocess.SubprocessError):
        return {"ok": False, "error": "ESPN did not answer", "teams": []}
    rows = sorted(({"id": t["id"], "name": t["name"], "abbr": t["abbr"]} for t in teams.values()), key=lambda t: t["name"])
    return {"ok": True, "error": "", "teams": rows}


def league_list():
    return {"ok": True, "leagues": [{"id": key, "name": name} for key, (name, _, _) in LEAGUES.items()], "default": DEFAULT_LEAGUE}


def option(args, name):
    if name not in args:
        return None
    index = args.index(name)
    return args[index + 1] if index + 1 < len(args) else ""


def main(argv):
    args = argv[1:]
    if "--leagues" in args:
        payload = league_list()
    elif option(args, "--teams") is not None:
        payload = team_list(option(args, "--teams"))
    else:
        payload = collect(option(args, "--league") or DEFAULT_LEAGUE, option(args, "--team") or "")
    json.dump(payload, sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
