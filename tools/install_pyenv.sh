#!/usr/bin/env bash
# Install pyenv + pyenv-virtualenv (via https://pyenv.run). Safe to re-run.
# Does not edit shell rc files; portable zshrc/bashrc already init pyenv when present.
set -u
. "$(dirname "$0")/lib.sh"
parse_dry "$@"
need_macos

export PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"
if [ -x "$PYENV_ROOT/bin/pyenv" ] || command -v pyenv >/dev/null 2>&1; then
  ensure_pyenv || exit 1
  echo "already installed: pyenv ($(pyenv --version 2>/dev/null || echo present))"
  if [ -d "$PYENV_ROOT/plugins/pyenv-virtualenv" ]; then
    echo "already present: pyenv-virtualenv"
  else
    echo "NOTE: pyenv-virtualenv plugin missing under $PYENV_ROOT/plugins"
  fi
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required to install pyenv" >&2
  exit 1
fi

# Build deps used by python-build on macOS (pyenv wiki).
ensure_brew || exit 1
for f in openssl readline sqlite3 xz zlib; do
  if brew_has formula "$f"; then
    echo "already installed: $f"
  else
    echo "installing build dep: $f"
    run brew install "$f"
  fi
done

echo "installing pyenv (pyenv.run includes pyenv-virtualenv)"
if [ "$DRY" -eq 1 ]; then
  echo "[dry-run] curl -fsSL https://pyenv.run | bash"
else
  curl -fsSL https://pyenv.run | bash
fi

ensure_pyenv || exit 1
echo "installed: $(pyenv --version 2>/dev/null || echo pyenv)"
echo "Next: ./tools/install_python.sh  (or open a new shell so PATH picks up pyenv)"
