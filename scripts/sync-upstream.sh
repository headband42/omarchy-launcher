#!/usr/bin/env bash
# Refresh the forked omarchy.menu sources from the installed Omarchy tree.
# MenuModel.js and BarWidget.qml are copied as-is. Menu.qml is copied to
# vendor/ for a manual merge — the left+right tile layout lives in our fork.

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
src="${OMARCHY_PATH:-/usr/share/omarchy}/shell/plugins/menu"

[[ -d $src ]] || {
  echo "sync-upstream: omarchy menu not found at $src" >&2
  exit 1
}

mkdir -p "$root/vendor/omarchy-menu"
cp -a "$src/MenuModel.js" "$root/MenuModel.js"
cp -a "$src/BarWidget.qml" "$root/BarWidget.qml"
cp -a "$src/Menu.qml" "$root/vendor/omarchy-menu/Menu.qml"

echo "Updated MenuModel.js and BarWidget.qml from $src"
echo "Stock Menu.qml saved to vendor/omarchy-menu/Menu.qml"
echo "Diff against the fork with:"
echo "  diff -u vendor/omarchy-menu/Menu.qml Menu.qml"
