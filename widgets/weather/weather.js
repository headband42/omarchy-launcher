function normalizedLocation(value) {
  if (!value || typeof value !== "object") return null
  var latitude = Number(value.latitude)
  var longitude = Number(value.longitude)
  if (!isFinite(latitude) || !isFinite(longitude)) return null
  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) return null
  return {
    name: String(value.name || value.label || "Saved location"),
    detail: String(value.detail || value.admin1 || value.country || ""),
    latitude: latitude,
    longitude: longitude,
    timezone: String(value.timezone || ""),
    admin1: String(value.admin1 || ""),
    country: String(value.country || ""),
    countryCode: String(value.countryCode || "").toUpperCase()
  }
}

function normalizedSettings(value) {
  var settings = value && typeof value === "object" ? value : {}
  return {
    location: normalizedLocation(settings.location),
    units: String(settings.units || "imperial") === "metric" ? "metric" : "imperial"
  }
}

function settingsFor(location, units) {
  var result = { units: units === "metric" ? "metric" : "imperial" }
  if (location) result.location = normalizedLocation(location)
  return result
}

function temperature(value, units) {
  var metric = Number(value)
  if (!isFinite(metric)) return "—"
  var shown = units === "metric" ? metric : metric * 9 / 5 + 32
  return Math.round(shown) + "°"
}

function speed(value, units) {
  var metric = Number(value)
  if (!isFinite(metric)) return "—"
  var shown = units === "metric" ? metric : metric * 0.621371
  return Math.round(shown) + (units === "metric" ? " km/h" : " mph")
}

function precipitation(value, units) {
  var metric = Number(value)
  if (!isFinite(metric)) return "—"
  var shown = units === "metric" ? metric : metric * 0.0393701
  return (shown < 0.01 && shown > 0 ? "<0.01" : shown.toFixed(shown >= 100 ? 0 : 1)) + (units === "metric" ? " mm" : " in")
}

function visibility(value, units) {
  var meters = Number(value)
  if (!isFinite(meters) || meters <= 0) return "—"
  if (units === "metric") return meters >= 1000 ? (meters / 1000).toFixed(meters >= 10000 ? 0 : 1) + " km" : Math.round(meters) + " m"
  var miles = meters / 1609.344
  return miles >= 10 ? Math.round(miles) + " mi" : miles.toFixed(1) + " mi"
}

function clock(iso, compact) {
  var value = String(iso || "")
  var match = value.match(/T(\d{2}):(\d{2})/)
  if (!match) return "—"
  var hour = Number(match[1])
  var minute = match[2]
  if (!compact) return match[1] + ":" + minute
  if (hour === 0) return "12a"
  if (hour < 12) return hour + "a"
  if (hour === 12) return "12p"
  return String(hour - 12) + "p"
}

function day(date, index) {
  var value = String(date || "")
  if (index === 0) return "TODAY"
  if (index === 1) return "TOMORROW"
  var parts = value.split("-")
  if (parts.length !== 3) return "—"
  var parsed = new Date(Date.UTC(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2])))
  if (isNaN(parsed.getTime())) return "—"
  return ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"][parsed.getUTCDay()]
}

function windDirection(value) {
  var angle = Number(value)
  if (!isFinite(angle)) return ""
  var points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
  return points[Math.round(((angle % 360) + 360) % 360 / 45) % 8]
}

function glyph(code, isDay) {
  var value = Math.round(Number(code))
  if (value === 0) return isDay ? "󰖀" : "󰖓"
  if (value === 1) return isDay ? "󰖀" : "󰖓"
  if (value === 2) return "󰖔"
  if (value === 3) return "☁"
  if (value === 45 || value === 48) return "󰖕"
  if ((value >= 51 && value <= 67) || (value >= 80 && value <= 82)) return "󰖗"
  if ((value >= 71 && value <= 77) || value === 85 || value === 86) return "󰖘"
  if (value >= 95) return "⛈"
  return "☁"
}


function pressure(value, units) {
  var hpa = Number(value)
  if (!isFinite(hpa) || hpa <= 0) return "—"
  if (units === "metric") return Math.round(hpa) + " hPa"
  return (hpa * 0.02953).toFixed(2) + " in"
}

function gust(value, units) {
  return speed(value, units)
}

function precipBars(rows, width, height) {
  var bars = []
  var list = rows || []
  if (!list.length || width < 2 || height < 2) return bars
  var slot = width / list.length
  var barWidth = Math.max(2, Math.min(10, slot * 0.42))
  for (var i = 0; i < list.length; i++) {
    var chance = Number(list[i] && list[i].precipProbability)
    if (!isFinite(chance) || chance < 0) chance = 0
    chance = Math.min(100, chance)
    var barHeight = Math.max(0, chance / 100 * Math.max(1, height - 2))
    bars.push({
      x: i * slot + (slot - barWidth) / 2,
      y: height - barHeight,
      width: barWidth,
      height: barHeight,
      chance: chance
    })
  }
  return bars
}

function dailyDays(rows, limit) {
  var out = []
  var list = rows || []
  var max = Math.max(1, Math.min(Number(limit) || 5, list.length))
  for (var i = 0; i < max; i++) {
    var row = list[i]
    if (!row) continue
    out.push({
      index: i,
      date: String(row.date || ""),
      code: Number(row.code),
      high: row.high,
      low: row.low,
      label: day(row.date, i),
      glyph: glyph(row.code, true)
    })
  }
  return out
}

function chartPoints(rows, units, width, height) {
  var values = []
  for (var i = 0; i < (rows || []).length; i++) {
    var metric = Number(rows[i] && rows[i].temperature)
    if (!isFinite(metric)) continue
    var value = units === "metric" ? metric : metric * 9 / 5 + 32
    values.push(value)
  }
  if (!values.length || width < 2 || height < 2) return []
  var minimum = Math.min.apply(Math, values)
  var maximum = Math.max.apply(Math, values)
  if (maximum - minimum < 1) {
    maximum += 0.5
    minimum -= 0.5
  }
  var points = []
  for (var j = 0; j < values.length; j++) {
    points.push({
      x: values.length === 1 ? width / 2 : j * (width - 8) / (values.length - 1) + 4,
      y: 7 + (maximum - values[j]) / (maximum - minimum) * Math.max(1, height - 14),
      temperature: Math.round(values[j]),
      label: j === 0 || j === values.length - 1 || j === Math.floor((values.length - 1) / 2)
    })
  }
  return points
}

function hourlyCount(width) {
  if (width >= 280) return 6
  if (width >= 220) return 5
  return 4
}

if (typeof module !== "undefined") {
  module.exports = {
    chartPoints: chartPoints,
    clock: clock,
    dailyDays: dailyDays,
    day: day,
    glyph: glyph,
    gust: gust,
    hourlyCount: hourlyCount,
    normalizedLocation: normalizedLocation,
    normalizedSettings: normalizedSettings,
    precipBars: precipBars,
    precipitation: precipitation,
    pressure: pressure,
    settingsFor: settingsFor,
    speed: speed,
    temperature: temperature,
    visibility: visibility,
    windDirection: windDirection
  }
}
