#!/usr/bin/env bash
# Install pyenv + pyenv-virtualenv (via https://pyenv.run). Safe to re-run.
# Does not edit shell rc files; the shell setup in this repo (lib/init-pyenv.bash) inits pyenv when present.
# macOS: build dependencies via brew. Linux: via apt/dnf/yum/pacman when root is
# available, otherwise it warns and carries on (pyenv itself installs in ~/.pyenv).
set -u
. "$(dirname "$0")/lib.sh"
parse_dry "$@"

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

for t in curl git; do
  command -v "$t" >/dev/null 2>&1 || { echo "$t is required to install pyenv" >&2; exit 1; }
done

install_python_build_deps || exit 1

echo "installing pyenv (pyenv.run includes pyenv-virtualenv)"
if [ "$DRY" -eq 1 ]; then
  echo "[dry-run] curl -fsSL https://pyenv.run | bash"
else
  curl -fsSL https://pyenv.run | bash
fi

ensure_pyenv || exit 1
echo "installed: $(pyenv --version 2>/dev/null || echo pyenv)"
echo "Next: tools/install_python.sh  (or open a new shell so PATH picks up pyenv)"
