// Pure helpers for the repo widget. QML imports this file; node tests require it.

var ACTIVITY_DAYS = 14

function data(sample) {
  return sample && typeof sample === "object" ? sample : {}
}

function count(value) {
  var n = Math.floor(Number(value) || 0)
  return n > 0 ? n : 0
}

function plural(n, one, many) {
  return n + " " + (n === 1 ? one : many)
}

// A list that crossed a QML `var` property is array-like but not an Array.
function toList(value) {
  if (Array.isArray(value)) return value
  if (value && typeof value === "object" && typeof value.length === "number")
    return Array.prototype.slice.call(value)
  return []
}

function branchLine(sample) {
  var d = data(sample)
  if (!d.ok) return ""
  if (d.detached) return "detached HEAD"
  return String(d.branch || "")
}

// Under the branch: where it tracks, or why there is nothing to compare with.
function upstreamLine(sample) {
  var d = data(sample)
  if (!d.ok) return ""
  if (d.detached) return d.hash ? "at " + d.hash : ""
  if (!d.branch) return ""
  if (!d.hash) return "no commits yet"
  return d.upstream ? String(d.upstream) : "no upstream"
}

// The file-state chips, in git status order. A clean tree gets one chip.
function chips(sample) {
  var d = data(sample)
  if (!d.ok) return []
  var out = []
  var conflicted = count(d.conflicted)
  var staged = count(d.staged)
  var modified = count(d.modified)
  var untracked = count(d.untracked)
  var stash = count(d.stash)
  if (conflicted) out.push({ key: "conflicted", label: plural(conflicted, "conflict", "conflicts"), tone: "urgent" })
  if (staged) out.push({ key: "staged", label: staged + " staged", tone: "accent" })
  if (modified) out.push({ key: "modified", label: modified + " modified", tone: "plain" })
  if (untracked) out.push({ key: "untracked", label: untracked + " new", tone: "plain" })
  if (!conflicted && !staged && !modified && !untracked)
    out.push({ key: "clean", label: "clean", tone: "clean" })
  if (stash) out.push({ key: "stash", label: stash + " stashed", tone: "muted" })
  return out
}

// "conflict", "dirty", or "clean": the header dot.
function state(sample) {
  var d = data(sample)
  if (!d.ok) return ""
  if (count(d.conflicted)) return "conflict"
  if (count(d.staged) || count(d.modified) || count(d.untracked) || count(d.dirty)) return "dirty"
  return "clean"
}

// Commits per day, oldest first, always ACTIVITY_DAYS long.
function activity(sample) {
  var raw = toList(data(sample).activity)
  var out = []
  for (var i = 0; i < ACTIVITY_DAYS; i++) {
    var j = raw.length - ACTIVITY_DAYS + i
    out.push(j >= 0 ? count(raw[j]) : 0)
  }
  return out
}

function total(list) {
  var sum = 0
  for (var i = 0; i < list.length; i++) sum += count(list[i])
  return sum
}

function peak(list) {
  var top = 0
  for (var i = 0; i < list.length; i++) top = Math.max(top, count(list[i]))
  return top
}

// 0..1 bar height for one day. An idle day still draws a stub.
function barLevel(value, top) {
  var n = count(value)
  if (n === 0 || top <= 0) return 0
  return Math.max(0.18, n / top)
}

// Seconds since the epoch in, "now" / "5m" / "3h" / "2d" / "3w" / "4mo" / "2y" out.
function ageLabel(at, now) {
  var then = Number(at) || 0
  var current = Number(now) || 0
  if (then <= 0 || current <= 0) return ""
  var s = Math.max(0, Math.floor(current - then))
  if (s < 60) return "now"
  var m = Math.floor(s / 60)
  if (m < 60) return m + "m"
  var h = Math.floor(m / 60)
  if (h < 24) return h + "h"
  var days = Math.floor(h / 24)
  if (days < 14) return days + "d"
  if (days < 60) return Math.floor(days / 7) + "w"
  if (days < 365) return Math.floor(days / 30) + "mo"
  return Math.floor(days / 365) + "y"
}

function fetchedLine(sample, now) {
  var d = data(sample)
  if (!d.ok || !d.upstream) return ""
  var age = ageLabel(d.fetchedAt, now)
  if (!age) return "never fetched"
  return age === "now" ? "fetched just now" : "fetched " + age + " ago"
}

// Commits at the top of HEAD that the upstream does not have yet.
function unpushed(sample, index) {
  var d = data(sample)
  return !!d.upstream && index >= 0 && index < count(d.ahead)
}

function displayPath(path, home) {
  var value = String(path || "")
  var base = String(home || "").replace(/\/+$/, "")
  if (base && (value === base || value.indexOf(base + "/") === 0)) return "~" + value.slice(base.length)
  return value
}

// What the settings panel stores. Empty forgets it and watches $HOME.
function settingsFromPath(text) {
  var value = String(text || "").trim()
  return value ? { path: value } : {}
}

if (typeof module !== "undefined") {
  module.exports = {
    ACTIVITY_DAYS: ACTIVITY_DAYS,
    branchLine: branchLine,
    upstreamLine: upstreamLine,
    chips: chips,
    state: state,
    activity: activity,
    total: total,
    peak: peak,
    barLevel: barLevel,
    ageLabel: ageLabel,
    fetchedLine: fetchedLine,
    unpushed: unpushed,
    displayPath: displayPath,
    settingsFromPath: settingsFromPath,
    toList: toList
  }
}
