#!/usr/bin/env bash
# Install selected macOS dev tools. Safe to re-run; skips what is already present.
# Usage:
#   ./tools/install.sh [--dry-run]                 # same order as install_all.sh
#   ./tools/install.sh [--dry-run] homebrew pyenv  # only these tools
# Full stack: prefer ./tools/install_all.sh
# Add a tool: drop in install_<name>.sh and append <name> to INSTALL_ORDER in lib.sh.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib.sh"
parse_dry "$@"

tools=""
for a in "$@"; do
  case "$a" in
    --dry-run) ;;
    *) tools="$tools $a" ;;
  esac
done
if [ -n "$tools" ]; then
  # shellcheck disable=SC2206
  selected=($tools)
else
  selected=("${INSTALL_ORDER[@]}")
fi

fail=0
for t in "${selected[@]}"; do
  script="$DIR/install_${t}.sh"
  echo "==> $t"
  if [ ! -f "$script" ]; then
    echo "no installer: $script" >&2
    fail=1
    continue
  fi
  if [ "$DRY" -eq 1 ]; then "$script" --dry-run; else "$script"; fi || { echo "failed: $t" >&2; fail=1; }
done
exit $fail
