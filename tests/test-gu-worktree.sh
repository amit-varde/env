#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File: env/tests/test-gu-worktree.sh
# Description: gu worktree against a throwaway repo. No network.
# -----------------------------------------------------------------------------
# Builds a temporary $WORK with one repo and runs add, list, remove, cleanup, and
# the lock hook. Nothing outside the temporary directory is touched.
#
# Usage: tests/test-gu-worktree.sh
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
T="$(mktemp -d "$TMP_BASE/gu-worktree-test.XXXXXX")" || { echo "cannot create a temp dir" >&2; exit 1; }
[ -n "$T" ] && [ -d "$T" ] || { echo "cannot create a temp dir" >&2; exit 1; }
trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
WORK="$T/work"
DEMO="$WORK/demo"

pass=0
fail=0
check() { # name, 0 to pass, [detail]
  if [ "$2" -eq 0 ]; then
    echo "  ok   $1"
    pass=$((pass + 1))
  else
    echo "  FAIL $1 ${3:-}"
    fail=$((fail + 1))
  fi
}
has() { # echo 0 if $1 contains $2
  case "$1" in
    *"$2"*) echo 0 ;;
    *) echo 1 ;;
  esac
}
lacks() { # echo 0 if $1 does not contain $2
  case "$1" in
    *"$2"*) echo 1 ;;
    *) echo 0 ;;
  esac
}
gu() { # gu "$@"; stdout in OUT, stderr in $T/err, status in RC
  RC=0
  OUT=$(WORK="$WORK" bash "$U" "$@" 2>"$T/err") || RC=$?
}
absent() { # echo 0 if the branch does not exist
  if git -C "$DEMO" show-ref --verify --quiet "refs/heads/$1"; then echo 1; else echo 0; fi
}
# macOS /var is a symlink of /private/var. Git records the physical path.
physical() {
  local p="$1" tail=""
  while [ ! -e "$p" ] && [ "$p" != / ]; do
    tail="/${p##*/}$tail"
    p=$(dirname "$p")
  done
  if [ -e "$p" ]; then p=$(cd "$p" && pwd -P); fi
  printf '%s%s\n' "$p" "$tail"
}

mkdir -p "$DEMO"
git -C "$DEMO" init -q -b main
git -C "$DEMO" config user.email t@t
git -C "$DEMO" config user.name t
echo a > "$DEMO/f"
git -C "$DEMO" add f
git -C "$DEMO" commit -q -m a
echo b >> "$DEMO/f"
git -C "$DEMO" commit -q -am b
[ "$(git -C "$DEMO" rev-list --count HEAD)" = 2 ] || { echo "setup: expected two commits" >&2; exit 1; }
git -C "$DEMO" branch feature
git -C "$DEMO" branch topic

echo "1. add an existing branch beside the main checkout"
gu worktree add demo feature
check "add feature" "$RC" "$(cat "$T/err")"
FEAT="$DEMO/.claude/worktrees/feature"
check "directory is demo/.claude/worktrees/feature" "$([ -d "$FEAT" ] && echo 0 || echo 1)"
check "worktree is on feature" "$([ "$(git -C "$FEAT" branch --show-current)" = feature ] && echo 0 || echo 1)"
check "main stays on main" "$([ "$(git -C "$DEMO" branch --show-current)" = main ] && echo 0 || echo 1)"

echo "2. --name checks out the branch in a different directory"
gu worktree add demo topic --name other
check "add topic --name other" "$RC" "$(cat "$T/err")"
check "directory is other" "$([ -d "$DEMO/.claude/worktrees/other" ] && echo 0 || echo 1)"
check "other is on topic" "$([ "$(git -C "$DEMO/.claude/worktrees/other" branch --show-current)" = topic ] && echo 0 || echo 1)"

echo "3. bad names are refused and create nothing"
gu worktree add demo bad1 --from main --name ../x
check "../x is refused" "$([ "$RC" -ne 0 ] && echo 0 || echo 1)" "$(cat "$T/err")"
check "bad1 was not created" "$(absent bad1)"
gu worktree add demo bad2 --from main --name /tmp/x
check "/tmp/x is refused" "$([ "$RC" -ne 0 ] && echo 0 || echo 1)" "$(cat "$T/err")"
check "bad2 was not created" "$(absent bad2)"

echo "4. list shows the worktree; ws does not list it as a repo"
gu worktree list
check "list shows feature" "$(has "$OUT" "$(physical "$FEAT")")"
check "list marks the main checkout" "$(has "$OUT" "demo|$(physical "$DEMO")|main|0|main")"
check "a branch at the default tip is not merged" "$(lacks "$OUT" "merged")"
gu ws
check "ws does not list worktrees as repos" "$(lacks "$OUT" "worktrees")"
check "add excludes .claude/worktrees from git status" "$(has "$(cat "$DEMO/.git/info/exclude")" ".claude/worktrees/")"
check "the main checkout is not dirty" "$([ -z "$(git -C "$DEMO" status --porcelain)" ] && echo 0 || echo 1)"
check "ws still lists demo" "$(has "$OUT" "demo|")"

git -C "$DEMO" branch old main~1
gu worktree add demo old
gu worktree list demo
check "a branch behind the default tip is merged" "$(has "$OUT" "|old|0|merged")"
gu worktree remove "$DEMO/.claude/worktrees/old"
check "remove clean worktree" "$RC" "$(cat "$T/err")"

echo "5. adding the same branch names the existing path"
gu worktree add demo feature
check "second add fails" "$([ "$RC" -ne 0 ] && echo 0 || echo 1)"
check "second add names the path" "$(has "$(cat "$T/err")" "$(physical "$FEAT")")"

echo "6. dirty remove is refused; --force removes"
echo dirty >> "$FEAT/f"
gu worktree remove "$FEAT"
check "dirty remove fails" "$([ "$RC" -ne 0 ] && echo 0 || echo 1)" "$(cat "$T/err")"
check "directory remains" "$([ -d "$FEAT" ] && echo 0 || echo 1)"
gu worktree remove --force "$FEAT"
check "force remove" "$RC" "$(cat "$T/err")"
check "directory is gone" "$([ ! -d "$FEAT" ] && echo 0 || echo 1)"

echo "7. the main worktree cannot be removed"
gu worktree remove "$DEMO"
check "remove main fails" "$([ "$RC" -ne 0 ] && echo 0 || echo 1)" "$(cat "$T/err")"
check "main repo remains" "$([ -d "$DEMO/.git" ] && echo 0 || echo 1)"

echo "8. cleanup reports a worktree whose folder was deleted, and --apply clears it"
git -C "$DEMO" branch side
gu worktree add demo side
check "add side" "$RC" "$(cat "$T/err")"
SIDE="$DEMO/.claude/worktrees/side"
rm -rf "$SIDE"
gu worktree cleanup demo
check "cleanup lists it as stale" "$(has "$OUT" "stale|demo|$(physical "$SIDE")|")"
porcelain=$(git -C "$DEMO" worktree list --porcelain)
check "still registered before --apply" "$(has "$porcelain" "$(physical "$SIDE")")"
gu worktree cleanup --apply demo
check "cleanup --apply" "$RC" "$(cat "$T/err")"
porcelain=$(git -C "$DEMO" worktree list --porcelain)
check "registration is gone" "$(lacks "$porcelain" "$(physical "$SIDE")")"

echo "9. a lock refuses a new branch and blocks a commit in a detached worktree"
gu lock "$DEMO" --reason test
check "lock" "$RC" "$(cat "$T/err")"
gu worktree add demo blocked --from main
check "locked add is refused" "$([ "$RC" -ne 0 ] && echo 0 || echo 1)" "$(cat "$T/err")"
check "refusal says locked" "$(has "$(cat "$T/err")" "locked")"
check "blocked branch was not created" "$(absent blocked)"
gu worktree add demo main --detach --name ro
check "detached add while locked" "$RC" "$(cat "$T/err")"
RO="$DEMO/.claude/worktrees/ro"
echo c >> "$RO/f"
git -C "$RO" add f
commit_out=$(git -C "$RO" commit -m c 2>&1) || true
check "commit in the worktree is refused" "$(has "$commit_out" "gu-lock")"
check "refusal names the repo, not the worktree" "$(has "$commit_out" "/gu-unlock demo")"
check "worktree HEAD did not move" "$([ "$(git -C "$RO" rev-parse HEAD)" = "$(git -C "$DEMO" rev-parse main)" ] && echo 0 || echo 1)"
git -C "$RO" reset -q -- f; git -C "$RO" checkout -q -- f
co_out=$(git -C "$RO" checkout -q --detach main~1 2>&1) || true
check "checkout in the detached worktree is refused" "$(has "$co_out" "gu-lock")"
echo c >> "$DEMO/f"
main_out=$(git -C "$DEMO" commit -qam c 2>&1) || true
check "commit in the main checkout is still refused" "$(has "$main_out" "gu-lock")"
git -C "$DEMO" checkout -q -- f 2>/dev/null
switch_out=$(git -C "$DEMO" checkout -q side 2>&1) || true
check "branch switch in the main checkout is still refused" "$([ "$(git -C "$DEMO" branch --show-current)" = main ] && echo 0 || echo 1)" "$switch_out"

echo "10. a lock made with the old hook gets a warning"
gd=$(git -C "$DEMO" rev-parse --absolute-git-dir)
for h in "$gd"/gu-lock/hooks/*; do grep -v commondir "$h" > "$T/h" && cat "$T/h" > "$h"; done
gu worktree add demo main --detach --name ro2
check "detached add with the old hook" "$RC" "$(cat "$T/err")"
check "warns that the old hook misses worktrees" "$(has "$(cat "$T/err")" "does not cover linked worktrees")"
gu unlock "$DEMO"
check "unlock" "$RC" "$(cat "$T/err")"

echo "11. a branch whose remote branch was deleted shows upstream-gone"
ORIGIN="$T/origin.git"
git init -q --bare "$ORIGIN"
git -C "$DEMO" remote add origin "$ORIGIN"
git -C "$DEMO" push -q origin main 2>/dev/null
git -C "$DEMO" branch gonebr main
gu worktree add demo gonebr
GONE="$DEMO/.claude/worktrees/gonebr"
echo g > "$GONE/g"; git -C "$GONE" add g; git -C "$GONE" commit -q -m g
git -C "$GONE" push -q -u origin gonebr 2>/dev/null
git -C "$ORIGIN" branch -D gonebr >/dev/null
gu worktree list demo --fetch
check "list --fetch notes upstream-gone" "$(has "$OUT" "|gonebr|0|upstream-gone")"
gu worktree remove "$GONE" --delete-branch
check "remove --delete-branch on upstream-gone" "$RC" "$(cat "$T/err")"
check "worktree is removed" "$([ ! -d "$GONE" ] && echo 0 || echo 1)"
check "an unconfirmed branch is kept" "$([ "$(absent gonebr)" = 1 ] && echo 0 || echo 1)"
check "says it kept the branch" "$(has "$OUT" "kept: gonebr")"

echo "12. squash merges are found through GitHub (fake gh)"
mkdir -p "$T/bin"
printf '#!/bin/sh\ncat "$FAKE_GH_OUT" 2>/dev/null\n' > "$T/bin/gh"; chmod +x "$T/bin/gh"
ghu() { RC=0; OUT=$(PATH="$T/bin:$PATH" FAKE_GH_OUT="$T/gh.out" WORK="$WORK" bash "$U" "$@" 2>"$T/err") || RC=$?; }
git -C "$DEMO" branch sq main
gu worktree add demo sq
SQ="$DEMO/.claude/worktrees/sq"
echo s > "$SQ/s"; git -C "$SQ" add s; git -C "$SQ" commit -q -m s
printf 'other 0000000000000000000000000000000000000000 3 MERGED\nsq %s 7 MERGED\n' "$(git -C "$SQ" rev-parse HEAD)" > "$T/gh.out"
ghu worktree list demo --gh
check "list --gh notes merged(#7)" "$(has "$OUT" "|sq|0|merged(#7)")"
gu worktree list demo
check "without --gh it is not merged" "$(lacks "$OUT" "|sq|0|merged")"
echo s2 > "$SQ/s2"; git -C "$SQ" add s2; git -C "$SQ" commit -q -m s2
ghu worktree list demo --gh
check "a local commit after the PR shows +local" "$(has "$OUT" "|sq|0|pr-merged(#7)+local")"
ghu worktree remove "$SQ" --delete-branch
check "remove with an extra local commit" "$RC" "$(cat "$T/err")"
check "branch with extra commits is kept" "$([ "$(absent sq)" = 1 ] && echo 0 || echo 1)"
gu worktree add demo sq
printf 'sq %s 7 MERGED\n' "$(git -C "$DEMO" rev-parse sq)" > "$T/gh.out"
ghu worktree remove "$SQ" --delete-branch
check "remove --delete-branch after a squash merge" "$RC" "$(cat "$T/err")"
check "squash-merged branch is deleted" "$(absent sq)"
check "says why it was safe" "$(has "$OUT" "deleted branch: sq (merged(#7)")"
git -C "$DEMO" branch old2 main~1
gu worktree add demo old2
gu worktree remove "$DEMO/.claude/worktrees/old2" --delete-branch
check "a branch already in main is deleted" "$(absent old2)"

echo "13. move renames the directory, and the branch when it was never pushed"
git -C "$DEMO" branch topicx/mv main
gu worktree add demo topicx/mv
MV="$DEMO/.claude/worktrees/topicx/mv"
check "nested name creates topicx/mv" "$([ -d "$MV" ] && echo 0 || echo 1)"
gu worktree move "$MV" login-fix --branch
check "move --branch" "$RC" "$(cat "$T/err")"
check "new directory exists" "$([ -d "$DEMO/.claude/worktrees/login-fix" ] && echo 0 || echo 1)"
check "empty topicx/ folder is removed" "$([ ! -e "$DEMO/.claude/worktrees/topicx" ] && echo 0 || echo 1)"
check "branch is renamed" "$([ "$(git -C "$DEMO/.claude/worktrees/login-fix" branch --show-current)" = login-fix ] && echo 0 || echo 1)"
gu worktree move "$DEMO/.claude/worktrees/login-fix" ../escape
check "move refuses ../" "$([ "$RC" -ne 0 ] && echo 0 || echo 1)"
gu worktree move "$DEMO" x
check "move refuses the main worktree" "$([ "$RC" -ne 0 ] && echo 0 || echo 1)"
git -C "$DEMO" branch pushed main
gu worktree add demo pushed
git -C "$DEMO/.claude/worktrees/pushed" push -q -u origin pushed 2>/dev/null
gu worktree move "$DEMO/.claude/worktrees/pushed" renamed --branch
check "--branch refuses a pushed branch" "$([ "$RC" -ne 0 ] && echo 0 || echo 1)"
check "refusal says it is pushed" "$(has "$(cat "$T/err")" "is pushed")"
check "nothing moved" "$([ -d "$DEMO/.claude/worktrees/pushed" ] && echo 0 || echo 1)"
gu worktree move "$DEMO/.claude/worktrees/pushed" renamed
check "directory-only move of a pushed branch" "$RC" "$(cat "$T/err")"
check "branch name unchanged" "$([ "$(git -C "$DEMO/.claude/worktrees/renamed" branch --show-current)" = pushed ] && echo 0 || echo 1)"

echo "14. ctx names the worktree and sees the lock from inside it"
gu ctx "$DEMO/.claude/worktrees/renamed" --no-fetch --no-gh
check "ctx prints the worktree name" "$(has "$OUT" "worktree: renamed")"
gu lock "$DEMO"
gu ctx "$DEMO/.claude/worktrees/renamed" --no-fetch --no-gh
check "ctx in a worktree shows the lock" "$(has "$OUT" "lock=git")"
gu worktree list demo
check "list shows LOCKED" "$(has "$OUT" "LOCKED")"
gu unlock "$DEMO"

echo "15. no git status unless asked; color only on a terminal or when forced"
gu worktree list demo
check "no git status by default" "$(lacks "$(cat "$T/err")" "== git status")"
check "captured output has no color codes" "$(lacks "$OUT" "$(printf '\033[')")"
RC=0; OUT=$(GU_STATUS=1 WORK="$WORK" bash "$U" worktree list demo 2>"$T/err") || RC=$?
check "GU_STATUS=1 prints git status" "$(has "$(cat "$T/err")" "== git status: demo ==")"
RC=0; OUT=$(GU_COLOR=always WORK="$WORK" bash "$U" worktree list demo 2>"$T/err") || RC=$?
check "GU_COLOR=always colors" "$(has "$OUT" "$(printf '\033[1mrepo')")"
plain=$(printf '%s\n' "$OUT" | sed "s/$(printf '\033')\[[0-9;]*m//g")
check "the table is aligned, without |" "$(lacks "$plain" "|")"
check "the main row is still there" "$(has "$plain" "$(physical "$DEMO")")"
RC=0; OUT=$(GU_COLOR=always WORK="$WORK" bash "$U" worktree remove "$T/nope" 2>"$T/err") || RC=$?
check "a forced-color error keeps its exit code" "$([ "$RC" -eq 1 ] && echo 0 || echo 1)"
RC=0; OUT=$(GU_COLOR=never WORK="$WORK" bash "$U" worktree list demo 2>&1) || RC=$?
check "GU_COLOR=never stays plain" "$(has "$OUT" "repo|path|branch|dirty|notes")"
aliases=$(bash -c 'shopt -s expand_aliases; source "$1/alias" >/dev/null 2>&1; alias' _ "$REPO")
check "wt aliases are defined" "$(has "$aliases" "alias wt-rm='gu worktree remove --delete-branch'")"
check "wt-reset alias is defined" "$(has "$aliases" "alias wt-reset=")"
for a in gu-ws gu-ctx gu-prs gu-pr gu-ci gu-threads gu-branches gu-lock gu-unlock gu-locks gu-readme \
         gu-release gu-auth gu-worktree gu-status gu-pr-status gu-pr-review gu-merge gu-actions gu-repo; do
  check "alias $a is defined" "$(has "$aliases" "alias $a='gu")"
done
check "gu-update stays the command, not an alias" "$(lacks "$aliases" "alias gu-update='")"
check "wt-cleanup replaces wt-prune" "$( { printf '%s' "$aliases" | grep -q "alias wt-cleanup=" && ! printf '%s' "$aliases" | grep -q "wt-prune"; } && echo 0 || echo 1)"

echo "16. the grouped view: repo line, then name, path, branch, PR and status per worktree"
git -C "$DEMO" branch openpr main
gu worktree add demo openpr
git -C "$DEMO/.claude/worktrees/openpr" push -q -u origin openpr 2>/dev/null
printf 'openpr %s 21 OPEN\n' "$(git -C "$DEMO" rev-parse openpr)" > "$T/gh.out"
echo x > "$DEMO/.claude/worktrees/openpr/x"
git -C "$DEMO" branch lonely main~1
gu worktree add demo lonely
ghu worktree list demo --view
check "repo line: name : path : remote" "$(has "$OUT" "demo : ")"
check "remote shown" "$(has "$OUT" " : $T/origin")"
line=$(printf '%s\n' "$OUT" | grep ' openpr ')
check "open PR shown as PR#21" "$(has "$line" "PR#21")"
check "a header names the columns" "$(has "$OUT" "WORKTREE")"
check "open PR is active" "$(has "$line" "active")"
check "untracked file is dirty" "$(has "$line" "dirty")"
line=$(printf '%s\n' "$OUT" | grep ' lonely ')
check "unpushed branch is local-br-only" "$(has "$line" "local-br-only")"
check "a branch with no commits of its own is not merged" "$(lacks "$line" "merged")"
check "it is behind main" "$(has "$line" "behind(1)")"
check "the main checkout is not a row" "$(lacks "$(printf '%s\n' "$OUT" | sed 1d)" "$(physical "$DEMO") ")"
ghu worktree list demo --rows
check "--rows keeps the | format" "$(has "$OUT" "repo|path|branch|dirty|notes")"
rm -f "$DEMO/.claude/worktrees/openpr/x"

echo "17. reset gathers stray worktrees into <repo>/.claude/worktrees; Cursor's only with --all"
git -C "$DEMO" branch stray main
git -C "$DEMO" worktree add -q "$T/elsewhere/stray" stray
FAKEHOME="$T/home"; mkdir -p "$FAKEHOME/.cursor/worktrees/demo"
git -C "$DEMO" branch cur main
git -C "$DEMO" worktree add -q "$FAKEHOME/.cursor/worktrees/demo/cur" cur
hu() { RC=0; OUT=$(HOME="$FAKEHOME" WORK="$WORK" bash "$U" "$@" 2>"$T/err") || RC=$?; }
hu worktree list demo --view
check "view marks a stray worktree outside" "$(has "$(printf '%s\n' "$OUT" | grep ' stray ')" "outside")"
hu worktree reset demo
check "dry run plans the stray move" "$(has "$OUT" "move|demo|$(physical "$T/elsewhere/stray")|$(physical "$DEMO/.claude/worktrees/stray")")"
check "dry run skips the Cursor worktree" "$(has "$OUT" "owned by cursor")"
check "dry run leaves worktrees already in place alone" "$(lacks "$OUT" "/.claude/worktrees/openpr|")"
check "dry run moves nothing" "$([ -d "$T/elsewhere/stray" ] && echo 0 || echo 1)"
hu worktree reset demo --apply
check "reset --apply" "$RC" "$(cat "$T/err")"
check "stray is in demo/.claude/worktrees" "$([ -d "$DEMO/.claude/worktrees/stray" ] && [ ! -d "$T/elsewhere/stray" ] && echo 0 || echo 1)"
check "Cursor worktree left alone" "$([ -d "$FAKEHOME/.cursor/worktrees/demo/cur" ] && echo 0 || echo 1)"
hu worktree reset demo --all --apply
check "--all moves the Cursor worktree" "$([ -d "$DEMO/.claude/worktrees/cur" ] && echo 0 || echo 1)"
check "git knows the new path" "$(has "$(git -C "$DEMO" worktree list)" "$(physical "$DEMO/.claude/worktrees/cur")")"
hu worktree reset demo
check "nothing left to move" "$(has "$OUT" "plan: 0 to move")"

echo "18. cleanup lists only clean, merged worktrees, and --apply removes them with their branch"
git -C "$DEMO" branch done1 main
gu worktree add demo done1
D1="$DEMO/.claude/worktrees/done1"
echo d > "$D1/d"; git -C "$D1" add d; git -C "$D1" commit -q -m d
git -C "$DEMO" branch wip main
gu worktree add demo wip
echo w > "$DEMO/.claude/worktrees/wip/w"
printf 'done1 %s 31 MERGED\nwip %s 32 MERGED\n' "$(git -C "$D1" rev-parse HEAD)" "$(git -C "$DEMO" rev-parse wip)" > "$T/gh.out"
ghu worktree cleanup demo
check "squash-merged clean worktree is listed" "$(has "$OUT" "remove|demo|$(physical "$D1")|done1|merged(#31)")"
check "a dirty merged worktree is kept" "$(lacks "$OUT" "|wip|")"
check "an open-PR worktree is kept" "$(lacks "$OUT" "|openpr|")"
check "the plan says what was kept" "$(has "$OUT" "kept")"
check "dry run removes nothing" "$([ -d "$D1" ] && echo 0 || echo 1)"
ghu worktree cleanup demo --apply
check "cleanup --apply" "$RC" "$(cat "$T/err")"
check "merged worktree is removed" "$([ ! -d "$D1" ] && echo 0 || echo 1)"
check "its branch is deleted" "$(absent done1)"
check "the dirty one is still there" "$([ -d "$DEMO/.claude/worktrees/wip" ] && echo 0 || echo 1)"

echo "19. the view puts PR and status before the branch"
ghu worktree list demo --view
hdr=$(printf '%s\n' "$OUT" | grep 'WORKTREE')
check "columns: WORKTREE PATH PR STATUS BRANCH" "$(printf '%s\n' "$hdr" | grep -q 'WORKTREE *PATH *PR *STATUS *BRANCH' && echo 0 || echo 1)"
line=$(printf '%s\n' "$OUT" | grep ' wip ')
check "branch is the last column" "$(printf '%s\n' "$line" | grep -q 'wip *$' && echo 0 || echo 1)"

echo "20. cleanup asks: all, select one by one, or no"
mk_done() { # $1 branch: a clean worktree whose squash-merged PR has its tip
  git -C "$DEMO" branch "$1" main
  gu worktree add demo "$1"
  echo "$1" > "$DEMO/.claude/worktrees/$1/f$1"; git -C "$DEMO/.claude/worktrees/$1" add "f$1"
  git -C "$DEMO/.claude/worktrees/$1" commit -q -m "$1"
}
mk_done ia; mk_done ib
printf 'ia %s 41 MERGED\nib %s 42 MERGED\n' "$(git -C "$DEMO" rev-parse ia)" "$(git -C "$DEMO" rev-parse ib)" > "$T/gh.out"
ask() { RC=0; OUT=$(printf "$1" | PATH="$T/bin:$PATH" FAKE_GH_OUT="$T/gh.out" GU_INTERACTIVE=1 WORK="$WORK" bash "$U" worktree cleanup demo 2>"$T/err") || RC=$?; }
ask 'n\n'
check "answer n removes nothing" "$([ -d "$DEMO/.claude/worktrees/ia" ] && [ -d "$DEMO/.claude/worktrees/ib" ] && echo 0 || echo 1)"
check "the view numbers the worktrees" "$(has "$OUT" "Safe to delete")"
check "the prompt offers all/select/no" "$(has "$(cat "$T/err")" "[a]ll, [s]elect")"
ask 's\ny\nn\n'
check "select: y removes the first" "$([ ! -d "$DEMO/.claude/worktrees/ia" ] && echo 0 || echo 1)"
check "select: its branch is deleted" "$(absent ia)"
check "select: n keeps the second" "$([ -d "$DEMO/.claude/worktrees/ib" ] && echo 0 || echo 1)"
check "select asked about each one by name" "$(has "$(cat "$T/err")" "Remove ib")"
ask 'a\n'
check "all removes the rest" "$([ ! -d "$DEMO/.claude/worktrees/ib" ] && echo 0 || echo 1)"
check "a summary line follows" "$(has "$OUT" "done: 1 removed")"
RC=0; OUT=$(printf 'a\n' | PATH="$T/bin:$PATH" FAKE_GH_OUT="$T/gh.out" WORK="$WORK" bash "$U" worktree cleanup demo 2>&1) || RC=$?
check "piped without a terminal it never asks" "$(lacks "$OUT" "[a]ll")"

echo
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ]
