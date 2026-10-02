// Logic for the F1 tile. Widget.qml imports it; test_logic.cjs requires it.

var DAY_NAMES = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var MONTH_NAMES = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
var PAGES = 3

function shortSession(name) {
  var map = { "Qualifying": "Quali", "Sprint Qualifying": "Sprint Q" }
  return map[name] || String(name || "")
}

// "Bahrain Grand Prix" reads as "Bahrain GP" on a tile.
function shortRace(name) {
  return String(name || "").replace(/Grand Prix/g, "GP").replace(/\s+/g, " ").trim()
}

function countdown(seconds) {
  var s = Math.max(0, Math.floor(Number(seconds) || 0))
  if (s < 60) return "now"
  var m = Math.floor(s / 60)
  if (m < 60) return m + "m"
  var h = Math.floor(m / 60)
  if (h < 24) return h + "h " + (m % 60) + "m"
  var d = Math.floor(h / 24)
  return d + "d " + (h % 24) + "h"
}

function sessionState(session, nowSec) {
  if (!session) return ""
  var now = Number(nowSec)
  if (now >= Number(session.end)) return "done"
  if (now >= Number(session.start)) return "live"
  return "later"
}

function nextSession(sessions, nowSec) {
  var list = Array.isArray(sessions) ? sessions : []
  for (var i = 0; i < list.length; i++) {
    if (Number(list[i].end) > Number(nowSec)) return list[i]
  }
  return null
}

function clock(sec, h24) {
  var d = new Date(Number(sec) * 1000)
  var h = d.getHours()
  var m = d.getMinutes()
  var mm = (m < 10 ? "0" : "") + m
  var time = h24 ? (h < 10 ? "0" : "") + h + ":" + mm : (h % 12 === 0 ? 12 : h % 12) + (m === 0 ? "" : ":" + mm) + (h < 12 ? "am" : "pm")
  return DAY_NAMES[d.getDay()] + " " + time
}

function dateText(sec) {
  if (!sec) return ""
  var d = new Date(Number(sec) * 1000)
  return MONTH_NAMES[d.getMonth()] + " " + d.getDate()
}

// The right side of the header: the live session, or how long until the next one.
function headerNote(sample, nowSec) {
  if (!sample || !sample.next) return ""
  if (sample.live && !sample.live.finished) return "LIVE · " + shortSession(sample.live.session)
  var next = nextSession(sample.next.sessions, nowSec)
  if (!next) return ""
  if (sessionState(next, nowSec) === "live") return shortSession(next.name) + " now"
  return shortSession(next.name) + " in " + countdown(Number(next.start) - Number(nowSec))
}

function nextPage(page, delta) {
  return ((Number(page) || 0) + (delta > 0 ? 1 : -1) + PAGES) % PAGES
}

// "#RRGGBB" from OpenF1's team colour, or "" when there is none.
function colour(hex) {
  var value = String(hex || "")
  return /^[0-9A-Fa-f]{6}$/.test(value) ? "#" + value : ""
}

if (typeof module !== "undefined") {
  module.exports = {
    PAGES: PAGES,
    shortSession: shortSession,
    shortRace: shortRace,
    countdown: countdown,
    sessionState: sessionState,
    nextSession: nextSession,
    clock: clock,
    dateText: dateText,
    headerNote: headerNote,
    nextPage: nextPage,
    colour: colour
  }
}
