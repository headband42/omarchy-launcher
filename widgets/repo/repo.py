#!/usr/bin/env python3
"""Git status for one repository, for the launcher tile. Stdlib only."""

import subprocess

TIMEOUT = 5


def parse_status(text):
    """Read `git status --porcelain=v2 --branch` into counts and branch info."""
    out = {"ok": False, "branch": "", "detached": False,
           "ahead": 0, "behind": 0, "dirty": 0, "untracked": 0, "conflicted": 0}
    for line in (text or "").splitlines():
        if line.startswith("# branch.head "):
            value = line[len("# branch.head "):].strip()
            out["ok"] = True
            if value == "(detached)":
                out["detached"] = True
            else:
                out["branch"] = value
        elif line.startswith("# branch.ab "):
            for part in line[len("# branch.ab "):].split():
                try:
                    count = int(part[1:])
                except ValueError:
                    continue
                if part.startswith("+"):
                    out["ahead"] = count
                elif part.startswith("-"):
                    out["behind"] = count
        elif line.startswith("1 ") or line.startswith("2 "):
            out["dirty"] += 1
        elif line.startswith("u "):
            out["conflicted"] += 1
        elif line.startswith("? "):
            out["untracked"] += 1
    return out


def parse_log(text):
    """`%h\\t%s\\t%ct` from git log."""
    line = (text or "").splitlines()
    if not line:
        return {"hash": "", "subject": "", "at": 0}
    parts = line[0].split("\t")
    at = 0
    if len(parts) >= 3:
        try:
            at = int(parts[2])
        except ValueError:
            at = 0
    return {
        "hash": parts[0] if parts else "",
        "subject": parts[1] if len(parts) > 1 else "",
        "at": at,
    }


def run_cmd(argv, timeout):
    try:
        proc = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        return proc.returncode, proc.stdout
    except (OSError, subprocess.SubprocessError):
        return 127, ""


def gather(run, path):
    code, status = run(["git", "-C", path, "status", "--porcelain=v2", "--branch"], TIMEOUT)
    if code != 0:
        return {"ok": False, "path": path, "branch": "", "detached": False,
                "ahead": 0, "behind": 0, "dirty": 0, "untracked": 0, "conflicted": 0,
                "hash": "", "subject": "", "at": 0}
    data = parse_status(status)
    _, log = run(["git", "-C", path, "log", "-1", "--format=%h\t%s\t%ct"], TIMEOUT)
    data.update(parse_log(log))
    data["ok"] = True
    data["path"] = path
    return data


def collect(path, run=None):
    return gather(run or run_cmd, path)
