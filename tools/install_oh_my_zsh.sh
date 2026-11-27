#!/usr/bin/env bash
# Install oh-my-zsh into ~/.oh-my-zsh without changing the login shell or rc files.
# Safe to re-run. Needs zsh; without it (common on Linux servers) it is skipped.
set -u
. "$(dirname "$0")/lib.sh"
parse_dry "$@"

dest="$HOME/.oh-my-zsh"
if [ -d "$dest" ]; then
  echo "already present: $dest"
  exit 0
fi

if ! command -v zsh >/dev/null 2>&1; then
  echo "zsh is not installed; installing it first"
  install_formula zsh zsh || {
    echo "could not install zsh; install it with your package manager, then re-run" >&2
    exit 1
  }
fi

if ! command -v git >/dev/null 2>&1; then
  echo "git is required to install oh-my-zsh" >&2
  exit 1
fi

echo "installing oh-my-zsh"
if [ "$DRY" -eq 1 ]; then
  echo "[dry-run] RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\""
else
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi
