#!/usr/bin/env bash
# Install oh-my-zsh into ~/.oh-my-zsh without changing the login shell or rc files.
# Safe to re-run. Portable zshrc already sources it when present.
set -u
. "$(dirname "$0")/lib.sh"
parse_dry "$@"
need_macos

dest="$HOME/.oh-my-zsh"
if [ -d "$dest" ]; then
  echo "already present: $dest"
  exit 0
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
