#!/usr/bin/env node
// Logic tests for the toggles widget. Stdlib only.
//
// Run from the repo root:  node --test widgets/toggles/test_logic.cjs

const test = require("node:test");
const assert = require("node:assert/strict");
const { ROWS, rowsFromSettings, settingsFromRows } = require("./toggles.js");

test("defaults to every row", () => {
  assert.deepEqual(rowsFromSettings({}).map((r) => r.id), ["nightlight", "stayAwake", "dnd"]);
  assert.deepEqual(rowsFromSettings(null).map((r) => r.id), ["nightlight", "stayAwake", "dnd"]);
  assert.deepEqual(rowsFromSettings({ rows: null }).map((r) => r.id), ["nightlight", "stayAwake", "dnd"]);
});

test("keeps catalog order for a picked subset", () => {
  assert.deepEqual(rowsFromSettings({ rows: ["dnd", "nightlight"] }).map((r) => r.id), ["nightlight", "dnd"]);
  assert.deepEqual(rowsFromSettings({ rows: ["stayAwake"] }).map((r) => r.id), ["stayAwake"]);
  assert.deepEqual(rowsFromSettings({ rows: [] }).map((r) => r.id), []);
  assert.deepEqual(rowsFromSettings({ rows: ["bogus"] }).map((r) => r.id), []);
});

test("forgets settings when every row is shown", () => {
  assert.deepEqual(settingsFromRows(["nightlight", "stayAwake", "dnd"]), {});
  assert.deepEqual(settingsFromRows(["dnd", "nightlight", "stayAwake", "dnd"]), {});
});

test("stores a subset in catalog order", () => {
  assert.deepEqual(settingsFromRows(["dnd", "nightlight"]), { rows: ["nightlight", "dnd"] });
  assert.deepEqual(settingsFromRows([]), { rows: [] });
});

test("round-trips a subset", () => {
  const settings = settingsFromRows(["stayAwake"]);
  assert.deepEqual(rowsFromSettings(settings).map((r) => r.id), ["stayAwake"]);
  assert.ok(ROWS.every((row) => row.glyph && row.command && row.label));
});
