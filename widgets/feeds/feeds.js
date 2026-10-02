// Logic for the feeds tile. Widget.qml and Settings.qml import it;
// test_logic.cjs requires it.

var MAX_FEEDS = 6
var NEW_SECONDS = 3600

function fmtAge(nowSec, thenSec) {
  var then = Number(thenSec) || 0
  if (then <= 0) return ""
  var seconds = Math.max(0, Math.floor(Number(nowSec) - then))
  if (seconds < 60) return "now"
  var minutes = Math.floor(seconds / 60)
  if (minutes < 60) return minutes + "m"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h"
  var days = Math.floor(hours / 24)
  if (days < 30) return days + "d"
  return Math.floor(days / 30) + "mo"
}

function isNew(item, nowSec) {
  var at = Number(item && item.at) || 0
  return at > 0 && Number(nowSec) - at < NEW_SECONDS
}

function caption(item, nowSec) {
  if (!item) return ""
  var age = fmtAge(nowSec, item.at)
  return String(item.source || "") + (age ? " · " + age : "")
}

function failing(feeds) {
  var n = 0
  for (var i = 0; i < (feeds || []).length; i++) if (!feeds[i].ok) n++
  return n
}

function headerNote(sample) {
  if (!sample) return ""
  var bad = failing(sample.feeds)
  if (bad > 0) return bad === 1 ? "1 feed down" : bad + " feeds down"
  var n = (sample.feeds || []).length
  return n === 1 ? String(sample.feeds[0].name || "") : (n > 0 ? n + " feeds" : "")
}

// The feeds the tile follows. An absent list follows the sampler's defaults.
function feeds(settings) {
  var list = settings && Array.isArray(settings.feeds) ? settings.feeds : null
  if (!list) return null
  var out = []
  var seen = {}
  for (var i = 0; i < list.length && out.length < MAX_FEEDS; i++) {
    var key = feedKey(list[i])
    if (!key || seen[key]) continue
    seen[key] = true
    out.push(list[i])
  }
  return out
}

function feedKey(item) {
  if (typeof item === "string") return item
  if (item && typeof item === "object" && item.url) return String(item.url)
  return ""
}

function settingsFrom(list) {
  return { feeds: list.slice(0, MAX_FEEDS) }
}

function withAdded(current, item) {
  var list = (current || []).slice()
  var key = feedKey(item)
  for (var i = 0; i < list.length; i++) if (feedKey(list[i]) === key) return list
  if (list.length >= MAX_FEEDS) return list
  list.push(item)
  return list
}

function withRemoved(current, index) {
  var list = (current || []).slice()
  if (index >= 0 && index < list.length) list.splice(index, 1)
  return list
}

// Catalog feeds that match the typed text by name, id, or address. A custom
// feed whose URL is a catalog feed's URL counts as that feed.
function filterCatalog(catalog, query, current) {
  var q = String(query || "").trim().toLowerCase()
  var taken = {}
  for (var i = 0; i < (current || []).length; i++) taken[feedKey(current[i])] = true
  var out = []
  for (var j = 0; j < (catalog || []).length; j++) {
    var row = catalog[j]
    if (!q || String(row.name).toLowerCase().indexOf(q) >= 0 || String(row.id).indexOf(q) >= 0 || String(row.url).toLowerCase().indexOf(q) >= 0)
      out.push({ id: row.id, name: row.name, url: row.url, added: !!(taken[row.id] || taken[row.url]) })
  }
  return out
}

function looksLikeUrl(text) {
  var value = String(text || "").trim()
  if (/^https?:\/\//i.test(value)) return value.length > 10
  return /^[a-z0-9-]+(\.[a-z0-9-]+)+(:\d+)?(\/\S*)?$/i.test(value)
}

function nameFor(item, catalog) {
  if (item && typeof item === "object") return String(item.name || item.url || "")
  for (var i = 0; i < (catalog || []).length; i++) if (catalog[i].id === item) return String(catalog[i].name)
  return String(item || "")
}

if (typeof module !== "undefined") {
  module.exports = {
    MAX_FEEDS: MAX_FEEDS,
    NEW_SECONDS: NEW_SECONDS,
    fmtAge: fmtAge,
    isNew: isNew,
    caption: caption,
    failing: failing,
    headerNote: headerNote,
    feeds: feeds,
    feedKey: feedKey,
    settingsFrom: settingsFrom,
    withAdded: withAdded,
    withRemoved: withRemoved,
    filterCatalog: filterCatalog,
    looksLikeUrl: looksLikeUrl,
    nameFor: nameFor
  }
}
