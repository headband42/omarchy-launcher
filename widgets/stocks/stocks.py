#!/usr/bin/env python3
"""Stocks tile model. Stdlib only. Tests call collect() with a fake fetch.

    stocks.py [--symbols A,B,C]   quotes for the tile
    stocks.py --search QUERY      ticker matches for the settings panel

With no --symbols the tile follows Omafinance's watchlist, and with no
watchlist it shows the major US indexes and Bitcoin. Quotes come from Yahoo
Finance's spark feed, the one Omafinance reads, so the tile and the bar agree.
Out of hours a quote is the latest pre- or post-market print, as Omafinance
shows it.

A good reply is also saved to the cache file. The tile draws that file while
the next reply is on its way, so opening the launcher does not flash empty.
"""

import json
import os
import re
import sys
import time
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

MAX_SYMBOLS = 6
SPARK_POINTS = 64
SEARCH_LIMIT = 8
DEFAULT_SYMBOLS = ("^GSPC", "^IXIC", "^DJI", "BTC-USD")
# Instruments that keep the stock market's hours.
EXCHANGE_HOURS = ("EQUITY", "ETF", "INDEX", "MUTUALFUND")
# Yahoo symbols: MSFT, BRK-B, ^GSPC, BTC-USD, GC=F, EURUSD=X, 7203.T
SYMBOL_RE = re.compile(r"^[A-Z0-9^][A-Z0-9.=^-]{0,19}$")
POLL_OPEN_MS = 15000
POLL_CRYPTO_MS = 30000
POLL_CLOSED_MS = 120000
SPARK_URL = "https://query1.finance.yahoo.com/v7/finance/spark"
SEARCH_URL = "https://query2.finance.yahoo.com/v1/finance/search"
# Yahoo answers urllib's default agent with 429 Too Many Requests.
USER_AGENT = "Mozilla/5.0"


def omafinance_path():
    # Omafinance reads this exact path; it does not follow XDG_STATE_HOME.
    return Path.home() / ".local" / "state" / "omarchy" / "settings" / "finance.json"


def cache_path():
    root = os.environ.get("XDG_CACHE_HOME") or str(Path.home() / ".cache")
    return Path(root) / "ande.launcher" / "stocks.json"


def normalize_symbol(value):
    symbol = str(value or "").strip().upper()
    return symbol if SYMBOL_RE.match(symbol) else ""


def parse_symbols(values, limit=MAX_SYMBOLS):
    """Comma- or space-separated text, or a list, as unique valid symbols."""
    if isinstance(values, str):
        values = re.split(r"[\s,]+", values)
    out = []
    for value in values or []:
        symbol = normalize_symbol(value)
        if symbol and symbol not in out:
            out.append(symbol)
        if len(out) >= limit:
            break
    return out


def omafinance_watchlist(path=None):
    try:
        data = json.loads(Path(path or omafinance_path()).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []
    if not isinstance(data, dict) or not isinstance(data.get("watchlist"), list):
        return []
    return parse_symbols(data["watchlist"])


def number(value):
    if value is None or isinstance(value, bool):
        return None
    try:
        n = float(value)
    except (TypeError, ValueError):
        return None
    return n if n == n and n not in (float("inf"), float("-inf")) else None


def downsample(values, limit=SPARK_POINTS):
    """Every finite value, thinned to `limit` points. The last point is kept."""
    nums = [n for n in (number(v) for v in values or []) if n is not None]
    if len(nums) <= limit or limit < 2:
        return nums
    step = (len(nums) - 1) / (limit - 1)
    return [nums[round(i * step)] for i in range(limit)]


def periods(value):
    """Yahoo nests trading periods in lists of lists. Flatten to (start, end)."""
    if isinstance(value, list):
        out = []
        for item in value:
            out.extend(periods(item))
        return out
    if isinstance(value, dict):
        start, end = number(value.get("start")), number(value.get("end"))
        if start is not None and end is not None:
            return [(start, end)]
    return []


def session_from_meta(meta, now):
    """regular, pre, post, or closed. Crypto trades all day: live."""
    if not isinstance(meta, dict):
        return "closed"
    if str(meta.get("instrumentType") or "") == "CRYPTOCURRENCY":
        return "live"
    listed = meta.get("tradingPeriods") or {}
    current = meta.get("currentTradingPeriod") or {}
    for name in ("regular", "pre", "post"):
        windows = periods(listed.get(name)) + periods(current.get(name))
        if any(start <= now < end for start, end in windows):
            return name
    return "closed"


def quote_from_chart(result, fallback_symbol, now):
    """One spark result as the row the tile draws. Mirrors Omafinance's watchlist."""
    if not isinstance(result, dict) or not isinstance(result.get("meta"), dict):
        return None
    meta = result["meta"]
    symbol = normalize_symbol(meta.get("symbol") or fallback_symbol)
    if not symbol:
        return None

    regular = number(meta.get("regularMarketPrice"))
    previous = number(meta.get("chartPreviousClose"))
    if previous is None:
        previous = number(meta.get("previousClose"))
    regular_pct = number(meta.get("regularMarketChangePercent"))
    if regular_pct is None and regular is not None and previous:
        regular_pct = (regular - previous) / previous * 100

    session = session_from_meta(meta, now)
    fullday = number(meta.get("fulldayPrice"))
    # Out of hours, show the latest pre- or post-market print when it moved.
    extended = (
        bool(meta.get("hasPrePostMarketData"))
        and fullday is not None
        and regular is not None
        and abs(fullday - regular) >= 0.005
        and session not in ("regular", "live")
    )
    if extended:
        price = fullday
        pct = number(meta.get("fulldayChangePercent"))
        if pct is None and previous:
            pct = (fullday - previous) / previous * 100
        change = number(meta.get("fulldayChange"))
        if change is None and previous is not None:
            change = fullday - previous
    else:
        price = regular
        pct = regular_pct
        change = number(meta.get("regularMarketChange"))
        if change is None and regular is not None and previous is not None:
            change = regular - previous

    indicators = result.get("indicators") or {}
    quotes = indicators.get("quote") or [{}]
    closes = quotes[0].get("close") if quotes and isinstance(quotes[0], dict) else []
    hint = meta.get("priceHint")
    name = str(meta.get("shortName") or meta.get("longName") or symbol).strip()
    return {
        "symbol": symbol,
        "name": re.sub(r"\s+", " ", name),
        "type": str(meta.get("instrumentType") or ""),
        "currency": str(meta.get("currency") or "USD"),
        "price": price,
        "previousClose": previous,
        "change": change,
        "changePercent": pct,
        "session": session,
        "extended": extended,
        "priceHint": int(hint) if isinstance(hint, int) and 0 <= hint <= 8 else None,
        "closes": downsample(closes),
    }


def parse_spark(payload, now):
    out = {}
    spark = payload.get("spark") if isinstance(payload, dict) else None
    results = spark.get("result") if isinstance(spark, dict) else None
    for item in results or []:
        if not isinstance(item, dict):
            continue
        responses = item.get("response") or []
        quote = quote_from_chart(responses[0] if responses else None, item.get("symbol"), now)
        if quote:
            out[quote["symbol"]] = quote
    return out


def market_state(quotes):
    """The header word. Stocks, funds, and indexes set it when the list has any:
    futures trade nearly all night and would say "open" at 11 PM."""
    rows = [q for q in quotes if not q.get("missing")]
    exchange_hours = [q for q in rows if q.get("type") in EXCHANGE_HOURS]
    sessions = [q.get("session") for q in (exchange_hours or rows)]
    for name in ("regular", "pre", "post"):
        if name in sessions:
            return name
    if any(s != "live" for s in sessions):
        return "closed"
    return "live" if sessions else "closed"


def poll_ms(quotes):
    """Faster while any row is trading, even when the header says closed."""
    sessions = {q.get("session") for q in quotes if not q.get("missing")}
    if sessions & {"regular", "pre", "post"}:
        return POLL_OPEN_MS
    if "live" in sessions:
        return POLL_CRYPTO_MS
    return POLL_CLOSED_MS


def spark_url(symbols):
    query = urlencode({
        "symbols": ",".join(symbols),
        "range": "1d",
        "interval": "5m",
        "includePrePost": "true",
    })
    return SPARK_URL + "?" + query


def search_url(text):
    return SEARCH_URL + "?" + urlencode({
        "q": text,
        "quotesCount": SEARCH_LIMIT,
        "newsCount": 0,
    })


def fetch_json(url, timeout=8):
    request = Request(url, headers={"Accept": "application/json", "User-Agent": USER_AGENT})
    try:
        with urlopen(request, timeout=timeout) as response:
            return json.load(response)
    except HTTPError as error:
        # Every symbol unknown: Yahoo says 404 with a JSON body. That is an
        # answer (no rows), not an outage.
        if error.code == 404:
            return {"spark": {"result": []}}
        raise


def read_cache(path=None):
    try:
        data = json.loads(Path(path or cache_path()).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) and data.get("ok") is True else None


def write_cache(payload, path=None, now=None):
    if not isinstance(payload, dict) or payload.get("ok") is not True:
        return False
    target = Path(path or cache_path())
    body = dict(payload)
    body["savedAt"] = int(time.time() if now is None else now)
    try:
        target.parent.mkdir(parents=True, exist_ok=True)
        # The tile and the settings panel can both be writing.
        tmp = target.with_name(".%s.%d.tmp" % (target.name, os.getpid()))
        tmp.write_text(json.dumps(body, separators=(",", ":")), encoding="utf-8")
        tmp.replace(target)
        return True
    except OSError:
        return False


def collect(requested, now, fetch, watchlist_path=None):
    """The tile payload for `requested` (settings symbols, maybe empty)."""
    chosen = parse_symbols(requested)
    watchlist = omafinance_watchlist(watchlist_path)
    if chosen:
        source, symbols = "settings", chosen
    elif watchlist:
        source, symbols = "omafinance", watchlist
    else:
        source, symbols = "default", list(DEFAULT_SYMBOLS)
    base = {
        "request": ",".join(chosen),
        "source": source,
        "symbols": symbols,
        "watchlist": watchlist,
    }
    try:
        found = parse_spark(fetch(spark_url(symbols)), now)
    except Exception:  # noqa: BLE001 - any failure is "no answer" to the tile
        return dict(base, ok=False, error="Yahoo Finance did not answer", quotes=[])
    quotes = [found.get(symbol) or {"symbol": symbol, "missing": True} for symbol in symbols]
    market = market_state(quotes)
    return dict(base, ok=True, error="", market=market, pollMs=poll_ms(quotes), quotes=quotes)


def parse_search(payload):
    out = []
    rows = payload.get("quotes") if isinstance(payload, dict) else None
    for row in rows or []:
        if not isinstance(row, dict) or str(row.get("quoteType") or "") == "OPTION":
            continue
        symbol = normalize_symbol(row.get("symbol"))
        if not symbol or any(item["symbol"] == symbol for item in out):
            continue
        name = str(row.get("shortname") or row.get("longname") or symbol).strip()
        out.append({
            "symbol": symbol,
            "name": re.sub(r"\s+", " ", name),
            "type": str(row.get("quoteType") or "").strip(),
            "exchange": str(row.get("exchDisp") or row.get("exchange") or "").strip(),
        })
    return out[:SEARCH_LIMIT]


def search(text, fetch):
    query = str(text or "").strip()
    if not query:
        return []
    return parse_search(fetch(search_url(query)))


def option(args, name):
    if name not in args:
        return None
    index = args.index(name)
    return args[index + 1] if index + 1 < len(args) else ""


def main(argv):
    args = argv[1:]
    query = option(args, "--search")
    if query is not None:
        try:
            rows = search(query, fetch_json)
        except Exception:  # noqa: BLE001
            # The panel reads anything but a list as "search failed".
            json.dump({"error": "Yahoo Finance did not answer"}, sys.stdout)
            sys.stdout.write("\n")
            return 0
        json.dump(rows, sys.stdout)
        sys.stdout.write("\n")
        return 0
    payload = collect(option(args, "--symbols") or "", time.time(), fetch_json)
    write_cache(payload)
    json.dump(payload, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
