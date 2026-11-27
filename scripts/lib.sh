# shellcheck shell=bash
# Shared helpers for scripts/ (sourced). See lib/scan-patterns.bash for the
# secret/PII patterns and the blocklist - they are defined there and only there,
# so the export scrubbers and bin/env-scan can never drift apart.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The repo these scripts act on. blocklist_file / blocklist_pattern default to
# it, so a stray $BU from the user's login shell cannot redirect them.
SCAN_ROOT="$ROOT"

# shellcheck source=../lib/scan-patterns.bash
. "$ROOT/lib/scan-patterns.bash"

# Path of the live blocklist, or empty when there is none. The export scrubbers
# print this, so keep it defined even when absent.
BLOCKLIST="$(blocklist_file "$ROOT")"
