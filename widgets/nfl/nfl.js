// Presentation helpers for the NFL tile.
//
// Everything here is pure: it reads a game or team object that nfl.py built
// and returns a string, a number, or a small list. Widget.qml imports this
// file and the Node tests require it, so there is one copy of these rules.
//
// QML's JavaScript engine is ES7 without modules, so this file uses `var` and
// `function` and nothing else.

// nf-md-football, for the empty states and the catalog.
var FOOTBALL = "󰉝"

// A missing score is not a zero. Number(null) is 0 in JavaScript, so a game
// that has not started would otherwise read "0 0" instead of nothing.
function scoreNumber(side) {
  if (!side) return NaN
  var raw = side.score
  if (raw === null || raw === undefined || raw === "") return NaN
  var value = Number(raw)
  return isFinite(value) ? value : NaN
}

function sideScore(side) {
  var value = scoreNumber(side)
  if (!isFinite(value)) return "—"
  return String(Math.round(value))
}

function teamAbbr(side) {
  return String((side && side.abbr) || "")
}

function isLeader(game, side) {
  if (!game || !side) return false
  var mine = scoreNumber(side)
  var other = scoreNumber(side === game.away ? game.home : game.away)
  if (!isFinite(mine) || !isFinite(other)) return false
  return mine > other
}

// The side that is behind, or lost, reads quieter. A tie dims nobody.
function trailing(game, side) {
  if (!game || !side) return false
  if (!game.live && !game.finished) return false
  var other = side === game.away ? game.home : game.away
  return isLeader(game, other)
}

function isOffense(game, side) {
  if (!game || !side || !game.live) return false
  var holder = String(game.possession || "")
  return holder !== "" && holder === teamAbbr(side)
}

// Down and distance, then the spot: "2nd & 6 · NYJ 38".
function driveLine(game) {
  if (!game || !game.live) return ""
  var down = String(game.downDistance || "")
  var ball = String(game.ball || "")
  if (down && ball) return down + " · " + ball
  return down || ball
}

// Whoever the model favors right now: "CHI 68%". Nothing at a coin flip.
function winLine(game) {
  if (!game || !game.live || !game.winChance) return ""
  var away = Number(game.winChance.away)
  var home = Number(game.winChance.home)
  if (!isFinite(away) || !isFinite(home) || away === home) return ""
  var side = home > away ? game.home : game.away
  return teamAbbr(side) + " " + Math.round(Math.max(away, home)) + "%"
}

// The ball and the line to gain on a strip drawn from the offence's own goal
// line (0) to the goal it is attacking (100). nfl.py already turned the spot
// into that one number, so there is no second, mirrored marker to misread.
function fieldMarks(game) {
  if (!game || !game.live || !String(game.possession || "")) return null
  var ball = clampYard(game.fieldYard)
  if (ball === null) return null
  var line = clampYard(game.firstDownYard)
  return { ball: ball, line: line }
}

function clampYard(raw) {
  if (raw === null || raw === undefined || raw === "") return null
  var yard = Number(raw)
  if (!isFinite(yard)) return null
  return Math.max(0, Math.min(100, yard))
}

// 0 to 3, or -1 when the feed did not say.
function timeoutsLeft(side) {
  if (!side || side.timeouts === null || side.timeouts === undefined) return -1
  var n = Number(side.timeouts)
  if (!isFinite(n)) return -1
  return Math.max(0, Math.min(3, Math.round(n)))
}

// Built from the day and kickoff fields rather than from `time`, because
// `time` already carries the day and prefixing it again doubled it.
function kickoffLine(game) {
  if (!game) return ""
  if (game.finished) return game.overtime ? "FINAL/OT" : "FINAL"
  if (game.live) return String(game.time || "LIVE")
  var day = String(game.day || "")
  var kickoff = String(game.kickoff || "")
  if (!day || day === "TODAY") return kickoff
  if (kickoff) return day + " " + kickoff
  return day
}

// The next-game card says the date as well as the weekday: SUN OCT 4 · 11 AM.
function whenLine(game) {
  if (!game) return ""
  var day = String(game.day || "")
  var kickoff = String(game.kickoff || "")
  var date = String(game.dateLabel || "")
  var head = day === "TODAY" ? "TODAY" : (day === "TOM" ? "TOMORROW" : (date || day))
  if (head && kickoff) return head + " · " + kickoff
  return head || kickoff
}

// The line and the total as a book prints them: "CHI -3.5 · O/U 43.5".
function oddsLine(game) {
  if (!game) return ""
  var bits = []
  var details = String(game.odds || "").replace("-", "−")
  if (details) bits.push(details)
  var total = Number(game.overUnder)
  if (game.overUnder !== null && game.overUnder !== undefined && isFinite(total) && total > 0)
    bits.push("O/U " + total)
  return bits.join(" · ")
}

// Where it is played: the stadium, else the city. A neutral site says so,
// since that is the surprising part.
function venueLine(game) {
  if (!game) return ""
  var place = String(game.venue || game.city || "")
  if (game.neutral && game.city && place !== game.city) return place + ", " + game.city
  return place
}

// The seed on its own, for a stat cell.
function seedLine(team) {
  if (!team) return ""
  var seed = Number(team.seed)
  if (isFinite(seed) && seed > 0) return "#" + Math.round(seed)
  return ""
}

function differential(value) {
  var number = Number(value)
  if (!isFinite(number) || number === 0) return "0"
  return (number > 0 ? "+" : "−") + String(Math.abs(Math.round(number)))
}

function teamLine(team) {
  if (!team) return ""
  var city = String(team.city || "")
  var nickname = String(team.nickname || team.name || "")
  var full = (city ? city + " " : "") + nickname
  if (full) return full.toUpperCase()
  return String(team.abbr || "").toUpperCase()
}

// A finished game from the club's side: W 27–24 vs NYJ. Without a favorite
// there is no W or L to give, so it falls back to the plain board line.
function resultLine(game) {
  if (!game) return ""
  var favorite = String(game.favorite || "")
  var mine = favorite === "away" ? game.away : (favorite === "home" ? game.home : null)
  var theirs = favorite === "away" ? game.home : (favorite === "home" ? game.away : null)
  if (!mine || !theirs) return boardLine(game)
  var won = String(game.won || "")
  var letter = ""
  if (won === "tie") letter = "T"
  else if (won === favorite) letter = "W"
  else if (won) letter = "L"
  var score = sideScore(mine) + "–" + sideScore(theirs)
  var venue = favorite === "away" ? "@ " : "vs "
  return (letter ? letter + " " : "") + score + " " + venue + teamAbbr(theirs)
}

// The opponent from the club's side: "@ NYJ" or "vs PHI".
function opponentLine(game) {
  if (!game) return ""
  var favorite = String(game.favorite || "")
  if (favorite === "away") return "@ " + teamAbbr(game.home)
  if (favorite === "home") return "vs " + teamAbbr(game.away)
  return teamAbbr(game.away) + " @ " + teamAbbr(game.home)
}

// One slate row as text, for a test or a tooltip.
function boardLine(game) {
  if (!game) return ""
  var away = game.away || {}
  var home = game.home || {}
  if (!game.live && !game.finished) return teamAbbr(away) + " @ " + teamAbbr(home)
  return teamAbbr(away) + " " + sideScore(away) + " @ " + teamAbbr(home) + " " + sideScore(home)
}

// A narrow slate row says "SUN 11a" instead of "SUN 11 AM".
function boardState(game, narrow) {
  if (!game) return ""
  if (game.live) return String(game.time || "LIVE")
  if (game.finished) return game.overtime ? "F/OT" : "FINAL"
  var line = kickoffLine(game)
  if (!narrow) return line
  return line.replace(/ AM$/, "a").replace(/ PM$/, "p")
}

// Which week this is, for a header. The postseason has rounds.
var ROUNDS = { 1: "WILD CARD", 2: "DIVISIONAL", 3: "CONFERENCE", 4: "PRO BOWL", 5: "SUPER BOWL" }

function weekLine(game) {
  if (!game) return ""
  var seasonType = Number(game.seasonType)
  var week = Number(game.week)
  if (seasonType === 3) return (isFinite(week) && ROUNDS[week]) ? ROUNDS[week] : "PLAYOFFS"
  if (!isFinite(week) || week < 1) return seasonType === 1 ? "PRESEASON" : ""
  if (seasonType === 1) return "PRESEASON WK " + Math.round(week)
  return "WEEK " + Math.round(week)
}

// Points by quarter, padded to four columns, with overtime after. A quarter
// not played yet is blank, not zero.
function lineTable(game) {
  var away = (game && game.away && game.away.lines) || []
  var home = (game && game.home && game.home.lines) || []
  var count = Math.max(4, away.length, home.length)
  var labels = []
  for (var i = 0; i < count; i++) {
    if (i < 4) labels.push(String(i + 1))
    else labels.push(i === 4 ? "OT" : (i - 3) + "OT")
  }
  function cells(lines) {
    var out = []
    for (var j = 0; j < count; j++) out.push(j < lines.length ? String(lines[j]) : "")
    return out
  }
  return { labels: labels, away: cells(away), home: cells(home), played: Math.max(away.length, home.length) }
}

function leaderRows(game) {
  var rows = (game && game.leaders) || []
  var out = []
  for (var i = 0; i < rows.length && out.length < 3; i++) {
    var row = rows[i]
    if (!row || !row.name || !row.line) continue
    out.push({ cat: String(row.cat || ""), name: String(row.name), team: String(row.team || ""), line: String(row.line) })
  }
  return out
}

function divisionRows(team) {
  var rows = (team && team.table) || []
  var out = []
  for (var i = 0; i < rows.length && out.length < 4; i++) {
    if (rows[i] && rows[i].abbr) out.push(rows[i])
  }
  return out
}

function lastPlay(game) {
  if (!game || !game.live) return ""
  // "(Shotgun)" and "(No Huddle, Shotgun)" lead most plays and say little.
  return String(game.lastPlay || "").replace(/\s+/g, " ").trim().replace(/^\([^)]*\)\s*/, "")
}

// ---------------------------------------------------------------- color

// A club's colors were chosen for white jerseys, not for a dark tile. Pick the
// one that stands off the tile's own fill, and fall back to the ink when
// neither does.
function luminance(hex) {
  var value = String(hex || "")
  if (!/^#[0-9a-fA-F]{6}$/.test(value)) return -1
  var out = 0
  var weights = [0.2126, 0.7152, 0.0722]
  for (var i = 0; i < 3; i++) {
    var c = parseInt(value.substr(1 + i * 2, 2), 16) / 255
    c = c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)
    out += weights[i] * c
  }
  return out
}

function contrast(a, b) {
  var la = luminance(a)
  var lb = luminance(b)
  if (la < 0 || lb < 0) return 0
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
}

// A QML color (or anything with r, g, b from 0 to 1) as #rrggbb.
function colorHex(c) {
  if (!c) return ""
  function two(v) {
    var n = Math.round(Math.max(0, Math.min(1, Number(v) || 0)) * 255).toString(16)
    return n.length < 2 ? "0" + n : n
  }
  return "#" + two(c.r) + two(c.g) + two(c.b)
}

function isDark(hex) {
  var lum = luminance(hex)
  return lum >= 0 && lum < 0.2
}

// Text on a club-colored block: dark on a light color, white on the rest.
function inkOn(hex) {
  var lum = luminance(hex)
  if (lum < 0) return "#ffffff"
  return lum > 0.4 ? "#111111" : "#ffffff"
}

// ESPN draws eight clubs a second time for dark backgrounds, where the usual
// mark is dark on dark (the Jets' green wordmark, the Giants' blue).
var DARK_LOGOS = { DAL: true, DEN: true, GB: true, LAR: true, LV: true, MIN: true, NYG: true, NYJ: true }

function logoPath(side, darkPaper) {
  var abbr = teamAbbr(side)
  if (!/^[A-Z]{2,3}$/.test(abbr)) return ""
  if (darkPaper && DARK_LOGOS[abbr]) return "logos/dark/" + abbr + ".png"
  return "logos/" + abbr + ".png"
}

function tint(side, paper, ink) {
  var main = String((side && side.color) || "")
  var alt = String((side && side.alt) || "")
  if (contrast(main, paper) >= 2.2) return main
  if (contrast(alt, paper) >= 2.2) return alt
  return String(ink || "")
}

// The tile says something honest in each gap. Before the first fetch it is
// still fetching, which is not the same as there being no games.
function emptyHeadline(mode, error, loaded) {
  if (error) return "Scores unavailable"
  if (loaded === false) return "NFL"
  if (mode === "closed") return "Season complete"
  if (mode === "upcoming") return "No game found"
  return "No games this week"
}

function emptyBody(mode, error, loaded) {
  if (error) return "ESPN did not answer. The tile tries again on its own."
  if (loaded === false) return "Fetching the schedule…"
  if (mode === "closed") return "Nothing left on the schedule."
  if (mode === "upcoming") return "Choose a club in settings."
  return "Nothing is scheduled right now."
}

if (typeof module !== "undefined") {
  module.exports = {
    DARK_LOGOS: DARK_LOGOS,
    FOOTBALL: FOOTBALL,
    boardLine: boardLine,
    boardState: boardState,
    colorHex: colorHex,
    contrast: contrast,
    differential: differential,
    divisionRows: divisionRows,
    driveLine: driveLine,
    emptyBody: emptyBody,
    emptyHeadline: emptyHeadline,
    fieldMarks: fieldMarks,
    inkOn: inkOn,
    isDark: isDark,
    isLeader: isLeader,
    isOffense: isOffense,
    kickoffLine: kickoffLine,
    lastPlay: lastPlay,
    leaderRows: leaderRows,
    lineTable: lineTable,
    logoPath: logoPath,
    luminance: luminance,
    oddsLine: oddsLine,
    opponentLine: opponentLine,
    resultLine: resultLine,
    seedLine: seedLine,
    sideScore: sideScore,
    teamAbbr: teamAbbr,
    teamLine: teamLine,
    timeoutsLeft: timeoutsLeft,
    tint: tint,
    trailing: trailing,
    venueLine: venueLine,
    weekLine: weekLine,
    whenLine: whenLine,
    winLine: winLine
  }
}
