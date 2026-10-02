#!/usr/bin/env python3
"""Tests for the status sampler. Stdlib only; nothing here reaches the network.

Run from the repo root:  python3 widgets/status/test_status.py
"""

import json
import os
import sys
import tempfile
import unittest
from urllib.error import URLError

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import status

PAGE = "https://www.githubstatus.com/"

STATUSPAGE_OK = {"page": {"name": "GitHub"}, "status": {"indicator": "none", "description": "All Systems Operational"}, "incidents": [], "scheduled_maintenances": []}
STATUSPAGE_INCIDENT = {
    "page": {"name": "Cloudflare"},
    "status": {"indicator": "minor", "description": "Minor Service Outage"},
    "incidents": [
        {"name": "Dashboard errors", "status": "investigating", "impact": "major", "shortlink": "https://stspg.io/abc"},
        {"name": "Old one", "status": "monitoring", "impact": "minor"},
        {"name": "Done", "status": "resolved", "impact": "critical"},
    ],
}
STATUSPAGE_MAINTENANCE = {
    "status": {"indicator": "maintenance", "description": "Service Under Maintenance"},
    "incidents": [],
    "scheduled_maintenances": [{"name": "Database upgrade", "status": "in_progress", "shortlink": "https://stspg.io/m"},
                               {"name": "Later", "status": "scheduled"}],
}


def fetcher_for(routes):
    """A fetch() stand-in: URL -> (status, body bytes, seconds) or an exception."""
    def fetch(url, timeout=None, raw=False):
        answer = routes.get(url)
        if answer is None:
            raise URLError("no route")
        if isinstance(answer, Exception):
            raise answer
        status_code, body = answer
        if not isinstance(body, bytes):
            body = json.dumps(body).encode()
        return status_code, body, 0.042
    return fetch


class UrlTests(unittest.TestCase):
    def test_clean_url(self):
        self.assertEqual(status.clean_url("nas.local:8080"), "https://nas.local:8080")
        self.assertEqual(status.clean_url("http://192.168.0.5/health"), "http://192.168.0.5/health")
        for bad in ("", "javascript:alert(1)", "ftp://x.org", "https://user@x.org", "https://x.org/a b",
                    "https://x.org/\"", "https://-x.org", "https://x..org", "file:///etc/passwd"):
            self.assertEqual(status.clean_url(bad), "", bad)

    def test_clean_services(self):
        rows = status.clean_services(json.dumps(["github", "nope", "github", {"url": "nas.local", "name": "NAS"}, {"url": "bad url"}, 7]))
        self.assertEqual(rows, [{"id": "github"}, {"url": "https://nas.local", "kind": "http", "name": "NAS"}])
        self.assertEqual([r["id"] for r in status.clean_services(None)], status.DEFAULTS)
        self.assertEqual([r["id"] for r in status.clean_services("not json")], status.DEFAULTS)
        self.assertEqual(status.clean_services("[]"), [])
        many = status.clean_services(json.dumps(list(status.CATALOG)))
        self.assertEqual(len(many), status.MAX_SERVICES)

    def test_custom_name_defaults_to_host(self):
        rows = status.clean_services([{"url": "https://status.example.com/", "kind": "statuspage"}])
        self.assertEqual(rows[0]["name"], "status.example.com")


class AdapterTests(unittest.TestCase):
    def test_statuspage_ok(self):
        self.assertEqual(status.from_statuspage(STATUSPAGE_OK, PAGE), ("none", "All Systems Operational", PAGE))

    def test_statuspage_incident_takes_the_worse_impact(self):
        state, summary, link = status.from_statuspage(STATUSPAGE_INCIDENT, PAGE)
        self.assertEqual(state, "major")
        self.assertEqual(summary, "Dashboard errors (+1 more)")
        self.assertEqual(link, "https://stspg.io/abc")

    def test_statuspage_maintenance(self):
        state, summary, link = status.from_statuspage(STATUSPAGE_MAINTENANCE, PAGE)
        self.assertEqual(state, "maintenance")
        self.assertEqual(summary, "Maintenance: Database upgrade")
        self.assertEqual(link, "https://stspg.io/m")

    def test_statuspage_rejects_other_json(self):
        with self.assertRaises(status.FetchError):
            status.from_statuspage({"hello": 1}, PAGE)

    def test_unknown_indicator(self):
        self.assertEqual(status.from_statuspage({"status": {"indicator": "weird"}}, PAGE)[0], "unknown")

    def test_slack(self):
        self.assertEqual(status.from_slack({"status": "ok", "active_incidents": []}, "p")[0], "none")
        outage = {"status": "active", "active_incidents": [{"title": "Messages delayed", "type": "outage", "url": "https://slack-status.com/x"}]}
        self.assertEqual(status.from_slack(outage, "p"), ("major", "Messages delayed", "https://slack-status.com/x"))
        notice = {"status": "active", "active_incidents": [{"title": "Heads up", "type": "notice"}]}
        self.assertEqual(status.from_slack(notice, "p")[0], "maintenance")

    def test_heroku(self):
        green = {"status": [{"system": "Apps", "status": "green"}, {"system": "Data", "status": "green"}], "incidents": []}
        self.assertEqual(status.from_heroku(green, "p")[0], "none")
        red = {"status": [{"system": "Apps", "status": "green"}, {"system": "Data", "status": "red"}], "incidents": []}
        self.assertEqual(status.from_heroku(red, "p"), ("major", "Trouble with Data", "p"))
        incident = {"status": [{"system": "Apps", "status": "green"}], "incidents": [{"title": "Builds slow"}]}
        self.assertEqual(status.from_heroku(incident, "p")[:2], ("minor", "Builds slow"))

    def test_statusio(self):
        ok = {"result": {"status_overall": {"status": "Operational", "status_code": 100}, "incidents": []}}
        self.assertEqual(status.from_statusio(ok, "p"), ("none", "Operational", "p"))
        partial = {"result": {"status_overall": {"status": "Partial Service Disruption", "status_code": 400}, "incidents": [{"name": "CI delays"}]}}
        self.assertEqual(status.from_statusio(partial, "p")[:2], ("major", "CI delays"))
        self.assertEqual(status.from_statusio({}, "p")[0], "unknown")

    def test_gcp(self):
        page = "https://status.cloud.google.com/"
        closed = [{"end": "2026-09-01T00:00:00Z", "severity": "high"}]
        self.assertEqual(status.from_gcp(closed, page)[0], "none")
        open_ = [{"severity": "medium", "external_desc": "BigQuery errors", "uri": "incidents/abc"}, {"severity": "low"}]
        self.assertEqual(status.from_gcp(open_, page), ("major", "BigQuery errors (+1 more)", page + "incidents/abc"))
        with self.assertRaises(status.FetchError):
            status.from_gcp({"not": "a list"}, page)

    def test_aws(self):
        page = "https://health.aws.amazon.com/"
        events = [
            {"region_name": "UAE", "service_name": "Multiple services", "status": "3", "event_log": [{"status": "3"}]},
            {"region_name": "Bahrain", "service_name": "Multiple services", "status": "3", "event_log": [{"status": "2"}]},
            {"region_name": "Oregon", "service_name": "Lambda", "status": "3", "event_log": [{"status": "0"}]},
        ]
        self.assertEqual(status.from_aws(events, page), ("major", "Multiple services in UAE, Bahrain", page))
        self.assertEqual(status.from_aws([], page)[0], "none")


class CollectTests(unittest.TestCase):
    def test_collect_catalog_and_custom(self):
        fetch = fetcher_for({
            PAGE + "api/v2/summary.json": (200, STATUSPAGE_OK),
            "https://www.cloudflarestatus.com/api/v2/summary.json": (200, STATUSPAGE_INCIDENT),
            "https://nas.local:8080": (401, b"login"),
            "https://down.example": (502, b""),
        })
        services = ["github", "cloudflare", {"url": "nas.local:8080", "name": "NAS"}, {"url": "down.example"}, "claude"]
        out = status.collect(json.dumps(services), fetch)
        rows = {row["key"]: row for row in out["services"]}
        self.assertEqual(rows["github"]["state"], "none")
        self.assertEqual(rows["cloudflare"]["state"], "major")
        self.assertEqual(rows["http:https://nas.local:8080"]["state"], "none")
        self.assertEqual(rows["http:https://nas.local:8080"]["latency"], 42)
        self.assertEqual(rows["http:https://down.example"]["state"], "down")
        self.assertEqual(rows["claude"]["state"], "unknown")
        self.assertEqual(rows["claude"]["summary"], "Status page did not answer")
        self.assertEqual(out["worst"], "down")
        self.assertEqual([row["key"] for row in out["services"]][:2], ["github", "cloudflare"])

    def test_status_page_errors(self):
        fetch = fetcher_for({PAGE + "api/v2/summary.json": (404, b"")})
        row = status.collect_one({"id": "github"}, fetch)
        self.assertEqual((row["state"], row["summary"]), ("unknown", "Status page answered 404"))
        fetch = fetcher_for({PAGE + "api/v2/summary.json": (200, b"<html>")})
        row = status.collect_one({"id": "github"}, fetch)
        self.assertEqual(row["summary"], "Status page sent something unreadable")

    def test_aws_is_utf16(self):
        body = json.dumps([{"region_name": "UAE", "service_name": "EC2", "event_log": [{"status": "2"}]}]).encode("utf-16")
        fetch = fetcher_for({"https://health.aws.amazon.com/public/currentevents": (200, body)})
        row = status.collect_one({"id": "aws"}, fetch)
        self.assertEqual((row["state"], row["summary"]), ("minor", "EC2 in UAE"))

    def test_nothing_to_check(self):
        self.assertEqual(status.collect("[]", fetcher_for({})), {"ok": True, "services": [], "worst": "none"})


class ProbeTests(unittest.TestCase):
    def test_probe_finds_a_status_page(self):
        fetch = fetcher_for({"https://status.example.com/api/v2/summary.json": (200, {"page": {"name": "Example"}, "status": {"indicator": "none"}})})
        self.assertEqual(status.probe("status.example.com/whatever", fetch),
                         {"ok": True, "kind": "statuspage", "url": "https://status.example.com/", "name": "Example"})

    def test_probe_falls_back_to_a_plain_check(self):
        fetch = fetcher_for({"https://nas.local": (200, b"ok")})
        self.assertEqual(status.probe("nas.local", fetch), {"ok": True, "kind": "http", "url": "https://nas.local", "name": "nas.local"})

    def test_probe_errors(self):
        self.assertFalse(status.probe("nowhere.invalid", fetcher_for({}))["ok"])
        self.assertEqual(status.probe("javascript:alert(1)", fetcher_for({}))["error"], "That isn't a web address")


class CacheTests(unittest.TestCase):
    def test_cache_round_trip_and_expiry(self):
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "status.json")
            status.write_cache("k", {"ok": True}, 1000, path)
            self.assertEqual(status.read_cache("k", 1000 + status.CACHE_TTL, path), {"ok": True})
            self.assertIsNone(status.read_cache("k", 1000 + status.CACHE_TTL + 1, path))
            self.assertIsNone(status.read_cache("other", 1001, path))
            self.assertIsNone(status.read_cache("k", 999, path))
            self.assertIsNone(status.read_cache("k", 1000, os.path.join(folder, "missing.json")))


class CatalogTests(unittest.TestCase):
    def test_catalog_is_well_formed(self):
        for key, (name, kind, host) in status.CATALOG.items():
            self.assertRegex(key, r"^[a-z0-9]+$")
            self.assertIn(kind, ("statuspage", "slack", "heroku", "statusio", "gcp", "aws"))
            self.assertTrue(status.HOST.fullmatch(host), host)
            self.assertTrue(name)
        for key in status.DEFAULTS:
            self.assertIn(key, status.CATALOG)


if __name__ == "__main__":
    unittest.main()
