#!/usr/bin/env node
// Logic tests for the calendar tile. Stdlib only.
//
// Run from the repo root:  node --test widgets/agenda/test_logic.cjs

process.env.TZ = "America/Denver";

const test = require("node:test");
const assert = require("node:assert/strict");
const A = require("./agenda.js");

const at = (y, mo, d, h = 0, mi = 0) => new Date(y, mo - 1, d, h, mi).getTime() / 1000;
// Friday 2 October 2026, 08:30 in Denver.
const NOW = new Date(2026, 9, 2, 8, 30).getTime();

const events = [
  { title: "Standup", start: at(2026, 10, 2, 8, 0), end: at(2026, 10, 2, 9, 0), allDay: false, calendar: 0, link: "https://meet.google.com/x" },
  { title: "Earlier", start: at(2026, 10, 2, 6, 0), end: at(2026, 10, 2, 7, 0), allDay: false, calendar: 0 },
  { title: "Lunch", start: at(2026, 10, 2, 12, 0), end: at(2026, 10, 2, 13, 0), allDay: false, calendar: 1 },
  { title: "Trip", start: at(2026, 10, 3), end: at(2026, 10, 6), allDay: true, calendar: 2 },
  { title: "Red-eye", start: at(2026, 10, 7, 23, 0), end: at(2026, 10, 8, 6, 0), allDay: false, calendar: 1 },
];

test("counts cover every day an event touches, all-day ends exclusive", () => {
  const counts = A.countsByDay(events);
  assert.equal(counts["2026-10-02"], 3);
  assert.equal(counts["2026-10-03"], 1);
  assert.equal(counts["2026-10-05"], 1);
  assert.equal(counts["2026-10-06"], undefined);
  assert.equal(counts["2026-10-07"], 1);
  assert.equal(counts["2026-10-08"], 1);
});

test("the week starts where the locale says", () => {
  const sunday = A.week(NOW, 0, {});
  assert.deepEqual(sunday.map((d) => d.day), [27, 28, 29, 30, 1, 2, 3]);
  assert.equal(sunday[5].today, true);
  assert.equal(sunday[0].past, true);
  const monday = A.week(NOW, 1, {});
  assert.deepEqual(monday.map((d) => d.name), ["M", "T", "W", "T", "F", "S", "S"]);
  assert.equal(monday[0].day, 28);
});

test("month grid", () => {
  const grid = A.monthGrid(NOW, 0, 0, { "2026-10-12": 2 });
  assert.equal(grid.title, "October 2026");
  assert.equal(grid.cells.length, 42);
  assert.equal(grid.cells[0].day, 27);
  assert.equal(grid.cells[0].inMonth, false);
  assert.equal(grid.cells.find((c) => c.today).key, "2026-10-02");
  assert.equal(grid.cells.find((c) => c.key === "2026-10-12").count, 2);
  assert.equal(A.monthGrid(NOW, 1, 0, {}).title, "November 2026");
  assert.equal(A.monthGrid(NOW, -10, 0, {}).title, "December 2025");
  assert.deepEqual(A.weekdayLetters(1), ["M", "T", "W", "T", "F", "S", "S"]);
});

test("agenda drops what ended today and keeps what is on now", () => {
  const groups = A.agenda(events, NOW, 14, true);
  assert.deepEqual(groups.map((g) => g.label), ["Today", "Tomorrow", "Sun Oct 4", "Mon Oct 5", "Wed Oct 7", "Thu Oct 8"]);
  assert.deepEqual(groups[0].events.map((e) => [e.title, e.time, e.now]), [["Standup", "08:00", true], ["Lunch", "12:00", false]]);
  assert.deepEqual(groups[1].events.map((e) => [e.title, e.time]), [["Trip", "all day"]]);
  assert.deepEqual(groups[5].events.map((e) => [e.title, e.time]), [["Red-eye", "→ 06:00"]]);
});

test("flattened rows and jumping to a day", () => {
  const rows = A.flatten(A.agenda(events, NOW, 14, true));
  assert.equal(rows[0].kind, "day");
  assert.equal(rows[1].event.title, "Standup");
  assert.equal(A.indexOfDay(rows, "2026-10-05"), rows.findIndex((r) => r.kind === "day" && r.key === "2026-10-05"));
  assert.equal(A.indexOfDay(rows, "2026-10-06"), rows.findIndex((r) => r.kind === "day" && r.key === "2026-10-07"));
  assert.equal(A.indexOfDay(rows, "2027-01-01"), -1);
});

test("clock formats", () => {
  assert.equal(A.fmtClock(at(2026, 10, 2, 9, 0), true), "09:00");
  assert.equal(A.fmtClock(at(2026, 10, 2, 9, 0), false), "9am");
  assert.equal(A.fmtClock(at(2026, 10, 2, 13, 5), false), "1:05pm");
  assert.equal(A.fmtClock(at(2026, 10, 2, 0, 30), false), "12:30am");
});

test("header note", () => {
  assert.equal(A.headerNote(events, NOW), "now");
  assert.equal(A.headerNote(events, new Date(2026, 9, 2, 11, 35).getTime()), "in 25m");
  assert.equal(A.headerNote(events, new Date(2026, 9, 2, 10, 30).getTime()), "in 1h 30m");
  assert.equal(A.headerNote(events, new Date(2026, 9, 2, 14, 0).getTime()), "");
  assert.equal(A.headerNote([], NOW), "");
  assert.equal(A.fmtIn(3 * 86400), "in 3d");
  assert.equal(A.dateTitle(NOW), "FRI, OCT 2");
});
