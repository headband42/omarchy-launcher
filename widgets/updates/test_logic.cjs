#!/usr/bin/env node
// Logic tests for the updates widget. Stdlib only.
//
// Run from the repo root:  node --test widgets/updates/test_logic.cjs

const test = require("node:test");
const assert = require("node:assert/strict");
const { fmtAgo } = require("./updates.js");

test("formats empty timestamps", () => {
  assert.equal(fmtAgo(Date.now(), 0), "");
  assert.equal(fmtAgo(Date.now(), null), "");
  assert.equal(fmtAgo(Date.now(), undefined), "");
});

test("formats recent times", () => {
  const now = 1_700_000_000_000;
  assert.equal(fmtAgo(now, 1_700_000_000 - 5), "just now");
  assert.equal(fmtAgo(now, 1_700_000_000 - 59), "just now");
  assert.equal(fmtAgo(now, 1_700_000_000 - 60), "1m ago");
  assert.equal(fmtAgo(now, 1_700_000_000 - 59 * 60), "59m ago");
  assert.equal(fmtAgo(now, 1_700_000_000 - 60 * 60), "1h ago");
  assert.equal(fmtAgo(now, 1_700_000_000 - 23 * 3600), "23h ago");
  assert.equal(fmtAgo(now, 1_700_000_000 - 24 * 3600), "1d ago");
  assert.equal(fmtAgo(now, 1_700_000_000 - 29 * 86400), "29d ago");
  assert.equal(fmtAgo(now, 1_700_000_000 - 30 * 86400), "1mo ago");
  assert.equal(fmtAgo(now, 1_700_000_000 - 330 * 86400), "11mo ago");
  assert.equal(fmtAgo(now, 1_700_000_000 - 365 * 86400), "1y ago");
  assert.equal(fmtAgo(now, 1_700_000_000 - 800 * 86400), "2y ago");
});

test("clamps future timestamps to just now", () => {
  const now = 1_700_000_000_000;
  assert.equal(fmtAgo(now, 1_700_000_100), "just now");
});
