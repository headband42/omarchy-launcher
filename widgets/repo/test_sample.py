#!/usr/bin/env python3
"""Regression tests for the repo tile logic. Stdlib only.

Run from the repo root:  python3 widgets/repo/test_sample.py
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import repo


STATUS_DIRTY = """\
# branch.oid 8f3a2b1c0d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a
# branch.head main
# branch.upstream origin/main
# branch.ab +2 -1
1 .M N...100644 100644 100644 aaa bbb Menu.qml
1 M. N...100644 100644 100644 ccc ddd README.md
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

LOG = "8f3a2b1\tAdd updates widget for pending packages\t1790212917\n"


class ParseTests(unittest.TestCase):
    def test_parse_status_dirty(self):
        data = repo.parse_status(STATUS_DIRTY)
        self.assertTrue(data["ok"])
        self.assertEqual(data["branch"], "main")
        self.assertFalse(data["detached"])
        self.assertEqual(data["ahead"], 2)
        self.assertEqual(data["behind"], 1)
        self.assertEqual(data["dirty"], 3)
        self.assertEqual(data["untracked"], 2)
        self.assertEqual(data["conflicted"], 1)

    def test_parse_status_clean(self):
        data = repo.parse_status(STATUS_CLEAN)
        self.assertTrue(data["ok"])
        self.assertEqual(data["branch"], "main")
        self.assertEqual(data["ahead"], 0)
        self.assertEqual(data["dirty"], 0)

    def test_parse_status_detached(self):
        data = repo.parse_status(STATUS_DETACHED)
        self.assertTrue(data["ok"])
        self.assertTrue(data["detached"])
        self.assertEqual(data["branch"], "")

    def test_parse_status_initial(self):
        data = repo.parse_status(STATUS_INITIAL)
        self.assertTrue(data["ok"])
        self.assertEqual(data["branch"], "master")
        self.assertEqual(data["untracked"], 1)
        self.assertEqual(data["dirty"], 0)

    def test_parse_status_empty(self):
        data = repo.parse_status("")
        self.assertFalse(data["ok"])
        data = repo.parse_status("fatal: not a git repository\n")
        self.assertFalse(data["ok"])

    def test_parse_log(self):
        data = repo.parse_log(LOG)
        self.assertEqual(data["hash"], "8f3a2b1")
        self.assertEqual(data["subject"], "Add updates widget for pending packages")
        self.assertEqual(data["at"], 1790212917)

    def test_parse_log_empty(self):
        self.assertEqual(repo.parse_log(""), {"hash": "", "subject": "", "at": 0})
        self.assertEqual(repo.parse_log("abc\tsubject\tnot-a-number")["at"], 0)


class GatherTests(unittest.TestCase):
    def test_gather_repo(self):
        def run(argv, timeout):
            self.assertEqual(argv[:3], ["git", "-C", "/srv/repo"])
            if "status" in argv:
                return 0, STATUS_DIRTY
            return 0, LOG

        payload = repo.gather(run, "/srv/repo")
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["path"], "/srv/repo")
        self.assertEqual(payload["branch"], "main")
        self.assertEqual(payload["dirty"], 3)
        self.assertEqual(payload["subject"], "Add updates widget for pending packages")

    def test_gather_not_a_repo(self):
        def run(argv, timeout):
            return 128, "fatal: not a git repository\n"

        payload = repo.gather(run, "/home")
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["path"], "/home")
        self.assertEqual(payload["dirty"], 0)
        self.assertEqual(payload["subject"], "")


if __name__ == "__main__":
    unittest.main()
