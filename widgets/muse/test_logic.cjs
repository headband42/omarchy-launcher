#!/usr/bin/env node
// Logic tests for the Muse tile's formatters. Stdlib only. The countdowns
// and calendar days are tested with the shared helpers in
// widgets/_kit/test_usage.cjs.
//
// Run from the repo root:  node --test widgets/muse/test_logic.cjs

const test = require("node:test");
const assert = require("node:assert/strict");
const Muse = require("./muse.js");

test("writes the line under a bar", () => {
  const window = { id: "window", label: "5-HOUR WINDOW", idle: false };
  assert.equal(Muse.detailLine(window, "resets in 4h 12m"), "resets in 4h 12m");
  assert.equal(Muse.detailLine({ id: "window", idle: true }, "resets in 1h"), "starts with your next message");
  assert.equal(Muse.detailLine({ id: "weekly", idle: false }, ""), "");
  assert.equal(Muse.detailLine(null, "x"), "");
  assert.equal(Muse.label(window), "5-HOUR WINDOW");
  assert.equal(Muse.label(null), "");
});

test("names the plan", () => {
  assert.equal(Muse.planName({ plan: "Everyday Usage" }), "Everyday Usage");
  assert.equal(Muse.planName({}), "");
  assert.equal(Muse.planName(null), "");
});

test("says what is missing, by reason", () => {
  assert.equal(Muse.emptyHeadline(null), "Reading Muse usage…");
  assert.equal(Muse.emptyBody(null), "");
  assert.equal(Muse.emptyHeadline({ ok: false, reason: "signin" }), "No Muse sign-in");
  assert.match(Muse.emptyBody({ ok: false, reason: "signin" }), /API key/);
  assert.equal(Muse.emptyHeadline({ ok: false, reason: "expired" }), "Sign-in expired");
  assert.match(Muse.emptyBody({ ok: false, reason: "expired" }), /muse login/);
  assert.equal(Muse.emptyHeadline({ ok: false, reason: "plan" }), "No subscription");
  assert.equal(Muse.emptyHeadline({ ok: false, reason: "error", error: "offline" }), "Muse usage unavailable");
  assert.equal(Muse.emptyBody({ ok: false, reason: "error", error: "offline" }), "offline");
});

test("trusts only a good cached reply", () => {
  const good = { ok: true, meters: [{ id: "window", percent: 5 }], savedAt: 1 };
  assert.deepEqual(Muse.fromCache(JSON.stringify(good)), good);
  assert.equal(Muse.fromCache(JSON.stringify({ ok: true, meters: [] })), null);
  assert.equal(Muse.fromCache(JSON.stringify({ ok: false, meters: [{}] })), null);
  assert.equal(Muse.fromCache("{"), null);
});
