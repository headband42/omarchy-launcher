#!/usr/bin/env node
// Per-slot widget settings. Stdlib only.
//
// Run from the repo root:  node --test test_tile_model.cjs

const { describe, it } = require("node:test");
const assert = require("node:assert/strict");
const path = require("path");

const TileModel = require(path.join(__dirname, "TileModel.js"));

const catalog = [
  { id: "timezones", name: "Time zones", qml: "/widgets/timezones/Widget.qml", settingsQml: "/widgets/timezones/Settings.qml", defaultLabel: "Time" },
  { id: "weather", name: "Weather", defaultLabel: "Weather", defaultUrl: "https://weather.com" }
];

const clock = {
  widget: "timezones",
  label: "Time",
  settings: { zones: ["America/New_York"] }
};

describe("stored settings", () => {
  it("keeps a plain settings object on a widget slot", () => {
    assert.deepEqual(TileModel.storedTile(clock).settings, { zones: ["America/New_York"] });
  });

  it("drops settings that have no widget to read them", () => {
    assert.equal(TileModel.storedTile({ settings: { zones: ["UTC"] } }), null);
    assert.deepEqual(TileModel.storedTile({ label: "Time", settings: { zones: ["UTC"] } }), { label: "Time" });
  });

  it("rejects settings that are not a JSON object", () => {
    assert.equal(TileModel.copySettings(null), null);
    assert.equal(TileModel.copySettings(["UTC"]), null);
    assert.equal(TileModel.copySettings({}), null);
    assert.equal(TileModel.storedTile({ widget: "timezones", settings: ["UTC"] }).settings, undefined);
  });
});

describe("applyWidget", () => {
  it("keeps settings when the same widget is chosen again", () => {
    const next = TileModel.applyWidget(clock, { id: "timezones", name: "Time zones", defaultLabel: "Time" });
    assert.equal(next.widget, "timezones");
    assert.deepEqual(next.settings, { zones: ["America/New_York"] });
  });

  it("hides settings when the widget changes and restores them when it returns", () => {
    const next = TileModel.applyWidget(clock, catalog[1]);
    assert.equal(next.widget, "weather");
    assert.equal(next.url, "https://weather.com");
    assert.equal(next.settings, undefined);
    assert.deepEqual(next.widgetSettings.timezones, { zones: ["America/New_York"] });
    const back = TileModel.applyWidget(next, catalog[0]);
    assert.equal(back.widget, "timezones");
    assert.deepEqual(back.settings, { zones: ["America/New_York"] });
  });

  it("remembers settings when the slot goes back to icon and link", () => {
    const next = TileModel.applyWidget(clock, { id: "" });
    assert.equal(next.label, "Time");
    assert.equal(next.widget, undefined);
    assert.equal(next.settings, undefined);
    assert.deepEqual(next.widgetSettings.timezones, { zones: ["America/New_York"] });
    const back = TileModel.applyWidget(next, catalog[0]);
    assert.deepEqual(back.settings, { zones: ["America/New_York"] });
  });

  it("remembers settings when the slot is cleared", () => {
    const cleared = TileModel.clearedTile(clock);
    assert.equal(TileModel.isEmptyTile(cleared), true);
    assert.deepEqual(cleared.widgetSettings.timezones, { zones: ["America/New_York"] });
    const resolved = TileModel.resolveOne(cleared, null, catalog);
    assert.equal(resolved.empty, true);
    const back = TileModel.applyWidget(cleared, catalog[0]);
    assert.equal(back.widget, "timezones");
    assert.deepEqual(back.settings, { zones: ["America/New_York"] });
  });
});

describe("applySettings", () => {
  it("replaces and clears the slot settings", () => {
    const next = TileModel.applySettings(clock, { zones: ["Asia/Tokyo", "Europe/London"] });
    assert.deepEqual(next.settings, { zones: ["Asia/Tokyo", "Europe/London"] });
    assert.equal(next.widget, "timezones");
    const cleared = TileModel.applySettings(next, null);
    assert.equal(cleared.settings, undefined);
    assert.equal(cleared.widget, "timezones");
    assert.equal(cleared.widgetSettings, undefined);
    const removed = TileModel.applyWidget(cleared, { id: "" });
    const back = TileModel.applyWidget(removed, catalog[0]);
    assert.equal(back.settings, undefined);
  });

  it("does not attach settings to a slot with no widget", () => {
    assert.deepEqual(
      TileModel.applySettings({ label: "Browser", command: "omarchy-launch-browser" }, { zones: ["UTC"] }),
      { label: "Browser", command: "omarchy-launch-browser" }
    );
  });
});

describe("applyLaunch", () => {
  it("keeps widget settings when Opens changes", () => {
    const next = TileModel.applyLaunch(clock, { url: "https://time.is", label: "Time" });
    assert.equal(next.url, "https://time.is");
    assert.deepEqual(next.settings, { zones: ["America/New_York"] });
  });
});

describe("resolveOne", () => {
  it("passes settings and the panel path through to the tile", () => {
    const resolved = TileModel.resolveOne(clock, null, catalog);
    assert.equal(resolved.widgetName, "Time zones");
    assert.equal(resolved.settingsQml, "/widgets/timezones/Settings.qml");
    assert.deepEqual(resolved.settings, { zones: ["America/New_York"] });
    assert.equal(resolved.empty, false);
  });

  it("leaves an empty slot without a panel", () => {
    const resolved = TileModel.resolveOne(null, null, catalog);
    assert.equal(resolved.empty, true);
    assert.equal(resolved.settingsQml, "");
    assert.deepEqual(resolved.settings, {});
  });
});
