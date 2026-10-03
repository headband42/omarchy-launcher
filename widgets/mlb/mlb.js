// Standings switcher and links for the MLB tile. QML imports this file; node
// tests require it. The widget passes in its own state, so each function is pure.

function standingsUrl() {
  return "https://www.mlb.com/standings"
}

function nextGameUrl(nextGame) {
  return String((nextGame && nextGame.gameday) || "")
}

function leagues(standings) {
  var rows = standings && standings.leagues
  return rows && rows.length ? rows : []
}

function defaults(standings) {
  var st = standings || {}
  return { league: String(st.defaultLeague || ""), table: st.defaultTable }
}

// The picked league, else the favorite club's league, else the first one.
function leagueObj(standings, leaguePick) {
  var list = leagues(standings)
  var want = leaguePick || defaults(standings).league
  for (var i = 0; i < list.length; i++) {
    if (String(list[i].id) === want) return list[i]
  }
  return list.length ? list[0] : null
}

// The picked table in that league. With no pick, the favorite club's division
// in its own league and the first table anywhere else.
function tableObj(standings, leaguePick, tablePick) {
  var league = leagueObj(standings, leaguePick)
  if (!league || !league.tables || !league.tables.length) return null
  var tables = league.tables
  var want = tablePick
  if (want === undefined || want === null || want === "") {
    var dflt = defaults(standings)
    want = String(league.id) === dflt.league ? dflt.table : tables[0].id
  }
  for (var j = 0; j < tables.length; j++) {
    if (tables[j].id === want) return tables[j]
  }
  return tables[0]
}

// The series line from longest to shortest. The board shows the first that
// fits, so a narrow card keeps the series score and drops the words around it.
function seriesLines(game) {
  if (!game || !game.series) return []
  var round = String(game.seriesRound || "")
  var number = Number(game.seriesGame) || 0
  var result = String(game.seriesResult || "")
  var out = [String(game.series)]
  function add(parts) {
    var line = parts.filter(function(part) { return part.length > 0 }).join(" · ")
    if (line && out.indexOf(line) < 0) out.push(line)
  }
  add([round + (number ? " G" + number : ""), result])
  add([number ? "G" + number : round, result])
  if (result) add([result])
  return out
}

function postseasonUrl() {
  return "https://www.mlb.com/postseason"
}

// The line score column of the inning being played, or -1. A long extra-inning
// game keeps only its latest columns, so the label is matched, not the number.
function currentColumn(game) {
  if (!game || !game.live || game.status === "Warmup") return -1
  var inning = Number(game.inning) || 0
  if (inning < 1) return -1
  var labels = game.labels || []
  for (var i = 0; i < labels.length; i++) {
    if (String(labels[i]) === String(inning)) return i
  }
  return -1
}

// True for the club behind in the game. Level or unknown is neither.
function trails(game, club) {
  if (!game || !club || (game.leader !== "away" && game.leader !== "home")) return false
  var ahead = game[game.leader]
  return !!ahead && Number(club.id) !== Number(ahead.id)
}

// "Riley Greene (L) batting" as the name and what follows it, so the name can
// be set apart. A line that does not start with the name is all name.
function roleParts(line, name) {
  var text = String(line || "")
  var who = String(name || "")
  if (who && text.indexOf(who) === 0) return { name: who, rest: text.slice(who.length).trim() }
  return { name: text, rest: "" }
}

// The words on one series card (a row of the sampler's `postseason.series`).
//   status / statusSide   the second line: the next game and its channel, or
//                         the result of a finished series and its last game
//   detail / detailSide   the third line: probable pitchers and the last game,
//                         or where the winner plays next
//   brief                 the right edge of a one-row card
//   hot                   the game is on today or under way
function seriesCard(row) {
  var out = { status: "", statusSide: "", detail: "", detailSide: "", brief: "", hot: false }
  if (!row) return out
  var next = row.next || null
  var live = row.live || null
  var last = row.last || null
  var advance = row.advance || null
  var lastText = last && last.line ? "G" + last.game + " " + last.line : ""
  if (live) {
    out.status = "G" + live.game + " · " + String(live.status || "Live")
    out.detail = String(live.line || "")
    out.detailSide = lastText
    out.brief = String(live.status || "Live")
    out.hot = true
  } else if (row.over) {
    out.status = String(row.summary || "")
    out.statusSide = lastText
    if (advance) {
      out.detail = "Next " + advance.code + " G" + advance.game + " · " + advance.when
      out.detailSide = String(advance.tv || "")
    }
    out.brief = String(row.summary || "")
  } else if (next) {
    out.status = "G" + next.game + " · " + next.when
    out.statusSide = String(next.tv || "")
    out.detail = next.pitchers ? String(next.pitchers) : "Pitchers TBD"
    out.detailSide = lastText
    out.brief = String(next.when || "")
    out.hot = !!next.today
  } else {
    out.status = String(row.summary || "")
    out.detailSide = lastText
    out.brief = String(row.summary || "")
  }
  return out
}

// "2–1" between the clubs, or "vs" before the first pitch.
function seriesScore(row) {
  if (!row) return ""
  var a = Number(row.left && row.left.wins) || 0
  var b = Number(row.right && row.right.wins) || 0
  if (a + b === 0 && !row.live) return "vs"
  return a + "–" + b
}

// One finished series on a results line: the winner, the score, the loser.
// A series still going (the board never sends one) reads leader first.
function seriesResult(row) {
  var left = (row && row.left) || {}
  var right = (row && row.right) || {}
  var flip = row && (row.winner === "right" || (!row.winner && row.leader === "right"))
  var won = flip ? right : left
  var lost = flip ? left : right
  return {
    won: won,
    lost: lost,
    score: (Number(won.wins) || 0) + "–" + (Number(lost.wins) || 0),
    decided: !!(row && row.winner)
  }
}

// How the series board fills `height` pixels.
//   cards    series cards in the current round (0 under a champion)
//   groups   series in each earlier round, newest first
//   m        sizes: gap, padV, club, clubMax, line, thin, hero, groupGap,
//            groupTitle, result
// The cards take the most lines all of them can carry: 2 (next game, then
// pitchers), 1, or 0 (one row each). Earlier rounds follow, whole or not at
// all, two results to a line. What is left grows the club line, up to clubMax.
function seriesLayout(cards, groups, height, m) {
  var avail = Math.max(0, height - (m.hero || 0))
  var gaps = cards > 1 ? (cards - 1) * m.gap : 0
  var lines = 0
  var cardH = cards > 0 ? m.thin : 0
  for (var n = 2; n >= 1 && cards > 0; n--) {
    var h = m.padV * 2 + m.club + n * m.line
    if (cards * h + gaps <= avail) {
      lines = n
      cardH = h
      break
    }
  }
  var used = cards > 0 ? cards * cardH + gaps : 0
  var shown = 0
  var groupsH = 0
  var list = groups || []
  for (var i = 0; i < list.length; i++) {
    var lead = used + groupsH > 0 || m.hero ? m.groupGap : 0
    var gh = lead + m.groupTitle + Math.ceil((Number(list[i]) || 0) / 2) * m.result
    if (used + groupsH + gh > avail) break
    groupsH += gh
    shown++
  }
  var club = m.club
  if (lines > 0) {
    var grow = Math.floor((avail - used - groupsH) / cards)
    grow = Math.max(0, Math.min(m.clubMax - m.club, grow))
    club += grow
    cardH += grow
  }
  return { lines: lines, cardH: cardH, club: club, groups: shown }
}

if (typeof module !== "undefined") {
  module.exports = {
    standingsUrl: standingsUrl, nextGameUrl: nextGameUrl, leagues: leagues,
    defaults: defaults, leagueObj: leagueObj, tableObj: tableObj, seriesLines: seriesLines,
    postseasonUrl: postseasonUrl, seriesCard: seriesCard, seriesScore: seriesScore,
    seriesResult: seriesResult, seriesLayout: seriesLayout, currentColumn: currentColumn,
    trails: trails, roleParts: roleParts
  }
}
