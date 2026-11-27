#!/usr/bin/env bash
# Install the full dev-tool stack in dependency order. Safe to re-run.
# Usage: ./tools/install_all.sh [--dry-run] [-y]
#
# This is a shim for `./tools/install.sh --all`, kept because the README and
# older notes name it. install.sh is the orchestrator: it reads INSTALL_ORDER
# from tools/lib.sh, skips what is already present, and on Linux skips the
# macOS-only tools instead of failing.
#
#   ./tools/install.sh --list            every tool, platform and whether it is installed
#   ./tools/install.sh --all             the full stack
#   ./tools/install.sh --tool gh         just one (repeatable)
#   ./tools/install.sh --dry-run --all   print what would happen, change nothing
#
# Add a tool: drop in tools/install_<name>.sh, append <name> to INSTALL_ORDER in
# tools/lib.sh, and add <name> to tool_present/tool_version in tools/detect.sh.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$DIR/install.sh" --all "$@"
