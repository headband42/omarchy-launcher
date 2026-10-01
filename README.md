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

Shared pieces live in [`widgets/_kit/`](widgets/_kit/). `import "../_kit"`
gives a widget `Poller`, which runs its Python sampler on an interval
while the tile is showing, `WidgetHeader`, the status dot and caption, and
`IconButton`, a round glyph button or labeled pill that keeps its own click.
The installer links `_kit` into the user widgets folder, so an installed
widget imports it the same way.

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
| `weather` | Current conditions over rotating Hours, Details, Week, Radar, Air quality, and Sun & moon panels, each one switchable in settings | weather.com |
| `stocks` | A watchlist styled after [Omafinance](https://github.com/mohamedmansour/omafinance): symbol, name, the day's sparkline, price, and a change pill. Follows Omafinance's watchlist until the panel picks up to 6 tickers. Out of hours it shows the latest pre- or post-market price | That ticker on Yahoo Finance; the header opens Yahoo Finance |
| `timezones` | Local time, plus up to 3 other clocks | none until Opens is set |
| `mlb` | Favorite club: score, count, division standings, winning and losing pitchers, and the next starter. No club, or a club out of the playoffs, shows every live game as a card with the inning, bases, and outs, plus the series score in the postseason | That game on MLB Gameday |
| `spotify` | What [OmaSpotify](https://github.com/jeremylanger/omaspotify) is playing on this computer: artwork, track, seek bar, shuffle, previous, play/pause, next, repeat. Read over MPRIS, so the official Spotify client works too | OmaSpotify's full player |
| `repo` | One git repository: branch with ahead and behind, changed-file chips, two weeks of commits as bars, and the latest commits with unpushed ones highlighted. Footer buttons open a terminal or the folder and fetch. The gear lists the repositories in your home folder | lazygit in that repository |
| `docker` | Running, unhealthy, paused, and stopped counts, then containers with compose project, image, ports, CPU, and memory. Hover a row to start, stop, or restart it. Without access to the socket it says what the daemon is doing, and it never wakes an idle socket-activated daemon | lazydocker |
| `todo` | A checklist in a text file, plain or Markdown: tick, add, rename, remove, and clear finished tasks. In a Markdown file only checkbox lines are tasks; headings and notes are written back as they were | none until Opens is set |

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

Weather updates from Open-Meteo, which also supplies air quality (US AQI, PM2.5, PM10, ozone, NO₂, and pollen in Europe). The lower half of the tile rotates through its panels: the next hours on a temperature curve, a card per reading, the week as low-to-high bars, the last hour of RainViewer radar over NASA's night lights with the distance to the nearest rain, air quality, and the sun's arc with the moon phase. The background follows the weather: a warm glow when clear, stars at night, drifting fog, rain, sleet, or snow, and lightning in storms. A panel's pill pauses on it. With no saved city, it uses an approximate location once per launcher session; the settings panel can replace that with a city, postal code, or explicit “City, Country” search. A click still launches whatever Opens is set to.

## Settings

The gear at the edge of the launcher opens one window. Each slot: pick a
**widget** from the launcher catalog, then separately pick what it
**opens** (installed apps from the stock menu list, or a new web app). A
stocks widget can open your brokerage; a weather widget can open your
preferred weather app.

A widget that ships a settings panel has its own gear on that slot, on
the widget row, and in the widget list. Whatever that panel saves follows
the widget, not the slot: move it and the same settings come with it.
Clearing them in the panel forgets them. The time zones panel is the
first of these. The tile always shows this computer’s clock, and the
panel adds up to three more. Each one can have its own label, and the
picker shows the zone name and current UTC offset. The weather panel stores
one location, imperial or metric units, the panels turned off, and a local
or regional radar range. The MLB panel stores
one favorite club. Leave it empty and the tile shows live games. The
stocks panel stores up to six tickers, found by symbol or company name.
Leave it empty and the tile follows Omafinance's watchlist, or shows the
S&P 500, Nasdaq, Dow, and Bitcoin when Omafinance is not installed.
