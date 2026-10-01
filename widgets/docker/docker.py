#!/usr/bin/env python3
"""Container summary for the launcher tile. Stdlib only."""

import json
import subprocess
import sys

SUDO_CHECK = ["omarchy-sudo-docker"]
PS = ["docker", "ps", "-a", "--format", "{{json .}}"]
TIMEOUT = 10
ROW_LIMIT = 4

EMPTY = {"ok": False, "mode": "error", "running": 0, "stopped": 0,
         "unhealthy": 0, "rows": []}


def parse_rows(text):
    """`docker ps --format '{{json .}}'` answers one object per line."""
    rows = []
    for line in (text or "").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            data = json.loads(line)
        except ValueError:
            continue
        if isinstance(data, dict):
            rows.append(data)
    return rows


def summarize(rows, limit=ROW_LIMIT):
    items = []
    running = stopped = unhealthy = 0
    for row in rows:
        state = str(row.get("State") or "").lower()
        status = str(row.get("Status") or "")
        name = str(row.get("Names") or "").split(",")[0].strip()
        is_running = state == "running"
        is_unhealthy = is_running and "(unhealthy)" in status.lower()
        if is_unhealthy:
            unhealthy += 1
        if is_running:
            running += 1
        else:
            stopped += 1
        items.append({"name": name, "status": status,
                      "running": is_running, "unhealthy": is_unhealthy})
    # The ones needing attention first, then live work, then history.
    items.sort(key=lambda item: (not item["unhealthy"], not item["running"], item["name"]))
    return {"running": running, "stopped": stopped, "unhealthy": unhealthy,
            "rows": items[:limit]}


def run_cmd(argv, timeout):
    try:
        proc = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        return proc.returncode, proc.stdout
    except (OSError, subprocess.SubprocessError):
        return 127, ""


def gather(run):
    code, _ = run(SUDO_CHECK, TIMEOUT)
    if code == 0:
        # The socket is unreachable. A missing client is not a permissions story.
        version_code, _ = run(["docker", "--version"], TIMEOUT)
        mode = "missing" if version_code == 127 else "sudo"
        payload = dict(EMPTY)
        payload["mode"] = mode
        return payload
    code, out = run(PS, TIMEOUT)
    if code != 0:
        return dict(EMPTY)
    payload = summarize(parse_rows(out))
    payload["ok"] = True
    payload["mode"] = "rows"
    return payload


def collect(run=None):
    return gather(run or run_cmd)


def main():
    json.dump(collect(), sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
