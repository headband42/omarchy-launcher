#!/usr/bin/env python3
"""Battery and power profile state for the launcher tile. Stdlib only."""

import json
import subprocess

BATTERY_PRESENT = ["omarchy-battery-present"]
POWER_PRESENT = ["omarchy-power-present"]
UPOWER_DEVICES = ["upower", "-e"]
PROFILES = ["omarchy-powerprofiles-list", "--active-state"]
TIMEOUT = 5


def parse_upower(text):
    """Pull percentage, state, time remaining, and rate out of `upower -i`."""
    fields = {}
    for line in (text or "").splitlines():
        if ":" not in line:
            continue
        key, _, value = line.partition(":")
        fields[key.strip()] = value.strip()
    out = {"percentage": 0, "state": "", "minutes": 0, "rate": 0.0}
    try:
        out["percentage"] = int(float(fields.get("percentage", "0").rstrip("%")))
    except ValueError:
        out["percentage"] = 0
    out["state"] = fields.get("state", "")
    out["minutes"] = parse_duration(fields.get("time to empty", "") or fields.get("time to full", ""))
    try:
        out["rate"] = float(fields.get("energy-rate", "0").split()[0])
    except (ValueError, IndexError):
        out["rate"] = 0.0
    return out


def parse_duration(text):
    """`3.7 hours` or `45.2 minutes` into whole minutes. 0 when unknown."""
    parts = (text or "").split()
    if len(parts) < 2:
        return 0
    try:
        value = float(parts[0])
    except ValueError:
        return 0
    unit = parts[1].lower()
    if unit.startswith("hour"):
        return int(round(value * 60))
    if unit.startswith("minute"):
        return int(round(value))
    if unit.startswith("second"):
        return int(round(value / 60))
    return 0


def parse_profiles(text):
    """`name\\t0|1` lines into (current, [names]) in listed order."""
    names = []
    current = ""
    for line in (text or "").splitlines():
        parts = line.split("\t")
        if len(parts) != 2:
            continue
        name = parts[0].strip()
        if not name:
            continue
        names.append(name)
        if parts[1].strip() == "1":
            current = name
    return current, names


def run_cmd(argv, timeout):
    try:
        proc = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        return proc.returncode, proc.stdout
    except (OSError, subprocess.SubprocessError):
        return 127, ""


def gather(run):
    code, _ = run(BATTERY_PRESENT, TIMEOUT)
    battery = code == 0
    data = {"percentage": 0, "state": "", "minutes": 0, "rate": 0.0}
    if battery:
        _, devices = run(UPOWER_DEVICES, TIMEOUT)
        device = ""
        for line in (devices or "").splitlines():
            if "BAT" in line:
                device = line.strip()
                break
        if device:
            _, info = run(["upower", "-i", device], TIMEOUT)
            data = parse_upower(info)
    ac_code, _ = run(POWER_PRESENT, TIMEOUT)
    _, listed = run(PROFILES, TIMEOUT)
    current, names = parse_profiles(listed)
    return {
        "battery": battery,
        "percentage": data["percentage"],
        "state": data["state"],
        "minutesLeft": data["minutes"],
        "rate": data["rate"],
        "onAc": ac_code == 0,
        "profile": current,
        "profiles": names,
    }


def collect(run=None):
    return gather(run or run_cmd)
