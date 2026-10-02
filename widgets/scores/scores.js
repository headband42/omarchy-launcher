// Logic for the scores tile. Widget.qml and Settings.qml import it;
// test_logic.cjs requires it.

var DAY_NAMES = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var MONTH_NAMES = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

function clock(d, h24) {
  var h = d.getHours()
  var m = d.getMinutes()
  var mm = (m < 10 ? "0" : "") + m
  if (h24) return (h < 10 ? "0" : "") + h + ":" + mm
  var hh = h % 12 === 0 ? 12 : h % 12
  return hh + (m === 0 ? "" : ":" + mm) + (h < 12 ? "am" : "pm")
}

function sameDay(a, b) {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
}

// When a game that has not started begins, in the viewer's own time.
function startText(game, nowMs, h24) {
  if (!game || !game.start) return ""
  var d = new Date(Number(game.start) * 1000)
  var now = new Date(nowMs)
  var days = Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate()) - new Date(now.getFullYear(), now.getMonth(), now.getDate())) / 86400000)
  var day = days === 0 ? "" : (days === 1 ? "Tmrw " : (days > 1 && days < 7 ? DAY_NAMES[d.getDay()] + " " : MONTH_NAMES[d.getMonth()] + " " + d.getDate() + " "))
  if (game.tbd) return (day || "Today ") + "TBD"
  return day + clock(d, h24)
}

function statusText(game, nowMs, h24) {
  if (!game) return ""
  if (game.state === "pre") return startText(game, nowMs, h24)
  return String(game.detail || (game.state === "post" ? "Final" : ""))
}

// A side is dimmed once the game is over and it lost.
function dimmed(game, part) {
  if (!game || game.state !== "post") return false
  var mine = game[part] || {}
  var other = game[part === "home" ? "away" : "home"] || {}
  if (mine.winner === false && other.winner === true) return true
  if (mine.winner === null || mine.winner === undefined) {
    var a = Number(mine.score)
    var b = Number(other.score)
    return isFinite(a) && isFinite(b) && a < b
  }
  return false
}

function liveCount(sample) {
  return Number(sample && sample.live) || 0
}

function title(sample, settings) {
  if (sample && sample.team && (sample.team.short || sample.team.name)) return String(sample.team.short || sample.team.name).toUpperCase()
  if (sample && sample.league) return String(sample.league.name).toUpperCase()
  return "SCORES"
}

function headerNote(sample) {
  var live = liveCount(sample)
  if (live > 0) return live + " live"
  return sample && sample.team && sample.league ? String(sample.league.name) : ""
}

// The light or dark mark for a team, for the theme's background.
function logoFor(side, darkTheme) {
  if (!side) return ""
  var path = darkTheme && side.logoDark ? side.logoDark : side.logo
  return path ? "file://" + path : ""
}

function isDark(r, g, b) {
  return (0.2126 * r + 0.7152 * g + 0.0722 * b) < 0.5
}

// Settings: one league, and an optional team in it.
function settingsFor(league, team) {
  var out = {}
  if (league) out.league = String(league)
  if (team) out.team = String(team)
  return out
}

function leagueOf(settings, fallback) {
  return settings && settings.league ? String(settings.league) : (fallback || "nba")
}

function teamOf(settings) {
  return settings && settings.team ? String(settings.team) : ""
}

function filterTeams(teams, query) {
  var q = String(query || "").trim().toLowerCase()
  var list = Array.isArray(teams) ? teams : []
  if (!q) return list
  return list.filter(function(t) {
    return String(t.name).toLowerCase().indexOf(q) >= 0 || String(t.abbr).toLowerCase() === q
  })
}

if (typeof module !== "undefined") {
  module.exports = {
    clock: clock,
    sameDay: sameDay,
    startText: startText,
    statusText: statusText,
    dimmed: dimmed,
    liveCount: liveCount,
    title: title,
    headerNote: headerNote,
    logoFor: logoFor,
    isDark: isDark,
    settingsFor: settingsFor,
    leagueOf: leagueOf,
    teamOf: teamOf,
    filterTeams: filterTeams
  }
}
