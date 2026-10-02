#!/usr/bin/env node
// Logic tests for the fantasy tile: league links, the stored settings, and
// the lines the tile draws. Stdlib only.
//
// Run from the repo root:  node --test widgets/fantasy/test_logic.cjs

const test = require("node:test");
const assert = require("node:assert/strict");
const Fantasy = require("./fantasy.js");

test("reads a league from what each platform's address bar shows", () => {
  const cases = [
    ["sleeper", "https://sleeper.com/leagues/1403186749361901568/matchup", { id: "1403186749361901568" }],
    ["sleeper", "1403186749361901568", { id: "1403186749361901568" }],
    ["sleeper", "@Gridiron_Gods", { user: "Gridiron_Gods" }],
    ["espn", "https://fantasy.espn.com/football/team?leagueId=1446375&teamId=4&seasonId=2026", { id: "1446375", team: "4" }],
    ["espn", "https://fantasy.espn.com/football/league?leagueId=1446375", { id: "1446375" }],
    ["espn", " 1446375 ", { id: "1446375" }],
    ["fleaflicker", "https://www.fleaflicker.com/nfl/leagues/349505/teams/1798697", { id: "349505", team: "1798697" }],
    ["fleaflicker", "https://www.fleaflicker.com/nfl/leagues/349505", { id: "349505" }],
    ["mfl", "https://www48.myfantasyleague.com/2026/home/10005#0", { id: "10005", season: 2026 }],
    ["mfl", "https://www48.myfantasyleague.com/2025/options?L=10005&O=07&F=0003", { id: "10005", team: "0003", season: 2025 }],
    ["mfl", "10005", { id: "10005" }],
    ["fantrax", "https://www.fantrax.com/fantasy/league/W9DCE4PFJ19MXF1U/team/roster;teamId=3IWHM8MBJ19MXF2O", { id: "w9dce4pfj19mxf1u", team: "3iwhm8mbj19mxf2o" }],
    ["fantrax", "https://www.fantrax.com/newui/fantasy/leagueRulesSummary.go?leagueId=w9dce4pfj19mxf1u", { id: "w9dce4pfj19mxf1u" }],
  ];
  for (const [platform, text, expected] of cases) {
    assert.deepEqual(Fantasy.parseLeagueInput(platform, text), expected, platform + " " + text);
  }
});

test("refuses what is not a league", () => {
  for (const [platform, text] of [
    ["espn", "https://fantasy.espn.com/football/"],
    ["espn", "abc"],
    ["sleeper", "two words"],
    ["fleaflicker", "https://example.com/nfl/leagues/x"],
    ["fantrax", "no"],
    ["yahoo", "anything"],
    ["cbs", "123"],
    ["espn", ""],
  ]) {
    assert.equal(Fantasy.parseLeagueInput(platform, text), null, platform + " " + text);
  }
});

test("keeps only stored leagues fantasy.py would accept", () => {
  assert.deepEqual(Fantasy.cleanLeague({ p: "espn", id: "222", team: "1", name: "Office", teamName: "Mine", extra: 1 }),
    { p: "espn", id: "222", team: "1", name: "Office", teamName: "Mine" });
  assert.equal(Fantasy.cleanLeague({ p: "espn", id: "222", team: "1", auth: true }).auth, true);
  assert.equal(Fantasy.cleanLeague({ p: "espn", id: "222", team: "1", auth: "yes" }).auth, undefined);
  assert.equal(Fantasy.cleanLeague({ p: "yahoo", id: "461.l.1", team: "1" }).auth, true);
  assert.deepEqual(Fantasy.cleanLeague({ p: "fantrax", id: "ABCD1234", team: "Z9Y8X7W6" }),
    { p: "fantrax", id: "abcd1234", team: "z9y8x7w6" });
  assert.equal(Fantasy.cleanLeague({ p: "sleeper", id: "111", team: "1", user: "900" }).user, "900");
  assert.equal(Fantasy.cleanLeague({ p: "espn", id: "222&x=1", team: "1" }), null);
  assert.equal(Fantasy.cleanLeague({ p: "mfl", id: "10005", team: "1" }), null);
  assert.equal(Fantasy.cleanLeague({ p: "cbs", id: "1", team: "1" }), null);
  assert.equal(Fantasy.cleanLeague(null), null);
});

test("adds, replaces, caps and removes leagues", () => {
  let settings = {};
  settings = Fantasy.addLeague(settings, { p: "espn", id: "222", team: "1", name: "Office" });
  settings = Fantasy.addLeague(settings, { p: "sleeper", id: "111", team: "2" });
  assert.equal(settings.leagues.length, 2);
  // The same league with a different team replaces the old row in place.
  settings = Fantasy.addLeague(settings, { p: "espn", id: "222", team: "5", name: "Office" });
  assert.deepEqual(settings.leagues.map((l) => l.team), ["5", "2"]);
  assert.ok(Fantasy.hasLeague(settings, "espn", "222"));
  for (let i = 0; i < 10; i++) settings = Fantasy.addLeague(settings, { p: "fleaflicker", id: String(100 + i), team: "1" });
  assert.equal(settings.leagues.length, Fantasy.MAX_LEAGUES);
  settings = Fantasy.addLeague(settings, { p: "espn", id: "nope", team: "1" });
  assert.equal(settings.leagues.length, Fantasy.MAX_LEAGUES);
  settings = Fantasy.removeLeague(settings, 0);
  assert.equal(settings.leagues[0].p, "sleeper");
  let empty = Fantasy.removeLeague({ leagues: [{ p: "espn", id: "1", team: "1" }] }, 0);
  assert.deepEqual(empty, {});
});

test("forgets a sign-in only with the last league that used it", () => {
  const settings = { leagues: [
    { p: "espn", id: "222", team: "1", auth: true },
    { p: "yahoo", id: "461.l.1", team: "1" },
    { p: "yahoo", id: "461.l.2", team: "3" },
    { p: "sleeper", id: "111", team: "1" },
    { p: "mfl", id: "10005", team: "0001", auth: true },
    { p: "espn", id: "333", team: "1" },
  ] };
  assert.equal(Fantasy.forgetKey(settings, 0), "espn:222");
  assert.equal(Fantasy.forgetKey(settings, 1), "");
  assert.equal(Fantasy.forgetKey({ leagues: [settings.leagues[2]] }, 0), "yahoo");
  assert.equal(Fantasy.forgetKey(settings, 3), "");
  assert.equal(Fantasy.forgetKey(settings, 4), "mfl:10005");
  // A public league never had a sign-in to forget.
  assert.equal(Fantasy.forgetKey(settings, 5), "");
  assert.equal(Fantasy.forgetKey(settings, 9), "");
});

test("the poll request leaves the names out", () => {
  const settings = { leagues: [{ p: "sleeper", id: "111", team: "1", user: "900", name: "A", teamName: "B" }] };
  assert.equal(Fantasy.requestArg(settings), '[{"p":"sleeper","id":"111","team":"1","user":"900"}]');
  assert.equal(Fantasy.requestArg({}), "");
  const cached = JSON.stringify({ ok: true, request: Fantasy.requestArg(settings), leagues: [] });
  assert.ok(Fantasy.fromCache(cached, Fantasy.requestArg(settings)));
  assert.equal(Fantasy.fromCache(cached, "[]"), null);
  assert.equal(Fantasy.fromCache("{", "x"), null);
});

test("builds the Yahoo sign-in link and checks league links", () => {
  assert.equal(Fantasy.yahooAuthUrl("abc+/="),
    "https://api.login.yahoo.com/oauth2/request_auth?client_id=abc%2B%2F%3D&redirect_uri=oob&response_type=code&language=en-us");
  assert.equal(Fantasy.yahooAuthUrl("has space"), "");
  assert.equal(Fantasy.yahooAuthUrl(""), "");
  assert.equal(Fantasy.safeUrl("https://sleeper.com/leagues/1/matchup"), "https://sleeper.com/leagues/1/matchup");
  assert.equal(Fantasy.safeUrl("https://sleeper.com.evil/x"), "");
  assert.equal(Fantasy.safeUrl("javascript:alert(1)"), "");
});

test("scores read short", () => {
  assert.equal(Fantasy.formatScore(112.4), "112.4");
  assert.equal(Fantasy.formatScore(98.06), "98.06");
  assert.equal(Fantasy.formatScore(100), "100");
  assert.equal(Fantasy.formatScore(0), "0");
  assert.equal(Fantasy.formatScore(1000.5), "1000.5");
  assert.equal(Fantasy.formatScore(null), "–");
  assert.equal(Fantasy.ordinal(1), "1st");
  assert.equal(Fantasy.ordinal(2), "2nd");
  assert.equal(Fantasy.ordinal(3), "3rd");
  assert.equal(Fantasy.ordinal(11), "11th");
  assert.equal(Fantasy.ordinal(12), "12th");
  assert.equal(Fantasy.ordinal(22), "22nd");
  assert.equal(Fantasy.ordinal(0), "");
});

const live = {
  ok: true, league: "Dynasty Bros", rank: 2, teams: 12, alerts: [],
  me: { name: "Gods", score: 112.4, projected: 131.2, left: 2, playing: 1, record: "3-1" },
  opp: { name: "Rivals", score: 98.06, projected: 104, left: 0, playing: 0, record: "2-2" },
};
const pregame = {
  ok: true, league: "Work", alerts: [],
  me: { name: "Gods", score: 0, projected: 101, left: 9, playing: 0, record: "1-0" },
  opp: { name: "Rivals", score: 0, projected: 110, left: 9, playing: 0 },
};

test("leans on the score once it starts, the projection before", () => {
  assert.equal(Fantasy.tone(live), "up");
  assert.equal(Fantasy.started(pregame), false);
  assert.equal(Fantasy.tone(pregame), "down");
  assert.equal(Fantasy.tone({ me: { score: 5 }, opp: { score: 5 } }), "even");
  assert.equal(Fantasy.tone({ me: { score: null }, opp: { score: null } }), "");
  assert.equal(Fantasy.tone({ me: { score: 5 } }), "");
  assert.equal(Fantasy.scorePair(live), "112.4 – 98.06");
  assert.equal(Fantasy.scorePair(pregame), "101 – 110");
  assert.equal(Fantasy.scorePair({ me: { score: null }, opp: { name: "x", score: null } }), "");
});

test("lists alerts, worst first, and counts the sure zeros", () => {
  const alerts = [
    { kind: "empty", count: 2 }, { kind: "bye", name: "Bijan" }, { kind: "out", name: "PHI D/ST" },
    { kind: "questionable", name: "Kittle" }, { kind: "weird", name: "x" },
  ];
  assert.equal(Fantasy.alertLabel(alerts[0]), "2 empty slots");
  assert.equal(Fantasy.alertLabel({ kind: "empty" }), "Empty slot");
  assert.equal(Fantasy.alertsLine(alerts), "2 empty slots · Bijan BYE · PHI D/ST OUT · Kittle Q · +1");
  assert.equal(Fantasy.alertsLine(alerts, 2), "2 empty slots · Bijan BYE · +3");
  assert.equal(Fantasy.alertsLine([]), "");
  assert.equal(Fantasy.urgentCount(alerts), 3);
});

test("writes each line of the tile", () => {
  assert.equal(Fantasy.sideLine(live.me), "2 left · 1 playing · proj 131.2");
  assert.equal(Fantasy.sideLine(live.me, false), "2 left · 1 playing");
  assert.equal(Fantasy.sideLine(live.opp, false), "done");
  assert.equal(Fantasy.sideLine({ score: null, left: null, projected: null }), "");
  assert.equal(Fantasy.placeLine(live), "3-1 · 2nd of 12");
  assert.equal(Fantasy.placeLine({ me: { record: "0-0" } }), "0-0");
  assert.equal(Fantasy.footerLine(live), "3-1 · 2nd of 12");
  assert.equal(Fantasy.footerLine(Object.assign({}, live, { me: Object.assign({}, live.me, { win: 0.617 }) })),
    "3-1 · 2nd of 12 · 62% to win");
  assert.equal(Fantasy.rowDetail(live), "vs Rivals · 2 left · 1 playing");
  assert.equal(Fantasy.rowDetail(Object.assign({}, live, { alerts: [{ kind: "bye", name: "Bijan" }] })), "Bijan BYE");
  assert.equal(Fantasy.rowDetail({ ok: false, error: "This ESPN league is private." }), "This ESPN league is private.");
  assert.equal(Fantasy.rowDetail({ ok: true, me: {}, note: "Season over" }), "Season over");
  assert.equal(Fantasy.rowTitle(null, { p: "espn", name: "Office" }), "Office");
  assert.equal(Fantasy.rowTitle({ p: "mfl" }, null), "MyFantasyLeague");
  assert.equal(Fantasy.headerTitle({ week: 4 }), "WEEK 4");
  assert.equal(Fantasy.headerTitle({}), "FANTASY");
});

test("reads lists that crossed into QML as array-likes", () => {
  const arrayLike = { length: 2, 0: { kind: "bye", name: "A" }, 1: { kind: "out", name: "B" } };
  assert.equal(Fantasy.alertsLine(arrayLike), "A BYE · B OUT");
  assert.equal(Fantasy.urgentCount(arrayLike), 2);
  const leagues = { length: 1, 0: { p: "espn", id: "222", team: "1" } };
  assert.equal(Fantasy.leaguesFrom({ leagues }).length, 1);
  assert.deepEqual(Fantasy.toList(null), []);
});

test("every platform has a name, and only Yahoo is beta", () => {
  const ids = Fantasy.PLATFORMS.map((p) => p.id);
  assert.deepEqual(ids, ["sleeper", "espn", "fleaflicker", "mfl", "fantrax", "yahoo"]);
  assert.deepEqual(Fantasy.PLATFORMS.filter((p) => p.beta).map((p) => p.id), ["yahoo"]);
  assert.equal(Fantasy.platformName("fantrax"), "Fantrax");
  assert.equal(Fantasy.platform("cbs"), null);
});
