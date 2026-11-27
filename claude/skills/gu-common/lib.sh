# shellcheck shell=bash  # sourced by bin/gu, so no shebang of its own
# gu-common/lib.sh - shared functions for the gu-* skill kit. Sourced by bin/gu.
# Bash 3.2 compatible (macOS /bin/bash). No here-docs/here-strings: bash 3.2
# needs a writable temp dir for them, which fails inside locked repos.
# Output convention: one record per line, fields separated by '|'; key: value for single records.

GU_WORK="${WORK:-$HOME/work}"

# Color on a terminal: GU_COLOR=always|never wins, then NO_COLOR, then "is fd $1 a terminal".
gu_color() {          # $1 fd (1 or 2) -> 0 when output to it should be colored
  case "${GU_COLOR:-auto}" in always) return 0 ;; never) return 1 ;; esac
  [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ] && [ -t "$1" ]
}
gu_truecolor() { case "${COLORTERM:-}" in truecolor|24bit) return 0 ;; esac; return 1; }
# Google's palette: blue #4285F4, red #EA4335, yellow #FBBC05, green #34A853 (24-bit when the
# terminal says so, else the nearest 256-color). Empty strings when stdout is not colored.
gu_palette() {
  if gu_color 1; then
    C_B=$'\033[1m'; C_D=$'\033[2m'; C_0=$'\033[0m'; C_WHT=$'\033[97m'; C_GRY=$'\033[38;5;245m'
    if gu_truecolor; then
      C_BLUE=$'\033[38;2;66;133;244m'; C_RED=$'\033[38;2;234;67;53m'
      C_YEL=$'\033[38;2;251;188;5m'; C_GRN=$'\033[38;2;52;168;83m'
    else
      C_BLUE=$'\033[38;5;69m'; C_RED=$'\033[38;5;203m'; C_YEL=$'\033[38;5;214m'; C_GRN=$'\033[38;5;71m'
    fi
  else
    C_B=; C_D=; C_0=; C_WHT=; C_GRY=; C_BLUE=; C_RED=; C_YEL=; C_GRN=
  fi
}
die()  { if gu_color 2; then printf '\033[38;5;203mgu: %s\033[0m\n' "$*" >&2; else echo "gu: $*" >&2; fi; exit 1; }
warn() { if gu_color 2; then printf '\033[38;5;214mgu: %s\033[0m\n' "$*" >&2; else echo "gu: $*" >&2; fi; }

# ---------- repo discovery ----------
ws_repos() {          # top-level repos under $GU_WORK (absolute paths)
  local d
  for d in "$GU_WORK"/*/; do d="${d%/}"; [ -e "$d/.git" ] && echo "$d"; done
}
resolve_repo() {      # name under $GU_WORK, path, or empty (= current repo) -> toplevel
  local r="${1:-.}"
  [ -d "$r" ] || r="$GU_WORK/$1"
  [ -d "$r" ] || die "no such repo: $1"
  git -C "$r" rev-parse --show-toplevel 2>/dev/null || die "not a git repo: $r"
}
try_repo() {          # $1 name or path -> toplevel, or fail without dying
  local r="${1:-}"
  [ -n "$r" ] || return 1
  [ -d "$r" ] || r="$GU_WORK/$1"
  [ -d "$r" ] || return 1
  git -C "$r" rev-parse --show-toplevel 2>/dev/null
}
# Repos whose worktree to show after a command. Named repos win. With no repo
# argument, ws and locks cover every repo under $GU_WORK; anything else uses
# the current repo when there is one.
gu_status_targets() { # $1 command, rest: its args. One toplevel per line.
  local cmd="$1" a nopt=0 found=0 top
  shift
  for a in "$@"; do
    case "$a" in -*) continue ;; esac
    nopt=1
    if top=$(try_repo "$a"); then printf '%s\n' "$top"; found=1; fi
  done
  if [ "$found" -eq 0 ] && [ "$nopt" -eq 0 ]; then
    case "$cmd" in ws|locks) ws_repos; return ;; esac
  fi
  if [ "$found" -eq 0 ]; then
    top=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
    printf '%s\n' "$top"
  fi
}
repos_from_args() {   # names/paths -> REPOS array of toplevels; no args = every repo under $GU_WORK
  local r t; REPOS=()
  if [ $# -eq 0 ]; then
    while read -r r; do REPOS+=("$r"); done < <(ws_repos); return 0
  fi
  for r in "$@"; do t=$(resolve_repo "$r") || exit 1; REPOS+=("$t"); done
}
submodules() {        # $1 top -> "<state>|<abs path>" per submodule, recursive; state: ' ' + - U
  local top="$1" l st
  git -C "$top" submodule status --recursive 2>/dev/null | while IFS= read -r l; do
    [ -n "$l" ] || continue
    st="${l:0:1}"; set -- ${l:1}; echo "$st|$top/$2"
  done
}
init_submodules() {   # $1 top -> abs paths of initialized submodules, recursive
  submodules "$1" | awk -F'|' '$1!="-"{print $2}'
}

# ---------- per-repo facts (all take the toplevel path) ----------
G()           { git -C "$1" "${@:2}" 2>/dev/null; }
gitdir()      { G "$1" rev-parse --absolute-git-dir; }
commondir()   { G "$1" rev-parse --path-format=absolute --git-common-dir; }  # shared by every worktree of the repo
branch()      { G "$1" symbolic-ref --short -q HEAD || echo "DETACHED@$(G "$1" rev-parse --short HEAD)"; }
upstream()    { G "$1" rev-parse --abbrev-ref --symbolic-full-name '@{u}' || echo "-"; }
upstream_gone(){ G "$1" config "branch.$2.merge" >/dev/null; }   # $2 has no upstream ref but is configured for one
behind_ahead(){ G "$1" rev-list --left-right --count "$2...$3" | awk '{print $1"/"$2}'; }  # behind/ahead of $3 vs $2
default_branch() {
  local d
  d=$(G "$1" symbolic-ref --short refs/remotes/origin/HEAD | sed 's#^origin/##')
  [ -z "$d" ] && d=$(G "$1" ls-remote --symref origin HEAD | sed -n 's#^ref: refs/heads/\([^[:space:]]*\).*#\1#p')
  echo "${d:-?}"
}
n_dirty()     { G "$1" status --porcelain --untracked-files=no --ignore-submodules=all | wc -l | tr -d ' '; }
n_untracked() { G "$1" ls-files --others --exclude-standard | wc -l | tr -d ' '; }

# A fast-forward is safe when nothing local would be lost. Tracked changes must
# already be the incoming blobs (worktree matches @{u}, and the index is either
# HEAD or that same worktree). Untracked files that @{u} also adds must be the
# same bytes and mode. An untracked file @{u} does not have is fine on a clean
# tree, and blocks the fast-forward when any tracked file is already modified:
# that mix is real local work, not a partial copy of the incoming commit.
ff_path_is_upstream_copy() { # $1 top, $2 path -> 0 if the worktree copy is @{u}
  local top="$1" path="$2" st
  G "$top" diff --quiet --no-ext-diff --ignore-submodules=all '@{u}' -- "$path"; st=$?
  [ "$st" -eq 0 ] || return 1
  G "$top" diff --quiet --cached --no-ext-diff --ignore-submodules=all -- "$path"; st=$?
  [ "$st" -eq 0 ] && return 0
  G "$top" diff --quiet --no-ext-diff --ignore-submodules=all -- "$path"; st=$?
  [ "$st" -eq 0 ]
}
ff_untracked_blob_matches() { # $1 top, $2 path -> 0 same blob, 1 differs, 2 not in @{u}
  local top="$1" path="$2" full blob kind hash mode lm
  blob=$(G "$top" rev-parse -q --verify "@{u}:$path") || return 2
  kind=$(G "$top" cat-file -t "$blob") || return 1
  [ "$kind" = blob ] || return 1
  full="$top/$path"
  hash=$(G "$top" hash-object -- "$full") || return 1
  [ "$hash" = "$blob" ] || return 1
  mode=$(G "$top" ls-tree '@{u}' -- "$path" | awk '{print $1}')
  if [ -L "$full" ]; then lm=120000
  elif [ -x "$full" ]; then lm=100755
  else lm=100644; fi
  [ "$mode" = "$lm" ]
}
ff_worktree_is_upstream() { # $1 top -> 0 if ff would not lose local work
  local top="$1" path tmp tracked=0 st
  G "$top" rev-parse --verify -q '@{u}^{commit}' >/dev/null || return 1
  tmp=$(mktemp "${TMPDIR:-/tmp}/gu.XXXXXX") || return 1
  if ! G "$top" diff -z --name-only --no-renames --ignore-submodules=all HEAD >"$tmp"; then
    rm -f "$tmp"; return 1
  fi
  while IFS= read -r -d '' path; do
    [ -n "$path" ] || continue
    tracked=1
    if ! ff_path_is_upstream_copy "$top" "$path"; then rm -f "$tmp"; return 1; fi
  done < "$tmp"
  if ! G "$top" ls-files -z --others --exclude-standard >"$tmp"; then
    rm -f "$tmp"; return 1
  fi
  while IFS= read -r -d '' path; do
    [ -n "$path" ] || continue
    ff_untracked_blob_matches "$top" "$path"; st=$?
    if [ "$st" -eq 1 ] || { [ "$st" -eq 2 ] && [ "$tracked" -ne 0 ]; }; then
      rm -f "$tmp"; return 1
    fi
  done < "$tmp"
  rm -f "$tmp"
  return 0
}
ff_drop_clear_lists() {
  rm -f "${FF_CLEAR_TRACKED:-}" "${FF_CLEAR_UNTRACKED:-}"
  FF_CLEAR_TRACKED=
  FF_CLEAR_UNTRACKED=
  FF_CLEAR_MSG=
}
# Record paths whose worktree bytes are already @{u}, then put those tracked
# paths back to HEAD and remove the matching untracked files so pull --ff-only
# can update every file. FF_CLEAR_* keeps the list so a failed pull can restore.
ff_clear_upstream_copies() { # $1 top -> 0, sets FF_CLEAR_MSG when it cleared any
  local top="$1" path mark tmp tracked untracked st cleared=0
  ff_drop_clear_lists
  ff_worktree_is_upstream "$top" || return 1
  tmp=$(mktemp "${TMPDIR:-/tmp}/gu.XXXXXX") || return 1
  tracked=$(mktemp "${TMPDIR:-/tmp}/gu.XXXXXX") || { rm -f "$tmp"; return 1; }
  untracked=$(mktemp "${TMPDIR:-/tmp}/gu.XXXXXX") || { rm -f "$tmp" "$tracked"; return 1; }
  if ! G "$top" diff -z --name-only --no-renames --ignore-submodules=all HEAD >"$tmp"; then
    rm -f "$tmp" "$tracked" "$untracked"; return 1
  fi
  while IFS= read -r -d '' path; do
    [ -n "$path" ] || continue
    if ! ff_path_is_upstream_copy "$top" "$path"; then
      rm -f "$tmp" "$tracked" "$untracked"; return 1
    fi
    # W: index is still HEAD (unstaged). S: index already matches the worktree.
    G "$top" diff --quiet --cached --no-ext-diff --ignore-submodules=all -- "$path"; st=$?
    if [ "$st" -eq 0 ]; then printf 'W\0%s\0' "$path" >> "$tracked"
    else printf 'S\0%s\0' "$path" >> "$tracked"; fi
  done < "$tmp"
  if ! G "$top" ls-files -z --others --exclude-standard >"$tmp"; then
    rm -f "$tmp" "$tracked" "$untracked"; return 1
  fi
  while IFS= read -r -d '' path; do
    [ -n "$path" ] || continue
    ff_untracked_blob_matches "$top" "$path"; st=$?
    if [ "$st" -eq 0 ]; then printf '%s\0' "$path" >> "$untracked"
    elif [ "$st" -eq 1 ]; then rm -f "$tmp" "$tracked" "$untracked"; return 1; fi
  done < "$tmp"
  rm -f "$tmp"
  FF_CLEAR_TRACKED=$tracked
  FF_CLEAR_UNTRACKED=$untracked
  while IFS= read -r -d '' mark && IFS= read -r -d '' path; do
    [ -n "$path" ] || continue
    # Reset both index and worktree to HEAD so pull --ff-only can rewrite the
    # path. checkout -- would only copy the index, and a staged @{u} blob would
    # still block the fast-forward. An add that is not in HEAD is removed;
    # pull creates it.
    if G "$top" cat-file -e "HEAD:$path"; then
      G "$top" checkout -q HEAD -- "$path" || return 1
    else
      G "$top" reset -q HEAD -- "$path" || return 1
      rm -f -- "$top/$path" || return 1
    fi
    cleared=1
  done < "$tracked"
  while IFS= read -r -d '' path; do
    [ -n "$path" ] || continue
    ff_untracked_blob_matches "$top" "$path"; st=$?
    [ "$st" -eq 0 ] || return 1
    rm -f -- "$top/$path" || return 1
    cleared=1
  done < "$untracked"
  [ "$cleared" -eq 1 ] && FF_CLEAR_MSG="cleared upstream copies"
  return 0
}
ff_restore_upstream_copies() { # $1 top: put back what ff_clear_upstream_copies removed
  local top="$1" path mark full mode
  [ -n "${FF_CLEAR_TRACKED:-}" ] && [ -f "$FF_CLEAR_TRACKED" ] || return 0
  while IFS= read -r -d '' mark && IFS= read -r -d '' path; do
    [ -n "$path" ] || continue
    if G "$top" cat-file -e "@{u}:$path"; then
      G "$top" checkout -q '@{u}' -- "$path" || return 1
      # W was unstaged: leave the @{u} bytes in the worktree only. S was staged.
      if [ "$mark" = W ]; then G "$top" reset -q HEAD -- "$path" || return 1; fi
    else
      # @{u} deleted the path, so checkout cannot name it. Drop the worktree
      # file; a staged deletion (S) comes out of the index too.
      rm -f -- "$top/$path" || return 1
      if [ "$mark" = S ]; then G "$top" rm -q --cached -- "$path" || return 1; fi
    fi
  done < "$FF_CLEAR_TRACKED"
  [ -n "${FF_CLEAR_UNTRACKED:-}" ] && [ -f "$FF_CLEAR_UNTRACKED" ] || return 0
  while IFS= read -r -d '' path; do
    [ -n "$path" ] || continue
    full="$top/$path"
    mkdir -p -- "$(dirname "$full")"
    G "$top" cat-file blob "@{u}:$path" > "$full" || return 1
    mode=$(G "$top" ls-tree '@{u}' -- "$path" | awk '{print $1}')
    if [ "$mode" = 100755 ]; then chmod +x -- "$full"; fi
  done < "$FF_CLEAR_UNTRACKED"
  return 0
}
n_stash()     { G "$1" stash list | wc -l | tr -d ' '; }
op_in_progress() {
  local g; g=$(gitdir "$1")
  if [ -d "$g/rebase-merge" ] || [ -d "$g/rebase-apply" ]; then echo REBASE
  elif [ -f "$g/MERGE_HEAD" ]; then echo MERGE
  elif [ -f "$g/CHERRY_PICK_HEAD" ]; then echo CHERRY-PICK
  elif [ -f "$g/REVERT_HEAD" ]; then echo REVERT
  else echo -; fi
}
lock_field()  { local s; s="$(commondir "$1")/gu-lock/state"; [ -f "$s" ] && sed -n "s/^$2=//p" "$s"; }  # $2: level|reason|date|prev_hooks...
lock_level()  { lock_field "$1" level; }
slug() {              # owner/repo of a remote (default origin)
  G "$1" remote get-url "${2:-origin}" | sed -E 's#^(https://[^/]+/|git@[^:]+:|ssh://git@[^/]+/)##; s#\.git$##'
}
last_commit_age() { G "$1" log -1 --format='%cr'; }

# ---------- network ----------
fetch_all() {         # $1 logdir, rest: repos. Parallel fetch; failures recorded in <logdir>/<name>.fetch
  local log="$1" r; shift
  for r in "$@"; do
    ( GIT_TERMINAL_PROMPT=0 git -C "$r" fetch --all --prune --quiet >"$log/$(basename "$r").fetch" 2>&1 \
        || echo FETCH_FAILED >>"$log/$(basename "$r").fetch" ) &
  done
  wait
}
fetch_error() {       # $1 logdir, $2 name -> first error line, empty if ok
  local f="$1/$2.fetch"
  [ -f "$f" ] && grep -q FETCH_FAILED "$f" && { grep -v FETCH_FAILED "$f" | head -1; [ -s "$f" ] || echo failed; }
}

# gh wrapper: runs gh, classifies failures so callers/skills get one actionable line.
#   exit 0 ok; 3 = classified failure (message on stderr: "gh: AUTH|SSO|NET|NOTFOUND: hint")
ghq() {
  local out err rc
  err="$(mktemp "${TMPDIR:-/tmp}/gu.XXXXXX")"
  out=$(gh "$@" 2>"$err"); rc=$?
  if [ $rc -ne 0 ]; then
    local e; e=$(cat "$err")
    case "$e" in
      *x509*|*tls*|*TLS*|*"CONNECT tunnel"*|*proxy*|*"dial tcp"*|*"no such host"*)
        echo "gh: NET: GitHub unreachable from here (sandbox/proxy). Run it yourself: ! gu ${GU_CMDLINE:-...}" >&2 ;;
      *SAML*|*SSO*) echo "gh: SSO: token not authorized for this org -> /gu-auth" >&2 ;;
      *"not logged"*|*"token"*"invalid"*|*"HTTP 401"*|*"authentication"*) echo "gh: AUTH: gh login broken -> /gu-auth" >&2 ;;
      *"HTTP 404"*|*"Could not resolve"*|*"no pull requests found"*) echo "gh: NOTFOUND: ${e%%$'\n'*}" >&2 ;;
      *) echo "gh: ERROR: ${e%%$'\n'*}" >&2 ;;
    esac
    rm -f "$err"; return 3
  fi
  rm -f "$err"; printf '%s\n' "$out"
}
protected() {         # $1 slug, $2 branch -> yes|no|unknown
  local o
  if o=$(gh api "repos/$1/branches/$2" --jq '.protected' 2>/dev/null); then
    [ "$o" = true ] && echo yes || echo no
  else echo unknown; fi
}

# jq (gh --jq) helpers for statusCheckRollup arrays: ci -> pass|fail|pending|-, failing -> names
JQ_CI='def st: (.conclusion // .state // "");
def bad: st | IN("FAILURE","ERROR","CANCELLED","TIMED_OUT","ACTION_REQUIRED","STARTUP_FAILURE");
def ci: if length == 0 then "-" elif any(.[]; bad) then "fail"
  elif any(.[]; ((.status // "COMPLETED") != "COMPLETED") or (st | IN("PENDING","EXPECTED"))) then "pending" else "pass" end;
def failing: [.[] | select(bad) | (.name // .context)] | join(",");
def pending: [.[] | select(((.status // "COMPLETED") != "COMPLETED") or (st | IN("PENDING","EXPECTED"))) | (.name // .context)] | join(",");'

pr_url_parts() {      # PR url -> PR_SLUG=owner/name, PR_NUM
  PR_SLUG=$(echo "$1" | sed 's#https://github.com/##; s#/pull/.*##'); PR_NUM=${1##*/}
}
# GraphQL for a PR's review threads (vars o, r, n); callers pick fields with --jq
GQL_THREADS='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){pullRequest(number:$n){
  reviewThreads(first:100){nodes{id isResolved isOutdated path line comments(first:20){totalCount nodes{databaseId author{login} body}}}}}}}'
pr_threads() {        # $1 slug, $2 number, rest: gh flags (e.g. --jq ...)
  local slug="$1" num="$2"; shift 2
  ghq api graphql -f query="$GQL_THREADS" -f o="${slug%/*}" -f r="${slug#*/}" -F n="$num" "$@"
}

pr_repo_args() {      # pass-through "--repo X" when given; sets REPO_ARGS array and PR_ARG
  REPO_ARGS=(); PR_ARG=""
  while [ $# -gt 0 ]; do
    case "$1" in --repo|-R) REPO_ARGS=(--repo "$2"); shift ;; *) PR_ARG="$1" ;; esac; shift
  done
}

# ---------- formatting ----------
kv() { printf '%s: %s\n' "$1" "${2:--}"; }
