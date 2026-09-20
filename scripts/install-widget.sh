#!/usr/bin/env bash
# Install a launcher widget into ~/.config/omarchy/extensions/ande.launcher/widgets/
# Usage: install-widget.sh <dir-or-git-url>

set -euo pipefail

dest_root="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/extensions/ande.launcher/widgets"
src=${1:-}

[[ -n $src ]] || {
  echo "usage: $0 <widget-dir-or-git-url>" >&2
  exit 1
}

tmp=""
cleanup() { [[ -n $tmp && -d $tmp ]] && rm -rf "$tmp"; }
trap cleanup EXIT

if [[ $src == git@* || $src == http://* || $src == https://* || $src == ssh://* ]]; then
  tmp=$(mktemp -d)
  git clone --depth 1 "$src" "$tmp/src"
  src=$tmp/src
fi

src=$(cd "$src" && pwd)
meta=$src/widget.json
qml=$src/Widget.qml
[[ -f $meta && -f $qml ]] || {
  echo "install-widget: $src needs widget.json and Widget.qml" >&2
  exit 1
}

id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("id",""))' "$meta")
[[ -n $id ]] || id=$(basename "$src")

mkdir -p "$dest_root"
rm -rf "$dest_root/$id"
cp -a "$src" "$dest_root/$id"
echo "Installed $id -> $dest_root/$id"
