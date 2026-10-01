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

if (typeof module !== "undefined") {
  module.exports = {
    standingsUrl: standingsUrl, nextGameUrl: nextGameUrl, leagues: leagues,
    defaults: defaults, leagueObj: leagueObj, tableObj: tableObj
  }
}
