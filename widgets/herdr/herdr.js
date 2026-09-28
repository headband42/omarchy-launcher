// Presentation helpers for the Herdr tile.
//
// Pure functions over the payload herdr.py built. Widget.qml and
// Settings.qml import this file and the Node tests require it, so the rules
// live in one place.
//
// QML's JavaScript engine is ES7 without modules, so this file uses `var` and
// `function` and nothing else.

// The order Herdr's schema fixes, and the order a person wants to read them:
// blocked is the one that needs a human.
var STATUSES = ["blocked", "working", "idle", "done", "unknown"]

function statusOf(agent) {
  var name = String((agent && agent.status) || "")
  return STATUSES.indexOf(name) >= 0 ? name : "unknown"
}

// The QML side owns the palette, so this returns a token name rather than a
// color. `blocked` borrows the urgent color: it means an agent is waiting on
// the person reading the tile.
function statusTone(status) {
  var name = String(status || "")
  if (name === "blocked") return "urgent"
  if (name === "working") return "accent"
  if (name === "done") return "quiet"
  return "muted"
}

function statusLabel(status) {
  var name = String(status || "")
  return STATUSES.indexOf(name) >= 0 ? name.toUpperCase() : "UNKNOWN"
}

function isBusy(status) {
  var name = String(status || "")
  return name === "working" || name === "blocked"
}

function needsAttention(counts) {
  if (!counts) return 0
  var blocked = Number(counts.blocked) || 0
  var working = Number(counts.working) || 0
  return blocked + working
}

function countFor(counts, status) {
  if (!counts) return 0
  var value = Number(counts[status])
  return isFinite(value) && value > 0 ? Math.round(value) : 0
}

// "2 working · 1 idle", blocked first, zeros dropped, and "no agents" rather
// than a string of nothing.
function summary(counts) {
  if (!counts) return "no agents"
  var parts = []
  for (var i = 0; i < STATUSES.length; i++) {
    var name = STATUSES[i]
    var value = countFor(counts, name)
    if (value > 0) parts.push(value + " " + name)
  }
  return parts.length ? parts.join(" · ") : "no agents"
}

// The header says the one thing worth glancing at, not everything. The count
// is the plural, so the word itself never needs one.
function headline(counts) {
  if (!counts) return "NO AGENTS"
  if (countFor(counts, "blocked") > 0) return countFor(counts, "blocked") + " BLOCKED"
  if (countFor(counts, "working") > 0) return countFor(counts, "working") + " WORKING"
  var idle = countFor(counts, "idle")
  var done = countFor(counts, "done")
  if (idle > 0 && !done) return idle + " IDLE"
  if (idle > 0 || done > 0) return "ALL QUIET"
  return "NO AGENTS"
}

function headlineTone(counts) {
  if (countFor(counts, "blocked") > 0) return "urgent"
  if (countFor(counts, "working") > 0) return "accent"
  return "muted"
}

// One letter for the avatar chip. A name like "opencode" reads as "o", which
// is enough to tell two agents apart at tile size.
function initial(agent) {
  var name = String((agent && agent.name) || "")
  if (!name) return "?"
  return name.slice(0, 1).toUpperCase()
}

function agentName(agent) {
  var name = String((agent && agent.name) || "")
  return name || "pane"
}

function agentTitle(agent) {
  var title = String((agent && agent.title) || "")
  if (title) return title
  var cwd = String((agent && agent.cwd) || "")
  return cwd || ""
}

function isFocused(agent) {
  return !!(agent && agent.focused)
}

function agentsOf(sample) {
  var rows = sample && sample.agents
  return rows && rows.length ? rows : []
}

// A row is two lines tall in a roomy tile and one line in a small one, so the
// count of visible rows is derived from the tile rather than fixed: a herdr
// session can easily hold a dozen agents.
function rowHeight(height) {
  var h = Number(height)
  if (!isFinite(h) || h < 1) return 28
  return Math.max(20, Math.round(h / 7))
}

function twoLine(height) {
  return Number(height) >= 250
}

// Where a scrolled list currently sits, worked out from a list view's
// contentY rather than tracked separately, so the footer cannot disagree with
// what is on screen. The numbers answer "is there more, and which way".
function visibleWindow(offset, step, total, capacity) {
  var rowHeight = Math.max(1, Number(step) || 1)
  var count = Math.max(0, Number(total) || 0)
  var rows = Math.max(0, Math.floor(Number(capacity) || 0))
  if (count < 1 || rows < 1) {
    return { index: 0, total: count, above: 0, below: 0, text: "" }
  }
  var first = Math.floor(Math.max(0, Number(offset) || 0) / rowHeight)
  var lastFirst = Math.max(0, count - rows)
  if (first > lastFirst) first = lastFirst
  if (first < 0) first = 0
  return {
    index: first + 1,
    total: count,
    above: first,
    below: Math.max(0, count - first - rows),
    text: (first + 1) + "/" + count
  }
}

function footerHint(win) {
  if (!win || !win.total) return ""
  var above = Number(win.above) || 0
  var below = Number(win.below) || 0
  if (above > 0 && below > 0) return above + " above · " + below + " below"
  if (above > 0) return above + " above"
  if (below > 0) return below + " below"
  return ""
}

// There are three different kinds of nothing, and the tile should say which.
// A section that holds no agents is not an empty session, and a session
// filtered down to nothing is not a broken section.
function emptyHeadline(sample) {
  if (sample && sample.error) return "Herdr is not answering"
  if (sample && sample.busyOnly) return "Nothing running"
  if (sample && sample.hidden) return "Nothing here"
  return "No agents"
}

function emptyBody(sample) {
  if (sample && sample.error) return String(sample.error)
  if (sample && sample.busyOnly) return "No agent is working or blocked here."
  if (sample && sample.hidden) return "This section has no agents in it."
  return "Start an agent in Herdr."
}

function sectionLabel(sample) {
  var label = String((sample && sample.sectionLabel) || "")
  return label || "All sections"
}

function versionLabel(sample) {
  var version = String((sample && sample.version) || "")
  return version ? "v" + version : ""
}

// A pane id is Herdr's own and looks like `w1:p6`. Only that shape is ever
// passed on, so a row cannot ask the launcher to focus anything else. The
// launcher checks the same shape again before it runs anything.
var PANE = /^[A-Za-z0-9_-]{1,32}:[A-Za-z0-9_-]{1,32}$/

function paneId(agent) {
  var value = String((agent && agent.paneId) || "")
  return PANE.test(value) ? value : ""
}

function isFocusable(agent) {
  return paneId(agent) !== ""
}

if (typeof module !== "undefined") {
  module.exports = {
    PANE: PANE,
    STATUSES: STATUSES,
    agentName: agentName,
    agentTitle: agentTitle,
    agentsOf: agentsOf,
    countFor: countFor,
    emptyBody: emptyBody,
    emptyHeadline: emptyHeadline,
    footerHint: footerHint,
    headline: headline,
    headlineTone: headlineTone,
    initial: initial,
    isBusy: isBusy,
    isFocusable: isFocusable,
    isFocused: isFocused,
    needsAttention: needsAttention,
    paneId: paneId,
    rowHeight: rowHeight,
    sectionLabel: sectionLabel,
    statusLabel: statusLabel,
    statusOf: statusOf,
    statusTone: statusTone,
    summary: summary,
    twoLine: twoLine,
    visibleWindow: visibleWindow,
    versionLabel: versionLabel
  }
}
