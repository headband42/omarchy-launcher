#!/usr/bin/env node
// Logic tests for the OpenCode Go tile's formatters. Stdlib only.
//
// opencode.js is the shipped file that Widget.qml imports, so this exercises
// that exact code rather than a copy of it. The countdowns and calendar days
// are tested with the shared helpers in widgets/_kit/test_usage.cjs.
//
// Run from the repo root:  node --test widgets/opencode/test_logic.cjs

const test = require("node:test");
const assert = require("node:assert/strict");
const Go = require("./opencode.js");

const fiveHour = { id: "fiveHour", label: "5-HOUR", used: 0, limit: 12, percent: 0, idle: true };
const week = { id: "week", label: "WEEK", used: 1.92, limit: 30, percent: 6.4, idle: false };
const month = { id: "month", label: "MONTH", used: 60.5, limit: 60, percent: 100.8, over: true };

test("money drops cents only when there are none", () => {
  assert.equal(Go.money(12), "$12");
  assert.equal(Go.money(0), "$0");
  assert.equal(Go.money(1.25), "$1.25");
  assert.equal(Go.money(60.5), "$60.50");
  assert.equal(Go.money(0.05), "$0.05");
  assert.equal(Go.money(1.91988426), "$1.92");
  assert.equal(Go.money(12.004), "$12");
  for (const bad of [null, undefined, NaN, "x", {}, ""]) assert.equal(Go.money(bad), "—");
});

test("labels and spends", () => {
  assert.equal(Go.label(week), "WEEK");
  assert.equal(Go.label({ label: "decade" }), "DECADE");
  assert.equal(Go.label(null), "");
  assert.equal(Go.usedLine(week), "$1.92 of $30");
  assert.equal(Go.usedLine(month), "$60.50 of $60");
  assert.equal(Go.usedLine(null), "");
});

test("writes the line under a bar", () => {
  assert.equal(Go.detailLine(week, "resets in 3d 16h", true), "$1.92 of $30 · resets in 3d 16h");
  assert.equal(Go.detailLine(week, "resets in 3d 16h", false), "resets in 3d 16h");
  assert.equal(Go.detailLine(week, "resets in 3d 16h"), "$1.92 of $30 · resets in 3d 16h");
  // A block with no window yet never says "resets in now".
  assert.equal(Go.detailLine(fiveHour, "", true), "$0 of $12 · starts with your next request");
  assert.equal(Go.detailLine(fiveHour, "resets in 5h", false), "starts with your next request");
  assert.equal(Go.detailLine(week, "", false), "");
  assert.equal(Go.detailLine(null, "x", true), "");
});

test("names the headline block", () => {
  assert.equal(Go.headlineCaption(fiveHour), "of the 5-hour block");
  assert.equal(Go.headlineCaption(week), "of this week’s block");
  assert.equal(Go.headlineCaption(month), "of this month’s block");
  assert.equal(Go.headlineCaption({ id: "decade", label: "DECADE" }), "of the decade block");
  assert.equal(Go.headlineCaption(null), "");
});

test("describes the plan", () => {
  const sample = { ok: true, plan: "OpenCode Go", active: true };
  assert.equal(Go.planLabel(sample), "OPENCODE GO");
  assert.equal(Go.planLabel({}), "OPENCODE GO");
  assert.equal(Go.statusText(sample), "active");
  assert.equal(Go.statusText({ ok: true, canceling: true }), "ending");
  assert.equal(Go.statusText({ ok: true, active: false }), "paused");
  assert.equal(Go.statusText({ ok: false }), "");
  assert.equal(Go.renewalLine(sample, "Oct 25"), "through Oct 25");
  assert.equal(Go.renewalLine({ ok: true, canceling: true }, "Oct 25"), "ends Oct 25");
  assert.equal(Go.renewalLine({ ok: true, renewalPending: true }, ""), "renewing");
  assert.equal(Go.renewalLine({ ok: false }, "Oct 25"), "");
});

test("says what is missing, by reason", () => {
  assert.equal(Go.emptyHeadline(null), "Reading OpenCode Go…");
  assert.equal(Go.emptyBody(null), "");
  assert.equal(Go.emptyHeadline({ ok: false, reason: "signin" }), "No console account");
  assert.match(Go.emptyBody({ ok: false, reason: "signin" }), /Sign in/);
  assert.equal(Go.emptyHeadline({ ok: false, reason: "expired" }), "Sign-in expired");
  assert.equal(Go.emptyHeadline({ ok: false, reason: "plan", error: "No Go usage blocks" }), "No Go plan");
  assert.equal(Go.emptyBody({ ok: false, reason: "plan", error: "No Go usage blocks" }), "No Go usage blocks");
  assert.equal(Go.emptyHeadline({ ok: false, reason: "error", error: "offline" }), "Go usage unavailable");
  assert.equal(Go.emptyBody({ ok: false, reason: "error", error: "offline" }), "offline");
});

test("trusts only a good cached reply", () => {
  const good = { ok: true, meters: [week], savedAt: 1 };
  assert.deepEqual(Go.fromCache(JSON.stringify(good)), good);
  assert.equal(Go.fromCache(JSON.stringify({ ok: true, meters: [] })), null);
  assert.equal(Go.fromCache(JSON.stringify({ ok: false, meters: [week] })), null);
  assert.equal(Go.fromCache("not json"), null);
  assert.equal(Go.fromCache(""), null);
});
