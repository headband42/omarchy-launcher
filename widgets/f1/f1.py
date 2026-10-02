#!/usr/bin/env python3
"""Formula 1 for the launcher tile. Stdlib only.

The season comes from Jolpica (api.jolpi.ca, the successor to the Ergast API):
the next round with every session's start, the last race's result, and both
championships. While a session is on, the running order comes from OpenF1
(api.openf1.org): the latest position of each car, with the three-letter codes
and team colors from that session's driver list. Jolpica's driver code and
OpenF1's acronym are the same, which is how standings get team colors.

Answers are cached: the season for half an hour (ten minutes on a race
weekend), and a session's driver list for as long as the session lasts.
Nothing here needs an account.
"""

import json
import os
import re
import sys
import time
from datetime import datetime, timezone
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

JOLPICA = "https://api.jolpi.ca/ergast/f1/"
OPENF1 = "https://api.openf1.org/v1/"
USER_AGENT = "omarchy-launcher-f1"
TIMEOUT = 12
MAX_BODY = 6_000_000
SEASON_TTL = 1800
WEEKEND_TTL = 600
LIVE_POLL_MS = 20000
IDLE_POLL_MS = 600000
# How long before a session starts and after it ends the tile treats it as live.
LEAD = 10 * 60
TAIL = 20 * 60
# Session lengths when the schedule gives only a start.
LENGTHS = {"FP1": 3600, "FP2": 3600, "FP3": 3600, "Sprint Qualifying": 2700, "Sprint": 3600, "Qualifying": 3600, "Race": 7200}

SESSIONS = (
    ("FirstPractice", "FP1"),
    ("SecondPractice", "FP2"),
    ("ThirdPractice", "FP3"),
    ("SprintQualifying", "Sprint Qualifying"),
    ("SprintShootout", "Sprint Qualifying"),
    ("Sprint", "Sprint"),
    ("Qualifying", "Qualifying"),
)


class F1Error(Exception):
    pass


def fetch(url, timeout=TIMEOUT):
    request = Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    try:
        with urlopen(request, timeout=timeout) as reply:
            return json.loads(reply.read(MAX_BODY))
    except HTTPError as error:
        if error.code == 404:
            return None
        raise F1Error("answered %d" % error.code)
    except (URLError, OSError, ValueError):
        raise F1Error("did not answer")


def text(value, limit=60):
    return " ".join(str(value or "").split())[:limit]


def stamp(day, clock):
    """Epoch seconds from Jolpica's separate date and time ("2026-10-04", "07:00:00Z")."""
    if not day:
        return None
    raw = "%sT%s" % (day, clock or "00:00:00Z")
    try:
        return int(datetime.fromisoformat(raw.replace("Z", "+00:00")).timestamp())
    except ValueError:
        return None


def iso(value):
    try:
        return int(datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp())
    except ValueError:
        return None


# —— Jolpica ——


def races_of(payload):
    try:
        return payload["MRData"]["RaceTable"]["Races"] or []
    except (KeyError, TypeError):
        return []


def weekend(race):
    """The next round: its name, place, and every session in order."""
    if not isinstance(race, dict):
        return None
    sessions = []
    for key, name in SESSIONS:
        part = race.get(key)
        if isinstance(part, dict):
            start = stamp(part.get("date"), part.get("time"))
            if start and not any(s["name"] == name for s in sessions):
                sessions.append({"name": name, "start": start, "end": start + LENGTHS.get(name, 3600)})
    start = stamp(race.get("date"), race.get("time"))
    if start:
        sessions.append({"name": "Race", "start": start, "end": start + LENGTHS["Race"]})
    sessions.sort(key=lambda s: s["start"])
    circuit = race.get("Circuit") or {}
    location = circuit.get("Location") or {}
    return {
        "round": text(race.get("round"), 4),
        "name": text(race.get("raceName")),
        "circuit": text(circuit.get("circuitName")),
        "locality": text(location.get("locality"), 40),
        "country": text(location.get("country"), 40),
        "start": start,
        "sessions": sessions,
        "url": text(race.get("url"), 300) if str(race.get("url") or "").startswith("https://") else "",
    }


def result_rows(race, limit=10):
    rows = []
    for row in (race or {}).get("Results") or []:
        driver = row.get("Driver") or {}
        rows.append({
            "pos": text(row.get("position"), 3),
            "code": text(driver.get("code") or driver.get("familyName", "")[:3].upper(), 4),
            "name": text(driver.get("familyName"), 30),
            "team": text((row.get("Constructor") or {}).get("name"), 30),
            "time": text((row.get("Time") or {}).get("time") or row.get("status"), 16),
            "points": text(row.get("points"), 5),
        })
        if len(rows) >= limit:
            break
    return rows


def standings(payload, kind, limit=10):
    try:
        lists = payload["MRData"]["StandingsTable"]["StandingsLists"]
        rows = lists[0][kind] if lists else []
    except (KeyError, TypeError, IndexError):
        return []
    out = []
    for row in rows[:limit]:
        if kind == "DriverStandings":
            driver = row.get("Driver") or {}
            teams = row.get("Constructors") or [{}]
            out.append({"pos": text(row.get("position"), 3), "code": text(driver.get("code"), 4),
                        "name": text(driver.get("familyName"), 30), "team": text(teams[-1].get("name"), 30),
                        "points": text(row.get("points"), 6), "wins": text(row.get("wins"), 3)})
        else:
            team = row.get("Constructor") or {}
            out.append({"pos": text(row.get("position"), 3), "name": text(team.get("name"), 30),
                        "points": text(row.get("points"), 6), "wins": text(row.get("wins"), 3)})
    return out


# —— OpenF1 ——


def live_order(positions, drivers):
    """The running order: each car's latest position, with its code and color."""
    latest = {}
    for row in positions if isinstance(positions, list) else []:
        if not isinstance(row, dict):
            continue
        number = row.get("driver_number")
        when = str(row.get("date") or "")
        if number is None or row.get("position") is None:
            continue
        if number not in latest or when >= latest[number][0]:
            latest[number] = (when, int(row["position"]))
    info = {d.get("driver_number"): d for d in drivers if isinstance(d, dict)} if isinstance(drivers, list) else {}
    order = []
    for number, (_, position) in latest.items():
        driver = info.get(number) or {}
        colour = str(driver.get("team_colour") or "")
        order.append({
            "pos": position,
            "code": text(driver.get("name_acronym") or number, 4),
            "team": text(driver.get("team_name"), 30),
            "colour": colour if re.fullmatch(r"[0-9A-Fa-f]{6}", colour) else "",
        })
    order.sort(key=lambda r: r["pos"])
    return order


def colours_by_code(drivers):
    out = {}
    for driver in drivers if isinstance(drivers, list) else []:
        code = str(driver.get("name_acronym") or "")
        colour = str(driver.get("team_colour") or "")
        if code and re.fullmatch(r"[0-9A-Fa-f]{6}", colour):
            out[code] = colour
    return out


def current_session(sessions, now):
    """The session on now, give or take its lead and tail, else None."""
    for session in sessions or []:
        if session["start"] - LEAD <= now <= session["end"] + TAIL:
            return session
    return None


# —— Cache ——


def cache_path(name, folder=None):
    root = folder or os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "ande.launcher", "f1")
    return os.path.join(root, name)


def cached(name, ttl, now, make, folder=None):
    """make()'s value, kept for `ttl` seconds. A failing make() falls back to
    the last value kept, however old, and raises only when there is none."""
    path = cache_path(name, folder)
    kept = None
    try:
        with open(path, encoding="utf-8") as handle:
            kept = json.load(handle)
    except (OSError, ValueError):
        kept = None
    if isinstance(kept, dict) and "value" in kept and 0 <= now - float(kept.get("at") or 0) < ttl:
        return kept["value"]
    try:
        value = make()
    except F1Error:
        if isinstance(kept, dict) and "value" in kept:
            return kept["value"]
        raise
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path + ".tmp", "w", encoding="utf-8") as handle:
            json.dump({"at": now, "value": value}, handle)
        os.replace(path + ".tmp", path)
    except OSError:
        pass
    return value


# —— The sample ——


def season(now, fetcher=fetch, folder=None, ttl=SEASON_TTL):
    def make():
        return {
            "next": fetcher(JOLPICA + "current/next.json"),
            "last": fetcher(JOLPICA + "current/last/results.json"),
            "drivers": fetcher(JOLPICA + "current/driverStandings.json"),
            "teams": fetcher(JOLPICA + "current/constructorStandings.json"),
        }
    return cached("season.json", ttl, now, make, folder)


def collect(now=None, fetcher=fetch, folder=None):
    now = time.time() if now is None else now
    out = {"ok": True, "error": "", "season": "", "next": None, "last": None, "drivers": [], "teams": [],
           "live": None, "pollMs": IDLE_POLL_MS}
    try:
        data = season(now, fetcher, folder)
        # On a race weekend, refresh more often so a result lands soon after it is in.
        upcoming = weekend((races_of(data.get("next")) or [None])[0])
        if upcoming and upcoming["sessions"] and upcoming["sessions"][0]["start"] - 86400 <= now:
            data = season(now, fetcher, folder, WEEKEND_TTL)
    except F1Error as error:
        out.update(ok=False, error="Jolpica %s" % error)
        return out
    next_races = races_of(data.get("next"))
    last_races = races_of(data.get("last"))
    out["next"] = weekend(next_races[0]) if next_races else None
    if last_races:
        out["last"] = {"round": text(last_races[0].get("round"), 4), "name": text(last_races[0].get("raceName")),
                       "date": stamp(last_races[0].get("date"), last_races[0].get("time")), "results": result_rows(last_races[0])}
    out["season"] = text((next_races or last_races or [{}])[0].get("season"), 4)
    out["drivers"] = standings(data.get("drivers"), "DriverStandings")
    out["teams"] = standings(data.get("teams"), "ConstructorStandings")

    session = current_session((out["next"] or {}).get("sessions"), now)
    colours = {}
    try:
        latest = cached("latest-session.json", 600 if not session else 60, now,
                        lambda: fetcher(OPENF1 + "sessions?session_key=latest"), folder)
        key = (latest or [{}])[0].get("session_key") if isinstance(latest, list) and latest else None
        if key is not None and re.fullmatch(r"\d{1,8}", str(key)):
            drivers = cached("drivers-%s.json" % key, 6 * 3600, now,
                             lambda: fetcher(OPENF1 + "drivers?session_key=%s" % key) or [], folder)
            colours = colours_by_code(drivers)
            if session:
                start, end = iso(latest[0].get("date_start")), iso(latest[0].get("date_end"))
                if start and end and start - LEAD <= now <= end + TAIL:
                    positions = fetcher(OPENF1 + "position?session_key=%s" % key) or []
                    order = live_order(positions, drivers)
                    if order:
                        out["live"] = {"session": session["name"], "name": text(latest[0].get("session_name"), 30),
                                       "start": start, "end": end, "order": order[:10],
                                       "finished": now > end}
    except F1Error:
        pass
    for row in out["drivers"] + ((out["last"] or {}).get("results") or []):
        row["colour"] = colours.get(row.get("code"), "")
    team_colour = {}
    for row in out["drivers"]:
        if row.get("colour") and row.get("team") and row["team"] not in team_colour:
            team_colour[row["team"]] = row["colour"]
    for row in out["teams"]:
        row["colour"] = team_colour.get(row["name"], "")
    if session:
        out["pollMs"] = LIVE_POLL_MS
    return out


def main():
    json.dump(collect(), sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
