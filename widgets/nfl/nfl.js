// Presentation helpers for the NFL tile.
//
// Everything here is pure: it reads a game or team object that nfl.py built
// and returns a string or a number. The same file is imported by Widget.qml
// and Settings.qml and required by the Node tests, so there is one copy of
// these rules rather than a second one in a test.
//
// QML's JavaScript engine is ES7 without modules, so this file uses `var` and
// `function` and nothing else.

// A missing score is not a zero. Number(null) is 0 in JavaScript, so a game
// that has not started would otherwise read "0 0" instead of a dash.
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

function hasBall(game, side) {
  if (!game || !side) return false
  var abbr = teamAbbr(side)
  return !!abbr && String(game.possession || "") === abbr
}

function isLeader(game, side) {
  if (!game || !side) return false
  var mine = scoreNumber(side)
  var other = scoreNumber(side === game.away ? game.home : game.away)
  if (!isFinite(mine) || !isFinite(other)) return false
  return mine > other
}

// The drive, in one line. A football tile without this is just two numbers.
function situationLine(game) {
  if (!game || !game.live) return ""
  var down = String(game.downDistance || "")
  var ball = String(game.ball || "")
  if (!down && !ball) return ""
  if (down && ball) return down + " at " + ball
  return down || ball
}

// Built from the day and kickoff fields rather than from `time`, because
// `time` already carries the day and prefixing it again doubled it.
function kickoffLine(game) {
  if (!game) return ""
  if (game.finished) return "FINAL"
  if (game.live) return String(game.time || "LIVE")
  var day = String(game.day || "")
  var kickoff = String(game.kickoff || "")
  if (!day || day === "TODAY") return kickoff
  if (kickoff) return day + " " + kickoff
  return day
}

// Where the club sits. The seed is what fans argue about, so it leads; the
// record is the fallback when the standings call is the one that failed.
function standingLine(team) {
  if (!team) return ""
  var seed = Number(team.seed)
  var rank = Number(team.conferenceRank)
  var place = ""
  if (isFinite(seed) && seed > 0) place = "#" + Math.round(seed)
  else if (isFinite(rank) && rank > 0) place = String(Math.round(rank)) + (String(team.conference || "") ? " " + String(team.conference) : "")
  var record = String(team.record || "")
  if (place && record) return place + " · " + record
  return place || record
}

function differential(value) {
  var number = Number(value)
  if (!isFinite(number) || number === 0) return "0"
  return (number > 0 ? "+" : "−") + String(Math.abs(Math.round(number)))
}

function streakLine(team) {
  if (!team) return ""
  return String(team.streak || "")
}

function teamLine(team) {
  if (!team) return ""
  var city = String(team.city || "")
  var nickname = String(team.nickname || team.name || "")
  var full = (city ? city + " " : "") + nickname
  if (full) return full.toUpperCase()
  return String(team.abbr || "").toUpperCase()
}

function opponentLine(game, favoriteAbbr) {
  if (!game) return ""
  var away = game.away || {}
  var home = game.home || {}
  var mine = String(game.favorite || "")
  var at = mine ? mine : String(favoriteAbbr || "")
  var venue = at === "away" ? "@ " : at === "home" ? "vs " : ""
  var other = at === "away" ? home : (at === "home" ? away : away)
  var name = (other.city ? String(other.city) + " " : "") + String(other.nickname || other.name || other.abbr || "")
  return venue + name.toUpperCase()
}

// One slate row: ticker, score, at, ticker, score. Kept terse on purpose,
// because the board shows up to eight of these.
function boardLine(game) {
  if (!game) return ""
  var away = game.away || {}
  var home = game.home || {}
  return teamAbbr(away) + " " + sideScore(away) + "  @  " + teamAbbr(home) + " " + sideScore(home)
}

function boardState(game) {
  if (!game) return ""
  if (game.live) return String(game.time || "LIVE")
  if (game.finished) return "FINAL"
  return String(game.time || game.kickoff || "")
}

function isFavorite(game, abbr) {
  if (!game) return false
  if (String(game.favorite || "")) return true
  var away = game.away || {}
  var home = game.home || {}
  return (teamAbbr(away) === String(abbr || "") || teamAbbr(home) === String(abbr || ""))
}

function isNeutral(game) {
  if (!game) return false
  return !!game.neutral
}

// The tile is square-ish and the layout has to survive a small one, so two
// thresholds decide how much of the drive line is drawn.
function compact(height) {
  return Number(height) < 230
}

function roomy(height) {
  return Number(height) >= 270
}

function heroSize(width, height) {
  var w = Number(width)
  var h = Number(height)
  // The floor matches the one below, so an unmeasured tile is never smaller
  // than a small one.
  if (!isFinite(w) || !isFinite(h) || w < 1 || h < 1) return 26
  return Math.max(26, Math.round(Math.min(w * 0.19, h * 0.2)))
}

function lastPlay(game) {
  if (!game || !game.live) return ""
  return String(game.lastPlay || "").replace(/\s+/g, " ").trim()
}

// The tile says something honest in each gap. Before the first fetch it is
// still fetching, which is not the same as there being no games.
function emptyHeadline(mode, error, loaded) {
  if (error) return "Scores unavailable"
  if (loaded === false) return "NFL"
  if (mode === "closed") return "Season complete"
  if (mode === "upcoming") return "No game found"
  return "NFL"
}

function emptyBody(mode, error, loaded) {
  if (error) return "Check the network, then try again."
  if (loaded === false) return "Fetching the schedule…"
  if (mode === "closed") return "Nothing left on the schedule."
  if (mode === "upcoming") return "Choose a club in settings."
  return "Nothing is scheduled right now."
}

function byKickoff(left, right) {
  var a = String((left && left.date) || "")
  var b = String((right && right.date) || "")
  if (a === b) return 0
  return a < b ? -1 : 1
}

if (typeof module !== "undefined") {
  module.exports = {
    boardLine: boardLine,
    boardState: boardState,
    byKickoff: byKickoff,
    compact: compact,
    differential: differential,
    emptyBody: emptyBody,
    emptyHeadline: emptyHeadline,
    hasBall: hasBall,
    heroSize: heroSize,
    isFavorite: isFavorite,
    isLeader: isLeader,
    isNeutral: isNeutral,
    kickoffLine: kickoffLine,
    lastPlay: lastPlay,
    opponentLine: opponentLine,
    roomy: roomy,
    sideScore: sideScore,
    situationLine: situationLine,
    standingLine: standingLine,
    streakLine: streakLine,
    teamAbbr: teamAbbr,
    teamLine: teamLine
  }
}
