#!/bin/sh
# gu-lock guard, copied into <gitdir>/gu-lock/hooks/<hook> by `gu lock`. Remove with `gu unlock <repo>`.
# Linked worktrees keep their own git dir. The lock state lives in the shared git dir (commondir).
hook=$(basename "$0")
gitdir=$(git rev-parse --absolute-git-dir 2>/dev/null) || exit 0
if [ -f "$gitdir/commondir" ]; then
  rel=$(sed -n '1s/[[:space:]]*$//p' "$gitdir/commondir")
  if [ -z "$rel" ]; then
    echo "gu-lock: cannot read $gitdir/commondir" >&2
    exit 1
  fi
  case "$rel" in
    /*) common=$rel ;;
    *) common=$(cd "$gitdir" && cd "$rel" && pwd) || { echo "gu-lock: cannot resolve $gitdir/commondir" >&2; exit 1; } ;;
  esac
else
  common=$gitdir
fi
state="$common/gu-lock/state"
[ -f "$state" ] || exit 0          # lock state gone: block nothing
say() {
  # Name the locked repo, not the linked worktree the command ran in.
  case "$common" in
    */.git) top=${common%/.git} ;;
    *) top=$(git rev-parse --show-toplevel 2>/dev/null) ;;
  esac
  reason=$(sed -n 's/^reason=//p' "$state")
  echo "gu-lock: $top is locked${reason:+ ($reason)}. $1" >&2
  echo "gu-lock: unlock with /gu-unlock $(basename "$top")  (or: gu unlock $(basename "$top"))" >&2
}
case "$hook" in
  reference-transaction)
    [ "$1" = prepared ] || { cat >/dev/null; exit 0; }
    blocked=""
    while read -r _old _new ref; do
      case "$ref" in
        refs/remotes/*|FETCH_HEAD) ;;          # fetch is allowed
        *) blocked="$blocked $ref" ;;
      esac
    done
    [ -z "$blocked" ] && exit 0
    say "Blocked update of:$blocked"; exit 1 ;;
  *) say "Blocked $hook."; exit 1 ;;
esac
