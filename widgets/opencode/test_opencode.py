import io
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from datetime import datetime, timezone
from unittest.mock import patch
from urllib.error import HTTPError

import opencode



def ms(*args):
    return int(datetime(*args, tzinfo=timezone.utc).timestamp() * 1000)

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


def fake_db(token="tok_abc123", org="wrk_testorg", accounts=1, active=None, tokens=None):
    """A throwaway database shaped like OpenCode's.

    The active account is the latest one unless told otherwise; `tokens`
    names each account's token when they must differ.
    """
    handle, path = tempfile.mkstemp(suffix=".db")
    os.close(handle)
    os.unlink(path)
    if active is None:
        active = accounts - 1
    connection = sqlite3.connect(path)
    connection.execute("create table account (id text, email text, url text, "
                      "access_token text, refresh_token text, token_expiry integer, "
                      "time_created integer, time_updated integer)")
    connection.execute("create table account_state (id integer, active_account_id text, "
                      "active_org_id text)")
    for index in range(accounts):
        if tokens is not None:
            value = tokens[index]
        else:
            value = token if index == accounts - 1 else "tok_old"
        connection.execute(
            "insert into account values (?,?,?,?,?,?,?,?)",
            ("acc_%d" % index, "a@b.c", "https://opencode.ai/console",
             value, "r", 0, index, index))
    connection.execute("insert into account_state values (?,?,?)", (1, "acc_%d" % active, org))
    connection.commit()
    connection.close()
    return path


class MoneyTest(unittest.TestCase):
    def test_micro_cents_are_a_hundred_millionth_of_a_dollar(self):
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


# The countdown and calendar day live in widgets/_kit/usage.js now.
class StampTest(unittest.TestCase):
    def test_stamps_survive_the_shapes_the_console_sends(self):
        self.assertEqual(opencode.parse_stamp("2026-10-05T00:00:00.000Z"),
                         datetime(2026, 10, 5, 0, 0, tzinfo=timezone.utc))
        self.assertEqual(opencode.parse_stamp("2026-09-28T21:42:55.562+00:00"),
                         datetime(2026, 9, 28, 21, 42, 55, 562000, tzinfo=timezone.utc))
        self.assertIsNone(opencode.parse_stamp("later"))
        self.assertIsNone(opencode.parse_stamp(""))

    def test_stamps_go_out_as_epoch_milliseconds(self):
        self.assertEqual(opencode.epoch_ms("2026-10-05T00:00:00.000Z"), ms(2026, 10, 5))
        self.assertEqual(opencode.epoch_ms("2026-09-28T21:42:55.562Z"),
                         ms(2026, 9, 28, 21, 42, 55) + 562)
        self.assertIsNone(opencode.epoch_ms(None))
        self.assertIsNone(opencode.epoch_ms("soon"))


class MeterTest(unittest.TestCase):
    def test_a_block_arrives_with_its_share_used_and_when_it_resets(self):
        payload = opencode.parse_status(STATUS)
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
        self.assertFalse(first["idle"])
        self.assertEqual(first["resetsAtMs"], ms(2026, 9, 28, 21, 42, 55) + 562)
        self.assertEqual(first["startsAtMs"], ms(2026, 9, 28, 16, 42, 55) + 562)
        self.assertIsNone(payload["meters"][2]["startsAtMs"])
        # The documented split shows up in the limits themselves.
        self.assertEqual([m["limit"] for m in payload["meters"]], [12.0, 30.0, 60.0])

    def test_a_block_near_its_ceiling_polls_faster(self):
        payload = opencode.parse_status(status_with({
            "fiveHour": used_meter(1200000000, 12000000, resetsAt="2026-09-28T21:00:00Z"),
            "week": used_meter(3000000000, 2520000000, resetsAt="2026-10-05T00:00:00Z"),
            "month": used_meter(6000000000, 60000000, resetsAt="2026-10-26T00:00:00Z"),
        }))
        week = payload["meters"][1]
        self.assertAlmostEqual(week["percent"], 84.0, places=1)
        self.assertTrue(week["near"])
        self.assertEqual(payload["pollMs"], opencode.POLL_BUSY_MS)

    def test_going_over_the_limit_is_shown_as_over(self):
        payload = opencode.parse_status(status_with({
            "fiveHour": used_meter(1200000000, 1260000000, resetsAt="2026-09-28T21:00:00Z"),
            "week": used_meter(3000000000, 0, resetsAt="2026-10-05T00:00:00Z"),
            "month": used_meter(6000000000, 0, resetsAt="2026-10-26T00:00:00Z"),
        }))
        first = payload["meters"][0]
        self.assertTrue(first["over"])
        self.assertTrue(first["near"])
        self.assertGreater(first["percent"], 100.0)

    def test_a_block_with_no_window_yet_is_idle(self):
        # The console leaves resetsAt out until the first request of a
        # rolling window. That is "starts with the next request", not "now".
        payload = opencode.parse_status(status_with({
            "fiveHour": used_meter(1200000000, 0),
            "week": used_meter(3000000000, 0, resetsAt="2026-10-05T00:00:00Z"),
        }))
        self.assertTrue(payload["meters"][0]["idle"])
        self.assertIsNone(payload["meters"][0]["resetsAtMs"])
        self.assertFalse(payload["meters"][1]["idle"])

    def test_a_quiet_account_polls_slowly(self):
        payload = opencode.parse_status(status_with({
            "fiveHour": used_meter(1200000000, 0, resetsAt="2026-09-28T21:00:00Z"),
            "week": used_meter(3000000000, 0, resetsAt="2026-10-05T00:00:00Z"),
            "month": used_meter(6000000000, 0, resetsAt="2026-10-26T00:00:00Z"),
        }))
        self.assertEqual(payload["pollMs"], opencode.POLL_MS)

    def test_a_block_the_console_did_not_send_is_left_out(self):
        # No usage and no block are different things, so a missing block is
        # dropped rather than drawn as a full bar of nothing.
        payload = opencode.parse_status(status_with({
            "fiveHour": used_meter(1200000000, 0, resetsAt="2026-09-28T21:00:00Z"),
        }))
        self.assertEqual([m["id"] for m in payload["meters"]], ["fiveHour"])
        payload = opencode.parse_status(status_with({}))
        self.assertFalse(payload["ok"])
        self.assertIn("No Go usage blocks", payload["error"])
        self.assertEqual(payload["reason"], "plan")

    def test_an_unheard_of_block_is_still_shown(self):
        payload = opencode.parse_status(status_with({
            "fiveHour": used_meter(1200000000, 0, resetsAt="2026-09-28T21:00:00Z"),
            "decade": used_meter(100000000, 0, resetsAt="2026-09-29T21:00:00Z"),
        }))
        self.assertEqual([m["id"] for m in payload["meters"]], ["fiveHour", "decade"])
        self.assertEqual(payload["meters"][1]["label"], "decade")

    def test_junk_meters_are_dropped(self):
        for junk in (None, 7, "x", [], {}):
            self.assertIsNone(opencode.parse_meter("fiveHour", junk))

    def test_the_plan_period_goes_out_too(self):
        payload = opencode.parse_status(STATUS)
        self.assertEqual(payload["endsAtMs"], ms(2026, 10, 26, 2, 39, 51))
        self.assertEqual(payload["startsAtMs"], ms(2026, 9, 26, 2, 39, 51))

    def test_a_cancelling_subscription_is_not_called_active(self):
        self.assertTrue(opencode.parse_status(STATUS)["active"])
        cancelled = json.loads(json.dumps(STATUS))
        cancelled["access"]["cancelAtPeriodEnd"] = True
        again = opencode.parse_status(cancelled)
        self.assertTrue(again["canceling"])
        self.assertFalse(again["active"])
        # The top level carries the same flag, and it counts the same way.
        top = json.loads(json.dumps(STATUS))
        top["cancelAtPeriodEnd"] = True
        sided = opencode.parse_status(top)
        self.assertTrue(sided["canceling"])
        self.assertFalse(sided["active"])

    def test_go_plus_is_named_differently(self):
        payload = json.loads(json.dumps(STATUS))
        payload["renewalProduct"] = "go-plus"
        self.assertEqual(opencode.parse_status(payload)["plan"], "OpenCode Go Plus")
        payload["renewalProduct"] = "go_plus"
        self.assertEqual(opencode.parse_status(payload)["plan"], "OpenCode Go Plus")
        self.assertEqual(opencode.plan_name("go", "go"), "OpenCode Go")
        self.assertEqual(opencode.plan_name("", ""), "OpenCode Go")

    def test_use_balance_is_passed_through(self):
        payload = json.loads(json.dumps(STATUS))
        payload["useBalance"] = True
        self.assertTrue(opencode.parse_status(payload)["useBalance"])

    def test_a_reply_with_no_access_is_drawn_not_raised(self):
        for bad in ({}, None, 7, [], {"access": None}, {"access": 7}, {"access": {}},
                    {"access": {"meters": None}}, {"access": {"meters": []}}):
            payload = opencode.parse_status(bad)
            self.assertFalse(payload["ok"], bad)
            self.assertTrue(payload["error"])
            self.assertEqual(payload["meters"], [])

    def test_every_view_carries_the_keys_the_tile_reads(self):
        for payload in (opencode.parse_status(STATUS),
                        opencode.error_view("gone")):
            for key in ("ok", "reason", "product", "plan", "active", "canceling", "renewalPending",
                        "useBalance", "endsAtMs", "startsAtMs", "currency", "upgrade",
                        "meters", "error", "pollMs"):
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

    def test_the_active_account_beats_the_latest_update(self):
        # Two sign-ins: the active one is older, and its token is the one
        # that belongs with the active org.
        path = fake_db(accounts=3, active=0,
                       tokens=["tok_active", "tok_mid", "tok_newest"])
        try:
            self.assertEqual(opencode.credentials(path)["token"], "tok_active")
        finally:
            os.unlink(path)

    def test_the_most_recently_updated_account_is_the_fallback(self):
        # An active account that is gone leaves the latest update to win.
        path = fake_db(accounts=3, active=9)
        try:
            self.assertEqual(opencode.credentials(path)["token"], "tok_abc123")
        finally:
            os.unlink(path)

    def test_a_long_token_is_not_trimmed(self):
        # Secrets are never displayed, so no display width applies to them.
        path = fake_db(token="t" * 1000)
        try:
            found = opencode.credentials(path)
            self.assertEqual(len(found["token"]), 1000)
        finally:
            os.unlink(path)

    def test_a_database_without_an_active_account_column_still_reads(self):
        handle, path = tempfile.mkstemp(suffix=".db")
        os.close(handle)
        os.unlink(path)
        connection = sqlite3.connect(path)
        connection.execute("create table account (id text, access_token text, "
                          "time_updated integer)")
        connection.execute("insert into account values (?,?,?)", ("acc_0", "tok_legacy", 1))
        connection.execute("create table account_state (id integer, active_org_id text)")
        connection.execute("insert into account_state values (?,?)", (1, "wrk_legacy"))
        connection.commit()
        connection.close()
        try:
            found = opencode.credentials(path)
            self.assertEqual(found["token"], "tok_legacy")
            self.assertEqual(found["org"], "wrk_legacy")
        finally:
            os.unlink(path)

    def test_a_path_with_uri_characters_still_opens(self):
        directory = tempfile.mkdtemp()
        path = fake_db()
        try:
            odd = os.path.join(directory, "open?code#1.db")
            os.rename(path, odd)
            path = odd
            found = opencode.credentials(odd)
            self.assertEqual(found["token"], "tok_abc123")
            self.assertEqual(found["db"], odd)
        finally:
            os.unlink(path)
            os.rmdir(directory)

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
        self.assertEqual(opencode.allowed_url(opencode.STATUS_URL), opencode.STATUS_URL)
        # A query or a fragment does not travel: the call is rebuilt bare.
        self.assertEqual(opencode.allowed_url(opencode.STATUS_URL + "?next=1#top"),
                         opencode.STATUS_URL)
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
            payload = opencode.collect(fetch=fetch)
        self.assertTrue(payload["ok"])
        self.assertEqual(seen["token"], "tok_abc")
        self.assertEqual(seen["org"], "wrk_1")
        self.assertEqual(len(payload["meters"]), 3)

    def test_no_account_is_drawn_rather_than_raised(self):
        with patch.object(opencode, "credentials", return_value=None):
            payload = opencode.collect(fetch=lambda *a: STATUS)
        self.assertFalse(payload["ok"])
        self.assertIn("account", payload["error"])
        self.assertEqual(payload["reason"], "signin")
        self.assertEqual(payload["meters"], [])

    def test_an_expired_sign_in_says_so(self):
        for raised in (HTTPError(opencode.STATUS_URL, 401, "Unauthorized", {}, None),
                       HTTPError(opencode.STATUS_URL, 403, "Forbidden", {}, None),
                       OSError("HTTP Error 401: Unauthorized"),
                       OSError("forbidden"),
                       PermissionError("403")):
            with patch.object(opencode, "credentials", return_value=self.fake_account()):
                payload = opencode.collect(fetch=lambda *a, e=raised: (_ for _ in ()).throw(e))
            self.assertFalse(payload["ok"])
            self.assertIn("expired", payload["error"].lower())
            self.assertEqual(payload["reason"], "expired")

    def test_a_server_error_names_its_status(self):
        raised = HTTPError(opencode.STATUS_URL, 502, "Bad Gateway", {}, None)
        with patch.object(opencode, "credentials", return_value=self.fake_account()):
            payload = opencode.collect(fetch=lambda *a: (_ for _ in ()).throw(raised))
        self.assertEqual(payload["error"], "OpenCode answered 502")
        self.assertEqual(payload["reason"], "error")

    def test_a_network_failure_is_drawn_rather_than_raised(self):
        for raised in (OSError("offline"), TimeoutError("slow"), RuntimeError("boom"),
                       ValueError("bad json")):
            with patch.object(opencode, "credentials", return_value=self.fake_account()):
                payload = opencode.collect(fetch=lambda *a, e=raised: (_ for _ in ()).throw(e))
            self.assertFalse(payload["ok"])
            self.assertTrue(payload["error"])
            self.assertEqual(payload["meters"], [])

    def test_the_shipped_path_reads_the_real_console(self):
        # The one test that talks to the console, and it only reads. It
        # stands down when there is nothing to read with: no account, or no
        # route. An expired sign-in still fails, because that is broken.
        if not opencode.credentials():
            self.skipTest("no OpenCode account on this machine")
        payload = opencode.collect()
        if not payload["ok"] and "expired" not in payload["error"].lower():
            self.skipTest("console unreachable: %s" % payload["error"])
        self.assertTrue(payload["ok"], payload["error"])
        self.assertTrue(payload["plan"].startswith("OpenCode Go"))
        by_id = {m["id"]: m for m in payload["meters"]}
        for known in ("fiveHour", "week", "month"):
            self.assertIn(known, by_id)
        # The documented 20 / 50 / 100 split of the monthly limit.
        month = by_id["month"]["limit"]
        self.assertTrue(month)
        self.assertAlmostEqual(by_id["fiveHour"]["limit"], month * 0.2)
        self.assertAlmostEqual(by_id["week"]["limit"], month * 0.5)


class MainTest(unittest.TestCase):
    def run_main(self, collector, cache):
        output = io.StringIO()
        with redirect_stdout(output):
            result = opencode.main(["opencode.py"], collector=collector, cache=cache)
        self.assertEqual(result, 0)
        return json.loads(output.getvalue())

    def test_main_prints_and_caches_a_good_reply(self):
        folder = tempfile.mkdtemp()
        cache = os.path.join(folder, "nested", "opencode.json")
        payload = self.run_main(lambda: opencode.parse_status(STATUS), cache)
        self.assertTrue(payload["ok"])
        self.assertGreater(payload["savedAt"], 0)
        with open(cache) as handle:
            saved = json.load(handle)
        self.assertEqual(saved["meters"], payload["meters"])
        self.assertEqual(saved["savedAt"], payload["savedAt"])

    def test_main_leaves_the_cache_alone_on_failure(self):
        folder = tempfile.mkdtemp()
        cache = os.path.join(folder, "opencode.json")
        payload = self.run_main(lambda: (_ for _ in ()).throw(RuntimeError("no route")), cache)
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["error"], "no route")
        self.assertFalse(os.path.exists(cache))


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
