#!/usr/bin/env bash
# Ensure pip exists for the active Python and upgrade it. Safe to re-run.
# Prefer pyenv's python when available (see install_pyenv.sh / install_python.sh).
set -u
. "$(dirname "$0")/lib.sh"
parse_dry "$@"

ensure_pyenv 2>/dev/null || true

if ! command -v python >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
  echo "No python/python3 on PATH. Run tools/install_python.sh first." >&2
  exit 1
fi
py=python
command -v python >/dev/null 2>&1 || py=python3

echo "using: $py ($($py --version 2>&1))"
if [ "$DRY" -eq 1 ]; then
  echo "[dry-run] $py -m ensurepip --upgrade"
  echo "[dry-run] $py -m pip install --upgrade pip"
  exit 0
fi

$py -m ensurepip --upgrade 2>/dev/null || true
$py -m pip install --upgrade pip
echo "pip: $($py -m pip --version 2>&1)"
