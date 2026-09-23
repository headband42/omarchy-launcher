# AGENTS.md

Omarchy plugin `ande.launcher`: the stock menu on the left, a 2×4 tile grid on the right. Quickshell and Qt 6 QML. Not a web app. There is no browser UI.

User-facing behavior is in [README.md](README.md). This file is how to change the code without breaking the fork.

## Ownership

| Path | Rule |
| --- | --- |
| `MenuModel.js`, `BarWidget.qml` | Copied from the installed Omarchy menu by `scripts/sync-upstream.sh`. Do not edit them here. A local edit is overwritten on the next sync. |
| `Menu.qml` | The fork. The tile grid lives in this file. After a sync, merge it by hand against `vendor/omarchy-menu/Menu.qml`. |
| `Tile.qml`, `TileGrid.qml`, `TileSettings.qml`, `TileModel.js`, `DesktopApps.qml`, `tiles.json` | Launcher-owned. |
| `widgets/<id>/` | One widget per folder. The catalog is a folder scan, not [`widgets.json`](widgets.json). That file is unread. |
| `~/.config/omarchy/extensions/ande.launcher/widgets/<id>/` | User widgets. Same id wins over the bundled copy. |
| `~/.config/omarchy/extensions/ande.launcher.json` | Live tile override. Do not write it unless the user asked. |

`scripts/sync-upstream.sh` reads `$OMARCHY_PATH` or `/usr/share/omarchy`. dmenu and input modes hide the tiles so `omarchy-menu-select` still gets the centered card. Keep that.

The plugin directory may be a symlink. Files inside it may not. Super+Alt+Space opens the stock menu when this build is broken.

## Widgets

A widget folder needs `widget.json` and `Widget.qml`. `scripts/list-widgets.py` publishes `id`, `qml`, and `dir`. Optional `defaultLabel`, `defaultCommand`, `defaultDesktop`, and `defaultUrl` are copied into **Opens** only when the slot has no launch target yet.

`Widget.qml` is an `Item` loaded by `TileGrid.qml`. The grid sets these when the item declares them:

- `tile` — resolved slot, including `tile.settings`
- `fontFamily`, `foreground` — menu theme. Fallbacks are `Style.font.menuFamily` and `Color.menu.text`
- `host` — `launchDefault`, `openFolder`, `openTerminal`, `openVolume`, `setEntryActive`, `dismiss`, `typeText`

Empty chrome launches Opens. A control the widget draws (a drive row, a calc key) needs its own `MouseArea` above that click. Set `host.setEntryActive(true)` while the widget is taking keys, and clear it on the way out.

`Text` uses `textFormat: Text.PlainText`. Glyphs are nerd-font characters in the menu font (the settings gear is ``).

## Settings panels

`Settings.qml` beside `Widget.qml` is the opt-in. `list-widgets.py` sets `settingsQml` only when that file exists. `TileSettings.qml` shows a gear on the slot, on the Widget row, and in the widget list, then loads the file.

The panel item may declare:

- `settings` — the slot’s current object. Persist with `host.save(settings)`. `null` or `{}` clears it.
- `tile`, `fontFamily`, `foreground`, `hoverFill`, `borderSpec`, `cornerRadius`
- `panelTitle` — non-empty string replaces the window title
- `handleEscape()` and `handleKey(event)` — return true when the panel consumed the key

`TileModel.js` stores `settings` only on a slot that has a widget. Choosing the same widget again keeps them. Choosing another widget, or Icon & link, drops them. Changing Opens does not. Time zones is the reference: `settings.zones` is up to three IANA ids, and the system clock is always shown.

## Logic and tests

Keep parsers, clock math, and tile updates in plain JavaScript or Python that the tests execute. QML JS in this repo is `var` and `function`, so the same file can run in QML and in Node. Guard `module.exports` with `typeof module`. Prefer testing the shipped source (see `widgets/calc/test_logic.cjs`, which slices functions out of `Widget.qml`) over a second copy.

From the repo root:

```
node --test test_tile_model.cjs widgets/calc/test_logic.cjs widgets/timezones/test_logic.cjs
python3 widgets/sysmon/test_sample.py
python3 widgets/disks/test_sample.py
python3 widgets/timezones/test_zones.py
```

Python helpers are stdlib only. Do not commit `__pycache__`.

To check QML, load it with `quickshell` where `qs.Commons` and `qs.Ui` resolve (they do next to an Omarchy `shell.qml`). `qmlscene` stops on the Quickshell imports. Do not restart the user’s shell unless they ask. `omarchy-shell shell rescanPlugins` picks up a new widget folder.

## Commits

Commit the work from each prompt before ending it. Match the log: one imperative sentence, then the why if it is not obvious. Leave bytecode caches untracked.
