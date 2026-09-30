#!/usr/bin/env python3
"""Regression tests for the docker tile logic. Stdlib only.

Run from the repo root:  python3 widgets/docker/test_sample.py
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import docker


PS = """\
{"Names": "web", "State": "running", "Status": "Up 2 hours", "Image": "nginx"}
{"Names": "db", "State": "running", "Status": "Up 5 minutes (unhealthy)", "Image": "postgres"}
{"Names": "cache,cache-alias", "State": "exited", "Status": "Exited (0) 3 days ago", "Image": "redis"}
{"Names": "batch", "State": "exited", "Status": "Exited (1) 1 hour ago", "Image": "alpine"}
{"Names": "sleepy", "State": "paused", "Status": "Up 6 minutes (Paused)", "Image": "alpine"}
"""


class ParseTests(unittest.TestCase):
    def test_parse_rows(self):
        rows = docker.parse_rows(PS)
        self.assertEqual(len(rows), 5)
        self.assertEqual(rows[0]["Names"], "web")

    def test_parse_rows_skips_garbage(self):
        rows = docker.parse_rows("not json\n\n[1, 2]\n{\"Names\": \"ok\", \"State\": \"running\"}\n")
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["Names"], "ok")
        self.assertEqual(docker.parse_rows(""), [])
        self.assertEqual(docker.parse_rows("{}\nextra"), [{}])


class SummarizeTests(unittest.TestCase):
    def test_counts_and_order(self):
        summary = docker.summarize(docker.parse_rows(PS))
        self.assertEqual(summary["running"], 2)
        self.assertEqual(summary["stopped"], 3)
        self.assertEqual(summary["unhealthy"], 1)
        names = [row["name"] for row in summary["rows"]]
        self.assertEqual(names, ["db", "web", "batch", "cache"])
        self.assertTrue(summary["rows"][0]["unhealthy"])
        self.assertTrue(summary["rows"][1]["running"])
        self.assertFalse(summary["rows"][2]["running"])

    def test_row_limit_and_names(self):
        summary = docker.summarize(docker.parse_rows(PS), limit=2)
        self.assertEqual(len(summary["rows"]), 2)
        rows = docker.parse_rows('{"Names": "cache,cache-alias", "State": "exited", "Status": "Exited (0)"}')
        self.assertEqual(docker.summarize(rows)["rows"][0]["name"], "cache")

    def test_empty(self):
        summary = docker.summarize([])
        self.assertEqual(summary, {"running": 0, "stopped": 0, "unhealthy": 0, "rows": []})


class GatherTests(unittest.TestCase):
    def run_fake(self, answers):
        def run(argv, timeout):
            return answers[tuple(argv)]
        return run

    def test_gather_rows(self):
        payload = docker.gather(self.run_fake({
            ("omarchy-sudo-docker",): (1, ""),
            ("docker", "ps", "-a", "--format", "{{json .}}"): (0, PS),
        }))
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["mode"], "rows")
        self.assertEqual(payload["running"], 2)
        self.assertEqual(payload["unhealthy"], 1)

    def test_gather_needs_sudo(self):
        payload = docker.gather(self.run_fake({
            ("omarchy-sudo-docker",): (0, ""),
            ("docker", "--version"): (0, "Docker version 27.0.0\n"),
        }))
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["mode"], "sudo")

    def test_gather_missing_client(self):
        payload = docker.gather(self.run_fake({
            ("omarchy-sudo-docker",): (0, ""),
            ("docker", "--version"): (127, ""),
        }))
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["mode"], "missing")

    def test_gather_daemon_error(self):
        payload = docker.gather(self.run_fake({
            ("omarchy-sudo-docker",): (1, ""),
            ("docker", "ps", "-a", "--format", "{{json .}}"): (1, ""),
        }))
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["mode"], "error")


if __name__ == "__main__":
    unittest.main()
