#!/usr/bin/env bash
# Install the Claude Code CLI (`claude`). Safe to re-run.
# Uses the Homebrew cask so upgrades stay with `brew upgrade --cask claude-code`.
# This is not the Claude desktop app (cask name: claude).
set -u
. "$(dirname "$0")/lib.sh"
parse_dry "$@"
need_macos
install_cask claude-code "" claude
