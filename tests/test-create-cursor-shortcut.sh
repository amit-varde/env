#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File: env/tests/test-create-cursor-shortcut.sh
# Description: create-cursor-ide-shortcut and create-cursor-agent-shortcut write Desktop apps
# -----------------------------------------------------------------------------
# Uses a temporary Desktop, so the real Desktop is never touched. macOS only.
#
# Usage: tests/test-create-cursor-shortcut.sh
# Exit:  0 all checks passed, 1 a check failed, 2 not macOS
# -----------------------------------------------------------------------------
set -uo pipefail

[ "$(uname -s)" = Darwin ] || { echo "macOS only"; exit 2; }

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The scripts under test resolve the repo from $BU. env.sh exports BU into
# every configured shell, so without this a developer running the tests from
# their own shell would silently test a DIFFERENT checkout. Pin it.
export BU="$REPO"

IDE="$REPO/bin/create-cursor-ide-shortcut"
AGENT="$REPO/bin/create-cursor-agent-shortcut"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

pass=0; fail=0
# The launcher's second line is `exec <cursor-ide> --yes <dir>`, with %q escaping.
launcher_word() { # file, 1-based word after exec
    local line n="$2"
    line="$(sed -n 's/^exec //p' "$1")"
    # shellcheck disable=SC2086  # the backslash escapes in the line are the quoting
    eval "set -- $line"
    case "$n" in
        1) printf '%s' "$1" ;;
        2) printf '%s' "$2" ;;
        3) printf '%s' "$3" ;;
        4) printf '%s' "$4" ;;
    esac
}
check() {
    if [ "$2" -eq 0 ]; then echo "  ok   $1"; pass=$((pass + 1)); else echo "  FAIL $1 ${3:-}"; fail=$((fail + 1)); fi
}

WS="$T/ws/my project"
mkdir -p "$WS" "$T/desk" "$T/work/env" "$T/work/rock" "$T/work/.hidden"

echo "1. --dir writes an app whose launcher is cursor-ide --yes on that directory"
out="$("$IDE" --desktop "$T/desk" --dir "$WS" 2>&1)"; rc=$?
check "exit 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)" "(rc=$rc)"
check "says Created" "$(printf '%s' "$out" | grep -q 'Created .*/my project.app' && echo 0 || echo 1)"
launch="$T/desk/my project.app/Contents/MacOS/launch"
check "launcher is executable" "$([ -x "$launch" ] && echo 0 || echo 1)"
check "launcher runs cursor-ide --yes on the workspace" "$( [ "$(launcher_word "$launch" 1)" = "$REPO/bin/cursor-ide" ] && [ "$(launcher_word "$launch" 2)" = --yes ] && [ "$(launcher_word "$launch" 3)" = "$WS" ] && echo 0 || echo 1)"
check "Info.plist names the app" "$(grep -q '<string>my project</string>' "$T/desk/my project.app/Contents/Info.plist" && echo 0 || echo 1)"
check "IDE icon installed" "$([ -s "$T/desk/my project.app/Contents/Resources/AppIcon.icns" ] && grep -q 'CFBundleIconFile' "$T/desk/my project.app/Contents/Info.plist" && echo 0 || echo 1)"

echo "2. Running it again replaces the app and does not ask"
out="$("$IDE" --desktop "$T/desk" --dir "$WS" 2>&1)"; rc=$?
check "exit 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)" "(rc=$rc)"
check "says Replaced" "$(printf '%s' "$out" | grep -q Replaced && echo 0 || echo 1)"
check "still one app" "$([ "$(find "$T/desk" -name '*.app' | wc -l | tr -d ' ')" = 1 ] && echo 0 || echo 1)"
check "launcher still targets the workspace" "$([ "$(launcher_word "$launch" 3)" = "$WS" ] && echo 0 || echo 1)"

echo "3. --name, and --name with two directories is refused"
"$IDE" --desktop "$T/desk" --dir "$T/work/env" --name "Env IDE" >/dev/null 2>&1; rc=$?
check "named app written" "$([ "$rc" -eq 0 ] && [ -x "$T/desk/Env IDE.app/Contents/MacOS/launch" ] && echo 0 || echo 1)"
"$IDE" --desktop "$T/desk" --dir "$T/work/env" --dir "$T/work/rock" --name "Nope" >/dev/null 2>&1; rc=$?
check "--name with two dirs exits 2" "$([ "$rc" -eq 2 ] && echo 0 || echo 1)" "(rc=$rc)"

echo "4. -y creates one app per directory under --work, skipping hidden ones"
mkdir -p "$T/desk2"
out="$("$IDE" -y --work "$T/work" --desktop "$T/desk2" 2>&1)"; rc=$?
check "exit 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)" "(rc=$rc)"
check "env.app and rock.app" "$([ -d "$T/desk2/env.app" ] && [ -d "$T/desk2/rock.app" ] && echo 0 || echo 1)"
check "hidden directory skipped" "$([ ! -e "$T/desk2/.hidden.app" ] && echo 0 || echo 1)"

echo "5. The agent app is named <dir>-agent and launches cursor-ide --agent"
out="$("$AGENT" --desktop "$T/desk" --dir "$WS" 2>&1)"; rc=$?
check "exit 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)" "(rc=$rc)"
al="$T/desk/my project-agent.app/Contents/MacOS/launch"
check "agent app exists" "$([ -x "$al" ] && echo 0 || echo 1)"
check "launcher passes --agent" "$( [ "$(launcher_word "$al" 2)" = --agent ] && [ "$(launcher_word "$al" 3)" = --yes ] && [ "$(launcher_word "$al" 4)" = "$WS" ] && echo 0 || echo 1)"
check "IDE app was left in place" "$([ -d "$T/desk/my project.app" ] && echo 0 || echo 1)"
check "agent icon installed" "$([ -s "$T/desk/my project-agent.app/Contents/Resources/AppIcon.icns" ] && echo 0 || echo 1)"

echo "6. A path that is not a directory fails"
"$IDE" --desktop "$T/desk" --dir "$T/no-such" >/dev/null 2>&1; rc=$?
check "exit 1" "$([ "$rc" -eq 1 ] && echo 0 || echo 1)" "(rc=$rc)"

echo
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ]
