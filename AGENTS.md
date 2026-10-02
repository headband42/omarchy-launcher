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
| `widgets/<id>/` | One widget per folder. The catalog is a scan of these folders. |
| `widgets/_kit/` | Shared by widgets, not a widget: `Poller`, `WidgetHeader`, `IconButton`, `UsageBoard` / `UsageMeter` / `usage.js` (the plan tiles' bars and reset times), `kit.js`, and the system and disk samplers that `sysmon`, `disks`, and `sysdisk` run. `list-widgets.py` skips any `_` folder. |
| `~/.config/omarchy/extensions/ande.launcher/widgets/<id>/` | Installed widgets. Same id wins over the bundled copy. |
| `~/.config/omarchy/extensions/ande.launcher.json` | The user’s live slots. Do not write it unless they asked. |

`scripts/sync-upstream.sh` reads `$OMARCHY_PATH` or `/usr/share/omarchy`. dmenu and input modes hide the tiles so `omarchy-menu-select` still gets the centered card. Keep that.

## Two different things in a slot

A slot is not “an app.”

- **Widget** is what is drawn. It is a folder we ship or the user installs. Icon & link means no widget. Its catalog entry is defined once, in `TileModel.iconLinkWidget()`, and `withIconLink()` puts it first.
- **Opens** is what a click on empty chrome launches (`desktop`, `command`, or `url`).

`TileModel.applyWidget` copies `defaultCommand` / `defaultDesktop` / `defaultUrl` only when the slot has no launch target yet. Changing Opens does not touch settings.

Do not store a widget’s nerd-font glyph on the tile. Icon-and-link tiles use the launch target’s desktop `Icon=`. A leftover glyph is why Stocks stayed on screen after the slot was switched to Orca Slicer.

## Clicks

`TileGrid` puts a `MouseArea` **behind** the `Loader`. Empty chrome hits that and calls `host.launchDefault()`. Do not add a full-tile `MouseArea` that only calls `launchDefault()`. A control the widget draws needs its own `MouseArea` on top (a drive row, a calc key). Hint badges sit above both.

`host` may declare:

- `launchDefault()` — Opens
- `openFolder(path)` / `openVolume(path, device)` — `scripts/open-volume.sh`, which uses `gio open` (the desktop’s default file manager). Do not call `omarchy-launch-nautilus`.
- `openTerminal(path)` — `xdg-terminal-exec --dir=`. Do not call `omarchy-launch-terminal`; it ignores the directory and uses the active terminal’s cwd.
- `openUrl(url)` — `omarchy-launch-webapp` for a link that starts with one of `Menu.qml` `widgetUrlPrefixes`: `https://www.mlb.com/`, `https://mlb.com/`, or `https://finance.yahoo.com/quote/`. The MLB tile uses it so a click opens that game on Gameday, and the stocks tile so a row opens that ticker. Any other URL does nothing.
- `focusAgent(paneId)` — moves Herdr's focus to a pane, via `/usr/bin/herdr agent focus`. `Menu.qml` `focusHerdrAgent` is the gate: a pane id must match `[A-Za-z0-9_-]{1,32}:[A-Za-z0-9_-]{1,32}` or nothing runs. The rule exists twice, in `herdr.js` and in `Menu.qml`; if you change one, change both. Ids must not be truncated, or the check rejects them and the row goes inert. This closes the launcher, like every other launch action.
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

Saving is the same for every panel. Assign `settings`, or call `host.save(settings)`. Both go through `TileModel.saveWidgetSettings`. The object is stored on the config under `widgetSettings[widgetId]`, not on the slot. Adding that widget to any slot restores it, and every slot showing it gets the same object. `null` or `{}` forgets it. Do not write the config file from the widget. A `widgetSettings` object left on an old slot is promoted by `normalizeConfig`. Time zones is the reference: `settings.zones` is up to three entries, either an IANA id or `{ id, label }` when the user set a custom label. The system clock is always shown. MLB stores `teamId`. An empty object shows the live slate, including during the playoffs when that club has no postseason games. With nothing live in the postseason, the slate is the series board (`Series.qml`), read from `schedule/postseason/series` with a `fields` list that keeps a 500 KB reply under 100 KB. A key the board reads has to be in `SERIES_FIELDS`, or the feed drops it. Stocks stores `symbols`, up to six Yahoo symbols. An empty object follows Omafinance's watchlist (`~/.local/state/omarchy/settings/finance.json`).

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

Call `poller.pollSoon()` after an action so the tile re-reads once it lands. Draw the dot-and-caption row with `WidgetHeader`, and a round glyph button or labeled pill with `IconButton`. It accepts every click, so a dimmed button never falls through to Opens. A TUI (lazygit, lazydocker) needs `omarchy-launch-tui` in front of it; the launcher runs commands with no terminal. A widget that still needs its own `Process` (weather's cache phases, a settings search) builds the path with `Kit.localPath(Qt.resolvedUrl(...))` from `_kit/kit.js`, and reads `StdioCollector { id: out; waitForEnd: true }` as `out.text`. It is a property. `text()` throws, the parse fails, and the tile stays at zeros or blank. That bug has already shipped once.

`widgets/opencode/` reads the Go plan with one call, `GET https://opencode.ai/console/api/go/status`. The console host is the one that answers: the bare `api.opencode.ai` and `app.opencode.ai` return 200 for every path, so they look alive and are not. Auth is `Authorization: Bearer <access_token>` plus `x-org-id`, and both come out of OpenCode's own database (`$OPENCODE_DB`, else `$XDG_DATA_HOME/opencode/opencode.db`, else `~/.local/share/opencode/opencode.db`), which is opened `mode=ro`. The token is the active account's, so it belongs to the same account as the org. The token is never printed, logged, or committed. Money is in micro-cents and **one dollar is 100000000 of them**: a $12 block arrives as `1200000000`; getting that factor wrong shows $12 as $1200 and nothing else looks broken. The three blocks are `fiveHour`, `week` and `month`, and they are the 20% / 50% / 100% split of the monthly limit that `opencode.ai/docs/go` documents.

`widgets/claude/` reads a Claude plan's limits with one call, `GET https://api.anthropic.com/api/oauth/usage`, with `Authorization: Bearer <token>` and `anthropic-beta: oauth-2025-04-20`. The token is Claude Code's own sign-in, `claudeAiOauth.accessToken` in `$CLAUDE_CONFIG_DIR/.credentials.json`, else `~/.claude/.credentials.json`. Read that file; never write it, and never refresh the token, because a refresh rotates Claude Code's refresh token behind its back. A past `expiresAt` is reported as expired without sending the token. `utilization` is already a percentage. Each limit is optional (`seven_day_opus` and `extra_usage` come and go by plan), and an unknown key is drawn once its `utilization` is above zero. At 0% it is hidden, because the reply carries internal codenames (`iguana_necktie`) that would otherwise show up as a label. Tests write their own credentials file; nothing in the suite may read the real one or reach the network.

`widgets/grok/` reads a Grok plan's limits with `GET https://cli-chat-proxy.grok.com/v1/billing?format=credits` (`Authorization: Bearer` plus `X-XAI-Token-Auth: xai-grok-cli`, and `x-userid` when the saved id matches `[A-Za-z0-9_-]{1,64}`). The token is the `key` of a sign-in in `$GROK_HOME/auth.json`, else `~/.grok/auth.json`. Read that file; never write it, and never refresh the token, because a refresh rotates Grok's refresh token behind its back. A past `expires_at` (RFC3339, nanoseconds trimmed to microseconds) is reported as expired without sending the token. When several sign-ins are saved, one that has not expired wins, and among those the one that lasts longest. `GROK_CLI_CHAT_PROXY_BASE_URL` may replace the host the same way the CLI does, https only, and the tile still calls only `/v1/billing?format=credits` and `/v1/settings`. Money is USD cents: `{"val": 500}` is $5.00, `{}` is $0, and **one dollar is 100 cents**. Getting that factor wrong the OpenCode way shows $5 as a huge number and nothing else looks broken. `creditUsagePercent` is already a percentage of the weekly or monthly allowance. The reset is `currentPeriod.end`. `billingPeriodEnd` is the calendar-month ledger, so it is not the weekly reset when the period end is present. A fresh window omits the percentage and is drawn at 0%. Grok Build, Grok Chat, and the API (`productUsage`) are extra bars only when at least two of them report `usagePercent` and those percentages add back up to the allowance, within a point. A product with no percentage is left out, and a single product that copies the allowance is left out. Pay-as-you-go (`ondemand`) is drawn only when `onDemandCap` is a non-zero number of cents. A prepaid balance is the footer, and only when its absolute cents are above zero. `monthlyLimit` / `used` are the older monthly ledger, same cents, used only when `creditUsagePercent` is absent and there is no weekly or monthly `currentPeriod`. The plan name is a second call, `GET /v1/settings`, preferring `subscription_tier_display` over `subscription_tier` (a bare tier number is not a name), including a nested `settings` object. Settings failing does not fail the tile; the name stays `Grok`. Do not parse `~/.grok/settings_cache.json`. An API key has no plan limits: no auth file is `signin`, and a reply with no meters is `plan`. The meter ids a panel can hide are `period`, `grokbuild`, `grokchat`, `api`, and `ondemand`. The last good reply is cached at `~/.cache/ande.launcher/grok.json` and the token is not in it. Tests write their own auth file and inject `fetch`; nothing in the suite may read the real one or reach the network.

`widgets/herdr/` reads the running Herdr server with `herdr api snapshot` and nothing else. `herdr.allowed_command` is an exact-match allowlist: the argument list must be exactly `[HERDR, "api", "snapshot"]`, length included. Herdr reports failure inside a 200-shaped reply as `{"error": {"code", "message"}}` and still exits 0, so the envelope is the gate and the exit code is not. `AgentStatus` is fixed by Herdr's schema at `idle | working | blocked | done | unknown`; anything else is read as `unknown`. A section id is Herdr's own: `""` is everything, `w1` a workspace, `w1:t2` one tab, and a tab is matched by that whole id, never by the tail after the colon.

The Qt here is 6.11, whose `WheelHandler` has no `onRotation`. Scrolling in a tile comes from `ListView.interactive`, bound to whether the content actually overflows so an unscrolling list does not swallow the wheel from the launcher.

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
