#!/usr/bin/env python3
"""Stocks sampler: quote parsing, sessions, sources, search, cache. Stdlib only.

Run from the repo root:  python3 widgets/stocks/test_stocks.py
"""

import importlib.util
import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock
from urllib.error import HTTPError

import stocks


ROOT = Path(__file__).resolve().parents[2]
# 2026-09-30, New York trading day. Times are epoch seconds.
PRE_START = 1790755200     # 04:00 EDT
OPEN = 1790775000          # 09:30 EDT
CLOSE = 1790798400         # 16:00 EDT
POST_END = 1790812800      # 20:00 EDT


def load_list_widgets():
    path = ROOT / "scripts" / "list-widgets.py"
    spec = importlib.util.spec_from_file_location("list_widgets", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def window(start, end):
    return {"timezone": "EDT", "start": start, "end": end, "gmtoffset": -14400}


def equity_meta(symbol, **extra):
    meta = {
        "symbol": symbol,
        "shortName": symbol + " Corp  ",
        "currency": "USD",
        "instrumentType": "EQUITY",
        "regularMarketPrice": 100.0,
        "chartPreviousClose": 98.0,
        "regularMarketChangePercent": 2.0408,
        "hasPrePostMarketData": True,
        "fulldayPrice": 101.5,
        "fulldayChange": 3.5,
        "fulldayChangePercent": 3.5714,
        "priceHint": 2,
        "currentTradingPeriod": {
            "pre": window(PRE_START, OPEN),
            "regular": window(OPEN, CLOSE),
            "post": window(CLOSE, POST_END),
        },
        "tradingPeriods": {
            "pre": [[window(PRE_START, OPEN)]],
            "regular": [[window(OPEN, CLOSE)]],
            "post": [[window(CLOSE, POST_END)]],
        },
    }
    meta.update(extra)
    return meta


def spark_item(meta, closes=(97.0, 99.0, None, 100.0)):
    return {
        "symbol": meta["symbol"],
        "response": [{"meta": meta, "indicators": {"quote": [{"close": list(closes)}]}}],
    }


def spark_payload(*metas):
    return {"spark": {"result": [spark_item(meta) for meta in metas]}}


class FakeFetch:
    def __init__(self, payload):
        self.payload = payload
        self.urls = []

    def __call__(self, url):
        self.urls.append(url)
        if isinstance(self.payload, Exception):
            raise self.payload
        return self.payload


class SymbolsTest(unittest.TestCase):
    def test_normalizes_dedupes_and_caps(self):
        self.assertEqual(
            stocks.parse_symbols(" msft, brk-b ^gspc btc-usd gc=f eurusd=x 7203.t MSFT"),
            ["MSFT", "BRK-B", "^GSPC", "BTC-USD", "GC=F", "EURUSD=X"],
        )

    def test_rejects_what_is_not_a_symbol(self):
        self.assertEqual(stocks.parse_symbols(["", "../etc", "a b", "$TSLA", "X" * 21, "ok"]), ["OK"])

    def test_watchlist_reads_omafinance_state(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "finance.json"
            path.write_text(json.dumps({"watchlist": ["tsla", "SPCX", "tsla"], "pinned": ["MU"]}))
            self.assertEqual(stocks.omafinance_watchlist(path), ["TSLA", "SPCX"])
            path.write_text("not json")
            self.assertEqual(stocks.omafinance_watchlist(path), [])
            self.assertEqual(stocks.omafinance_watchlist(Path(tmp) / "missing.json"), [])


class QuoteTest(unittest.TestCase):
    def test_sessions(self):
        meta = equity_meta("MSFT")
        self.assertEqual(stocks.session_from_meta(meta, PRE_START + 60), "pre")
        self.assertEqual(stocks.session_from_meta(meta, OPEN + 60), "regular")
        self.assertEqual(stocks.session_from_meta(meta, CLOSE + 60), "post")
        self.assertEqual(stocks.session_from_meta(meta, POST_END + 60), "closed")
        crypto = equity_meta("BTC-USD", instrumentType="CRYPTOCURRENCY")
        self.assertEqual(stocks.session_from_meta(crypto, POST_END + 60), "live")

    def test_regular_session_uses_the_regular_price(self):
        quote = stocks.quote_from_chart(spark_item(equity_meta("MSFT"))["response"][0], "", OPEN + 60)
        self.assertEqual(quote["price"], 100.0)
        self.assertAlmostEqual(quote["changePercent"], 2.0408)
        self.assertAlmostEqual(quote["change"], 2.0)
        self.assertFalse(quote["extended"])
        self.assertEqual(quote["name"], "MSFT Corp")
        self.assertEqual(quote["closes"], [97.0, 99.0, 100.0])
        self.assertEqual(quote["type"], "EQUITY")

    def test_after_hours_uses_the_latest_print_against_the_close(self):
        quote = stocks.quote_from_chart(spark_item(equity_meta("MSFT"))["response"][0], "", CLOSE + 60)
        self.assertTrue(quote["extended"])
        self.assertEqual(quote["price"], 101.5)
        self.assertAlmostEqual(quote["changePercent"], 3.5714)
        self.assertAlmostEqual(quote["change"], 3.5)

    def test_no_extended_print_keeps_the_close(self):
        meta = equity_meta("MSFT", fulldayPrice=100.001)
        quote = stocks.quote_from_chart(spark_item(meta)["response"][0], "", POST_END + 60)
        self.assertFalse(quote["extended"])
        self.assertEqual(quote["price"], 100.0)

    def test_downsample_keeps_ends(self):
        values = list(range(200))
        thinned = stocks.downsample(values, 64)
        self.assertEqual(len(thinned), 64)
        self.assertEqual(thinned[0], 0)
        self.assertEqual(thinned[-1], 199)
        self.assertEqual(stocks.downsample([1, None, "x", 2.5]), [1.0, 2.5])


class CollectTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.watchlist = Path(self.tmp.name) / "finance.json"

    def tearDown(self):
        self.tmp.cleanup()

    def test_settings_win_over_the_watchlist(self):
        self.watchlist.write_text(json.dumps({"watchlist": ["TSLA"]}))
        fetch = FakeFetch(spark_payload(equity_meta("MSFT")))
        payload = stocks.collect("msft,zzzz", OPEN + 60, fetch, self.watchlist)
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["source"], "settings")
        self.assertEqual(payload["request"], "MSFT,ZZZZ")
        self.assertEqual(payload["watchlist"], ["TSLA"])
        self.assertEqual([q["symbol"] for q in payload["quotes"]], ["MSFT", "ZZZZ"])
        self.assertTrue(payload["quotes"][1]["missing"])
        self.assertIn("symbols=MSFT%2CZZZZ", fetch.urls[0])
        self.assertIn("includePrePost=true", fetch.urls[0])

    def test_no_settings_follows_omafinance(self):
        self.watchlist.write_text(json.dumps({"watchlist": ["TSLA", "MU"]}))
        fetch = FakeFetch(spark_payload(equity_meta("TSLA"), equity_meta("MU")))
        payload = stocks.collect("", OPEN + 60, fetch, self.watchlist)
        self.assertEqual(payload["source"], "omafinance")
        self.assertEqual(payload["request"], "")
        self.assertEqual(payload["symbols"], ["TSLA", "MU"])

    def test_no_watchlist_shows_the_indexes(self):
        fetch = FakeFetch(spark_payload())
        payload = stocks.collect("", OPEN + 60, fetch, self.watchlist)
        self.assertEqual(payload["source"], "default")
        self.assertEqual(payload["symbols"], list(stocks.DEFAULT_SYMBOLS))
        self.assertIn("%5EGSPC", fetch.urls[0])

    def test_no_answer_is_an_error_not_an_empty_list(self):
        payload = stocks.collect("MSFT", OPEN + 60, FakeFetch(OSError("offline")), self.watchlist)
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["request"], "MSFT")
        self.assertEqual(payload["quotes"], [])
        self.assertTrue(payload["error"])

    def test_header_follows_stock_hours_and_polling_follows_any_trade(self):
        gold = equity_meta("GC=F", instrumentType="FUTURE", currentTradingPeriod={
            "regular": window(POST_END, POST_END + 3600)}, tradingPeriods={})
        fetch = FakeFetch(spark_payload(equity_meta("MSFT"), gold))
        payload = stocks.collect("MSFT,GC=F", POST_END + 60, fetch, self.watchlist)
        self.assertEqual(payload["market"], "closed")
        self.assertEqual(payload["pollMs"], stocks.POLL_OPEN_MS)

    def test_crypto_only_is_live(self):
        coin = equity_meta("BTC-USD", instrumentType="CRYPTOCURRENCY")
        payload = stocks.collect("BTC-USD", POST_END + 60, FakeFetch(spark_payload(coin)), self.watchlist)
        self.assertEqual(payload["market"], "live")
        self.assertEqual(payload["pollMs"], stocks.POLL_CRYPTO_MS)

    def test_closed_polls_slowly(self):
        payload = stocks.collect("MSFT", POST_END + 60, FakeFetch(spark_payload(equity_meta("MSFT"))), self.watchlist)
        self.assertEqual(payload["market"], "closed")
        self.assertEqual(payload["pollMs"], stocks.POLL_CLOSED_MS)


class FetchTest(unittest.TestCase):
    def test_unknown_symbols_are_an_empty_answer(self):
        error = HTTPError("https://example.invalid", 404, "Not Found", {}, io.BytesIO(b"{}"))
        with mock.patch.object(stocks, "urlopen", side_effect=error):
            self.assertEqual(stocks.fetch_json("https://example.invalid"), {"spark": {"result": []}})

    def test_other_http_errors_raise(self):
        error = HTTPError("https://example.invalid", 429, "Too Many", {}, io.BytesIO(b""))
        with mock.patch.object(stocks, "urlopen", side_effect=error):
            with self.assertRaises(HTTPError):
                stocks.fetch_json("https://example.invalid")


class SearchTest(unittest.TestCase):
    def test_parse_skips_options_and_duplicates(self):
        rows = stocks.parse_search({"quotes": [
            {"symbol": "nvda", "shortname": "NVIDIA  Corporation ", "quoteType": "EQUITY", "exchDisp": "NASDAQ"},
            {"symbol": "NVDA", "shortname": "dup", "quoteType": "EQUITY"},
            {"symbol": "NVDA261218C00100000", "quoteType": "OPTION"},
            {"symbol": "has space", "quoteType": "EQUITY"},
            {"symbol": "XNVDA=F", "longname": "Micro NVIDIA", "quoteType": "FUTURE", "exchange": "CME"},
        ]})
        self.assertEqual(rows, [
            {"symbol": "NVDA", "name": "NVIDIA Corporation", "type": "EQUITY", "exchange": "NASDAQ"},
            {"symbol": "XNVDA=F", "name": "Micro NVIDIA", "type": "FUTURE", "exchange": "CME"},
        ])
        self.assertEqual(stocks.parse_search(None), [])

    def test_empty_query_does_not_fetch(self):
        fetch = FakeFetch({"quotes": []})
        self.assertEqual(stocks.search("  ", fetch), [])
        self.assertEqual(fetch.urls, [])

    def test_main_prints_a_list_or_an_error_object(self):
        out = io.StringIO()
        with mock.patch.object(stocks, "fetch_json", FakeFetch({"quotes": [{"symbol": "MU", "shortname": "Micron"}]})):
            with redirect_stdout(out):
                stocks.main(["stocks.py", "--search", "micron"])
        self.assertEqual(json.loads(out.getvalue())[0]["symbol"], "MU")
        out = io.StringIO()
        with mock.patch.object(stocks, "fetch_json", FakeFetch(OSError("offline"))):
            with redirect_stdout(out):
                stocks.main(["stocks.py", "--search", "micron"])
        self.assertIn("error", json.loads(out.getvalue()))


class CacheTest(unittest.TestCase):
    def test_round_trip_and_only_good_replies(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "nested" / "stocks.json"
            self.assertFalse(stocks.write_cache({"ok": False, "quotes": []}, path))
            self.assertIsNone(stocks.read_cache(path))
            self.assertTrue(stocks.write_cache({"ok": True, "request": "", "quotes": [{"symbol": "MU"}]}, path, now=5))
            cached = stocks.read_cache(path)
            self.assertEqual(cached["savedAt"], 5)
            self.assertEqual(cached["quotes"], [{"symbol": "MU"}])
            self.assertEqual(sorted(p.name for p in path.parent.iterdir()), ["stocks.json"])


class CatalogTest(unittest.TestCase):
    def test_stocks_widget_publishes_a_settings_panel(self):
        rows = load_list_widgets().load_dir(ROOT / "widgets")
        by_id = {row["id"]: row for row in rows}
        self.assertTrue(str(by_id["stocks"]["settingsQml"]).endswith("/widgets/stocks/Settings.qml"))
        self.assertEqual(by_id["stocks"]["defaultUrl"], "https://finance.yahoo.com")


if __name__ == "__main__":
    unittest.main()
