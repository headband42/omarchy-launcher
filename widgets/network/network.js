// Logic for the network tile. Widget.qml imports it; test_logic.cjs requires it.

var HISTORY = 40

// Bytes a second between two samples of the same interface, or null when the
// pair cannot give one (a different interface, a counter reset, no time).
function rateBetween(prev, next) {
  if (!prev || !next || prev.device !== next.device || !next.device) return null
  var dt = (Number(next.at) - Number(prev.at)) / 1000
  if (!(dt > 0) || dt > 60) return null
  var rx = Number(next.rx) - Number(prev.rx)
  var tx = Number(next.tx) - Number(prev.tx)
  if (!isFinite(rx) || !isFinite(tx) || rx < 0 || tx < 0) return null
  return { down: rx / dt, up: tx / dt }
}

// The rate to show for a new sample: between the tile's own samples when it
// has the previous one, else the sampler's short first measurement.
function pickRate(prev, next) {
  var between = rateBetween(prev, next)
  if (between) return between
  var own = next && next.rate
  if (own && isFinite(Number(own.down)) && isFinite(Number(own.up)))
    return { down: Number(own.down), up: Number(own.up) }
  return null
}

function pushHistory(list, value, max) {
  var out = Array.isArray(list) ? list.slice() : []
  out.push(Math.max(0, Number(value) || 0))
  var limit = max || HISTORY
  while (out.length > limit) out.shift()
  return out
}

function fmtBytes(value) {
  var n = Math.max(0, Number(value) || 0)
  var units = ["B", "KB", "MB", "GB", "TB"]
  var i = 0
  while (n >= 1000 && i < units.length - 1) {
    n /= 1000
    i++
  }
  var digits = i === 0 || n >= 100 ? 0 : (n >= 10 ? 0 : 1)
  return n.toFixed(digits) + " " + units[i]
}

function fmtRate(value) {
  if (value === null || value === undefined || !isFinite(Number(value))) return "—"
  return fmtBytes(value) + "/s"
}

// A link speed in Mb/s, as the kernel reports it.
function fmtLinkSpeed(mbps) {
  var n = Number(mbps) || 0
  if (n <= 0) return ""
  if (n >= 1000) {
    var gb = n / 1000
    return (gb === Math.floor(gb) ? String(gb) : gb.toFixed(1)) + " Gb/s"
  }
  return n + " Mb/s"
}

function signalGlyph(percent) {
  if (percent === null || percent === undefined) return "󰤨"
  var p = Number(percent)
  if (p >= 80) return "󰤨"
  if (p >= 60) return "󰤥"
  if (p >= 40) return "󰤢"
  if (p >= 20) return "󰤟"
  return "󰤯"
}

function glyph(sample) {
  var kind = sample && sample.kind
  if (kind === "wifi") return signalGlyph(sample.signal)
  if (kind === "ethernet") return "󰈀"
  if (kind === "tunnel") return "󰖂"
  return "󰤮"
}

function kindLabel(sample) {
  var kind = sample && sample.kind
  if (kind === "wifi") return "Wi-Fi"
  if (kind === "ethernet") return "Ethernet"
  if (kind === "tunnel") return "VPN"
  return "Offline"
}

// The big line: the network's name.
function title(sample) {
  if (!sample || !sample.device) return "Offline"
  if (sample.kind === "wifi") return String(sample.name || "") || "Wi-Fi"
  if (sample.kind === "ethernet") return "Ethernet"
  return String(sample.name || "") || "Tunnel"
}

// The line under it: band and strength, link speed, or what a VPN rides on.
function detail(sample) {
  if (!sample || !sample.device) return "No route to the internet"
  var parts = []
  if (sample.kind === "wifi") {
    if (sample.band) parts.push(String(sample.band))
    if (sample.signal !== null && sample.signal !== undefined) parts.push(Number(sample.signal) + "%")
  } else if (sample.kind === "ethernet") {
    var speed = fmtLinkSpeed(sample.speed)
    if (speed) parts.push(speed)
  } else if (sample.via) {
    parts.push("over " + sample.via)
  }
  parts.push(String(sample.device))
  return parts.join(" · ")
}

// VPNs other than the one carrying the default route (that one is the title).
function vpnLine(sample) {
  if (!sample) return ""
  var list = Array.isArray(sample.vpns) ? sample.vpns : []
  var parts = []
  for (var i = 0; i < list.length; i++) {
    var vpn = list[i] || {}
    if (sample.kind === "tunnel" && vpn.device === sample.device) continue
    var text = String(vpn.name || "VPN")
    if (vpn.detail) text += " · " + vpn.detail
    if (parts.indexOf(text) < 0) parts.push(text)
  }
  return parts.join("  ")
}

function fmtLatency(ms) {
  if (ms === null || ms === undefined || !isFinite(Number(ms))) return ""
  var n = Number(ms)
  return (n < 10 ? n.toFixed(1) : String(Math.round(n))) + " ms"
}

// Points for the throughput graph: both series share one scale so a busy
// upload and a quiet download are drawn honestly against each other.
function graphScale(down, up) {
  var top = 0
  var all = (down || []).concat(up || [])
  for (var i = 0; i < all.length; i++) top = Math.max(top, Number(all[i]) || 0)
  // A floor so an idle link draws a flat line, not noise blown up to full height.
  return Math.max(top * 1.15, 16 * 1024)
}

function graphPoints(values, width, height, scale, slots) {
  var list = Array.isArray(values) ? values : []
  var count = slots || HISTORY
  var step = count > 1 ? width / (count - 1) : width
  var start = count - list.length
  var out = []
  for (var i = 0; i < list.length; i++) {
    var v = Math.max(0, Number(list[i]) || 0)
    out.push({ x: (start + i) * step, y: height - Math.min(1, v / scale) * height })
  }
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    HISTORY: HISTORY,
    rateBetween: rateBetween,
    pickRate: pickRate,
    pushHistory: pushHistory,
    fmtBytes: fmtBytes,
    fmtRate: fmtRate,
    fmtLinkSpeed: fmtLinkSpeed,
    signalGlyph: signalGlyph,
    glyph: glyph,
    kindLabel: kindLabel,
    title: title,
    detail: detail,
    vpnLine: vpnLine,
    fmtLatency: fmtLatency,
    graphScale: graphScale,
    graphPoints: graphPoints
  }
}
