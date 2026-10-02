#!/usr/bin/env python3
"""Output volume and sink state for the launcher tile. Stdlib only."""

import json
import re
import subprocess
import sys

DEFAULT_SINK = ["pactl", "get-default-sink"]
RESOLVED_SINK = ["omarchy-audio-output-sink"]
FRONTED_SINK = ["omarchy-audio-tuning", "fronted-sink"]
SINKS = ["pactl", "-f", "json", "list", "sinks"]
TIMEOUT = 5

PERCENT = re.compile(r"(\d+)\s*%")


def parse_volume(text):
    """First percentage from `pactl get-sink-volume`."""
    match = PERCENT.search(text or "")
    return int(match.group(1)) if match else 0


def parse_mute(text):
    """`Mute: yes` / `Mute: no`."""
    value = (text or "").partition(":")[2].strip().lower()
    return value == "yes"


def parse_sinks(text, fronted=""):
    """Available sinks, filtered the way omarchy-audio-output-switch picks them."""
    try:
        data = json.loads(text or "")
    except ValueError:
        return []
    out = []
    if not isinstance(data, list):
        return out
    for sink in data:
        if not isinstance(sink, dict):
            continue
        name = str(sink.get("name") or "")
        if not name:
            continue
        if fronted and name == fronted:
            continue
        ports = sink.get("ports") or []
        if isinstance(ports, list) and len(ports) > 0:
            usable = any(isinstance(port, dict) and port.get("availability") != "not available"
                         for port in ports)
            if not usable:
                continue
        properties = sink.get("properties") or {}
        description = sink.get("description") or properties.get("device.description") or name
        out.append({"name": name, "description": str(description)})
    return out


def run_cmd(argv, timeout):
    try:
        proc = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        return proc.returncode, proc.stdout
    except (OSError, subprocess.SubprocessError):
        return 127, ""


def gather(run):
    _, default_out = run(DEFAULT_SINK, TIMEOUT)
    default = (default_out or "").strip()
    _, resolved_out = run(RESOLVED_SINK, TIMEOUT)
    resolved = (resolved_out or "").strip() or default
    volume = 0
    muted = False
    if resolved:
        _, volume_out = run(["pactl", "get-sink-volume", resolved], TIMEOUT)
        volume = parse_volume(volume_out)
        _, mute_out = run(["pactl", "get-sink-mute", resolved], TIMEOUT)
        muted = parse_mute(mute_out)
    _, fronted_out = run(FRONTED_SINK, TIMEOUT)
    fronted = (fronted_out or "").strip()
    _, listed = run(SINKS, TIMEOUT)
    sinks = parse_sinks(listed, fronted)
    index = -1
    label = ""
    for i, row in enumerate(sinks):
        if row["name"] == default:
            index = i
            label = row["description"]
    if not label:
        label = default
    return {
        "volume": volume,
        "muted": muted,
        "sink": label,
        "sinks": [row["description"] for row in sinks],
        "index": index,
    }


def collect(run=None):
    return gather(run or run_cmd)


def main():
    json.dump(collect(), sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
