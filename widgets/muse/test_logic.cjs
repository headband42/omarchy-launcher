#!/usr/bin/env node
// Logic tests for the Muse tile's formatters. Stdlib only. The countdowns
// and calendar days are tested with the shared helpers in
// widgets/_kit/test_usage.cjs.
//
// Run from the repo root:  node --test widgets/muse/test_logic.cjs

const test = require("node:test");
const assert = require("node:assert/strict");
const Muse = require("./muse.js");

test("reads the sampler's line under a bar", () => {
  const today = { id: "today", label: "TODAY", detail: "31K tokens · 2 sessions" };
  assert.equal(Muse.detailLine(today, ""), "31K tokens · 2 sessions");
  assert.equal(Muse.detailLine(today, "resets in 2h"), "resets in 2h");
  assert.equal(Muse.detailLine({ id: "week" }, ""), "");
  assert.equal(Muse.detailLine(null, "x"), "");
  assert.equal(Muse.label(today), "TODAY");
  assert.equal(Muse.label(null), "");
});

test("names the plan and the model", () => {
  assert.equal(Muse.planLabel({ plan: "Muse" }), "MUSE");
  assert.equal(Muse.planLabel({}), "MUSE");
  assert.equal(Muse.planLabel(null), "MUSE");
  assert.equal(Muse.modelShort({ model: "muse-spark-1.3-contributor" }), "spark-1.3");
  assert.equal(Muse.modelShort({ model: "muse-spark-1.3" }), "spark-1.3");
  assert.equal(Muse.modelShort({ model: "other-model" }), "other-model");
  assert.equal(Muse.modelShort({}), "");
  assert.equal(Muse.modelShort(null), "");
});

test("says what is missing, by reason", () => {
  assert.equal(Muse.emptyHeadline(null), "Reading Muse usage…");
  assert.equal(Muse.emptyBody(null), "");
  assert.equal(Muse.emptyHeadline({ ok: false, reason: "empty" }), "No Muse usage yet");
  assert.match(Muse.emptyBody({ ok: false, reason: "empty" }), /session logs/);
  assert.equal(Muse.emptyHeadline({ ok: false, reason: "error", error: "offline" }), "Muse usage unavailable");
  assert.equal(Muse.emptyBody({ ok: false, reason: "error", error: "offline" }), "offline");
});

test("trusts only a good cached reply", () => {
  const good = { ok: true, meters: [{ id: "today", percent: null }], savedAt: 1 };
  assert.deepEqual(Muse.fromCache(JSON.stringify(good)), good);
  assert.equal(Muse.fromCache(JSON.stringify({ ok: true, meters: [] })), null);
  assert.equal(Muse.fromCache(JSON.stringify({ ok: false, meters: [{}] })), null);
  assert.equal(Muse.fromCache("{"), null);
});
