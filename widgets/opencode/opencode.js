// Presentation helpers for the OpenCode Go tile.
//
// Pure functions over the payload opencode.py built. Widget.qml and
// Settings.qml import this file and the Node tests require it. Times are
// formatted by ../_kit/usage.js, and the tile passes the result in.

// $12.00, $1.25, $12 — cents only when they are worth the column.
function money(value) {
  if (value === null || value === undefined || value === "") return "—"
  var number = Number(value)
  if (!isFinite(number)) return "—"
  var rounded = Math.round(number * 100) / 100
  var whole = Math.floor(rounded)
  var cents = Math.round((rounded - whole) * 100)
  if (cents === 0) return "$" + whole
  return "$" + whole + "." + (cents < 10 ? "0" + cents : String(cents))
}

function label(meter) {
  return String((meter && meter.label) || "").toUpperCase()
}

function usedLine(meter) {
  if (!meter) return ""
  return money(meter.used) + " of " + money(meter.limit)
}

// Under a bar: what is spent of what, and when the block frees up. `reset`
// is Usage.resetLine() for the block. A rolling block with no window yet
// starts with the next request.
function detailLine(meter, reset, showAmounts) {
  if (!meter) return ""
  var parts = []
  if (showAmounts !== false) parts.push(usedLine(meter))
  if (meter.idle) parts.push("starts with your next request")
  else if (reset) parts.push(reset)
  return parts.join(" · ")
}

// Under the headline number: which block it is.
function headlineCaption(meter) {
  if (!meter) return ""
  if (meter.id === "fiveHour") return "of the 5-hour block"
  if (meter.id === "week") return "of this week’s block"
  if (meter.id === "month") return "of this month’s block"
  return "of the " + String(meter.label || meter.id || "").toLowerCase() + " block"
}

// The subscription period, from Usage.dayLabel() of its end.
function renewalLine(sample, day) {
  if (!sample || !sample.ok) return ""
  var when = String(day || "")
  if (sample.canceling) return when ? "ends " + when : "ending"
  if (sample.renewalPending) return when ? "renews " + when : "renewing"
  return when ? "through " + when : ""
}

function statusText(sample) {
  if (!sample || !sample.ok) return ""
  if (sample.canceling) return "ending"
  if (sample.active) return "active"
  return "paused"
}

function planLabel(sample) {
  var plan = String((sample && sample.plan) || "")
  return plan ? plan.toUpperCase() : "OPENCODE GO"
}

// No console account, an expired sign-in, and a plan with no blocks each say
// which, because the fix is different for each.
function emptyHeadline(sample) {
  var reason = String((sample && sample.reason) || "")
  if (!sample || sample.ok === undefined) return "Reading OpenCode Go…"
  if (reason === "signin") return "No console account"
  if (reason === "expired") return "Sign-in expired"
  if (reason === "plan") return "No Go plan"
  return "Go usage unavailable"
}

function emptyBody(sample) {
  var reason = String((sample && sample.reason) || "")
  if (!sample || sample.ok === undefined) return ""
  if (reason === "signin") return "Sign in to the OpenCode console on this computer and the tile picks it up."
  if (reason === "expired") return "Sign in to the OpenCode console again."
  return String(sample.error || "OpenCode is not answering")
}

// The last good reply opencode.py saved, if it is one.
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
    usedLine: usedLine,
    detailLine: detailLine,
    headlineCaption: headlineCaption,
    renewalLine: renewalLine,
    statusText: statusText,
    planLabel: planLabel,
    emptyHeadline: emptyHeadline,
    emptyBody: emptyBody,
    fromCache: fromCache
  }
}
