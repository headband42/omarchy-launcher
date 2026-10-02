#!/usr/bin/env python3
"""Omarchy reminders for the timer tile. Stdlib only.

    timer.py                 every reminder still to fire, soonest first
    timer.py --cancel UNIT   stop one reminder

A reminder is a systemd user timer that `omarchy-reminder <minutes>` starts:
it fires a notification whether or not the launcher is open. This file reads
them through `omarchy-reminder show --json` and cancels one the way
`omarchy-reminder clear` cancels them all, since that command has no way to
stop a single one. The unit name carries the length and the start:
omarchy-reminder-25m-1790000000.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import time

UNIT = re.compile(r"omarchy-reminder-(\d{1,5})m-(\d{9,11})")
TIMEOUT = 5


def run(argv, timeout=TIMEOUT):
    if not shutil.which(argv[0]):
        return None
    try:
        proc = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError):
        return None
    return proc.stdout if proc.returncode == 0 else None


def parse_unit(unit):
    """(minutes, started) from a reminder's unit name, or None."""
    match = UNIT.fullmatch(str(unit or "").removesuffix(".timer"))
    if not match:
        return None
    return int(match.group(1)), int(match.group(2))


def normalize(payload, now):
    """The reminders that have not fired yet, soonest first."""
    rows = []
    items = payload.get("reminders") if isinstance(payload, dict) else None
    for item in items if isinstance(items, list) else []:
        if not isinstance(item, dict):
            continue
        unit = str(item.get("unit") or "")
        parsed = parse_unit(unit)
        try:
            at = int(item.get("at"))
        except (TypeError, ValueError):
            continue
        if not parsed or at <= now:
            continue
        minutes, started = parsed
        message = str(item.get("message") or "").strip()
        rows.append({
            "unit": unit,
            "minutes": minutes,
            "started": started,
            "at": at,
            "message": message[:120],
        })
    rows.sort(key=lambda row: row["at"])
    return rows


def collect(runner=run, now=None):
    now = int(time.time()) if now is None else now
    if not shutil.which("omarchy-reminder") and runner is run:
        return {"ok": False, "error": "omarchy-reminder is not installed", "reminders": []}
    out = runner(["omarchy-reminder", "show", "--json"])
    if out is None:
        return {"ok": False, "error": "omarchy-reminder did not answer", "reminders": []}
    try:
        payload = json.loads(out)
    except ValueError:
        return {"ok": False, "error": "omarchy-reminder sent something unreadable", "reminders": []}
    return {"ok": True, "error": "", "reminders": normalize(payload, now)}


def message_dir():
    return os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "omarchy-reminders")


def cancel(unit, runner=run, remove=os.remove, folder=None):
    """Stop one reminder. Only a name `omarchy-reminder` itself makes is accepted."""
    unit = str(unit or "").removesuffix(".timer")
    if not parse_unit(unit):
        return {"ok": False}
    stopped = runner(["systemctl", "--user", "stop", unit + ".timer"]) is not None
    try:
        remove(os.path.join(folder or message_dir(), unit + ".message"))
    except OSError:
        pass
    runner(["omarchy-shell", "-q", "omarchy.indicators", "refresh"])
    return {"ok": stopped}


def main(argv):
    args = argv[1:]
    if "--cancel" in args:
        index = args.index("--cancel")
        payload = cancel(args[index + 1] if index + 1 < len(args) else "")
    else:
        payload = collect()
    json.dump(payload, sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
