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
  assert.equal(Weather.normalizedSettings({}).atmosphere, true);
  assert.equal(Weather.normalizedSettings({ atmosphere: false }).atmosphere, false);
  assert.equal(Weather.settingsFor(null, "metric").atmosphere, true);
  assert.equal(Weather.settingsFor(null, "metric", false).atmosphere, false);
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
  // Weather Icons (nf-weather) — clear must never be speaker or lightning
  assert.equal(Weather.glyph(0, true), "");
  assert.equal(Weather.glyph(0, false), "");
  assert.equal(Weather.glyph(0, 0), ""); // numeric is_day
  assert.equal(Weather.glyph(1, true), "");
  assert.equal(Weather.glyph(2, false), "");
  assert.equal(Weather.glyph(3, true), "");
  assert.equal(Weather.glyph(45, true), "");
  assert.equal(Weather.glyph(61, true), "");
  assert.equal(Weather.glyph(63, true), "");
  assert.equal(Weather.glyph(71, true), "");
  assert.equal(Weather.glyph(95, true), "");
  assert.notEqual(Weather.glyph(0, true), "󰖀"); // never speaker
  assert.notEqual(Weather.glyph(0, false), "󰖓"); // never MDI lightning
  assert.notEqual(Weather.glyph(0, true), "");
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
  assert.equal(Weather.hourlyCount(300), 12);
  assert.equal(Weather.hourlyCount(270), 11);
  assert.equal(Weather.hourlyCount(230), 10);
  assert.equal(Weather.hourlyCount(190), 8);
  assert.equal(Weather.hourlyCount(140), 6);
});

test("formats pressure and builds precip bars plus daily days", () => {
  assert.equal(Weather.pressure(1013.25, "metric"), "1013 hPa");
  assert.equal(Weather.pressure(1013.25, "imperial"), "29.92 in");
  assert.equal(Weather.gust(100, "metric"), "100 km/h");
  const bars = Weather.precipBars([
    { precipProbability: 0 },
    { precipProbability: 50 },
    { precipProbability: 100 }
  ], 120, 40);
  assert.equal(bars.length, 3);
  assert.equal(bars[0].height, 0);
  assert.ok(bars[1].height > 0 && bars[1].height < bars[2].height);
  const days = Weather.dailyDays([
    { date: "2026-09-24", code: 0, high: 20, low: 10 },
    { date: "2026-09-25", code: 61, high: 18, low: 9 },
    { date: "2026-09-26", code: 2, high: 17, low: 8 }
  ], 3);
  assert.equal(days.length, 3);
  assert.equal(days[0].label, "TODAY");
  assert.equal(days[1].label, "TOMORROW");
  assert.ok(days[0].glyph);
});

test("chart points include temperature labels on ends and midpoint", () => {
  const points = Weather.chartPoints([
    { temperature: 10 },
    { temperature: 12 },
    { temperature: 11 },
    { temperature: 13 },
    { temperature: 14 }
  ], "metric", 120, 40);
  assert.equal(points.length, 5);
  assert.equal(points[0].label, true);
  assert.equal(points[2].label, true);
  assert.equal(points[4].label, true);
  assert.equal(points[1].label, false);
  assert.equal(points[0].temperature, 10);
  assert.equal(points[4].temperature, 14);
});

test("formats sun clock with minutes and cache keys", () => {
  assert.equal(Weather.sunClock("2026-09-25T07:00"), "7:00 am");
  assert.equal(Weather.sunClock("2026-09-24T19:02"), "7:02 pm");
  assert.equal(Weather.sunClock("2026-09-24T00:05"), "12:05 am");
  assert.equal(Weather.sunClock("2026-09-24T12:30"), "12:30 pm");
  assert.equal(Weather.sunClock(""), "—");
  assert.equal(Weather.cacheKey({ latitude: 47.6062, longitude: -122.3321 }), "47.6062_-122.3321");
  assert.equal(Weather.cacheFilePath({ latitude: 47.6062, longitude: -122.3321 }), "47.6062_-122.3321.json");
  assert.equal(Weather.cacheKey(null), "");
});
