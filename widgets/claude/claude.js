// Presentation helpers for the Claude tile.
//
// Pure functions over the payload claude.py built. Widget.qml imports this
// file and the Node tests require it. Times are formatted by
// ../_kit/usage.js, and the tile passes the result in.

function label(meter) {
  return String((meter && meter.label) || "").toUpperCase()
}

// Under a bar: when the limit frees up. `reset` is Usage.resetLine() for it.
function detailLine(meter, reset) {
  if (!meter) return ""
  if (meter.idle) return "starts with your next message"
  if (reset) return reset
  if (meter.id === "extra_usage") return "pay as you go, past the plan"
  return ""
}

function planLabel(sample) {
  var plan = String((sample && sample.plan) || "")
  return plan ? plan.toUpperCase() : "CLAUDE"
}

// No sign-in, an expired one, and a sign-in with no limits each say which,
// because the fix is different for each.
function emptyHeadline(sample) {
  if (!sample || sample.ok === undefined) return "Reading Claude usage…"
  var reason = String(sample.reason || "")
  if (reason === "signin") return "No Claude sign-in"
  if (reason === "expired") return "Sign-in expired"
  if (reason === "plan") return "No plan limits"
  return "Claude usage unavailable"
}

function emptyBody(sample) {
  if (!sample || sample.ok === undefined) return ""
  var reason = String(sample.reason || "")
  if (reason === "signin")
    return "Run claude and sign in with your Claude account. An API key has no plan limits to show."
  if (reason === "expired") return "Claude Code renews it the next time it runs."
  return String(sample.error || "Anthropic is not answering")
}

// The last good reply claude.py saved, if it is one.
function fromCache(raw) {
  var data = null
  try { data = JSON.parse(String(raw || "")) } catch (e) { return null }
  if (!data || typeof data !== "object" || data.ok !== true) return null
  if (!data.meters || typeof data.meters.length !== "number" || !data.meters.length) return null
  return data
}

if (typeof module !== "undefined") {
  module.exports = {
    label: label,
    detailLine: detailLine,
    planLabel: planLabel,
    emptyHeadline: emptyHeadline,
    emptyBody: emptyBody,
    fromCache: fromCache
  }
}
