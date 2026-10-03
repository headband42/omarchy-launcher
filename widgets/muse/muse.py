#!/usr/bin/env python3
"""Muse usage for the launcher tile. Stdlib only.

Muse Code writes every model call to its session logs, one JSON object per
line under `$XDG_DATA_HOME/muse/sessions/` (else `~/.local/share/muse/`):

    <uuid>/session.jsonl -> payload.event.kind == "model_completed"

Each of those events names the model and its token use (`input_tokens`,
`output_tokens`, `reasoning_tokens`, cache counters) and when it finished
(`recorded_at`, microseconds since the epoch). The tile adds those up: the
tokens since local midnight, the tokens in the last seven days, and how
full the latest call's context window was, against that model's
`context_limit` from the catalog Muse Code keeps next to the logs
(`model-catalog/*.json`).

Only `model_completed` events are counted. The logs also carry aggregated
`quantity` records that repeat the same numbers, so counting both would
count everything twice. Exact duplicates (same moment, model, and counts)
are read once, so a forked session that copied a log does not double it.
`reasoning_tokens` is not added on top: it is part of the output count.

Nothing here reaches the network or reads a credential. A model the catalog
does not know keeps its absolute tokens but no percentage, never a guessed
limit.
"""

import json
import os
import sys
from datetime import datetime

DAY_MS = 24 * 60 * 60 * 1000
WEEK_MS = 7 * DAY_MS

POLL_MS = 60000
NEAR_LIMIT = 80.0


def number(value):
    if value is None or isinstance(value, bool):
        return None
    try:
        result = float(value)
    except (TypeError, ValueError):
        return None
    if result != result or result in (float("inf"), float("-inf")):
        return None
    return result


def count(value):
    """A token count: whole tokens, never negative, never a guess."""
    result = number(value)
    if result is None:
        return None
    return max(0, int(result))


def text(value, limit=200):
    return str(value or "").strip()[:limit]


def compact(value):
    """31494 -> "31K", 1200000 -> "1.2M". None stays unknown, not zero."""
    amount = count(value)
    if amount is None:
        return "—"
    if amount >= 999500:
        trimmed = ("%.1f" % (amount / 1000000)).rstrip("0").rstrip(".")
        return trimmed + "M"
    if amount >= 1000:
        return str(int(amount / 1000 + 0.5)) + "K"
    return str(amount)


def data_home():
    """Where Muse Code keeps its sessions, the way Muse Code finds it."""
    root = text(os.environ.get("XDG_DATA_HOME"), 400)
    if root:
        return os.path.join(os.path.expanduser(root), "muse")
    home = os.path.expanduser("~")
    if home and home != "~":
        return os.path.join(home, ".local", "share", "muse")
    return ""


def recorded_ms(value):
    """`recorded_at` is microseconds; accept millis or seconds too."""
    stamp = number(value)
    if stamp is None:
        return None
    if stamp >= 1e14:
        return int(stamp / 1000)
    if stamp >= 1e11:
        return int(stamp)
    if stamp >= 1e8:
        return int(stamp * 1000)
    return None


def parse_event(line):
    """One model_completed event, or None for anything else. No counting."""
    try:
        record = json.loads(line)
    except (TypeError, ValueError):
        return None
    if not isinstance(record, dict):
        return None
    payload = record.get("payload")
    event = payload.get("event") if isinstance(payload, dict) else None
    if not isinstance(event, dict) or event.get("kind") != "model_completed":
        return None
    usage = event.get("usage")
    if not isinstance(usage, dict):
        return None
    stamp = recorded_ms(record.get("recorded_at"))
    if stamp is None:
        return None
    stream = record.get("stream")
    session = stream.get("id") if isinstance(stream, dict) else None
    return {
        "at": stamp,
        "model": text(event.get("model"), 120),
        "session": text(session, 64),
        "input": count(usage.get("input_tokens")),
        "output": count(usage.get("output_tokens")),
    }


def tokens(event):
    """What one call used. Missing counters are zeros, not unknowns."""
    return (event["input"] or 0) + (event["output"] or 0)


def session_files(sessions):
    """Every session.jsonl under a sessions dir, newest first."""
    found = []
    if not sessions or not os.path.isdir(sessions):
        return found
    for dirpath, _dirnames, filenames in os.walk(sessions):
        for name in filenames:
            if name != "session.jsonl":
                continue
            path = os.path.join(dirpath, name)
            try:
                found.append((os.path.getmtime(path), path))
            except OSError:
                continue
    found.sort(reverse=True)
    return [path for _mtime, path in found]


def scan_file(path, seen):
    """The model_completed events in one log, minus exact duplicates."""
    events = []
    try:
        handle = open(path, encoding="utf-8", errors="replace")
    except OSError:
        return events
    with handle:
        for line in handle:
            if "model_completed" not in line:
                continue
            event = parse_event(line)
            if not event:
                continue
            key = (event["at"], event["model"], event["input"], event["output"])
            if key in seen:
                continue
            seen.add(key)
            events.append(event)
    return events


def collect_events(sessions):
    """Every log, newest first. A copied log can carry a stale mtime with
    fresh events inside, so no file is skipped for its age; the event
    timestamps gate the windows instead."""
    events = []
    seen = set()
    for path in session_files(sessions):
        events.extend(scan_file(path, seen))
    return events


def context_limits(home):
    """model_id -> context_limit from Muse Code's own catalog cache."""
    limits = {}
    folder = os.path.join(home, "model-catalog") if home else ""
    if not folder or not os.path.isdir(folder):
        return limits
    try:
        names = sorted(os.listdir(folder))
    except OSError:
        return limits
    for name in names:
        if not name.endswith(".json"):
            continue
        try:
            with open(os.path.join(folder, name), encoding="utf-8") as handle:
                data = json.load(handle)
        except (OSError, ValueError):
            continue
        rows = data.get("rows") if isinstance(data, dict) else None
        if not isinstance(rows, list):
            continue
        for row in rows:
            if not isinstance(row, dict):
                continue
            model = text(row.get("model_id"), 120)
            limit = count(row.get("context_limit"))
            if model and limit:
                limits.setdefault(model, limit)
    return limits


def midnight_ms(now_ms):
    """Local midnight before now, in epoch millis."""
    moment = datetime.fromtimestamp(now_ms / 1000)
    start = moment.replace(hour=0, minute=0, second=0, microsecond=0)
    return int(start.timestamp() * 1000)


def summarize(events, start_ms):
    total = 0
    sessions = set()
    for event in events:
        if event["at"] < start_ms:
            continue
        total += tokens(event)
        if event["session"]:
            sessions.add(event["session"])
    return total, len(sessions)


def sessions_word(counted):
    return "1 session" if counted == 1 else "%d sessions" % counted


def parse_usage(events, limits, now_ms):
    if not events:
        return error_view("No Muse usage recorded yet", "empty")
    today_at = midnight_ms(now_ms)
    week_at = now_ms - WEEK_MS
    today, today_sessions = summarize(events, today_at)
    week, week_sessions = summarize(events, week_at)
    with_input = [event for event in events if event["input"]]
    latest = max(with_input or events, key=lambda event: (event["at"], tokens(event)))
    used = latest["input"] or 0
    limit = limits.get(latest["model"]) if latest["model"] else None
    percent = used / limit * 100 if limit else None
    if percent is not None:
        context_detail = "%s of %s · %s" % (compact(used), compact(limit), latest["model"])
    elif latest["model"]:
        context_detail = "%s · %s" % (compact(used), latest["model"])
    else:
        context_detail = compact(used)
    meters = [
        {
            "id": "context",
            "label": "CONTEXT",
            "caption": "of the context window",
            "percent": percent,
            "resetsAtMs": None,
            "idle": False,
            "over": percent is not None and percent >= 100.0,
            "near": percent is not None and percent >= NEAR_LIMIT,
            "detail": context_detail,
        },
        {
            "id": "today",
            "label": "TODAY",
            "caption": "tokens today",
            "percent": None,
            "resetsAtMs": None,
            "idle": False,
            "over": False,
            "near": False,
            "detail": "%s tokens · %s" % (compact(today), sessions_word(today_sessions)),
        },
        {
            "id": "week",
            "label": "7 DAYS",
            "caption": "tokens in 7 days",
            "percent": None,
            "resetsAtMs": None,
            "idle": False,
            "over": False,
            "near": False,
            "detail": "%s tokens · %s" % (compact(week), sessions_word(week_sessions)),
        },
    ]
    return {
        "ok": True,
        "reason": "",
        "plan": "Muse",
        "model": latest["model"],
        "meters": meters,
        "error": None,
        "pollMs": POLL_MS,
    }


def error_view(message="Muse usage is unavailable", reason="error", plan="Muse"):
    """What the tile draws instead of bars. `reason` picks the advice:
    empty (no usage recorded yet) or error."""
    return {
        "ok": False,
        "reason": reason,
        "plan": plan,
        "model": "",
        "meters": [],
        "error": text(message, 160) or "Muse usage is unavailable",
        "pollMs": POLL_MS,
    }


def collect(home=None, now_ms=None):
    home = home if home is not None else data_home()
    now_ms = now_ms if now_ms is not None else int(datetime.now().timestamp() * 1000)
    events = collect_events(os.path.join(home, "sessions") if home else "")
    return parse_usage(events, context_limits(home), now_ms)


def cache_path():
    root = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
    return os.path.join(root, "ande.launcher", "muse.json")


def write_cache(payload, path=None):
    """Keep the last good reply for the next launcher session. Best effort.
    The payload is usage only: it never held a credential."""
    target = path or cache_path()
    try:
        os.makedirs(os.path.dirname(target), exist_ok=True)
        temporary = "%s.%d.tmp" % (target, os.getpid())
        with open(temporary, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, separators=(",", ":"))
        os.replace(temporary, target)
    except OSError:
        pass


def main(argv, collector=None, cache=None):
    try:
        payload = (collector or collect)()
    except Exception as error:
        payload = error_view(text(error, 160) or "Muse usage is unavailable")
    payload["savedAt"] = int(datetime.now().timestamp() * 1000)
    if payload.get("ok"):
        write_cache(payload, cache)
    json.dump(payload, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
