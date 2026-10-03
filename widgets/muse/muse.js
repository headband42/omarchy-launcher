// Presentation helpers for the Muse tile.
//
// Pure functions over the payload muse.py built. Widget.qml imports this
// file and the Node tests require it. Times are formatted by
// ../_kit/usage.js, and the tile passes the result in.

function label(meter) {
  return String((meter && meter.label) || "").toUpperCase()
}

// Under a bar: when the quota frees up. `reset` is Usage.resetLine() for it.
function detailLine(meter, reset) {
  if (!meter) return ""
  if (meter.idle) return "starts with your next message"
  if (reset) return reset
  return ""
}

// After the title: the plan as the provider named it, or nothing.
function planName(sample) {
  return String((sample && sample.plan) || "")
}

// No sign-in, an expired one, and no subscription each say which,
// because the fix is different for each.
function emptyHeadline(sample) {
  if (!sample || sample.ok === undefined) return "Reading Muse usage…"
  var reason = String(sample.reason || "")
  if (reason === "signin") return "No Muse sign-in"
  if (reason === "expired") return "Sign-in expired"
  if (reason === "plan") return "No subscription"
  return "Muse usage unavailable"
}

function emptyBody(sample) {
  if (!sample || sample.ok === undefined) return ""
  var reason = String(sample.reason || "")
  if (reason === "signin")
    return "Run muse login and sign in with your Meta account. An API key has no subscription quota to show."
  if (reason === "expired") return "Run muse login again to renew it."
  return String(sample.error || "Meta is not answering")
}

// The last good reply muse.py saved, if it is one.
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
    planName: planName,
    emptyHeadline: emptyHeadline,
    emptyBody: emptyBody,
    fromCache: fromCache
  }
}
