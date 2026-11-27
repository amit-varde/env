#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File: env/tests/check-helper-drift.sh
# Description: Fail when bootstrap.sh drifts from the repo it bootstraps
# -----------------------------------------------------------------------------
# bootstrap.sh is downloaded on its own, before the repo exists, so it carries its own
# copies of the small helpers in lib/common.bash. This keeps the copies identical.
#
# It also carries its own ENV_REPO default, for the same reason: it cannot read
# env.conf before the clone exists. That value is checked against env.conf here,
# so a fork only has to change env.conf and bootstrap.sh once and the build says
# so if it forgets one.
#
# Usage: tests/check-helper-drift.sh
# Exit:  0 identical, 1 a helper differs or is missing, or ENV_REPO disagrees
# -----------------------------------------------------------------------------
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The scripts under test resolve the repo from $BU. env.sh exports BU into
# every configured shell, so without this a developer running the tests from
# their own shell would silently test a DIFFERENT checkout. Pin it.
export BU="$REPO"

# step() is left out on purpose: lib/common.bash numbers setup steps, bootstrap.sh does not.
# pkg_install is left out too: bootstrap.sh keeps its own copy so it can run before the clone.
HELPERS="ok warn die err success have ask confirm norm_path _get_caller_info _get_timestamp env_wire_upstream"

# fn_def FILE NAME: the function's text. A one-line function is that line; otherwise
# everything up to the first line that is just "}".
fn_def() {
    awk -v n="$2" '
        $0 ~ "^" n "\\(\\) *\\{" { p = 1; print; if ($0 ~ /\}[[:space:]]*$/) exit; next }
        p { print; if ($0 ~ /^\}/) exit }
    ' "$1" | sed -E 's/[[:space:]]+/ /g'      # alignment spaces are not drift
}

rc=0
for fn in $HELPERS; do
    a="$(fn_def "$REPO/bootstrap.sh" "$fn")"
    b="$(fn_def "$REPO/lib/common.bash" "$fn")"
    if [ -z "$a" ] || [ -z "$b" ]; then
        echo "MISSING  $fn: not found in $([ -z "$a" ] && echo bootstrap.sh || echo lib/common.bash)"; rc=1
    elif [ "$a" != "$b" ]; then
        echo "DRIFT    $fn differs between bootstrap.sh and lib/common.bash:"
        diff <(printf '%s\n' "$a") <(printf '%s\n' "$b") | sed 's/^/           /'; rc=1
    else
        echo "same     $fn"
    fi
done
# ENV_REPO: bootstrap.sh's built-in default must match env.conf.
conf_repo="$(sed -n 's/^[[:space:]]*ENV_REPO[[:space:]]*=[[:space:]]*//p' "$REPO/env.conf" \
    | sed -e 's/[[:space:]]*#.*$//' -e 's/[[:space:]]*$//' | tail -1)"
boot_repo="$(sed -n 's/^ENV_REPO="\${ENV_REPO:-\([^}]*\)}"[[:space:]]*$/\1/p' "$REPO/bootstrap.sh" | tail -1)"
if [ -z "$conf_repo" ]; then
    echo "MISSING  ENV_REPO: not found in env.conf"; rc=1
elif [ -z "$boot_repo" ]; then
    echo "MISSING  ENV_REPO: no 'ENV_REPO=\"\${ENV_REPO:-...}\"' line in bootstrap.sh"; rc=1
elif [ "$conf_repo" != "$boot_repo" ]; then
    echo "DRIFT    ENV_REPO: env.conf says '$conf_repo', bootstrap.sh says '$boot_repo'"; rc=1
else
    echo "same     ENV_REPO ($conf_repo)"
fi

[ "$rc" -eq 0 ] && echo "bootstrap.sh is in step with the repo" || echo "Update both files so they match."
exit "$rc"
