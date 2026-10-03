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

describe("widget picker", () => {
  const scan = [
    { id: "weather", name: "Weather", category: "Everyday", description: "Live conditions and radar." },
    { id: "sysmon", name: "System monitor", category: "System", description: "CPU, memory, GPU." },
    { id: "audio", name: "Audio", category: "System", description: "Output volume." },
    { id: "agenda", name: "Calendar", category: "Everyday", description: "Events from iCal links." },
    { id: "homebrew", name: "Homebrew", category: "Taps", description: "Outdated formulae." },
    { id: "loose", name: "Loose", description: "Says no category." }
  ];

  it("puts Icon & link first, then each section in order with names sorted", () => {
    const rows = TileModel.pickerRows(scan, "");
    const shape = rows.map((r) => (r.kind === "header" ? "# " + r.title : r.widget.id));
    assert.deepEqual(shape, ["", "# Everyday", "agenda", "weather", "# System", "audio", "sysmon", "# Taps", "homebrew", "# Other", "loose"]);
  });

  it("numbers only the rows that can be chosen", () => {
    const rows = TileModel.pickerRows(scan, "");
    const picks = rows.filter((r) => r.kind === "widget").map((r) => r.pick);
    assert.deepEqual(picks, [0, 1, 2, 3, 4, 5, 6]);
    assert.equal(TileModel.pickOf(rows, "sysmon"), 4);
    assert.equal(TileModel.pickOf(rows, ""), 0);
    assert.equal(TileModel.pickOf(rows, "gone"), 0);
  });

  it("ranks a name match above a description match and drops the rest", () => {
    const rows = TileModel.pickerRows(scan, "cal");
    assert.ok(rows.every((r) => r.kind === "widget"));
    assert.deepEqual(rows.map((r) => r.widget.id), ["agenda"]);
    assert.deepEqual(TileModel.pickerRows(scan, "o").map((r) => r.widget.id).slice(0, 1), ["audio"]);
  });

  it("needs every word, from any field", () => {
    assert.deepEqual(TileModel.pickerRows(scan, "system gpu").map((r) => r.widget.id), ["sysmon"]);
    assert.deepEqual(TileModel.pickerRows(scan, "everyday radar").map((r) => r.widget.id), ["weather"]);
    assert.deepEqual(TileModel.pickerRows(scan, "zzz"), []);
  });

  it("finds Icon & link by name", () => {
    assert.equal(TileModel.pickerRows(scan, "link")[0].widget.name, TileModel.ICON_LINK_NAME);
  });

  it("gives Icon & link no category and a missing one Other", () => {
    assert.equal(TileModel.widgetCategory(TileModel.iconLinkWidget()), "");
    assert.equal(TileModel.widgetCategory({ id: "x" }), TileModel.OTHER_CATEGORY);
    assert.equal(TileModel.widgetCategory({ id: "x", category: " Sports " }), "Sports");
  });

  it("gives every bundled widget a known category", () => {
    const fs = require("fs");
    const dir = path.join(__dirname, "widgets");
    for (const name of fs.readdirSync(dir)) {
      const meta = path.join(dir, name, "widget.json");
      if (name.startsWith("_") || !fs.existsSync(meta)) continue;
      const widget = JSON.parse(fs.readFileSync(meta, "utf8"));
      assert.ok(TileModel.WIDGET_CATEGORIES.includes(widget.category), name + ": " + widget.category);
    }
  });
});

describe("settings home arrows", () => {
  // 4 x 2: slots 0-7, the dock is 8.
  const move = (at, dx, dy, column) => TileModel.homeMove(at, dx, dy, 4, 2, column || 0);

  it("steps left and right in slot order, wrapping", () => {
    assert.equal(move(0, 1, 0), 1);
    assert.equal(move(3, 1, 0), 4);
    assert.equal(move(7, 1, 0), 0);
    assert.equal(move(0, -1, 0), 7);
    assert.equal(move(8, 1, 0), 8);
  });

  it("keeps the column going up and down, through the dock", () => {
    assert.equal(move(1, 0, 1), 5);
    assert.equal(move(5, 0, 1), 8);
    assert.equal(move(5, 0, -1), 1);
    assert.equal(move(1, 0, -1), 8);
    assert.equal(move(8, 0, 1, 2), 2);
    assert.equal(move(8, 0, -1, 2), 6);
  });

  it("recovers from an index out of range", () => {
    assert.equal(move(-3, 0, 1), 4);
    assert.equal(move(99, 1, 0), 1);
    assert.equal(TileModel.homeMove(0, 0, 1, 0, 0, 0), 1);
  });
});

describe("what a slot opens", () => {
  const apps = { find: (desktop) => (desktop === "firefox" ? { appId: "firefox", name: "Firefox", iconName: "firefox" } : null) };
  const label = (tile) => TileModel.launchLabel(TileModel.resolveOne(tile, apps, catalog, null));

  it("names the app, not the widget, once Opens is changed", () => {
    assert.equal(label({ widget: "weather", label: "Weather", desktop: "firefox" }), "Firefox");
    assert.equal(label({ widget: "weather", label: "Weather", url: "https://www.weather.com/today" }), "weather.com");
  });

  it("keeps an icon-and-link slot's own label", () => {
    assert.equal(label({ label: "Terminal", command: "omarchy-launch-terminal" }), "Terminal");
    assert.equal(label({ desktop: "firefox" }), "Firefox");
  });

  it("drops the wrappers in front of a command", () => {
    assert.equal(label({ widget: "weather", command: "uwsm-app -- xdg-terminal-exec btop" }), "btop");
    assert.equal(label({ widget: "weather", command: "omarchy-launch-tui lazydocker" }), "lazydocker");
    assert.equal(label({ widget: "weather", label: "Browser", command: "omarchy-launch-browser" }), "browser");
  });

  it("is empty when the slot opens nothing", () => {
    assert.equal(TileModel.launchLabel(TileModel.resolveOne(null, apps, catalog, null)), "");
    assert.equal(TileModel.launchLabel({ widget: "weather" }), "");
  });
});
