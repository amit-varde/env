#!/usr/bin/env bash
# Install MacVim (`mvim`). Safe to re-run.
# Preferred local EDITOR in bu/lib/init-editor.bash when not over SSH.
set -u
. "$(dirname "$0")/lib.sh"
parse_dry "$@"
mac_only "Install MacVim by hand (macOS only); on Linux use vim or gvim from your package manager."
install_cask macvim-app "/Applications/MacVim.app" mvim
