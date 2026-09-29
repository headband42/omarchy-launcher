#!/usr/bin/env python3
"""Toggle switch states for the launcher tile. Stdlib only.

Reads the two Omarchy indicator status commands and the notifications
file the shell keeps for do-not-disturb.
"""

import json
import os
import subprocess

NIGHTLIGHT = ["omarchy-toggle-nightlight", "--status"]
STAY_AWAKE = ["omarchy-toggle-idle", "status"]
DND_PATH = os.path.expanduser("~/.local/state/omarchy/notifications.json")
TIMEOUT = 5


def parse_enabled(text):
    """Status scripts answer with {"enabled": bool, ...}."""
    try:
        data = json.loads(text or "")
    except ValueError:
        return False
    return isinstance(data, dict) and bool(data.get("enabled"))


def parse_dnd(text):
    """The notifications file keeps do-not-disturb in its `dnd` key."""
    try:
        data = json.loads(text or "")
    except ValueError:
        return False
    return isinstance(data, dict) and bool(data.get("dnd"))


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


def gather(run, read_file):
    _, night = run(NIGHTLIGHT, TIMEOUT)
    _, awake = run(STAY_AWAKE, TIMEOUT)
    return {
        "nightlight": parse_enabled(night),
        "stayAwake": parse_enabled(awake),
        "dnd": parse_dnd(read_file(DND_PATH)),
    }


def collect(run=None, read_file=None):
    return gather(run or run_cmd, read_file or read_text)
