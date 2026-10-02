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
