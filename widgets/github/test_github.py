#!/usr/bin/env python3
"""Tests for the GitHub sampler. Stdlib only; gh is never run.

Run from the repo root:  python3 widgets/github/test_github.py
"""

import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import github


def node(number, checks="SUCCESS", review="APPROVED", mergeable="MERGEABLE", draft=False, url=None):
    return {
        "number": number, "title": "  PR   %d  " % number, "url": url or "https://github.com/o/r/pull/%d" % number,
        "isDraft": draft, "updatedAt": "2026-10-01T12:00:00Z", "reviewDecision": review, "mergeable": mergeable,
        "repository": {"nameWithOwner": "o/r"}, "author": {"login": "dev"},
        "commits": {"nodes": [{"commit": {"statusCheckRollup": {"state": checks} if checks else None}}]},
    }


GRAPHQL = {"data": {
    "viewer": {"login": "octocat"},
    "reviews": {"issueCount": 12, "nodes": [node(1, "FAILURE", "REVIEW_REQUIRED"), {}]},
    "mine": {"issueCount": 2, "nodes": [node(2, "PENDING", "CHANGES_REQUESTED", "CONFLICTING"), node(3, None, None, "UNKNOWN", True)]},
    "assigned": {"issueCount": 4},
}}


class Runner:
    def __init__(self, answers):
        self.answers = answers
        self.calls = []

    def __call__(self, argv, timeout=None):
        self.calls.append(argv)
        key = "graphql" if "graphql" in argv else "notifications"
        return self.answers.get(key, (0, "[]", ""))


class CollectTests(unittest.TestCase):
    def test_full_sample(self):
        runner = Runner({"graphql": (0, json.dumps(GRAPHQL), ""), "notifications": (0, json.dumps([{}] * 3), "")})
        out = github.collect(runner)
        self.assertEqual(out["state"], "ok")
        self.assertEqual(out["login"], "octocat")
        self.assertEqual(out["reviews"]["count"], 12)
        self.assertEqual(len(out["reviews"]["items"]), 1)
        first = out["reviews"]["items"][0]
        self.assertEqual((first["title"], first["checks"], first["review"], first["repo"], first["author"]), ("PR 1", "failure", "required", "o/r", "dev"))
        mine = out["mine"]["items"]
        self.assertEqual((mine[0]["checks"], mine[0]["review"], mine[0]["conflict"]), ("pending", "changes", True))
        self.assertEqual((mine[1]["checks"], mine[1]["review"], mine[1]["draft"]), ("", "", True))
        self.assertEqual(mine[0]["updated"], 1790856000)
        self.assertEqual(out["assigned"], 4)
        self.assertEqual((out["notifications"], out["moreNotifications"]), (3, False))
        self.assertEqual(runner.calls[1], ["gh", "api", "notifications?per_page=50"])

    def test_a_full_page_of_notifications_says_more(self):
        runner = Runner({"graphql": (0, json.dumps(GRAPHQL), ""), "notifications": (0, json.dumps([{}] * 50), "")})
        self.assertTrue(github.collect(runner)["moreNotifications"])

    def test_notifications_failing_leaves_the_rest(self):
        runner = Runner({"graphql": (0, json.dumps(GRAPHQL), ""), "notifications": (1, "", "boom")})
        out = github.collect(runner)
        self.assertEqual((out["state"], out["notifications"]), ("ok", 0))

    def test_missing_gh(self):
        out = github.collect(Runner({"graphql": (127, "", "")}))
        self.assertEqual(out["state"], "missing")

    def test_signed_out(self):
        stderr = "To get started with GitHub CLI, please run:  gh auth login\n"
        self.assertEqual(github.collect(Runner({"graphql": (4, "", stderr)}))["state"], "signin")
        self.assertEqual(github.collect(Runner({"graphql": (1, "", "HTTP 401: Bad credentials")}))["state"], "signin")

    def test_other_errors(self):
        out = github.collect(Runner({"graphql": (1, "", "\nerror connecting to api.github.com\n")}))
        self.assertEqual((out["state"], out["error"]), ("error", "error connecting to api.github.com"))
        out = github.collect(Runner({"graphql": (0, "not json", "")}))
        self.assertEqual(out["state"], "error")
        out = github.collect(Runner({"graphql": (0, json.dumps({"errors": [{"message": "Something went wrong"}]}), "")}))
        self.assertEqual((out["state"], out["error"]), ("error", "Something went wrong"))

    def test_a_link_that_is_not_https_is_dropped(self):
        self.assertIsNone(github.pull(node(9, url="javascript:alert(1)")))
        self.assertIsNone(github.pull({"number": 1}))

    def test_query_asks_for_open_unarchived_pull_requests(self):
        self.assertIn("review-requested:@me archived:false", github.QUERY)
        self.assertIn("author:@me archived:false", github.QUERY)
        self.assertIn("first: %d" % github.PER_LIST, github.QUERY)


class PathTests(unittest.TestCase):
    def test_search_path_adds_user_installs_once(self):
        home = os.path.expanduser("~")
        path = github.search_path({"PATH": "/usr/bin:" + home + "/.local/bin"}).split(os.pathsep)
        self.assertEqual(path[:2], ["/usr/bin", home + "/.local/bin"])
        self.assertEqual(path.count(home + "/.local/bin"), 1)
        self.assertIn(home + "/.local/share/mise/shims", path)
        self.assertIn("/usr/local/bin", github.search_path({}).split(os.pathsep))


if __name__ == "__main__":
    unittest.main()
