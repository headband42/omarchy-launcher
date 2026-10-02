#!/usr/bin/env node
// Logic tests for the F1 tile. Stdlib only.
//
// Run from the repo root:  node --test widgets/f1/test_logic.cjs

process.env.TZ = "America/Denver";

const test = require("node:test");
const assert = require("node:assert/strict");
const F = require("./f1.js");

const sessions = [
  { name: "FP1", start: 1000, end: 4600 },
  { name: "Qualifying", start: 90000, end: 93600 },
  { name: "Race", start: 180000, end: 187200 },
];

test("names", () => {
  assert.equal(F.shortSession("Qualifying"), "Quali");
  assert.equal(F.shortSession("Sprint Qualifying"), "Sprint Q");
  assert.equal(F.shortSession("FP2"), "FP2");
  assert.equal(F.shortRace("Bahrain Grand Prix"), "Bahrain GP");
  assert.equal(F.shortRace("Grand Prix de Monaco"), "GP de Monaco");
});

test("countdowns", () => {
  assert.equal(F.countdown(30), "now");
  assert.equal(F.countdown(25 * 60), "25m");
  assert.equal(F.countdown(5 * 3600 + 20 * 60), "5h 20m");
  assert.equal(F.countdown(2 * 86400 + 5 * 3600), "2d 5h");
});

test("session states and the next one", () => {
  assert.equal(F.sessionState(sessions[0], 500), "later");
  assert.equal(F.sessionState(sessions[0], 2000), "live");
  assert.equal(F.sessionState(sessions[0], 4600), "done");
  assert.equal(F.nextSession(sessions, 2000).name, "FP1");
  assert.equal(F.nextSession(sessions, 5000).name, "Qualifying");
  assert.equal(F.nextSession(sessions, 999999), null);
});

test("header note", () => {
  assert.equal(F.headerNote({ next: { sessions } }, 1000 - 25 * 60), "FP1 in 25m");
  assert.equal(F.headerNote({ next: { sessions } }, 2000), "FP1 now");
  assert.equal(F.headerNote({ next: { sessions }, live: { session: "FP1", finished: false } }, 2000), "LIVE · FP1");
  assert.equal(F.headerNote({ next: { sessions }, live: { session: "FP1", finished: true } }, 5000), "Quali in 23h 36m");
  assert.equal(F.headerNote(null, 0), "");
});

test("clock, dates, pages, colours", () => {
  const sunday1pm = new Date(2026, 9, 4, 13, 0).getTime() / 1000;
  assert.equal(F.clock(sunday1pm, false), "Sun 1pm");
  assert.equal(F.clock(sunday1pm, true), "Sun 13:00");
  assert.equal(F.dateText(sunday1pm), "Oct 4");
  assert.equal(F.nextPage(0, 1), 1);
  assert.equal(F.nextPage(0, -1), 2);
  assert.equal(F.nextPage(2, 1), 0);
  assert.equal(F.colour("00D7B6"), "#00D7B6");
  assert.equal(F.colour("bad"), "");
});
