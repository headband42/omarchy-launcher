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

  it("does not leave settings on a slot after the widget leaves", () => {
    const next = TileModel.applyWidget(clock, catalog[1]);
    assert.equal(next.widget, "weather");
    assert.equal(next.url, "https://weather.com");
    assert.equal(next.settings, undefined);
    assert.equal(next.widgetSettings, undefined);
    const icon = TileModel.applyWidget(clock, { id: "" });
    assert.equal(icon.label, "Time");
    assert.equal(icon.settings, undefined);
    assert.equal(icon.widgetSettings, undefined);
  });

  it("resets Opens to the new widget default when the widget type changes", () => {
    const weather = TileModel.applyWidget(clock, catalog[1]);
    assert.equal(weather.url, "https://weather.com");
    const calc = {
      id: "calc",
      name: "Calculator",
      defaultLabel: "Calc",
      defaultCommand: "uwsm-app -- omacalc"
    };
    const next = TileModel.applyWidget(
      { widget: "weather", label: "Weather", url: "https://weather.com", iconName: "weather" },
      calc
    );
    assert.equal(next.widget, "calc");
    assert.equal(next.command, "uwsm-app -- omacalc");
    assert.equal(next.url, undefined);
    assert.equal(next.desktop, undefined);
    assert.equal(next.iconName, undefined);
    // Widget with no default launch clears the previous Opens target.
    const zones = TileModel.applyWidget(next, catalog[0]);
    assert.equal(zones.widget, "timezones");
    assert.equal(zones.command, undefined);
    assert.equal(zones.url, undefined);
  });

  it("keeps Opens when the same widget is chosen again", () => {
    const custom = {
      widget: "weather",
      label: "Weather",
      url: "https://example.com/my-weather"
    };
    const next = TileModel.applyWidget(custom, catalog[1]);
    assert.equal(next.url, "https://example.com/my-weather");
  });
});

describe("saveWidgetSettings", () => {
  it("stores any widget's settings once and copies them to every slot", () => {
    const tiles = [
      { widget: "notes", label: "A" },
      { widget: "notes", label: "B" },
      { widget: "weather", label: "W" }
    ];
    const saved = TileModel.saveWidgetSettings(tiles, 3, null, "notes", { text: "hello" });
    assert.equal(saved.changed, true);
    assert.deepEqual(saved.widgetSettings, { notes: { text: "hello" } });
    assert.deepEqual(saved.tiles[0].settings, { text: "hello" });
    assert.deepEqual(saved.tiles[1].settings, { text: "hello" });
    assert.equal(saved.tiles[2].settings, undefined);
    const again = TileModel.saveWidgetSettings(saved.tiles, 3, saved.widgetSettings, "notes", { text: "hello" });
    assert.equal(again.changed, false);
    const moved = TileModel.applyWidget({ label: "Elsewhere" }, { id: "notes", name: "Notes" }, saved.widgetSettings);
    assert.deepEqual(moved.settings, { text: "hello" });
  });

  it("forgets a widget when the panel saves nothing", () => {
    const saved = TileModel.saveWidgetSettings(
      [{ widget: "notes", settings: { text: "hello" } }],
      1,
      { notes: { text: "hello" } },
      "notes",
      {}
    );
    assert.equal(saved.changed, true);
    assert.equal(saved.widgetSettings, null);
    assert.equal(saved.tiles[0].settings, undefined);
    assert.equal(TileModel.saveWidgetSettings([], 0, null, "", { text: "x" }).changed, false);
  });
});

describe("widget settings follow the widget", () => {
  const memory = TileModel.rememberWidget(null, "timezones", { zones: ["America/New_York"] });

  it("puts the saved zones on a different slot", () => {
    const moved = TileModel.applyWidget({ label: "Files", command: "gio open $HOME" }, catalog[0], memory);
    assert.equal(moved.widget, "timezones");
    assert.equal(moved.command, "gio open $HOME");
    assert.deepEqual(moved.settings, { zones: ["America/New_York"] });
    const shown = TileModel.resolveOne(moved, null, catalog, memory);
    assert.deepEqual(shown.settings, { zones: ["America/New_York"] });
  });

  it("shows the same zones on every slot that has the widget", () => {
    const tiles = [
      { widget: "timezones", label: "Time", settings: { zones: ["UTC"] } },
      { widget: "timezones", label: "Clock" }
    ];
    const resolved = TileModel.resolveAll(tiles, 2, null, catalog, memory);
    assert.deepEqual(resolved[0].settings, { zones: ["America/New_York"] });
    assert.deepEqual(resolved[1].settings, { zones: ["America/New_York"] });
  });

  it("forgets the zones when the panel clears them", () => {
    const cleared = TileModel.rememberWidget(memory, "timezones", null);
    assert.equal(cleared, null);
    const tiles = TileModel.applySettingsToTiles(
      [{ widget: "timezones", settings: { zones: ["America/New_York"] } }, { widget: "timezones", settings: { zones: ["UTC"] } }],
      2,
      "timezones",
      null
    );
    assert.equal(tiles[0].settings, undefined);
    assert.equal(tiles[1].settings, undefined);
    const moved = TileModel.applyWidget(null, catalog[0], cleared);
    assert.equal(moved.settings, undefined);
  });

  it("promotes settings that were stored on a slot", () => {
    const config = TileModel.normalizeConfig({
      columns: 4,
      rows: 2,
      tiles: [
        { widget: "timezones", label: "Time", settings: { zones: ["Asia/Tokyo"] }, widgetSettings: { timezones: { zones: ["UTC"] } } },
        null
      ]
    });
    assert.deepEqual(config.widgetSettings, { timezones: { zones: ["Asia/Tokyo"] } });
    assert.equal(config.tiles[0].widgetSettings, undefined);
    assert.deepEqual(config.tiles[1], null);
    const moved = TileModel.applyWidget(null, catalog[0], config.widgetSettings);
    assert.deepEqual(moved.settings, { zones: ["Asia/Tokyo"] });
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

describe("icon dock", () => {
  it("stores launch-only dock items and drops empties", () => {
    assert.deepEqual(TileModel.storedDock([
      { desktop: "discord", label: "Discord" },
      { command: "omarchy-launch-terminal", label: "Terminal", icon: "x" },
      { label: "noop" },
      null
    ]), [
      { desktop: "discord", label: "Discord" },
      { command: "omarchy-launch-terminal", label: "Terminal", icon: "x" }
    ]);
  });

  it("keeps dock through normalizeConfig", () => {
    const cfg = TileModel.normalizeConfig({
      columns: 4,
      rows: 2,
      tiles: [{ label: "Browser", command: "omarchy-launch-browser" }],
      dock: [{ desktop: "discord" }, { url: "https://example.com", label: "Example" }]
    });
    assert.equal(cfg.dock.length, 2);
    assert.equal(cfg.dock[0].desktop, "discord");
    assert.equal(cfg.dock[1].url, "https://example.com");
  });
});

describe("icon & link catalog entry", () => {
  it("puts Icon & link first in the scanned catalog", () => {
    const list = TileModel.withIconLink(catalog);
    assert.equal(list.length, catalog.length + 1);
    assert.equal(list[0].id, "");
    assert.equal(list[0].name, TileModel.ICON_LINK_NAME);
    assert.deepEqual(list.slice(1), catalog);
  });

  it("does not add it twice or touch the input", () => {
    const once = TileModel.withIconLink(catalog);
    assert.equal(TileModel.withIconLink(once).length, once.length);
    assert.equal(catalog.length, 2);
  });

  it("gives an empty or missing scan just Icon & link", () => {
    assert.deepEqual(TileModel.withIconLink([]), [TileModel.iconLinkWidget()]);
    assert.deepEqual(TileModel.withIconLink(null), [TileModel.iconLinkWidget()]);
  });

  it("names a slot without a widget the same way", () => {
    const resolved = TileModel.resolveOne({ label: "Browser", command: "omarchy-launch-browser" }, null, catalog, null);
    assert.equal(resolved.widgetName, TileModel.ICON_LINK_NAME);
  });
});

describe("widget links", () => {
  it("passes plain http and https links through", () => {
    assert.equal(TileModel.linkTarget("https://news.ycombinator.com/item?id=1"), "https://news.ycombinator.com/item?id=1");
    assert.equal(TileModel.linkTarget("  http://example.org/a#b  "), "http://example.org/a#b");
    assert.equal(TileModel.linkTarget("https://github.com/o/r/pull/7"), "https://github.com/o/r/pull/7");
  });

  it("refuses other schemes and anything a shell or a browser would read twice", () => {
    for (const bad of [
      "", "file:///etc/passwd", "javascript:alert(1)", "ftp://x.org/", "https://", "https:///path",
      "https://x.org/a b", "https://x.org/\"", "https://x.org/'", "https://x.org/<b>", "https://x.org/a\\b",
      "https://x.org/`id`", "https://x.org/\u0007", "https://x.org/\nrm", "-https://x.org/",
      "https://x.org/" + "a".repeat(2100), null, undefined
    ]) {
      assert.equal(TileModel.linkTarget(bad), "", JSON.stringify(bad));
    }
  });
});
