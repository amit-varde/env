#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File: env/tests/test-gu-fork.sh
# Description: gu fork against throwaway repos (an original, its fork, a clone). No network.
# -----------------------------------------------------------------------------
# Builds a temporary $WORK where "orig.git" plays the original on GitHub, "fork.git"
# its fork, and work/demo the user's clone of the fork. Runs wire, status, pull
# (clean, merge and conflict), land, send and take. gh is never called (--no-gh,
# or commands that do not need it). Nothing outside the temporary directory is touched.
#
# Usage: tests/test-gu-fork.sh
# Exit:  0 all checks passed, 1 a check failed
# -----------------------------------------------------------------------------
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The scripts under test resolve the repo from $BU. env.sh exports BU into
# every configured shell, so without this a developer running the tests from
# their own shell would silently test a DIFFERENT checkout. Pin it.
export BU="$REPO"

U="$REPO/claude/skills/gu-common/bin/gu"
# TMPDIR ends with a slash on macOS, which would put "//" inside every path
# built from it. bootstrap.sh and setup-env.sh normalise the paths they print,
# so a "//" here compares a raw path against a normalised one and fails.
TMP_BASE="${TMPDIR:-/tmp}"; TMP_BASE="${TMP_BASE%/}"
T="$(mktemp -d "$TMP_BASE/gu-fork-test.XXXXXX")" || { echo "cannot create a temp dir" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
WORK="$T/work"
DEMO="$WORK/demo"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1
git config --global init.defaultBranch main
git config --global advice.detachedHead false

pass=0
fail=0
check() { # name, 0 to pass, [detail]
  if [ "$2" -eq 0 ]; then echo "  ok   $1"; pass=$((pass + 1)); else echo "  FAIL $1 ${3:-}"; fail=$((fail + 1)); fi
}
has() { case "$1" in *"$2"*) echo 0 ;; *) echo 1 ;; esac; }
gu() { # stdout in OUT, stderr in $T/err, status in RC
  RC=0
  OUT=$(cd "$DEMO" && WORK="$WORK" BU="${GU_TEST_BU:-}" GU_COLOR=never bash "$U" "$@" 2>"$T/err") || RC=$?
}
commit() { # dir file text message
  printf '%s\n' "$3" > "$1/$2" && git -C "$1" add "$2" && git -C "$1" commit -q -m "$4"
}

# The original, with a checkout to make upstream commits from
git init -q "$T/orig-src"
commit "$T/orig-src" a.txt one "Initial"
commit "$T/orig-src" b.txt one "Add b"
git clone -q --bare "$T/orig-src" "$T/orig.git"
git -C "$T/orig-src" remote add origin "$T/orig.git"
git clone -q --bare "$T/orig.git" "$T/fork.git"
mkdir -p "$WORK"
git clone -q "$T/fork.git" "$DEMO"

echo "1. wire: adds upstream with pushing disabled"
gu fork wire --url "$T/orig.git"
check "exit 0" "$RC" "($RC: $OUT $(cat "$T/err"))"
check "upstream remote added" "$([ "$(git -C "$DEMO" remote get-url upstream)" = "$T/orig.git" ] && echo 0 || echo 1)"
check "push to upstream disabled" "$(has "$(git -C "$DEMO" remote get-url --push upstream)" no_push)"
gu fork wire --url "$T/orig.git"
check "re-run is a no-op" "$([ "$RC" -eq 0 ] && [ "$(has "$OUT" added)" = 1 ] && echo 0 || echo 1)" "($OUT)"
git -C "$DEMO" fetch -q upstream
git -C "$DEMO" remote set-head upstream -a >/dev/null 2>&1
git -C "$DEMO" remote set-head origin -a >/dev/null 2>&1

echo "2. status: up to date"
gu fork status --no-gh
check "exit 0" "$RC" "($(cat "$T/err"))"
check "role fork" "$(has "$OUT" "role: fork")"
check "behind/ahead 0/0" "$(has "$OUT" "behind/ahead=0/0")"
gu fork pull
check "pull says up to date" "$(has "$OUT" UP_TO_DATE)" "($OUT)"

echo "3. clean pull: the original moves, the fork has nothing of its own -> fast-forward branch"
commit "$T/orig-src" c.txt one "Add c upstream"; git -C "$T/orig-src" push -q origin main
gu fork status --no-gh
check "1 incoming" "$(has "$OUT" "incoming: 1 commit")" "($OUT)"
gu fork pull --name sync/one
check "exit 0" "$RC" "($OUT $(cat "$T/err"))"
check "fast-forward" "$(has "$OUT" fast-forward)" "($OUT)"
WT="$DEMO/.claude/worktrees/sync/one"
check "worktree has the upstream commit" "$([ -f "$WT/c.txt" ] && echo 0 || echo 1)"
check "same SHA as upstream" "$([ "$(git -C "$WT" rev-parse HEAD)" = "$(git -C "$DEMO" rev-parse upstream/main)" ] && echo 0 || echo 1)"

echo "4. land: fast-forwards origin/main and keeps upstream's SHA"
gu fork land sync/one
check "exit 0" "$RC" "($OUT $(cat "$T/err"))"
check "origin main = upstream main" "$([ "$(git -C "$T/fork.git" rev-parse main)" = "$(git -C "$T/orig.git" rev-parse main)" ] && echo 0 || echo 1)"
git -C "$DEMO" pull -q --ff-only

echo "5. both sides move, no overlap -> merge commit"
commit "$T/orig-src" d.txt one "Add d upstream"; git -C "$T/orig-src" push -q origin main
commit "$DEMO" mine.txt mine "Add my file"; git -C "$DEMO" push -q origin main
gu fork status --no-gh
check "1 incoming, 1 outgoing" "$([ "$(has "$OUT" "incoming: 1")" = 0 ] && [ "$(has "$OUT" "outgoing: 1")" = 0 ] && echo 0 || echo 1)" "($OUT)"
check "outgoing lists my commit" "$(has "$OUT" "Add my file")"
gu fork pull --name sync/two
check "merge commit" "$(has "$OUT" "merge commit")" "($OUT)"
gu fork land sync/two
check "lands" "$RC" "($OUT)"
check "upstream commit reachable unchanged in the fork" "$(git -C "$T/fork.git" merge-base --is-ancestor "$(git -C "$T/orig.git" rev-parse main)" main && echo 0 || echo 1)"
git -C "$DEMO" pull -q --ff-only

echo "6. overlap -> CONFLICT reported with the file"
commit "$T/orig-src" a.txt upstream-edit "Edit a upstream"; git -C "$T/orig-src" push -q origin main
commit "$DEMO" a.txt fork-edit "Edit a in fork"; git -C "$DEMO" push -q origin main
gu fork status --no-gh
check "overlap lists a.txt" "$(has "$OUT" "  a.txt")" "($OUT)"
gu fork pull --name sync/three
check "exit non-zero" "$([ "$RC" -ne 0 ] && echo 0 || echo 1)"
check "CONFLICT a.txt" "$([ "$(has "$OUT" CONFLICT)" = 0 ] && [ "$(has "$OUT" "  a.txt")" = 0 ] && echo 0 || echo 1)" "($OUT)"
git -C "$DEMO/.claude/worktrees/sync/three" merge --abort

echo "7. land refuses a branch that is not a fast-forward"
git -C "$DEMO" branch old-branch HEAD~1
gu fork land old-branch
check "REFUSED" "$(has "$OUT" REFUSED)" "($OUT)"

echo "8. send: cherry-picks a fork commit onto upstream/main"
sha=$(git -C "$DEMO" log --format=%h -1 --grep "Add my file")
gu fork send --name send/my-file "$sha"
check "exit 0" "$RC" "($OUT $(cat "$T/err"))"
WT="$DEMO/.claude/worktrees/send/my-file"
check "based on upstream/main" "$([ "$(git -C "$WT" rev-parse HEAD~1)" = "$(git -C "$DEMO" rev-parse upstream/main)" ] && echo 0 || echo 1)"
check "cherry-pick -x trailer" "$(has "$(git -C "$WT" log -1 --format=%B)" "cherry picked from")"
check "next names a PR on the original" "$(has "$OUT" "gh pr create --repo ${T}/orig ")" "($OUT)"

echo "9. take: the original's owner picks a fork commit"
DEMO="$T/orig-src"
git -C "$DEMO" fetch -q "$T/fork.git" "+refs/heads/main:refs/remotes/forks/someone/main"
git -C "$DEMO" fetch -q origin
sha=$(git -C "$DEMO" log --format=%h -1 --grep "Add my file" forks/someone/main)
gu fork status --no-gh
check "status says original" "$(has "$OUT" "role: original")" "($OUT)"
gu fork take --name take/my-file "$sha"
check "exit 0" "$RC" "($OUT $(cat "$T/err"))"
check "author kept" "$(has "$OUT" "authors: t")" "($OUT)"

echo
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ] || exit 1
