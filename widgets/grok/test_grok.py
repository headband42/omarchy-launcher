#!/usr/bin/env python3
"""Regression tests for the Grok tile's sampler. Stdlib only.

Every test uses an auth file it made itself, and `fetch` is always replaced:
nothing here reads the real sign-in or reaches the network.

Run from the repo root:  python3 widgets/grok/test_grok.py
"""

import io
import json
import os
import shutil
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from datetime import datetime, timezone
from unittest.mock import patch
from urllib.error import HTTPError

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import grok


def ms(*args):
    return int(datetime(*args, tzinfo=timezone.utc).timestamp() * 1000)


NOW_MS = ms(2026, 10, 2, 3, 0)
WEEK_END = "2026-10-07T10:41:24.364336+00:00"
MONTH_END = "2026-11-01T00:00:00Z"
TOKEN = "tok-test"
SECRET_EMAIL = "person@example.com"
REFRESH = "ref-test-do-not-print"


def signin(token=TOKEN, expires="2026-10-02T04:20:27.553002431Z", user_id="user_1", **extra):
    data = {"key": token, "auth_mode": "oidc", "expires_at": expires, "refresh_token": REFRESH,
            "user_id": user_id, "email": SECRET_EMAIL, "principal_type": "User"}
    data.update(extra)
    return data


class Folder:
    """A throwaway directory holding an auth.json."""

    def __init__(self, payload):
        self.path = tempfile.mkdtemp()
        self.file = os.path.join(self.path, "auth.json")
        with open(self.file, "w", encoding="utf-8") as handle:
            if isinstance(payload, str):
                handle.write(payload)
            else:
                json.dump(payload, handle)

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        shutil.rmtree(self.path)


def credits(**config):
    body = {
        "currentPeriod": {"type": "USAGE_PERIOD_TYPE_WEEKLY",
                          "start": "2026-09-30T10:41:24.364336+00:00", "end": WEEK_END},
        "creditUsagePercent": 5.0,
        "onDemandCap": {"val": 0},
        "onDemandUsed": {"val": 0},
        "productUsage": [{"product": "GrokBuild", "usagePercent": 5.0}, {"product": "GrokChat"}],
        "prepaidBalance": {"val": 0},
        "billingPeriodEnd": MONTH_END,
    }
    body.update(config)
    return {"config": body}


class Isolated(unittest.TestCase):
    """The machine's Grok env must not decide what these tests call."""

    def setUp(self):
        self._env = patch.dict(os.environ, {}, clear=False)
        self._env.start()
        os.environ.pop("GROK_HOME", None)
        os.environ.pop("GROK_CLI_CHAT_PROXY_BASE_URL", None)

    def tearDown(self):
        self._env.stop()


class CredentialsTest(Isolated):
    def test_reads_the_session_token(self):
        saved = {"https://auth.x.ai::client": signin()}
        with Folder(saved) as folder:
            account = grok.credentials(folder.file, NOW_MS)
        self.assertEqual(account["token"], TOKEN)
        self.assertEqual(account["userId"], "user_1")
        self.assertEqual(account["expiresAt"], ms(2026, 10, 2, 4, 20, 27, 553002))
        self.assertNotIn(REFRESH, json.dumps({k: v for k, v in account.items() if k != "token"}))
        self.assertNotIn(SECRET_EMAIL, json.dumps(account))

    def test_a_bare_credential_and_access_token_work(self):
        with Folder({"access_token": "alt-tok", "expiresAt": "2026-10-02T05:00:00Z",
                     "userId": "abc"}) as folder:
            account = grok.credentials(folder.file, NOW_MS)
        self.assertEqual(account["token"], "alt-tok")
        self.assertEqual(account["userId"], "abc")
        self.assertEqual(account["expiresAt"], ms(2026, 10, 2, 5))

    def test_a_sign_in_without_a_token_is_none(self):
        for broken in (signin(token=""), signin(token=None), signin(token="x" * 9000), {}):
            with Folder({"issuer::client": broken}) as folder:
                self.assertIsNone(grok.credentials(folder.file, NOW_MS))
        for raw in ("not json", "[]", "{}"):
            with Folder(raw) as folder:
                self.assertIsNone(grok.credentials(folder.file, NOW_MS))
        self.assertIsNone(grok.credentials("/nonexistent/auth.json", NOW_MS))

    def test_an_odd_user_id_is_left_off(self):
        with Folder(signin(user_id="not a user")) as folder:
            self.assertEqual(grok.credentials(folder.file, NOW_MS)["userId"], "")

    def test_a_live_sign_in_beats_an_expired_one(self):
        saved = {
            "old": signin(token="expired-tok", expires="2026-10-01T00:00:00Z"),
            "live": signin(token="live-tok", expires="2026-10-02T04:00:00Z"),
        }
        with Folder(saved) as folder:
            self.assertEqual(grok.credentials(folder.file, NOW_MS)["token"], "live-tok")

    def test_when_every_sign_in_is_expired_the_newest_is_kept(self):
        saved = {
            "older": signin(token="older-tok", expires="2026-09-01T00:00:00Z"),
            "newer": signin(token="newer-tok", expires="2026-10-01T00:00:00Z"),
        }
        with Folder(saved) as folder:
            self.assertEqual(grok.credentials(folder.file, NOW_MS)["token"], "newer-tok")

    def test_the_longer_lived_sign_in_wins(self):
        saved = {
            "soon": signin(token="soon-tok", expires="2026-10-02T04:00:00Z"),
            "later": signin(token="later-tok", expires="2026-10-02T08:00:00Z"),
        }
        with Folder(saved) as folder:
            self.assertEqual(grok.credentials(folder.file, NOW_MS)["token"], "later-tok")

    def test_a_sign_in_with_no_expiry_beats_an_expired_one(self):
        saved = {
            "stamped": signin(token="expired-tok", expires="2026-10-01T00:00:00Z"),
            "open": {"key": "open-tok", "user_id": "user_1"},
        }
        with Folder(saved) as folder:
            self.assertEqual(grok.credentials(folder.file, NOW_MS)["token"], "open-tok")

    def test_grok_home_comes_first(self):
        home = tempfile.mkdtemp()
        custom = tempfile.mkdtemp()
        try:
            os.makedirs(os.path.join(home, ".grok"))
            with open(os.path.join(home, ".grok", "auth.json"), "w", encoding="utf-8") as handle:
                json.dump(signin(token="home-tok"), handle)
            with open(os.path.join(custom, "auth.json"), "w", encoding="utf-8") as handle:
                json.dump(signin(token="custom-tok"), handle)
            with patch.dict(os.environ, {"HOME": home, "GROK_HOME": custom}):
                self.assertEqual(grok.auth_path(), os.path.join(custom, "auth.json"))
                self.assertEqual(grok.credentials(now_ms=NOW_MS)["token"], "custom-tok")
            with patch.dict(os.environ, {"HOME": home, "GROK_HOME": ""}):
                self.assertEqual(grok.auth_path(), os.path.join(home, ".grok", "auth.json"))
                self.assertEqual(grok.credentials(now_ms=NOW_MS)["token"], "home-tok")
        finally:
            shutil.rmtree(home)
            shutil.rmtree(custom)

    def test_names_the_plan(self):
        self.assertEqual(grok.plan_name({"subscription_tier": "4",
                                         "subscription_tier_display": "X Premium+"}, None),
                         "X Premium+")
        self.assertEqual(grok.plan_name({"subscription_tier": "SuperGrok",
                                         "subscription_tier_display": "X Premium+"}, None),
                         "X Premium+")
        self.assertEqual(grok.plan_name({"settings": {"subscriptionTierDisplay": "SuperGrok Heavy"}},
                                        {"subscription_tier": "Ignored"}),
                         "SuperGrok Heavy")
        self.assertEqual(grok.plan_name(None, {"subscription_tier": "SuperGrok"}), "SuperGrok")
        self.assertEqual(grok.plan_name({"subscription_tier": 4}, None), "Grok")
        self.assertEqual(grok.plan_name(None, None), "Grok")


class MoneyTest(Isolated):
    def test_cents(self):
        self.assertEqual(grok.cents({"val": 5000}), 5000)
        self.assertEqual(grok.cents({"val": 355}), 355)
        self.assertEqual(grok.cents({"val": -1250}), -1250)
        self.assertEqual(grok.cents({}), 0)
        self.assertEqual(grok.cents({"val": None}), 0)
        self.assertEqual(grok.cents(500), 500)
        self.assertEqual(grok.cents(500.0), 500)
        self.assertEqual(grok.cents("500"), 500)
        self.assertIsNone(grok.cents({"val": 1.5}))
        self.assertIsNone(grok.cents(True))
        self.assertIsNone(grok.cents("5.5"))
        self.assertEqual(grok.dollars({"val": 5000}), 50.0)
        self.assertEqual(grok.dollars({"val": 355}), 3.55)
        self.assertEqual(grok.dollars({"val": -1250}), 12.50)
        self.assertEqual(grok.dollars({}), 0.0)
        self.assertIsNone(grok.dollars(None))

    def test_nanos_trim_to_microseconds(self):
        self.assertEqual(grok.epoch_ms("2026-10-02T04:20:27.553002431Z"),
                         ms(2026, 10, 2, 4, 20, 27, 553002))
        self.assertEqual(grok.epoch_ms(WEEK_END), ms(2026, 10, 7, 10, 41, 24, 364336))
        self.assertEqual(grok.epoch_ms("2026-10-03T04:00:00Z"), ms(2026, 10, 3, 4))
        self.assertEqual(grok.epoch_ms("2026-10-03T04:00:00"), ms(2026, 10, 3, 4))
        self.assertIsNone(grok.epoch_ms(None))
        self.assertIsNone(grok.epoch_ms("later"))


class ParseTest(Isolated):
    def test_a_weekly_allowance_hides_a_duplicate_product(self):
        payload = grok.parse_billing(credits(), "X Premium+")
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["plan"], "X Premium+")
        self.assertEqual([m["id"] for m in payload["meters"]], ["period"])
        week = payload["meters"][0]
        self.assertEqual(week["label"], "WEEK")
        self.assertEqual(week["caption"], "of this week")
        self.assertEqual(week["percent"], 5.0)
        self.assertEqual(week["resetsAtMs"], ms(2026, 10, 7, 10, 41, 24, 364336))
        self.assertIsNone(week["used"])
        self.assertFalse(week["near"])
        self.assertIsNone(payload["credits"])
        self.assertEqual(payload["pollMs"], grok.POLL_MS)
        # The weekly reset is the period end, not the calendar-month ledger.
        self.assertNotEqual(week["resetsAtMs"], grok.epoch_ms(MONTH_END))

    def test_products_show_when_they_add_up_to_the_allowance(self):
        payload = grok.parse_billing(credits(
            creditUsagePercent=100,
            productUsage=[{"product": "PRODUCT_GROK_BUILD", "usagePercent": 54},
                          {"product": "GrokChat", "usagePercent": 46},
                          {"product": "PRODUCT_GROK_BUILD", "usagePercent": 1}]))
        self.assertEqual([m["id"] for m in payload["meters"]], ["period", "grokbuild", "grokchat"])
        self.assertEqual(payload["meters"][1]["label"], "GROK BUILD")
        self.assertEqual(payload["meters"][1]["percent"], 54)
        self.assertEqual(payload["meters"][2]["caption"], "of Grok Chat")

    def test_products_that_do_not_add_up_stay_hidden(self):
        payload = grok.parse_billing(credits(
            creditUsagePercent=100,
            productUsage=[{"product": "GrokBuild", "usagePercent": 54},
                          {"product": "api", "usagePercent": 10}]))
        self.assertEqual([m["id"] for m in payload["meters"]], ["period"])

    def test_the_api_share_uses_the_api_id(self):
        payload = grok.parse_billing(credits(
            creditUsagePercent=100,
            productUsage=[{"product": "GrokBuild", "usagePercent": 54},
                          {"product": "PRODUCT_GROK_API", "usagePercent": 46}]))
        self.assertEqual([m["id"] for m in payload["meters"]], ["period", "grokbuild", "api"])
        self.assertEqual(payload["meters"][2]["label"], "API")

    def test_a_fresh_week_is_zero_not_the_monthly_ledger(self):
        # A missing percentage is not the same as a stored null. Drop the key.
        body = credits()
        del body["config"]["creditUsagePercent"]
        del body["config"]["productUsage"]
        body["config"]["monthlyLimit"] = {"val": 15000}
        body["config"]["used"] = {"val": 5000}
        payload = grok.parse_billing(body)
        self.assertEqual([m["id"] for m in payload["meters"]], ["period"])
        self.assertEqual(payload["meters"][0]["percent"], 0.0)
        self.assertEqual(payload["meters"][0]["label"], "WEEK")
        self.assertEqual(payload["meters"][0]["resetsAtMs"], grok.epoch_ms(WEEK_END))

    def test_a_missing_period_end_falls_back_to_the_ledger(self):
        body = credits(creditUsagePercent=None)
        del body["config"]["creditUsagePercent"]
        del body["config"]["currentPeriod"]["end"]
        payload = grok.parse_billing(body)
        self.assertEqual(payload["meters"][0]["resetsAtMs"], grok.epoch_ms(MONTH_END))

    def test_an_explicit_zero_beats_the_old_ledger(self):
        payload = grok.parse_billing(credits(
            creditUsagePercent=0, monthlyLimit={"val": 15000}, used={"val": 5000}))
        self.assertEqual(len(payload["meters"]), 1)
        self.assertEqual(payload["meters"][0]["percent"], 0.0)
        self.assertEqual(payload["meters"][0]["label"], "WEEK")

    def test_the_older_monthly_ledger(self):
        payload = grok.parse_billing({
            "monthlyLimit": {"val": 15000},
            "used": {"val": 3550},
            "billingPeriodEnd": MONTH_END,
            "onDemandCap": {},
        })
        self.assertEqual([m["id"] for m in payload["meters"]], ["period"])
        month = payload["meters"][0]
        self.assertEqual(month["label"], "MONTH")
        self.assertEqual(month["caption"], "of this month")
        self.assertAlmostEqual(month["percent"], 3550 / 15000 * 100.0)
        self.assertEqual(month["used"], 35.50)
        self.assertEqual(month["limit"], 150.0)
        self.assertEqual(month["resetsAtMs"], grok.epoch_ms(MONTH_END))

    def test_pay_as_you_go_and_bought_credits(self):
        payload = grok.parse_billing(credits(
            onDemandCap={"val": 5000}, onDemandUsed={"val": 355},
            prepaidBalance={"val": -1250}))
        extra = payload["meters"][-1]
        self.assertEqual(extra["id"], "ondemand")
        self.assertEqual(extra["label"], "PAY AS YOU GO")
        self.assertEqual(extra["caption"], "of the spending cap")
        self.assertAlmostEqual(extra["percent"], 355 / 5000 * 100.0)
        self.assertEqual(extra["used"], 3.55)
        self.assertEqual(extra["limit"], 50.0)
        self.assertEqual(payload["credits"], 12.50)
        hidden = grok.parse_billing(credits(onDemandCap={}, prepaidBalance={"val": 0}))
        self.assertNotIn("ondemand", [m["id"] for m in hidden["meters"]])
        self.assertIsNone(hidden["credits"])

    def test_a_negative_cap_is_still_a_cap(self):
        payload = grok.parse_billing(credits(onDemandCap={"val": -5000}, onDemandUsed={"val": -355}))
        extra = payload["meters"][-1]
        self.assertEqual(extra["used"], 3.55)
        self.assertEqual(extra["limit"], 50.0)
        self.assertAlmostEqual(extra["percent"], 7.1)

    def test_near_and_over(self):
        payload = grok.parse_billing(credits(creditUsagePercent=104.5, productUsage=[]))
        self.assertTrue(payload["meters"][0]["over"])
        self.assertTrue(payload["meters"][0]["near"])
        self.assertEqual(payload["pollMs"], grok.POLL_BUSY_MS)
        near = grok.parse_billing(credits(creditUsagePercent=80, productUsage=[]))
        self.assertTrue(near["meters"][0]["near"])
        self.assertFalse(near["meters"][0]["over"])

    def test_a_monthly_window(self):
        payload = grok.parse_billing(credits(
            currentPeriod={"type": "USAGE_PERIOD_TYPE_MONTHLY", "end": MONTH_END},
            productUsage=[]))
        self.assertEqual(payload["meters"][0]["label"], "MONTH")
        self.assertEqual(payload["meters"][0]["caption"], "of this month")

    def test_no_limits_is_a_plan_message(self):
        view = grok.parse_billing({"config": {"onDemandCap": {}, "prepaidBalance": {}}})
        self.assertFalse(view["ok"])
        self.assertEqual(view["reason"], "plan")
        self.assertEqual(grok.parse_billing(["x"])["reason"], "error")
        self.assertEqual(grok.parse_billing({"config": "nope"})["reason"], "error")


class CollectTest(Isolated):
    def answers(self, billing, settings=None, settings_error=None):
        seen = []

        def fetch(url, token, user_id=""):
            seen.append({"url": url, "token": token, "userId": user_id})
            if url.endswith("/settings"):
                if settings_error:
                    raise settings_error
                return settings if settings is not None else {}
            return billing

        return fetch, seen

    def test_a_signed_in_account_becomes_a_payload(self):
        fetch, seen = self.answers(credits(), {"subscription_tier": 4,
                                                "subscription_tier_display": "X Premium+"})
        with Folder({"https://auth.x.ai::client": signin()}) as folder:
            payload = grok.collect(fetch=fetch, path=folder.file, now_ms=NOW_MS)
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["plan"], "X Premium+")
        self.assertEqual([call["url"] for call in seen], [grok.billing_url(), grok.settings_url()])
        self.assertEqual(seen[0]["token"], TOKEN)
        self.assertEqual(seen[0]["userId"], "user_1")
        dumped = json.dumps(payload)
        self.assertNotIn(TOKEN, dumped)
        self.assertNotIn(REFRESH, dumped)
        self.assertNotIn(SECRET_EMAIL, dumped)

    def test_settings_failing_keeps_the_bars(self):
        fetch, _seen = self.answers(credits(), settings_error=OSError("settings down"))
        with Folder(signin()) as folder:
            payload = grok.collect(fetch=fetch, path=folder.file, now_ms=NOW_MS)
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["plan"], "Grok")
        self.assertEqual(payload["meters"][0]["percent"], 5.0)

    def test_a_billing_name_is_used_when_settings_has_none(self):
        fetch, _seen = self.answers(credits(subscription_tier_display="SuperGrok"), {})
        with Folder(signin()) as folder:
            payload = grok.collect(fetch=fetch, path=folder.file, now_ms=NOW_MS)
        self.assertEqual(payload["plan"], "SuperGrok")

    def test_the_settings_name_wins(self):
        fetch, _seen = self.answers(credits(subscription_tier="FromBilling"),
                                    {"subscription_tier_display": "FromSettings"})
        with Folder(signin()) as folder:
            payload = grok.collect(fetch=fetch, path=folder.file, now_ms=NOW_MS)
        self.assertEqual(payload["plan"], "FromSettings")

    def test_no_sign_in(self):
        payload = grok.collect(fetch=lambda *a: credits(), path="/nonexistent/auth.json", now_ms=NOW_MS)
        self.assertEqual(payload["reason"], "signin")

    def test_an_expired_token_is_not_sent(self):
        def fetch(*args):
            raise AssertionError("an expired token must not be sent")

        with Folder(signin(expires="2026-10-01T00:00:00Z")) as folder:
            payload = grok.collect(fetch=fetch, path=folder.file, now_ms=NOW_MS)
        self.assertEqual(payload["reason"], "expired")

    def test_collect_without_a_clock_still_skips_the_expired_sign_in(self):
        seen = {}

        def fetch(url, token, user_id=""):
            seen["token"] = token
            if url.endswith("/settings"):
                return {}
            return credits()

        saved = {
            "stamped": signin(token="expired-tok", expires="2026-10-01T00:00:00Z"),
            "open": {"key": "open-tok", "user_id": "user_1"},
        }
        with Folder(saved) as folder:
            payload = grok.collect(fetch=fetch, path=folder.file)
        self.assertTrue(payload["ok"])
        self.assertEqual(seen["token"], "open-tok")

    def test_errors_by_status(self):
        cases = ((401, "expired", "expired"), (403, "expired", "expired"),
                 (429, "error", "slow down"), (500, "error", "Grok answered 500"))
        for code, reason, words in cases:
            error = HTTPError(grok.billing_url(), code, "x", {}, None)

            def fetch(*args, e=error):
                raise e

            with Folder(signin()) as folder:
                payload = grok.collect(fetch=fetch, path=folder.file, now_ms=NOW_MS)
            self.assertEqual(payload["reason"], reason, code)
            self.assertIn(words, payload["error"])

    def test_a_network_failure_is_drawn(self):
        with Folder(signin()) as folder:
            payload = grok.collect(fetch=lambda *a: (_ for _ in ()).throw(OSError("offline")),
                                   path=folder.file, now_ms=NOW_MS)
        self.assertEqual(payload["reason"], "error")
        self.assertEqual(payload["error"], "offline")

    def test_a_bad_proxy_is_not_called(self):
        def fetch(*args):
            raise AssertionError("a rejected address must not be called")

        with Folder(signin()) as folder, patch.dict(os.environ, {"GROK_CLI_CHAT_PROXY_BASE_URL": "http://insecure"}):
            payload = grok.collect(fetch=fetch, path=folder.file, now_ms=NOW_MS)
        self.assertEqual(payload["reason"], "error")
        self.assertIn("billing address", payload["error"])


class RequestTest(Isolated):
    def test_only_the_two_calls_are_allowed(self):
        for url in ("https://example.com/v1/billing?format=credits",
                    grok.DEFAULT_BASE + "/billing",
                    grok.DEFAULT_BASE + "/auto-topup-rule",
                    "http://cli-chat-proxy.grok.com/v1/billing?format=credits"):
            with self.assertRaises(ValueError):
                grok.fetch_json(url, TOKEN)

    def test_a_userinfo_or_query_on_the_base_is_rejected(self):
        for raw in ("https://user:pass@cli-chat-proxy.grok.com/v1",
                    "https://cli-chat-proxy.grok.com/v1?x=1",
                    "not a url",
                    "http://cli-chat-proxy.grok.com/v1"):
            with patch.dict(os.environ, {"GROK_CLI_CHAT_PROXY_BASE_URL": raw}):
                self.assertEqual(grok.base_url(), "")

    def test_an_https_override_is_honored(self):
        with patch.dict(os.environ, {"GROK_CLI_CHAT_PROXY_BASE_URL": "https://proxy.example:8443/v1/"}):
            self.assertEqual(grok.billing_url(), "https://proxy.example:8443/v1/billing?format=credits")
            self.assertEqual(grok.settings_url(), "https://proxy.example:8443/v1/settings")

    def test_the_request_carries_the_token_and_the_cli_header(self):
        seen = {}

        class Response:
            def __enter__(self):
                return self

            def __exit__(self, *exc):
                return False

            def read(self, size):
                return json.dumps(credits()).encode()

        def opener(request, timeout):
            seen["url"] = request.full_url
            seen["auth"] = request.get_header("Authorization")
            seen["cli"] = request.get_header("X-xai-token-auth")
            seen["user"] = request.get_header("X-userid")
            seen["agent"] = request.get_header("User-agent")
            return Response()

        payload = grok.fetch_json(grok.billing_url(), TOKEN, "user_1", opener=opener)
        self.assertEqual(payload["config"]["creditUsagePercent"], 5.0)
        self.assertEqual(seen, {"url": grok.billing_url(), "auth": "Bearer " + TOKEN,
                                "cli": grok.TOKEN_HEADER, "user": "user_1", "agent": grok.USER_AGENT})

    def test_an_oversized_reply_is_refused(self):
        class Big:
            def __enter__(self):
                return self

            def __exit__(self, *exc):
                return False

            def read(self, size):
                return b"x" * size

        with self.assertRaises(OSError):
            grok.fetch_json(grok.billing_url(), TOKEN, opener=lambda request, timeout: Big())


class MainTest(Isolated):
    def run_main(self, collector, cache):
        output = io.StringIO()
        with redirect_stdout(output):
            self.assertEqual(grok.main(["grok.py"], collector=collector, cache=cache), 0)
        return json.loads(output.getvalue())

    def test_a_good_reply_is_printed_and_cached(self):
        folder = tempfile.mkdtemp()
        try:
            cache = os.path.join(folder, "nested", "grok.json")
            payload = self.run_main(lambda: grok.parse_billing(credits(), "X Premium+"), cache)
            self.assertTrue(payload["ok"])
            self.assertGreater(payload["savedAt"], 0)
            self.assertNotIn(TOKEN, json.dumps(payload))
            with open(cache, encoding="utf-8") as handle:
                saved = json.load(handle)
            self.assertEqual(saved["meters"], payload["meters"])
            self.assertEqual(saved["plan"], "X Premium+")
        finally:
            shutil.rmtree(folder)

    def test_a_failure_is_printed_not_cached(self):
        folder = tempfile.mkdtemp()
        try:
            cache = os.path.join(folder, "grok.json")
            payload = self.run_main(lambda: (_ for _ in ()).throw(RuntimeError("boom")), cache)
            self.assertFalse(payload["ok"])
            self.assertEqual(payload["error"], "boom")
            self.assertFalse(os.path.exists(cache))
        finally:
            shutil.rmtree(folder)


if __name__ == "__main__":
    unittest.main()
