#!/usr/bin/env bash
# Install Cursor. Safe to re-run.
set -u
. "$(dirname "$0")/lib.sh"
parse_dry "$@"
mac_only "Download Cursor from https://cursor.com/downloads (AppImage or .deb). Servers do not need it."
install_cask cursor "/Applications/Cursor.app" cursor
