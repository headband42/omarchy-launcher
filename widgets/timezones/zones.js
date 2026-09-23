// Pure helpers for the time zones widget. QML imports this file;
// node tests require it. Keep it free of Qt types.

var MAX_ZONES = 3

function maxZones() { return MAX_ZONES }

var WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

function cleanLabel(value) {
  return String(value || "").replace(/[\r\n\t]+/g, " ").replace(/\s+/g, " ").trim().slice(0, 32)
}

// Each entry is { id, label }. label is the custom name, or "" to use the city.
// Older configs stored plain id strings; those still load.
function normalizeZones(settings) {
  var raw = settings && settings.zones
  if (!Array.isArray(raw)) return []
  var out = []
  var seen = {}
  for (var i = 0; i < raw.length; i++) {
    var item = raw[i]
    var id = ""
    var label = ""
    if (item && typeof item === "object") {
      id = String(item.id || "").trim()
      label = cleanLabel(item.label)
    } else {
      id = String(item || "").trim()
    }
    if (!id || seen[id]) continue
    if (!/^[A-Za-z0-9_+\-]+(?:\/[A-Za-z0-9_+\-]+)*$/.test(id)) continue
    seen[id] = true
    out.push({ id: id, label: label })
    if (out.length >= MAX_ZONES) break
  }
  return out
}

function settingsFromZones(entries) {
  var zones = normalizeZones({ zones: entries })
  if (zones.length === 0) return null
  var stored = []
  for (var i = 0; i < zones.length; i++) {
    if (zones[i].label) stored.push({ id: zones[i].id, label: zones[i].label })
    else stored.push(zones[i].id)
  }
  return { zones: stored }
}

function formatOffset(minutes) {
  var n = Number(minutes)
  if (!isFinite(n)) return ""
  if (n === 0) return "UTC"
  var sign = n < 0 ? "-" : "+"
  var abs = Math.abs(Math.trunc(n))
  var hours = Math.floor(abs / 60)
  var mins = abs % 60
  if (mins === 0) return "UTC" + sign + hours
  return "UTC" + sign + hours + ":" + pad2(mins)
}

function cityOf(id) {
  var parts = String(id || "").split("/")
  var city = parts[parts.length - 1] || String(id || "")
  return city.replace(/_/g, " ")
}

function regionOf(id) {
  var parts = String(id || "").split("/")
  if (parts.length < 2) return ""
  var out = []
  for (var i = 0; i < parts.length - 1; i++) out.push(parts[i].replace(/_/g, " "))
  return out.join(" · ")
}

function pad2(n) {
  var value = Math.floor(Math.abs(Number(n) || 0)) % 100
  return (value < 10 ? "0" : "") + value
}

// Shift UTC by the zone's current offset and read UTC fields.
// That is the wall clock in that zone, including the calendar day.
function wallClock(nowMs, offsetMin) {
  var shifted = new Date(Number(nowMs) + Number(offsetMin) * 60000)
  return {
    hour: shifted.getUTCHours(),
    minute: shifted.getUTCMinutes(),
    date: shifted.getUTCDate(),
    month: shifted.getUTCMonth(),
    day: shifted.getUTCDay()
  }
}

function formatTime(nowMs, offsetMin, hour12) {
  var wall = wallClock(nowMs, offsetMin)
  if (!hour12) return pad2(wall.hour) + ":" + pad2(wall.minute)
  var suffix = wall.hour >= 12 ? "PM" : "AM"
  var hour = wall.hour % 12
  if (hour === 0) hour = 12
  return hour + ":" + pad2(wall.minute) + " " + suffix
}

function formatDate(nowMs, offsetMin) {
  var wall = wallClock(nowMs, offsetMin)
  return WEEKDAYS[wall.day] + " " + wall.date + " " + MONTHS[wall.month]
}

function dayDelta(nowMs, localOffset, zoneOffset) {
  var localDay = Math.floor((Number(nowMs) + Number(localOffset) * 60000) / 86400000)
  var zoneDay = Math.floor((Number(nowMs) + Number(zoneOffset) * 60000) / 86400000)
  return zoneDay - localDay
}

function formatDayDelta(delta) {
  var n = Math.trunc(Number(delta) || 0)
  if (n === 0) return ""
  return (n > 0 ? "+" : "-") + String(Math.abs(n))
}

if (typeof module !== "undefined") {
  module.exports = {
    MAX_ZONES: MAX_ZONES,
    maxZones: maxZones,
    cleanLabel: cleanLabel,
    normalizeZones: normalizeZones,
    settingsFromZones: settingsFromZones,
    formatOffset: formatOffset,
    cityOf: cityOf,
    regionOf: regionOf,
    formatTime: formatTime,
    formatDate: formatDate,
    dayDelta: dayDelta,
    formatDayDelta: formatDayDelta
  }
}
