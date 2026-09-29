// Logic tests for the OpenCode Go tile's formatters. Stdlib only.
//
// opencode.js is the shipped file that Widget.qml and Settings.qml import, so
// this exercises that exact code rather than a copy of it.
//
// Run from the repo root:  node --test widgets/opencode/test_logic.cjs

const test = require("node:test");
const assert = require("node:assert/strict");
const Go = require("./opencode.js");

const fiveHour = {
  id: "fiveHour", label: "5-hour", used: 1.44, limit: 12, percent: 12,
  resetCountdown: "4h 04m", resetDay: "today 9:42 pm", expired: false, over: false, near: false
};
const week = {
  id: "week", label: "week", used: 21, limit: 30, percent: 70,
  resetCountdown: "6d 06h", resetDay: "Oct 5", expired: false, over: false, near: false
};
const month = {
  id: "month", label: "month", used: 60.5, limit: 60, percent: 100.8,
  resetCountdown: "27d 09h", resetDay: "Oct 26", expired: false, over: true, near: true
};

const sample = {
  ok: true, plan: "OpenCode Go", active: true, canceling: false,
  renewalPending: false, currency: "USD",
  renewalDay: "Oct 26", meters: [fiveHour, week, month]
};

test("money drops cents only when there are none", () => {
  assert.equal(Go.money(12), "$12");
  assert.equal(Go.money(0), "$0");
  assert.equal(Go.money(1.25), "$1.25");
  assert.equal(Go.money(60.5), "$60.50");
  assert.equal(Go.money(0.05), "$0.05");
  assert.equal(Go.money(1.5), "$1.50");
  assert.equal(Go.money(-3), "$-3");
  assert.equal(Go.money(12.004), "$12");
  for (const bad of [null, undefined, NaN, "x", {}]) {
    assert.equal(Go.money(bad), "—");
  }
  assert.equal(Go.moneyExact(12), "$12.00");
  assert.equal(Go.moneyExact(1.5), "$1.50");
  assert.equal(Go.moneyExact(null), "—");
});

test("a percentage reads as a whole number, over or not", () => {
  assert.equal(Go.percent({ percent: 12 }), "12%");
  assert.equal(Go.percent({ percent: 12.4 }), "12%");
  assert.equal(Go.percent({ percent: 12.6 }), "13%");
  assert.equal(Go.percent({ percent: 100.8 }), "101%");
  assert.equal(Go.percent({ percent: 0 }), "0%");
  for (const bad of [null, undefined, {}, { percent: null }, { percent: "x" }]) {
    assert.equal(Go.percent(bad), "—");
  }
});

test("the bar fills to the track but the number does not clip", () => {
  assert.equal(Go.fill({ percent: 0 }), 0);
  assert.equal(Go.fill({ percent: 50 }), 0.5);
  assert.equal(Go.fill({ percent: 100 }), 1);
  // A block over its limit fills the bar and no further.
  assert.equal(Go.fill({ percent: 108 }), 1);
  assert.equal(Go.fill({ percent: -5 }), 0);
  for (const bad of [null, undefined, {}, { percent: "x" }]) {
    assert.equal(Go.fill(bad), 0);
  }
});

test("a bar warms up as its block fills and turns urgent past the ceiling", () => {
  assert.equal(Go.tone({ percent: 10 }), "calm");
  assert.equal(Go.tone({ percent: 49.9 }), "calm");
  assert.equal(Go.tone({ percent: 50 }), "warm");
  assert.equal(Go.tone({ percent: 79.9 }), "warm");
  assert.equal(Go.tone({ percent: 80 }), "urgent");
  // Being over the limit is the strongest signal there is.
  assert.equal(Go.tone({ percent: 5, over: true }), "urgent");
  assert.equal(Go.tone({ percent: "x" }), "muted");
  assert.equal(Go.tone(null), "muted");
});

test("tones map onto the ramp between the theme's own colors", () => {
  assert.equal(Go.toneFraction("calm"), 0);
  assert.equal(Go.toneFraction("muted"), 0.15);
  assert.ok(Go.toneFraction("warm") > 0.4 && Go.toneFraction("warm") < 0.7);
  assert.equal(Go.toneFraction("urgent"), 1);
  assert.equal(Go.toneFraction("nonsense"), 0.15);
  assert.equal(Go.toneFraction(null), 0.15);
});

test("a block is named and its money line is readable", () => {
  assert.equal(Go.label(fiveHour), "5-HOUR");
  assert.equal(Go.label({ label: "week" }), "WEEK");
  assert.equal(Go.label(null), "");
  assert.equal(Go.usedLine(fiveHour), "$1.44 of $12");
  assert.equal(Go.usedLine(month), "$60.50 of $60");
  assert.equal(Go.usedLine(null), "");
});

test("the reset line offers a countdown or a calendar day", () => {
  assert.equal(Go.resetLine(fiveHour, "relative"), "resets in 4h 04m");
  assert.equal(Go.resetLine(fiveHour, "absolute"), "resets today 9:42 pm");
  assert.equal(Go.resetLine(week, "absolute"), "resets Oct 5");
  // Default is the countdown, which is the one you can act on.
  assert.equal(Go.resetLine(week, ""), "resets in 6d 06h");
  // A block that has just reset says so rather than counting from zero.
  const expired = { expired: true, resetCountdown: "now", resetDay: "today 1:00 pm" };
  assert.equal(Go.resetLine(expired, "relative"), "resetting");
  assert.equal(Go.resetLine(expired, "absolute"), "resetting");
  assert.equal(Go.resetLine({}, "relative"), "");
  assert.equal(Go.resetLine(null), "");
});

test("the subscription is described by what it is doing", () => {
  assert.equal(Go.planLabel(sample), "OPENCODE GO");
  assert.equal(Go.planLabel({}), "OPENCODE");
  assert.equal(Go.planLabel(null), "OPENCODE");
  assert.equal(Go.renewalLine(sample), "through Oct 26");
  assert.equal(Go.renewalLine({ canceling: true, renewalDay: "Oct 26" }), "ends Oct 26");
  assert.equal(Go.renewalLine({ renewalPending: true, renewalDay: "Oct 26" }), "renews Oct 26");
  assert.equal(Go.renewalLine({ renewalPending: true }), "renewing");
  assert.equal(Go.renewalLine({}), "");
});

test("the status word follows the subscription, not the network", () => {
  assert.equal(Go.statusText(sample), "ACTIVE");
  assert.equal(Go.statusTone(sample), "calm");
  assert.equal(Go.statusText({ ok: true, active: false }), "PAUSED");
  assert.equal(Go.statusTone({ ok: true, active: false }), "muted");
  assert.equal(Go.statusText({ ok: true, active: true, canceling: true }), "ENDING");
  assert.equal(Go.statusTone({ ok: true, canceling: true }), "warm");
  // A failed read says so and stays quiet rather than claiming a plan.
  assert.equal(Go.statusText({ ok: false }), "OFFLINE");
  assert.equal(Go.statusTone({ ok: false }), "muted");
});

test("blocks can be left off the tile", () => {
  assert.equal(Go.metersOf(sample, "").length, 3);
  assert.equal(Go.metersOf(sample, null).length, 3);
  assert.equal(Go.metersOf(sample, "month").length, 2);
  assert.equal(Go.metersOf(sample, "week,month").length, 1);
  assert.equal(Go.metersOf(sample, "week,month")[0].id, "fiveHour");
  // Hiding something that is not there changes nothing.
  assert.equal(Go.metersOf(sample, "decade").length, 3);
  assert.equal(Go.metersOf({ meters: [] }, "").length, 0);
  assert.equal(Go.metersOf({}, "").length, 0);
  assert.equal(Go.metersOf(null, "").length, 0);
});

test("the headline is the block closest to its ceiling", () => {
  assert.equal(Go.headlinePercent([fiveHour, week, month]), "101%");
  assert.equal(Go.headlinePercent([fiveHour, week]), "70%");
  // Order in the list does not decide it.
  assert.equal(Go.headlinePercent([month, week, fiveHour]), "101%");
  // A block with no percentage cannot be the worst.
  const unknown = { id: "x", percent: null };
  assert.equal(Go.headlinePercent([unknown, fiveHour]), "12%");
  assert.equal(Go.headlinePercent([]), "—");
  assert.equal(Go.headlinePercent(null), "—");
});

test("the placeholder says which kind of nothing it is", () => {
  assert.equal(Go.emptyHeadline({ ok: false }), "Go usage unavailable");
  assert.equal(Go.emptyBody({ ok: false, error: "Console sign-in has expired" }),
               "Console sign-in has expired");
  assert.equal(Go.emptyBody({ ok: false }), "OpenCode is not answering");
  assert.equal(Go.emptyHeadline({ ok: true, meters: [] }), "No Go blocks");
  assert.equal(Go.emptyBody({ ok: true, meters: [] }), "This account has no Go usage blocks.");
  // Before the first read there is nothing to complain about yet.
  assert.equal(Go.emptyHeadline({}), "OPENCODE");
  assert.equal(Go.emptyBody({}), "Waiting for the console.");
});
