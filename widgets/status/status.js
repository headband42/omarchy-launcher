// Logic for the status tile. Widget.qml and Settings.qml import it;
// test_logic.cjs requires it.

var MAX_SERVICES = 8
var SEVERITY = { none: 0, maintenance: 1, unknown: 2, minor: 3, major: 4, critical: 5, down: 5 }

function severity(state) {
  var value = SEVERITY[String(state || "")]
  return value === undefined ? 2 : value
}

function isProblem(state) {
  return severity(state) >= 3
}

// Problems float to the top, worst first; the rest keep the user's order.
function sortRows(rows) {
  var list = Array.isArray(rows) ? rows.slice() : []
  var indexed = list.map(function(row, i) { return { row: row, i: i } })
  indexed.sort(function(a, b) {
    var pa = isProblem(a.row.state) ? severity(a.row.state) : 0
    var pb = isProblem(b.row.state) ? severity(b.row.state) : 0
    return pb - pa || a.i - b.i
  })
  return indexed.map(function(x) { return x.row })
}

function stateLabel(state) {
  switch (String(state || "")) {
  case "none": return "ok"
  case "maintenance": return "maintenance"
  case "minor": return "degraded"
  case "major": return "outage"
  case "critical": return "major outage"
  case "down": return "down"
  default: return "unknown"
  }
}

function headerNote(rows) {
  var list = Array.isArray(rows) ? rows : []
  if (list.length === 0) return ""
  var problems = 0
  var unknown = 0
  var maintenance = 0
  for (var i = 0; i < list.length; i++) {
    var state = list[i].state
    if (isProblem(state)) problems++
    else if (state === "maintenance") maintenance++
    else if (state !== "none") unknown++
  }
  if (problems > 0) return problems === 1 ? "1 issue" : problems + " issues"
  if (maintenance > 0) return "maintenance"
  if (unknown === list.length) return "no answer"
  return "all good"
}

// The services the tile follows: catalog ids and custom entries. An absent
// list follows the defaults the sampler names.
function services(settings) {
  var list = settings && Array.isArray(settings.services) ? settings.services : null
  if (!list) return null
  var out = []
  var seen = {}
  for (var i = 0; i < list.length && out.length < MAX_SERVICES; i++) {
    var item = list[i]
    var key = serviceKey(item)
    if (!key || seen[key]) continue
    seen[key] = true
    out.push(item)
  }
  return out
}

function serviceKey(item) {
  if (typeof item === "string") return item
  if (item && typeof item === "object" && item.url) return String(item.kind || "http") + ":" + String(item.url)
  return ""
}

function settingsFrom(list) {
  return { services: list.slice(0, MAX_SERVICES) }
}

function withAdded(current, item) {
  var list = (current || []).slice()
  var key = serviceKey(item)
  for (var i = 0; i < list.length; i++) if (serviceKey(list[i]) === key) return list
  if (list.length >= MAX_SERVICES) return list
  list.push(item)
  return list
}

function withRemoved(current, index) {
  var list = (current || []).slice()
  if (index >= 0 && index < list.length) list.splice(index, 1)
  return list
}

function withMoved(current, index, delta) {
  var list = (current || []).slice()
  var to = index + delta
  if (index < 0 || index >= list.length || to < 0 || to >= list.length) return list
  var item = list.splice(index, 1)[0]
  list.splice(to, 0, item)
  return list
}

// The catalog rows that match what the user typed, by name or host.
function filterCatalog(catalog, query, current) {
  var q = String(query || "").trim().toLowerCase()
  var taken = {}
  for (var i = 0; i < (current || []).length; i++) taken[serviceKey(current[i])] = true
  var out = []
  for (var j = 0; j < (catalog || []).length; j++) {
    var row = catalog[j]
    if (!q || String(row.name).toLowerCase().indexOf(q) >= 0 || String(row.host).toLowerCase().indexOf(q) >= 0 || String(row.id).indexOf(q) >= 0)
      out.push({ id: row.id, name: row.name, host: row.host, added: !!taken[row.id] })
  }
  return out
}

// Typed text that could be a site of the user's own: a host or a URL.
function looksLikeUrl(text) {
  var value = String(text || "").trim()
  if (/^https?:\/\//i.test(value)) return value.length > 10
  return /^[a-z0-9-]+(\.[a-z0-9-]+)+(:\d+)?(\/\S*)?$/i.test(value) || /^[a-z0-9-]+:\d{2,5}$/i.test(value)
}

function nameFor(item, catalog) {
  if (item && typeof item === "object") return String(item.name || item.url || "")
  for (var i = 0; i < (catalog || []).length; i++) if (catalog[i].id === item) return String(catalog[i].name)
  return String(item || "")
}

function fmtAgo(nowSec, thenSec) {
  var then = Number(thenSec) || 0
  if (then <= 0) return ""
  var minutes = Math.floor(Math.max(0, Number(nowSec) - then) / 60)
  if (minutes < 1) return "just now"
  if (minutes < 60) return minutes + "m ago"
  return Math.floor(minutes / 60) + "h ago"
}

if (typeof module !== "undefined") {
  module.exports = {
    MAX_SERVICES: MAX_SERVICES,
    severity: severity,
    isProblem: isProblem,
    sortRows: sortRows,
    stateLabel: stateLabel,
    headerNote: headerNote,
    services: services,
    serviceKey: serviceKey,
    settingsFrom: settingsFrom,
    withAdded: withAdded,
    withRemoved: withRemoved,
    withMoved: withMoved,
    filterCatalog: filterCatalog,
    looksLikeUrl: looksLikeUrl,
    nameFor: nameFor,
    fmtAgo: fmtAgo
  }
}
