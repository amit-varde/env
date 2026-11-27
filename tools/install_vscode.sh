#!/usr/bin/env bash
# Install Visual Studio Code (the `code` command). Safe to re-run.
set -u
. "$(dirname "$0")/lib.sh"
parse_dry "$@"
mac_only "Download VS Code from https://code.visualstudio.com/Download or use your package manager."
install_cask visual-studio-code "/Applications/Visual Studio Code.app" code
