import io
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

import opencode
import sample

NOW = datetime(2026, 9, 28, 17, 38, tzinfo=timezone.utc)

# The console's own reply, with the values it really sends: a $12 five-hour
# block, $30 for the week, $60 for the month, which is the documented
# 20% / 50% / 100% split of the monthly limit.
STATUS = {
    "subscriberUserId": "acc_TESTaccount",
    "product": "go",
    "renewalProduct": "go",
    "paymentMethodId": "payment_method_test",
    "renewalCurrency": "usd",
    "useBalance": False,
    "cancelAtPeriodEnd": False,
    "renewalPending": False,
    "access": {
        "startsAt": "2026-09-26T02:39:51.000Z",
        "endsAt": "2026-10-26T02:39:51.000Z",
        "cancelAtPeriodEnd": False,
        "meters": {
            "fiveHour": {
                "startsAt": "2026-09-28T16:42:55.562Z",
                "resetsAt": "2026-09-28T21:42:55.562Z",
                "limitMicroCents": "1200000000",
                "usedMicroCents": "0",
            },
            "week": {
                "startsAt": "2026-09-28T00:00:00.000Z",
                "resetsAt": "2026-10-05T00:00:00.000Z",
                "limitMicroCents": "3000000000",
                "usedMicroCents": "0",
            },
            "month": {
                "resetsAt": "2026-10-26T02:39:51.000Z",
                "limitMicroCents": "6000000000",
                "usedMicroCents": "0",
            },
        },
    },
    "upgradePrice": {"amountMicroCents": "3000000000", "currency": "usd"},
}


def used_meter(limit, used, **kwargs):
    row = {"limitMicroCents": str(limit), "usedMicroCents": str(used)}
    row.update(kwargs)
    return row


def status_with(meters, **access):
    payload = json.loads(json.dumps(STATUS))
    payload["access"]["meters"] = meters
    payload["access"].update(access)
    return payload


def fake_db(token="tok_abc123", org="wrk_testorg", accounts=1):
    """A throwaway database shaped like OpenCode's."""
    handle, path = tempfile.mkstemp(suffix=".db")
    os.close(handle)
    os.unlink(path)
    connection = sqlite3.connect(path)
    connection.execute("create table account (id text, email text, url text, "
                      "access_token text, refresh_token text, token_expiry integer, "
                      "time_created integer, time_updated integer)")
    connection.execute("create table account_state (id integer, active_account_id text, "
                      "active_org_id text)")
    for index in range(accounts):
        connection.execute(
            "insert into account values (?,?,?,?,?,?,?,?)",
            ("acc_%d" % index, "a@b.c", "https://opencode.ai/console",
             token if index == accounts - 1 else "tok_old", "r", 0, index, index))
    connection.execute("insert into account_state values (?,?,?)", (1, "acc_0", org))
    connection.commit()
    connection.close()
    return path


class MoneyTest(unittest.TestCase):
    def test_micro_cents_are_a_hundred_thousandth_of_a_dollar(self):
        # Pinned to the console's own numbers, because getting this wrong
        # would show $12 as $1200 and nothing else would look wrong.
        self.assertEqual(opencode.dollars("1200000000"), 12.0)
        self.assertEqual(opencode.dollars("3000000000"), 30.0)
        self.assertEqual(opencode.dollars("6000000000"), 60.0)
        self.assertEqual(opencode.dollars("0"), 0.0)
        self.assertEqual(opencode.dollars("125000000"), 1.25)
        self.assertIsNone(opencode.dollars(None))
        self.assertIsNone(opencode.dollars(""))
        self.assertIsNone(opencode.dollars("abc"))

    def test_percent_is_used_over_limit(self):
        self.assertEqual(opencode.percent_of({"usedMicroCents": "600000000",
                                              "limitMicroCents": "1200000000"}), 50.0)
        self.assertEqual(opencode.percent_of({"usedMicroCents": "0",
                                              "limitMicroCents": "1200000000"}), 0.0)
        # Over the limit is a real state and is not clamped away.
        self.assertAlmostEqual(
            opencode.percent_of({"usedMicroCents": "1300000000",
                                 "limitMicroCents": "1200000000"}), 108.33, places=1)
        for bad in ({"usedMicroCents": "1", "limitMicroCents": "0"},
                    {"usedMicroCents": "1", "limitMicroCents": "-5"},
                    {"usedMicroCents": "1"},
                    {"limitMicroCents": "100"},
                    {}):
            self.assertIsNone(opencode.percent_of(bad), bad)


class CountdownTest(unittest.TestCase):
    def test_a_reset_is_counted_down_in_the_form_the_tile_shows(self):
        self.assertEqual(opencode.countdown(0), "now")
        self.assertEqual(opencode.countdown(-5), "now")
        self.assertEqual(opencode.countdown(45), "45s")
        self.assertEqual(opencode.countdown(90), "1m")
        self.assertEqual(opencode.countdown(600), "10m")
        self.assertEqual(opencode.countdown(3600), "1h")
        self.assertEqual(opencode.countdown(3600 + 14 * 60), "1h 14m")
        self.assertEqual(opencode.countdown(86400), "1d")
        self.assertEqual(opencode.countdown(86400 + 9 * 3600 + 1800), "1d 09h")
        self.assertEqual(opencode.countdown(27 * 86400 + 9 * 3600), "27d 09h")
        self.assertEqual(opencode.countdown(None), "now")

    def test_a_reset_is_named_by_calendar_when_it_is_not_today(self):
        self.assertEqual(opencode.day_stamp(datetime(2026, 9, 28, 21, 42, tzinfo=timezone.utc), NOW),
                         "today 9:42 pm")
        self.assertEqual(opencode.day_stamp(datetime(2026, 9, 29, 8, 0, tzinfo=timezone.utc), NOW),
                         "tomorrow")
        self.assertEqual(opencode.day_stamp(datetime(2026, 10, 3, 8, 0, tzinfo=timezone.utc), NOW),
                         "sat")
        self.assertEqual(opencode.day_stamp(datetime(2026, 10, 26, 2, 39, tzinfo=timezone.utc), NOW),
                         "Oct 26")
        self.assertEqual(opencode.day_stamp(None, NOW), "")

    def test_stamps_survive_the_shapes_the_console_sends(self):
        self.assertEqual(opencode.parse_stamp("2026-10-05T00:00:00.000Z"),
                         datetime(2026, 10, 5, 0, 0, tzinfo=timezone.utc))
        self.assertEqual(opencode.parse_stamp("2026-09-28T21:42:55.562+00:00"),
                         datetime(2026, 9, 28, 21, 42, 55, 562000, tzinfo=timezone.utc))
        self.assertIsNone(opencode.parse_stamp("later"))
        self.assertIsNone(opencode.parse_stamp(""))


class MeterTest(unittest.TestCase):
    def test_a_block_arrives_with_its_share_used_and_when_it_resets(self):
        payload = opencode.parse_status(STATUS, NOW)
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["plan"], "OpenCode Go")
        self.assertTrue(payload["active"])
        self.assertFalse(payload["canceling"])
        self.assertEqual(payload["currency"], "USD")
        self.assertEqual(payload["upgrade"], 30.0)
        self.assertEqual([m["id"] for m in payload["meters"]], ["fiveHour", "week", "month"])
        first = payload["meters"][0]
        self.assertEqual(first["label"], "5-HOUR")
        self.assertEqual(first["limit"], 12.0)
        self.assertEqual(first["used"], 0.0)
        self.assertEqual(first["percent"], 0.0)
        self.assertFalse(first["near"])
        self.assertFalse(first["expired"])
        self.assertTrue(first["resetsAt"].startswith("2026-09-28T21:42:55"))
        self.assertTrue(first["startsAt"])
        # The documented split shows up in the limits themselves.
        self.assertEqual([m["limit"] for m in payload["meters"]], [12.0, 30.0, 60.0])

    def test_the_soonest_block_is_named_as_the_worst(self):
        payload = opencode.parse_status(status_with({
            "fiveHour": used_meter(1200000000, 12000000, resetsAt="2026-09-28T21:00:00Z"),
            "week": used_meter(3000000000, 2520000000, resetsAt="2026-10-05T00:00:00Z"),
            "month": used_meter(6000000000, 60000000, resetsAt="2026-10-26T00:00:00Z"),
        }), NOW)
        self.assertEqual(payload["worst"]["id"], "week")
        self.assertAlmostEqual(payload["worst"]["percent"], 84.0, places=1)
        self.assertTrue(payload["worst"]["near"])
        # A block near its ceiling is polled faster.
        self.assertEqual(payload["pollMs"], opencode.POLL_BUSY_MS)

        # The worst is the fullest, not the first: a nearly spent monthly
        # block outranks a nearly spent five-hour one.
        payload = opencode.parse_status(status_with({
            "fiveHour": used_meter(1200000000, 1140000000, resetsAt="2026-09-28T21:00:00Z"),
            "week": used_meter(3000000000, 30000000, resetsAt="2026-10-05T00:00:00Z"),
            "month": used_meter(6000000000, 0, resetsAt="2026-10-26T00:00:00Z"),
        }), NOW)
        self.assertEqual(payload["worst"]["id"], "fiveHour")

    def test_going_over_the_limit_is_shown_as_over(self):
        payload = opencode.parse_status(status_with({
            "fiveHour": used_meter(1200000000, 1260000000, resetsAt="2026-09-28T21:00:00Z"),
            "week": used_meter(3000000000, 0, resetsAt="2026-10-05T00:00:00Z"),
            "month": used_meter(6000000000, 0, resetsAt="2026-10-26T00:00:00Z"),
        }), NOW)
        first = payload["meters"][0]
        self.assertTrue(first["over"])
        self.assertTrue(first["near"])
        self.assertGreater(first["percent"], 100.0)

    def test_an_expired_block_says_now(self):
        payload = opencode.parse_status(status_with({
            "fiveHour": used_meter(1200000000, 0, resetsAt="2026-09-28T00:00:00Z"),
        }), NOW)
        meter = payload["meters"][0]
        self.assertTrue(meter["expired"])
        self.assertEqual(meter["resetCountdown"], "now")
        self.assertLessEqual(meter["resetsInSeconds"], 0)

    def test_a_quiet_account_polls_slowly(self):
        payload = opencode.parse_status(status_with({
            "fiveHour": used_meter(1200000000, 0, resetsAt="2026-09-28T21:00:00Z"),
            "week": used_meter(3000000000, 0, resetsAt="2026-10-05T00:00:00Z"),
            "month": used_meter(6000000000, 0, resetsAt="2026-10-26T00:00:00Z"),
        }), NOW)
        self.assertEqual(payload["pollMs"], opencode.POLL_MS)

    def test_a_block_the_console_did_not_send_is_left_out(self):
        # No usage and no block are different things, so a missing block is
        # dropped rather than drawn as a full bar of nothing.
        payload = opencode.parse_status(status_with({
            "fiveHour": used_meter(1200000000, 0, resetsAt="2026-09-28T21:00:00Z"),
        }), NOW)
        self.assertEqual([m["id"] for m in payload["meters"]], ["fiveHour"])
        payload = opencode.parse_status(status_with({}), NOW)
        self.assertFalse(payload["ok"])
        self.assertIn("No Go usage blocks", payload["error"])

    def test_an_unheard_of_block_is_still_shown(self):
        payload = opencode.parse_status(status_with({
            "fiveHour": used_meter(1200000000, 0, resetsAt="2026-09-28T21:00:00Z"),
            "decade": used_meter(100000000, 0, resetsAt="2026-09-29T21:00:00Z"),
        }), NOW)
        self.assertEqual([m["id"] for m in payload["meters"]], ["fiveHour", "decade"])
        self.assertEqual(payload["meters"][1]["label"], "decade")

    def test_junk_meters_are_dropped(self):
        for junk in (None, 7, "x", [], {}):
            self.assertIsNone(opencode.parse_meter("fiveHour", junk, NOW))

    def test_renewal_is_counted_down_too(self):
        payload = opencode.parse_status(STATUS, NOW)
        self.assertEqual(payload["renewalDay"], "Oct 26")
        self.assertEqual(payload["renewsCountdown"], "27d 09h")
        self.assertTrue(payload["endsAt"].startswith("2026-10-26T02:39:51"))

    def test_a_cancelling_subscription_is_not_called_active(self):
        self.assertTrue(opencode.parse_status(STATUS, NOW)["active"])
        cancelled = json.loads(json.dumps(STATUS))
        cancelled["access"]["cancelAtPeriodEnd"] = True
        again = opencode.parse_status(cancelled, NOW)
        self.assertTrue(again["canceling"])
        self.assertFalse(again["active"])

    def test_go_plus_is_named_differently(self):
        payload = json.loads(json.dumps(STATUS))
        payload["renewalProduct"] = "go-plus"
        self.assertEqual(opencode.parse_status(payload, NOW)["plan"], "OpenCode Go Plus")
        payload["renewalProduct"] = "go_plus"
        self.assertEqual(opencode.parse_status(payload, NOW)["plan"], "OpenCode Go Plus")
        self.assertEqual(opencode.plan_name("go", "go"), "OpenCode Go")
        self.assertEqual(opencode.plan_name("", ""), "OpenCode Go")

    def test_use_balance_is_passed_through(self):
        payload = json.loads(json.dumps(STATUS))
        payload["useBalance"] = True
        self.assertTrue(opencode.parse_status(payload, NOW)["useBalance"])

    def test_a_reply_with_no_access_is_drawn_not_raised(self):
        for bad in ({}, None, 7, [], {"access": None}, {"access": 7}, {"access": {}},
                    {"access": {"meters": None}}, {"access": {"meters": []}}):
            payload = opencode.parse_status(bad, NOW)
            self.assertFalse(payload["ok"], bad)
            self.assertTrue(payload["error"])
            self.assertEqual(payload["meters"], [])

    def test_every_view_carries_the_keys_the_tile_reads(self):
        for payload in (opencode.parse_status(STATUS, NOW),
                        opencode.error_view("gone", NOW)):
            for key in ("ok", "product", "plan", "active", "canceling", "renewalPending",
                        "useBalance", "endsAt", "startsAt", "renewsInSeconds",
                        "renewsCountdown", "renewalDay", "currency", "upgrade",
                        "meters", "worst", "error", "pollMs"):
                self.assertIn(key, payload)


class DatabaseTest(unittest.TestCase):
    def test_the_token_and_org_come_out_of_the_database(self):
        path = fake_db()
        try:
            found = opencode.credentials(path)
            self.assertEqual(found["token"], "tok_abc123")
            self.assertEqual(found["org"], "wrk_testorg")
            self.assertEqual(found["db"], path)
        finally:
            os.unlink(path)

    def test_the_most_recently_updated_account_wins(self):
        path = fake_db(accounts=3)
        try:
            self.assertEqual(opencode.credentials(path)["token"], "tok_abc123")
        finally:
            os.unlink(path)

    def test_a_signed_out_install_has_no_account(self):
        path = fake_db(token="", org="")
        try:
            self.assertIsNone(opencode.credentials(path))
        finally:
            os.unlink(path)

    def test_a_database_without_the_tables_is_not_fatal(self):
        handle, path = tempfile.mkstemp(suffix=".db")
        os.close(handle)
        try:
            self.assertIsNone(opencode.credentials(path))
        finally:
            os.unlink(path)

    def test_a_missing_database_is_not_fatal(self):
        self.assertIsNone(opencode.credentials("/nonexistent/opencode.db"))

    def test_the_read_never_writes(self):
        path = fake_db()
        try:
            before = os.path.getmtime(path)
            opencode.credentials(path)
            self.assertEqual(os.path.getmtime(path), before)
        finally:
            os.unlink(path)

    def test_the_search_order_follows_opencodes_own(self):
        with patch.dict(os.environ, {"OPENCODE_DB": "/tmp/a.db", "XDG_DATA_HOME": "/tmp/x"}, clear=False):
            self.assertEqual(opencode.db_candidates()[:2], ["/tmp/a.db", "/tmp/x/opencode/opencode.db"])
        with patch.dict(os.environ, {"XDG_DATA_HOME": "/tmp/x"}, clear=True):
            paths = opencode.db_candidates()
            self.assertEqual(len(paths), 2)
            self.assertTrue(paths[0].endswith("/tmp/x/opencode/opencode.db"))
            self.assertTrue(paths[1].endswith("/.local/share/opencode/opencode.db"))


class RequestGuardTest(unittest.TestCase):
    def test_only_the_console_status_call_is_allowed(self):
        self.assertTrue(opencode.allowed_url(opencode.STATUS_URL))
        for bad in ("http://opencode.ai/console/api/go/status",
                    "https://evil.example/console/api/go/status",
                    "https://opencode.ai.evil.example/console/api/go/status",
                    "https://opencode.ai/console/api/usage/summary",
                    "https://opencode.ai/console/api/go/cancel",
                    "https://opencode.ai/",
                    "file:///etc/passwd",
                    "", None, 7):
            self.assertEqual(opencode.allowed_url(bad), "", str(bad))

    def test_the_guard_runs_before_the_request(self):
        with patch("opencode.urlopen") as opener:
            with self.assertRaises(ValueError):
                opencode.fetch_json("https://evil.example/x", "tok", "wrk")
        opener.assert_not_called()

    def test_the_request_carries_the_token_and_the_org(self):
        seen = {}

        class FakeResponse:
            def __init__(self, payload):
                self.payload = json.dumps(payload).encode()

            def read(self, limit):
                return self.payload

            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

        def opener(request, timeout=None):
            seen["url"] = request.full_url
            seen["auth"] = request.get_header("Authorization")
            seen["org"] = request.get_header("X-org-id")
            return FakeResponse(STATUS)

        payload = opencode.fetch_json(opencode.STATUS_URL, "tok_abc", "wrk_1", opener=opener)
        self.assertEqual(seen["url"], opencode.STATUS_URL)
        self.assertIn("tok_abc", seen["auth"])
        self.assertEqual(seen["org"], "wrk_1")
        self.assertTrue(payload["access"])

    def test_an_oversized_reply_is_refused(self):
        class Big:
            def read(self, limit):
                return b"x" * (opencode.MAX_BYTES + 1)

            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

        with self.assertRaises(OSError):
            opencode.fetch_json(opencode.STATUS_URL, "t", "o", opener=lambda *a, **k: Big())


class CollectTest(unittest.TestCase):
    def fake_account(self, token="tok_abc", org="wrk_1"):
        return {"token": token, "org": org, "db": "/tmp/opencode.db"}

    def test_a_signed_in_account_becomes_a_payload(self):
        seen = {}

        def fetch(url, token, org):
            seen["token"] = token
            seen["org"] = org
            return STATUS

        with patch.object(opencode, "credentials", return_value=self.fake_account()):
            payload = opencode.collect(NOW, fetch=fetch)
        self.assertTrue(payload["ok"])
        self.assertEqual(seen["token"], "tok_abc")
        self.assertEqual(seen["org"], "wrk_1")
        self.assertEqual(len(payload["meters"]), 3)

    def test_no_account_is_drawn_rather_than_raised(self):
        with patch.object(opencode, "credentials", return_value=None):
            payload = opencode.collect(NOW, fetch=lambda *a: STATUS)
        self.assertFalse(payload["ok"])
        self.assertIn("account", payload["error"])
        self.assertEqual(payload["meters"], [])

    def test_an_expired_sign_in_says_so(self):
        for raised in (OSError("HTTP Error 401: Unauthorized"),
                       OSError("forbidden"),
                       PermissionError("403")):
            with patch.object(opencode, "credentials", return_value=self.fake_account()):
                payload = opencode.collect(NOW, fetch=lambda *a, e=raised: (_ for _ in ()).throw(e))
            self.assertFalse(payload["ok"])
            self.assertIn("expired", payload["error"].lower())

    def test_a_network_failure_is_drawn_rather_than_raised(self):
        for raised in (OSError("offline"), TimeoutError("slow"), RuntimeError("boom"),
                       ValueError("bad json")):
            with patch.object(opencode, "credentials", return_value=self.fake_account()):
                payload = opencode.collect(NOW, fetch=lambda *a, e=raised: (_ for _ in ()).throw(e))
            self.assertFalse(payload["ok"])
            self.assertTrue(payload["error"])
            self.assertEqual(payload["meters"], [])

    def test_the_shipped_path_reads_the_real_console(self):
        # The one test that talks to the console, and it only reads.
        payload = opencode.collect(NOW)
        self.assertTrue(payload["ok"], payload["error"])
        self.assertEqual(payload["plan"], "OpenCode Go")
        self.assertEqual([m["id"] for m in payload["meters"]], ["fiveHour", "week", "month"])
        # The documented 20 / 50 / 100 split of the monthly limit.
        self.assertAlmostEqual(payload["meters"][0]["limit"], payload["meters"][2]["limit"] * 0.2)
        self.assertAlmostEqual(payload["meters"][1]["limit"], payload["meters"][2]["limit"] * 0.5)


class SampleTest(unittest.TestCase):
    def test_sample_passes_the_payload_through(self):
        output = io.StringIO()
        with patch("sample.opencode.collect", return_value={"ok": True}) as collect:
            with redirect_stdout(output):
                result = sample.main(["sample.py"])
        self.assertEqual(result, 0)
        collect.assert_called_once()
        self.assertTrue(json.loads(output.getvalue())["ok"])

    def test_sample_survives_a_raising_collector(self):
        output = io.StringIO()
        with patch("sample.opencode.collect", side_effect=RuntimeError("no route")):
            with redirect_stdout(output):
                result = sample.main(["sample.py"])
        self.assertEqual(result, 0)
        payload = json.loads(output.getvalue())
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["error"], "no route")

    def test_the_catalog_is_empty_but_present(self):
        output = io.StringIO()
        with redirect_stdout(output):
            sample.main(["sample.py", "--catalog"])
        self.assertEqual(json.loads(output.getvalue())["rows"], [])


class CatalogWiringTest(unittest.TestCase):
    def test_the_launcher_finds_this_widget(self):
        here = os.path.dirname(os.path.abspath(__file__))
        widgets = os.path.dirname(here)
        script = os.path.join(os.path.dirname(widgets), "scripts", "list-widgets.py")
        rows = subprocess.run([sys.executable, script, widgets],
                              capture_output=True, text=True, timeout=30, check=True).stdout
        found = {row["id"]: row for row in json.loads(rows)}
        self.assertIn("opencode", found)
        row = found["opencode"]
        self.assertTrue(row["qml"].endswith("/widgets/opencode/Widget.qml"))
        self.assertTrue(row["settingsQml"].endswith("/widgets/opencode/Settings.qml"))
        self.assertTrue(os.path.isfile(row["qml"]))
        self.assertTrue(os.path.isfile(row["settingsQml"]))
        self.assertEqual(row["name"], "OpenCode")
        self.assertTrue(row["defaultUrl"].startswith("https://opencode.ai"))
        self.assertTrue(row["defaultLabel"])
        self.assertTrue(row["icon"])
        self.assertTrue(row["description"])


if __name__ == "__main__":
    unittest.main()
