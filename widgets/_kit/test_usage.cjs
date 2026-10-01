#!/usr/bin/env node
// Tests for the shared usage-meter helpers. Stdlib only.
//
// Run from the repo root:  node --test widgets/_kit/test_usage.cjs

// Pin the calendar before any Date is made, so the day labels read the same
// on every machine.
process.env.TZ = "America/Chicago";

const test = require("node:test");
const assert = require("node:assert/strict");
const Usage = require("./usage.js");

// 2026-09-28 12:38 in Chicago (17:38 UTC), a Monday.
const NOW = Date.UTC(2026, 8, 28, 17, 38);
const HOUR = 3600 * 1000;
const DAY = 24 * HOUR;

test("counts down in the tile's compact form", () => {
  assert.equal(Usage.countdown(0), "now");
  assert.equal(Usage.countdown(-5), "now");
  assert.equal(Usage.countdown(null), "now");
  assert.equal(Usage.countdown(45), "45s");
  assert.equal(Usage.countdown(90), "1m");
  assert.equal(Usage.countdown(600), "10m");
  assert.equal(Usage.countdown(3600), "1h");
  assert.equal(Usage.countdown(3600 + 4 * 60), "1h 04m");
  assert.equal(Usage.countdown(86400), "1d");
  assert.equal(Usage.countdown(86400 + 9 * 3600 + 1800), "1d 09h");
  assert.equal(Usage.countdown(27 * 86400 + 19 * 3600), "27d 19h");
});

test("names a reset by this machine's calendar", () => {
  assert.equal(Usage.dayLabel(NOW + 4 * HOUR + 4 * 60 * 1000, NOW), "today 4:42 pm");
  assert.equal(Usage.dayLabel(Date.UTC(2026, 8, 29, 6, 0), NOW), "tomorrow 1 am");
  // Sunday 19:00 in Chicago is Monday 00:00 UTC: the viewer's day wins.
  assert.equal(Usage.dayLabel(Date.UTC(2026, 9, 5, 0, 0), NOW), "Sun 7 pm");
  assert.equal(Usage.dayLabel(Date.UTC(2026, 9, 26, 2, 39), NOW), "Oct 25");
  assert.equal(Usage.dayLabel(null, NOW), "");
  assert.equal(Usage.dayLabel(NOW, null), "");
});

test("writes the reset line both ways", () => {
  const at = NOW + 2 * HOUR + 14 * 60 * 1000;
  assert.equal(Usage.resetLine(at, NOW, "relative"), "resets in 2h 14m");
  assert.equal(Usage.resetLine(at, NOW), "resets in 2h 14m");
  assert.equal(Usage.resetLine(at, NOW, "absolute"), "resets today 2:52 pm");
  assert.equal(Usage.resetLine(NOW - 1000, NOW, "relative"), "resetting");
  assert.equal(Usage.resetLine(null, NOW, "relative"), "");
  // A tile that keeps ticking counts down without a new reply.
  assert.equal(Usage.resetLine(at, NOW + HOUR, "relative"), "resets in 1h 14m");
});

test("reads percentages without inventing them", () => {
  assert.equal(Usage.percentText(12.4), "12%");
  assert.equal(Usage.percentText(108.3), "108%");
  assert.equal(Usage.percentText(-3), "0%");
  assert.equal(Usage.percentText(null), "—");
  assert.equal(Usage.percentText(""), "—");
  assert.equal(Usage.percentText(undefined), "—");
  assert.equal(Usage.fill(50), 0.5);
  assert.equal(Usage.fill(130), 1);
  assert.equal(Usage.fill(null), 0);
  assert.equal(Usage.fill(-1), 0);
});

test("warms the tone as a block fills", () => {
  assert.equal(Usage.tone(10), "calm");
  assert.equal(Usage.tone(50), "warm");
  assert.equal(Usage.tone(80), "urgent");
  assert.equal(Usage.tone(20, true), "urgent");
  assert.equal(Usage.tone(null), "muted");
  assert.equal(Usage.toneFraction("urgent"), 1);
  assert.equal(Usage.toneFraction("calm"), 0);
  assert.equal(Usage.toneFraction("muted"), 0.15);
});

test("finds the block closest to its ceiling", () => {
  assert.equal(Usage.worstIndex([{ percent: 10 }, { percent: 70 }, { percent: 30 }]), 1);
  assert.equal(Usage.worstIndex([{ percent: null }, { percent: 0 }]), 1);
  assert.equal(Usage.worstIndex([{ percent: null }]), -1);
  assert.equal(Usage.worstIndex([]), -1);
  assert.equal(Usage.worstIndex(null), -1);
});

test("hides the blocks the settings name", () => {
  const meters = [{ id: "a" }, { id: "b" }, { id: "c" }];
  assert.deepEqual(Usage.visibleMeters(meters, "b").map((m) => m.id), ["a", "c"]);
  assert.deepEqual(Usage.visibleMeters(meters, "a,c").map((m) => m.id), ["b"]);
  assert.deepEqual(Usage.visibleMeters(meters, "").map((m) => m.id), ["a", "b", "c"]);
  assert.deepEqual(Usage.visibleMeters({ length: 1, 0: { id: "a" } }, "x").map((m) => m.id), ["a"]);
});

test("says how old a reply is", () => {
  assert.equal(Usage.ageLine(NOW - 30 * 1000, NOW), "updated just now");
  assert.equal(Usage.ageLine(NOW - 12 * 60 * 1000, NOW), "updated 12m ago");
  assert.equal(Usage.ageLine(NOW - 3 * HOUR - 20 * 60 * 1000, NOW), "updated 3h ago");
  assert.equal(Usage.ageLine(NOW - 2 * DAY, NOW), "updated 2d ago");
  assert.equal(Usage.ageLine(0, NOW), "");
});
