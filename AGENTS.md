# AGENTS.md

Omarchy plugin `ande.launcher`. Stock menu on the left, a 2×4 tile grid on the right. Quickshell / Qt 6 QML. Not a web app. There is no browser to open.

[README.md](README.md) is the user-facing description. It still says this plugin is an `omarchy.clonedFrom` clone. That is stale. Do not put `clonedFrom` back.

## What this is

We forked the stock menu because its card cannot be embedded. The packaged menu under `/usr/share/omarchy` is untouched. This repo is a separate plugin, installed here as a symlink:

```
~/.config/omarchy/plugins/ande.launcher -> this checkout
```

The plugin *directory* may be a symlink. Files inside it may not. Omarchy’s plugin validator rejects internal symlinks.

Keybindings live in `~/.config/hypr/bindings.lua`, not in this repo:

- Super+Space toggles `ande.launcher`
- Super+Alt+Space toggles the stock `omarchy.menu`

Do not steal Super+Alt+Space. A broken build must leave the original launcher usable. Do not edit `/usr/share/omarchy`.

`keepLoaded` is false so a save is picked up on the next open. `omarchy-shell shell rescanPlugins` reloads plugin code. `omarchy restart shell` restarts the whole shell. Do not restart the user’s shell unless they ask, or unless a QML type failed to load and a rescan is not enough.

## Version

Bump `manifest.json` `version` on every change a user can see or that fixes a behavior bug. Later sessions added time zones, sysdisk, and widget settings without moving it, so the number no longer matches the tree. Patch for a fix, minor for a widget or a settings panel.

## Ownership

| Path | Rule |
| --- | --- |
| `MenuModel.js` | Copied from the installed Omarchy menu by `scripts/sync-upstream.sh`. Do not edit it. The next sync overwrites it. |
| `BarWidget.qml` | Same copy, **except** two lines the sync will clobber: `moduleName: "ande.launcher"` and the left-click command `omarchy-shell shell toggle ande.launcher …`. After a sync, put those back. Stock `BarWidget.qml` toggles `omarchy.menu`. |
| `Menu.qml` | The fork. Layout, Space-hint keys, and the app-launch call live here. After a sync, merge by hand against `vendor/omarchy-menu/Menu.qml`. |
| `Tile*.qml`, `TileModel.js`, `DesktopApps.qml`, `tiles.json` | Ours. |
| `widgets/<id>/` | One widget per folder. [`widgets.json`](widgets.json) is not read. |
| `widgets/_kit/` | Shared by widgets, not a widget: `Poller`, `WidgetHeader`, `kit.js`, and the system and disk samplers that `sysmon`, `disks`, and `sysdisk` run. `list-widgets.py` skips any `_` folder. |
| `~/.config/omarchy/extensions/ande.launcher/widgets/<id>/` | Installed widgets. Same id wins over the bundled copy. |
| `~/.config/omarchy/extensions/ande.launcher.json` | The user’s live slots. Do not write it unless they asked. |

`scripts/sync-upstream.sh` reads `$OMARCHY_PATH` or `/usr/share/omarchy`. dmenu and input modes hide the tiles so `omarchy-menu-select` still gets the centered card. Keep that.

## Two different things in a slot

A slot is not “an app.”

- **Widget** is what is drawn. It is a folder we ship or the user installs. Icon & link means no widget.
- **Opens** is what a click on empty chrome launches (`desktop`, `command`, or `url`).

`TileModel.applyWidget` copies `defaultCommand` / `defaultDesktop` / `defaultUrl` only when the slot has no launch target yet. Changing Opens does not touch settings.

Do not store a widget’s nerd-font glyph on the tile. Icon-and-link tiles use the launch target’s desktop `Icon=`. A leftover glyph is why Stocks stayed on screen after the slot was switched to Orca Slicer.

## Clicks

`TileGrid` puts a `MouseArea` **behind** the `Loader`. Empty chrome hits that and calls `host.launchDefault()`. A control the widget draws needs its own `MouseArea` on top (a drive row, a calc key). Hint badges sit above both.

`host` may declare:

- `launchDefault()` — Opens
- `openFolder(path)` / `openVolume(path, device)` — `scripts/open-volume.sh`, which uses `gio open` (the desktop’s default file manager). Do not call `omarchy-launch-nautilus`.
- `openTerminal(path)` — `xdg-terminal-exec --dir=`. Do not call `omarchy-launch-terminal`; it ignores the directory and uses the active terminal’s cwd.
- `openUrl(url)` — `omarchy-launch-webapp` for an `https://www.mlb.com/` or `https://mlb.com/` link. The MLB tile uses it so a click opens that game on Gameday.
- `setEntryActive(bool)` — while true, keystrokes stay in the widget instead of the menu search. Clear it on the way out.
- `dismiss()`, `typeText()`

Space on an empty filter shows 1–8 on the tiles. A digit launches that slot. Any other printable character hides the grid and searches the menu. Claim Space with `Keys.onShortcutOverride` before it becomes filter text. `showTiles` is false whenever `filterText` is non-empty.

## Apps list

`DesktopApps.qml` is the only app catalog. It feeds the left Apps submenu, tile icons, and the Opens picker. Do not add a second list.

This plugin is third-party. `root.appLibrary` is a JS facade, not the real `AppLibrary`. `DesktopEntry` objects usually do not survive that boundary, so `row.entry.icon` comes back empty and `appLibrary.launch` can no-op. Read entries here, in-process, from `DesktopEntries`. Launch with `desktopApps.launch` (entry `execute()`, then `gtk-launch`). Do not gate a click on `if (root.appLibrary)`.

The stock menu hides ids from `launcher.hides` and `hidden-entries.sh` (Avahi browsers, and similar). `DesktopApps` applies that same filter. A fallback that only skips `NoDisplay` will show apps the stock list does not.

New installs show up because `DesktopEntries` changes, not because we copy `.desktop` files into the plugin. Tiles are a pinned subset. Installing Firefox adds it to Apps and to the Opens picker. It does not occupy a tile until the user assigns one.

Nothing in the sensors or the disk list is named after this machine. Disks come from `lsblk` / `findmnt` in `widgets/_kit/disks.py`. CPU, memory, and GPU come from `widgets/_kit/system.py`. GPU comes from `nvidia-smi` if it exists, otherwise sysfs. Do not hardcode `/dev/nvme…`, model strings, or this user’s home path.

## Widgets

`widget.json` + `Widget.qml`. Optional `Settings.qml`. `scripts/list-widgets.py` adds `qml`, `dir`, and `settingsQml`. `scripts/install-widget.sh` copies a folder or a git URL into the user widgets dir and links `_kit` next to it, so an installed widget imports `../_kit` the same way a bundled one does. A widget copied there by hand has no `_kit` until the installer runs once.

Next to those, a widget folder has at most:

- `<id>.py`: the sampler. Stdlib only. It prints one JSON object, takes its settings as flags, and runs directly (`main()` under `if __name__ == "__main__"`). Tests import the same file. No wrapper scripts.
- `<id>.js`: logic that `Widget.qml` or `Settings.qml` imports and node tests `require`. A second file is fine when it is a separate concern (`mlb/colors.js`).
- `test_<id>.py`, `test_*.cjs`.

`Widget.qml` is an `Item`. The grid sets `tile` (including `tile.settings`), `fontFamily`, `foreground`, and `host` only if the item declares them.

`Settings.qml` is loaded by `TileSettings.qml`. The panel may declare `settings`, `tile`, `fontFamily`, `foreground`, `hoverFill`, `borderSpec`, `cornerRadius`, `panelTitle`, `handleEscape()`, and `handleKey(event)`.

Saving is the same for every panel. Assign `settings`, or call `host.save(settings)`. Both go through `TileModel.saveWidgetSettings`. The object is stored on the config under `widgetSettings[widgetId]`, not on the slot. Adding that widget to any slot restores it, and every slot showing it gets the same object. `null` or `{}` forgets it. Do not write the config file from the widget. A `widgetSettings` object left on an old slot is promoted by `normalizeConfig`. Time zones is the reference: `settings.zones` is up to three entries, either an IANA id or `{ id, label }` when the user set a custom label. The system clock is always shown. MLB stores `teamId`. An empty object shows the live slate, including during the playoffs when that club has no postseason games.

Poll a sampler with `Poller` (`import "../_kit"`):

```qml
Poller {
  id: poller
  script: Qt.resolvedUrl("battery.py")   // resolve it here, next to Widget.qml
  args: ["--path", root.repoPath]         // a change throws away a reply in flight
  interval: 15000
  active: root.visible
  onSampled: function(data) { if (data) root.sample = data }   // null on bad output
}
```

Call `poller.pollSoon()` after an action so the tile re-reads once it lands. Draw the dot-and-caption row with `WidgetHeader`. A widget that still needs its own `Process` (weather's cache phases, a settings search) builds the path with `Kit.localPath(Qt.resolvedUrl(...))` from `_kit/kit.js`, and reads `StdioCollector { id: out; waitForEnd: true }` as `out.text`. It is a property. `text()` throws, the parse fails, and the tile stays at zeros or blank. That bug has already shipped once.

`Text` uses `textFormat: Text.PlainText`. Glyphs are nerd-font characters in the menu font (the settings gear is ``).

## Logic and tests

Keep parsers, clock math, and tile updates in plain JavaScript or Python that the tests execute. QML JS in this repo is `var` and `function`, so the same file can run in QML and in Node. Guard `module.exports` with `typeof module`. QML imports the `.js` file and the test `require`s that same file. A `.js` file can read the global `Qt` (see `calc.js`); its test sets `globalThis.Qt` first. Do not test code by slicing it out of `Widget.qml` between marker strings. Moving a function breaks the test.

From the repo root:

```
scripts/test.sh                  # every test_*.cjs and test_*.py
scripts/test.sh widgets/weather  # just one widget
```

The runner finds tests by name, so a new widget's tests run as soon as they exist. Do not keep a list of test files anywhere.

Python helpers are stdlib only. Do not commit `__pycache__`.

To check QML, load it with `quickshell` where `qs.Commons` and `qs.Ui` resolve. `qmlscene` stops on the Quickshell imports.

## Commits

Commit the work from each prompt before ending it. One imperative sentence, then the why if it is not obvious. Bump `manifest.json` `version` in that same commit when the behavior changed. Leave bytecode caches untracked.
