#!/usr/bin/env bash
# Install the Claude Code CLI (`claude`). Safe to re-run.
# macOS: the Homebrew cask, so upgrades stay with `brew upgrade --cask claude-code`.
# Linux: Anthropic's installer script (https://claude.ai/install.sh), which installs
# under ~/.local. This is not the Claude desktop app.
set -u
. "$(dirname "$0")/lib.sh"
parse_dry "$@"

if command -v claude >/dev/null 2>&1; then
  echo "already installed: claude ($(command -v claude))"
  exit 0
fi

if [ "$OS_NAME" = mac ]; then
  install_cask claude-code "" claude
  exit $?
fi

[ "$OS_NAME" = linux ] || { echo "unsupported OS for install_claude: $(uname -s)" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "curl is required to install claude" >&2; exit 1; }
echo "installing claude with Anthropic's installer (https://claude.ai/install.sh)"
if [ "$DRY" -eq 1 ]; then
  echo "[dry-run] curl -fsSL https://claude.ai/install.sh | bash"
else
  curl -fsSL https://claude.ai/install.sh | bash
fi
