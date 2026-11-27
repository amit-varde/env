#!/usr/bin/env bash
# Install vim. Safe to re-run. macOS: Homebrew. Linux: apt/dnf/yum/pacman (needs root).
set -u
. "$(dirname "$0")/lib.sh"
parse_dry "$@"
install_formula vim vim
