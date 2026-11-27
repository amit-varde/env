#!/usr/bin/env bash
# Install one or more Python versions via pyenv and upgrade pip on the global one.
# Safe to re-run; skips versions already installed.
#
# Usage:
#   ./tools/install_python.sh [--dry-run] [--global VER] [VER ...]
# Defaults match this Mac's current set: 3.10.16 3.11.8 3.13.11 (global 3.11.8).
set -u
. "$(dirname "$0")/lib.sh"
parse_dry "$@"

DEFAULT_VERSIONS="3.10.16 3.11.8 3.13.11"
GLOBAL_DEFAULT="3.11.8"
global="$GLOBAL_DEFAULT"
versions=""
prev=""
for a in "$@"; do
  if [ "$prev" = "--global" ]; then
    global="$a"
    prev=""
    continue
  fi
  case "$a" in
    --dry-run) ;;
    --global) prev="--global" ;;
    --global=*) global="${a#--global=}" ;;
    *) versions="$versions $a" ;;
  esac
done
[ -z "$prev" ] || { echo "--global requires a version" >&2; exit 1; }
[ -n "$versions" ] || versions="$DEFAULT_VERSIONS"

ensure_pyenv || exit 1

fail=0
for ver in $versions; do
  if pyenv versions --bare 2>/dev/null | grep -qx "$ver"; then
    echo "already installed: python $ver"
    continue
  fi
  echo "installing python $ver"
  if [ "$DRY" -eq 1 ]; then
    echo "[dry-run] pyenv install $ver"
  else
    pyenv install -s "$ver" || { echo "failed: python $ver" >&2; fail=1; }
  fi
done

echo "setting global python: $global"
if [ "$DRY" -eq 1 ]; then
  echo "[dry-run] pyenv global $global"
else
  if pyenv versions --bare 2>/dev/null | grep -qx "$global"; then
    pyenv global "$global"
  else
    echo "global version not installed: $global" >&2
    fail=1
  fi
fi

# Keep pip current on the active interpreter (same as pydev-install).
if [ "$DRY" -eq 1 ]; then
  echo "[dry-run] python -m pip install --upgrade pip"
elif command -v python >/dev/null 2>&1; then
  echo "upgrading pip"
  python -m pip install --upgrade pip || fail=1
else
  echo "python not on PATH after pyenv init; skip pip upgrade" >&2
fi

if [ "$DRY" -eq 0 ] && command -v python >/dev/null 2>&1; then
  echo "python: $(command -v python) ($(python --version 2>&1))"
  command -v pip >/dev/null 2>&1 && echo "pip: $(command -v pip) ($(pip --version 2>&1))"
fi
exit $fail
