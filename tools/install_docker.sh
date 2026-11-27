#!/usr/bin/env bash
# Install Docker Desktop. Safe to re-run.
# Launch Docker.app once after install to finish setup; CLI is then on PATH.
set -u
. "$(dirname "$0")/lib.sh"
parse_dry "$@"
mac_only "Install Docker Engine for your distro: https://docs.docker.com/engine/install/ (needs root)."
install_cask docker-desktop "/Applications/Docker.app" docker
