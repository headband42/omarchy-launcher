// Presentation helpers for the OpenCode Go tile.
//
// Pure functions over the payload opencode.py built. Widget.qml and
// Settings.qml import this file and the Node tests require it.
//
// QML's JavaScript engine is ES7 without modules, so this file uses `var` and
// `function` and nothing else.

// $12.00, $1.25, $12 — cents only when they are worth the column.
function money(value) {
  if (value === null || value === undefined) return "—"
  var number = Number(value)
  if (!isFinite(number)) return "—"
  var rounded = Math.round(number * 100) / 100
  var whole = Math.floor(rounded)
  var cents = Math.round((rounded - whole) * 100)
  if (cents === 0) return "$" + whole
  return "$" + whole + "." + (cents < 10 ? "0" + cents : String(cents))
}

function moneyExact(value) {
  if (value === null || value === undefined) return "—"
  var number = Number(value)
  if (!isFinite(number)) return "—"
  return "$" + number.toFixed(2)
}

// The percentage, rounded for reading. A block over its limit says so rather
// than being clipped to 100.
// Number(null) is 0, so a block that reported no percentage would otherwise
// be drawn as a confident zero.
function meterPercent(meter) {
  if (!meter) return NaN
  var raw = meter.percent
  if (raw === null || raw === undefined || raw === "") return NaN
  var value = Number(raw)
  return isFinite(value) ? value : NaN
}

function percent(meter) {
  var value = meterPercent(meter)
  if (!isFinite(value)) return "—"
  // Never negative, and never quietly shortened: a block over its limit
  // still reads over 100%.
  if (value < 0) value = 0
  return Math.round(value) + "%"
}

// How full the bar is drawn. The bar stops at 100 even though the number does
// not, because there is nowhere further to fill.
function fill(meter) {
  var value = meterPercent(meter)
  if (!isFinite(value) || value <= 0) return 0
  return Math.min(1, value / 100)
}

// The palette token a bar is drawn in: calm, then warm as a block fills up,
// then urgent once it is over.
function tone(meter) {
  if (!meter) return "muted"
  if (meter.over) return "urgent"
  var value = meterPercent(meter)
  if (!isFinite(value)) return "muted"
  if (value >= 80) return "urgent"
  if (value >= 50) return "warm"
  return "calm"
}

// Where a tone sits on the ramp from the theme's accent to its urgent color,
// so the bar warms up as a block fills. The colors themselves belong to QML.
function toneFraction(name) {
  var tone = String(name || "")
  if (tone === "urgent") return 1
  if (tone === "warm") return 0.55
  if (tone === "calm") return 0
  return 0.15
}

function label(meter) {
  return String((meter && meter.label) || "").toUpperCase()
}

function usedLine(meter) {
  if (!meter) return ""
  return money(meter.used) + " of " + money(meter.limit)
}

// The reset line. "in 4h 04m" is what a person acts on; the calendar day is
// what they check when the block is further out.
function resetLine(meter, style) {
  if (!meter) return ""
  if (meter.expired) return "resetting"
  if (style === "absolute") {
    var day = String(meter.resetDay || "")
    return day ? "resets " + day : ""
  }
  var countdown = String(meter.resetCountdown || "")
  return countdown ? "resets in " + countdown : ""
}

// "Renews Oct 26" for the subscription itself.
function renewalLine(sample) {
  if (!sample) return ""
  var day = String(sample.renewalDay || "")
  if (sample.canceling) return day ? "ends " + day : "ending"
  if (sample.renewalPending) return day ? "renews " + day : "renewing"
  return day ? "through " + day : ""
}

function statusText(sample) {
  if (!sample) return ""
  if (!sample.ok) return "OFFLINE"
  if (sample.canceling) return "ENDING"
  if (sample.active) return "ACTIVE"
  return "PAUSED"
}

function statusTone(sample) {
  if (!sample) return "muted"
  if (!sample.ok) return "muted"
  if (sample.canceling) return "warm"
  if (sample.active) return "calm"
  return "muted"
}

function metersOf(sample, hidden) {
  var rows = sample && sample.meters
  if (!rows || !rows.length) return []
  var hide = hidden && String(hidden) ? String(hidden).split(",") : []
  if (!hide.length) return rows
  var out = []
  for (var i = 0; i < rows.length; i++) {
    if (hide.indexOf(String(rows[i].id)) < 0) out.push(rows[i])
  }
  return out
}

// The headline percentage is the block closest to its ceiling, which is the
// one worth a glance.
function headlinePercent(meters) {
  if (!meters || !meters.length) return "—"
  var worst = meters[0]
  for (var i = 1; i < meters.length; i++) {
    var mine = Number(meters[i].percent)
    var theirs = Number(worst.percent)
    if (isFinite(mine) && (!isFinite(theirs) || mine > theirs)) worst = meters[i]
  }
  return percent(worst)
}

function planLabel(sample) {
  if (!sample) return "OPENCODE"
  var plan = String(sample.plan || "")
  return plan ? plan.toUpperCase() : "OPENCODE"
}

function emptyHeadline(sample) {
  if (sample && sample.ok === false) return "Go usage unavailable"
  if (sample && sample.meters && !sample.meters.length) return "No Go blocks"
  return "OPENCODE"
}

function emptyBody(sample) {
  if (sample && sample.ok === false) return String(sample.error || "OpenCode is not answering")
  if (sample && !sample.meters) return "Waiting for the console."
  return "This account has no Go usage blocks."
}

if (typeof module !== "undefined") {
  module.exports = {
    emptyBody: emptyBody,
    emptyHeadline: emptyHeadline,
    fill: fill,
    headlinePercent: headlinePercent,
    label: label,
    metersOf: metersOf,
    money: money,
    moneyExact: moneyExact,
    percent: percent,
    planLabel: planLabel,
    renewalLine: renewalLine,
    resetLine: resetLine,
    statusText: statusText,
    statusTone: statusTone,
    tone: tone,
    toneFraction: toneFraction,
    usedLine: usedLine
  }
}
