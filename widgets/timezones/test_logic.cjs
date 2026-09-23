#!/usr/bin/env node
// Clock formatting and zone-list normalization. Stdlib only.
//
// Run from the repo root:  node --test widgets/timezones/test_logic.cjs

const { describe, it } = require("node:test");
const assert = require("node:assert/strict");
const path = require("path");

const Zones = require(path.join(__dirname, "zones.js"));

describe("normalizeZones", () => {
  it("keeps three unique valid ids in order", () => {
    assert.deepEqual(
      Zones.normalizeZones({
        zones: ["  UTC ", "America/New_York", "UTC", "Asia/Tokyo", "Europe/London"]
      }),
      ["UTC", "America/New_York", "Asia/Tokyo"]
    );
  });

  it("drops blanks, duplicates, and ids that are not zone names", () => {
    assert.deepEqual(
      Zones.normalizeZones({
        zones: ["", "Not a zone", "../etc/passwd", "America//Denver", "Etc/GMT+5", "Etc/GMT+5"]
      }),
      ["Etc/GMT+5"]
    );
  });

  it("treats a missing list as no extra clocks", () => {
    assert.deepEqual(Zones.normalizeZones(null), []);
    assert.deepEqual(Zones.normalizeZones({ zones: "UTC" }), []);
    assert.equal(Zones.settingsFromZones([]), null);
    assert.deepEqual(Zones.settingsFromZones(["UTC", "UTC"]), { zones: ["UTC"] });
  });
});

describe("labels", () => {
  it("splits a zone id into a city and a region", () => {
    assert.equal(Zones.cityOf("America/Argentina/Buenos_Aires"), "Buenos Aires");
    assert.equal(Zones.regionOf("America/Argentina/Buenos_Aires"), "America · Argentina");
    assert.equal(Zones.cityOf("UTC"), "UTC");
    assert.equal(Zones.regionOf("UTC"), "");
  });
});

describe("clocks", () => {
  // 2026-09-23 05:30 UTC. Denver (UTC-6) is still the previous evening.
  const now = Date.UTC(2026, 8, 23, 5, 30, 0);

  it("formats 24-hour and 12-hour wall clocks from an offset", () => {
    assert.equal(Zones.formatTime(now, -360, false), "23:30");
    assert.equal(Zones.formatTime(now, 540, false), "14:30");
    assert.equal(Zones.formatTime(now, -360, true), "11:30 PM");
    assert.equal(Zones.formatTime(now, 0, true), "5:30 AM");
    assert.equal(Zones.formatTime(Date.UTC(2026, 0, 1, 0, 5), 0, true), "12:05 AM");
    assert.equal(Zones.formatTime(Date.UTC(2026, 0, 1, 12, 5), 0, true), "12:05 PM");
  });

  it("names the calendar day in that zone", () => {
    assert.equal(Zones.formatDate(now, -360), "Tue 22 Sep");
    assert.equal(Zones.formatDate(now, 540), "Wed 23 Sep");
  });

  it("reports how many days ahead or behind the local clock a zone is", () => {
    assert.equal(Zones.dayDelta(now, -360, 540), 1);
    assert.equal(Zones.dayDelta(now, -360, -360), 0);
    assert.equal(Zones.formatDayDelta(1), "+1");
    assert.equal(Zones.formatDayDelta(-1), "-1");
    assert.equal(Zones.formatDayDelta(0), "");
  });
});
