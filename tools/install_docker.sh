#!/usr/bin/env bash
# Install Docker Desktop. Safe to re-run.
# Launch Docker.app once after install to finish setup; CLI is then on PATH.
set -u
. "$(dirname "$0")/lib.sh"
parse_dry "$@"
need_macos
install_cask docker-desktop "/Applications/Docker.app" docker
