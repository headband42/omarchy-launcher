#!/usr/bin/env node
// Logic tests for the MLB standings switcher. Stdlib only.
//
// The league/table resolvers are plain JS shipped inside Widget.qml, so this
// file executes that exact code against a fake root object instead of a copy.
//
// Run from the repo root:  node --test widgets/mlb/test_standings.cjs

const { describe, it } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const path = require("path");

const SRC = fs.readFileSync(path.join(__dirname, "Widget.qml"), "utf8");
const CODE = SRC.slice(SRC.indexOf("  function standLeagues()"),
                       SRC.indexOf("  function scriptPath(name)"));

// Functions call each other as root.standLeagues() in QML scope, so they
// are attached to the stub like the QML root object carries them.
const load = (stub) => Object.assign(stub, new Function(
  "root", `${CODE}; return {standLeagues, standDefaults, standLeagueObj, standTableObj};`)(
  stub));

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

const fns = (over = {}) => load({ standings: standings(), standLeague: "", standTable: undefined, ...over });

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
});
