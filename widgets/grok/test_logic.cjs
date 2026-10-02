#!/usr/bin/env node
// Logic tests for the Grok tile's formatters. Stdlib only. The countdowns
// and calendar days are tested with the shared helpers in
// widgets/_kit/test_usage.cjs.
//
// Run from the repo root:  node --test widgets/grok/test_logic.cjs

const test = require("node:test");
const assert = require("node:assert/strict");
const Grok = require("./grok.js");

const week = { id: "period", label: "WEEK", percent: 5, resetsAtMs: 1 };
const spend = { id: "ondemand", label: "PAY AS YOU GO", used: 3.55, limit: 50, percent: 7.1 };

test("money drops cents only when there are none", () => {
  assert.equal(Grok.money(12), "$12");
  assert.equal(Grok.money(0), "$0");
  assert.equal(Grok.money(50), "$50");
  assert.equal(Grok.money(3.55), "$3.55");
  assert.equal(Grok.money(12.5), "$12.50");
  assert.equal(Grok.money(0.05), "$0.05");
  assert.equal(Grok.money(1.919), "$1.92");
  assert.equal(Grok.money(-12.5), "$12.50");
  for (const bad of [null, undefined, NaN, "x", {}, ""]) assert.equal(Grok.money(bad), "");
});

test("writes the line under a bar", () => {
  assert.equal(Grok.detailLine(week, "resets in 5d 7h"), "resets in 5d 7h");
  assert.equal(Grok.detailLine(spend, "resets in 5d 7h"), "$3.55 of $50 · resets in 5d 7h");
  assert.equal(Grok.detailLine(spend, ""), "$3.55 of $50");
  assert.equal(Grok.detailLine(week, ""), "");
  assert.equal(Grok.detailLine(null, "x"), "");
  assert.equal(Grok.label(week), "WEEK");
  assert.equal(Grok.label({ label: "month" }), "MONTH");
  assert.equal(Grok.label(null), "");
});

test("names the plan and bought credits", () => {
  assert.equal(Grok.planLabel({ plan: "X Premium+" }), "X PREMIUM+");
  assert.equal(Grok.planLabel({}), "GROK");
  assert.equal(Grok.planLabel(null), "GROK");
  assert.equal(Grok.footerLine({ ok: true, credits: 12.5 }), "credits $12.50");
  assert.equal(Grok.footerLine({ ok: true, credits: 5 }), "credits $5");
  assert.equal(Grok.footerLine({ ok: true, credits: null }), "");
  assert.equal(Grok.footerLine({ ok: false, credits: 12.5 }), "");
  assert.equal(Grok.footerLine(null), "");
});

test("says what is missing, by reason", () => {
  assert.equal(Grok.emptyHeadline(null), "Reading Grok usage…");
  assert.equal(Grok.emptyBody(null), "");
  assert.equal(Grok.emptyHeadline({ ok: false, reason: "signin" }), "No Grok sign-in");
  assert.match(Grok.emptyBody({ ok: false, reason: "signin" }), /API key/);
  assert.equal(Grok.emptyHeadline({ ok: false, reason: "expired" }), "Sign-in expired");
  assert.match(Grok.emptyBody({ ok: false, reason: "expired" }), /next time it runs/);
  assert.equal(Grok.emptyHeadline({ ok: false, reason: "plan" }), "No usage limits");
  assert.equal(Grok.emptyBody({ ok: false, reason: "plan", error: "This sign-in has no usage limits" }),
    "This sign-in has no usage limits");
  assert.equal(Grok.emptyHeadline({ ok: false, reason: "error", error: "offline" }), "Grok usage unavailable");
  assert.equal(Grok.emptyBody({ ok: false, reason: "error", error: "offline" }), "offline");
});

test("trusts only a good cached reply", () => {
  const good = { ok: true, meters: [{ id: "period", percent: 5 }], savedAt: 1 };
  assert.deepEqual(Grok.fromCache(JSON.stringify(good)), good);
  assert.equal(Grok.fromCache(JSON.stringify({ ok: true, meters: [] })), null);
  assert.equal(Grok.fromCache(JSON.stringify({ ok: false, meters: [{}] })), null);
  assert.equal(Grok.fromCache("{"), null);
  assert.equal(Grok.fromCache(""), null);
});
