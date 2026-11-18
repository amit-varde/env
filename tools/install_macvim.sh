#!/usr/bin/env bash
# Install MacVim (`mvim`). Safe to re-run.
# Preferred local EDITOR in bu/lib/init-editor.bash when not over SSH.
set -u
. "$(dirname "$0")/lib.sh"
parse_dry "$@"
need_macos
install_cask macvim-app "/Applications/MacVim.app" mvim
