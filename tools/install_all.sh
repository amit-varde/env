#!/usr/bin/env bash
# Install the full macOS dev-tool stack in dependency order. Safe to re-run.
# Usage: ./tools/install_all.sh [--dry-run]
#
# Order (see INSTALL_ORDER in lib.sh):
#   1. homebrew          package manager (needed by most brew-based installers)
#   2. oh_my_zsh         shell framework (portable zshrc sources it)
#   3. pyenv             Python version manager (+ virtualenv plugin)
#   4. python            pyenv Python versions (needs pyenv + build deps)
#   5. pip               upgrade pip on the active Python (needs python)
#   6. nvm               Node version manager
#   7. vim / macvim      editors
#   8. docker            Docker Desktop
#   9. gh / iterm2       CLI + terminal
#  10. cursor / vscode   IDEs (casks)
#  11. claude            Claude Code CLI
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib.sh"
parse_dry "$@"

fail=0
for t in "${INSTALL_ORDER[@]}"; do
  script="$DIR/install_${t}.sh"
  echo "==> $t"
  if [ ! -f "$script" ]; then
    echo "no installer: $script" >&2
    fail=1
    continue
  fi
  if [ "$DRY" -eq 1 ]; then "$script" --dry-run; else "$script"; fi || { echo "failed: $t" >&2; fail=1; }
done

if [ $fail -eq 0 ]; then
  echo "All tools installed (or already present)."
else
  echo "Finished with errors. Re-run after fixing failed steps." >&2
fi
exit $fail
