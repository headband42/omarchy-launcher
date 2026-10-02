// Presentation helpers for the Grok tile.
//
// Pure functions over the payload grok.py built. Widget.qml imports this
// file and the Node tests require it. Times are formatted by
// ../_kit/usage.js, and the tile passes the result in.

// $12, $12.50 — cents only when the amount has them. Money is already dollars.
function money(value) {
  if (value === null || value === undefined || value === "") return ""
  var number = Number(value)
  if (!isFinite(number)) return ""
  var cents = Math.round(Math.abs(number) * 100)
  var whole = Math.floor(cents / 100)
  var rest = cents % 100
  if (rest === 0) return "$" + whole
  return "$" + whole + "." + (rest < 10 ? "0" : "") + rest
}

function label(meter) {
  return String((meter && meter.label) || "").toUpperCase()
}

// Under a bar: the dollars, when this limit is one, and when it frees up.
// `reset` is Usage.resetLine() for it.
function detailLine(meter, reset) {
  if (!meter) return ""
  var parts = []
  var used = money(meter.used)
  var limit = money(meter.limit)
  if (used && limit) parts.push(used + " of " + limit)
  if (reset) parts.push(reset)
  return parts.join(" · ")
}

function planLabel(sample) {
  var plan = String((sample && sample.plan) || "")
  return plan ? plan.toUpperCase() : "GROK"
}

// Bought credits, once the balance is worth showing.
function footerLine(sample) {
  if (!sample || !sample.ok) return ""
  var credits = money(sample.credits)
  return credits ? "credits " + credits : ""
}

// No sign-in, an expired one, and a sign-in with no limits each say which,
// because the fix is different for each.
function emptyHeadline(sample) {
  if (!sample || sample.ok === undefined) return "Reading Grok usage…"
  var reason = String(sample.reason || "")
  if (reason === "signin") return "No Grok sign-in"
  if (reason === "expired") return "Sign-in expired"
  if (reason === "plan") return "No usage limits"
  return "Grok usage unavailable"
}

function emptyBody(sample) {
  if (!sample || sample.ok === undefined) return ""
  var reason = String(sample.reason || "")
  if (reason === "signin")
    return "Run grok and sign in. An API key has no plan limits to show."
  if (reason === "expired") return "Grok renews it the next time it runs."
  return String(sample.error || "Grok is not answering")
}

// The last good reply grok.py saved, if it is one.
function fromCache(raw) {
  var data = null
  try { data = JSON.parse(String(raw || "")) } catch (e) { return null }
  if (!data || typeof data !== "object" || data.ok !== true) return null
  if (!data.meters || typeof data.meters.length !== "number" || !data.meters.length) return null
  return data
}

if (typeof module !== "undefined") {
  module.exports = {
    money: money,
    label: label,
    detailLine: detailLine,
    planLabel: planLabel,
    footerLine: footerLine,
    emptyHeadline: emptyHeadline,
    emptyBody: emptyBody,
    fromCache: fromCache
  }
}
