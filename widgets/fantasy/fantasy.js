// Fantasy football tile logic: the settings shape, league links, and the
// lines the tile draws. Widget.qml and Settings.qml import it; node tests
// require it.

var MAX_LEAGUES = 6

// The order the settings panel lists them. `beta` platforms need a sign-in
// that has not been tried against a real account yet.
var PLATFORMS = [
  { id: "sleeper", name: "Sleeper", beta: false,
    note: "Your username finds every league",
    detail: "Type your Sleeper username to see every league you're in this season, or paste one league's link to pick any team in it.",
    placeholder: "Username, or a sleeper.com/leagues/… link" },
  { id: "espn", name: "ESPN", beta: false,
    note: "Public leagues. Private ones need cookies (beta)",
    detail: "Paste the league's link from fantasy.espn.com, or its leagueId number. A link to a team page picks that team for you.",
    placeholder: "League link, or the leagueId number" },
  { id: "fleaflicker", name: "Fleaflicker", beta: false,
    note: "Any league link or ID",
    detail: "Paste the league's link from fleaflicker.com, or its number. A link to a team page picks that team for you.",
    placeholder: "fleaflicker.com/nfl/leagues/… link, or the ID" },
  { id: "mfl", name: "MyFantasyLeague", beta: false,
    note: "Public leagues. Private ones need an API key (beta)",
    detail: "Paste the league's link from myfantasyleague.com, or its league number.",
    placeholder: "League link, or the league number" },
  { id: "fantrax", name: "Fantrax", beta: false,
    note: "Standings and opponent only, no scores",
    detail: "Paste the league's link from fantrax.com, or its ID. Fantrax's public data has the schedule and standings but no scores, so the tile shows your opponent and record.",
    placeholder: "fantrax.com/fantasy/league/… link, or the ID" },
  { id: "yahoo", name: "Yahoo", beta: true,
    note: "Sign in with your own Yahoo app",
    detail: "",
    placeholder: "" }
]

// The ids fantasy.py accepts. It checks them again before building a URL.
var ID_PATTERNS = {
  sleeper: [/^\d{1,24}$/, /^\d{1,4}$/],
  espn: [/^\d{1,12}$/, /^\d{1,4}$/],
  fleaflicker: [/^\d{1,12}$/, /^\d{1,12}$/],
  mfl: [/^\d{1,8}$/, /^\d{4}$/],
  fantrax: [/^[a-z0-9]{4,32}$/, /^[a-z0-9]{4,32}$/],
  yahoo: [/^\d{1,6}\.l\.\d{1,12}$/, /^\d{1,4}$/]
}

var YAHOO_AUTHORIZE = "https://api.login.yahoo.com/oauth2/request_auth"

// Where a league link may send a click. Menu.qml checks the same prefixes.
var URL_PREFIXES = [
  "https://sleeper.com/",
  "https://fantasy.espn.com/",
  "https://www.fleaflicker.com/",
  "https://www.myfantasyleague.com/",
  "https://www.fantrax.com/",
  "https://football.fantasysports.yahoo.com/"
]

// A list that crossed a QML `var` property (a delegate's modelData, a tile's
// settings) is array-like but not an Array, so Array.isArray() would drop it.
function toList(value) {
  if (Array.isArray(value)) return value
  if (value && typeof value === "object" && typeof value.length === "number")
    return Array.prototype.slice.call(value)
  return []
}

function platform(id) {
  for (var i = 0; i < PLATFORMS.length; i++) {
    if (PLATFORMS[i].id === id) return PLATFORMS[i]
  }
  return null
}

function platformName(id) {
  var found = platform(id)
  return found ? found.name : ""
}

function match(text, re) {
  var found = re.exec(text)
  return found ? found[1] : ""
}

// What someone pasted for a platform: a link, a bare ID, or for Sleeper a
// username. Returns { id, team, season } or { user }, or null.
function parseLeagueInput(id, value) {
  var text = String(value || "").trim()
  if (!text) return null
  var out = null
  if (id === "sleeper") {
    var league = match(text, /sleeper\.(?:com|app)\/leagues\/(\d{1,24})/i)
    if (league) return { id: league }
    if (/^\d{10,24}$/.test(text)) return { id: text }
    if (/^@?[A-Za-z0-9_]{1,40}$/.test(text)) return { user: text.replace(/^@/, "") }
    return null
  }
  if (id === "espn") {
    out = { id: match(text, /[?&]leagueId=(\d{1,12})/i), team: match(text, /[?&]teamId=(\d{1,4})/i) }
    if (!out.id && /^\d{1,12}$/.test(text)) out.id = text
  } else if (id === "fleaflicker") {
    out = { id: match(text, /fleaflicker\.com\/nfl\/leagues\/(\d{1,12})/i), team: match(text, /\/teams\/(\d{1,12})/i) }
    if (!out.id && /^\d{1,12}$/.test(text)) out.id = text
  } else if (id === "mfl") {
    out = {
      id: match(text, /myfantasyleague\.com\/\d{4}\/home\/(\d{1,8})/i) || match(text, /[?&]L=(\d{1,8})/i),
      team: match(text, /[?&]F=(\d{4})/i),
      season: match(text, /myfantasyleague\.com\/(\d{4})\//i)
    }
    if (!out.id && /^\d{1,8}$/.test(text)) out.id = text
  } else if (id === "fantrax") {
    var lower = text.toLowerCase()
    out = {
      id: match(lower, /fantrax\.com\/fantasy\/league\/([a-z0-9]{4,32})/) || match(lower, /[?&;]leagueid=([a-z0-9]{4,32})/),
      team: match(lower, /[?&;]teamid=([a-z0-9]{4,32})/)
    }
    if (!out.id && /^[a-z0-9]{4,32}$/.test(lower)) out.id = lower
  } else {
    return null
  }
  if (!out.id) return null
  var result = { id: out.id }
  if (out.team) result.team = out.team
  if (out.season) result.season = Number(out.season)
  return result
}

// A stored league, with the names kept for the settings list and the tile's
// first paint. null when the ids would not pass fantasy.py.
function cleanLeague(raw) {
  if (!raw || typeof raw !== "object") return null
  var p = String(raw.p || "")
  var patterns = ID_PATTERNS[p]
  if (!patterns) return null
  var id = String(raw.id || "").trim()
  var team = String(raw.team || "").trim()
  if (p === "fantrax") {
    id = id.toLowerCase()
    team = team.toLowerCase()
  }
  if (!patterns[0].test(id) || !patterns[1].test(team)) return null
  var entry = { p: p, id: id, team: team }
  if (p === "sleeper" && /^\d{1,24}$/.test(String(raw.user || ""))) entry.user = String(raw.user)
  var name = String(raw.name || "").trim().slice(0, 60)
  var teamName = String(raw.teamName || "").trim().slice(0, 48)
  if (name) entry.name = name
  if (teamName) entry.teamName = teamName
  // Added with a cookie, an API key, or a Yahoo sign-in: shown as beta.
  if (raw.auth === true || p === "yahoo") entry.auth = true
  return entry
}

function entryKey(entry) {
  return entry ? entry.p + ":" + entry.id + ":" + entry.team : ""
}

function leaguesFrom(settings) {
  var rows = toList(settings && settings.leagues)
  var out = []
  var seen = {}
  for (var i = 0; i < rows.length && out.length < MAX_LEAGUES; i++) {
    var entry = cleanLeague(rows[i])
    if (!entry || seen[entryKey(entry)]) continue
    seen[entryKey(entry)] = true
    out.push(entry)
  }
  return out
}

// An empty list forgets the settings.
function settingsFrom(list) {
  var leagues = leaguesFrom({ leagues: list })
  return leagues.length ? { leagues: leagues } : {}
}

// The same league added again replaces its old row in place.
function addLeague(settings, raw) {
  var entry = cleanLeague(raw)
  var list = leaguesFrom(settings)
  if (!entry) return settingsFrom(list)
  for (var i = 0; i < list.length; i++) {
    if (entryKey(list[i]) === entryKey(entry) || (list[i].p === entry.p && list[i].id === entry.id)) {
      list[i] = entry
      return settingsFrom(list)
    }
  }
  if (list.length >= MAX_LEAGUES) return settingsFrom(list)
  list.push(entry)
  return settingsFrom(list)
}

function removeLeague(settings, index) {
  var list = leaguesFrom(settings)
  if (index >= 0 && index < list.length) list.splice(index, 1)
  return settingsFrom(list)
}

function hasLeague(settings, p, id) {
  var list = leaguesFrom(settings)
  for (var i = 0; i < list.length; i++) {
    if (list[i].p === p && list[i].id === String(id)) return true
  }
  return false
}

// The saved sign-in to drop when a league goes, or "" when it has none.
// Yahoo's sign-in covers every Yahoo league, so it goes with the last one.
function forgetKey(settings, index) {
  var list = leaguesFrom(settings)
  var entry = list[index]
  if (!entry) return ""
  if ((entry.p === "espn" || entry.p === "mfl") && entry.auth) {
    for (var i = 0; i < list.length; i++) {
      if (i !== index && list[i].p === entry.p && list[i].id === entry.id) return ""
    }
    return entry.p + ":" + entry.id
  }
  if (entry.p === "yahoo") {
    for (var j = 0; j < list.length; j++) {
      if (j !== index && list[j].p === "yahoo") return ""
    }
    return "yahoo"
  }
  return ""
}

// The --leagues argument. Names stay out of it so renaming a team does not
// look like a new request.
function requestArg(settings) {
  var list = leaguesFrom(settings)
  if (!list.length) return ""
  return JSON.stringify(list.map(function(entry) {
    var row = { p: entry.p, id: entry.id, team: entry.team }
    if (entry.user) row.user = entry.user
    return row
  }))
}

function fromCache(text, request) {
  var data = null
  try { data = JSON.parse(String(text || "")) } catch (e) { return null }
  if (!data || data.ok !== true || !Array.isArray(data.leagues)) return null
  if (String(data.request || "") !== String(request || "")) return null
  return data
}

function yahooAuthUrl(clientId) {
  var id = String(clientId || "").trim()
  if (!id || /\s/.test(id)) return ""
  return YAHOO_AUTHORIZE + "?client_id=" + encodeURIComponent(id)
    + "&redirect_uri=oob&response_type=code&language=en-us"
}

function safeUrl(url) {
  var value = String(url || "")
  for (var i = 0; i < URL_PREFIXES.length; i++) {
    if (value.indexOf(URL_PREFIXES[i]) === 0) return value
  }
  return ""
}

// —— What the tile draws ——

function isNumber(value) {
  return value !== null && value !== undefined && value !== "" && isFinite(Number(value))
}

// Up to two decimals, without trailing zeros: 112.4, 98.06, 0.
function formatScore(value) {
  if (!isNumber(value)) return "–"
  var text = Number(value).toFixed(2)
  return text.replace(/\.?0+$/, "")
}

function ordinal(n) {
  var value = Math.round(Number(n))
  if (!isFinite(value) || value <= 0) return ""
  var tens = value % 100
  var suffix = "th"
  if (tens < 11 || tens > 13) {
    if (value % 10 === 1) suffix = "st"
    else if (value % 10 === 2) suffix = "nd"
    else if (value % 10 === 3) suffix = "rd"
  }
  return value + suffix
}

function hasScores(league) {
  return !!(league && league.me && isNumber(league.me.score))
}

// Before kickoff the projection is the story: 0–0 says nothing.
function started(league) {
  if (!hasScores(league)) return false
  var me = league.me || {}
  var opp = league.opp || {}
  return Number(me.score) !== 0 || Number(opp.score || 0) !== 0
    || Number(me.playing || 0) > 0 || Number(opp.playing || 0) > 0
}

// Which way the matchup leans: up, down, even, or "" with nothing to compare.
function tone(league) {
  if (!league || !league.me || !league.opp) return ""
  var a, b
  if (started(league)) {
    a = Number(league.me.score)
    b = Number(league.opp.score)
  } else if (isNumber(league.me.projected) && isNumber(league.opp.projected)) {
    a = Number(league.me.projected)
    b = Number(league.opp.projected)
  } else {
    return ""
  }
  if (Math.abs(a - b) < 0.005) return "even"
  return a > b ? "up" : "down"
}

function alertLabel(alert) {
  if (!alert) return ""
  var kind = String(alert.kind || "")
  var name = String(alert.name || "")
  if (kind === "empty") {
    var count = Number(alert.count) || 1
    return count === 1 ? "Empty slot" : count + " empty slots"
  }
  var tag = { bye: "BYE", out: "OUT", ir: "IR", suspended: "SUSP", doubtful: "D", questionable: "Q" }[kind]
  if (!tag) return ""
  return name ? name + " " + tag : tag
}

function alertsLine(alerts, max) {
  var list = toList(alerts)
  var limit = max > 0 ? max : list.length
  var parts = []
  for (var i = 0; i < list.length && parts.length < limit; i++) {
    var label = alertLabel(list[i])
    if (label) parts.push(label)
  }
  var hidden = list.length - parts.length
  var line = parts.join(" · ")
  if (hidden > 0 && line) line += " · +" + hidden
  return line
}

// The serious ones: a starter who will score nothing for sure.
function urgentCount(alerts) {
  var list = toList(alerts)
  var n = 0
  for (var i = 0; i < list.length; i++) {
    var kind = String(list[i] && list[i].kind)
    if (kind === "empty" || kind === "bye" || kind === "out" || kind === "ir" || kind === "suspended") n++
  }
  return n
}

// "2 left · 1 playing · proj 131.2", short enough for one tile line.
function sideLine(side, withProjection) {
  if (!side) return ""
  var parts = []
  if (isNumber(side.left) && Number(side.left) > 0) parts.push(side.left + " left")
  if (isNumber(side.playing) && Number(side.playing) > 0) parts.push(side.playing + " playing")
  if (withProjection !== false && isNumber(side.projected)) parts.push("proj " + formatScore(side.projected))
  if (!parts.length && isNumber(side.left) && Number(side.left) === 0 && isNumber(side.score)) parts.push("done")
  return parts.join(" · ")
}

// "3-1 · 2nd of 12"
function placeLine(league) {
  if (!league) return ""
  var parts = []
  var record = league.me && league.me.record
  if (record) parts.push(String(record))
  if (league.rank && league.teams) parts.push(ordinal(league.rank) + " of " + league.teams)
  return parts.join(" · ")
}

// Under the matchup: "3-1 · 2nd of 12 · 62% to win".
function footerLine(league) {
  if (!league) return ""
  var parts = []
  var place = placeLine(league)
  if (place) parts.push(place)
  var win = league.me && league.me.win
  if (isNumber(win) && league.opp) parts.push(Math.round(Number(win) * 100) + "% to win")
  return parts.join(" · ")
}

// The score pair for a list row: "112.4 – 98.1", or the projections before
// kickoff, or the opponent's name when the platform has no scores.
function scorePair(league) {
  if (!league || !league.me) return ""
  if (!league.opp) return hasScores(league) ? formatScore(league.me.score) : ""
  if (started(league)) return formatScore(league.me.score) + " – " + formatScore(league.opp.score)
  if (isNumber(league.me.projected) && isNumber(league.opp.projected))
    return formatScore(league.me.projected) + " – " + formatScore(league.opp.projected)
  if (hasScores(league)) return formatScore(league.me.score) + " – " + formatScore(league.opp.score)
  return ""
}

// The second line of a list row: an alert first, else who it is against.
function rowDetail(league) {
  if (!league) return ""
  if (league.ok === false) return String(league.error || "Not available")
  var alerts = alertsLine(league.alerts, 2)
  if (alerts) return alerts
  var parts = []
  if (league.opp && league.opp.name) parts.push("vs " + league.opp.name)
  else if (league.note) parts.push(String(league.note))
  var status = sideLine(league.me, false)
  if (status) parts.push(status)
  return parts.join(" · ")
}

function rowTitle(league, stored) {
  var name = league && league.league ? String(league.league) : String((stored && stored.name) || "")
  return name || platformName((league && league.p) || (stored && stored.p)) || "League"
}

function headerTitle(sample) {
  var week = sample && Number(sample.week)
  return week > 0 ? "WEEK " + week : "FANTASY"
}

if (typeof module !== "undefined") {
  module.exports = {
    MAX_LEAGUES: MAX_LEAGUES,
    toList: toList,
    PLATFORMS: PLATFORMS,
    URL_PREFIXES: URL_PREFIXES,
    platform: platform,
    platformName: platformName,
    parseLeagueInput: parseLeagueInput,
    cleanLeague: cleanLeague,
    entryKey: entryKey,
    leaguesFrom: leaguesFrom,
    settingsFrom: settingsFrom,
    addLeague: addLeague,
    removeLeague: removeLeague,
    hasLeague: hasLeague,
    forgetKey: forgetKey,
    requestArg: requestArg,
    fromCache: fromCache,
    yahooAuthUrl: yahooAuthUrl,
    safeUrl: safeUrl,
    formatScore: formatScore,
    ordinal: ordinal,
    hasScores: hasScores,
    started: started,
    tone: tone,
    alertLabel: alertLabel,
    alertsLine: alertsLine,
    urgentCount: urgentCount,
    sideLine: sideLine,
    placeLine: placeLine,
    footerLine: footerLine,
    scorePair: scorePair,
    rowDetail: rowDetail,
    rowTitle: rowTitle,
    headerTitle: headerTitle
  }
}
