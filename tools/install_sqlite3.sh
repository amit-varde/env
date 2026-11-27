#!/usr/bin/env bash
# Install the sqlite3 command (needed by bin/cursor-ide). Safe to re-run.
# macOS ships it; Linux uses the system package manager (needs root).
set -u
. "$(dirname "$0")/lib.sh"
parse_dry "$@"
install_formula sqlite3 sqlite3
