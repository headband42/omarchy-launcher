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

Enabling it disables stock `omarchy.menu` and replaces the bar button. Disable
it to restore the original launcher:

```
omarchy plugin disable ande.launcher
```

## Tiles

Defaults live in [`tiles.json`](tiles.json). Override them with:

```
~/.config/omarchy/extensions/ande.launcher.json
```

Edits hot-reload. A tile is one of:

| Field | Meaning |
| --- | --- |
| `label` | Caption on the tile |
| `desktop` | Desktop entry id (`X Pro`, `discord`, `YouTube`) |
| `command` | Shell command (`omarchy-launch-browser`) |
| `url` | Opened with `omarchy-launch-webapp` |
| `icon` | Nerd Font glyph, used when there is no desktop icon |
| `iconName` | Freedesktop icon name |

Empty slots in the 2×4 grid stay reserved so the layout does not shift.
All eight tiles are the same size. The grid hides on narrow screens rather
than colliding with the menu card.

## Settings

The gear to the right of the tile grid opens one settings window covering the launcher.
Every slot is listed there. Click a slot to pick an installed app or paste a
URL; Clear empties it. Done (or Escape) closes the window. Escape from the
app picker returns to the slot list first.

Picks are saved to `~/.config/omarchy/extensions/ande.launcher.json` so they
survive plugin updates. More widget types can use the same slots later.
