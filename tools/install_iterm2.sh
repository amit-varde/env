#!/usr/bin/env bash
# Install iTerm2 and the zsh integration sourced by dotfiles/zshrc.
# Safe to re-run.
set -u
. "$(dirname "$0")/lib.sh"
parse_dry "$@"
need_macos
install_cask iterm2 "/Applications/iTerm.app" || exit $?

dest="$HOME/.iterm2_shell_integration.zsh"
if [ -f "$dest" ]; then
  echo "already present: $dest"
  exit 0
fi
echo "installing iTerm2 shell integration"
if [ "$DRY" -eq 1 ]; then
  echo "[dry-run] curl -fsSL https://iterm2.com/shell_integration/zsh -o $dest"
else
  curl -fsSL "https://iterm2.com/shell_integration/zsh" -o "$dest"
fi
