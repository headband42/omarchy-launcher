#!/usr/bin/env python3
"""Regression tests for the repo tile logic. Stdlib only.

Run from the repo root:  python3 widgets/repo/test_repo.py
"""

import datetime
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import repo


STATUS_DIRTY = """\
# branch.oid 8f3a2b1c0d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a
# branch.head main
# branch.upstream origin/main
# branch.ab +2 -1
# stash 3
1 .M N...100644 100644 100644 aaa bbb Menu.qml
1 M. N...100644 100644 100644 ccc ddd README.md
1 MM N...100644 100644 100644 ccc ddd Both.md
2 R. N...100644 100644 100644 eee fff R100 new.txt\told.txt
? untracked.txt
? another.txt
u UU N...100644 100644 100644 111 222 conflict.txt
"""

STATUS_CLEAN = """\
# branch.oid 8f3a2b1c0d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a
# branch.head main
# branch.upstream origin/main
# branch.ab +0 -0
"""

STATUS_DETACHED = """\
# branch.oid 8f3a2b1c0d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a
# branch.head (detached)
"""

STATUS_INITIAL = """\
# branch.oid (initial)
# branch.head master
? README.md
"""

NOW = 1790212917
S = repo.FIELD
LOG = (f"8f3a2b1{S}{NOW - 60}{S}Ana{S}Add updates widget for pending packages\n"
       f"7e6d5c4{S}{NOW - 86400}{S}Ana{S}Use a{S}separator in a subject\n"
       f"6d5c4b3{S}{NOW - 30 * 86400}{S}Bo{S}Old work\n")


def local_noon(days_ago):
    """A timestamp at local noon, so day buckets do not depend on the hour."""
    day = datetime.date.fromtimestamp(NOW) - datetime.timedelta(days=days_ago)
    return int(time.mktime(day.timetuple())) + 12 * 3600


class ParseTests(unittest.TestCase):
    def test_parse_status_dirty(self):
        data = repo.parse_status(STATUS_DIRTY)
        self.assertTrue(data["ok"])
        self.assertEqual(data["branch"], "main")
        self.assertEqual(data["upstream"], "origin/main")
        self.assertFalse(data["detached"])
        self.assertEqual(data["ahead"], 2)
        self.assertEqual(data["behind"], 1)
        self.assertEqual(data["dirty"], 4)
        self.assertEqual(data["staged"], 3)
        self.assertEqual(data["modified"], 2)
        self.assertEqual(data["untracked"], 2)
        self.assertEqual(data["conflicted"], 1)
        self.assertEqual(data["stash"], 3)

    def test_parse_status_clean(self):
        data = repo.parse_status(STATUS_CLEAN)
        self.assertTrue(data["ok"])
        self.assertEqual(data["branch"], "main")
        self.assertEqual(data["ahead"], 0)
        self.assertEqual(data["dirty"], 0)
        self.assertEqual(data["stash"], 0)

    def test_parse_status_detached(self):
        data = repo.parse_status(STATUS_DETACHED)
        self.assertTrue(data["ok"])
        self.assertTrue(data["detached"])
        self.assertEqual(data["branch"], "")
        self.assertEqual(data["upstream"], "")

    def test_parse_status_initial(self):
        data = repo.parse_status(STATUS_INITIAL)
        self.assertTrue(data["ok"])
        self.assertEqual(data["branch"], "master")
        self.assertEqual(data["untracked"], 1)
        self.assertEqual(data["dirty"], 0)

    def test_parse_status_empty(self):
        self.assertFalse(repo.parse_status("")["ok"])
        self.assertFalse(repo.parse_status("fatal: not a git repository\n")["ok"])

    def test_parse_commits(self):
        commits = repo.parse_commits(LOG)
        self.assertEqual(len(commits), 3)
        self.assertEqual(commits[0], {"hash": "8f3a2b1", "at": NOW - 60, "author": "Ana",
                                      "subject": "Add updates widget for pending packages"})
        self.assertEqual(commits[1]["subject"], f"Use a{S}separator in a subject")

    def test_parse_commits_skips_garbage(self):
        self.assertEqual(repo.parse_commits(""), [])
        self.assertEqual(repo.parse_commits("fatal: bad\n"), [])
        commits = repo.parse_commits(f"abc{S}nope{S}A{S}subject\n")
        self.assertEqual(commits[0]["at"], 0)

    def test_activity_buckets_by_local_day(self):
        commits = [{"at": local_noon(0)}, {"at": local_noon(0)}, {"at": local_noon(1)},
                   {"at": local_noon(13)}, {"at": local_noon(14)}, {"at": 0}]
        counts = repo.activity(commits, NOW)
        self.assertEqual(len(counts), repo.ACTIVITY_DAYS)
        self.assertEqual(counts[-1], 2)
        self.assertEqual(counts[-2], 1)
        self.assertEqual(counts[0], 1)
        self.assertEqual(sum(counts), 4)

    def test_parse_dirs(self):
        self.assertEqual(repo.parse_dirs("/srv/app\n/srv/app/.git\n", "/srv/app"),
                         ("/srv/app", "/srv/app/.git"))
        self.assertEqual(repo.parse_dirs("/srv/app\n.git\n", "/srv/app"),
                         ("/srv/app", "/srv/app/.git"))
        self.assertEqual(repo.parse_dirs("", "/srv/app"), ("", ""))


class GatherTests(unittest.TestCase):
    def fake(self, status=(0, STATUS_DIRTY), log=(0, LOG)):
        calls = []

        def run(argv, timeout, env=None):
            calls.append(argv)
            self.assertEqual(argv[:3], ["git", "-C", "/srv/repo"])
            if "status" in argv:
                return status[0], status[1], ""
            if "rev-parse" in argv:
                return 0, "/srv/repo\n/srv/repo/.git\n", ""
            if "log" in argv:
                return log[0], log[1], ""
            if "fetch" in argv:
                self.assertEqual(env.get("GIT_TERMINAL_PROMPT"), "0")
                return self.fetch_answer
            raise AssertionError(argv)
        run.calls = calls
        return run

    def test_gather_repo(self):
        stats = {}

        def stat(path):
            stats["path"] = path
            return NOW - 3600

        payload = repo.gather(self.fake(), "/srv/repo", now=NOW, stat=stat)
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["path"], "/srv/repo")
        self.assertEqual(payload["name"], "repo")
        self.assertEqual(payload["branch"], "main")
        self.assertEqual(payload["dirty"], 4)
        self.assertEqual(payload["hash"], "8f3a2b1")
        self.assertEqual(payload["subject"], "Add updates widget for pending packages")
        self.assertEqual(len(payload["commits"]), 3)
        self.assertEqual(sum(payload["activity"]), 2)
        self.assertEqual(payload["fetchedAt"], NOW - 3600)
        self.assertEqual(stats["path"], "/srv/repo/.git/FETCH_HEAD")

    def test_gather_keeps_commit_list_short(self):
        log = "".join(f"h{i}{S}{NOW - i}{S}A{S}s{i}\n" for i in range(30))
        payload = repo.gather(self.fake(log=(0, log)), "/srv/repo", now=NOW, stat=lambda p: 0)
        self.assertEqual(len(payload["commits"]), repo.COMMIT_LIMIT)
        self.assertEqual(payload["activity"][-1], 30)

    def test_gather_empty_repository(self):
        payload = repo.gather(self.fake(status=(0, STATUS_INITIAL),
                                        log=(128, "")), "/srv/repo", now=NOW, stat=lambda p: 0)
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["commits"], [])
        self.assertEqual(payload["hash"], "")
        self.assertEqual(payload["activity"], [0] * repo.ACTIVITY_DAYS)

    def test_gather_not_a_repo(self):
        def run(argv, timeout, env=None):
            return 128, "", "fatal: not a git repository\n"

        payload = repo.gather(run, "/home", now=NOW)
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["path"], "/home")
        self.assertEqual(payload["dirty"], 0)
        self.assertEqual(payload["commits"], [])

    def test_fetch_reports_the_error(self):
        run = self.fake()
        self.fetch_answer = (128, "", "fatal: could not read Username for 'https://github.com'\n")
        self.assertEqual(repo.fetch(run, "/srv/repo"),
                         {"ok": False, "error": "could not read Username for 'https://github.com'"})
        self.fetch_answer = (1, "", "")
        self.assertEqual(repo.fetch(run, "/srv/repo"), {"ok": False, "error": "fetch failed"})
        self.fetch_answer = (0, "", "")
        self.assertEqual(repo.fetch(run, "/srv/repo"), {"ok": True, "error": ""})


class FindTests(unittest.TestCase):
    def test_find_repos(self):
        home = tempfile.mkdtemp()
        try:
            for path in ["src/app/.git", "src/app/vendor/lib/.git", "notes/.git",
                         ".hidden/secret/.git", "a/b/c/d/deep/.git", "node_modules/pkg/.git"]:
                os.makedirs(os.path.join(home, path))
            os.utime(os.path.join(home, "notes/.git"), (NOW, NOW))
            os.utime(os.path.join(home, "src/app/.git"), (NOW - 100, NOW - 100))
            found = repo.find_repos(home)
            self.assertEqual([r["path"] for r in found], ["~/notes", "~/src/app"])
            self.assertEqual(found[1]["name"], "app")
            self.assertEqual(len(repo.find_repos(home, limit=1)), 1)
        finally:
            shutil.rmtree(home)


@unittest.skipUnless(shutil.which("git"), "git is not installed")
class RealGitTests(unittest.TestCase):
    """The parsers against the git this machine actually has."""

    def git(self, *args):
        env = dict(os.environ, GIT_AUTHOR_NAME="T", GIT_AUTHOR_EMAIL="t@example.com",
                   GIT_COMMITTER_NAME="T", GIT_COMMITTER_EMAIL="t@example.com",
                   GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1")
        subprocess.run(["git", "-C", self.path] + list(args), check=True, env=env,
                       capture_output=True)

    def setUp(self):
        self.path = tempfile.mkdtemp()
        self.git("init", "-q", "-b", "main")

    def tearDown(self):
        shutil.rmtree(self.path)

    def write(self, name, text):
        with open(os.path.join(self.path, name), "w") as handle:
            handle.write(text)

    def test_collect_real_repo(self):
        payload = repo.collect(self.path)
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["branch"], "main")
        self.assertEqual(payload["commits"], [])

        self.write("a.txt", "one\n")
        self.git("add", "a.txt")
        self.git("commit", "-q", "-m", "First")
        self.write("a.txt", "two\n")
        self.write("b.txt", "new\n")
        self.git("stash", "push", "-q", "-m", "keep")
        self.write("a.txt", "three\n")
        self.write("c.txt", "staged\n")
        self.git("add", "c.txt")
        self.write("u.txt", "untracked\n")

        payload = repo.collect(self.path)
        self.assertEqual(payload["name"], os.path.basename(self.path))
        self.assertEqual(payload["staged"], 1)
        self.assertEqual(payload["modified"], 1)
        self.assertEqual(payload["untracked"], 2)
        self.assertEqual(payload["stash"], 1)
        self.assertEqual(payload["subject"], "First")
        self.assertEqual(payload["activity"][-1], 1)
        self.assertEqual(payload["fetchedAt"], 0)
        self.assertNotIn("fetch", payload)


if __name__ == "__main__":
    unittest.main()
