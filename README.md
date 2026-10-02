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
`UsageBoard` and `UsageMeter` draw a plan tile's usage bars, with
`usage.js` formatting their countdowns and reset days.
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
| `mlb` | Favorite club: score, count, division standings, winning and losing pitchers, and the next starter. No club, or a club out of the playoffs, shows every live game as a card with the inning, bases, and outs, plus the series score in the postseason. In the postseason with nothing live, it shows each series in the current round (wins, next game, channel, probable pitchers, last result) and earlier rounds' results | That game on MLB Gameday, or the postseason page from the series board |
| `spotify` | What [OmaSpotify](https://github.com/jeremylanger/omaspotify) is playing on this computer: artwork, track, seek bar, shuffle, previous, play/pause, next, repeat. Read over MPRIS, so the official Spotify client works too | OmaSpotify's full player |
| `repo` | One git repository: branch with ahead and behind, changed-file chips, two weeks of commits as bars, and the latest commits with unpushed ones highlighted. Footer buttons open a terminal or the folder and fetch. The gear lists the repositories in your home folder | lazygit in that repository |
| `docker` | Running, unhealthy, paused, and stopped counts, then containers with compose project, image, ports, CPU, and memory. Hover a row to start, stop, or restart it. Without access to the socket it says what the daemon is doing, and it never wakes an idle socket-activated daemon | lazydocker |
| `todo` | A checklist in a text file, plain or Markdown: tick, add, rename, remove, and clear finished tasks. In a Markdown file only checkbox lines are tasks; headings and notes are written back as they were | none until Opens is set |
| `opencode` | OpenCode Go: the block closest to its limit as a big number, then a bar for each of the 5-hour, weekly, and monthly blocks with what is spent and when it resets | The console |
| `claude` | Your Claude plan: the fullest limit as a big number, then a bar for the 5-hour session and each weekly limit (all models, Opus, Sonnet), plus extra usage when it is on, with when each frees up | claude.ai's usage page |
| `herdr` | Every agent in the live Herdr session and what each one is doing, blocked first. Attaches to a workspace, a tab, or the whole session. Click a row to focus that agent | Herdr in a terminal |

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

OpenCode Go limits each model over three blocks: 5 hours, a week, and the
month, worth 20%, 50% and 100% of the monthly limit. The tile shows the block
closest to its ceiling as one big number, then a bar per block, warming from
the theme's accent to its urgent color as it fills. Under each bar it shows
what is spent of what and when the block frees up; a 5-hour block that has
not started says it starts with your next request. The numbers come from one
call, `GET /console/api/go/status`, using the console sign-in OpenCode already
has on this machine: the token and active organization are read from
OpenCode's own database, opened read-only, and the token is never logged or
printed. The tile polls every five minutes, every minute when a block is near
its ceiling, and draws the last reply from `~/.cache/ande.launcher` while the
first poll of a session is out. Signed out, an expired sign-in, and a plan
with no blocks are three different messages, because the fix is different for
each.

The Claude tile works the same way for a Claude plan. It reads the sign-in
Claude Code saved (`~/.claude/.credentials.json`, or under
`$CLAUDE_CONFIG_DIR`) and makes one call, `GET
https://api.anthropic.com/api/oauth/usage`. That file is only read: the tile
never refreshes the token, so once it expires the tile says so until Claude
Code next runs and renews it. The token is never logged, printed, or cached.
A Claude Code that runs on an API key has no plan limits, and the tile says
that too. Its panel hides limits and switches the reset style.

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
S&P 500, Nasdaq, Dow, and Bitcoin when Omafinance is not installed. The OpenCode panel hides the blocks you do not want on the tile, switches
the reset line between a countdown and the day, and turns the money line off.

The Herdr panel picks which part of the session the tile watches: all of
it, one workspace, or one tab. Every row is one agent, with the status
Herdr reports for its pane. `blocked` sorts to the top, because that is
the one an agent is waiting on a person for; `working` follows. The panel
can also hide the idle and done agents, leaving only the ones that need
something. The counts in the list come from the session, so a section
with nothing in it is obvious before you pick it.

A session with more agents than fit scrolls, with the wheel or by
dragging, and the tile remembers the agent at the top so a poll that
reorders the list does not lose your place.

Clicking a row moves Herdr's focus to that agent and closes the launcher.
The pane id is checked twice: the tile only passes one that looks like Herdr's own `w1:p6`, and
the launcher refuses anything else before it runs `herdr agent focus`.
