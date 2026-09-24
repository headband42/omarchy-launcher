const test = require("node:test");
const assert = require("node:assert/strict");
const Weather = require("./weather.js");

test("normalizes location and settings", () => {
  const location = Weather.normalizedLocation({
    name: "Oslo",
    latitude: "59.9139",
    longitude: "10.7522",
    countryCode: "no"
  });
  assert.deepEqual(location, {
    name: "Oslo",
    detail: "",
    latitude: 59.9139,
    longitude: 10.7522,
    timezone: "",
    admin1: "",
    country: "",
    countryCode: "NO"
  });
  assert.equal(Weather.normalizedLocation({ latitude: 100, longitude: 0 }), null);
  assert.equal(Weather.normalizedSettings({ units: "metric" }).units, "metric");
  assert.equal(Weather.normalizedSettings({ units: "kelvin" }).units, "imperial");
});

test("formats metric and imperial weather values", () => {
  assert.equal(Weather.temperature(20, "metric"), "20°");
  assert.equal(Weather.temperature(20, "imperial"), "68°");
  assert.equal(Weather.speed(100, "metric"), "100 km/h");
  assert.equal(Weather.speed(100, "imperial"), "62 mph");
  assert.equal(Weather.precipitation(25.4, "metric"), "25.4 mm");
  assert.equal(Weather.precipitation(25.4, "imperial"), "1.0 in");
  assert.equal(Weather.visibility(1600, "metric"), "1.6 km");
  assert.equal(Weather.visibility(16094, "imperial"), "10 mi");
  assert.equal(Weather.temperature("bad", "metric"), "—");
});

test("formats local clock and forecast day", () => {
  assert.equal(Weather.clock("2026-09-24T05:42"), "05:42");
  assert.equal(Weather.clock("2026-09-24T00:05", true), "12a");
  assert.equal(Weather.clock("2026-09-24T13:05", true), "1p");
  assert.equal(Weather.day("2026-09-24", 0), "TODAY");
  assert.equal(Weather.day("2026-09-25", 1), "TOMORROW");
  assert.equal(Weather.day("2026-09-26", 2), "SAT");
});

test("maps wind and condition glyphs", () => {
  assert.equal(Weather.windDirection(0), "N");
  assert.equal(Weather.windDirection(225), "SW");
  assert.equal(Weather.windDirection(359), "N");
  assert.equal(Weather.glyph(0, true), "󰖀");
  assert.equal(Weather.glyph(0, false), "󰖓");
  assert.equal(Weather.glyph(95, true), "⛈");
});

test("builds bounded chart points and responsive counts", () => {
  const points = Weather.chartPoints([
    { temperature: 10 },
    { temperature: 12 },
    { temperature: 11 }
  ], "metric", 120, 40);
  assert.equal(points.length, 3);
  assert.equal(points[0].x, 4);
  assert.equal(points[2].x, 116);
  assert.ok(points.every(point => point.y >= 7 && point.y <= 33));
  assert.equal(Weather.chartPoints([], "metric", 120, 40).length, 0);
  assert.equal(Weather.hourlyCount(300), 6);
  assert.equal(Weather.hourlyCount(230), 5);
  assert.equal(Weather.hourlyCount(180), 4);
});
