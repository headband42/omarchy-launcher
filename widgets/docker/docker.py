#!/usr/bin/env python3
"""Container summary for the launcher tile. Stdlib only.

    docker.py
    docker.py --action start|stop|restart --id CONTAINER

It asks systemd about the daemon first, which needs no root. A daemon that is
stopped, or idle behind its socket, is reported as such: `docker ps` would
wake a socket-activated daemon, and with it every `restart: always`
container, just because the launcher opened.
"""

import json
import os
import re
import subprocess
import sys

VERSION = ["docker", "--version"]
UNITS = ["systemctl", "show", "docker.service", "docker.socket",
         "--property=LoadState,ActiveState"]
SUDO_CHECK = ["omarchy-sudo-docker"]
SUDO_CONFIGURED = ["omarchy-sudo-docker", "--configured"]
SCOPES = ["systemctl", "list-units", "--type=scope", "--state=running",
          "--no-legend", "--plain", "docker-*.scope"]
PS = ["docker", "ps", "-a", "--format", "{{json .}}"]
STATS = ["docker", "stats", "--no-stream", "--format", "{{json .}}"]
TIMEOUT = 10
ACTION_TIMEOUT = 40
ROW_LIMIT = 12
ACTIONS = ("start", "stop", "restart")
TARGET_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$")

DURATION_RE = re.compile(
    r"(less than a second)|(about an?) (minute|hour)|(\d+) (second|minute|hour|day|week|month|year)s?",
    re.IGNORECASE)
UNIT = {"second": "s", "minute": "m", "hour": "h", "day": "d", "week": "w",
        "month": "mo", "year": "y"}
EXIT_RE = re.compile(r"exited \((-?\d+)\)", re.IGNORECASE)
PORT_RE = re.compile(r":(\d+)->")
SIZE_RE = re.compile(r"^\s*([\d.]+)\s*([kmgtp]?i?b)\s*$", re.IGNORECASE)
SIZES = {"b": 1, "kb": 10**3, "kib": 2**10, "mb": 10**6, "mib": 2**20, "gb": 10**9,
         "gib": 2**30, "tb": 10**12, "tib": 2**40, "pb": 10**15, "pib": 2**50}


def payload(mode, daemon=""):
    return {"ok": False, "mode": mode, "daemon": daemon, "running": 0, "paused": 0,
            "stopped": 0, "unhealthy": 0, "cpu": 0.0, "mem": 0, "rows": []}


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


def parse_units(text):
    """`systemctl show A B --property=...`: one block per unit, blank-separated."""
    blocks = []
    current = {}
    for line in (text or "").splitlines():
        line = line.strip()
        if not line:
            if current:
                blocks.append(current)
                current = {}
            continue
        key, _, value = line.partition("=")
        current[key] = value
    if current:
        blocks.append(current)
    return blocks


def daemon_state(blocks):
    """running, idle (only the socket is up), stopped, or "" when systemd has no unit."""
    service = blocks[0] if blocks else {}
    socket = blocks[1] if len(blocks) > 1 else {}
    if service.get("LoadState") != "loaded":
        return ""
    if service.get("ActiveState") in ("active", "activating", "reloading"):
        return "running"
    if socket.get("LoadState") == "loaded" and socket.get("ActiveState") == "active":
        return "idle"
    return "stopped"


def count_scopes(text):
    """Running containers systemd can see, one docker-<id>.scope each."""
    return sum(1 for line in (text or "").splitlines() if line.strip().startswith("docker-"))


def short_duration(text):
    match = DURATION_RE.search(text or "")
    if not match:
        return ""
    if match.group(1):
        return "now"
    if match.group(2):
        return "1" + UNIT[match.group(3).lower()]
    return match.group(4) + UNIT[match.group(5).lower()]


def describe(state, status):
    """A short status for the row, its health, and how loud it should look."""
    lower = (status or "").lower()
    health = ""
    if "(unhealthy)" in lower:
        health = "unhealthy"
    elif "(healthy)" in lower:
        health = "healthy"
    elif "health: starting" in lower:
        health = "starting"
    age = short_duration(status)
    if state == "running":
        if health == "unhealthy":
            return "unhealthy", health, "bad"
        if health == "starting":
            return "starting", health, "warn"
        return ("up " + age).strip(), health, "ok"
    if state == "exited":
        match = EXIT_RE.search(lower)
        code = int(match.group(1)) if match else 0
        if code:
            return "exit %d" % code + (" · " + age if age else ""), health, "bad"
        return ("exited " + age).strip(), health, "off"
    if state == "paused":
        return "paused", health, "warn"
    if state in ("restarting", "dead"):
        return state, health, "bad"
    return state or (status or "").lower(), health, "off"


def short_image(image):
    value = (image or "").split("@", 1)[0]
    if value.startswith("sha256:"):
        return value[7:19]
    name = value.rsplit("/", 1)[-1]
    return name[:-len(":latest")] if name.endswith(":latest") else name


def label(labels, key):
    for part in (labels or "").split(","):
        name, _, value = part.partition("=")
        if name.strip() == key:
            return value.strip()
    return ""


def host_ports(text):
    ports = []
    for port in PORT_RE.findall(text or ""):
        if port not in ports:
            ports.append(port)
    return ports


def parse_size(text):
    match = SIZE_RE.match(text or "")
    if not match:
        return 0
    try:
        return int(float(match.group(1)) * SIZES[match.group(2).lower()])
    except (ValueError, KeyError):
        return 0


def parse_percent(text):
    try:
        return float(str(text or "").strip().rstrip("%"))
    except ValueError:
        return 0.0


def parse_stats(text):
    """`docker stats --no-stream`: CPU percent and memory in use, by name."""
    stats = {}
    for row in parse_rows(text):
        name = str(row.get("Name") or row.get("Container") or "").strip()
        if not name:
            continue
        used = str(row.get("MemUsage") or "").split("/", 1)[0]
        stats[name] = {"cpu": parse_percent(row.get("CPUPerc")), "mem": parse_size(used)}
    return stats


# Trouble first, then what is running, then what is not.
RANK = {"bad": 0, "ok": 1, "warn": 2, "off": 3}


def summarize(rows, stats=None, limit=ROW_LIMIT):
    stats = stats or {}
    items = []
    out = payload("rows")
    for row in rows:
        state = str(row.get("State") or "").lower()
        status = str(row.get("Status") or "")
        name = str(row.get("Names") or "").split(",")[0].strip()
        short, health, tone = describe(state, status)
        running = state == "running"
        if running:
            out["running"] += 1
        elif state == "paused":
            out["paused"] += 1
        else:
            out["stopped"] += 1
        if health == "unhealthy":
            out["unhealthy"] += 1
        usage = stats.get(name) if running else None
        if usage:
            out["cpu"] += usage["cpu"]
            out["mem"] += usage["mem"]
        items.append({
            "id": str(row.get("ID") or ""),
            "name": name,
            "image": short_image(str(row.get("Image") or "")),
            "project": label(str(row.get("Labels") or ""), "com.docker.compose.project"),
            "state": state,
            "status": status,
            "short": short,
            "tone": tone,
            "health": health,
            "running": running,
            "unhealthy": health == "unhealthy",
            "ports": host_ports(str(row.get("Ports") or ""))[:2],
            "cpu": round(usage["cpu"], 1) if usage else None,
            "mem": usage["mem"] if usage else None,
        })
    items.sort(key=lambda item: (RANK.get(item["tone"], 3), item["project"], item["name"]))
    out["cpu"] = round(out["cpu"], 1)
    out["rows"] = items[:limit]
    return out


def run_cmd(argv, timeout):
    try:
        proc = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        return proc.returncode, proc.stdout, proc.stderr
    except subprocess.TimeoutExpired:
        return 124, "", "timed out"
    except (OSError, subprocess.SubprocessError) as error:
        return 127, "", str(error)


def gather(run, env=None):
    env = os.environ if env is None else env
    remote = bool(env.get("DOCKER_HOST") or env.get("DOCKER_CONTEXT"))
    if run(VERSION, TIMEOUT)[0] == 127:
        return payload("missing")
    daemon = "" if remote else daemon_state(parse_units(run(UNITS, TIMEOUT)[1]))
    if daemon == "stopped":
        return payload("stopped", daemon)
    if not remote and run(SUDO_CHECK, TIMEOUT)[0] == 0:
        out = payload("sudo", daemon)
        # In the docker group already, but this session predates it.
        out["pendingLogin"] = run(SUDO_CONFIGURED, TIMEOUT)[0] == 1
        out["scoped"] = count_scopes(run(SCOPES, TIMEOUT)[1]) if daemon == "running" else 0
        return out
    if daemon == "idle":
        return payload("idle", daemon)
    code, out, _ = run(PS, TIMEOUT)
    if code != 0:
        return payload("error", daemon)
    rows = parse_rows(out)
    stats = {}
    if any(str(row.get("State") or "").lower() == "running" for row in rows):
        code, text, _ = run(STATS, TIMEOUT)
        if code == 0:
            stats = parse_stats(text)
    data = summarize(rows, stats)
    data["ok"] = True
    data["daemon"] = daemon or "running"
    return data


def act(run, action, target):
    if action not in ACTIONS or not TARGET_RE.match(target or ""):
        return {"ok": False, "action": action, "id": target, "error": "unknown action"}
    code, _, err = run(["docker", action, target], ACTION_TIMEOUT)
    lines = [line.strip() for line in (err or "").splitlines() if line.strip()]
    error = "" if code == 0 else (lines[-1] if lines else "docker %s failed" % action)
    if error.startswith("Error response from daemon: "):
        error = error[len("Error response from daemon: "):]
    return {"ok": code == 0, "action": action, "id": target, "error": error}


def collect(run=None, action="", target=""):
    run = run or run_cmd
    result = act(run, action, target) if action else None
    data = gather(run)
    if result is not None:
        data["action"] = result
    return data


def flag(args, name):
    if name in args:
        index = args.index(name)
        if index + 1 < len(args):
            return args[index + 1]
    return ""


def main(argv):
    args = argv[1:]
    json.dump(collect(action=flag(args, "--action"), target=flag(args, "--id")), sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
