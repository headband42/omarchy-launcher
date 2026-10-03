#!/usr/bin/env node
// Logic tests for mlb.js: the standings switcher and the series line. Stdlib only.
//
// Run from the repo root:  node --test widgets/mlb/test_logic.cjs

const { describe, it } = require("node:test");
const assert = require("node:assert/strict");
const Mlb = require("./mlb.js");

// Widget.qml wraps mlb.js the same way: each call reads the tile's state.
const load = (root) => ({
  standingsUrl: () => Mlb.standingsUrl(),
  nextGameUrl: () => Mlb.nextGameUrl(root.nextGame),
  standLeagues: () => Mlb.leagues(root.standings),
  standDefaults: () => Mlb.defaults(root.standings),
  standLeagueObj: () => Mlb.leagueObj(root.standings, root.standLeague),
  standTableObj: () => Mlb.tableObj(root.standings, root.standLeague, root.standTable),
});

const table = (id, label, rows) => ({ id, kind: "division", label, title: label, rows });
const rows = (abbrs) => abbrs.map((abbr) => ({ abbr, record: "0-0", gb: "—" }));

const standings = () => ({
  defaultLeague: "AL",
  defaultTable: 201,
  leagues: [
    {
      id: "AL", label: "AL",
      tables: [
        table(201, "East", rows(["TB", "NYY"])),
        table(202, "Central", rows(["DET"])),
        { id: "WC", kind: "wildcard", label: "WC", title: "AL Wild Card", rows: rows(["NYY", "BOS"]) },
      ],
    },
    {
      id: "NL", label: "NL",
      tables: [
        table(204, "East", rows(["NYM"])),
        { id: "WC", kind: "wildcard", label: "WC", title: "NL Wild Card", rows: rows(["LAD"]) },
      ],
    },
  ],
});

const fns = (over = {}) => load({ standings: standings(), nextGame: null, standLeague: "", standTable: undefined, ...over });

describe("standings switcher", () => {
  it("defaults to the favorite club's division", () => {
    const f = fns();
    assert.equal(f.standLeagueObj().id, "AL");
    assert.equal(f.standTableObj().id, 201);
    assert.deepEqual(f.standTableObj().rows.map((row) => row.abbr), ["TB", "NYY"]);
  });

  it("switching league starts at that league's first table", () => {
    const f = fns({ standLeague: "NL", standTable: undefined });
    assert.equal(f.standLeagueObj().id, "NL");
    assert.equal(f.standTableObj().id, 204);
  });

  it("returns to the favorite division when coming back", () => {
    const f = fns({ standLeague: "AL", standTable: undefined });
    assert.equal(f.standTableObj().id, 201);
  });

  it("keeps an explicit table pick across leagues that have it", () => {
    const f = fns({ standLeague: "NL", standTable: "WC" });
    assert.equal(f.standTableObj().id, "WC");
    assert.equal(f.standTableObj().title, "NL Wild Card");
  });

  it("falls back to the first table for an unknown pick", () => {
    const f = fns({ standLeague: "NL", standTable: 999 });
    assert.equal(f.standTableObj().id, 204);
  });

  it("falls back to the first league for an unknown league", () => {
    const f = fns({ standLeague: "XX", standTable: undefined });
    assert.equal(f.standLeagueObj().id, "AL");
  });

  it("keeps the pick when a poll replaces the payload", () => {
    const root = { standings: standings(), standLeague: "NL", standTable: "WC" };
    const before = load(root).standTableObj().id;
    root.standings = standings();
    assert.equal(before, "WC");
    assert.equal(load(root).standTableObj().id, "WC");
  });

  it("hides the section without standings data", () => {
    const f = fns({ standings: null });
    assert.deepEqual(f.standLeagues(), []);
    assert.equal(f.standLeagueObj(), null);
    assert.equal(f.standTableObj(), null);
  });

  it("links rows to the standings page", () => {
    assert.equal(fns().standingsUrl(), "https://www.mlb.com/standings");
  });

  it("links the next block to the next game", () => {
    assert.equal(fns().nextGameUrl(), "");
    const f = fns({ nextGame: { gameday: "https://www.mlb.com/gameday/40" } });
    assert.equal(f.nextGameUrl(), "https://www.mlb.com/gameday/40");
  });
});

describe("series line", () => {
  const game = {
    series: "ALWC · Game 2 · NYY leads 1-0", seriesRound: "ALWC", seriesGame: 2, seriesResult: "NYY leads 1-0",
  };

  it("goes from the full line down to the series score", () => {
    assert.deepEqual(Mlb.seriesLines(game), [
      "ALWC · Game 2 · NYY leads 1-0",
      "ALWC G2 · NYY leads 1-0",
      "G2 · NYY leads 1-0",
      "NYY leads 1-0",
    ]);
  });

  it("game 1 has no score yet", () => {
    assert.deepEqual(Mlb.seriesLines({ series: "ALDS · Game 1", seriesRound: "ALDS", seriesGame: 1, seriesResult: "" }),
      ["ALDS · Game 1", "ALDS G1", "G1"]);
  });

  it("regular season has none", () => {
    assert.deepEqual(Mlb.seriesLines({ series: "" }), []);
    assert.deepEqual(Mlb.seriesLines(null), []);
  });
});

describe("series board", () => {
  const club = (abbr, wins) => ({ id: 1, abbr, wins });
  const upcoming = {
    left: club("NYY", 1), right: club("TB", 1), need: 3, over: false, winner: "", leader: "",
    summary: "Series tied 1-1",
    next: { game: 3, when: "Today 4:08 PM", today: true, tv: "TBS", pitchers: "Rodón vs Rasmussen" },
    last: { game: 2, line: "NYY 5-3" },
  };

  it("an open series shows the next game, its channel, the pitchers, and the last result", () => {
    assert.deepEqual(Mlb.seriesCard(upcoming), {
      status: "G3 · Today 4:08 PM", statusSide: "TBS",
      detail: "Rodón vs Rasmussen", detailSide: "G2 NYY 5-3",
      brief: "Today 4:08 PM", hot: true,
    });
  });

  it("says when no starter is named yet", () => {
    const row = { ...upcoming, next: { ...upcoming.next, pitchers: "", today: false }, last: null };
    const card = Mlb.seriesCard(row);
    assert.equal(card.detail, "Pitchers TBD");
    assert.equal(card.detailSide, "");
    assert.equal(card.hot, false);
  });

  it("a finished series shows the result and where the winner plays next", () => {
    const row = {
      left: club("CWS", 3), right: club("CLE", 0), need: 3, over: true, winner: "left", leader: "left",
      summary: "CWS wins 3-0", next: null, last: { game: 3, line: "CWS 4-0" },
      advance: { code: "ALCS", game: 1, when: "Sun 6:08 PM", tv: "TBS" },
    };
    const card = Mlb.seriesCard(row);
    assert.equal(card.status, "CWS wins 3-0");
    assert.equal(card.statusSide, "G3 CWS 4-0");
    assert.equal(card.detail, "Next ALCS G1 · Sun 6:08 PM");
    assert.equal(card.detailSide, "TBS");
    assert.equal(card.hot, false);
  });

  it("a game under way is hot and shows its score", () => {
    const row = { ...upcoming, next: null, live: { game: 3, status: "Top 6", line: "NYY 2-1" } };
    const card = Mlb.seriesCard(row);
    assert.equal(card.status, "G3 · Top 6");
    assert.equal(card.detail, "NYY 2-1");
    assert.equal(card.brief, "Top 6");
    assert.equal(card.hot, true);
  });

  it("series score reads vs before the first pitch", () => {
    assert.equal(Mlb.seriesScore({ left: club("SD", 0), right: club("MIL", 0) }), "vs");
    assert.equal(Mlb.seriesScore({ left: club("SD", 2), right: club("MIL", 1) }), "2–1");
    assert.equal(Mlb.seriesScore(null), "");
  });

  it("a result line puts the winner first", () => {
    const parts = Mlb.seriesResult({ left: club("BOS", 0), right: club("NYY", 2), winner: "right" });
    assert.equal(parts.won.abbr, "NYY");
    assert.equal(parts.lost.abbr, "BOS");
    assert.equal(parts.score, "2–0");
    assert.equal(parts.decided, true);
  });

  const sizes = { gap: 4, padV: 5, club: 22, clubMax: 28, line: 14, thin: 22, hero: 0, groupGap: 6, groupTitle: 14, result: 15 };

  it("four cards on a 270 px board carry both lines and grow into the rest", () => {
    // 4 × (10 + 22 + 28) + 3 × 4 = 252; 18 px over, 4 each.
    assert.deepEqual(Mlb.seriesLayout(4, [4], 270, sizes), { lines: 2, cardH: 64, club: 26, groups: 0 });
  });

  it("earlier rounds go under the cards before the cards grow", () => {
    // 252 + (6 + 14 + 2 × 15) = 302.
    assert.deepEqual(Mlb.seriesLayout(4, [4, 4], 310, sizes), { lines: 2, cardH: 62, club: 24, groups: 1 });
  });

  it("a short board drops the third line, then the second", () => {
    assert.equal(Mlb.seriesLayout(4, [], 220, sizes).lines, 1);
    // One-row cards: 4 × 22 + 3 × 4 = 100, and the round under them 50.
    const thin = Mlb.seriesLayout(4, [4], 150, sizes);
    assert.equal(thin.lines, 0);
    assert.equal(thin.cardH, 22);
    assert.equal(thin.groups, 1);
  });

  it("the champion takes its block first, then the rounds that fit", () => {
    const plan = Mlb.seriesLayout(0, [2, 4, 4], 200, { ...sizes, hero: 100 });
    // 100 left: 6 + 14 + 15 = 35, then 6 + 14 + 30 = 50; the third would need 50 more.
    assert.deepEqual(plan, { lines: 0, cardH: 0, club: 22, groups: 2 });
  });
});

describe("single game", () => {
  const live = (over) => ({
    live: true, status: "Top 6", inning: 6, labels: ["1", "2", "3", "4", "5", "6", "7", "8", "9"],
    away: { id: 116 }, home: { id: 136 }, leader: "away", ...over,
  });

  it("lights the column of the inning being played", () => {
    assert.equal(Mlb.currentColumn(live()), 5);
    // Eleven columns at most: the 13th is the last one shown, not the 13th slot.
    const labels = ["3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13"];
    assert.equal(Mlb.currentColumn(live({ inning: 13, labels })), 10);
  });

  it("lights nothing before the first pitch or after the last", () => {
    assert.equal(Mlb.currentColumn(live({ status: "Warmup" })), -1);
    assert.equal(Mlb.currentColumn(live({ live: false })), -1);
    assert.equal(Mlb.currentColumn(live({ inning: 0 })), -1);
    assert.equal(Mlb.currentColumn(live({ inning: 2, labels: ["3", "4"] })), -1);
    assert.equal(Mlb.currentColumn(null), -1);
  });

  it("only the club behind trails", () => {
    const game = live();
    assert.equal(Mlb.trails(game, game.home), true);
    assert.equal(Mlb.trails(game, game.away), false);
    assert.equal(Mlb.trails(live({ leader: "" }), game.home), false);
    assert.equal(Mlb.trails(game, null), false);
  });

  it("splits the name off a batter or pitcher line", () => {
    assert.deepEqual(Mlb.roleParts("Riley Greene (L) batting", "Riley Greene"), { name: "Riley Greene", rest: "(L) batting" });
    assert.deepEqual(Mlb.roleParts("Logan Gilbert pitching", "Logan Gilbert"), { name: "Logan Gilbert", rest: "pitching" });
    assert.deepEqual(Mlb.roleParts("Someone batting", "Other"), { name: "Someone batting", rest: "" });
    assert.deepEqual(Mlb.roleParts("", ""), { name: "", rest: "" });
  });
});
