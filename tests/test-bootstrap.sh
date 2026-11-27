#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File: env/tests/test-bootstrap.sh
# Description: Drive bootstrap.sh's questions through a pseudo-terminal
# -----------------------------------------------------------------------------
# Builds a throwaway git repo from this working tree, then runs bootstrap.sh in a
# temporary HOME with `expect`, answering its questions. Nothing outside the
# temporary directory is touched. Needs: expect, git, bash.
#
# Usage: tests/test-bootstrap.sh
# Exit:  0 all scenarios passed, 1 a scenario failed, 2 expect is missing
# -----------------------------------------------------------------------------
set -uo pipefail

command -v expect >/dev/null 2>&1 || { echo "expect is required (apt install expect / brew install expect)" >&2; exit 2; }
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The scripts under test resolve the repo from $BU. env.sh exports BU into
# every configured shell, so without this a developer running the tests from
# their own shell would silently test a DIFFERENT checkout. Pin it.
export BU="$REPO"

# TMPDIR ends with a slash on macOS, which would put "//" inside every path
# built from it. bootstrap.sh and setup-env.sh normalise the paths they print,
# so a "//" here compares a raw path against a normalised one and fails.
TMP_BASE="${TMPDIR:-/tmp}"; TMP_BASE="${TMP_BASE%/}"
T="$(mktemp -d "$TMP_BASE/bootstrap-test.XXXXXX")" || { echo "cannot create a temp dir" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT

# A source repo made from the files in this tree (tracked or new, not deleted).
SRC="$T/src"; mkdir -p "$SRC"
( cd "$REPO" && git ls-files -co --exclude-standard | while IFS= read -r f; do [ -f "$f" ] && echo "$f"; done \
    | grep -v '^claude/\(backups\|cache\|projects\|sessions\|history\|file-history\|plugins\|downloads\)' \
    | tar -cf - -T - ) | tar -xf - -C "$SRC"
( cd "$SRC" && git init -q -b main && git add -A && git -c user.name=t -c user.email=t@t commit -q -m test )

# bootstrap.sh is run from a standalone copy, the way a user downloads it: run from inside
# a clone it would default to that clone (and the tests must never touch the real one).
mkdir -p "$T/dl"; cp "$REPO/bootstrap.sh" "$T/dl/bootstrap.sh"
BOOT="$T/dl/bootstrap.sh"

pass=0; fail=0
check() { # name, condition-exit-status, [detail]
    if [ "$2" -eq 0 ]; then echo "  ok   $1"; pass=$((pass + 1)); else echo "  FAIL $1 ${3:-}"; fail=$((fail + 1)); fi
}

# run_pty LOGFILE HOME EXPECT_BODY BOOTSTRAP_ARGS...   (env: extra VAR=val before call)
# EXPECT_BODY is Tcl run after `spawn`; it can use the proc `answer pattern text`.
run_pty() {
    local log="$1" home="$2" body="$3"; shift 3
    mkdir -p "$home"
    env -u WORK -u BU HOME="$home" SHELL=/bin/bash expect -f - -- "$BOOT" "$@" > "$log" 2>&1 <<EOF
set timeout 10
set script [lindex \$argv 0]
set args [lrange \$argv 1 end]
proc answer {pat text} { expect -re \$pat { send "\$text\r" } timeout { puts "TIMEOUT waiting for \$pat"; exit 3 } }
eval spawn bash \$script \$args
$body
expect eof
catch wait result
exit [lindex \$result 3]
EOF
    return $?
}
strip() { sed 's/\x1b\[[0-9;]*m//g' "$1" | tr -d '\r'; }

export ENV_BRANCH=main

echo "1. Defaults: Enter at every question, then a full run limited to the repo step"
H="$T/h1"
ENV_REPO_URL="$SRC" run_pty "$T/l1" "$H" '
answer {\(WORK\) \[[^]]*\]: } ""
answer {Create it\? \[Y/n\] } ""
answer {Env repo location \[[^]]*\]: } ""
answer {Proceed\? \[Y/n\] } ""
' -- --only repo >/dev/null 2>&1
rc=$?; strip "$T/l1" > "$T/l1.txt"
check "exit 0" "$rc" "(rc=$rc)"
check "WORK defaults to ~/work and is created" "$([ -d "$H/work" ] && echo 0 || echo 1)"
check "repo cloned to <WORK>/env" "$([ -f "$H/work/env/env.sh" ] && echo 0 || echo 1)"
check "hands over to setup-env.sh" "$(grep -q 'Environment setup' "$T/l1.txt" && echo 0 || echo 1)"

echo "2. Custom WORK given with ~ and a space; repo location follows it"
H="$T/h2"
ENV_REPO_URL="$SRC" run_pty "$T/l2" "$H" '
answer {\(WORK\) \[[^]]*\]: } "~/my projects"
answer {Create it\? \[Y/n\] } "y"
answer {Env repo location \[[^]]*\]: } ""
answer {Proceed\? \[Y/n\] } ""
' -- --only repo >/dev/null 2>&1
rc=$?; strip "$T/l2" > "$T/l2.txt"
check "exit 0" "$rc" "(rc=$rc)"
check "~ expanded to HOME" "$([ -d "$H/my projects" ] && echo 0 || echo 1)"
check "repo under the custom WORK" "$([ -f "$H/my projects/env/env.sh" ] && echo 0 || echo 1)"
check "summary shows the chosen WORK" "$(grep -q "WORK .*$H/my projects" "$T/l2.txt" && echo 0 || echo 1)"

echo "3. Answering n at 'Proceed?' changes nothing (also exercises the repo/branch questions)"
H="$T/h3"
run_pty "$T/l3" "$H" '
answer {\(WORK\) \[[^]]*\]: } ""
answer {Create it\? \[Y/n\] } "y"
answer {Env repo location \[[^]]*\]: } ""
answer {OWNER/NAME\) \[[^]]*\]: } ""
answer {Branch \[[^]]*\]: } ""
answer {Proceed\? \[Y/n\] } "n"
' >/dev/null 2>&1
rc=$?; strip "$T/l3" > "$T/l3.txt"
check "exits non-zero" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)" "(rc=$rc)"
check "says it was cancelled" "$(grep -q Cancelled "$T/l3.txt" && echo 0 || echo 1)"
check "no repo was cloned" "$([ ! -e "$H/work/env" ] && echo 0 || echo 1)"

echo "4. Declining to create a missing WORK stops"
H="$T/h4"
ENV_REPO_URL="$SRC" run_pty "$T/l4" "$H" '
answer {\(WORK\) \[[^]]*\]: } "~/nowhere"
answer {Create it\? \[Y/n\] } "n"
' >/dev/null 2>&1
rc=$?; strip "$T/l4" > "$T/l4.txt"
check "exits non-zero" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)" "(rc=$rc)"
check "directory not created" "$([ ! -e "$H/nowhere" ] && echo 0 || echo 1)"

echo "5. WORK that is a file is refused"
H="$T/h5"; mkdir -p "$H"; : > "$H/afile"
ENV_REPO_URL="$SRC" run_pty "$T/l5" "$H" '
answer {\(WORK\) \[[^]]*\]: } "~/afile"
' >/dev/null 2>&1
rc=$?; strip "$T/l5" > "$T/l5.txt"
check "exits non-zero" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)" "(rc=$rc)"
check "explains it is not a directory" "$(grep -q 'is not a directory' "$T/l5.txt" && echo 0 || echo 1)"

echo "6. A non-empty directory that is not a clone is never touched"
H="$T/h6"; mkdir -p "$H/work/env"; echo keep > "$H/work/env/precious.txt"
ENV_REPO_URL="$SRC" run_pty "$T/l6" "$H" '
answer {\(WORK\) \[[^]]*\]: } ""
answer {Env repo location \[[^]]*\]: } ""
' >/dev/null 2>&1
rc=$?; strip "$T/l6" > "$T/l6.txt"
check "exits non-zero" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)" "(rc=$rc)"
check "file untouched" "$([ "$(cat "$H/work/env/precious.txt")" = keep ] && echo 0 || echo 1)"
check "says why" "$(grep -q 'not a git clone' "$T/l6.txt" && echo 0 || echo 1)"

echo "7. Command-line answers skip the questions (--work, --dir, -y)"
H="$T/h7"; mkdir -p "$H"
( cd "$T" && env -u WORK -u BU HOME="$H" SHELL=/bin/bash ENV_REPO_URL="$SRC" bash "$BOOT" -y --work "$T/w 7" --dir "$T/w 7/code/env" -- --only repo ) > "$T/l7" 2>&1 < /dev/null
rc=$?
check "exit 0" "$rc" "(rc=$rc)"
check "clone at the --dir location" "$([ -f "$T/w 7/code/env/env.sh" ] && echo 0 || echo 1)"

# A fake gh for the fork scenarios: GitHub is a folder of bare repos ($GH_ROOT/<owner>/<name>.git),
# a fork records its parent in <name>.parent, and `repo clone` of a fork adds the
# `upstream` remote the way the real gh does.
GH_ROOT="$T/github"; mkdir -p "$GH_ROOT/boss" "$T/fakebin"
git clone -q --bare "$SRC" "$GH_ROOT/boss/env.git"
cat > "$T/fakebin/gh" <<'GH'
#!/usr/bin/env bash
R="$FAKE_GH_ROOT"
case "$1 $2" in
  "auth status"|"auth setup-git"|"auth login") exit 0 ;;
  "api user") echo "$FAKE_GH_LOGIN"; exit 0 ;;
  "repo view")
    [ -d "$R/$3.git" ] || exit 1
    case "$*" in *parent*) cat "$R/$3.parent" 2>/dev/null; echo ;; esac; exit 0 ;;
  "repo fork")
    src="$3"; shift 3; org=""; name="${src#*/}"
    while [ $# -gt 0 ]; do case "$1" in --org) org="$2"; shift ;; --fork-name) name="$2"; shift ;; esac; shift; done
    owner="${org:-$FAKE_GH_LOGIN}"; mkdir -p "$R/$owner"
    git clone -q --bare "$R/$src.git" "$R/$owner/$name.git" && echo "$src" > "$R/$owner/$name.parent"; exit $? ;;
  "repo clone")
    slug="$3"; dir="$4"; br=main; [ "${6:-}" = --branch ] && br="$7"
    git clone -q --branch "$br" "$R/$slug.git" "$dir" || exit 1
    [ -f "$R/$slug.parent" ] && git -C "$dir" remote add upstream "$R/$(cat "$R/$slug.parent").git"
    exit 0 ;;
esac
echo "fake gh: unhandled: $*" >&2; exit 1
GH
chmod +x "$T/fakebin/gh"
FAKE_PATH="$T/fakebin:$PATH"

echo "8. Not the owner: Enter at the fork question forks into your account and wires upstream"
H="$T/h8"
PATH="$FAKE_PATH" FAKE_GH_ROOT="$GH_ROOT" FAKE_GH_LOGIN=me ENV_REPO=boss/env run_pty "$T/l8" "$H" '
answer {\(WORK\) \[[^]]*\]: } ""
answer {Create it\? \[Y/n\] } ""
answer {Env repo location \[[^]]*\]: } ""
answer {OWNER/NAME\) \[[^]]*\]: } ""
answer {Branch \[[^]]*\]: } ""
answer {Proceed\? \[Y/n\] } ""
answer {Fork boss/env into your own GitHub repo.*\[Y/n\] } ""
answer {Fork owner [^[]*\[me\]: } ""
answer {Fork name \[env\]: } ""
' -- --only repo >/dev/null 2>&1
rc=$?; strip "$T/l8" > "$T/l8.txt"
D="$H/work/env"
check "exit 0" "$rc" "(rc=$rc)"
check "fork created at me/env" "$([ -d "$GH_ROOT/me/env.git" ] && echo 0 || echo 1)"
check "clone's origin is the fork" "$([ "$(git -C "$D" remote get-url origin 2>/dev/null)" = "$GH_ROOT/me/env.git" ] && echo 0 || echo 1)"
check "upstream is the original" "$([ "$(git -C "$D" remote get-url upstream 2>/dev/null)" = "$GH_ROOT/boss/env.git" ] && echo 0 || echo 1)"
check "pushing to upstream disabled" "$(git -C "$D" remote get-url --push upstream 2>/dev/null | grep -q no_push && echo 0 || echo 1)"
check "setup-env.sh names the fork" "$(grep -q 'repo me/env' "$T/l8.txt" && echo 0 || echo 1)"

echo "9. -y --fork-name: forks without questions, under the given name"
H="$T/h9"; mkdir -p "$H"
( cd "$T" && env -u WORK -u BU HOME="$H" SHELL=/bin/bash PATH="$FAKE_PATH" FAKE_GH_ROOT="$GH_ROOT" FAKE_GH_LOGIN=me ENV_REPO=boss/env \
    bash "$BOOT" -y --fork-name my-env --work "$H/work" -- --only repo ) > "$T/l9" 2>&1 < /dev/null
rc=$?
check "exit 0" "$rc" "(rc=$rc)"
check "fork created at me/my-env" "$([ -d "$GH_ROOT/me/my-env.git" ] && echo 0 || echo 1)"
check "upstream wired" "$([ "$(git -C "$H/work/env" remote get-url upstream 2>/dev/null)" = "$GH_ROOT/boss/env.git" ] && echo 0 || echo 1)"

echo "10. The owner: the fork question defaults to no, and the original is cloned"
H="$T/h10"
PATH="$FAKE_PATH" FAKE_GH_ROOT="$GH_ROOT" FAKE_GH_LOGIN=boss ENV_REPO=boss/env run_pty "$T/l10" "$H" '
answer {\(WORK\) \[[^]]*\]: } ""
answer {Create it\? \[Y/n\] } ""
answer {Env repo location \[[^]]*\]: } ""
answer {OWNER/NAME\) \[[^]]*\]: } ""
answer {Branch \[[^]]*\]: } ""
answer {Proceed\? \[Y/n\] } ""
answer {Fork boss/env into your own GitHub repo.*\[y/N\] } ""
' -- --only repo >/dev/null 2>&1
rc=$?
check "exit 0" "$rc" "(rc=$rc)"
check "origin is the original" "$([ "$(git -C "$H/work/env" remote get-url origin 2>/dev/null)" = "$GH_ROOT/boss/env.git" ] && echo 0 || echo 1)"
check "no upstream remote" "$(git -C "$H/work/env" remote get-url upstream >/dev/null 2>&1 && echo 1 || echo 0)"

echo "11. -y alone never forks"
H="$T/h11"; mkdir -p "$H"
( cd "$T" && env -u WORK -u BU HOME="$H" SHELL=/bin/bash PATH="$FAKE_PATH" FAKE_GH_ROOT="$GH_ROOT" FAKE_GH_LOGIN=other ENV_REPO=boss/env \
    bash "$BOOT" -y --work "$H/work" -- --only repo ) > "$T/l11" 2>&1 < /dev/null
rc=$?
check "exit 0" "$rc" "(rc=$rc)"
check "no fork for 'other'" "$([ ! -d "$GH_ROOT/other" ] && echo 0 || echo 1)"
check "origin is the original" "$([ "$(git -C "$H/work/env" remote get-url origin 2>/dev/null)" = "$GH_ROOT/boss/env.git" ] && echo 0 || echo 1)"

echo
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ] || { echo "Logs: $T (kept)"; trap - EXIT; exit 1; }
