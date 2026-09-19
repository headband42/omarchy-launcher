# Tiled Launcher

Omarchy launcher with the stock menu on the left and a 2×4 grid of app tiles
on the right. First iteration tiles are static launch buttons — a web app or
a regular app, no live data.

```
┌─────────────┬──────┬──────┬──────┬──────┐
│             │ app  │ app  │ app  │ app  │
│  Omarchy    ├──────┼──────┼──────┼──────┤
│  menu       │ app  │ app  │ app  │ app  │
└─────────────┴──────┴──────┴──────┴──────┘
```

## Why a fork

The stock `omarchy.menu` plugin owns its overlay window and centers a single
card. There is no public hook to embed that card in another layout, and
plugin packages cannot symlink into `/usr/share/omarchy`.

This plugin is a clone of `omarchy.menu` (`omarchy.clonedFrom`). That means:

- Super+Space, `omarchy menu …`, and the bar button keep working
- dmenu/input callers (`omarchy-menu-select`, etc.) still get the original
  centered card — tiles hide in those modes
- `MenuModel.js` and `BarWidget.qml` can be refreshed from Omarchy with
  `scripts/sync-upstream.sh`
- `Menu.qml` carries the layout change and needs a manual merge after a
  large upstream menu rewrite

## Install

From a git remote, once this repo is pushed:

```
omarchy plugin add <git-url> --enable --yes
```

For local development, point Omarchy at this checkout (the plugin *directory*
may be a symlink; files inside it may not):

```
ln -sfn "$PWD" ~/.config/omarchy/plugins/ande.launcher
omarchy-shell shell rescanPlugins
omarchy plugin enable ande.launcher
```

The bar button and Super+Space open this launcher. Super+Alt+Space opens the
stock Omarchy menu so a broken build does not take over the system.

After it opens, Space puts a large 1–8 on each tile; that number launches the
slot. Any other typing hides the tiles and searches the full menu. Escape
clears the numbers, then the search, then the launcher.

Disable this plugin to put the stock menu back on the bar:

```
omarchy plugin disable ande.launcher
```

## Tiles

A slot has two independent pieces:

- **Widget** — something built for this launcher (weather, stocks, …). Drop
  a folder in `widgets/<id>/` with `widget.json` and `Widget.qml`.
- **Opens** — the app or website a click launches. Unrelated to the widget.

If no widget is selected, the tile is just the icon and label for whatever
it opens.

Defaults live in [`tiles.json`](tiles.json). Override them with:

```
~/.config/omarchy/extensions/ande.launcher.json
```

| Field | Meaning |
| --- | --- |
| `widget` | Launcher widget id (`weather`, `stocks`, or omit for icon & link) |
| `label` | Caption |
| `desktop` | Desktop entry to open |
| `command` | Shell command to open |
| `url` | Opened with `omarchy-launch-webapp` |
| `icon` / `iconName` | Glyph or themed icon for icon-and-link tiles |

Included widgets: Icon & link, Weather, Stocks. Weather and Stocks are
visual for now; click still goes to the Opens target (defaults
weather.com and Yahoo Finance until you change them).

## Settings

The gear opens one window. Each slot: pick a **widget** from the launcher
catalog, then separately pick what it **opens** (installed apps from the
stock menu list, or a new web app). A stocks widget can open your
brokerage; a weather widget can open your preferred weather app.
