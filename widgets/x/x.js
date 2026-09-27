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

function cleanPath(value) {
  return String(value || "").trim()
}

function woeidOf(value) {
  var n = Number(value)
  if (!isFinite(n) || n <= 0) return 1
  return Math.round(n)
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

function normalizedSettings(value) {
  var settings = value && typeof value === "object" ? value : {}
  var woeid = woeidOf(settings.woeid)
  var placeName = String(settings.placeName || "").trim() || placeNameFor(woeid, "")
  return {
    woeid: woeid,
    placeName: placeName,
    countryCode: String(settings.countryCode || "").trim().toUpperCase(),
    maxHeadlines: maxHeadlinesOf(settings.maxHeadlines),
    cookiesPath: cleanPath(settings.cookiesPath)
  }
}

function settingsFor(woeid, placeName, maxHeadlines, cookiesPath, countryCode) {
  var result = {
    woeid: woeidOf(woeid),
    placeName: String(placeName || "").trim() || placeNameFor(woeid, ""),
    maxHeadlines: maxHeadlinesOf(maxHeadlines)
  }
  var code = String(countryCode || "").trim().toUpperCase()
  if (code) result.countryCode = code
  var path = cleanPath(cookiesPath)
  if (path) result.cookiesPath = path
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

if (typeof module !== "undefined") {
  module.exports = {
    placePresets: placePresets,
    normalizedSettings: normalizedSettings,
    settingsFor: settingsFor,
    volumeLabel: volumeLabel,
    notificationLabel: notificationLabel,
    woeidOf: woeidOf,
    maxHeadlinesOf: maxHeadlinesOf,
    placeNameFor: placeNameFor
  }
}
