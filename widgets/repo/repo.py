#!/usr/bin/env python3
"""Git status for one repository, for the launcher tile. Stdlib only.

    repo.py [--path DIR] [--fetch]
    repo.py --find

--fetch runs `git fetch` first and reports how it went in `fetch`.
--find lists the repositories under the home directory for the settings picker.
"""

import datetime
import json
import os
import subprocess
import sys
import time

TIMEOUT = 5
FETCH_TIMEOUT = 45
COMMIT_LIMIT = 8
# How far back `git log` reads for the commit list and the activity strip.
LOG_LIMIT = 1000
ACTIVITY_DAYS = 14

# --find walks this deep under $HOME and stops at these.
FIND_DEPTH = 3
FIND_LIMIT = 60
FIND_VISIT_LIMIT = 4000
FIND_SKIP = {"node_modules", "vendor", "target", "build", "dist", "venv",
             "__pycache__", "site-packages", "go", "snap", "Library"}

FIELD = "\x1f"


def empty(path):
    return {"ok": False, "path": path, "name": "", "branch": "", "detached": False,
            "upstream": "", "ahead": 0, "behind": 0, "dirty": 0, "staged": 0,
            "modified": 0, "untracked": 0, "conflicted": 0, "stash": 0,
            "hash": "", "subject": "", "at": 0, "commits": [],
            "activity": [0] * ACTIVITY_DAYS, "fetchedAt": 0}


def parse_status(text):
    """Read `git status --porcelain=v2 --branch --show-stash`."""
    out = {"ok": False, "branch": "", "detached": False, "upstream": "",
           "ahead": 0, "behind": 0, "dirty": 0, "staged": 0, "modified": 0,
           "untracked": 0, "conflicted": 0, "stash": 0}
    for line in (text or "").splitlines():
        if line.startswith("# branch.head "):
            value = line[len("# branch.head "):].strip()
            out["ok"] = True
            if value == "(detached)":
                out["detached"] = True
            else:
                out["branch"] = value
        elif line.startswith("# branch.upstream "):
            out["upstream"] = line[len("# branch.upstream "):].strip()
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
        elif line.startswith("# stash "):
            try:
                out["stash"] = int(line[len("# stash "):].strip())
            except ValueError:
                pass
        elif line.startswith("1 ") or line.startswith("2 "):
            # XY: X is the index, Y the work tree. "." is unchanged.
            xy = line[2:4]
            out["dirty"] += 1
            if xy[:1] not in (".", ""):
                out["staged"] += 1
            if xy[1:2] not in (".", ""):
                out["modified"] += 1
        elif line.startswith("u "):
            out["conflicted"] += 1
        elif line.startswith("? "):
            out["untracked"] += 1
    return out


def parse_commits(text):
    """`%h %ct %an %s`, split by the unit separator, newest first."""
    commits = []
    for line in (text or "").splitlines():
        parts = line.split(FIELD)
        if len(parts) < 4 or not parts[0]:
            continue
        try:
            at = int(parts[1])
        except ValueError:
            at = 0
        commits.append({"hash": parts[0], "at": at, "author": parts[2],
                        "subject": FIELD.join(parts[3:])})
    return commits


def activity(commits, now, days=ACTIVITY_DAYS):
    """Commits per local day, oldest first, ending today."""
    counts = [0] * days
    today = datetime.date.fromtimestamp(now)
    first = today - datetime.timedelta(days=days - 1)
    for commit in commits:
        at = commit.get("at") or 0
        if at <= 0:
            continue
        index = (datetime.date.fromtimestamp(at) - first).days
        if 0 <= index < days:
            counts[index] += 1
    return counts


def parse_dirs(text, path):
    """`rev-parse --path-format=absolute --show-toplevel --git-common-dir`."""
    lines = [line.strip() for line in (text or "").splitlines() if line.strip()]
    top = lines[0] if lines else ""
    common = lines[1] if len(lines) > 1 else ""
    if common and not os.path.isabs(common):
        common = os.path.join(path, common)
    return top, common


def run_cmd(argv, timeout, env=None):
    try:
        proc = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, env=env)
        return proc.returncode, proc.stdout, proc.stderr
    except subprocess.TimeoutExpired:
        return 124, "", "timed out"
    except (OSError, subprocess.SubprocessError) as error:
        return 127, "", str(error)


def mtime(path):
    try:
        return int(os.stat(path).st_mtime)
    except OSError:
        return 0


def gather(run, path, now=None, stat=mtime):
    now = time.time() if now is None else now
    git = ["git", "-C", path]
    code, status, _ = run(git + ["status", "--porcelain=v2", "--branch", "--show-stash"], TIMEOUT)
    if code != 0:
        return empty(path)
    data = empty(path)
    data.update(parse_status(status))
    data["ok"] = True

    _, dirs, _ = run(git + ["rev-parse", "--path-format=absolute",
                            "--show-toplevel", "--git-common-dir"], TIMEOUT)
    top, common = parse_dirs(dirs, path)
    data["name"] = os.path.basename(top.rstrip("/")) if top else os.path.basename(path.rstrip("/"))
    data["fetchedAt"] = stat(os.path.join(common, "FETCH_HEAD")) if common else 0

    # An empty repository has no HEAD yet, and log fails. That is no commits.
    _, log, _ = run(git + ["log", "-n", str(LOG_LIMIT),
                           "--format=%h%x1f%ct%x1f%an%x1f%s"], TIMEOUT)
    commits = parse_commits(log)
    data["commits"] = commits[:COMMIT_LIMIT]
    data["activity"] = activity(commits, now)
    if commits:
        data["hash"] = commits[0]["hash"]
        data["subject"] = commits[0]["subject"]
        data["at"] = commits[0]["at"]
    return data


def fetch(run, path):
    """`git fetch` that cannot stop to ask for a password."""
    env = dict(os.environ)
    env["GIT_TERMINAL_PROMPT"] = "0"
    code, _, err = run(["git", "-C", path, "fetch", "--quiet", "--prune"], FETCH_TIMEOUT, env)
    if code == 0:
        return {"ok": True, "error": ""}
    lines = [line.strip() for line in (err or "").splitlines() if line.strip()]
    message = lines[0] if lines else "fetch failed"
    for prefix in ("fatal: ", "error: "):
        if message.startswith(prefix):
            message = message[len(prefix):]
    return {"ok": False, "error": message}


def collect(path, run=None, do_fetch=False):
    run = run or run_cmd
    result = fetch(run, path) if do_fetch else None
    data = gather(run, path)
    if result is not None:
        data["fetch"] = result
        if result["ok"] and data["ok"]:
            # FETCH_HEAD can be left alone when nothing changed upstream.
            data["fetchedAt"] = max(data["fetchedAt"], int(time.time()))
    return data


def short_home(path, home):
    if home and (path == home or path.startswith(home.rstrip("/") + "/")):
        return "~" + path[len(home.rstrip("/")):]
    return path


def find_repos(home, depth=FIND_DEPTH, limit=FIND_LIMIT, visit_limit=FIND_VISIT_LIMIT):
    """Git work trees under home, most recently used first."""
    found = []
    visited = 0
    queue = [(home, 0)]
    while queue and visited < visit_limit:
        folder, level = queue.pop(0)
        visited += 1
        marker = os.path.join(folder, ".git")
        if folder != home and os.path.exists(marker):
            # The index changes on every add and commit; HEAD on every checkout.
            used = max(mtime(os.path.join(marker, "index")), mtime(os.path.join(marker, "HEAD")),
                       mtime(marker))
            found.append({"path": short_home(folder, home),
                          "name": os.path.basename(folder), "at": used})
            continue
        if level >= depth:
            continue
        try:
            entries = sorted(os.scandir(folder), key=lambda entry: entry.name.lower())
        except OSError:
            continue
        for entry in entries:
            if entry.name.startswith(".") or entry.name in FIND_SKIP:
                continue
            try:
                if entry.is_dir(follow_symlinks=False):
                    queue.append((entry.path, level + 1))
            except OSError:
                continue
    found.sort(key=lambda repo: (-repo["at"], repo["path"].lower()))
    return found[:limit]


def main(argv):
    args = argv[1:]
    home = os.path.expanduser("~")
    if "--find" in args:
        json.dump({"repos": find_repos(home)}, sys.stdout)
        sys.stdout.write("\n")
        return 0
    path = home
    if "--path" in args:
        index = args.index("--path")
        if index + 1 < len(args) and args[index + 1]:
            path = os.path.expanduser(args[index + 1])
    json.dump(collect(path, do_fetch="--fetch" in args), sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
