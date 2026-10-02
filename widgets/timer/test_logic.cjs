#!/usr/bin/env node
// Logic tests for the timer tile. Stdlib only.
//
// Run from the repo root:  node --test widgets/timer/test_logic.cjs

const test = require("node:test");
const assert = require("node:assert/strict");
const T = require("./timer.js");

test("presets default, filter, sort, and cap", () => {
  assert.deepEqual(T.presets({}), T.DEFAULTS);
  assert.deepEqual(T.presets(null), T.DEFAULTS);
  assert.deepEqual(T.presets({ presets: [25, 3, 7, "10"] }), [3, 10, 25]);
  assert.deepEqual(T.presets({ presets: [1, 2, 3, 5, 10] }), [1, 2, 3, 5]);
  assert.deepEqual(T.presets({ presets: [] }), T.DEFAULTS);
});

test("toggling presets", () => {
  assert.deepEqual(T.togglePreset({}, 5), { presets: [15, 25, 60] });
  assert.deepEqual(T.togglePreset({ presets: [15, 25, 60] }, 5), {}, "back to the defaults is stored as {}");
  assert.deepEqual(T.togglePreset({}, 10), {}, "full: no change");
  assert.deepEqual(T.togglePreset({ presets: [10] }, 10), { presets: [10] }, "keeps one");
  assert.deepEqual(T.togglePreset({ presets: [10] }, 7), { presets: [10] }, "unknown length");
  assert.deepEqual(T.togglePreset({ presets: [30, 10] }, 20), { presets: [10, 20, 30] });
});

test("preset labels", () => {
  assert.equal(T.fmtPreset(5), "5m");
  assert.equal(T.fmtPreset(60), "1h");
  assert.equal(T.fmtPreset(90), "1h30");
  assert.equal(T.fmtPreset(120), "2h");
  assert.equal(T.fmtPreset(65), "1h05");
});

test("countdowns", () => {
  const row = { minutes: 25, started: 1000, at: 1000 + 1500 };
  assert.equal(T.remaining(row, 1600), 900);
  assert.equal(T.remaining(row, 5000), 0);
  assert.equal(T.fmtCountdown(900), "15:00");
  assert.equal(T.fmtCountdown(59), "0:59");
  assert.equal(T.fmtCountdown(3725), "1:02:05");
  assert.equal(T.elapsed(row, 1600), 0.4);
  assert.equal(T.elapsed(row, 0), 0);
  assert.equal(T.elapsed(row, 99999), 1);
  assert.equal(T.elapsed({ minutes: 0, started: 1 }, 5), 0);
});

test("labels and the live list", () => {
  assert.equal(T.label({ minutes: 25, message: "" }), "25m timer");
  assert.equal(T.label({ minutes: 25, message: " Tea " }), "Tea");
  const rows = [{ at: 10 }, { at: 20 }];
  assert.deepEqual(T.live(rows, 15), [{ at: 20 }]);
  assert.deepEqual(T.live(null, 15), []);
});
