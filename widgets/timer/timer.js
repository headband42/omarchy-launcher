// Logic for the timer tile. Widget.qml and Settings.qml import it;
// test_logic.cjs requires it.

var CHOICES = [1, 2, 3, 5, 10, 15, 20, 25, 30, 45, 60, 90, 120]
var DEFAULTS = [5, 15, 25, 60]
var MAX_PRESETS = 4

// The preset buttons: the user's pick, kept to known lengths, shortest first.
function presets(settings) {
  var picked = settings && Array.isArray(settings.presets) ? settings.presets : null
  if (!picked) return DEFAULTS.slice()
  var out = []
  for (var i = 0; i < CHOICES.length; i++) {
    for (var j = 0; j < picked.length; j++) {
      if (Number(picked[j]) === CHOICES[i]) {
        out.push(CHOICES[i])
        break
      }
    }
  }
  out = out.slice(0, MAX_PRESETS)
  return out.length > 0 ? out : DEFAULTS.slice()
}

// Turn one length on or off. Keeps at least one and at most MAX_PRESETS; the
// defaults are stored as {} so the tile follows them.
function togglePreset(settings, minutes) {
  var current = presets(settings)
  var at = current.indexOf(minutes)
  var next = current.slice()
  if (at >= 0) {
    if (next.length <= 1) return settings && Array.isArray(settings.presets) ? { presets: current } : {}
    next.splice(at, 1)
  } else {
    if (CHOICES.indexOf(minutes) < 0 || next.length >= MAX_PRESETS) return settings && Array.isArray(settings.presets) ? { presets: current } : {}
    next.push(minutes)
    next.sort(function(a, b) { return a - b })
  }
  if (next.join(",") === DEFAULTS.join(",")) return {}
  return { presets: next }
}

function fmtPreset(minutes) {
  var m = Number(minutes) || 0
  if (m < 60) return m + "m"
  var h = Math.floor(m / 60)
  var rest = m % 60
  return rest ? h + "h" + (rest < 10 ? "0" : "") + rest : h + "h"
}

function remaining(row, nowSec) {
  if (!row) return 0
  return Math.max(0, Math.round(Number(row.at) - Number(nowSec)))
}

function fmtCountdown(seconds) {
  var total = Math.max(0, Math.floor(Number(seconds) || 0))
  var h = Math.floor(total / 3600)
  var m = Math.floor((total % 3600) / 60)
  var s = total % 60
  var ss = (s < 10 ? "0" : "") + s
  if (h > 0) return h + ":" + (m < 10 ? "0" : "") + m + ":" + ss
  return m + ":" + ss
}

// How much of the reminder has run, 0..1.
function elapsed(row, nowSec) {
  if (!row) return 0
  var total = Number(row.minutes) * 60
  if (!(total > 0)) return 0
  var done = Number(nowSec) - Number(row.started)
  return Math.max(0, Math.min(1, done / total))
}

function label(row) {
  if (!row) return ""
  var message = String(row.message || "").trim()
  return message || fmtPreset(row.minutes) + " timer"
}

// Reminders that have not fired as of now; the sampler's list can be a few
// seconds old.
function live(rows, nowSec) {
  var out = []
  var list = Array.isArray(rows) ? rows : []
  for (var i = 0; i < list.length; i++) {
    if (Number(list[i].at) > Number(nowSec)) out.push(list[i])
  }
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    CHOICES: CHOICES,
    DEFAULTS: DEFAULTS,
    MAX_PRESETS: MAX_PRESETS,
    presets: presets,
    togglePreset: togglePreset,
    fmtPreset: fmtPreset,
    remaining: remaining,
    fmtCountdown: fmtCountdown,
    elapsed: elapsed,
    label: label,
    live: live
  }
}
