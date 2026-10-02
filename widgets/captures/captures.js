// Logic for the captures tile. Widget.qml imports it; test_logic.cjs requires it.

// The capture buttons. Each runs one of Omarchy's own commands.
var ACTIONS = [
  { id: "smart", glyph: "󰩭", label: "Area", argv: ["omarchy-capture-screenshot", "smart"] },
  { id: "windows", glyph: "󰖯", label: "Window", argv: ["omarchy-capture-screenshot", "windows"] },
  { id: "fullscreen", glyph: "󰍹", label: "Screen", argv: ["omarchy-capture-screenshot", "fullscreen"] },
  { id: "record", glyph: "󰑊", label: "Record", argv: ["omarchy-capture-screenrecording"] }
]

// The launcher must be gone before the screen is frozen, or it is in the
// picture. The argv runs after a pause, with nothing passing through a shell.
var CLOSE_DELAY = 0.45

function delayed(argv, seconds) {
  return ["bash", "-c", 'sleep "$1"; shift; exec "$@"', "bash", String(seconds)].concat(argv)
}

function mimeFor(path) {
  var lower = String(path || "").toLowerCase()
  if (/\.jpe?g$/.test(lower)) return "image/jpeg"
  if (/\.webp$/.test(lower)) return "image/webp"
  return "image/png"
}

// Put a picture on the clipboard. The path is a positional argument, so a
// file name never becomes shell text.
function copyArgv(path) {
  return ["bash", "-c", 'wl-copy --type "$2" < "$1"', "bash", String(path), mimeFor(path)]
}

function fmtAgo(nowSec, thenSec) {
  var then = Number(thenSec) || 0
  if (then <= 0) return ""
  var seconds = Math.max(0, Math.floor(Number(nowSec) - then))
  if (seconds < 60) return "just now"
  var minutes = Math.floor(seconds / 60)
  if (minutes < 60) return minutes + "m ago"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h ago"
  var days = Math.floor(hours / 24)
  if (days < 30) return days + "d ago"
  var months = Math.floor(days / 30)
  if (months < 12) return months + "mo ago"
  return Math.floor(months / 12) + "y ago"
}

function fmtElapsed(seconds) {
  var total = Math.max(0, Math.floor(Number(seconds) || 0))
  var h = Math.floor(total / 3600)
  var m = Math.floor((total % 3600) / 60)
  var s = total % 60
  var ss = (s < 10 ? "0" : "") + s
  if (h > 0) return h + ":" + (m < 10 ? "0" : "") + m + ":" + ss
  return m + ":" + ss
}

function fmtSize(bytes) {
  var n = Math.max(0, Number(bytes) || 0)
  if (n >= 1e9) return (n / 1e9).toFixed(1) + " GB"
  if (n >= 1e6) return (n / 1e6).toFixed(1) + " MB"
  if (n >= 1e3) return Math.round(n / 1e3) + " KB"
  return n + " B"
}

function shotCaption(shot, nowSec) {
  if (!shot) return ""
  var parts = [fmtAgo(nowSec, shot.mtime)]
  if (shot.width && shot.height) parts.push(shot.width + "×" + shot.height)
  return parts.filter(function(p) { return p.length > 0 }).join(" · ")
}

function headerNote(sample, nowSec) {
  if (!sample) return ""
  if (sample.recordingActive) {
    var since = Number(sample.recordingSince) || 0
    return since > 0 ? "REC " + fmtElapsed(nowSec - since) : "REC"
  }
  var today = Number(sample.today) || 0
  return today > 0 ? today + " today" : ""
}

if (typeof module !== "undefined") {
  module.exports = {
    ACTIONS: ACTIONS,
    CLOSE_DELAY: CLOSE_DELAY,
    delayed: delayed,
    mimeFor: mimeFor,
    copyArgv: copyArgv,
    fmtAgo: fmtAgo,
    fmtElapsed: fmtElapsed,
    fmtSize: fmtSize,
    shotCaption: shotCaption,
    headerNote: headerNote
  }
}
