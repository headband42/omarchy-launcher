#!/usr/bin/env node
// Logic tests for the Claude tile's formatters. Stdlib only. The countdowns
// and calendar days are tested with the shared helpers in
// widgets/_kit/test_usage.cjs.
//
// Run from the repo root:  node --test widgets/claude/test_logic.cjs

const test = require("node:test");
const assert = require("node:assert/strict");
const Claude = require("./claude.js");

test("writes the line under a bar", () => {
  const session = { id: "five_hour", label: "5-HOUR SESSION", idle: false };
  assert.equal(Claude.detailLine(session, "resets in 2h 14m"), "resets in 2h 14m");
  assert.equal(Claude.detailLine({ id: "seven_day_opus", idle: true }, "resets in 1h"), "starts with your next message");
  assert.equal(Claude.detailLine({ id: "extra_usage", idle: false }, ""), "pay as you go, past the plan");
  assert.equal(Claude.detailLine({ id: "seven_day", idle: false }, ""), "");
  assert.equal(Claude.detailLine(null, "x"), "");
  assert.equal(Claude.label(session), "5-HOUR SESSION");
  assert.equal(Claude.label(null), "");
});

test("names the plan", () => {
  assert.equal(Claude.planLabel({ plan: "Claude Max 20x" }), "CLAUDE MAX 20X");
  assert.equal(Claude.planLabel({}), "CLAUDE");
  assert.equal(Claude.planLabel(null), "CLAUDE");
});

test("says what is missing, by reason", () => {
  assert.equal(Claude.emptyHeadline(null), "Reading Claude usage…");
  assert.equal(Claude.emptyBody(null), "");
  assert.equal(Claude.emptyHeadline({ ok: false, reason: "signin" }), "No Claude sign-in");
  assert.match(Claude.emptyBody({ ok: false, reason: "signin" }), /API key/);
  assert.equal(Claude.emptyHeadline({ ok: false, reason: "expired" }), "Sign-in expired");
  assert.match(Claude.emptyBody({ ok: false, reason: "expired" }), /next time it runs/);
  assert.equal(Claude.emptyHeadline({ ok: false, reason: "plan" }), "No plan limits");
  assert.equal(Claude.emptyHeadline({ ok: false, reason: "error", error: "offline" }), "Claude usage unavailable");
  assert.equal(Claude.emptyBody({ ok: false, reason: "error", error: "offline" }), "offline");
});

test("trusts only a good cached reply", () => {
  const good = { ok: true, meters: [{ id: "five_hour", percent: 4 }], savedAt: 1 };
  assert.deepEqual(Claude.fromCache(JSON.stringify(good)), good);
  assert.equal(Claude.fromCache(JSON.stringify({ ok: true, meters: [] })), null);
  assert.equal(Claude.fromCache(JSON.stringify({ ok: false, meters: [{}] })), null);
  assert.equal(Claude.fromCache("{"), null);
});
