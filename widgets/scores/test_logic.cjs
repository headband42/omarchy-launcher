#!/usr/bin/env node
// Logic tests for the scores tile. Stdlib only.
//
// Run from the repo root:  node --test widgets/scores/test_logic.cjs

process.env.TZ = "America/Denver";

const test = require("node:test");
const assert = require("node:assert/strict");
const S = require("./scores.js");

const NOW = new Date(2026, 9, 2, 9, 0).getTime();
const at = (y, mo, d, h, mi = 0) => new Date(y, mo - 1, d, h, mi).getTime() / 1000;

test("start times in the viewer's zone", () => {
  assert.equal(S.startText({ start: at(2026, 10, 2, 19, 0) }, NOW, false), "7pm");
  assert.equal(S.startText({ start: at(2026, 10, 3, 19, 30) }, NOW, false), "Tmrw 7:30pm");
  assert.equal(S.startText({ start: at(2026, 10, 5, 13, 0) }, NOW, true), "Mon 13:00");
  assert.equal(S.startText({ start: at(2026, 10, 10, 5, 30) }, NOW, false), "Oct 10 5:30am");
  assert.equal(S.startText({ start: at(2026, 10, 3, 0, 0), tbd: true }, NOW, false), "Tmrw TBD");
  assert.equal(S.startText({ start: at(2026, 10, 2, 0, 0), tbd: true }, NOW, false), "Today TBD");
});

test("status by state", () => {
  assert.equal(S.statusText({ state: "in", detail: "2nd 10:21" }, NOW, false), "2nd 10:21");
  assert.equal(S.statusText({ state: "post", detail: "Final/OT" }, NOW, false), "Final/OT");
  assert.equal(S.statusText({ state: "post", detail: "" }, NOW, false), "Final");
  assert.equal(S.statusText({ state: "pre", start: at(2026, 10, 2, 19, 0) }, NOW, false), "7pm");
});

test("losers dim once it is over", () => {
  const final = { state: "post", home: { score: "2", winner: false }, away: { score: "4", winner: true } };
  assert.equal(S.dimmed(final, "home"), true);
  assert.equal(S.dimmed(final, "away"), false);
  const noFlags = { state: "post", home: { score: "1" }, away: { score: "3" } };
  assert.equal(S.dimmed(noFlags, "home"), true);
  assert.equal(S.dimmed({ state: "post", home: { score: "1" }, away: { score: "1" } }, "home"), false);
  assert.equal(S.dimmed({ state: "in", home: { score: "0", winner: false }, away: { score: "1" } }, "home"), false);
});

test("titles and notes", () => {
  assert.equal(S.title({ team: { short: "Avalanche" }, league: { name: "NHL" } }), "AVALANCHE");
  assert.equal(S.title({ team: null, league: { name: "Premier League" } }), "PREMIER LEAGUE");
  assert.equal(S.title(null), "SCORES");
  assert.equal(S.headerNote({ live: 2 }), "2 live");
  assert.equal(S.headerNote({ live: 0, team: { id: "1" }, league: { name: "NHL" } }), "NHL");
  assert.equal(S.headerNote({ live: 0, team: null, league: { name: "NHL" } }), "");
});

test("logos follow the theme", () => {
  const side = { logo: "/c/17.png", logoDark: "/c/17-dark.png" };
  assert.equal(S.logoFor(side, true), "file:///c/17-dark.png");
  assert.equal(S.logoFor(side, false), "file:///c/17.png");
  assert.equal(S.logoFor({ logo: "/c/19.png", logoDark: "" }, true), "file:///c/19.png");
  assert.equal(S.logoFor({}, true), "");
  assert.equal(S.isDark(0.06, 0.07, 0.08), true);
  assert.equal(S.isDark(0.95, 0.95, 0.9), false);
});

test("settings", () => {
  assert.deepEqual(S.settingsFor("nhl", ""), { league: "nhl" });
  assert.deepEqual(S.settingsFor("nhl", "17"), { league: "nhl", team: "17" });
  assert.equal(S.leagueOf({}, "nba"), "nba");
  assert.equal(S.leagueOf({ league: "epl" }, "nba"), "epl");
  assert.equal(S.teamOf({ team: 17 }), "17");
  const teams = [{ name: "Colorado Avalanche", abbr: "COL" }, { name: "Columbus Blue Jackets", abbr: "CBJ" }];
  assert.equal(S.filterTeams(teams, "col").length, 2);
  assert.equal(S.filterTeams(teams, "cbj").length, 1);
  assert.equal(S.filterTeams(teams, "").length, 2);
});
