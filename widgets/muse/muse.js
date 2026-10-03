// Presentation helpers for the Muse tile.
//
// Pure functions over the payload muse.py built. Widget.qml imports this
// file and the Node tests require it. The sampler composes the line under
// each bar, since nothing on this tile counts down.

function label(meter) {
  return String((meter && meter.label) || "").toUpperCase()
}

// A reset would win, if a meter had one; none does yet.
function detailLine(meter, reset) {
  if (!meter) return ""
  if (reset) return reset
  return String(meter.detail || "")
}

function planLabel(sample) {
  var plan = String((sample && sample.plan) || "")
  return plan ? plan.toUpperCase() : "MUSE"
}

// After the title: "muse-spark-1.3-contributor" reads "spark-1.3".
function modelShort(sample) {
  var model = String((sample && sample.model) || "")
  if (model.indexOf("muse-") === 0) model = model.slice("muse-".length)
  var suffix = "-contributor"
  if (model.length > suffix.length && model.slice(-suffix.length) === suffix)
    model = model.slice(0, -suffix.length)
  return model
}

function emptyHeadline(sample) {
  if (!sample || sample.ok === undefined) return "Reading Muse usage…"
  if (String(sample.reason || "") === "empty") return "No Muse usage yet"
  return "Muse usage unavailable"
}

function emptyBody(sample) {
  if (!sample || sample.ok === undefined) return ""
  if (String(sample.reason || "") === "empty")
    return "Run muse and the tile fills in from its session logs."
  return String(sample.error || "The session logs are not answering")
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
    planLabel: planLabel,
    modelShort: modelShort,
    emptyHeadline: emptyHeadline,
    emptyBody: emptyBody,
    fromCache: fromCache
  }
}
