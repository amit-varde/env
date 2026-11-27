#: worktree list|add|move|remove|cleanup|reset - linked worktrees in <repo>/.claude/worktrees/<name> (Claude Code's default)
# list [repo...] [--fetch] [--gh] [--view|--rows]
#   On a terminal (or --view): grouped by repo, one line per linked worktree:
#     <repo> : <main checkout> : <remote>
#          WORKTREE  PATH    PR      STATUS      BRANCH   (a header line, then one line per worktree)
#          <name>    <path>  PR#<n>  <status...> <branch>
#     status: dirty, merged, local-br-only, active (open PR), behind(N) (origin/<default> is N ahead),
#     missing, outside (not in <repo>/.claude/worktrees; wt-reset moves it). Always asks GitHub (one gh call per repo); works without it, minus PR and squash merges.
#   Piped (or --rows): repo|path|branch|dirty|notes, every worktree including the main checkout.
#   --fetch: git fetch --prune origin first, so upstream-gone is current.
#   --gh: one `gh pr list --state all` per repo, so squash-merged branches show as merged(#n).
# add <repo> <branch> [--name DIR] [--from REF] [--detach] [--submodules]
# add <repo> --pr N [--name DIR] [--detach] [--submodules]
#   DIR defaults to the branch (pr-<n> for --pr). Slashes are kept. A new branch
#   is refused while the repo is locked; --detach still works (hooks are skipped
#   for that one command; the lock covers the worktree once it exists). --from is the
#   start point for a new branch (default: origin's default, else the current branch).
# move <path> <new-name> [--branch]      rename the worktree directory; --branch also renames a
#                                        branch that was never pushed
# remove <path> [--force] [--delete-branch]
#   never the main worktree; dirty needs --force. --delete-branch then deletes the local branch
#   only when its work is already in the default branch: an ancestor of it, or the head of a
#   merged PR (squash merges). Otherwise it keeps the branch and prints "kept:".
# cleanup [repo...] [--apply]            list worktrees that are safe to delete: clean (no uncommitted or untracked
#                                        files) and merged, plus stale entries whose folder is gone. --apply removes
#                                        them (with their local branch) and clears the stale entries.
# reset [repo...] [--all] [--apply]      move linked worktrees that live elsewhere into <repo>/.claude/worktrees/
#   Dry run unless --apply. Cursor's worktrees (~/.cursor/worktrees/) are skipped unless --all: Cursor
#   tracks them, and moving one breaks its open window.
# Worktrees live where Claude Code puts its own: <main checkout>/.claude/worktrees/<name>, kept out of
# git status by a `.claude/worktrees/` line in .git/info/exclude (add writes it when missing).
# Notes: main, LOCKED, missing, outside (a linked worktree not in <repo>/.claude/worktrees), and one merge note:
#   merged             branch tip is in the default branch (merge or rebase merge)
#   merged(#n)         PR #n was merged with this tip as its head (squash merge; needs --gh)
#   pr-merged(#n)+local  PR #n was merged, but the local branch has commits the PR did not
#   upstream-gone      the branch tracked a remote branch that is now deleted (often: merged)
# Read-only except add, move, remove, cleanup --apply, reset --apply (and --fetch, which only fetches).

wt_main() {           # $1 any toplevel in the repo -> the main worktree path
  local line
  while IFS= read -r line; do
    case "$line" in
      worktree\ *) printf '%s\n' "${line#worktree }"; return 0 ;;
    esac
  done < <(git -C "$1" worktree list --porcelain 2>/dev/null)
  die "worktree: not a git repo: $1"
}

wt_check_name() {     # $1 directory name under <repo>/.claude/worktrees/
  local name="$1" rest part
  [ -n "$name" ] || die "worktree: name is empty"
  case "$name" in
    /*|~*) die "worktree: name must be a relative path: $name" ;;
    */) die "worktree: name must not end with /: $name" ;;
  esac
  rest=$name
  while [ -n "$rest" ]; do
    part=${rest%%/*}
    case "$part" in
      ""|.) die "worktree: name has an empty or '.' component: $name" ;;
      ..) die "worktree: name must not contain '..': $name" ;;
    esac
    case "$rest" in
      */*) rest=${rest#*/} ;;
      *) rest="" ;;
    esac
  done
}

wt_checked_out() {    # $1 main, $2 branch -> path if that branch is checked out
  local main="$1" branch="$2" line path=""
  while IFS= read -r line; do
    case "$line" in
      worktree\ *) path=${line#worktree } ;;
      branch\ *) [ "$line" = "branch refs/heads/$branch" ] && { printf '%s\n' "$path"; return 0; } ;;
    esac
  done < <(git -C "$main" worktree list --porcelain 2>/dev/null)
  return 1
}

wt_fetch_from() {     # $1 main, $2 ref. Fetch only remote-tracking refs (origin/main).
  local main="$1" from="$2" remote br
  case "$from" in
    */*)
      remote=${from%%/*}
      br=${from#*/}
      G "$main" remote get-url "$remote" >/dev/null || return 0
      GIT_TERMINAL_PROMPT=0 git -C "$main" fetch --quiet "$remote" "$br" \
        || die "worktree: fetch $from failed (network/sandbox?)"
      ;;
  esac
}

wt_fetch_pr() {       # $1 main, $2 number. Leaves the commit in FETCH_HEAD.
  GIT_TERMINAL_PROMPT=0 git -C "$1" fetch --quiet origin "refs/pull/$2/head" \
    || die "worktree: fetch pull/$2 failed (network/sandbox?)"
}

wt_default_from() {   # $1 main -> start ref for a new branch. No network.
  local main="$1" def
  def=$(git -C "$main" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
  if [ -n "$def" ] && git -C "$main" rev-parse --verify --quiet "refs/remotes/origin/$def" >/dev/null; then
    printf '%s\n' "origin/$def"
    return 0
  fi
  def=$(git -C "$main" symbolic-ref --short HEAD 2>/dev/null || true)
  if [ -n "$def" ]; then printf '%s\n' "$def"; return 0; fi
  if git -C "$main" rev-parse --verify --quiet refs/heads/main >/dev/null; then
    printf '%s\n' main
    return 0
  fi
  die "worktree: pass --from; no default branch"
}

WT_HINT="(sandbox? run it yourself: ! gu $GU_CMDLINE)"

wt_default() {        # $1 main -> WT_DEF (default branch) and WT_DEFREF (origin/<def> when it exists)
  WT_DEF=$(git -C "$1" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
  [ -z "$WT_DEF" ] && WT_DEF=$(git -C "$1" symbolic-ref --short HEAD 2>/dev/null || true)
  WT_DEFREF=$WT_DEF
  if [ -n "$WT_DEF" ] && git -C "$1" rev-parse --verify --quiet "refs/remotes/origin/$WT_DEF" >/dev/null; then
    WT_DEFREF="origin/$WT_DEF"
  fi
}

wt_gh_prs() {         # $1 main, $2 out file: "<head branch> <head sha> <number> <OPEN|MERGED|CLOSED>" (newest first)
  if ! ( cd "$1" && ghq pr list --state all --limit 200 --json headRefName,headRefOid,number,state \
          --jq '.[] | "\(.headRefName) \(.headRefOid) \(.number) \(.state)"' ) >"$2"; then
    warn "worktree: GitHub lookup failed for $(basename "$1"); PRs and squash merges are not shown"
    : >"$2"
  fi
}

wt_pr_of() {          # $1 pr file, $2 branch, $3 state -> newest PR number in that state, or nothing
  [ -n "$1" ] && [ -s "$1" ] || return 0
  awk -v b="$2" -v st="$3" '$1 == b && $4 == st { print $3; exit }' "$1"
}

wt_merge_note() {     # $1 main, $2 branch, $3 file from wt_gh_prs or "" -> one merge note, or nothing
  local main="$1" br="$2" ghf="$3" tip b sha num st
  wt_default "$main"
  [ -n "$WT_DEF" ] && [ "$br" != "$WT_DEF" ] || return 0
  tip=$(git -C "$main" rev-parse --verify --quiet "refs/heads/$br") || return 0
  # A branch still at the default tip has no work of its own yet: not "merged".
  if [ "$tip" != "$(git -C "$main" rev-parse --verify --quiet "$WT_DEFREF")" ] \
      && git -C "$main" merge-base --is-ancestor "$tip" "$WT_DEFREF" 2>/dev/null; then
    echo merged; return 0
  fi
  if [ -n "$ghf" ] && [ -s "$ghf" ]; then
    while read -r b sha num st; do
      [ "$b" = "$br" ] && [ "$st" = MERGED ] || continue
      # The tip is the PR head, or behind it: everything local went into the PR.
      if [ "$sha" = "$tip" ] || git -C "$main" merge-base --is-ancestor "$tip" "$sha" 2>/dev/null; then
        echo "merged(#$num)"
      else
        echo "pr-merged(#$num)+local"
      fi
      return 0
    done <"$ghf"
  fi
  if git -C "$main" config "branch.$br.merge" >/dev/null 2>&1 \
      && ! git -C "$main" rev-parse --verify --quiet "refs/heads/$br@{u}" >/dev/null 2>&1; then
    echo upstream-gone
  fi
}

wt_linked_top() {     # $1 path -> toplevel of a linked worktree; dies on the main worktree
  local path="$1" top gd
  [ -d "$path" ] || die "worktree: no such directory: $path"
  top=$(git -C "$path" rev-parse --show-toplevel 2>/dev/null) || die "worktree: not a git worktree: $path"
  # pwd -P: macOS /var is a symlink to /private/var, so the path the caller
  # passed and the path git reports can both name this directory.
  [ "$(cd "$path" && pwd -P)" = "$(cd "$top" && pwd -P)" ] || die "worktree: $path is inside $top; pass the worktree root"
  gd=$(git -C "$top" rev-parse --absolute-git-dir 2>/dev/null) || die "worktree: not a git worktree: $path"
  [ -f "$gd/commondir" ] || die "REFUSED: $top is the main worktree"
  printf '%s\n' "$top"
}

wt_lock_stale() {     # $1 main. A lock copied before the commondir fix does not cover linked worktrees.
  local top="$1" hook
  [ -n "$(lock_level "$top")" ] || return 0
  hook="$(commondir "$top")/gu-lock/hooks/reference-transaction"
  if [ -f "$hook" ] && ! grep -q commondir "$hook"; then
    warn "lock hook is old and does not cover linked worktrees; unlock and lock this repo again"
  fi
}

wt_root() {           # $1 main checkout -> <main>/.claude/worktrees, symlinks resolved like git records them
  local m
  m=$(cd "$1" 2>/dev/null && pwd -P) || m=$1
  printf '%s/.claude/worktrees\n' "$m"
}

wt_dest() {           # $1 main checkout, $2 name -> absolute directory
  local root dest
  root=$(wt_root "$1"); dest="$root/$2"
  case "$dest" in
    "$root"/*) ;;
    *) die "worktree: name escapes $root: $2" ;;
  esac
  printf '%s\n' "$dest"
}

wt_exclude() {        # $1 main checkout: keep .claude/worktrees/ out of git status, as Claude Code does
  local f
  f="$(commondir "$1")/info/exclude"
  grep -qx '\.claude/worktrees/' "$f" 2>/dev/null && return 0
  mkdir -p -- "$(dirname "$f")" && printf '.claude/worktrees/\n' >>"$f" \
    || warn "worktree: could not add .claude/worktrees/ to $f; the folder will show as untracked"
}

wt_emit() {           # $1 main, $2 path, $3 branch, $4 head, $5 detached(0|1), $6 gh file or ""
  local main="$1" path="$2" br="$3" head="$4" detached="$5" ghf="${6:-}"
  local repo dirty=- notes="" gd m
  repo=$(basename "$main")
  if [ "$detached" = 1 ]; then
    br="DETACHED@$(git -C "$main" rev-parse --short "$head" 2>/dev/null || printf '%s' "$head")"
  fi
  [ -n "$br" ] || br="-"
  if [ ! -d "$path" ]; then
    notes="missing"
  else
    dirty=$(n_dirty "$path")
    gd=$(git -C "$path" rev-parse --absolute-git-dir 2>/dev/null || true)
    if [ -z "$gd" ] || [ ! -f "$gd/commondir" ]; then
      notes="main"
    else
      case "$path/" in
        "$(wt_root "$main")"/*) ;;
        *) notes="outside" ;;
      esac
      if [ "$detached" != 1 ] && [ "$br" != "-" ]; then
        m=$(wt_merge_note "$main" "$br" "$ghf")
        [ -n "$m" ] && notes="${notes:+$notes }$m"
      fi
    fi
  fi
  [ -n "$(lock_level "$main")" ] && notes="${notes:+$notes }LOCKED"
  printf '%s|%s|%s|%s|%s\n' "$repo" "$path" "$br" "$dirty" "${notes:--}"
}

wt_list_repo() {      # $1 main, $2 gh file or ""
  local main="$1" ghf="${2:-}" line path="" br="" head="" detached=0
  while IFS= read -r line; do
    case "$line" in
      worktree\ *)
        [ -n "$path" ] && wt_emit "$main" "$path" "$br" "$head" "$detached" "$ghf"
        path=${line#worktree }
        br=""; head=""; detached=0
        ;;
      HEAD\ *) head=${line#HEAD } ;;
      branch\ *) br=${line#branch }; br=${br#refs/heads/} ;;
      detached) detached=1 ;;
      "")
        [ -n "$path" ] && wt_emit "$main" "$path" "$br" "$head" "$detached" "$ghf"
        path=""; br=""; head=""; detached=0
        ;;
    esac
  done < <(git -C "$main" worktree list --porcelain 2>/dev/null)
  [ -n "$path" ] && wt_emit "$main" "$path" "$br" "$head" "$detached" "$ghf"
}

wt_list() {
  local names=() r main fetch=0 usegh=0 ghf="" view=0
  [ "${GU_TTY:-}" = 1 ] && view=1
  case " $* " in *" --rows "*) view=0 ;; *" --view "*) view=1 ;; esac
  if [ "$view" -eq 1 ]; then wt_view "$@"; return; fi
  while [ $# -gt 0 ]; do
    case "$1" in
      --fetch) fetch=1 ;;
      --gh) usegh=1 ;;
      --rows|--view) ;;
      -*) die "worktree list: unknown option $1" ;;
      *) names+=("$1") ;;
    esac
    shift
  done
  repos_from_args ${names[@]+"${names[@]}"}
  [ ${#REPOS[@]} -gt 0 ] || die "worktree list: no git repos under $GU_WORK"
  [ "$usegh" -eq 1 ] && ghf=$(mktemp "${TMPDIR:-/tmp}/gu.XXXXXX")
  echo "repo|path|branch|dirty|notes"
  for r in "${REPOS[@]}"; do
    main=$(wt_main "$r") || exit 1
    if [ "$fetch" -eq 1 ] && G "$main" remote get-url origin >/dev/null; then
      GIT_TERMINAL_PROMPT=0 git -C "$main" fetch --prune --quiet origin \
        || warn "worktree: fetch failed for $(basename "$main") (network/sandbox?)"
    fi
    [ -n "$ghf" ] && wt_gh_prs "$main" "$ghf"
    wt_list_repo "$main" "$ghf"
  done
  [ -n "$ghf" ] && rm -f "$ghf"
  return 0
}

wt_add() {
  local repo="" branch="" name="" from="" pr="" detach=0 subs=0
  local top main dest start where hooks
  while [ $# -gt 0 ]; do
    case "$1" in
      --name) name="${2:-}"; shift ;;
      --name=*) name=${1#*=} ;;
      --from) from="${2:-}"; shift ;;
      --from=*) from=${1#*=} ;;
      --pr) pr="${2:-}"; shift ;;
      --pr=*) pr=${1#*=} ;;
      --detach) detach=1 ;;
      --submodules) subs=1 ;;
      -*) die "worktree add: unknown option $1" ;;
      *)
        if [ -z "$repo" ]; then repo=$1
        elif [ -z "$branch" ]; then branch=$1
        else die "worktree add: unexpected argument $1"
        fi ;;
    esac
    shift
  done
  [ -n "$repo" ] || die "usage: gu worktree add <repo> <branch> [--name DIR] [--from REF] [--detach] [--submodules]"
  if [ -n "$pr" ]; then
    case "$pr" in
      *[!0-9]*|"") die "worktree: --pr needs a number" ;;
    esac
    [ -z "$branch" ] || die "worktree: --pr does not take a branch argument"
    [ -z "$from" ] || die "worktree: --pr does not take --from"
    branch="pr-$pr"
  fi
  [ -n "$branch" ] || die "usage: gu worktree add <repo> <branch>|--pr N ..."
  [ -n "$name" ] || name=$branch
  wt_check_name "$name"
  top=$(resolve_repo "$repo") || exit 1
  main=$(wt_main "$top") || exit 1
  dest=$(wt_dest "$main" "$name") || exit 1
  if [ "$detach" -eq 0 ] && where=$(wt_checked_out "$main" "$branch"); then
    die "worktree: branch $branch is already checked out at $where (pick a new branch name, or --detach)"
  fi
  [ -e "$dest" ] && die "worktree: already exists: $dest"
  wt_lock_stale "$main"
  wt_exclude "$main"

  if [ "$detach" -eq 1 ]; then
    if [ -n "$pr" ]; then
      wt_fetch_pr "$main" "$pr"
      start=FETCH_HEAD
    elif [ -n "$from" ]; then
      wt_fetch_from "$main" "$from"
      start=$from
    else
      start=$branch
    fi
    mkdir -p -- "$(dirname "$dest")" || die "worktree: cannot create $(dirname "$dest") $WT_HINT"
    # A detached worktree creates no branch, but creating its HEAD is still a
    # ref update the lock hook refuses (the hook cannot tell it from a branch
    # switch). Skip hooks for this one command only; once the worktree exists,
    # the shared lock hook refuses commits and checkouts inside it.
    hooks=()
    [ -n "$(lock_level "$main")" ] && hooks=(-c core.hooksPath=/dev/null)
    git ${hooks[@]+"${hooks[@]}"} -C "$main" worktree add --detach "$dest" "$start" || die "worktree: add failed: $dest $WT_HINT"
  elif git -C "$main" show-ref --verify --quiet "refs/heads/$branch"; then
    mkdir -p -- "$(dirname "$dest")" || die "worktree: cannot create $(dirname "$dest") $WT_HINT"
    git -C "$main" worktree add "$dest" "$branch" || die "worktree: add failed: $dest $WT_HINT"
  else
    [ -z "$(lock_level "$main")" ] || die "REFUSED: $(basename "$main") is locked ($(lock_level "$main")); a new branch is a ref change. /gu-unlock first, or add --detach for a read-only worktree"
    if [ -n "$pr" ]; then
      wt_fetch_pr "$main" "$pr"
      start=FETCH_HEAD
    elif [ -n "$from" ]; then
      wt_fetch_from "$main" "$from"
      start=$from
    else
      start=$(wt_default_from "$main") || exit 1
      wt_fetch_from "$main" "$start"
    fi
    mkdir -p -- "$(dirname "$dest")" || die "worktree: cannot create $(dirname "$dest") $WT_HINT"
    git -C "$main" worktree add -b "$branch" "$dest" "$start" || die "worktree: add failed: $dest $WT_HINT"
  fi
  if [ "$subs" -eq 1 ] && [ -f "$dest/.gitmodules" ]; then
    git -C "$dest" submodule update --init --recursive || die "worktree: submodule update failed: $dest"
  fi
  echo "added: $dest"
}

wt_remove() {
  local force=0 delbr=0 path="" top main br note ghf where
  while [ $# -gt 0 ]; do
    case "$1" in
      --force) force=1 ;;
      --delete-branch) delbr=1 ;;
      -*) die "worktree remove: unknown option $1" ;;
      *) [ -n "$path" ] && die "worktree remove: unexpected argument $1"; path=$1 ;;
    esac
    shift
  done
  [ -n "$path" ] || die "usage: gu worktree remove <path> [--force] [--delete-branch]"
  top=$(wt_linked_top "$path") || exit 1
  if [ "$force" -eq 0 ] && [ -n "$(git -C "$top" status --porcelain --ignore-submodules=all)" ]; then
    die "REFUSED: $top has uncommitted changes (pass --force to remove it)"
  fi
  main=$(wt_main "$top") || exit 1
  br=$(git -C "$top" symbolic-ref --short -q HEAD || true)
  case "$PWD/" in "$top"/*|"$(cd "$top" && pwd -P)"/*) cd "$main" || exit 1 ;; esac
  if [ "$force" -eq 1 ]; then
    git -C "$main" worktree remove --force "$top" || die "worktree remove failed: $top $WT_HINT"
  else
    git -C "$main" worktree remove "$top" || die "worktree remove failed: $top $WT_HINT"
  fi
  echo "removed: $top"
  [ "$delbr" -eq 1 ] || return 0
  if [ -z "$br" ]; then echo "kept: no branch (the worktree was detached)"; return 0; fi
  if where=$(wt_checked_out "$main" "$br"); then echo "kept: $br is checked out at $where"; return 0; fi
  note=$(wt_merge_note "$main" "$br" "")
  if [ "$note" != merged ]; then
    ghf=$(mktemp "${TMPDIR:-/tmp}/gu.XXXXXX")
    wt_gh_prs "$main" "$ghf"
    note=$(wt_merge_note "$main" "$br" "$ghf")
    rm -f "$ghf"
  fi
  case "$note" in
    merged|merged\(#*\))
      # Safe to force: the check above proved the tip is already in $WT_DEFREF or a merged PR.
      # -d alone would refuse a squash-merged branch, and a branch merged into a default branch
      # the main checkout is not on.
      git -C "$main" branch -D -q "$br" || die "worktree: could not delete branch $br $WT_HINT"
      echo "deleted branch: $br ($note; its commits are in $WT_DEFREF)" ;;
    *)
      echo "kept: $br is not merged into $WT_DEFREF${note:+ ($note)}; delete it yourself only if you are sure: git -C $main branch -D $br" ;;
  esac
}

wt_move() {
  local renbr=0 path="" new="" top main dest br old d root
  while [ $# -gt 0 ]; do
    case "$1" in
      --branch) renbr=1 ;;
      -*) die "worktree move: unknown option $1" ;;
      *)
        if [ -z "$path" ]; then path=$1
        elif [ -z "$new" ]; then new=$1
        else die "worktree move: unexpected argument $1"
        fi ;;
    esac
    shift
  done
  [ -n "$path" ] && [ -n "$new" ] || die "usage: gu worktree move <path> <new-name> [--branch]"
  wt_check_name "$new"
  top=$(wt_linked_top "$path") || exit 1
  main=$(wt_main "$top") || exit 1
  dest=$(wt_dest "$main" "$new") || exit 1
  [ -e "$dest" ] && die "worktree: already exists: $dest"
  br=$(git -C "$top" symbolic-ref --short -q HEAD || true)
  if [ "$renbr" -eq 1 ]; then
    [ -n "$br" ] || die "worktree move: --branch needs a worktree on a branch (this one is detached)"
    [ "$br" != "$new" ] || die "worktree move: the branch is already called $new"
    git -C "$main" show-ref --verify --quiet "refs/heads/$new" && die "worktree move: branch $new already exists"
    if old=$(git -C "$main" config "branch.$br.merge" 2>/dev/null); then
      die "REFUSED: $br is pushed (tracks ${old#refs/heads/}); a local rename would split it from its remote branch and PR. Move the directory without --branch"
    fi
  fi
  case "$PWD/" in "$top"/*|"$(cd "$top" && pwd -P)"/*) cd "$main" || exit 1 ;; esac
  mkdir -p -- "$(dirname "$dest")" || die "worktree: cannot create $(dirname "$dest") $WT_HINT"
  git -C "$main" worktree move "$top" "$dest" || die "worktree move failed: $top $WT_HINT"
  # Drop folders the old name left empty (feature/foo -> feature/), but never .claude/worktrees itself.
  root=$(wt_root "$main")
  d=$(dirname "$top")
  while [ "$d" != "$root" ] && case "$d" in "$root"/*) true ;; *) false ;; esac; do
    rmdir "$d" 2>/dev/null || break
    d=$(dirname "$d")
  done
  echo "moved: $top -> $dest"
  if [ "$renbr" -eq 1 ]; then
    git -C "$main" branch -m "$br" "$new" || die "worktree moved, but renaming branch $br failed $WT_HINT"
    echo "branch: $br -> $new"
  fi
}

wt_cleanup() {        # list the worktrees that are safe to delete; remove all, some (asked), or none
  local names=() apply=0 dry=0 ask=0 r main repo prf line path br note kept=0 i n ans pick
  local -a CP CB KM KR KP KB KN SM SP
  while [ $# -gt 0 ]; do
    case "$1" in
      --apply) apply=1 ;;
      -n|--dry-run) dry=1 ;;
      -*) die "worktree cleanup: unknown option $1" ;;
      *) names+=("$1") ;;
    esac
    shift
  done
  # Ask on a terminal (the dispatcher sets GU_TTY); GU_INTERACTIVE=1 forces it (tests feed stdin).
  if [ "$apply" -eq 0 ] && [ "$dry" -eq 0 ]; then
    if [ "${GU_INTERACTIVE:-}" = 1 ] || { [ "${GU_TTY:-}" = 1 ] && [ -t 0 ]; }; then ask=1; fi
  fi
  repos_from_args ${names[@]+"${names[@]}"}
  [ ${#REPOS[@]} -gt 0 ] || die "worktree cleanup: no git repos under $GU_WORK"
  prf=$(mktemp "${TMPDIR:-/tmp}/gu.XXXXXX")
  KM=(); KR=(); KP=(); KB=(); KN=(); SM=(); SP=()
  for r in "${REPOS[@]}"; do
    main=$(wt_main "$r") || exit 1
    repo=$(basename "$main")
    CP=(); CB=(); path=""; br=""
    while IFS= read -r line; do
      case "$line" in
        worktree\ *) path=${line#worktree }; br="" ;;
        branch\ *) br=${line#branch refs/heads/} ;;
        "")
          if [ -n "$path" ] && [ "$path" != "$main" ]; then
            if [ ! -d "$path" ]; then SM+=("$main"); SP+=("$path"); else CP+=("$path"); CB+=("$br"); fi
          fi
          path="" ;;
      esac
    done < <(git -C "$main" worktree list --porcelain 2>/dev/null; echo)
    : >"$prf"
    if [ ${#CP[@]} -gt 0 ] && G "$main" remote get-url origin >/dev/null; then wt_gh_prs "$main" "$prf"; fi
    wt_default "$main"
    for i in "${!CP[@]}"; do
      path=${CP[$i]}; br=${CB[$i]}
      case "$PWD/" in "$path"/*|"$(cd "$path" && pwd -P)"/*) kept=$((kept + 1)); continue ;; esac
      [ -n "$br" ] || { kept=$((kept + 1)); continue; }
      [ -z "$(git -C "$path" status --porcelain --ignore-submodules=all 2>/dev/null | head -1)" ] || { kept=$((kept + 1)); continue; }
      note=$(wt_is_merged "$main" "$br" "$prf") || { kept=$((kept + 1)); continue; }
      KM+=("$main"); KR+=("$repo"); KP+=("$path"); KB+=("$br"); KN+=("$note")
    done
  done
  rm -f "$prf"

  local viewed=0
  if [ "${GU_TTY:-}" = 1 ] || [ "$ask" -eq 1 ]; then wt_cleanup_view "$kept"; viewed=1
  else
    for i in "${!KP[@]}"; do echo "remove|${KR[$i]}|${KP[$i]}|${KB[$i]}|${KN[$i]}"; done
    for i in "${!SP[@]}"; do echo "stale|$(basename "${SM[$i]}")|${SP[$i]}|folder is gone; only git's record of it is left"; done
  fi
  n=$(( ${#KP[@]} + ${#SP[@]} ))
  if [ "$n" -eq 0 ]; then echo "nothing to clean up ($kept kept)."; return 0; fi

  # Decide what goes: PICK[i]=1 for worktree i; STALE=1 clears the stale entries.
  local -a PICK; local stale=0
  for i in "${!KP[@]}"; do PICK[$i]=0; done
  if [ "$apply" -eq 1 ]; then
    for i in "${!KP[@]}"; do PICK[$i]=1; done; stale=1
  elif [ "$ask" -eq 1 ]; then
    gu_palette
    printf '%sRemove them?%s [a]ll, [s]elect one by one, [n]o (default): ' "$C_B" "$C_0" >&2
    read -r ans || ans=n
    case "$ans" in
      a|A|all) for i in "${!KP[@]}"; do PICK[$i]=1; done; stale=1 ;;
      s|S|select)
        for i in "${!KP[@]}"; do
          printf '  Remove %s%s%s (%s, branch %s)? [y/N] ' "$C_BLUE" "$(wt_name_of "${KM[$i]}" "${KP[$i]}")" "$C_0" "${KN[$i]}" "${KB[$i]}" >&2
          read -r pick || pick=n
          case "$pick" in y|Y|yes) PICK[$i]=1 ;; esac
        done
        if [ ${#SP[@]} -gt 0 ]; then
          printf '  Clear %d stale entr%s? [y/N] ' "${#SP[@]}" "$( [ ${#SP[@]} -eq 1 ] && echo y || echo ies)" >&2
          read -r pick || pick=n
          case "$pick" in y|Y|yes) stale=1 ;; esac
        fi ;;
      *) echo "nothing removed."; return 0 ;;
    esac
  else
    [ "$viewed" -eq 1 ] || echo "plan: ${#KP[@]} to remove, ${#SP[@]} stale, $kept kept (dirty, not merged, detached, or this shell's)."
    echo "Run again with --apply to remove them all (with their local branches), or without -n in a terminal to choose."
    return 0
  fi

  local removed=0 cleared=0 m
  for i in "${!KP[@]}"; do
    [ "${PICK[$i]}" = 1 ] || continue
    if ( wt_remove "${KP[$i]}" --delete-branch ); then removed=$((removed + 1)); fi
  done
  if [ "$stale" -eq 1 ] && [ ${#SP[@]} -gt 0 ]; then
    for m in $(printf '%s\n' "${SM[@]}" | awk '!seen[$0]++'); do
      if git -C "$m" worktree prune; then echo "cleared stale entries: $(basename "$m")"
      else warn "worktree: prune failed for $(basename "$m") $WT_HINT"; fi
    done
    cleared=${#SP[@]}
  fi
  echo "done: $removed removed, $cleared stale cleared, $(( ${#KP[@]} - removed )) left in the list, $kept kept."
  return 0
}

wt_cleanup_view() {   # $1 kept count. Colored, numbered list of KM/KR/KP/KB/KN and SM/SP (wt_cleanup's arrays)
  local kept="$1" i n=0 last="" wn=8 wp=4 wr=2 nm pr pth
  local -a VN VP VR
  gu_palette
  for i in "${!KP[@]}"; do
    VN[$i]=$(wt_name_of "${KM[$i]}" "${KP[$i]}"); VP[$i]=$(wt_home "${KP[$i]}")
    case "${KN[$i]}" in merged\(#*\)) pr=${KN[$i]#merged(#}; VR[$i]="PR#${pr%)}" ;; *) VR[$i]="-" ;; esac
    [ ${#VN[$i]} -gt $wn ] && wn=${#VN[$i]}; [ ${#VP[$i]} -gt $wp ] && wp=${#VP[$i]}; [ ${#VR[$i]} -gt $wr ] && wr=${#VR[$i]}
  done
  if [ ${#KP[@]} -gt 0 ]; then
    printf '%sSafe to delete%s %s(clean, and merged into the default branch)%s\n' "$C_B" "$C_0" "$C_D" "$C_0"
    for i in "${!KP[@]}"; do
      if [ "${KR[$i]}" != "$last" ]; then
        last=${KR[$i]}
        printf '%s%s%s%s %s:%s %s\n' "$C_B" "$C_BLUE" "$last" "$C_0" "$C_D" "$C_0" "$(wt_home "${KM[$i]}")"
        printf '     %s%-3s %s  %s  %s  %-8s %s%s\n' "$C_B" "#" "$(wt_pad WORKTREE "$wn")" "$(wt_pad PATH "$wp")" \
          "$(wt_pad PR "$wr")" STATUS BRANCH "$C_0"
      fi
      n=$((n + 1))
      printf '     %s%-3s%s %s%s%s  %s%s%s  %s%s%s  %s%-8s%s %s%s%s\n' "$C_D" "$n" "$C_0" \
        "$C_BLUE" "$(wt_pad "${VN[$i]}" "$wn")" "$C_0" "$C_WHT" "$(wt_pad "${VP[$i]}" "$wp")" "$C_0" \
        "$C_WHT" "$(wt_pad "${VR[$i]}" "$wr")" "$C_0" "$C_GRN" merged "$C_0" "$C_GRY" "${KB[$i]}" "$C_0"
    done
  fi
  if [ ${#SP[@]} -gt 0 ]; then
    printf '%sStale%s %s(folder already gone; only git'"'"'s record is left)%s\n' "$C_B" "$C_0" "$C_D" "$C_0"
    for i in "${!SP[@]}"; do
      printf '     %s%-8s%s %s%s%s  %s\n' "$C_YEL" missing "$C_0" "$C_WHT" "$(wt_home "${SP[$i]}")" "$C_0" "$(basename "${SM[$i]}")"
    done
  fi
  printf '%s%d to remove%s, %s%d stale%s, %s%d kept%s %s(dirty, not merged, detached, or this shell'"'"'s; wt list shows why)%s\n' \
    "$C_GRN" "${#KP[@]}" "$C_0" "$C_YEL" "${#SP[@]}" "$C_0" "$C_D" "$kept" "$C_0" "$C_D" "$C_0"
}

wt_home() { case "$1" in "$HOME"/*) printf '~/%s\n' "${1#"$HOME"/}" ;; *) printf '%s\n' "$1" ;; esac; }

wt_name_of() {        # $1 main, $2 worktree path -> its name (path under <repo>/.claude/worktrees/, else the folder name)
  local root
  root="$(wt_root "$1")/"
  case "$2/" in "$root"*) printf '%s\n' "${2#"$root"}" ;; *) basename "$2" ;; esac
}

wt_owner() {          # $1 worktree path -> cursor, or nothing (Cursor tracks its own worktrees)
  local h
  h=$(cd "$HOME" 2>/dev/null && pwd -P) || h=$HOME
  case "$1/" in "$HOME"/.cursor/worktrees/*|"$h"/.cursor/worktrees/*) echo cursor ;; esac
}

wt_is_merged() {      # $1 main, $2 branch, $3 pr file -> prints the merge note when the branch's work is merged
  local main="$1" br="$2" note
  note=$(wt_merge_note "$main" "$br" "$3")
  # A branch that was never pushed and is behind main has no commits of its own yet: not "merged".
  if [ "$note" = merged ] && ! git -C "$main" show-ref --verify --quiet "refs/remotes/origin/$br" \
      && ! git -C "$main" config "branch.$br.merge" >/dev/null 2>&1; then
    return 1
  fi
  case "$note" in merged|merged\(#*\)) echo "$note"; return 0 ;; esac
  return 1
}

wt_status() {         # $1 main, $2 path, $3 branch ("" if detached), $4 pr file -> status words
  local main="$1" path="$2" br="$3" prf="$4" out="" n
  [ -d "$path" ] || { echo missing; return; }
  case "$path/" in "$(wt_root "$main")"/*) ;; *) out="outside" ;; esac
  [ -n "$(git -C "$path" status --porcelain --ignore-submodules=all 2>/dev/null | head -1)" ] && out="${out:+$out }dirty"
  [ -n "$br" ] || { echo "${out:+$out }detached"; return; }
  wt_is_merged "$main" "$br" "$prf" >/dev/null && out="${out:+$out }merged"
  git -C "$main" show-ref --verify --quiet "refs/remotes/origin/$br" || out="${out:+$out }local-br-only"
  [ -n "$(wt_pr_of "$prf" "$br" OPEN)" ] && out="${out:+$out }active"
  case "$out" in *merged*) ;; *)
    n=$(git -C "$main" rev-list --count "refs/heads/$br..$WT_DEFREF" 2>/dev/null || echo 0)
    [ "${n:-0}" -gt 0 ] && out="${out:+$out }behind($n)" ;;
  esac
  echo "${out:--}"
}

wt_paint_status() {   # status words -> colored (Google palette)
  local w out=""
  for w in $1; do
    case "$w" in
      merged) w="$C_GRN$w$C_0" ;;
      active) w="$C_BLUE$w$C_0" ;;
      dirty|behind*) w="$C_YEL$w$C_0" ;;
      local-br-only|missing) w="$C_RED$w$C_0" ;;
      -|detached|outside) w="$C_D$w$C_0" ;;
    esac
    out="${out:+$out }$w"
  done
  printf '%s' "$out"
}

wt_pad() { printf '%s%*s' "$1" $(( $2 - ${#1} )) ''; }   # $1 text, $2 width (pads after the text)

wt_view() {           # grouped human view (see header)
  local names=() fetch=0 r main prf line path br head det slug quiet=0 i
  local -a N P B R S RP
  while [ $# -gt 0 ]; do
    case "$1" in
      --fetch) fetch=1 ;;
      --gh|--view|--rows) ;;
      -*) die "worktree list: unknown option $1" ;;
      *) names+=("$1") ;;
    esac
    shift
  done
  repos_from_args ${names[@]+"${names[@]}"}
  [ ${#REPOS[@]} -gt 0 ] || die "worktree list: no git repos under $GU_WORK"
  gu_palette
  prf=$(mktemp "${TMPDIR:-/tmp}/gu.XXXXXX")
  for r in "${REPOS[@]}"; do
    main=$(wt_main "$r") || exit 1
    N=(); P=(); B=(); R=(); S=()
    path=""; br=""; det=0
    while IFS= read -r line; do
      case "$line" in
        worktree\ *) path=${line#worktree }; br=""; det=0 ;;
        branch\ *) br=${line#branch refs/heads/} ;;
        detached) det=1 ;;
        "")
          if [ -n "$path" ] && [ "$path" != "$main" ]; then P+=("$path"); B+=("$br"); fi
          path="" ;;
      esac
    done < <(git -C "$main" worktree list --porcelain 2>/dev/null; echo)
    if [ ${#P[@]} -eq 0 ] && [ ${#names[@]} -eq 0 ]; then quiet=$((quiet + 1)); continue; fi
    if [ "$fetch" -eq 1 ] && G "$main" remote get-url origin >/dev/null; then
      GIT_TERMINAL_PROMPT=0 git -C "$main" fetch --prune --quiet origin \
        || warn "worktree: fetch failed for $(basename "$main") (network/sandbox?)"
    fi
    : >"$prf"
    if [ ${#P[@]} -gt 0 ] && G "$main" remote get-url origin >/dev/null; then wt_gh_prs "$main" "$prf"; fi
    wt_default "$main"
    slug=$(slug "$main"); [ -n "$slug" ] || slug="(no remote)"
    printf '%s%s%s%s %s:%s %s %s:%s %s%s%s\n' "$C_B" "$C_BLUE" "$(basename "$main")" "$C_0" \
      "$C_D" "$C_0" "$(wt_home "$main")" "$C_D" "$C_0" "$C_D" "$slug" "$C_0"
    local wn=8 wp=4 wr=2 ws=6          # at least as wide as the header labels
    RP=("${P[@]}")
    for i in "${!P[@]}"; do
      N[$i]=$(wt_name_of "$main" "${P[$i]}")
      P[$i]=$(wt_home "${P[$i]}")
      if [ -z "${B[$i]}" ]; then B[$i]="(detached)"; R[$i]="-"
      else
        R[$i]=$(wt_pr_of "$prf" "${B[$i]}" OPEN)
        [ -n "${R[$i]}" ] || R[$i]=$(wt_pr_of "$prf" "${B[$i]}" MERGED)
        R[$i]=${R[$i]:+PR#${R[$i]}}; R[$i]=${R[$i]:--}
      fi
      S[$i]=$(wt_status "$main" "${RP[$i]}" "${B[$i]#(detached)}" "$prf")
      [ ${#N[$i]} -gt $wn ] && wn=${#N[$i]}; [ ${#P[$i]} -gt $wp ] && wp=${#P[$i]}
      [ ${#R[$i]} -gt $wr ] && wr=${#R[$i]}; [ ${#S[$i]} -gt $ws ] && ws=${#S[$i]}
    done
    if [ ${#P[@]} -gt 0 ]; then
      printf '     %s%s  %s  %s  %s  %s%s\n' "$C_B" "$(wt_pad WORKTREE "$wn")" "$(wt_pad PATH "$wp")" \
        "$(wt_pad PR "$wr")" "$(wt_pad STATUS "$ws")" BRANCH "$C_0"
    fi
    for i in "${!P[@]}"; do
      # name blue, path and PR white, status in its own colors, branch grey (last, so it can run long)
      printf '     %s%s%s  %s%s%s  %s%s%s  %s%*s  %s%s%s\n' \
        "$C_BLUE" "$(wt_pad "${N[$i]}" "$wn")" "$C_0" "$C_WHT" "$(wt_pad "${P[$i]}" "$wp")" "$C_0" \
        "$( [ "${R[$i]}" = - ] && printf '%s' "$C_D" || printf '%s' "$C_WHT")" "$(wt_pad "${R[$i]}" "$wr")" "$C_0" \
        "$(wt_paint_status "${S[$i]}")" $(( ws - ${#S[$i]} )) '' "$C_GRY" "${B[$i]}" "$C_0"
    done
    [ ${#P[@]} -gt 0 ] || printf '     %s(no linked worktrees)%s\n' "$C_D" "$C_0"
  done
  rm -f "$prf"
  [ "$quiet" -gt 0 ] && printf '%s(%d repos without worktrees not shown)%s\n' "$C_D" "$quiet" "$C_0"
  return 0
}

wt_reset() {          # move linked worktrees that live elsewhere into <repo>/.claude/worktrees/
  local names=() all=0 apply=0 r main repo root line path br locked owner name dest k moved=0 todo=0 skipped=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --all) all=1 ;;
      --apply) apply=1 ;;
      -*) die "worktree reset: unknown option $1" ;;
      *) names+=("$1") ;;
    esac
    shift
  done
  repos_from_args ${names[@]+"${names[@]}"}
  [ ${#REPOS[@]} -gt 0 ] || die "worktree reset: no git repos under $GU_WORK"
  for r in "${REPOS[@]}"; do
    main=$(wt_main "$r") || exit 1
    repo=$(basename "$main")
    root=$(wt_root "$main")
    path=""; locked=0
    while IFS= read -r line; do
      case "$line" in
        worktree\ *) path=${line#worktree }; locked=0 ;;
        locked*) locked=1 ;;
        "")
          [ -n "$path" ] && [ "$path" != "$main" ] || { path=""; continue; }
          case "$path/" in "$root"/*) path=""; continue ;; esac     # already in place
          if [ ! -d "$path" ]; then echo "skip|$repo|$path|directory is gone (gu worktree cleanup)"; skipped=$((skipped+1)); path=""; continue; fi
          if [ "$locked" -eq 1 ]; then echo "skip|$repo|$path|locked (git worktree unlock)"; skipped=$((skipped+1)); path=""; continue; fi
          owner=$(wt_owner "$path")
          if [ -n "$owner" ] && [ "$all" -eq 0 ]; then
            echo "skip|$repo|$path|owned by $owner (close its window, then --all)"; skipped=$((skipped+1)); path=""; continue
          fi
          case "$PWD/" in "$path"/*) echo "skip|$repo|$path|this shell is inside it"; skipped=$((skipped+1)); path=""; continue ;; esac
          name=$(basename "$path"); dest="$root/$name"; k=2
          while [ -e "$dest" ]; do dest="$root/$name-$k"; k=$((k + 1)); done
          if [ "$apply" -eq 0 ]; then
            echo "move|$repo|$path|$dest"; todo=$((todo + 1))
          elif mkdir -p -- "$root" && wt_exclude "$main" && git -C "$main" worktree move "$path" "$dest"; then
            echo "moved|$repo|$path|$dest"; moved=$((moved + 1))
          else
            echo "skip|$repo|$path|git worktree move failed (submodules? $WT_HINT)"; skipped=$((skipped+1))
          fi
          path="" ;;
      esac
    done < <(git -C "$main" worktree list --porcelain 2>/dev/null; echo)
  done
  if [ "$apply" -eq 0 ]; then
    echo "plan: $todo to move, $skipped skipped. Run again with --apply to move them."
  else
    echo "done: $moved moved, $skipped skipped."
  fi
}

main() {
  local sub="${1:-}"
  [ $# -gt 0 ] && shift
  case "$sub" in
    list) wt_list "$@" ;;
    add) wt_add "$@" ;;
    move) wt_move "$@" ;;
    remove) wt_remove "$@" ;;
    cleanup) wt_cleanup "$@" ;;
    reset) wt_reset "$@" ;;
    *) die "usage: gu worktree list|add|move|remove|cleanup|reset" ;;
  esac
}
