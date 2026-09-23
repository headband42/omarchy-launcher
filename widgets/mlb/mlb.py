#!/usr/bin/env python3
"""MLB tile model. Stdlib only. Network lives in sample.py; tests call collect().

The tile follows one club (`teamId` in the widget settings). A live game shows
the line score, count, bases, batter, and pitcher. Between games it shows the
last final line score and when the next game starts. With no club, or during
the postseason when that club has no postseason games, it shows the live slate.
"""

import json
from datetime import date, datetime, timedelta
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo

API = "https://statsapi.mlb.com/api/v1"
MLB_TZ = ZoneInfo("America/New_York")
POLL_LIVE_MS = 15000
POLL_IDLE_MS = 60000
MAX_INNINGS = 11

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
        rows.append({
            "id": pk,
            "abbr": str(team.get("abbreviation") or "").strip(),
            "name": name,
            "location": str(team.get("locationName") or "").strip(),
            "club": str(team.get("teamName") or name).strip(),
        })
    rows.sort(key=lambda row: (row["name"].casefold(), row["id"]))
    return rows


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
        hydrate="linescore,team",
    )


def postseason_url(team_id, year):
    return _url(
        "schedule",
        sportId=1,
        teamId=team_id,
        season=year,
        gameTypes="F,D,L,W",
        hydrate="linescore,team",
    )


def team_url(team_id):
    return _url(
        f"teams/{int(team_id)}",
        hydrate="previousSchedule(linescore,team),nextSchedule(team,linescore)",
    )


def teams_url(now):
    return _url("teams", sportId=1, season=mlb_day(now).year)


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


def count_line(balls, strikes, outs):
    parts = []
    if balls is not None and strikes is not None:
        parts.append(f"{balls}-{strikes}")
    if outs is not None:
        parts.append("1 out" if outs == 1 else f"{outs} outs")
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
    if state == "live":
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
        batter = person_name(offense.get("batter"))
        pitcher = person_name(defense.get("pitcher"))
    status = status_label(state, detailed, linescore)
    detail_bits = [status]
    counted = count_line(balls, strikes, outs)
    if counted:
        detail_bits.append(counted)
    names = [last_name(batter), last_name(pitcher)]
    pk = as_int(game.get("gamePk")) or 0
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
        "batterLine": f"{batter} batting" if batter else "",
        "pitcherLine": f"{pitcher} pitching" if pitcher else "",
        "countLine": counted,
        "labels": labels,
        "hasLine": any(cell != "" for cell in away_innings + home_innings),
        "away": away,
        "home": home,
        "rowTitle": f"{away['abbr']} {away['score']}  {home['abbr']} {home['score']}",
        "rowDetail": " · ".join(detail_bits),
        "rowNames": " · ".join(name for name in names if name),
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
    pk = as_int(game.get("gamePk")) or 0
    return {
        "gamePk": pk,
        "gameday": gameday_url(pk),
        "when": when,
        "where": matchup(away, home, team_id),
        "kicker": kicker,
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
    }
    base.update(extra)
    return base


def choose_view(team_id, window, pool, *, missed_playoffs, now):
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
    if team_id:
        season_payload = safe_fetch(fetch, season_url(day.year))
        season = season_record(season_payload, day.year) if season_payload is not None else {}
        if in_postseason(season, day):
            posted = safe_fetch(fetch, postseason_url(team_id, day.year))
            if posted is not None:
                postseason_games = games_from_schedule(posted)
                missed = len(postseason_games) == 0
    if not team_id or missed:
        return choose_view(team_id, window, [], missed_playoffs=missed, now=now)
    live_now = any(involves(game, team_id) and classify_game(game)[0] == "live" for game in window)
    pool = list(postseason_games)
    if not live_now:
        hydrated = safe_fetch(fetch, team_url(team_id))
        if hydrated is not None:
            pool.extend(games_from_team_payload(hydrated))
    pool.extend(game for game in window if involves(game, team_id))
    return choose_view(team_id, window, pool, missed_playoffs=False, now=now)
