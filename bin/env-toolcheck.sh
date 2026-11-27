#!/usr/bin/env bash
# =============================================================================
# File:        bin/env-toolcheck.sh
# =============================================================================
#
# DESCRIPTION: Which dev tools are installed, from $HOME/.setup-env.manifest
#   The manifest (written by setup-env.sh and tools/install.sh) has one line per
#   tool:  <tool>:<version>:<Y|N>.  This prints each tool's manifest state next to
#   its state on the machine now. A line marked DRIFT means the manifest and the
#   machine disagree (a tool recorded as installed is gone, or the reverse).
#   Changes nothing, except --reset.
#
#   Reading the log: ~/.setup-env.log has the date of each install and change.
#
# OPTIONS:
#   --reset      Rebuild the manifest from a fresh check of every dev tool, then
#                print the report (the manifest then matches the machine)
#   -q, --quiet  Print only the tools that are DRIFT, and the summary
#   -h, --help   Show this help
#
# EXIT CODES:
#   0 - The manifest matches the machine
#   1 - Drift, or no manifest yet (run setup-env.sh, or this script with --reset)
#   2 - Bad usage
#
# USAGE:
#   env-toolcheck.sh
#   env-toolcheck.sh --reset
#   env-toolcheck.sh -q
#
# ENVIRONMENT: SETUP_ENV_MANIFEST and SETUP_ENV_LOG move the two files (tests use this).
#
# =============================================================================
set -uo pipefail

: "${BU:=$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)}"
# shellcheck source=../lib/common.bash
source "$BU/lib/common.bash"
# shellcheck source=../tools/detect.sh
source "$BU/tools/detect.sh"
handle_help "$@"

RESET=0
QUIET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --reset) RESET=1 ;;
    -q|--quiet) QUIET=1 ;;
    *) err "Unknown option: $1 (try --help)"; exit 2 ;;
  esac
  shift
done

MANIFEST="$(manifest_path)"

if [ "$RESET" -eq 1 ]; then
  if manifest_write; then
    setup_log "TOOLCHECK --reset: manifest rebuilt from the machine ($MANIFEST)"
    ok "Rebuilt $MANIFEST for ${#INSTALL_ORDER[@]} tools."
  else
    err "Could not write $MANIFEST"
    exit 1
  fi
fi

if [ ! -f "$MANIFEST" ]; then
  warn "No manifest at $MANIFEST. Run setup-env.sh, or $0 --reset to build it."
  exit 1
fi

drift=0
total=0
printf '%-12s %-14s %-9s %-9s %s\n' TOOL VERSION MANIFEST ON-DISK STATUS
# Read the manifest on fd 3: a version check run in the loop must not eat its lines.
exec 3< "$MANIFEST"
while IFS= read -r line <&3 || [ -n "$line" ]; do
  case "$line" in ''|'#'*) continue ;; esac
  IFS=: read -r t v yn <<< "$line"
  total=$((total + 1))
  if tool_present "$t"; then now=Y; else now=N; fi
  if [ "$now" = "$yn" ]; then
    status=ok
  else
    drift=$((drift + 1))
    if [ "$yn" = Y ]; then status="DRIFT: recorded as installed, now missing"
    else status="DRIFT: recorded as missing, now installed"; fi
  fi
  if [ "$QUIET" -eq 1 ] && [ "$status" = ok ]; then continue; fi
  printf '%-12s %-14s %-9s %-9s %s\n' "$t" "${v:--}" "${yn:-?}" "$now" "$status"
done
exec 3<&-

echo ""
if [ "$drift" -eq 0 ]; then
  ok "$total tools checked: the manifest matches this machine."
  exit 0
fi
warn "$drift of $total tools do not match the manifest. Run setup-env.sh --only tools to install, or $0 --reset to accept this machine's state."
exit 1
