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
  assert.equal(Weather.storedSettings({ units: "metric" }).atmosphere, true);
  assert.equal(Weather.settingsWith({ units: "metric" }, "atmosphere", false).atmosphere, false);
  assert.equal(Weather.settingsWith({ units: "metric" }, "atmosphere", false).units, "metric");
});

test("panels default on, toggle off, and never all hide", () => {
  assert.deepEqual(Weather.normalizedSettings({}).panels, ["hours", "details", "week", "radar", "air", "sun"]);
  assert.equal("hiddenPanels" in Weather.storedSettings(Weather.normalizedSettings({})), false);

  const noRadar = Weather.togglePanel({ units: "metric" }, "radar");
  assert.deepEqual(noRadar.hiddenPanels, ["radar"]);
  assert.equal(noRadar.units, "metric");
  assert.deepEqual(Weather.normalizedSettings(noRadar).panels, ["hours", "details", "week", "air", "sun"]);
  assert.equal("hiddenPanels" in Weather.togglePanel(noRadar, "radar"), false);

  // Unknown ids and duplicates are dropped; order follows the panel list.
  assert.deepEqual(Weather.hiddenPanels(["sun", "bogus", "hours", "sun"]), ["hours", "sun"]);

  let only = { hiddenPanels: ["hours", "details", "week", "radar", "air"] };
  assert.deepEqual(Weather.normalizedSettings(only).panels, ["sun"]);
  assert.deepEqual(Weather.togglePanel(only, "sun").hiddenPanels, only.hiddenPanels);

  // Hand-edited settings that hide everything still show Hours.
  assert.deepEqual(Weather.normalizedSettings({ hiddenPanels: Weather.panelIds() }).panels, ["hours"]);
  assert.equal(Weather.panelTitle("air"), "AIR QUALITY");
});

test("radar range picks a zoom and stores only the non-default", () => {
  assert.equal(Weather.normalizedSettings({}).radarZoom, 6);
  assert.equal(Weather.normalizedSettings({ radarRange: "regional" }).radarZoom, 5);
  assert.equal(Weather.normalizedSettings({ radarRange: "galactic" }).radarRange, "local");
  assert.equal(Weather.settingsWith({}, "radarRange", "regional").radarRange, "regional");
  assert.equal("radarRange" in Weather.settingsWith({ radarRange: "regional" }, "radarRange", "local"), false);
  // Other changes keep it.
  assert.equal(Weather.togglePanel({ radarRange: "regional" }, "sun").radarRange, "regional");
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
  assert.equal(points[0].x, 20);
  assert.equal(points[2].x, 100);
  assert.ok(points.every(point => point.y >= 7 && point.y <= 33));
  const padded = Weather.chartPoints([{ temperature: 10 }, { temperature: 20 }], "metric", 100, 50, 14, 4);
  assert.equal(padded[1].y, 14);
  assert.equal(padded[0].y, 46);
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

test("week range bars span the coldest low to the warmest high", () => {
  const days = [{ high: 20, low: 10 }, { high: 25, low: 12 }, { high: null, low: 5 }];
  assert.deepEqual(Weather.temperatureSpan(days), { low: 5, high: 25 });
  assert.equal(Weather.spanOffset({ low: 5, high: 25 }, 25), 0);
  assert.equal(Weather.spanOffset({ low: 5, high: 25 }, 15), 0.5);
  assert.equal(Weather.spanOffset({ low: 5, high: 25 }, -40), 1);
  assert.equal(Weather.temperatureSpan([]), null);
  assert.equal(Weather.temperatureColor(-30), "#7aa2ff");
  assert.equal(Weather.temperatureColor(50), "#eb5757");
  assert.match(Weather.temperatureColor(21), /^#[0-9a-f]{6}$/);
  assert.equal(Weather.dailyDays([{ date: "2026-09-24", code: 61, high: 18, low: 9, precipProbability: 70 }], 1)[0].precipProbability, 70);
});

test("air quality bands, scale position, and pollen", () => {
  assert.equal(Weather.aqiBand(30).label, "Good");
  assert.equal(Weather.aqiBand(51).label, "Moderate");
  assert.equal(Weather.aqiBand(120).index, 2);
  assert.equal(Weather.aqiBand(800).label, "Hazardous");
  assert.equal(Weather.aqiBand(null), null);
  assert.equal(Weather.aqiPosition(0), 0);
  assert.ok(Math.abs(Weather.aqiPosition(50) - 1 / 6) < 1e-9);
  assert.ok(Math.abs(Weather.aqiPosition(250) - 4.5 / 6) < 1e-9);
  assert.equal(Weather.aqiPosition(900), 1);
  assert.equal(Weather.concentration(2.46), "2.5");
  assert.equal(Weather.concentration(44.4), "44");
  assert.equal(Weather.concentration(null), "—");
  assert.deepEqual(Weather.topPollen({ grass: 24, birch: 3 }), { name: "grass", amount: 24, level: "Moderate" });
  assert.equal(Weather.topPollen({}), null);
  assert.equal(Weather.pollenLevel(0.2), "None");
});

test("sun position, countdowns, and daylight change", () => {
  const today = { sunrise: "2026-09-30T07:40", sunset: "2026-09-30T19:20" };
  const tomorrow = { sunrise: "2026-10-01T07:41" };
  const noon = Weather.sunState("2026-09-30T13:30", today, tomorrow);
  assert.equal(noon.day, true);
  assert.equal(noon.next, "Sunset");
  assert.equal(noon.until, 350);
  assert.equal(noon.progress, 0.5);
  const dawn = Weather.sunState("2026-09-30T06:40", today, tomorrow);
  assert.equal(dawn.day, false);
  assert.equal(dawn.until, 60);
  const night = Weather.sunState("2026-09-30T23:41", today, tomorrow);
  assert.equal(night.next, "Sunrise");
  assert.equal(night.until, 480);
  assert.ok(isNaN(Weather.sunState("", today, tomorrow).until));
  assert.equal(Weather.duration(712), "11h 52m");
  assert.equal(Weather.duration(40), "40m");
  assert.equal(Weather.daylightChange(42000, 41830), "\u22123m");
  assert.equal(Weather.daylightChange(42000, 42048), "+48s");
  assert.equal(Weather.daylightChange(0, 42048), "");
});

test("moon phase matches known new and full moons", () => {
  const full = Weather.moonPhase(Date.UTC(2024, 0, 25, 17, 54));
  assert.equal(full.name, "Full moon");
  assert.equal(full.glyph, "\ue39b");
  assert.equal(full.illumination, 100);
  const fresh = Weather.moonPhase(Date.UTC(2024, 0, 11, 11, 57));
  assert.equal(fresh.name, "New moon");
  assert.equal(fresh.glyph, "\ue38d");
  // A mean cycle lands within about half a day of the true quarter.
  const quarter = Weather.moonPhase(Date.UTC(2024, 0, 18, 3, 52));
  assert.ok(Math.abs(quarter.step - 7) <= 1);
  assert.ok(Math.abs(quarter.illumination - 50) <= 12);
  assert.equal(Weather.moonPhase(Date.UTC(2024, 0, 21)).name, "Waxing gibbous");
});

test("radar tiles centre the location and frames read as ages", () => {
  const radar = { tileSize: 256, columns: 3, offset: { x: 1.5, y: 1.25 } };
  const tiles = Weather.radarTiles(radar, 200, 100);
  assert.equal(tiles.length, 9);
  assert.deepEqual(tiles[0], { index: 0, x: -284, y: -270 });
  assert.deepEqual(tiles[4], { index: 4, x: -28, y: -14 });
  // The location (1.5, 1.25 tiles in) lands on the view's centre.
  assert.equal(tiles[0].x + 1.5 * 256, 100);
  assert.equal(tiles[0].y + 1.25 * 256, 50);
  assert.deepEqual(Weather.radarTiles(null, 200, 100), []);
  const now = Date.UTC(2026, 8, 30, 12, 0);
  assert.equal(Weather.frameAge(now / 1000 - 60, now), "now");
  assert.equal(Weather.frameAge(now / 1000 - 20 * 60, now), "20 min ago");
  assert.equal(Weather.frameAge(now / 1000 - 70 * 60, now), "1 hr 10 min ago");
  assert.equal(Weather.frameAge(now / 1000 - 61 * 60, now), "1 hr ago");
});

test("hour columns lead with current conditions", () => {
  const current = { temperature: 20, code: 2, isDay: true };
  const hourly = [{ time: "2026-09-24T11:00", temperature: 21 }, { time: "2026-09-24T12:00", temperature: 22 }];
  const columns = Weather.hourColumns(current, hourly, 2);
  assert.equal(columns.length, 2);
  assert.equal(columns[0].time, "now");
  assert.equal(columns[0].precipProbability, null);
  assert.equal(columns[1].temperature, 21);
  assert.equal(Weather.hourColumns(null, hourly, 5).length, 2);
  assert.equal(Weather.hourColumns(current, hourly, 0).length, 0);
});
