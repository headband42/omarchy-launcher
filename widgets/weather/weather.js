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

// The rotating panels, in rotation order. Settings store the ones turned
// off, so a panel added later shows up on tiles that already exist.
var PANELS = [
  { id: "hours", title: "HOURS", name: "Hours" },
  { id: "details", title: "DETAILS", name: "Details" },
  { id: "week", title: "WEEK", name: "Week" },
  { id: "radar", title: "RADAR", name: "Radar" },
  { id: "air", title: "AIR QUALITY", name: "Air quality" },
  { id: "sun", title: "SUN & MOON", name: "Sun & moon" }
]

function panelIds() {
  var ids = []
  for (var i = 0; i < PANELS.length; i++) ids.push(PANELS[i].id)
  return ids
}

function panelTitle(id) {
  for (var i = 0; i < PANELS.length; i++) if (PANELS[i].id === id) return PANELS[i].title
  return ""
}

function hiddenPanels(value) {
  var list = Array.isArray(value) ? value : []
  var ids = panelIds()
  var out = []
  for (var i = 0; i < ids.length; i++) if (list.indexOf(ids[i]) >= 0) out.push(ids[i])
  return out
}

// Never empty: with every panel hidden, Hours still shows.
function visiblePanels(hidden) {
  var ids = panelIds()
  var out = []
  for (var i = 0; i < ids.length; i++) if ((hidden || []).indexOf(ids[i]) < 0) out.push(ids[i])
  return out.length ? out : ["hours"]
}

// Radar zoom: 6 shows about 400 km across a tile, 5 twice that.
var RADAR_ZOOMS = { local: 6, regional: 5 }

function radarRange(value) {
  return value === "regional" ? "regional" : "local"
}

function normalizedSettings(value) {
  var settings = value && typeof value === "object" ? value : {}
  var hidden = hiddenPanels(settings.hiddenPanels)
  var range = radarRange(settings.radarRange)
  return {
    location: normalizedLocation(settings.location),
    units: String(settings.units || "imperial") === "metric" ? "metric" : "imperial",
    // Default ON so existing tiles keep the weather-tinted atmosphere.
    atmosphere: settings.atmosphere !== false,
    hiddenPanels: hidden,
    panels: visiblePanels(hidden),
    radarRange: range,
    radarZoom: RADAR_ZOOMS[range]
  }
}

// What is saved for normalized options. Defaults are left out.
function storedSettings(options) {
  var value = options || {}
  var result = {
    units: value.units === "metric" ? "metric" : "imperial",
    atmosphere: value.atmosphere !== false
  }
  var location = normalizedLocation(value.location)
  if (location) result.location = location
  var hidden = hiddenPanels(value.hiddenPanels)
  if (hidden.length) result.hiddenPanels = hidden
  if (radarRange(value.radarRange) !== "local") result.radarRange = radarRange(value.radarRange)
  return result
}

function settingsWith(value, key, next) {
  var options = normalizedSettings(value)
  options[key] = next
  return storedSettings(options)
}

// Shows or hides one panel. The last visible panel cannot be hidden.
function togglePanel(value, id) {
  var options = normalizedSettings(value)
  var hidden = options.hiddenPanels.slice()
  var at = hidden.indexOf(id)
  if (at >= 0) hidden.splice(at, 1)
  else if (panelIds().indexOf(id) >= 0 && !(options.panels.length === 1 && options.panels[0] === id)) hidden.push(id)
  options.hiddenPanels = hidden
  return storedSettings(options)
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

function sunClock(iso) {
  var value = String(iso || "")
  var match = value.match(/T(\d{2}):(\d{2})/)
  if (!match) return "—"
  var hour = Number(match[1])
  var minute = match[2]
  var suffix = "am"
  var shown = hour
  if (hour === 0) shown = 12
  else if (hour === 12) suffix = "pm"
  else if (hour > 12) { shown = hour - 12; suffix = "pm" }
  return String(shown) + ":" + minute + " " + suffix
}

function cacheKey(location) {
  if (!location || typeof location !== "object") return ""
  var latitude = Number(location.latitude)
  var longitude = Number(location.longitude)
  if (!isFinite(latitude) || !isFinite(longitude)) return ""
  return latitude.toFixed(4) + "_" + longitude.toFixed(4)
}

function cacheFilePath(location) {
  var key = cacheKey(location)
  if (!key) return ""
  return key + ".json"
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

function nightFlag(isDay) {
  // Treat 0 / "0" / false as night (Open-Meteo is_day is often numeric).
  return isDay === false || isDay === 0 || isDay === "0"
}

function glyph(code, isDay) {
  // Weather Icons (nf-weather), matching stock omarchy weather Model.js.
  // Avoid MDI PUA slots: clear-day was previously md-volume-medium (speaker)
  // and clear-night was md-weather-lightning.
  var value = Math.round(Number(code))
  var night = nightFlag(isDay)
  if (value === 0) return night ? "" : ""
  if (value === 1 || value === 2) return night ? "" : ""
  if (value === 3) return ""
  if (value === 45 || value === 48) return ""
  if (value === 51 || value === 53 || value === 55 || value === 56 || value === 57 || value === 61)
    return night ? "" : ""
  if ((value >= 63 && value <= 67) || (value >= 80 && value <= 82)) return ""
  if ((value >= 71 && value <= 77) || value === 85 || value === 86) return ""
  if (value >= 95) return ""
  return ""
}


// The tile's sky for a weather code. Each kind has its own colors and effect
// so a glance tells clear from rain from snow.
function skyKind(code, isDay) {
  var value = Math.round(Number(code))
  var night = nightFlag(isDay)
  if (value === 0 || value === 1) return night ? "clear-night" : "clear-day"
  if (value === 2) return night ? "cloudy-night" : "cloudy-day"
  if (value === 3) return "overcast"
  if (value === 45 || value === 48) return "fog"
  if (value === 56 || value === 57 || value === 66 || value === 67) return "freezing"
  if (value >= 51 && value <= 55) return "drizzle"
  if ((value >= 61 && value <= 65) || (value >= 80 && value <= 82)) return "rain"
  if ((value >= 71 && value <= 77) || value === 85 || value === 86) return "snow"
  if (value >= 95) return "storm"
  return night ? "cloudy-night" : "cloudy-day"
}

// top/bottom: the gradient. glow: a radial light near the top right.
// stars, clouds: how many to draw. particles: what falls. mist, lightning: effects.
var SKIES = {
  "clear-day": { top: "#2f8fe0", bottom: "#174f93", glow: "#ffc457", glowAlpha: 0.6 },
  "cloudy-day": { top: "#6a8cc4", bottom: "#2e4a6b", glow: "#ffffff", glowAlpha: 0.16, clouds: 3 },
  "clear-night": { top: "#25317a", bottom: "#0b1033", glow: "#b9c7ff", glowAlpha: 0.12, stars: 30 },
  "cloudy-night": { top: "#454a63", bottom: "#181b2a", glow: "#b9c7ff", glowAlpha: 0.05, stars: 10, clouds: 3 },
  "overcast": { top: "#6b7380", bottom: "#33383f", clouds: 5 },
  "fog": { top: "#a0a6ad", bottom: "#5f646a", mist: true },
  "drizzle": { top: "#3f7f80", bottom: "#1d3a40", particles: "drizzle" },
  "rain": { top: "#1f5f9e", bottom: "#0b2447", particles: "rain" },
  "freezing": { top: "#4fc2bf", bottom: "#1f5a5c", particles: "sleet" },
  "snow": { top: "#bcd3e4", bottom: "#6d88a0", glow: "#ffffff", glowAlpha: 0.16, particles: "snow" },
  "storm": { top: "#5a2c8a", bottom: "#1b0d36", particles: "storm", lightning: true }
}

// count, streak length, alpha, sideways slant, and falls per animation loop.
var PARTICLES = {
  drizzle: { count: 22, length: 5, alpha: 0.2, slant: 1, speed: 1 },
  rain: { count: 34, length: 11, alpha: 0.28, slant: 3, speed: 2 },
  sleet: { count: 26, length: 6, alpha: 0.3, slant: 2, speed: 2 },
  storm: { count: 42, length: 13, alpha: 0.3, slant: 5, speed: 2 },
  snow: { count: 28, length: 0, alpha: 0.5, slant: 0, speed: 1 }
}

// A seeded generator (mulberry32), so a sky draws the same on every paint.
function seededRandom(seed) {
  var state = Number(seed) >>> 0
  return function() {
    state = (state + 0x6D2B79F5) >>> 0
    var t = state
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

// count points over the unit square: one per cell of a shuffled grid, at a
// random spot inside it. Even, but never in rows the way i * k % n is.
// a and b are two more random numbers per point, for size or brightness.
function scatter(count, seed) {
  var total = Math.max(0, Math.round(Number(count) || 0))
  if (!total) return []
  var next = seededRandom(seed)
  var columns = Math.ceil(Math.sqrt(total * 1.6))
  var rows = Math.ceil(total / columns)
  var cells = []
  for (var i = 0; i < columns * rows; i++) cells.push(i)
  for (var j = cells.length - 1; j > 0; j--) {
    var k = Math.floor(next() * (j + 1))
    var swap = cells[j]
    cells[j] = cells[k]
    cells[k] = swap
  }
  var out = []
  for (var n = 0; n < total; n++) {
    var cell = cells[n]
    out.push({
      x: (cell % columns + next()) / columns,
      y: (Math.floor(cell / columns) + next()) / rows,
      a: next(),
      b: next()
    })
  }
  return out
}

function sky(kind) {
  return SKIES[kind] || SKIES["cloudy-day"]
}

function particles(kind) {
  return PARTICLES[kind] || null
}

// The radar's nearest-rain chip: "Rain here", "Rain 110 mi NW", "No rain nearby".
function nearestRain(nearest, units, snowing) {
  if (!nearest || !isFinite(Number(nearest.km))) return "No rain nearby"
  var km = Number(nearest.km)
  if (km < 8) return snowing ? "Snow here" : "Rain here"
  var distance = units === "metric" ? Math.round(km) + " km" : Math.round(km * 0.621371) + " mi"
  return "Rain " + distance + (nearest.bearing ? " " + nearest.bearing : "")
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
      precipProbability: Number(row.precipProbability) || 0,
      label: day(row.date, i),
      glyph: glyph(row.code, true)
    })
  }
  return out
}

// The coldest low and warmest high across days, in Celsius, for range bars.
function temperatureSpan(days) {
  var low = Infinity
  var high = -Infinity
  for (var i = 0; i < (days || []).length; i++) {
    var lo = Number(days[i] && days[i].low)
    var hi = Number(days[i] && days[i].high)
    if (days[i].low !== null && isFinite(lo)) low = Math.min(low, lo)
    if (days[i].high !== null && isFinite(hi)) high = Math.max(high, hi)
  }
  if (!isFinite(low) || !isFinite(high)) return null
  if (high - low < 1) { high += 0.5; low -= 0.5 }
  return { low: low, high: high }
}

// Where a temperature sits in a span: 0 is the top (warmest), 1 the bottom.
function spanOffset(span, celsius) {
  var value = Number(celsius)
  if (!span || !isFinite(value)) return 0
  return Math.max(0, Math.min(1, (span.high - value) / (span.high - span.low)))
}

var TEMPERATURE_STOPS = [
  [-10, [122, 162, 255]],
  [0, [108, 196, 255]],
  [10, [95, 211, 180]],
  [18, [184, 214, 90]],
  [24, [242, 201, 76]],
  [30, [242, 153, 74]],
  [38, [235, 87, 87]]
]

function hex2(value) {
  var text = Math.round(Math.max(0, Math.min(255, value))).toString(16)
  return text.length < 2 ? "0" + text : text
}

// A cool-to-warm color for a Celsius temperature, as #rrggbb.
function temperatureColor(celsius) {
  var value = Number(celsius)
  if (!isFinite(value)) value = 15
  var stops = TEMPERATURE_STOPS
  if (value <= stops[0][0]) value = stops[0][0]
  if (value >= stops[stops.length - 1][0]) value = stops[stops.length - 1][0]
  for (var i = 1; i < stops.length; i++) {
    if (value <= stops[i][0]) {
      var a = stops[i - 1]
      var b = stops[i]
      var t = (value - a[0]) / (b[0] - a[0])
      return "#" + hex2(a[1][0] + (b[1][0] - a[1][0]) * t)
        + hex2(a[1][1] + (b[1][1] - a[1][1]) * t)
        + hex2(a[1][2] + (b[1][2] - a[1][2]) * t)
    }
  }
  return "#eb5757"
}

// US AQI bands, with a short label that fits beside the number.
var AQI_BANDS = [
  { max: 50, label: "Good", color: "#4cc36b" },
  { max: 100, label: "Moderate", color: "#e3c440" },
  { max: 150, label: "Unhealthy for some", color: "#f08c3a" },
  { max: 200, label: "Unhealthy", color: "#e5534b" },
  { max: 300, label: "Very unhealthy", color: "#a05cc0" },
  { max: 500, label: "Hazardous", color: "#8c2a3c" }
]

function aqiBand(value) {
  var aqi = Number(value)
  if (value === null || value === undefined || !isFinite(aqi)) return null
  for (var i = 0; i < AQI_BANDS.length; i++) {
    if (aqi <= AQI_BANDS[i].max) return { index: i, label: AQI_BANDS[i].label, color: AQI_BANDS[i].color }
  }
  var last = AQI_BANDS.length - 1
  return { index: last, label: AQI_BANDS[last].label, color: AQI_BANDS[last].color }
}

// Position on a scale where each band takes the same width, 0..1.
function aqiPosition(value) {
  var aqi = Number(value)
  if (!isFinite(aqi) || aqi <= 0) return 0
  var floor = 0
  for (var i = 0; i < AQI_BANDS.length; i++) {
    if (aqi <= AQI_BANDS[i].max) return (i + (aqi - floor) / (AQI_BANDS[i].max - floor)) / AQI_BANDS.length
    floor = AQI_BANDS[i].max
  }
  return 1
}

// "12", "4.5", or "—" for a pollutant concentration.
function concentration(value) {
  var amount = Number(value)
  if (value === null || value === undefined || !isFinite(amount)) return "—"
  return amount >= 10 ? String(Math.round(amount)) : amount.toFixed(1)
}

// Open-Meteo pollen in grains/m³ as a level word. Europe only.
function pollenLevel(value) {
  var amount = Number(value)
  if (!isFinite(amount)) return ""
  if (amount < 1) return "None"
  if (amount < 20) return "Low"
  if (amount < 100) return "Moderate"
  if (amount < 500) return "High"
  return "Very high"
}

// The strongest pollen type, or null when none is reported.
function topPollen(pollen) {
  var best = null
  for (var name in (pollen || {})) {
    var amount = Number(pollen[name])
    if (isFinite(amount) && (!best || amount > best.amount)) best = { name: name, amount: amount }
  }
  if (!best) return null
  best.level = pollenLevel(best.amount)
  return best
}

// Minutes since the epoch for a local "YYYY-MM-DDTHH:MM" stamp. Both sides of
// a comparison are in the forecast's own time zone, so UTC math is exact.
function stampMinutes(iso) {
  var match = String(iso || "").match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/)
  if (!match) return NaN
  return Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]), Number(match[4]), Number(match[5])) / 60000
}

// "11h 52m", "40m"
function duration(minutes) {
  var total = Math.max(0, Math.round(Number(minutes) || 0))
  var hours = Math.floor(total / 60)
  return hours > 0 ? hours + "h " + (total % 60) + "m" : (total % 60) + "m"
}

// Tomorrow's daylight against today's: "+2m", "−3m", "−48s".
function daylightChange(todaySeconds, tomorrowSeconds) {
  var a = Number(todaySeconds)
  var b = Number(tomorrowSeconds)
  if (!isFinite(a) || !isFinite(b) || a <= 0 || b <= 0) return ""
  var delta = b - a
  var size = Math.abs(delta)
  var sign = delta < 0 ? "\u2212" : "+"
  return sign + (size >= 60 ? Math.round(size / 60) + "m" : Math.round(size) + "s")
}

// Where the sun is between today's sunrise and sunset.
//   day: true while it is up; progress: 0 at sunrise, 1 at sunset
//   next: "Sunset" or "Sunrise"; until: minutes to it, or NaN
function sunState(now, today, tomorrow) {
  var current = stampMinutes(now)
  var rise = stampMinutes(today && today.sunrise)
  var set = stampMinutes(today && today.sunset)
  var result = { day: false, progress: 0, next: "Sunrise", until: NaN }
  if (!isFinite(current) || !isFinite(rise) || !isFinite(set) || set <= rise) return result
  if (current < rise) {
    result.until = rise - current
    return result
  }
  if (current < set) {
    result.day = true
    result.progress = (current - rise) / (set - rise)
    result.next = "Sunset"
    result.until = set - current
    return result
  }
  result.progress = 1
  var nextRise = stampMinutes(tomorrow && tomorrow.sunrise)
  if (isFinite(nextRise) && nextRise > current) result.until = nextRise - current
  return result
}

var SYNODIC_MONTH = 29.530588853
// A new moon: 2000-01-06 18:14 UTC.
var KNOWN_NEW_MOON = Date.UTC(2000, 0, 6, 18, 14)
var MOON_NAMES = ["New moon", "Waxing crescent", "First quarter", "Waxing gibbous",
  "Full moon", "Waning gibbous", "Last quarter", "Waning crescent"]

// The moon at a moment (ms since the epoch). The nerd-font set runs from
// new (U+E38D) through full (U+E39B) and back, 28 steps.
function moonPhase(ms) {
  var days = (Number(ms) - KNOWN_NEW_MOON) / 86400000
  var age = ((days % SYNODIC_MONTH) + SYNODIC_MONTH) % SYNODIC_MONTH
  var fraction = age / SYNODIC_MONTH
  var step = Math.round(fraction * 28) % 28
  var name = 0
  if (step === 0) name = 0
  else if (step < 7) name = 1
  else if (step === 7) name = 2
  else if (step < 14) name = 3
  else if (step === 14) name = 4
  else if (step < 21) name = 5
  else if (step === 21) name = 6
  else name = 7
  return {
    age: age,
    step: step,
    illumination: Math.round((1 - Math.cos(2 * Math.PI * fraction)) / 2 * 100),
    name: MOON_NAMES[name],
    glyph: String.fromCharCode(0xE38D + step)
  }
}

// Where each radar tile sits so the location lands in the middle of a
// width x height view: [{ index, x, y }] in the sampler's row order.
function radarTiles(radar, width, height) {
  var out = []
  if (!radar || !radar.offset) return out
  var size = Number(radar.tileSize) || 256
  var columns = Number(radar.columns) || 3
  var left = width / 2 - Number(radar.offset.x) * size
  var top = height / 2 - Number(radar.offset.y) * size
  if (!isFinite(left) || !isFinite(top)) return out
  for (var i = 0; i < columns * columns; i++) {
    out.push({ index: i, x: Math.round(left + (i % columns) * size), y: Math.round(top + Math.floor(i / columns) * size) })
  }
  return out
}

// "now", "20 min ago", "1 hr ago" for a frame time in seconds.
function frameAge(seconds, nowMs) {
  var minutes = Math.round((Number(nowMs) - Number(seconds) * 1000) / 60000)
  if (!isFinite(minutes)) return ""
  if (minutes < 3) return "now"
  if (minutes < 60) return minutes + " min ago"
  var hours = Math.floor(minutes / 60)
  var rest = minutes % 60
  return hours + " hr" + (rest >= 5 ? " " + rest + " min" : "") + " ago"
}

// Temperature points for the hours curve, one per column centre.
// Top and bottom padding leave room for the labels above each point.
function chartPoints(rows, units, width, height, padTop, padBottom) {
  var values = []
  for (var i = 0; i < (rows || []).length; i++) {
    var metric = Number(rows[i] && rows[i].temperature)
    if (!isFinite(metric)) continue
    var value = units === "metric" ? metric : metric * 9 / 5 + 32
    values.push(value)
  }
  if (!values.length || width < 2 || height < 2) return []
  var top = padTop === undefined ? 7 : Number(padTop)
  var bottom = padBottom === undefined ? 7 : Number(padBottom)
  var minimum = Math.min.apply(Math, values)
  var maximum = Math.max.apply(Math, values)
  if (maximum - minimum < 1) {
    maximum += 0.5
    minimum -= 0.5
  }
  var column = width / values.length
  var points = []
  for (var j = 0; j < values.length; j++) {
    points.push({
      x: (j + 0.5) * column,
      y: top + (maximum - values[j]) / (maximum - minimum) * Math.max(1, height - top - bottom),
      temperature: Math.round(values[j]),
      label: j === 0 || j === values.length - 1 || j === Math.floor((values.length - 1) / 2)
    })
  }
  return points
}

// The HOURS columns: current conditions as "now", then the coming hours.
function hourColumns(current, hourly, count) {
  var out = []
  var limit = Math.max(0, Math.round(Number(count) || 0))
  if (!limit) return out
  if (current && isFinite(Number(current.temperature))) {
    out.push({
      time: "now",
      temperature: current.temperature,
      code: current.code,
      isDay: current.isDay,
      precipProbability: null
    })
  }
  var rows = hourly || []
  for (var i = 0; i < rows.length && out.length < limit; i++) out.push(rows[i])
  return out
}

function hourlyCount(width) {
  // Discrete HOURS columns on ~270–280px tiles: aim for 10–12.
  if (width >= 300) return 12
  if (width >= 260) return 11
  if (width >= 220) return 10
  if (width >= 180) return 8
  return 6
}

if (typeof module !== "undefined") {
  module.exports = {
    PANELS: PANELS,
    aqiBand: aqiBand,
    aqiPosition: aqiPosition,
    cacheFilePath: cacheFilePath,
    cacheKey: cacheKey,
    chartPoints: chartPoints,
    clock: clock,
    concentration: concentration,
    dailyDays: dailyDays,
    day: day,
    daylightChange: daylightChange,
    frameAge: frameAge,
    glyph: glyph,
    gust: gust,
    hiddenPanels: hiddenPanels,
    hourColumns: hourColumns,
    hourlyCount: hourlyCount,
    SKIES: SKIES,
    moonPhase: moonPhase,
    nearestRain: nearestRain,
    particles: particles,
    nightFlag: nightFlag,
    normalizedLocation: normalizedLocation,
    normalizedSettings: normalizedSettings,
    panelIds: panelIds,
    panelTitle: panelTitle,
    pollenLevel: pollenLevel,
    precipBars: precipBars,
    precipitation: precipitation,
    pressure: pressure,
    radarTiles: radarTiles,
    scatter: scatter,
    settingsWith: settingsWith,
    sky: sky,
    skyKind: skyKind,
    duration: duration,
    spanOffset: spanOffset,
    speed: speed,
    stampMinutes: stampMinutes,
    storedSettings: storedSettings,
    sunClock: sunClock,
    sunState: sunState,
    temperature: temperature,
    temperatureColor: temperatureColor,
    temperatureSpan: temperatureSpan,
    togglePanel: togglePanel,
    topPollen: topPollen,
    visibility: visibility,
    visiblePanels: visiblePanels,
    windDirection: windDirection
  }
}
