function placePresets() {
  return [
    { woeid: 1, name: "Worldwide", countryCode: "" },
    { woeid: 23424977, name: "United States", countryCode: "US" },
    { woeid: 23424975, name: "United Kingdom", countryCode: "GB" },
    { woeid: 23424775, name: "Canada", countryCode: "CA" },
    { woeid: 23424748, name: "Australia", countryCode: "AU" },
    { woeid: 2459115, name: "New York", countryCode: "US" },
    { woeid: 2442047, name: "Los Angeles", countryCode: "US" },
    { woeid: 2379574, name: "Chicago", countryCode: "US" },
    { woeid: 2487956, name: "San Francisco", countryCode: "US" },
    { woeid: 44418, name: "London", countryCode: "GB" },
    { woeid: 1105779, name: "Sydney", countryCode: "AU" },
    { woeid: 4118, name: "Toronto", countryCode: "CA" }
  ]
}

var DEFAULT_COOKIES_PATH = "~/.config/ande.launcher/x-cookies.json"

function cleanPath(value) {
  return String(value || "").trim()
}

function defaultCookiesPath() {
  return DEFAULT_COOKIES_PATH
}

function effectiveCookiesPath(value) {
  var path = cleanPath(value)
  return path || DEFAULT_COOKIES_PATH
}

var WORLDWIDE = 1

function woeidOf(value) {
  var n = Number(value)
  if (!isFinite(n) || n <= 0) return WORLDWIDE
  return Math.round(n)
}

function isWorldwide(woeid) {
  return woeidOf(woeid) === WORLDWIDE
}

function maxHeadlinesOf(value) {
  var n = Number(value)
  if (!isFinite(n)) return 8
  n = Math.round(n)
  if (n < 3) return 3
  if (n > 10) return 10
  return n
}

function placeNameFor(woeid, fallback) {
  var id = woeidOf(woeid)
  var rows = placePresets()
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].woeid === id) return String(rows[i].name || "")
  }
  return String(fallback || ("WOEID " + id))
}

function sessionAtOf(value) {
  var n = Number(value)
  if (!isFinite(n) || n <= 0) return 0
  return Math.round(n)
}

function normalizedSettings(value) {
  var settings = value && typeof value === "object" ? value : {}
  var woeid = woeidOf(settings.woeid)
  var placeName = String(settings.placeName || "").trim() || placeNameFor(woeid, "")
  return {
    woeid: woeid,
    placeName: placeName,
    countryCode: String(settings.countryCode || "").trim().toUpperCase(),
    maxHeadlines: maxHeadlinesOf(settings.maxHeadlines),
    cookiesPath: cleanPath(settings.cookiesPath),
    sessionAt: sessionAtOf(settings.sessionAt)
  }
}

function settingsFor(woeid, placeName, maxHeadlines, cookiesPath, countryCode, sessionAt) {
  var result = { maxHeadlines: maxHeadlinesOf(maxHeadlines) }
  // Worldwide is the default, so a cleared place leaves no place keys behind.
  if (!isWorldwide(woeid)) {
    result.woeid = woeidOf(woeid)
    result.placeName = String(placeName || "").trim() || placeNameFor(woeid, "")
    var code = String(countryCode || "").trim().toUpperCase()
    if (code) result.countryCode = code
  }
  var path = cleanPath(cookiesPath)
  if (path) result.cookiesPath = path
  var stamp = sessionAtOf(sessionAt)
  if (stamp) result.sessionAt = stamp
  return result
}

function volumeLabel(volume) {
  var n = Number(volume)
  if (!isFinite(n) || n <= 0) return ""
  if (n >= 1000000) {
    var m = (n / 1000000).toFixed(1)
    if (m.slice(-2) === ".0") m = m.slice(0, -2)
    return m + "M"
  }
  if (n >= 1000) {
    var k = (n / 1000).toFixed(1)
    if (k.slice(-2) === ".0") k = k.slice(0, -2)
    return k + "K"
  }
  return String(Math.round(n))
}

function notificationLabel(notifications) {
  if (!notifications || typeof notifications !== "object") return ""
  if (!notifications.ok) return ""
  var count = Number(notifications.count)
  if (!isFinite(count) || count <= 0) return ""
  if (count > 99) return "99+"
  return String(Math.round(count))
}

function sourceOf(sample) {
  if (!sample || typeof sample !== "object") return ""
  return String(sample.source || "")
}

function headlinesOf(sample) {
  // Array-like, not Array.isArray: a list that crossed into QML from a
  // property is a sequence wrapper, and isArray turns it down.
  var rows = sample && typeof sample === "object" ? sample.headlines : null
  if (!rows || typeof rows !== "object" || !(rows.length > 0)) return []
  return rows
}

function headerTitle(sample) {
  var source = sourceOf(sample)
  if (source === "news") return "X · TODAY'S NEWS"
  if (source === "trends") return "X · TRENDING"
  return "X"
}

// The place belongs to guest trends. Today's News is one feed wherever the
// tile is set, so naming a city over it says something that is not true.
function placeCaption(sample, options) {
  if (sourceOf(sample) !== "trends") return ""
  var place = sample.place
  if (place && place.name) return String(place.name)
  return String((options && options.placeName) || "Worldwide")
}

// The dim line under a headline: a trend's post count, or a story's category.
function headlineMeta(row) {
  if (!row || typeof row !== "object") return ""
  var volume = volumeLabel(row.volume)
  if (volume) return volume + " posts"
  return String(row.category || "").trim()
}

// Guest trends with no session saved. A session whose news call failed is
// not told to sign in again.
function signInHint(sample) {
  if (!sample || sample.ok !== true || sourceOf(sample) !== "trends") return false
  return !sample.signedIn
}

if (typeof module !== "undefined") {
  module.exports = {
    placePresets: placePresets,
    normalizedSettings: normalizedSettings,
    settingsFor: settingsFor,
    volumeLabel: volumeLabel,
    notificationLabel: notificationLabel,
    woeidOf: woeidOf,
    isWorldwide: isWorldwide,
    maxHeadlinesOf: maxHeadlinesOf,
    placeNameFor: placeNameFor,
    DEFAULT_COOKIES_PATH: DEFAULT_COOKIES_PATH,
    defaultCookiesPath: defaultCookiesPath,
    effectiveCookiesPath: effectiveCookiesPath,
    sessionAtOf: sessionAtOf,
    headlinesOf: headlinesOf,
    headerTitle: headerTitle,
    placeCaption: placeCaption,
    headlineMeta: headlineMeta,
    signInHint: signInHint
  }
}
