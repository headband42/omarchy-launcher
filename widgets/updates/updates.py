#!/usr/bin/env python3
"""Pending updates for the launcher tile. Stdlib only.

Reads `checkupdates`, `omarchy-update-available`, and the last package
transaction in /var/log/pacman.log. Answers are cached on disk so opening
the launcher does not hit the network every time.
"""

import json
import os
import subprocess
import time
from datetime import datetime

PACMAN_LOG = "/var/log/pacman.log"
CACHE_PATH = os.path.expanduser("~/.cache/ande.launcher/updates.json")
CACHE_MAX_AGE = 30 * 60
CHECKUPDATES_TIMEOUT = 60
OMARCHY_TIMEOUT = 30
NAME_LIMIT = 3


def parse_updates(text):
    """Turn `checkupdates --nocolor` lines into {name, old, new} rows."""
    rows = []
    for line in (text or "").splitlines():
        line = line.strip()
        if not line or " -> " not in line:
            continue
        left, _, new = line.partition(" -> ")
        name, sep, old = left.rpartition(" ")
        if not sep:
            continue
        rows.append({"name": name.strip(), "old": old.strip(), "new": new.strip()})
    return rows


def parse_last_upgrade(text):
    """Epoch seconds of the last `[ALPM] transaction completed` line, else 0."""
    stamp = ""
    for line in (text or "").splitlines():
        if line.startswith("[") and "[ALPM] transaction completed" in line:
            stamp = line[1:line.index("]")]
    if not stamp:
        return 0
    try:
        return datetime.strptime(stamp, "%Y-%m-%dT%H:%M:%S%z").timestamp()
    except ValueError:
        return 0


def parse_omarchy(text, code):
    """omarchy-update-available prints note lines and exits 0 when there are any."""
    if code != 0:
        return []
    return [line.strip() for line in (text or "").splitlines() if line.strip()]


def run_cmd(argv, timeout):
    try:
        proc = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        return proc.returncode, proc.stdout
    except (OSError, subprocess.SubprocessError):
        return 127, ""


def read_text(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


def write_cache(path, payload):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(payload, fh)
        os.replace(tmp, path)
    except OSError:
        pass


def read_cache(path, max_age, now):
    try:
        age = now - os.path.getmtime(path)
    except OSError:
        return None
    if age < 0 or age > max_age:
        return None
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def gather(run, read_log):
    code, out = run(["checkupdates", "--nocolor"], CHECKUPDATES_TIMEOUT)
    rows = parse_updates(out)
    ocode, oout = run(["omarchy-update-available"], OMARCHY_TIMEOUT)
    return {
        "ok": code in (0, 2),
        "count": len(rows),
        "names": [row["name"] for row in rows[:NAME_LIMIT]],
        "omarchy": parse_omarchy(oout, ocode),
        "lastUpgradeAt": parse_last_upgrade(read_log(PACMAN_LOG)),
    }


def collect(run=None, read_log=None, cache_path=CACHE_PATH, max_age=CACHE_MAX_AGE,
            now=None, read_cache_fn=read_cache):
    run = run or run_cmd
    read_log = read_log or read_text
    if now is None:
        now = time.time()
    cached = read_cache_fn(cache_path, max_age, now)
    if cached is not None:
        # The log read is local and cheap; keep "last updated" moving even
        # while the network answers come from the cache.
        cached["lastUpgradeAt"] = parse_last_upgrade(read_log(PACMAN_LOG))
        return cached
    payload = gather(run, read_log)
    write_cache(cache_path, payload)
    return payload
