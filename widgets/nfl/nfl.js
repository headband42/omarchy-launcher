// Presentation helpers for the NFL tile.
//
// Everything here is pure: it reads a game or team object that nfl.py built
// and returns a string or a number. Widget.qml imports this file and the Node
// tests require it, so there is one copy of these rules rather than a second
// one in a test.
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

function isLeader(game, side) {
  if (!game || !side) return false
  var mine = scoreNumber(side)
  var other = scoreNumber(side === game.away ? game.home : game.away)
  if (!isFinite(mine) || !isFinite(other)) return false
  return mine > other
}

// The drive, in one line. A football tile without this is just two numbers.
function driveLine(game) {
  if (!game || !game.live) return ""
  var down = String(game.downDistance || "")
  var ball = String(game.ball || "")
  if (down && ball) return down + "  ·  " + ball
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

// The seed on its own, for a stat cell. The record lives in the cell next to
// it, so repeating it here would print it twice.
function seedLine(team) {
  if (!team) return ""
  var seed = Number(team.seed)
  if (isFinite(seed) && seed > 0) return "#" + Math.round(seed)
  var rank = Number(team.conferenceRank)
  if (isFinite(rank) && rank > 0) {
    var conf = String(team.conference || "")
    return "#" + Math.round(rank) + (conf ? " " + conf : "")
  }
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

// The club on the other side of the ball, for the hero logo. Null when the
// game names no favorite, because either side would be a guess.
function opponentSide(game) {
  if (!game) return null
  var favorite = String(game.favorite || "")
  if (favorite === "away") return game.home || null
  if (favorite === "home") return game.away || null
  return null
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

// Which week this is, for a header. The postseason has no week worth naming.
function weekLine(game) {
  if (!game) return ""
  var seasonType = Number(game.seasonType)
  if (seasonType === 1) return "PRESEASON"
  if (seasonType === 3) return "PLAYOFFS"
  var week = Number(game.week)
  if (isFinite(week) && week > 0) return "WEEK " + Math.round(week)
  return ""
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

// Where the ball sits on a strip drawn 0 to 100, always from the offence's
// own goal line: their 20 is 20 and the opponent's 20 is 80. The strip is
// drawn from the offence's perspective, so this one number is the whole
// picture and there is no mirrored second marker to misread.
function ballYard(game) {
  if (!game || !game.live) return null
  if (!String(game.possession || "")) return null
  var raw = game.yardLine
  if (raw === null || raw === undefined || raw === "") return null
  var yard = Number(raw)
  if (!isFinite(yard)) return null
  if (yard < 0) return 0
  if (yard > 100) return 100
  return yard
}

function isOffense(game, side) {
  if (!game || !side) return false
  return String(game.possession || "") === teamAbbr(side) && String(game.possession || "") !== ""
}

function hasField(game) {
  return ballYard(game) !== null
}

if (typeof module !== "undefined") {
  module.exports = {
    ballYard: ballYard,
    boardLine: boardLine,
    boardState: boardState,
    compact: compact,
    differential: differential,
    driveLine: driveLine,
    emptyBody: emptyBody,
    emptyHeadline: emptyHeadline,
    hasField: hasField,
    heroSize: heroSize,
    isLeader: isLeader,
    isOffense: isOffense,
    kickoffLine: kickoffLine,
    lastPlay: lastPlay,
    opponentLine: opponentLine,
    opponentSide: opponentSide,
    resultLine: resultLine,
    roomy: roomy,
    seedLine: seedLine,
    sideScore: sideScore,
    teamAbbr: teamAbbr,
    teamLine: teamLine,
    weekLine: weekLine
  }
}
