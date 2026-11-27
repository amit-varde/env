#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File: env/tests/test-setup-env-tools.sh
# Description: The tool manifest, change log, env-toolcheck and --tools selection.
# -----------------------------------------------------------------------------
# Runs in a throwaway HOME. PATH has only a fake gh (version 2.63.0) and the system
# dirs, so the results do not depend on what this machine has installed. The log and
# manifest go to the temporary directory (SETUP_ENV_LOG, SETUP_ENV_MANIFEST). Nothing
# is installed: gh is already "present", so its installer only reports that.
#
# Usage: tests/test-setup-env-tools.sh
# Exit:  0 all checks passed, 1 a check failed
# -----------------------------------------------------------------------------
# shellcheck disable=SC2034  # variables are read by the check conditions, which check() evals
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The scripts under test resolve the repo from $BU. env.sh exports BU into
# every configured shell, so without this a developer running the tests from
# their own shell would silently test a DIFFERENT checkout. Pin it.
export BU="$REPO"

# TMPDIR ends with a slash on macOS, which would put "//" inside every path
# built from it. bootstrap.sh and setup-env.sh normalise the paths they print,
# so a "//" here compares a raw path against a normalised one and fails.
TMP_BASE="${TMPDIR:-/tmp}"; TMP_BASE="${TMP_BASE%/}"
T="$(mktemp -d "$TMP_BASE/setup-env-tools-test.XXXXXX")" || { echo "cannot create a temp dir" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" SETUP_ENV_LOG="$T/setup-env.log" SETUP_ENV_MANIFEST="$T/setup-env.manifest"
mkdir -p "$HOME" "$T/fakebin"
printf '#!/bin/sh\necho "gh version 2.63.0 (2024-01-01)"\n' > "$T/fakebin/gh"
chmod +x "$T/fakebin/gh"
CLEAN_PATH="$T/fakebin:/usr/bin:/bin"
TC="$REPO/bin/env-toolcheck.sh"

pass=0
fail=0
# check NAME CONDITION: CONDITION is shell code that must succeed (it can use $out, $rc)
check() {
  if eval "$2"; then echo "  ok   $1"; pass=$((pass + 1))
  else echo "  FAIL $1"; fail=$((fail + 1)); fi
}
# contains TEXT NEEDLE: true when TEXT has NEEDLE
contains() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }

echo "manifest and toolcheck"
out="$(PATH="$CLEAN_PATH" "$TC" 2>&1)"; rc=$?
check "no manifest: toolcheck exits 1 and says how to build it" '[ "$rc" -eq 1 ] && contains "$out" "--reset"'

out="$(PATH="$CLEAN_PATH" "$TC" --reset 2>&1)"; rc=$?
check "--reset writes the manifest and the check then passes" '[ "$rc" -eq 0 ] && [ -f "$SETUP_ENV_MANIFEST" ]'

lines="$(grep -v '^#' "$SETUP_ENV_MANIFEST" | grep -c .)"
bad="$(grep -v '^#' "$SETUP_ENV_MANIFEST" | grep -cvE '^[a-z0-9_]+:[^:]*:[YN]$')"
check "one line per tool, as tool:version:Y|N ($lines lines)" '[ "$bad" -eq 0 ] && [ "$lines" -ge 10 ]'
check "gh is recorded as installed with its version" 'grep -qx "gh:2.63.0:Y" "$SETUP_ENV_MANIFEST"'

# A tool the manifest records as installed but that is gone: drift, exit 1.
printf 'zzfake:1.0:Y\n' >> "$SETUP_ENV_MANIFEST"
out="$(PATH="$CLEAN_PATH" "$TC" 2>&1)"; rc=$?
check "a tool recorded as installed but missing is DRIFT (exit 1)" '[ "$rc" -eq 1 ] && contains "$out" "DRIFT: recorded as installed, now missing"'
out="$(PATH="$CLEAN_PATH" "$TC" -q 2>&1)"
check "-q shows only the drift lines" 'contains "$out" "zzfake" && ! contains "$out" "gh "'

# A tool that is installed but recorded as missing: also drift.
sed -i.bak '/^gh:/d' "$SETUP_ENV_MANIFEST" && printf 'gh::N\n' >> "$SETUP_ENV_MANIFEST"
out="$(PATH="$CLEAN_PATH" "$TC" 2>&1)"; rc=$?
check "a tool recorded as missing but installed is DRIFT" '[ "$rc" -eq 1 ] && contains "$out" "now installed"'

PATH="$CLEAN_PATH" "$TC" --reset >/dev/null 2>&1
PATH="$CLEAN_PATH" "$TC" >/dev/null 2>&1; rc=$?
check "--reset then clears the drift" '[ "$rc" -eq 0 ]'

echo "change log"
check "--reset is logged with the date" 'grep -q "^[0-9-]* [0-9:]* TOOLCHECK --reset" "$SETUP_ENV_LOG"'

echo "setup-env.sh tool selection"
help="$(bash "$REPO/setup-env.sh" --help 2>&1)"
check "--help documents --tools" 'contains "$help" "--tools LIST"'

out="$(PATH="$CLEAN_PATH" bash "$REPO/setup-env.sh" --only tools --tools nosuchtool -y -d "$REPO" </dev/null 2>&1)"
check "--tools with an unknown name installs nothing and says so" 'contains "$out" "Unknown tool '\''nosuchtool'\''"'

out="$(PATH="$CLEAN_PATH" bash "$REPO/setup-env.sh" --only tools --tools gh -y -d "$REPO" </dev/null 2>&1)"; rc=$?
check "--tools gh runs only gh (already present, so no change)" '[ "$rc" -eq 0 ] && contains "$out" "already installed: gh"'
check "the run logs the choice and that gh was already present" 'grep -q "TOOLS chosen: gh" "$SETUP_ENV_LOG" && grep -q "RUN gh (already present, version=2.63.0)" "$SETUP_ENV_LOG"'
check "the run logs its start and end" 'grep -q "SETUP start: " "$SETUP_ENV_LOG" && grep -q "SETUP done" "$SETUP_ENV_LOG"'
check "a setup run rewrites the manifest" 'grep -qx "gh:2.63.0:Y" "$SETUP_ENV_MANIFEST"'

out="$(PATH="$CLEAN_PATH" bash "$REPO/setup-env.sh" --only tools -y -d "$REPO" </dev/null 2>&1)"; rc=$?
check "-y without --tools installs nothing" '[ "$rc" -eq 0 ] && contains "$out" "No tools chosen"'

echo ""
echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
