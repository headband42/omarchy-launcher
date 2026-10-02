// Pure helpers for the stocks widget. QML imports this file;
// node tests require it. Keep it free of Qt types.

var MAX_SYMBOLS = 6
// Same rule as stocks.py: MSFT, BRK-B, ^GSPC, BTC-USD, GC=F, EURUSD=X, 7203.T
var SYMBOL_RE = /^[A-Z0-9^][A-Z0-9.=^-]{0,19}$/
var CURRENCY_SIGNS = { USD: "$", EUR: "€", GBP: "£", JPY: "¥" }

function maxSymbols() { return MAX_SYMBOLS }

function normalizeSymbol(value) {
  var symbol = String(value || "").trim().toUpperCase()
  return SYMBOL_RE.test(symbol) ? symbol : ""
}

// settings.symbols: unique valid symbols, at most MAX_SYMBOLS, in order.
function normalizeSymbols(settings) {
  var raw = toList(settings && settings.symbols)
  var out = []
  for (var i = 0; i < raw.length && out.length < MAX_SYMBOLS; i++) {
    var symbol = normalizeSymbol(raw[i])
    if (symbol && out.indexOf(symbol) < 0) out.push(symbol)
  }
  return out
}

// What the panel stores. null forgets the list, and the tile follows
// Omafinance's watchlist again.
function settingsFromSymbols(list) {
  var symbols = normalizeSymbols({ symbols: list })
  return symbols.length ? { symbols: symbols } : null
}

// Omafinance's state file, { "watchlist": [...] }, read by the same rule as stocks.py.
function parseWatchlist(raw) {
  var data = null
  try { data = JSON.parse(String(raw || "")) } catch (e) { return [] }
  return normalizeSymbols({ symbols: data && data.watchlist })
}

// The --symbols argument, and the `request` a reply carries back.
function requestKey(settings) {
  return normalizeSymbols(settings).join(",")
}

// A list that crossed a QML `var` property (a Repeater's modelData) is
// array-like but not an Array, so Array.isArray() would drop it.
function toList(value) {
  if (Array.isArray(value)) return value
  if (value && typeof value === "object" && typeof value.length === "number")
    return Array.prototype.slice.call(value)
  return []
}

function finite(value) {
  if (value === null || value === undefined || value === "" || typeof value === "boolean") return null
  var n = Number(value)
  return isFinite(n) ? n : null
}

function changeTone(pct) {
  var n = finite(pct)
  if (n === null || n === 0) return "flat"
  return n > 0 ? "up" : "down"
}

function withCommas(text) {
  var parts = String(text).split(".")
  parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",")
  return parts.join(".")
}

// Yahoo's priceHint, with at least four places under a dollar (Omafinance's rule).
function priceDecimals(price, hint) {
  var abs = Math.abs(Number(price))
  var h = parseInt(hint, 10)
  if (isFinite(h) && h >= 0 && h <= 8) return abs > 0 && abs < 1 ? Math.max(h, 4) : h
  if (!isFinite(abs) || abs >= 1) return 2
  return abs >= 0.01 ? 4 : 6
}

function formatPrice(price, currency, hint) {
  var n = finite(price)
  if (n === null) return "—"
  var body = withCommas(n.toFixed(priceDecimals(n, hint)))
  var code = String(currency || "USD")
  // London quotes in pence.
  if (code === "GBp" || code === "GBX") return body + "p"
  if (CURRENCY_SIGNS[code]) return (n < 0 ? "-" + CURRENCY_SIGNS[code] + body.slice(1) : CURRENCY_SIGNS[code] + body)
  return body + " " + code
}

function formatPercent(pct) {
  var n = finite(pct)
  if (n === null) return "—"
  return (n > 0 ? "+" : "") + n.toFixed(2) + "%"
}

function isMissing(quote) {
  return !quote || quote.missing === true || finite(quote.price) === null
}

// The longest symbol, price, and change among the rows. The menu font is
// monospaced, so the longest string sizes each column.
function widest(quotes) {
  var out = { symbol: "", price: "", change: "" }
  var list = toList(quotes)
  for (var i = 0; i < list.length; i++) {
    var quote = list[i] || {}
    var symbol = String(quote.symbol || "")
    var price = formatPrice(quote.price, quote.currency, quote.priceHint)
    var change = isMissing(quote) ? "" : formatPercent(quote.changePercent)
    if (symbol.length > out.symbol.length) out.symbol = symbol
    if (price.length > out.price.length) out.price = price
    if (change.length > out.change.length) out.change = change
  }
  return out
}

// How many rows fit in `height`, and how tall each is. Rows grow up to
// maxRow, shrink to minRow, and past that the list is cut at the bottom.
// The company name shows once a row has room for two lines.
function rowPlan(count, height, minRow, maxRow, nameRow) {
  var n = Math.max(0, Math.floor(Number(count) || 0))
  var h = Math.max(0, Number(height) || 0)
  var lo = Math.max(1, Number(minRow) || 1)
  var hi = Math.max(lo, Number(maxRow) || lo)
  if (n === 0 || h < lo) return { rows: 0, height: 0, names: false }
  var rows = Math.min(n, Math.floor(h / lo))
  var each = Math.floor(Math.min(hi, h / rows))
  return { rows: rows, height: each, names: each >= (Number(nameRow) || 0) }
}

function marketLabel(market) {
  switch (String(market || "")) {
    case "regular": return "open"
    case "pre": return "pre-market"
    case "post": return "after hours"
    case "closed": return "closed"
    case "live": return "24/7"
    default: return ""
  }
}

function quoteUrl(symbol) {
  var value = normalizeSymbol(symbol)
  if (!value) return ""
  return "https://finance.yahoo.com/quote/" + encodeURIComponent(value) + "/"
}

// The cache file stocks.py saves, if it answers this request.
function fromCache(raw, request) {
  var data = null
  try { data = JSON.parse(String(raw || "")) } catch (e) { return null }
  if (!data || typeof data !== "object" || data.ok !== true || !Array.isArray(data.quotes)) return null
  if (String(data.request || "") !== String(request || "")) return null
  return data
}

// Points for the sparkline, after Omafinance's: an 8% margin above and below,
// and the previous close kept in range when its dashed line is drawn.
function sparkGeometry(values, width, height, pad, previousClose, showPreviousClose) {
  var nums = []
  var list = toList(values)
  for (var i = 0; i < list.length; i++) {
    var n = finite(list[i])
    if (n !== null) nums.push(n)
  }
  var p = Math.max(0, Number(pad) || 0)
  var left = p
  var right = Math.max(left + 1, (Number(width) || 0) - p)
  var top = p
  var bottom = Math.max(top + 1, (Number(height) || 0) - p)
  var out = { xs: [], ys: [], left: left, right: right, bottom: bottom, closeY: NaN }
  if (nums.length === 0) return out

  var min = Math.min.apply(null, nums)
  var max = Math.max.apply(null, nums)
  var close = finite(previousClose)
  var drawClose = !!showPreviousClose && close !== null
  if (drawClose) {
    min = Math.min(min, close)
    max = Math.max(max, close)
  }
  var span = max - min
  if (span === 0) span = Math.abs(max) * 0.01 || 1
  min -= span * 0.08
  max += span * 0.08
  span = max - min

  var innerW = right - left
  var innerH = bottom - top
  for (var j = 0; j < nums.length; j++) {
    out.xs.push(nums.length === 1 ? left + innerW / 2 : left + innerW * j / (nums.length - 1))
    out.ys.push(top + innerH * (1 - (nums[j] - min) / span))
  }
  if (drawClose) out.closeY = top + innerH * (1 - (close - min) / span)
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    MAX_SYMBOLS: MAX_SYMBOLS,
    maxSymbols: maxSymbols,
    toList: toList,
    normalizeSymbol: normalizeSymbol,
    normalizeSymbols: normalizeSymbols,
    settingsFromSymbols: settingsFromSymbols,
    parseWatchlist: parseWatchlist,
    requestKey: requestKey,
    changeTone: changeTone,
    formatPrice: formatPrice,
    formatPercent: formatPercent,
    isMissing: isMissing,
    widest: widest,
    rowPlan: rowPlan,
    marketLabel: marketLabel,
    quoteUrl: quoteUrl,
    fromCache: fromCache,
    sparkGeometry: sparkGeometry
  }
}
