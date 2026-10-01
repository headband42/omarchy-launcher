#!/usr/bin/env node
// Ticker lists, price formatting, row layout, cache, and sparkline math.
//
// Run from the repo root:  node --test widgets/stocks/test_logic.cjs

const { describe, it } = require("node:test");
const assert = require("node:assert/strict");
const path = require("path");

const Stocks = require(path.join(__dirname, "stocks.js"));

describe("symbol lists", () => {
  it("keeps unique valid symbols, upper-cased, capped at six", () => {
    assert.deepEqual(
      Stocks.normalizeSymbols({ symbols: [" msft", "brk-b", "^gspc", "MSFT", "../x", "", "btc-usd", "gc=f", "eurusd=x", "7203.t"] }),
      ["MSFT", "BRK-B", "^GSPC", "BTC-USD", "GC=F", "EURUSD=X"]
    );
    assert.deepEqual(Stocks.normalizeSymbols(null), []);
    assert.deepEqual(Stocks.normalizeSymbols({ symbols: "MSFT" }), []);
  });

  it("accepts an array-like list from a QML property", () => {
    const like = { 0: "mu", 1: "tsla", length: 2 };
    assert.deepEqual(Stocks.normalizeSymbols({ symbols: like }), ["MU", "TSLA"]);
    assert.deepEqual(Stocks.toList(like), ["mu", "tsla"]);
    assert.deepEqual(Stocks.toList("text"), []);
  });

  it("stores the list, or null to follow Omafinance again", () => {
    assert.deepEqual(Stocks.settingsFromSymbols(["mu", "MU", "nvda"]), { symbols: ["MU", "NVDA"] });
    assert.equal(Stocks.settingsFromSymbols([]), null);
    assert.equal(Stocks.requestKey({ symbols: ["mu", "nvda"] }), "MU,NVDA");
    assert.equal(Stocks.requestKey({}), "");
  });

  it("reads Omafinance's watchlist", () => {
    assert.deepEqual(Stocks.parseWatchlist('{"watchlist":["tsla","SPCX"],"pinned":["MU"]}'), ["TSLA", "SPCX"]);
    assert.deepEqual(Stocks.parseWatchlist("nope"), []);
    assert.deepEqual(Stocks.parseWatchlist("{}"), []);
  });
});

describe("formatting", () => {
  it("prices use Yahoo's hint, commas, and a currency sign", () => {
    assert.equal(Stocks.formatPrice(83421.234, "USD", 2), "$83,421.23");
    assert.equal(Stocks.formatPrice(1.1329, "USD", 4), "$1.1329");
    assert.equal(Stocks.formatPrice(0.5, "USD", 2), "$0.5000");
    assert.equal(Stocks.formatPrice(0.004, "USD", null), "$0.004000");
    assert.equal(Stocks.formatPrice(612.4, "EUR", 2), "€612.40");
    assert.equal(Stocks.formatPrice(72.34, "GBp", 2), "72.34p");
    assert.equal(Stocks.formatPrice(1234.5, "CHF", 2), "1,234.50 CHF");
    assert.equal(Stocks.formatPrice(null, "USD", 2), "—");
  });

  it("changes carry a sign and a tone", () => {
    assert.equal(Stocks.formatPercent(1.0739), "+1.07%");
    assert.equal(Stocks.formatPercent(-0.051), "-0.05%");
    assert.equal(Stocks.formatPercent(0), "0.00%");
    assert.equal(Stocks.formatPercent(undefined), "—");
    assert.equal(Stocks.changeTone(0.2), "up");
    assert.equal(Stocks.changeTone(-0.2), "down");
    assert.equal(Stocks.changeTone(0), "flat");
    assert.equal(Stocks.changeTone(null), "flat");
  });

  it("widest finds the longest text in each column", () => {
    const widest = Stocks.widest([
      { symbol: "MU", price: 1064.54, currency: "USD", priceHint: 2, changePercent: -0.05 },
      { symbol: "BTC-USD", price: 83421.23, currency: "USD", priceHint: 2, changePercent: 10.4 },
      { symbol: "ZZZZQQ", missing: true }
    ]);
    assert.deepEqual(widest, { symbol: "BTC-USD", price: "$83,421.23", change: "+10.40%" });
  });

  it("market words for the header", () => {
    assert.equal(Stocks.marketLabel("regular"), "open");
    assert.equal(Stocks.marketLabel("post"), "after hours");
    assert.equal(Stocks.marketLabel("live"), "24/7");
    assert.equal(Stocks.marketLabel(undefined), "");
  });

  it("quote links are Yahoo pages, encoded", () => {
    assert.equal(Stocks.quoteUrl("^gspc"), "https://finance.yahoo.com/quote/%5EGSPC/");
    assert.equal(Stocks.quoteUrl("GC=F"), "https://finance.yahoo.com/quote/GC%3DF/");
    assert.equal(Stocks.quoteUrl("a b"), "");
  });
});

describe("rowPlan", () => {
  it("grows rows up to the max when few", () => {
    assert.deepEqual(Stocks.rowPlan(3, 228, 38, 56, 36), { rows: 3, height: 56, names: true });
  });

  it("shares the height when many fit", () => {
    assert.deepEqual(Stocks.rowPlan(6, 228, 38, 56, 36), { rows: 6, height: 38, names: true });
  });

  it("cuts the list instead of overlapping rows", () => {
    assert.deepEqual(Stocks.rowPlan(6, 180, 38, 56, 36), { rows: 4, height: 45, names: true });
  });

  it("drops names below their row height, and shows nothing with no room", () => {
    assert.equal(Stocks.rowPlan(2, 70, 30, 56, 40).names, false);
    assert.deepEqual(Stocks.rowPlan(3, 20, 38, 56, 36), { rows: 0, height: 0, names: false });
    assert.deepEqual(Stocks.rowPlan(0, 228, 38, 56, 36), { rows: 0, height: 0, names: false });
  });
});

describe("fromCache", () => {
  const saved = JSON.stringify({ ok: true, request: "MU", quotes: [{ symbol: "MU" }], savedAt: 5 });

  it("answers only the same request", () => {
    assert.equal(Stocks.fromCache(saved, "MU").quotes[0].symbol, "MU");
    assert.equal(Stocks.fromCache(saved, ""), null);
  });

  it("ignores failures and junk", () => {
    assert.equal(Stocks.fromCache(JSON.stringify({ ok: false, request: "", quotes: [] }), ""), null);
    assert.equal(Stocks.fromCache("{", ""), null);
    assert.equal(Stocks.fromCache("", ""), null);
  });
});

describe("sparkGeometry", () => {
  it("spans the width and keeps an 8% margin", () => {
    const g = Stocks.sparkGeometry([1, null, 2, 3], 102, 50, 1, NaN, false);
    assert.deepEqual(g.xs, [1, 51, 101]);
    // 3 is the top value; the range is padded by 8% of 2 on each side.
    const span = 2 * 1.16;
    assert.ok(Math.abs(g.ys[2] - (1 + 48 * (1 - (3 - (1 - 0.16)) / span))) < 1e-9);
    assert.ok(g.ys[0] > g.ys[1] && g.ys[1] > g.ys[2]);
    assert.ok(Number.isNaN(g.closeY));
  });

  it("keeps the previous close in range when it is drawn", () => {
    const g = Stocks.sparkGeometry([10, 11], 100, 40, 2, 20, true);
    assert.ok(g.closeY >= 2 && g.closeY < g.ys[1]);
    const hidden = Stocks.sparkGeometry([10, 11], 100, 40, 2, 20, false);
    assert.ok(Number.isNaN(hidden.closeY));
  });

  it("handles one point, a flat day, and no data", () => {
    assert.deepEqual(Stocks.sparkGeometry([5], 100, 40, 0, NaN, false).xs, [50]);
    const flat = Stocks.sparkGeometry([5, 5, 5], 100, 40, 0, NaN, false);
    assert.ok(flat.ys.every((y) => y === flat.ys[0] && y > 0 && y < 40));
    assert.deepEqual(Stocks.sparkGeometry([], 100, 40, 2, NaN, false).xs, []);
    assert.deepEqual(Stocks.sparkGeometry({ 0: 1, 1: 2, length: 2 }, 100, 40, 0, NaN, false).xs, [0, 100]);
  });
});
