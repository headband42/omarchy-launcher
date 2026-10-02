#!/usr/bin/env bash
# Open a folder in the desktop's default file manager (inode/directory).
# If only a block device is given, mount it first.
set -euo pipefail

path=${1:-}
dev=${2:-}

open_path() {
  local target=$1
  [[ -n $target ]] || return 1
  if command -v gio >/dev/null; then
    gio open "$target"
    return
  fi
  xdg-open "$target"
}

if [[ -n $path && -d $path ]]; then
  open_path "$path"
  exit 0
fi

if [[ -n $dev && -b $dev ]]; then
  udisksctl mount -b "$dev" >/dev/null 2>&1 || true
  mp=$(findmnt -n -o TARGET "$dev" | head -1 || true)
  if [[ -n $mp ]]; then
    open_path "$mp"
    exit 0
  fi
fi

open_path "${HOME:-/}"
