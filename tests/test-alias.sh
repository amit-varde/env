#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File: env/tests/test-alias.sh
# Description: the alias file survives a machine that already aliases its names
# -----------------------------------------------------------------------------
# zsh expands aliases at PARSE time. So if a user's shell already has, say,
# `alias so=...` when env.sh sources the repo's alias file, then `so() {` is not
# a warning -- it is a parse error that ABORTS the rest of the file, silently
# dropping every alias below it. That is why the alias file clears its own
# function names first, and why this test exists:
#
#   1. every function the file defines is named in its unalias guard, so adding
#      an unguarded function in future cannot quietly reintroduce the cliff;
#   2. sourcing it under zsh with every one of those names pre-aliased still
#      defines the whole file, functions and the last alias included;
#   3. the same under bash;
#   4. no rc template aliases a name the alias file defines as a function.
#
# Usage: tests/test-alias.sh
# Exit:  0 all checks passed, 1 a check failed
# -----------------------------------------------------------------------------
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# env.sh exports BU into every configured shell, so without pinning it a
# developer running the tests from their own shell would test ANOTHER checkout.
export BU="$REPO"

ALIAS="$REPO/alias"
ERRF="$(mktemp)"
trap 'rm -f "$ERRF"' EXIT
pass=0; fail=0
check() {
    if [ "$2" -eq 0 ]; then echo "  ok   $1"; pass=$((pass + 1)); else echo "  FAIL $1 ${3:-}"; fail=$((fail + 1)); fi
}

[ -f "$ALIAS" ] || { echo "no alias file at $ALIAS"; exit 1; }

# --- 1. every function defined in the file is named in the unalias guard -----
FNS="$(grep -oE '^[A-Za-z_][A-Za-z0-9_-]*\(\)' "$ALIAS" | tr -d '()' | sort -u)"
GUARD="$(sed -n 's/^unalias \(.*\) 2>\/dev\/null.*$/\1/p' "$ALIAS" | tr ' ' '\n' | sort -u)"

check "the file has an unalias guard" "$([ -n "$GUARD" ] && echo 0 || echo 1)"
check "the file defines at least one function" "$([ -n "$FNS" ] && echo 0 || echo 1)"

# bash 3.2: no here-strings, and a plain `for f in $FNS` would not split in zsh.
while IFS= read -r fn; do
    [ -n "$fn" ] || continue
    if printf '%s\n' "$GUARD" | grep -qx "$fn"; then
        check "guard covers $fn()" 0
    else
        check "guard covers $fn()" 1 "(add it to the unalias line in $ALIAS)"
    fi
done <<EOF
$FNS
EOF

# The last alias in the file. If a parse error aborts partway, this is the thing
# that goes missing, so it is what proves the whole file was read.
LAST_ALIAS="$(grep -oE '^alias [A-Za-z_][A-Za-z0-9_-]*=' "$ALIAS" | tail -1 | sed 's/alias //;s/=//')"
check "found a last alias to probe for" "$([ -n "$LAST_ALIAS" ] && echo 0 || echo 1)"

# --- 2 & 3. source it with every function name already aliased ---------------
# Build the hostile preamble: alias every name the file defines as a function.
PRE=""
while IFS= read -r fn; do
    [ -n "$fn" ] || continue
    PRE="$PRE alias $fn='echo HOSTILE';"
done <<EOF
$FNS
EOF

probe() { # shell_name shell_cmd
    local sh="$1" cmd="$2" out rc missing err
    # Source under the hostile preamble, then report what survived. Each name
    # must end up a FUNCTION (not the alias), and the file's last alias must
    # exist -- that is the proof nothing aborted early.
    # NB: never pipe `source`. A pipeline runs it in a SUBSHELL, so every
    # definition is discarded and the probe reports a failure that is its own.
    # Redirect to a file instead.
    out="$("$cmd" -c "
        $PRE
        export BU='$REPO'
        source '$ALIAS' >/dev/null 2>'$ERRF'
        missing=
        while IFS= read -r fn; do
            [ -n \"\$fn\" ] || continue
            if ! typeset -f \"\$fn\" >/dev/null 2>&1; then missing=\"\$missing \$fn(fn)\"; fi
        done <<EOT
$FNS
EOT
        if ! alias '$LAST_ALIAS' >/dev/null 2>&1; then missing=\"\$missing $LAST_ALIAS(last-alias)\"; fi
        [ -z \"\$missing\" ] && echo OK || echo \"MISSING:\$missing\"
    " 2>&1)"
    rc=$?
    # Any stderr at all means the shell complained while reading the file.
    err="$(tr '\n' ' ' < "$ERRF" 2>/dev/null)"
    missing="$(printf '%s' "$out" | grep -E '^MISSING' | tr '\n' ' ')"
    check "$sh: whole file survives a hostile pre-existing alias" \
        "$([ "$rc" -eq 0 ] && [ -z "$err" ] && printf '%s' "$out" | grep -q '^OK$' && echo 0 || echo 1)" \
        "${missing:-}${err:+ stderr: $err}${missing:+}$([ -n "$missing$err" ] || printf '(rc=%s)' "$rc")"
}

if command -v zsh >/dev/null 2>&1; then
    probe "zsh " zsh
else
    echo "  skip zsh not installed"
fi
probe "bash" bash

# --- 4. no rc template aliases a name the alias file defines as a function ----
for rc in zshrc bashrc; do
    f="$REPO/dotfiles/$rc"
    [ -f "$f" ] || { echo "  skip dotfiles/$rc not present"; continue; }
    clash=""
    while IFS= read -r fn; do
        [ -n "$fn" ] || continue
        if grep -qE "^alias $fn=" "$f"; then clash="$clash $fn"; fi
    done <<EOF
$FNS
EOF
    check "dotfiles/$rc does not alias a name alias defines as a function" \
        "$([ -z "$clash" ] && echo 0 || echo 1)" "(clashes:$clash)"
done

# dotfiles/cshrc is deliberately exempt: csh has no functions and never sources
# the alias file (env.sh refuses any shell but bash and zsh), so its own
# `alias so 'source ~/.cshrc'` is csh's implementation, not drift.

echo
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ]
