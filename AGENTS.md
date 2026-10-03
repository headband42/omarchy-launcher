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
- `openUrl(url)` — `omarchy-launch-webapp` for a link that starts with one of `Menu.qml` `widgetUrlPrefixes`: `https://www.mlb.com/`, `https://mlb.com/`, `https://www.nfl.com/`, `https://finance.yahoo.com/quote/`, `https://x.com/`, or one of the six fantasy sites (`https://sleeper.com/`, `https://fantasy.espn.com/`, `https://www.fleaflicker.com/`, `https://www.myfantasyleague.com/`, `https://www.fantrax.com/`, `https://football.fantasysports.yahoo.com/`). The MLB and NFL tiles use it so a click opens that game, the stocks tile so a row opens that ticker, the X tile so a headline opens on x.com, and the fantasy tile so a league opens on its own site. `fantasy.js` `URL_PREFIXES` is the same six; change both together. Any other URL does nothing.
- `openLink(url)` — any other web link (a feed headline, a pull request, a status page, a meeting, a Gmail conversation) in the default browser, via `omarchy-launch-browser` as an argv, never through a shell. `TileModel.linkTarget` is the gate: http or https, a real host, no whitespace, quotes, angle brackets, backslashes, backticks, or control characters, at most 2048 characters. Use `openUrl` for the five webapp prefixes above and `openLink` for everything else.
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

`widgets/nfl/` reads ESPN's public feeds with curl, because ESPN answers Python's own TLS client with a 403: the scoreboard, the club's schedule, and the standings with `level=3`, which groups clubs by division in NFL.com's order. The scoreboard's copy of a game is richer than the schedule's (network, line, weather, records), so the next game is taken from it when both have it. The schedule names the network under `broadcasts[].media.shortName`. A game that has not kicked off arrives with `"score": "0"`; that is not a score and is dropped. ESPN's `situation.yardLine` is counted from the **home** team's goal line, not the offence's, so reading it as the offence's puts a visiting drive in the wrong half. The field strip is drawn from the offence's side and places the ball from `possessionText` ("PIT 44") instead; no spot, no field. At halftime and between quarters a game stays `in` with a 0:00 clock: the status name says which. Logos are shipped, 96 px; `logos/dark/` holds ESPN's dark-background marks for the eight clubs whose usual mark disappears on a dark tile, and `nfl.js` `DARK_LOGOS` lists them.

`widgets/fantasy/` follows up to six leagues on Sleeper, ESPN, Fleaflicker, MyFantasyLeague, Fantrax, and Yahoo, and reduces each to one shape: both sides' score, projection, players left and playing, record, and alerts for my starters. A stored league is `{p, id, team}` (Sleeper adds `user`, the owner's id, so a league that rolled into a new season with a new id is followed by `previous_league_id`); `fantasy.py` `ID_PATTERNS` checks every id before it goes in a URL, and `fantasy.js` `ID_PATTERNS` mirrors it for the panel. Bye weeks and kickoffs for every platform come from ESPN's public `proTeamSchedules_wl`, cached for half a day: a starter whose club has kicked off is playing for four hours, then done; only one not yet kicked off raises an alert. Sleeper's 15 MB `/players/nfl` is asked for once a day, as Sleeper requests, and cached trimmed; its injuries are overridden by the weekly projections (`api.sleeper.com/projections`, undocumented: when it fails there is no projection, nothing else breaks). ESPN narrows the box score with `X-Fantasy-Filter` (`filterCurrentMatchupPeriod` + `filterTeamIds`, about 100 KB instead of 400), and its injuries are only in `mRoster`. A dead Fleaflicker league answers a request for this season with its last season and no error; only a live one says `activeForCurrentSeason: true` (a dead one leaves the key out, it is not `false`). Fleaflicker's box score refuses `season=` with a 400, and spells the injury field `typeAbbreviaition`. MFL redirects a call with `L=` to the league's own server and refuses a call without one there, so `players` and `injuries` go without `L=`; a one-item list arrives as a bare object. Fantrax's public `fxea` API has no scores and reports a bad id as a 200 with `{"error": ...}`. Private ESPN (`espn_s2` + `SWID` cookies), private MFL (API key), and Yahoo (OAuth with the user's own registered app, `redirect_uri=oob`) are **beta**: never tried against a real account. Their secrets live in `$XDG_CONFIG_HOME/ande.launcher/fantasy-auth.json`, mode 0600, keyed `espn:<id>`, `mfl:<id>`, `yahoo`. The panel passes a new one in the `ANDE_FANTASY_AUTH` environment variable, never argv, and it is saved only after a lookup with it works. Yahoo's tokens belong to the tile, so `fantasy.py` refreshes them and keeps the rotated refresh token. CBS is left out on purpose: its API is deprecated and the only working sign-in poses as CBS's mobile app with its built-in secret. Tests inject `fetch` and point `XDG_CACHE_HOME` / `XDG_CONFIG_HOME` at a temporary folder.

`widgets/network/` takes the interface the kernel routes 1.1.1.1 through (`ip -j route get`), so a VPN that holds the default route is the interface and the link under it is `via`. Wi-Fi comes from `nmcli`, then `iwctl`, then `iw dev X link`, whichever answers; none is assumed. `tailscale0` stays up while Tailscale is signed out or stopped, so it counts as a VPN only when `tailscale status --json` says `BackendState: Running` (or the CLI is missing). Each sample reads the byte counters twice, 0.5 s apart, so a tile that just opened has a rate; after that the tile takes the rate between its own samples.

`widgets/bluetooth/` reads `Quickshell.Bluetooth` in-process and copies each device into a plain row, as Omarchy's own panel does: a delegate that holds a BlueZ object can outlive it and crash the shell. Only connected, paired, bonded, or trusted devices are rows; strangers seen during someone's discovery are not. Actions run `omarchy-bluetooth-device` and `omarchy-bluetooth-power` as an argv, and an address must match `XX:XX:XX:XX:XX:XX`.

`widgets/timer/` is Omarchy's reminders: `omarchy-reminder <minutes>` starts a systemd user timer named `omarchy-reminder-<m>m-<epoch>`, and `show --json` lists them. There is no command to stop one, so `timer.py --cancel` does what `omarchy-reminder clear` does for a single unit: `systemctl --user stop <unit>.timer` and remove `$XDG_RUNTIME_DIR/omarchy-reminders/<unit>.message`. Any other unit name is refused.

`widgets/captures/` runs Omarchy's capture commands after a 0.45 s pause and closes the launcher, or the launcher is in the picture. File paths only ever reach a shell as positional arguments (`captures.js` `copyArgv`, `delayed`).

`widgets/status/` reads Atlassian Statuspage's `/api/v2/summary.json`. incident.io pages answer that same path in the same shape, but only on their canonical host: `status.linear.app` redirects to `linearstatus.com/` and drops the path, so the catalog stores canonical hosts. Slack (`slack-status.com/api/v2.0.0/current`), Heroku (`/api/v4/current-status`), GitLab (status.io, `status_code` 100–600), Google Cloud (`incidents.json`, open when `end` is missing), and AWS (`health.aws.amazon.com/public/currentevents`, **UTF-16**, latest `event_log` status 0–3) have adapters of their own. Stripe's `/current` still says February 2024 and is left out. A custom URL is a status page when it serves `summary.json`, else a reachability check where any answer below 500 is up. Healthy rows are drawn in the text color, not the accent: some themes' accent is orange.

`widgets/feeds/` reads RSS 2.0, RSS 1.0 (RDF), and Atom. A pasted site address is fetched and its `<link rel="alternate">` feed is used. Each feed is cached 15 minutes, and a copy up to a week old stands in when it stops answering.

`widgets/github/` runs `gh api graphql` and `gh api notifications` and nothing else, so it never holds a token. A pull request link that is not https is dropped.

`widgets/agenda/` is the calendar. Its sampler is `agenda.py` because a `calendar.py` beside it shadows the standard library's `calendar`, which `email._parseaddr` and `http.cookiejar` import. Calendars live in `$XDG_CONFIG_HOME/ande.launcher/calendars.json` at 0600 (folder 0700), not in `widgetSettings`: an iCal address can be a password. The panel passes a new one in `ANDE_CALENDAR_URL`, never argv, and `--list` shows only the host. Recurrence is expanded in the event's own zone (`occurrences`), with EXDATE (a date-only EXDATE also removes a timed instance that day), RDATE, and RECURRENCE-ID overrides; its output matched python-dateutil on 100 rule and start pairs, DST and leap days included. Windows zone names from Outlook map through `WINDOWS_ZONES`.

`widgets/mail/` reads unread mail over IMAP with an app password, so one adapter covers Gmail, Workspace, iCloud, Fastmail, Yahoo, AOL, Zoho, GMX, Proton (through Proton Mail Bridge on `127.0.0.1:1143`), and any other server. Accounts live in `$XDG_CONFIG_HOME/ande.launcher/mail-accounts.json` at 0600 (folder 0700), not in `widgetSettings`; the panel passes `ANDE_MAIL_ADDRESS`, `ANDE_MAIL_PASSWORD`, and `ANDE_MAIL_SERVER` in the environment, never argv, an account is saved only after it signs in, and `--list` and the cache never carry the password. Sign-in is `AUTHENTICATE PLAIN` where offered (every big provider offers it), else `LOGIN`. A password goes only over TLS: port 993, or STARTTLS on any other port, and the certificate is checked except on loopback, where Bridge's is self-signed. The server comes from `DOMAINS`, else the domain's MX through the resolver in `/etc/resolv.conf` (`lookup_mx` is a small DNS client, so the domain goes nowhere new), else the user types it. Microsoft is refused by domain, by MX (`*.outlook.com`), and by a typed `office365.com` or `outlook.com` host: since 2024-09-16 it takes only OAuth, app passwords included. DavMail on loopback still works as `other`. HEY (`app.hey.com` MX for a custom domain) and Tuta have no IMAP. Gmail is the `X-GM-EXT-1` capability, not the domain. Its view is `primary` (`X-GM-RAW "is:unread category:primary"`), `inbox` (`UNSEEN`), or `important`; `@gmail.com` starts on Primary and Workspace on Inbox, where tabs are off by default. imaplib sends arguments raw, so the `X-GM-RAW` query carries its own quotes. A row links to `https://mail.google.com/mail/u/?authuser=<address>#inbox/<X-GM-THRID in hex>`; `/mail/u/<address>/` no longer picks the account. Reading is `EXAMINE` and `BODY.PEEK`, so nothing changes; `--read` is the only write, and it stores `\Seen` only while the inbox's UIDVALIDITY matches the row's. imaplib hands FETCH back as `(line ending in {n}, literal)` tuples and a bare line that ends each message, and the tokenizer keeps `BODY[HEADER.FIELDS (…)]` as one atom. A raw 8-bit header is read as UTF-8, then Latin-1. iCloud signs in with the name before the `@` for its own domains, then the whole address. Gmail and Yahoo print an app password as four groups of four letters, and only that exact shape loses its spaces. The last reply is cached in `$XDG_CACHE_HOME/ande.launcher/mail.json` at 0600; an account that fails shows its last mail, marked stale, until a day after that mail was read. The tests run a fake IMAP server on loopback through the real imaplib.

`widgets/scores/` is the other leagues on ESPN, through curl like the NFL tile. A soccer team's schedule lists results; its fixtures need `?fixture=true`, so both are read. A score is a string on the scoreboard and an object in a schedule. Logos are fetched once at 64 px through `a.espncdn.com/combiner` into the cache, with the `dark` variant when the team has one, and the tile picks by the theme's background.

`widgets/f1/` reads the season from Jolpica (`api.jolpi.ca/ergast/f1/current/...`) and running orders from OpenF1 (`/v1/position`, the latest row per car). Jolpica's driver `code` equals OpenF1's `name_acronym`, which is how standings get team colors. While any session is live, OpenF1 answers **every** request without a paid key with a 401, past sessions included (seen during FP2 on 2026-10-02, and still at 09:12 after its scheduled 09:00 end; open again by 11:11), so a live order never shows for free: the tile marks the session `locked`, polls every five minutes instead of every twenty seconds, and shows that session's final order for three hours after it ends. A session from another weekend is not shown. OpenF1 `intervals` exist only for races. Caches store the fetch time inside the file; comparing a file's mtime with an injected clock never hits.

To look at a tile without a desktop, render it offscreen: a quickshell config folder with `Commons` and `Ui` linked from `/usr/share/omarchy/shell`, a `FloatingWindow` that loads the widget, and `grabToImage` after a delay, under `QT_QPA_PLATFORM=offscreen`. That runs Qt Quick's software renderer, so `MultiEffect` and other shader effects draw nothing there; they still work in the shell.

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
