#!/usr/bin/env bash
# Install Visual Studio Code (the `code` command). Safe to re-run.
set -u
. "$(dirname "$0")/lib.sh"
parse_dry "$@"
need_macos
install_cask visual-studio-code "/Applications/Visual Studio Code.app" code
