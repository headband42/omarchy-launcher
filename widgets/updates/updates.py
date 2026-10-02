#!/usr/bin/env python3
"""Pending updates for the launcher tile. Stdlib only.

Reads `checkupdates`, `omarchy-update-available`, the active channel and
version, and the last package transaction in /var/log/pacman.log. Network
answers are cached on disk so opening the launcher does not hit the
network every time; the local answers are always fresh.
"""

import json
import os
import subprocess
import sys
import time
from datetime import datetime

PACMAN_LOG = "/var/log/pacman.log"
CACHE_PATH = os.path.expanduser("~/.cache/ande.launcher/updates.json")
CACHE_MAX_AGE = 30 * 60
CHECKUPDATES_TIMEOUT = 60
OMARCHY_TIMEOUT = 30
LOCAL_TIMEOUT = 5
NAME_LIMIT = 3

CHANNEL = ["omarchy-channel-current"]
VERSION = ["omarchy-version"]


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


def first_line(text):
    """Trimmed first non-empty line, or ""."""
    for line in (text or "").splitlines():
        line = line.strip()
        if line:
            return line
    return ""


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


def local_state(run, read_log):
    """Channel, version, and last upgrade. Local and cheap, so always fresh."""
    _, channel = run(CHANNEL, LOCAL_TIMEOUT)
    _, version = run(VERSION, LOCAL_TIMEOUT)
    return {
        "channel": first_line(channel),
        "version": first_line(version),
        "lastUpgradeAt": parse_last_upgrade(read_log(PACMAN_LOG)),
    }


def gather(run, read_log):
    code, out = run(["checkupdates", "--nocolor"], CHECKUPDATES_TIMEOUT)
    rows = parse_updates(out)
    ocode, oout = run(["omarchy-update-available"], OMARCHY_TIMEOUT)
    payload = {
        "ok": code in (0, 2),
        "count": len(rows),
        "names": [row["name"] for row in rows[:NAME_LIMIT]],
        "omarchy": parse_omarchy(oout, ocode),
    }
    payload.update(local_state(run, read_log))
    return payload


def collect(run=None, read_log=None, cache_path=CACHE_PATH, max_age=CACHE_MAX_AGE,
            now=None, read_cache_fn=read_cache):
    run = run or run_cmd
    read_log = read_log or read_text
    if now is None:
        now = time.time()
    cached = read_cache_fn(cache_path, max_age, now)
    if cached is not None:
        # Cached answers cover the network calls only. Channel, version, and
        # "last updated" move too often to freeze behind the cache.
        cached.update(local_state(run, read_log))
        return cached
    payload = gather(run, read_log)
    write_cache(cache_path, payload)
    return payload


def main():
    json.dump(collect(), sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
