#!/usr/bin/env bash
# Install a launcher widget into ~/.config/omarchy/extensions/ande.launcher/widgets/
# Usage: install-widget.sh <dir-or-git-url>
#
# Also links this plugin's widgets/_kit into that folder, so an installed
# widget can `import "../_kit"` the same way a bundled one does.

set -euo pipefail

dest_root="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/extensions/ande.launcher/widgets"
kit=$(cd "$(dirname "${BASH_SOURCE[0]}")/../widgets/_kit" && pwd)
src=${1:-}

[[ -n $src ]] || {
  echo "usage: $0 <widget-dir-or-git-url>" >&2
  exit 1
}

tmp=""
# An `[[ ]] && rm` here would make the trap, and so the script, exit 1
# after a local install that worked.
cleanup() {
  if [[ -n $tmp && -d $tmp ]]; then rm -rf "$tmp"; fi
}
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
# The id becomes a folder name that gets replaced, so keep it to one plain
# path segment. A leading `_` is reserved for shared code like _kit.
[[ $id =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
  echo "install-widget: widget id '$id' must be letters, digits, '.', '_' or '-', not starting with '_'" >&2
  exit 1
}

mkdir -p "$dest_root"
rm -rf "${dest_root:?}/$id"
cp -a "$src" "$dest_root/$id"

# A real _kit directory there was put by hand. Leave it alone.
if [[ -L $dest_root/_kit || ! -e $dest_root/_kit ]]; then
  ln -sfn "$kit" "$dest_root/_kit"
else
  echo "install-widget: $dest_root/_kit is not a link to $kit; leaving it" >&2
fi

echo "Installed $id -> $dest_root/$id"
