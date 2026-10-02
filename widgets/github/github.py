#!/usr/bin/env python3
"""Pull requests waiting on you, for the launcher tile. Stdlib only.

Everything goes through the GitHub CLI, so the tile never sees a token: one
`gh api graphql` call for the pull requests that ask for your review and the
ones you opened (with their checks, review decision, and merge conflicts), and
one `gh api notifications` call for the unread count. gh's own GH_HOST picks
GitHub Enterprise the same way it does for the CLI.

States: "ok", "missing" (no gh), "signin" (gh is not signed in), "error".
"""

import json
import shutil
import subprocess
import sys
from datetime import datetime

TIMEOUT = 20
PER_LIST = 10
NOTIFICATIONS_PAGE = 50

QUERY = """
query {
  viewer { login }
  reviews: search(query: "is:pr is:open review-requested:@me archived:false sort:updated-desc", type: ISSUE, first: %(n)d) {
    issueCount
    nodes { ...pr }
  }
  mine: search(query: "is:pr is:open author:@me archived:false sort:updated-desc", type: ISSUE, first: %(n)d) {
    issueCount
    nodes { ...pr }
  }
  assigned: search(query: "is:issue is:open assignee:@me archived:false", type: ISSUE, first: 1) {
    issueCount
  }
}
fragment pr on PullRequest {
  number title url isDraft updatedAt reviewDecision mergeable
  repository { nameWithOwner }
  author { login }
  commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
}
""" % {"n": PER_LIST}

CHECKS = {"SUCCESS": "success", "FAILURE": "failure", "ERROR": "failure", "PENDING": "pending", "EXPECTED": "pending"}
REVIEWS = {"APPROVED": "approved", "CHANGES_REQUESTED": "changes", "REVIEW_REQUIRED": "required"}
SIGNIN_HINTS = ("gh auth login", "not logged", "authentication", "401", "bad credentials")


def run(argv, timeout=TIMEOUT):
    """(returncode, stdout, stderr) of argv; 127 when it cannot run."""
    if not shutil.which(argv[0]):
        return 127, "", ""
    try:
        proc = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError) as error:
        return 1, "", str(error)
    return proc.returncode, proc.stdout, proc.stderr


def epoch(value):
    try:
        return int(datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp())
    except ValueError:
        return None


def text(value, limit=160):
    return " ".join(str(value or "").split())[:limit]


def checks_of(node):
    try:
        state = node["commits"]["nodes"][0]["commit"]["statusCheckRollup"]["state"]
    except (KeyError, IndexError, TypeError):
        return ""
    return CHECKS.get(str(state), "")


def pull(node):
    """One pull request in the tile's shape, or None for a search hit that is not one."""
    if not isinstance(node, dict) or not node.get("url") or node.get("number") is None:
        return None
    url = str(node["url"])
    if not url.startswith("https://"):
        return None
    return {
        "number": int(node["number"]),
        "title": text(node.get("title")),
        "url": url,
        "repo": text((node.get("repository") or {}).get("nameWithOwner"), 80),
        "author": text((node.get("author") or {}).get("login"), 40),
        "draft": bool(node.get("isDraft")),
        "updated": epoch(node.get("updatedAt")),
        "checks": checks_of(node),
        "review": REVIEWS.get(str(node.get("reviewDecision") or ""), ""),
        "conflict": node.get("mergeable") == "CONFLICTING",
    }


def section(data, key):
    block = (data or {}).get(key) or {}
    items = [p for p in (pull(n) for n in block.get("nodes") or []) if p]
    try:
        count = int(block.get("issueCount"))
    except (TypeError, ValueError):
        count = len(items)
    return {"count": max(count, len(items)), "items": items}


def failure(stderr):
    lower = (stderr or "").lower()
    if any(hint in lower for hint in SIGNIN_HINTS):
        return "signin", "Sign in with gh auth login"
    line = next((l.strip() for l in (stderr or "").splitlines() if l.strip()), "")
    return "error", text(line, 120) or "gh did not answer"


def collect(runner=run):
    out = {"ok": True, "state": "ok", "error": "", "login": "", "reviews": {"count": 0, "items": []},
           "mine": {"count": 0, "items": []}, "assigned": 0, "notifications": 0, "moreNotifications": False}
    code, stdout, stderr = runner(["gh", "api", "graphql", "-f", "query=" + QUERY])
    if code == 127:
        out.update(state="missing", error="Install the GitHub CLI (gh)")
        return out
    if code != 0:
        state, message = failure(stderr)
        out.update(state=state, error=message)
        return out
    try:
        payload = json.loads(stdout)
    except ValueError:
        out.update(state="error", error="gh sent something unreadable")
        return out
    data = payload.get("data") if isinstance(payload, dict) else None
    if not isinstance(data, dict):
        errors = payload.get("errors") if isinstance(payload, dict) else None
        message = text((errors or [{}])[0].get("message"), 120) if isinstance(errors, list) and errors else ""
        out.update(state="error", error=message or "GitHub sent no data")
        return out
    out["login"] = text((data.get("viewer") or {}).get("login"), 40)
    out["reviews"] = section(data, "reviews")
    out["mine"] = section(data, "mine")
    try:
        out["assigned"] = int((data.get("assigned") or {}).get("issueCount") or 0)
    except (TypeError, ValueError):
        out["assigned"] = 0
    code, stdout, _ = runner(["gh", "api", "notifications?per_page=%d" % NOTIFICATIONS_PAGE])
    if code == 0:
        try:
            unread = json.loads(stdout)
            if isinstance(unread, list):
                out["notifications"] = len(unread)
                out["moreNotifications"] = len(unread) >= NOTIFICATIONS_PAGE
        except ValueError:
            pass
    return out


def main():
    json.dump(collect(), sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
