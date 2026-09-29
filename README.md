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

## Widgets

A widget is a folder with `widget.json` and `Widget.qml`. Bundled widgets
live in [`widgets/`](widgets/). Extra widgets go in:

```
~/.config/omarchy/extensions/ande.launcher/widgets/<id>/
```

Install one with `scripts/install-widget.sh <dir-or-git-url>`. The catalog
is a folder scan (user dir wins on the same id), plus **Icon & link**.

`widget.json` can set `defaultCommand`, `defaultDesktop`, or `defaultUrl`.
Assigning that widget to an empty slot copies the default into **Opens**.
Clicking unused chrome on the tile launches Opens. Controls drawn by the
widget (a drive row, a calc key) keep their own clicks.

A widget can include `Settings.qml`. That file is its settings panel.
The settings page puts a gear beside every widget that has one. The panel
stores plain options on the widget, and `Widget.qml` reads them back from
`tile.settings`.

Bundled:

| Id | What it shows | Default click |
| --- | --- | --- |
| `sysmon` | CPU, RAM, GPU, VRAM bars | `btop` in a terminal |
| `sysdisk` | CPU, RAM, GPU plus drive usage in one tile | `btop` in a terminal |
| `disks` | Mounted drives; USB appears while open | Files; click a row for that folder, right-click for a terminal |
| `calc` | Keypad | `omacalc` |
| `weather` | Live forecast with disk cache, precip bars, temp curve, 5-day strip, and roomy stats (gusts/pressure/visibility) | weather.com |
| `stocks` | Placeholder | Yahoo Finance |
| `timezones` | Local time, plus up to 3 other clocks | none until Opens is set |
| `mlb` | Favorite club: score, count, division standings, winning and losing pitchers, and the next starter. No club, or a club out of the playoffs, shows live games | That game on MLB Gameday |
| `nfl` | Favorite club: the live score with its quarter, clock, down, and field position on a field strip, then the next game, the record, form, point differential, and playoff seed. No club shows the week's games | That game on NFL.com |

## Tiles

A slot has two independent pieces:

- **Widget** — a launcher widget from the catalog, or Icon & link.
- **Opens** — the app or website a click on empty chrome launches.

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
| `settings` | Widget options shown on this slot. Time zones stores `zones`: up to 3 time zone ids, and weather stores a location plus units; both follow the widget |

Weather updates from Open-Meteo. On taller tiles the chart shows rain probability bars under the temperature curve, first/mid/last hour labels, gusts and pressure in the stats grid, and the next five days. With no saved city, it uses an approximate location once per launcher session; the settings panel can replace that with a city, postal code, or explicit “City, Country” search. A click still launches whatever Opens is set to.

## Settings

The gear at the edge of the launcher opens one window. Each slot: pick a
**widget** from the launcher catalog, then separately pick what it
**opens** (installed apps from the stock menu list, or a new web app). A
stocks widget can open your brokerage; a weather widget can open your
preferred weather app.

A widget that ships a settings panel has its own gear on that slot, on
the widget row, and in the widget list. Whatever that panel saves follows
the widget, not the slot: move it and the same settings come with it.
Clearing them in the panel forgets them. The NFL panel stores one club out of the 32. The tile ships a logo per
club. A live game reads like a scoreboard: logo, score, and the quarter
and clock in the middle over the down, the yards to go, and where the
ball is. Under that is a field strip with the two teams marked where they
actually stand, and the line of scrimmage between them, because a
football tile without field position is just two numbers. The panel can
hide any of the three blocks and switch the reset line between a
countdown and a calendar day.

The time zones panel is the
first of these. The tile always shows this computer’s clock, and the
panel adds up to three more. Each one can have its own label, and the
picker shows the zone name and current UTC offset. The weather panel stores
one location and either imperial or metric units. The MLB panel stores
one favorite club. Leave it empty and the tile shows live games.
