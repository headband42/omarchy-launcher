// Logic for the calendar tile. Widget.qml imports it; test_logic.cjs requires it.
// Times are epoch seconds; days are local dates, as JavaScript's Date sees them.

var DAY_NAMES = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var MONTH_NAMES = ["January", "February", "March", "April", "May", "June", "July",
  "August", "September", "October", "November", "December"]
var AGENDA_DAYS = 14

function pad(n) {
  return (n < 10 ? "0" : "") + n
}

function dayKey(d) {
  return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
}

function startOfDay(d) {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate())
}

function addDays(d, n) {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n)
}

// The last moment an event covers. All-day ends are exclusive midnights.
function lastMoment(event) {
  var end = Number(event.end) || Number(event.start)
  return end > Number(event.start) ? end - 1 : Number(event.start)
}

// How many events touch each local day, by "YYYY-MM-DD".
function countsByDay(events) {
  var out = {}
  var list = Array.isArray(events) ? events : []
  for (var i = 0; i < list.length; i++) {
    var e = list[i]
    var day = startOfDay(new Date(Number(e.start) * 1000))
    var last = startOfDay(new Date(lastMoment(e) * 1000))
    for (var guard = 0; day <= last && guard < 62; guard++) {
      var key = dayKey(day)
      out[key] = (out[key] || 0) + 1
      day = addDays(day, 1)
    }
  }
  return out
}

// Seven days from the week's first day (0 Sunday … 6 Saturday) that holds `now`.
function week(nowMs, weekStart, counts) {
  var today = startOfDay(new Date(nowMs))
  var back = (today.getDay() - (Number(weekStart) || 0) + 7) % 7
  var first = addDays(today, -back)
  var out = []
  for (var i = 0; i < 7; i++) {
    var d = addDays(first, i)
    var key = dayKey(d)
    out.push({ key: key, day: d.getDate(), name: DAY_NAMES[d.getDay()].charAt(0), today: key === dayKey(today), count: (counts || {})[key] || 0, past: d < today })
  }
  return out
}

// Six weeks covering the month that holds `nowMs`, offset by `monthOffset`.
function monthGrid(nowMs, monthOffset, weekStart, counts) {
  var now = new Date(nowMs)
  var first = new Date(now.getFullYear(), now.getMonth() + (Number(monthOffset) || 0), 1)
  var back = (first.getDay() - (Number(weekStart) || 0) + 7) % 7
  var start = addDays(first, -back)
  var todayKey = dayKey(now)
  var cells = []
  for (var i = 0; i < 42; i++) {
    var d = addDays(start, i)
    var key = dayKey(d)
    cells.push({ key: key, day: d.getDate(), inMonth: d.getMonth() === first.getMonth(), today: key === todayKey, count: (counts || {})[key] || 0 })
  }
  return { title: MONTH_NAMES[first.getMonth()] + " " + first.getFullYear(), month: first.getMonth(), year: first.getFullYear(), cells: cells }
}

function weekdayLetters(weekStart) {
  var out = []
  for (var i = 0; i < 7; i++) out.push(DAY_NAMES[(i + (Number(weekStart) || 0)) % 7].charAt(0))
  return out
}

function fmtClock(sec, h24) {
  var d = new Date(Number(sec) * 1000)
  var h = d.getHours()
  var m = pad(d.getMinutes())
  if (h24) return pad(h) + ":" + m
  var suffix = h < 12 ? "am" : "pm"
  var hh = h % 12 === 0 ? 12 : h % 12
  return hh + (m === "00" ? "" : ":" + m) + suffix
}

function dayLabel(d, today) {
  var diff = Math.round((startOfDay(d) - startOfDay(today)) / 86400000)
  if (diff === 0) return "Today"
  if (diff === 1) return "Tomorrow"
  if (diff === -1) return "Yesterday"
  return DAY_NAMES[d.getDay()] + " " + MONTH_NAMES[d.getMonth()].slice(0, 3) + " " + d.getDate()
}

// The time column of a row on a given day.
function timeText(event, dayStartSec, h24) {
  if (event.allDay) return "all day"
  var start = Number(event.start)
  if (start < dayStartSec) return "→ " + fmtClock(event.end, h24)
  return fmtClock(start, h24)
}

// Days from today on, each with the events that touch it, not ended yet.
function agenda(events, nowMs, days, h24) {
  var list = Array.isArray(events) ? events : []
  var nowSec = Math.floor(nowMs / 1000)
  var today = startOfDay(new Date(nowMs))
  var out = []
  for (var i = 0; i < (days || AGENDA_DAYS); i++) {
    var day = addDays(today, i)
    var dayStart = day.getTime() / 1000
    var dayEnd = addDays(day, 1).getTime() / 1000
    var rows = []
    for (var j = 0; j < list.length; j++) {
      var e = list[j]
      var start = Number(e.start)
      var last = lastMoment(e)
      if (start >= dayEnd || last < dayStart) continue
      if (i === 0 && !e.allDay && Number(e.end) <= nowSec && Number(e.end) > start) continue
      rows.push({
        title: String(e.title || ""),
        time: timeText(e, dayStart, h24),
        calendar: Number(e.calendar) || 0,
        link: String(e.link || ""),
        location: String(e.location || ""),
        allDay: !!e.allDay,
        now: !e.allDay && start <= nowSec && nowSec < Number(e.end),
        start: start
      })
    }
    rows.sort(function(a, b) { return (b.allDay - a.allDay) || (a.start - b.start) })
    if (rows.length > 0) out.push({ key: dayKey(day), label: dayLabel(day, today), events: rows })
  }
  return out
}

// One flat list for the ListView: a day header, then its events.
function flatten(groups) {
  var out = []
  for (var i = 0; i < (groups || []).length; i++) {
    out.push({ kind: "day", label: groups[i].label, key: groups[i].key })
    for (var j = 0; j < groups[i].events.length; j++) out.push({ kind: "event", event: groups[i].events[j], key: groups[i].key })
  }
  return out
}

function fmtIn(seconds) {
  var s = Math.max(0, Math.floor(seconds))
  if (s < 60) return "now"
  var m = Math.floor(s / 60)
  if (m < 60) return "in " + m + "m"
  var h = Math.floor(m / 60)
  var rest = m % 60
  if (h < 24) return "in " + h + "h" + (rest && h < 3 ? " " + rest + "m" : "")
  return "in " + Math.floor(h / 24) + "d"
}

// The header's right side: what is on now, or how soon the next timed event starts.
function headerNote(events, nowMs) {
  var nowSec = Math.floor(nowMs / 1000)
  var list = Array.isArray(events) ? events : []
  var next = null
  for (var i = 0; i < list.length; i++) {
    var e = list[i]
    if (e.allDay) continue
    if (Number(e.start) <= nowSec && nowSec < Number(e.end)) return "now"
    if (Number(e.start) > nowSec && (!next || Number(e.start) < Number(next.start))) next = e
  }
  if (!next || Number(next.start) - nowSec > 12 * 3600) return ""
  return fmtIn(Number(next.start) - nowSec)
}

function dateTitle(nowMs) {
  var d = new Date(nowMs)
  return (DAY_NAMES[d.getDay()] + ", " + MONTH_NAMES[d.getMonth()].slice(0, 3) + " " + d.getDate()).toUpperCase()
}

function indexOfDay(rows, key) {
  for (var i = 0; i < (rows || []).length; i++) if (rows[i].kind === "day" && rows[i].key >= key) return i
  return -1
}

if (typeof module !== "undefined") {
  module.exports = {
    AGENDA_DAYS: AGENDA_DAYS,
    dayKey: dayKey,
    countsByDay: countsByDay,
    week: week,
    monthGrid: monthGrid,
    weekdayLetters: weekdayLetters,
    fmtClock: fmtClock,
    dayLabel: dayLabel,
    timeText: timeText,
    agenda: agenda,
    flatten: flatten,
    fmtIn: fmtIn,
    headerNote: headerNote,
    dateTitle: dateTitle,
    indexOfDay: indexOfDay
  }
}
