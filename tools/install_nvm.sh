#!/usr/bin/env bash
# Install nvm into ~/.nvm without editing shell rc files.
# Safe to re-run. Portable zshrc/bashrc already source nvm when present.
set -u
. "$(dirname "$0")/lib.sh"
parse_dry "$@"

export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [ -s "$NVM_DIR/nvm.sh" ]; then
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh"
  echo "already installed: nvm ($(nvm --version 2>/dev/null || echo present))"
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required to install nvm" >&2
  exit 1
fi

# Pin a known nvm release; bump when you want a newer installer.
NVM_VERSION="${NVM_VERSION:-v0.40.3}"
echo "installing nvm $NVM_VERSION"
if [ "$DRY" -eq 1 ]; then
  echo "[dry-run] PROFILE=/dev/null bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh)\""
else
  PROFILE=/dev/null bash -c "$(curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh")"
fi

if [ "$DRY" -eq 0 ] && [ -s "$NVM_DIR/nvm.sh" ]; then
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh"
  echo "installed: nvm $(nvm --version 2>/dev/null)"
  echo "Optional: nvm install --lts"
fi
