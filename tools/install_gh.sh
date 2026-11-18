#!/usr/bin/env bash
# Install GitHub CLI (gh). Safe to re-run. Auth is separate: gh auth login
set -u
. "$(dirname "$0")/lib.sh"
parse_dry "$@"
need_macos
install_formula gh gh
