#!/usr/bin/env bash
# Install vim via Homebrew. Safe to re-run.
set -u
. "$(dirname "$0")/lib.sh"
parse_dry "$@"
need_macos
install_formula vim vim
