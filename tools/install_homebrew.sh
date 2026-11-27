#!/usr/bin/env bash
# Install Homebrew (macOS). Needs Xcode Command Line Tools and may prompt for a password.
# Safe to re-run. https://brew.sh
set -u
. "$(dirname "$0")/lib.sh"
parse_dry "$@"
mac_only "Linux uses the system package manager (apt/dnf/yum/pacman); Homebrew is not used."

if command -v brew >/dev/null 2>&1 || [ -x /opt/homebrew/bin/brew ] || [ -x /usr/local/bin/brew ]; then
  ensure_brew || exit 1
  echo "already installed: homebrew ($(brew --version | head -n 1))"
  exit 0
fi

if ! xcode-select -p >/dev/null 2>&1; then
  echo "Xcode Command Line Tools are required. Install them, then re-run:"
  echo "  xcode-select --install"
  [ "$DRY" -eq 1 ] || exit 1
fi

echo "installing homebrew"
if [ "$DRY" -eq 1 ]; then
  echo "[dry-run] NONINTERACTIVE=1 /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
else
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
