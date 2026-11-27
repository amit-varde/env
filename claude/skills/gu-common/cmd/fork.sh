# shellcheck shell=bash  # sourced by bin/gu, so no shebang of its own
#: fork status|wire|pull|land|send|forks|take - keep a GitHub fork and its original in step, always through PRs (/gu-fork-sync)
# status [repo] [--no-fetch] [--no-gh]
#   Read-only. Role (fork or original), the upstream remote and whether pushing to it is disabled,
#   behind/ahead of origin/<default> vs upstream/<default>, incoming commits (in the original, not
#   in the fork), outgoing commits (in the fork, not in the original; patch-equivalent ones left out),
#   files changed on both sides since they split, open sync/* and send/* PRs, and for the env repo
#   ($BU) the incoming files that change machine wiring (re-run setup-env.sh).
# wire [repo] [--upstream OWNER/NAME | --url URL]
#   Add the `upstream` remote (from GitHub's parent link when not given) and disable pushing to it.
# pull [repo] [--merge|--rebase] [--name BRANCH]
#   New worktree branch sync/upstream-<date> from origin/<default>, then merge (default) or rebase
#   upstream/<default> into it. Prints the path, OK or CONFLICT with the files. Does not push.
# land [repo] <branch>
#   Fast-forward origin/<default> to <branch> (git push origin <branch>:<default>, never forced),
#   so the original's commits keep their SHAs and the open PR shows as merged. Refuses a non-fast-forward.
# send [repo] --name BRANCH <sha>...
#   New worktree branch from upstream/<default> with the given fork commits cherry-picked (-x),
#   oldest first, ready to push to the fork and open a PR on the original. Does not push.
# forks [repo] [--fetch]
#   For the original's owner: every GitHub fork with behind/ahead of the default branch. --fetch also
#   fetches each fork's default branch to refs/remotes/forks/<owner>/<branch> and lists the commits
#   the original does not have.
# take [repo] --name BRANCH <sha>...
#   For the original's owner: new worktree branch from origin/<default> with commits from a fetched
#   fork cherry-picked (-x; authors are kept). Does not push.
# Read-only: status, forks without --fetch (and --fetch only adds remote-tracking refs).

FK_WIRING='^(setup-env\.sh|bootstrap\.sh|env\.sh|lib/|claude/settings\.json|claude/skills/|ssh/|dotfiles/|cursor/|tools/)'
FK_NOPUSH='no_push--send-changes-with-a-PR'

fk_repo_arg() {       # sets FK_ARGS (non-repo args) and FK_TOP from the first arg that is a repo
  local a found=0; FK_ARGS=()
  for a in "$@"; do
    if [ "$found" -eq 0 ] && [ "${a#-}" = "$a" ] && { [ -d "$a" ] || [ -d "$GU_WORK/$a" ]; } && try_repo "$a" >/dev/null; then
      FK_TOP=$(resolve_repo "$a"); found=1
    else
      FK_ARGS+=("$a")
    fi
  done
  [ "$found" -eq 1 ] || FK_TOP=$(resolve_repo "")
  [ -n "$FK_TOP" ] || exit 1
}
fk_def() {            # $1 top, $2 remote -> its default branch
  local d
  d=$(G "$1" symbolic-ref --short "refs/remotes/$2/HEAD" | sed "s#^$2/##")
  [ -z "$d" ] && d=$(GIT_TERMINAL_PROMPT=0 G "$1" ls-remote --symref "$2" HEAD | sed -n 's#^ref: refs/heads/\([^[:space:]]*\).*#\1#p')
  echo "${d:-main}"
}
fk_has_upstream() { G "$1" remote get-url upstream >/dev/null; }
fk_parent() {         # $1 top -> owner/name of the GitHub parent, empty when none or unknown
  local sl; sl=$(slug "$1")
  case "$sl" in */*) ;; *) return 0 ;; esac
  gh repo view "$sl" --json parent --jq 'if .parent then "\(.parent.owner.login)/\(.parent.name)" else "" end' 2>/dev/null
}
fk_fetch() {          # $1 top, remotes...
  local top="$1" r; shift
  for r in "$@"; do
    GIT_TERMINAL_PROMPT=0 G "$top" fetch --prune --quiet "$r" || warn "fetch $r failed (network/sandbox?) - $r state may be stale"
  done
}
fk_main() {           # $1 top -> main checkout
  dirname "$(commondir "$1")"
}
fk_newbranch() {      # $1 top, $2 base name -> a branch name that does not exist yet
  local b="$2" n=2
  while G "$1" show-ref --verify --quiet "refs/heads/$b" || G "$1" show-ref --verify --quiet "refs/remotes/origin/$b"; do
    b="$2-$n"; n=$((n + 1))
  done
  echo "$b"
}
fk_worktree() {       # $1 top, $2 branch, $3 from -> path of the new worktree (dies on failure)
  local out
  out=$(bash "$GU_HOME/bin/gu" worktree add "$1" "$2" --from "$3" 2>&1) || die "worktree add failed: $out"
  printf '%s\n' "$out" | sed -n 's/^added: //p' | tail -1
}
fk_conflicts() { G "$1" diff --name-only --diff-filter=U | sed 's/^/  /'; }
fk_picks() {          # $1 worktree, shas... -> cherry-pick -x each; prints OK or CONFLICT
  local wt="$1" s n=0; shift
  for s in "$@"; do
    if ! git -C "$wt" cherry-pick -x "$s" >/dev/null 2>&1; then
      if [ -z "$(G "$wt" diff --name-only --diff-filter=U)" ] && G "$wt" diff --cached --quiet; then
        git -C "$wt" cherry-pick --skip >/dev/null 2>&1   # already in the base: nothing to pick
        echo "  skipped (already there): $(G "$wt" log -1 --format='%h %s' "$s")"; continue
      fi
      kv result "CONFLICT at $(G "$wt" log -1 --format='%h %s' "$s") ($n of $# picked)"
      fk_conflicts "$wt"
      kv next "fix the files, git -C $wt add <files>, git -C $wt cherry-pick --continue; or --abort"
      return 1
    fi
    n=$((n + 1))
  done
  kv result "OK ($n picked)"
}

fk_status() {
  local fetch=1 usegh=1 a top sl up role def udef ba base inc out ov n
  for a in ${FK_ARGS[@]+"${FK_ARGS[@]}"}; do
    case "$a" in --no-fetch) fetch=0 ;; --no-gh) usegh=0 ;; *) die "fork status: unknown option $a" ;; esac
  done
  top=$FK_TOP; sl=$(slug "$top")
  kv repo "${top/#$HOME/~}  $sl"
  kv lock "$(lock_level "$top")"
  if fk_has_upstream "$top"; then
    up=$(slug "$top" upstream); role=fork
    case "$(G "$top" remote get-url --push upstream)" in "$FK_NOPUSH"|*no_push*|DISABLED) a=disabled ;; *) a="ENABLED (gu fork wire disables it)" ;; esac
    kv upstream "$up  push=$a"
  else
    up=""; [ "$usegh" = 1 ] && up=$(fk_parent "$top")
    if [ -n "$up" ]; then
      kv upstream "MISSING remote; GitHub parent is $up (gu fork wire $top)"
      kv role fork
      return 0
    fi
    kv role "original (no upstream remote$( [ "$usegh" = 1 ] && echo ', no GitHub parent'))"
    kv next "gu fork forks $top --fetch  (commits in forks you can take)"
    return 0
  fi
  kv role "$role"
  [ "$fetch" = 1 ] && fk_fetch "$top" origin upstream
  def=$(fk_def "$top" origin); udef=$(fk_def "$top" upstream)
  G "$top" rev-parse --verify --quiet "upstream/$udef" >/dev/null || die "no upstream/$udef yet: git -C $top fetch upstream"
  ba=$(behind_ahead "$top" "upstream/$udef" "origin/$def")
  kv default "origin/$def vs upstream/$udef  behind/ahead=$ba"
  base=$(G "$top" merge-base "origin/$def" "upstream/$udef")
  inc=$(G "$top" log --reverse --no-merges --format='%h %s (%an, %cr)' "origin/$def..upstream/$udef")
  n=$(printf '%s' "$inc" | grep -c .)
  kv incoming "$n commit(s) in upstream/$udef, not in origin/$def"
  [ -n "$inc" ] && printf '%s\n' "$inc" | head -25 | sed 's/^/  /'
  out=$(G "$top" log --reverse --no-merges --cherry-pick --right-only --format='%h %s (%an, %cr)' "upstream/$udef...origin/$def")
  n=$(printf '%s' "$out" | grep -c .)
  kv outgoing "$n commit(s) in origin/$def, not in upstream/$udef (oldest first)"
  [ -n "$out" ] && printf '%s\n' "$out" | head -40 | sed 's/^/  /'
  if [ -n "$base" ]; then
    ov=$(comm -12 <(G "$top" diff --name-only "$base" "upstream/$udef" | sort) <(G "$top" diff --name-only "$base" "origin/$def" | sort))
    kv overlap "$(printf '%s' "$ov" | grep -c .) file(s) changed on both sides (likely merge conflicts)"
    [ -n "$ov" ] && printf '%s\n' "$ov" | head -30 | sed 's/^/  /'
  else
    kv overlap "no common history with upstream"
  fi
  kv checkout "$(fk_main "$top")  branch=$(branch "$(fk_main "$top")")  dirty=$(n_dirty "$(fk_main "$top")")  vs origin/$def=$(behind_ahead "$(fk_main "$top")" "origin/$def" HEAD)"
  if [ -n "${BU:-}" ] && [ "$(cd "$(fk_main "$top")" && pwd -P)" = "$(cd "$BU" 2>/dev/null && pwd -P)" ]; then
    kv env "yes (this is \$BU: after landing, update the checkout, run the tests and env-doctor)"
    a=$(G "$top" diff --name-only "origin/$def" "upstream/$udef" | grep -E "$FK_WIRING")
    kv wiring "$(printf '%s' "$a" | grep -c .) incoming file(s) that setup-env.sh wires into the machine"
    [ -n "$a" ] && printf '%s\n' "$a" | head -20 | sed 's/^/  /'
  else
    kv env no
  fi
  if [ "$usegh" = 1 ]; then
    a=$(cd "$top" && ghq pr list --repo "$sl" --state open --json number,headRefName,url \
          --jq '.[] | select(.headRefName|test("^(sync|send|take)/")) | "#\(.number) \(.headRefName) \(.url)"' 2>&1) || a="unknown - $a"
    kv sync-prs "${a:-none}"
    a=$(cd "$top" && ghq pr list --repo "$up" --state open --author @me --json number,headRefName,url \
          --jq '.[] | "#\(.number) \(.headRefName) \(.url)"' 2>&1) || a="unknown - $a"
    kv upstream-prs "${a:-none}"
  fi
}

fk_wire() {
  local top=$FK_TOP up="" url="" a ourl
  set -- ${FK_ARGS[@]+"${FK_ARGS[@]}"}
  while [ $# -gt 0 ]; do
    case "$1" in
      --upstream) up="${2:-}"; shift ;;
      --url) url="${2:-}"; shift ;;
      *) die "fork wire: unknown option $1" ;;
    esac
    shift
  done
  if ! fk_has_upstream "$top"; then
    if [ -z "$url" ]; then
      [ -n "$up" ] || up=$(fk_parent "$top")
      [ -n "$up" ] || die "no GitHub parent found for $(slug "$top"); pass --upstream OWNER/NAME"
      ourl=$(G "$top" remote get-url origin)
      case "$ourl" in git@*|ssh://*) url="git@github.com:$up.git" ;; *) url="https://github.com/$up.git" ;; esac
    fi
    git -C "$top" remote add upstream "$url" 2>/dev/null \
      || { echo "NEEDS_USER: git -C $top remote add upstream $url && git -C $top remote set-url --push upstream $FK_NOPUSH  (sandbox? .git/config is read-only here)"; return 2; }
    echo "added: upstream -> $url"
  fi
  a=$(G "$top" remote get-url --push upstream)
  if [ "$a" != "$FK_NOPUSH" ]; then
    git -C "$top" remote set-url --push upstream "$FK_NOPUSH" 2>/dev/null \
      || { echo "NEEDS_USER: git -C $top remote set-url --push upstream $FK_NOPUSH  (sandbox?)"; return 2; }
    echo "push to upstream: disabled"
  fi
  kv upstream "$(slug "$top" upstream)  push=disabled"
}

fk_pull() {
  local top=$FK_TOP how=merge name="" def udef wt ba
  set -- ${FK_ARGS[@]+"${FK_ARGS[@]}"}
  while [ $# -gt 0 ]; do
    case "$1" in
      --merge) how=merge ;; --rebase) how=rebase ;;
      --name) name="${2:-}"; shift ;;
      *) die "fork pull: unknown option $1" ;;
    esac
    shift
  done
  fk_has_upstream "$top" || die "no upstream remote: gu fork wire $top"
  fk_fetch "$top" origin upstream
  def=$(fk_def "$top" origin); udef=$(fk_def "$top" upstream)
  ba=$(behind_ahead "$top" "upstream/$udef" "origin/$def")
  if [ "${ba%/*}" = 0 ]; then kv result "UP_TO_DATE (origin/$def has every commit of upstream/$udef)"; return 0; fi
  [ -n "$name" ] || name=$(fk_newbranch "$top" "sync/upstream-$(date +%Y%m%d)")
  wt=$(fk_worktree "$top" "$name" "origin/$def") || exit 1
  kv path "$wt"; kv branch "$name  (from origin/$def, $how upstream/$udef; fork behind/ahead=$ba)"
  if [ "$how" = merge ]; then
    if git -C "$wt" merge --no-edit -m "Merge upstream/$udef into $def" "upstream/$udef" >/dev/null 2>&1; then
      kv result "OK ($( [ "${ba#*/}" = 0 ] && echo 'fast-forward' || echo 'merge commit'))"
    else
      kv result "CONFLICT"; fk_conflicts "$wt"
      kv next "fix the files, git -C $wt add <files>, git -C $wt commit --no-edit; or git -C $wt merge --abort"
      return 1
    fi
  else
    if git -C "$wt" rebase "upstream/$udef" >/dev/null 2>&1; then
      kv result "OK (rebased; landing needs a force-with-lease update of $def, not a fast-forward)"
    else
      kv result "CONFLICT"; fk_conflicts "$wt"
      kv next "fix the files, git -C $wt add <files>, git -C $wt rebase --continue; or --abort"
      return 1
    fi
  fi
  kv next "git -C $wt push -u origin $name, then gh pr create --repo $(slug "$top") --base $def --head $name"
}

fk_land() {
  local top=$FK_TOP br="${FK_ARGS[0]:-}" def sha
  [ -n "$br" ] || die "usage: gu fork land [repo] <branch>"
  G "$top" show-ref --verify --quiet "refs/heads/$br" || die "no local branch $br"
  fk_fetch "$top" origin
  def=$(fk_def "$top" origin)
  [ "$br" != "$def" ] || die "land: $br is the default branch"
  if G "$top" show-ref --verify --quiet "refs/remotes/origin/$br" \
     && [ "$(G "$top" rev-parse "origin/$br")" != "$(G "$top" rev-parse "$br")" ]; then
    echo "REFUSED: local $br and origin/$br differ (push it, or pull the PR's new commits) so the PR and what lands match"
    return 2
  fi
  if ! G "$top" merge-base --is-ancestor "origin/$def" "$br"; then
    echo "REFUSED: $br is not a fast-forward of origin/$def (rebased, or $def moved). Pull again, or name --force-with-lease yourself."
    return 2
  fi
  sha=$(G "$top" rev-parse --short "$br")
  if GIT_TERMINAL_PROMPT=0 git -C "$top" push origin "$br:$def" 2>"${TMPDIR:-/tmp}/gu-land.$$"; then
    rm -f "${TMPDIR:-/tmp}/gu-land.$$"
    kv landed "origin/$def -> $sha (fast-forward; the PR from $br shows as merged)"
  else
    sed 's/^/  /' "${TMPDIR:-/tmp}/gu-land.$$"; rm -f "${TMPDIR:-/tmp}/gu-land.$$"
    echo "REFUSED: push to $def failed (protected branch?). Merge the PR with a merge commit instead: gh pr merge <n> --merge (not squash or rebase: they rewrite upstream's SHAs)"
    return 2
  fi
  kv checkout "$(fk_main "$top") is $(behind_ahead "$(fk_main "$top")" "origin/$def" HEAD) behind/ahead origin/$def (gu-update to fast-forward it)"
}

fk_send() {
  local top=$FK_TOP name="" udef wt shas=() a
  set -- ${FK_ARGS[@]+"${FK_ARGS[@]}"}
  while [ $# -gt 0 ]; do
    case "$1" in --name) name="${2:-}"; shift ;; -*) die "fork send: unknown option $1" ;; *) shas+=("$1") ;; esac
    shift
  done
  [ -n "$name" ] && [ ${#shas[@]} -gt 0 ] || die "usage: gu fork send [repo] --name BRANCH <sha>..."
  fk_has_upstream "$top" || die "no upstream remote: gu fork wire $top"
  for a in "${shas[@]}"; do G "$top" rev-parse --verify --quiet "$a^{commit}" >/dev/null || die "unknown commit $a"; done
  fk_fetch "$top" upstream
  udef=$(fk_def "$top" upstream)
  name=$(fk_newbranch "$top" "$name")
  wt=$(fk_worktree "$top" "$name" "upstream/$udef") || exit 1
  kv path "$wt"; kv branch "$name  (from upstream/$udef)"
  fk_picks "$wt" "${shas[@]}" || return 1
  kv next "git -C $wt push -u origin $name, then gh pr create --repo $(slug "$top" upstream) --base $udef --head $(slug "$top" | cut -d/ -f1):$name"
}

fk_forks() {
  local top=$FK_TOP fetch=0 a sl def rows f br owner ref log
  for a in ${FK_ARGS[@]+"${FK_ARGS[@]}"}; do case "$a" in --fetch) fetch=1 ;; *) die "fork forks: unknown option $a" ;; esac; done
  sl=$(slug "$top"); def=$(fk_def "$top" origin)
  rows=$(ghq api "repos/$sl/forks" --paginate --jq '.[] | "\(.full_name)|\(.default_branch)|\(.pushed_at)"') || exit 3
  [ -n "$rows" ] || { kv forks "none for $sl"; return 0; }
  [ "$fetch" = 1 ] && fk_fetch "$top" origin
  echo "fork|branch|behind/ahead vs $sl:$def|pushed"
  printf '%s\n' "$rows" | while IFS='|' read -r f br a; do
    owner=${f%%/*}
    log=$(ghq api "repos/$sl/compare/$def...$owner:$br" --jq '"\(.behind_by)/\(.ahead_by)"' 2>/dev/null) || log='?'
    echo "$f|$br|$log|$a"
    if [ "$fetch" = 1 ]; then
      ref="refs/remotes/forks/$owner/$br"
      if GIT_TERMINAL_PROMPT=0 G "$top" fetch --quiet "https://github.com/$f.git" "+refs/heads/$br:$ref"; then
        G "$top" log --reverse --no-merges --cherry-pick --right-only --format='  %h %s (%an, %cr)' "origin/$def...$ref" | head -30
      else
        echo "  fetch failed (no access, or network/sandbox)"
      fi
    fi
  done
}

fk_take() {
  local top=$FK_TOP name="" def wt shas=() a
  set -- ${FK_ARGS[@]+"${FK_ARGS[@]}"}
  while [ $# -gt 0 ]; do
    case "$1" in --name) name="${2:-}"; shift ;; -*) die "fork take: unknown option $1" ;; *) shas+=("$1") ;; esac
    shift
  done
  [ -n "$name" ] && [ ${#shas[@]} -gt 0 ] || die "usage: gu fork take [repo] --name BRANCH <sha>...  (gu fork forks --fetch first)"
  for a in "${shas[@]}"; do G "$top" rev-parse --verify --quiet "$a^{commit}" >/dev/null || die "unknown commit $a (gu fork forks $top --fetch first)"; done
  fk_fetch "$top" origin
  def=$(fk_def "$top" origin)
  name=$(fk_newbranch "$top" "$name")
  wt=$(fk_worktree "$top" "$name" "origin/$def") || exit 1
  kv path "$wt"; kv branch "$name  (from origin/$def)"
  fk_picks "$wt" "${shas[@]}" || return 1
  kv authors "$(G "$wt" log --format='%an' "origin/$def..HEAD" | sort -u | paste -sd, -)"
  kv next "git -C $wt push -u origin $name, then gh pr create --repo $(slug "$top") --base $def --head $name"
}

main() {
  local sub="${1:-status}"; [ $# -gt 0 ] && shift
  fk_repo_arg "$@"
  case "$sub" in
    status) fk_status ;;
    wire) fk_wire ;;
    pull) fk_pull ;;
    land) fk_land ;;
    send) fk_send ;;
    forks) fk_forks ;;
    take) fk_take ;;
    *) die "usage: gu fork status|wire|pull|land|send|forks|take [repo] ... (gu help)" ;;
  esac
}
