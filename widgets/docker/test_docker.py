#!/usr/bin/env python3
"""Regression tests for the docker tile logic. Stdlib only.

Run from the repo root:  python3 widgets/docker/test_docker.py
"""

import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import docker


PS = """\
{"ID": "w1", "Names": "web", "State": "running", "Status": "Up 2 hours", "Image": "nginx:latest", "Labels": "com.docker.compose.project=site,com.docker.compose.service=web", "Ports": "0.0.0.0:8080->80/tcp, [::]:8080->80/tcp"}
{"ID": "d1", "Names": "db", "State": "running", "Status": "Up 5 minutes (unhealthy)", "Image": "postgres:16", "Labels": "com.docker.compose.project=site", "Ports": "5432/tcp"}
{"ID": "c1", "Names": "cache,cache-alias", "State": "exited", "Status": "Exited (0) 3 days ago", "Image": "redis", "Labels": ""}
{"ID": "b1", "Names": "batch", "State": "exited", "Status": "Exited (1) About an hour ago", "Image": "ghcr.io/acme/batch@sha256:abc", "Labels": ""}
{"ID": "s1", "Names": "sleepy", "State": "paused", "Status": "Up 6 minutes (Paused)", "Image": "alpine", "Labels": ""}
"""

STATS = """\
{"Name": "web", "CPUPerc": "1.50%", "MemUsage": "20MiB / 31.2GiB"}
{"Name": "db", "CPUPerc": "10.25%", "MemUsage": "1.5GiB / 31.2GiB"}
"""

UNITS_RUNNING = "LoadState=loaded\nActiveState=active\n\nLoadState=loaded\nActiveState=active\n"
UNITS_IDLE = "LoadState=loaded\nActiveState=inactive\n\nLoadState=loaded\nActiveState=active\n"
UNITS_STOPPED = "LoadState=loaded\nActiveState=inactive\n\nLoadState=loaded\nActiveState=inactive\n"
UNITS_NONE = "LoadState=not-found\nActiveState=inactive\n\nLoadState=not-found\nActiveState=inactive\n"


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

    def test_daemon_state(self):
        state = lambda text: docker.daemon_state(docker.parse_units(text))
        self.assertEqual(state(UNITS_RUNNING), "running")
        self.assertEqual(state(UNITS_IDLE), "idle")
        self.assertEqual(state(UNITS_STOPPED), "stopped")
        self.assertEqual(state(UNITS_NONE), "")
        self.assertEqual(state(""), "")
        self.assertEqual(state("LoadState=loaded\nActiveState=activating\n"), "running")

    def test_count_scopes(self):
        text = "docker-0a1b.scope loaded active running libcontainer container 0a1b\n" \
               "docker-9f8e.scope loaded active running libcontainer container 9f8e\n"
        self.assertEqual(docker.count_scopes(text), 2)
        self.assertEqual(docker.count_scopes(""), 0)

    def test_short_duration(self):
        self.assertEqual(docker.short_duration("Up 2 hours"), "2h")
        self.assertEqual(docker.short_duration("Up About a minute"), "1m")
        self.assertEqual(docker.short_duration("Up About an hour (healthy)"), "1h")
        self.assertEqual(docker.short_duration("Up Less than a second"), "now")
        self.assertEqual(docker.short_duration("Exited (0) 3 weeks ago"), "3w")
        self.assertEqual(docker.short_duration("Up 4 months"), "4mo")
        self.assertEqual(docker.short_duration("Up 45 seconds"), "45s")
        self.assertEqual(docker.short_duration("Created"), "")

    def test_describe(self):
        self.assertEqual(docker.describe("running", "Up 2 hours"), ("up 2h", "", "ok"))
        self.assertEqual(docker.describe("running", "Up 2 hours (healthy)"), ("up 2h", "healthy", "ok"))
        self.assertEqual(docker.describe("running", "Up 5 minutes (unhealthy)"), ("unhealthy", "unhealthy", "bad"))
        self.assertEqual(docker.describe("running", "Up 3 seconds (health: starting)"), ("starting", "starting", "warn"))
        self.assertEqual(docker.describe("exited", "Exited (0) 3 days ago"), ("exited 3d", "", "off"))
        self.assertEqual(docker.describe("exited", "Exited (137) About an hour ago"), ("exit 137 · 1h", "", "bad"))
        self.assertEqual(docker.describe("paused", "Up 6 minutes (Paused)"), ("paused", "", "warn"))
        self.assertEqual(docker.describe("restarting", "Restarting (1) 5 seconds ago"), ("restarting", "", "bad"))
        self.assertEqual(docker.describe("created", "Created"), ("created", "", "off"))
        self.assertEqual(docker.describe("", "Removal In Progress"), ("removal in progress", "", "off"))

    def test_short_image(self):
        self.assertEqual(docker.short_image("nginx:latest"), "nginx")
        self.assertEqual(docker.short_image("postgres:16"), "postgres:16")
        self.assertEqual(docker.short_image("ghcr.io/immich-app/immich-server:release"), "immich-server:release")
        self.assertEqual(docker.short_image("localhost:5000/app:1.0"), "app:1.0")
        self.assertEqual(docker.short_image("ghcr.io/acme/batch@sha256:abc"), "batch")
        self.assertEqual(docker.short_image("sha256:0123456789abcdef0123"), "0123456789ab")
        self.assertEqual(docker.short_image(""), "")

    def test_label_and_ports(self):
        labels = "com.docker.compose.project=site,com.docker.compose.service=web"
        self.assertEqual(docker.label(labels, "com.docker.compose.project"), "site")
        self.assertEqual(docker.label(labels, "missing"), "")
        self.assertEqual(docker.host_ports("0.0.0.0:8080->80/tcp, [::]:8080->80/tcp, 0.0.0.0:443->443/tcp"),
                         ["8080", "443"])
        self.assertEqual(docker.host_ports("5432/tcp"), [])

    def test_sizes_and_stats(self):
        self.assertEqual(docker.parse_size("20MiB"), 20 * 2**20)
        self.assertEqual(docker.parse_size("1.5GiB"), int(1.5 * 2**30))
        self.assertEqual(docker.parse_size("512kB"), 512000)
        self.assertEqual(docker.parse_size("0B"), 0)
        self.assertEqual(docker.parse_size("--"), 0)
        self.assertEqual(docker.parse_percent("10.25%"), 10.25)
        self.assertEqual(docker.parse_percent("--"), 0.0)
        stats = docker.parse_stats(STATS)
        self.assertEqual(stats["web"], {"cpu": 1.5, "mem": 20 * 2**20})
        self.assertEqual(stats["db"]["cpu"], 10.25)


class SummarizeTests(unittest.TestCase):
    def test_counts_and_order(self):
        summary = docker.summarize(docker.parse_rows(PS), docker.parse_stats(STATS))
        self.assertEqual(summary["running"], 2)
        self.assertEqual(summary["paused"], 1)
        self.assertEqual(summary["stopped"], 2)
        self.assertEqual(summary["unhealthy"], 1)
        self.assertEqual(summary["cpu"], 11.8)
        self.assertEqual(summary["mem"], 20 * 2**20 + int(1.5 * 2**30))
        names = [row["name"] for row in summary["rows"]]
        # Trouble, then running by project, then paused, then the rest.
        self.assertEqual(names, ["batch", "db", "web", "sleepy", "cache"])

    def test_row_fields(self):
        rows = docker.summarize(docker.parse_rows(PS), docker.parse_stats(STATS))["rows"]
        web = rows[2]
        self.assertEqual(web["id"], "w1")
        self.assertEqual(web["image"], "nginx")
        self.assertEqual(web["project"], "site")
        self.assertEqual(web["ports"], ["8080"])
        self.assertEqual(web["short"], "up 2h")
        self.assertEqual(web["cpu"], 1.5)
        self.assertTrue(web["running"])
        self.assertEqual(rows[4]["name"], "cache")
        self.assertIsNone(rows[4]["cpu"])
        self.assertTrue(rows[1]["unhealthy"])

    def test_row_limit(self):
        summary = docker.summarize(docker.parse_rows(PS), limit=2)
        self.assertEqual(len(summary["rows"]), 2)
        self.assertEqual(summary["stopped"], 2)

    def test_empty(self):
        summary = docker.summarize([])
        self.assertEqual(summary["rows"], [])
        self.assertEqual(summary["running"], 0)
        self.assertEqual(summary["cpu"], 0.0)


class GatherTests(unittest.TestCase):
    def run_fake(self, answers, calls=None):
        def run(argv, timeout):
            if calls is not None:
                calls.append(tuple(argv))
            answer = answers.get(tuple(argv))
            if answer is None:
                raise AssertionError("unexpected command: %r" % (argv,))
            return answer if len(answer) == 3 else (answer[0], answer[1], "")
        return run

    def base(self, units=UNITS_RUNNING, sudo=1):
        return {
            tuple(docker.VERSION): (0, "Docker version 28.0.0\n"),
            tuple(docker.UNITS): (0, units),
            tuple(docker.SUDO_CHECK): (sudo, ""),
        }

    def test_gather_rows(self):
        answers = self.base()
        answers[tuple(docker.PS)] = (0, PS)
        answers[tuple(docker.STATS)] = (0, STATS)
        payload = docker.gather(self.run_fake(answers), env={})
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["mode"], "rows")
        self.assertEqual(payload["daemon"], "running")
        self.assertEqual(payload["running"], 2)
        self.assertEqual(payload["unhealthy"], 1)
        self.assertEqual(payload["cpu"], 11.8)

    def test_gather_skips_stats_with_nothing_running(self):
        answers = self.base()
        answers[tuple(docker.PS)] = (0, '{"ID": "c1", "Names": "cache", "State": "exited", "Status": "Exited (0) 1 day ago"}')
        calls = []
        payload = docker.gather(self.run_fake(answers, calls), env={})
        self.assertTrue(payload["ok"])
        self.assertNotIn(tuple(docker.STATS), calls)

    def test_gather_survives_failed_stats(self):
        answers = self.base()
        answers[tuple(docker.PS)] = (0, PS)
        answers[tuple(docker.STATS)] = (1, "")
        payload = docker.gather(self.run_fake(answers), env={})
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["cpu"], 0.0)
        self.assertIsNone(payload["rows"][0]["cpu"])

    def test_gather_needs_sudo(self):
        answers = self.base(units=UNITS_IDLE, sudo=0)
        answers[tuple(docker.SUDO_CONFIGURED)] = (0, "")
        calls = []
        payload = docker.gather(self.run_fake(answers, calls), env={})
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["mode"], "sudo")
        self.assertEqual(payload["daemon"], "idle")
        self.assertFalse(payload["pendingLogin"])
        self.assertEqual(payload["scoped"], 0)
        self.assertNotIn(tuple(docker.PS), calls)
        self.assertNotIn(tuple(docker.SCOPES), calls)

    def test_gather_needs_sudo_with_running_daemon(self):
        answers = self.base(units=UNITS_RUNNING, sudo=0)
        answers[tuple(docker.SUDO_CONFIGURED)] = (1, "")
        answers[tuple(docker.SCOPES)] = (0, "docker-0a1b.scope loaded active running c\n")
        payload = docker.gather(self.run_fake(answers), env={})
        self.assertEqual(payload["mode"], "sudo")
        self.assertTrue(payload["pendingLogin"])
        self.assertEqual(payload["scoped"], 1)

    def test_gather_does_not_wake_an_idle_daemon(self):
        calls = []
        payload = docker.gather(self.run_fake(self.base(units=UNITS_IDLE), calls), env={})
        self.assertEqual(payload["mode"], "idle")
        self.assertNotIn(tuple(docker.PS), calls)

    def test_gather_stopped_daemon(self):
        calls = []
        payload = docker.gather(self.run_fake(self.base(units=UNITS_STOPPED), calls), env={})
        self.assertEqual(payload["mode"], "stopped")
        # A stopped daemon has no socket, which reads as "needs sudo". It is not.
        self.assertNotIn(tuple(docker.SUDO_CHECK), calls)

    def test_gather_remote_host_skips_systemd(self):
        answers = {tuple(docker.VERSION): (0, ""), tuple(docker.PS): (0, PS), tuple(docker.STATS): (0, STATS)}
        calls = []
        payload = docker.gather(self.run_fake(answers, calls), env={"DOCKER_HOST": "tcp://nas:2375"})
        self.assertEqual(payload["mode"], "rows")
        self.assertNotIn(tuple(docker.UNITS), calls)
        self.assertNotIn(tuple(docker.SUDO_CHECK), calls)

    def test_gather_without_systemd_unit_asks_docker(self):
        answers = self.base(units=UNITS_NONE)
        answers[tuple(docker.PS)] = (0, "")
        payload = docker.gather(self.run_fake(answers), env={})
        self.assertEqual(payload["mode"], "rows")
        self.assertEqual(payload["daemon"], "running")

    def test_gather_missing_client(self):
        payload = docker.gather(self.run_fake({tuple(docker.VERSION): (127, "")}), env={})
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["mode"], "missing")

    def test_gather_daemon_error(self):
        answers = self.base()
        answers[tuple(docker.PS)] = (1, "")
        payload = docker.gather(self.run_fake(answers), env={})
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["mode"], "error")


class ActionTests(unittest.TestCase):
    def test_act_runs_the_action(self):
        calls = []

        def run(argv, timeout):
            calls.append(argv)
            return 0, "w1\n", ""

        self.assertEqual(docker.act(run, "restart", "w1"),
                         {"ok": True, "action": "restart", "id": "w1", "error": ""})
        self.assertEqual(calls, [["docker", "restart", "w1"]])

    def test_act_reports_the_daemon_error(self):
        def run(argv, timeout):
            return 1, "", "Error response from daemon: No such container: w9\n"

        result = docker.act(run, "start", "w9")
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"], "No such container: w9")

    def test_act_refuses_anything_else(self):
        def run(argv, timeout):
            raise AssertionError("must not run")

        self.assertFalse(docker.act(run, "rm", "w1")["ok"])
        self.assertFalse(docker.act(run, "stop", "--all")["ok"])
        self.assertFalse(docker.act(run, "stop", "a b")["ok"])
        self.assertFalse(docker.act(run, "stop", "")["ok"])

    def test_main_prints_one_object(self):
        # With no flags, main() is the sampler: one JSON object on stdout.
        import io
        out = io.StringIO()
        saved = sys.stdout, docker.run_cmd
        try:
            sys.stdout = out
            docker.run_cmd = lambda argv, timeout: (127, "", "")
            docker.main(["docker.py"])
        finally:
            sys.stdout, docker.run_cmd = saved
        self.assertEqual(json.loads(out.getvalue())["mode"], "missing")


if __name__ == "__main__":
    unittest.main()
