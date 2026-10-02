// Usage-meter helpers shared by the plan tiles (OpenCode Go, Claude, Grok). A
// widget imports this as "../_kit/usage.js"; node tests require it.
//
// Times arrive as epoch milliseconds and are formatted here, against a `now`
// the tile keeps ticking, so a countdown stays right between polls and a
// cached reply reads correctly the moment the launcher opens.

var DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

// A number, or null. Number(null) is 0, and a block that reported nothing
// must not be drawn as a confident zero.
function finite(value) {
  if (value === null || value === undefined || value === "" || typeof value === "boolean") return null
  var n = Number(value)
  return isFinite(n) ? n : null
}

// Seconds until something, in the tile's compact form.
function countdown(seconds) {
  var value = finite(seconds)
  if (value === null || value <= 0) return "now"
  var total = Math.floor(value)
  if (total < 60) return total + "s"
  var minutes = Math.floor(total / 60)
  if (minutes < 60) return minutes + "m"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) {
    var restMinutes = minutes % 60
    return restMinutes ? hours + "h " + (restMinutes < 10 ? "0" : "") + restMinutes + "m" : hours + "h"
  }
  var days = Math.floor(hours / 24)
  var restHours = hours % 24
  return restHours ? days + "d " + (restHours < 10 ? "0" : "") + restHours + "h" : days + "d"
}

// "9:42 pm", or "3 pm" on the hour.
function clock(date) {
  var h = date.getHours()
  var m = date.getMinutes()
  var suffix = h < 12 ? " am" : " pm"
  var twelve = h % 12 === 0 ? 12 : h % 12
  return twelve + (m ? ":" + (m < 10 ? "0" : "") + m : "") + suffix
}

// A moment as a day on this machine's calendar: "today 9:42 pm",
// "tomorrow 1 am", "Thu 3 pm" within the week, else "Oct 26".
function dayLabel(atMs, nowMs) {
  var at = finite(atMs)
  var now = finite(nowMs)
  if (at === null || now === null) return ""
  var moment = new Date(at)
  var today = new Date(now)
  var startMoment = new Date(moment.getFullYear(), moment.getMonth(), moment.getDate()).getTime()
  var startToday = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime()
  // Rounded, so a daylight-saving day of 23 or 25 hours still counts as one.
  var days = Math.round((startMoment - startToday) / 86400000)
  if (days === 0) return "today " + clock(moment)
  if (days === 1) return "tomorrow " + clock(moment)
  if (days > 1 && days <= 6) return DAYS[moment.getDay()] + " " + clock(moment)
  return MONTHS[moment.getMonth()] + " " + moment.getDate()
}

// When a block frees up: a countdown, or the calendar day with "absolute".
// "" when the block has no reset time.
function resetLine(atMs, nowMs, style) {
  var at = finite(atMs)
  var now = finite(nowMs)
  if (at === null || now === null) return ""
  if (at <= now) return "resetting"
  if (style === "absolute") return "resets " + dayLabel(at, now)
  return "resets in " + countdown((at - now) / 1000)
}

// The percentage, rounded for reading. Over the limit still reads over 100.
function percentText(percent) {
  var value = finite(percent)
  if (value === null) return "—"
  return Math.round(Math.max(0, value)) + "%"
}

// How full a bar is drawn. It stops at the end of the track.
function fill(percent) {
  var value = finite(percent)
  if (value === null || value <= 0) return 0
  return Math.min(1, value / 100)
}

// calm, warm past half, urgent from 80% or over the limit; muted with no number.
function tone(percent, over) {
  if (over) return "urgent"
  var value = finite(percent)
  if (value === null) return "muted"
  if (value >= 80) return "urgent"
  if (value >= 50) return "warm"
  return "calm"
}

// Where a tone sits on the ramp from the theme's accent to its urgent color.
function toneFraction(name) {
  if (name === "urgent") return 1
  if (name === "warm") return 0.55
  if (name === "calm") return 0
  return 0.15
}

// The block closest to its ceiling: the one worth a glance. -1 for none.
function worstIndex(meters) {
  var list = toList(meters)
  var best = -1
  var top = -1
  for (var i = 0; i < list.length; i++) {
    var value = finite(list[i] && list[i].percent)
    if (value !== null && value > top) {
      top = value
      best = i
    }
  }
  return best
}

// Leave out the blocks named in a comma list (the settings' `hidden`).
function visibleMeters(meters, hidden) {
  var list = toList(meters)
  var hide = String(hidden || "").split(",").filter(function(id) { return id.length > 0 })
  if (!hide.length) return list
  return list.filter(function(meter) { return hide.indexOf(String(meter && meter.id)) < 0 })
}

// "updated 12m ago" for a reply that is not fresh.
function ageLine(savedMs, nowMs) {
  var saved = finite(savedMs)
  var now = finite(nowMs)
  if (saved === null || now === null || saved <= 0) return ""
  var seconds = (now - saved) / 1000
  if (seconds < 90) return "updated just now"
  return "updated " + countdown(seconds).split(" ")[0] + " ago"
}

// A list that crossed a QML `var` property is array-like but not an Array.
function toList(value) {
  if (Array.isArray(value)) return value
  if (value && typeof value === "object" && typeof value.length === "number")
    return Array.prototype.slice.call(value)
  return []
}

if (typeof module !== "undefined") {
  module.exports = {
    finite: finite,
    countdown: countdown,
    clock: clock,
    dayLabel: dayLabel,
    resetLine: resetLine,
    percentText: percentText,
    fill: fill,
    tone: tone,
    toneFraction: toneFraction,
    worstIndex: worstIndex,
    visibleMeters: visibleMeters,
    ageLine: ageLine,
    toList: toList
  }
}
