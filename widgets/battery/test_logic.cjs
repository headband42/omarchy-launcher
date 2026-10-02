#!/usr/bin/env node
// Logic tests for the battery widget. Stdlib only.
//
// Run from the repo root:  node --test widgets/battery/test_logic.cjs

const test = require("node:test");
const assert = require("node:assert/strict");
const { fmtDuration, timeLine, profileLabel, nextProfile } = require("./battery.js");

test("formats durations", () => {
  assert.equal(fmtDuration(0), "");
  assert.equal(fmtDuration(null), "");
  assert.equal(fmtDuration(45), "45m");
  assert.equal(fmtDuration(60), "1h");
  assert.equal(fmtDuration(61), "1h 1m");
  assert.equal(fmtDuration(222), "3h 42m");
  assert.equal(fmtDuration("90"), "1h 30m");
});

test("builds the time line", () => {
  assert.equal(timeLine({ state: "charging", minutesLeft: 65 }), "1h 5m to full");
  assert.equal(timeLine({ state: "charging", minutesLeft: 0 }), "charging");
  assert.equal(timeLine({ state: "discharging", minutesLeft: 222 }), "3h 42m left");
  assert.equal(timeLine({ state: "fully-charged" }), "charged");
  assert.equal(timeLine({ state: "discharging", minutesLeft: 0, onAc: true }), "on AC");
  assert.equal(timeLine({ state: "discharging", minutesLeft: 0 }), "");
  assert.equal(timeLine(null), "");
});

test("labels profiles", () => {
  assert.equal(profileLabel("power-saver"), "Power saver");
  assert.equal(profileLabel("balanced"), "Balanced");
  assert.equal(profileLabel(""), "");
});

test("cycles profiles forward", () => {
  const list = ["power-saver", "balanced", "performance"];
  assert.equal(nextProfile({ profile: "power-saver", profiles: list }), "balanced");
  assert.equal(nextProfile({ profile: "performance", profiles: list }), "power-saver");
  assert.equal(nextProfile({ profile: "missing", profiles: list }), "power-saver");
  assert.equal(nextProfile({ profile: "balanced", profiles: ["balanced"] }), "");
  assert.equal(nextProfile({ profiles: [] }), "");
  assert.equal(nextProfile(null), "");
});
