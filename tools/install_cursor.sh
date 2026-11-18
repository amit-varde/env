#!/usr/bin/env bash
# Install Cursor. Safe to re-run.
set -u
. "$(dirname "$0")/lib.sh"
parse_dry "$@"
need_macos
install_cask cursor "/Applications/Cursor.app" cursor
