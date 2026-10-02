#!/usr/bin/env bash
# Run every test in the repo, or only the ones under the given directories.
# Usage: scripts/test.sh [dir...]
#
# Finds test_*.cjs (node:test) and test_*.py (unittest). Each Python file runs
# on its own so it can import the modules next to it.

set -uo pipefail
shopt -s nullglob globstar

cd "$(dirname "${BASH_SOURCE[0]}")/.."
export PYTHONDONTWRITEBYTECODE=1

roots=("$@")
((${#roots[@]})) || roots=(.)

node_tests=()
py_tests=()
for root in "${roots[@]}"; do
  root=${root%/}
  [[ -d $root ]] || {
    echo "test.sh: no such directory: $root" >&2
    exit 2
  }
  for file in "$root"/**/test_*.cjs; do
    [[ $file == */node_modules/* ]] || node_tests+=("$file")
  done
  for file in "$root"/**/test_*.py; do
    py_tests+=("$file")
  done
done

failed=()

if ((${#node_tests[@]})); then
  node --test --test-reporter=dot "${node_tests[@]}" || failed+=("node")
fi

for file in "${py_tests[@]}"; do
  if ! out=$(python3 "$file" 2>&1); then
    printf '%s\n' "$out"
    failed+=("$file")
  fi
done

total=$((${#node_tests[@]} + ${#py_tests[@]}))
if ((${#failed[@]})); then
  echo "FAIL: ${failed[*]}" >&2
  exit 1
fi
echo "ok: $total test files (${#node_tests[@]} node, ${#py_tests[@]} python)"
