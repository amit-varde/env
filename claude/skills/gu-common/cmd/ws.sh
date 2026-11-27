# shellcheck shell=bash  # sourced by bin/gu, so no shebang of its own
#: ws [--fetch] [--all] [--plan] [repo...] - status table of every repo under $WORK + submodules; --plan adds the update bucket
# Read-only (fetch only touches remote-tracking refs). Rows: repo|branch|upstream|behind/ahead|default|
# default_behind/ahead|dirty|untracked|stash|op|last commit|notes[|bucket]. Submodule rows are indented and
# shown only when they need attention, unless --all.
# Buckets (--plan): LOCKED BLOCKED CURRENT FF DEFAULT DECIDE - see gu-update/SKILL.md.

sub_rows() {   # stdin: submodules() output; $1 all -> indented rows (flagged ones, or all)
  local all="$1" st p notes d u s o
  while IFS='|' read -r st p; do
    [ -n "$p" ] || continue
    notes=""
    case "$st" in
      -) [ "$all" = 1 ] && echo "  ${p#$GU_WORK/}|-|-|-|-|-|-|-|-|-|-|not initialized"; continue ;;
      +) notes="not-at-recorded-commit" ;;
      U) notes="MERGE_CONFLICT" ;;
    esac
    # detached at the recorded commit is normal; only look for unpushed work when moved or on a branch
    if [ "$st" = + ] || G "$p" symbolic-ref -q HEAD >/dev/null; then
      u=$(G "$p" rev-list --count HEAD --not --remotes --tags); [ "${u:-0}" -gt 0 ] && notes="$notes $u-commits-on-no-remote"
    fi
    d=$(n_dirty "$p"); s=$(n_untracked "$p"); o=$(op_in_progress "$p")
    if [ -z "$notes" ] && [ "$d" = 0 ] && [ "$s" = 0 ] && [ "$o" = - ] && [ "$all" = 0 ]; then continue; fi
    echo "  ${p#$GU_WORK/}|$(branch "$p")|$(upstream "$p")|-|-|-|$d|$s|$(n_stash "$p")|$o|$(last_commit_age "$p")|${notes# }"
  done
}

main() {
  local fetch=0 all=0 plan=0 names=() r
  while [ $# -gt 0 ]; do
    case "$1" in --fetch) fetch=1 ;; --all) all=1 ;; --plan) plan=1 ;; -*) die "ws: unknown option $1" ;; *) names+=("$1") ;; esac
    shift
  done
  repos_from_args ${names[@]+"${names[@]}"}
  local repos=(${REPOS[@]+"${REPOS[@]}"})
  [ ${#repos[@]} -gt 0 ] || die "no git repos under $GU_WORK"

  local log; log=$(mktemp -d "${TMPDIR:-/tmp}/gu-ws.XXXXXX")
  [ "$fetch" = 1 ] && fetch_all "$log" "${repos[@]}"

  printf 'repo|branch|upstream|behind/ahead|default|default_behind/ahead|dirty|untracked|stash|op|last commit|notes'
  [ "$plan" = 1 ] && printf '|bucket'; echo

  local n b up ba def dba dirty untr stash op notes lk fe beh ahd dbeh dahd subs subsum bucket
  for r in "${repos[@]}"; do
    n=$(basename "$r"); b=$(branch "$r"); up=$(upstream "$r")
    ba="-"; [ "$up" != - ] && ba=$(behind_ahead "$r" '@{u}' HEAD)
    def=$(default_branch "$r"); dba="-"
    if [ "$def" != "?" ] && G "$r" show-ref -q --verify "refs/heads/$def"; then dba=$(behind_ahead "$r" "origin/$def" "$def"); fi
    dirty=$(n_dirty "$r"); untr=$(n_untracked "$r"); stash=$(n_stash "$r"); op=$(op_in_progress "$r")
    notes=""; lk=$(lock_level "$r"); [ -n "$lk" ] && notes="$notes LOCKED($lk)"
    fe=$(fetch_error "$log" "$n"); [ -n "$fe" ] && notes="$notes FETCH_FAILED($fe)"
    case "$b" in DETACHED@*) ;; *)
      if [ "$up" = - ]; then
        if upstream_gone "$r" "$b"; then notes="$notes UPSTREAM_GONE"; else notes="$notes no-upstream"; fi
      fi ;;
    esac
    [ "$up" != - ] && [ -n "$(G "$r" diff --name-only HEAD '@{u}' -- .claude | head -1)" ] && notes="$notes incoming-.claude"
    [ -f "$r/.gitattributes" ] && grep -q 'filter=lfs' "$r/.gitattributes" && notes="$notes LFS"
    subs=""; subsum=""
    if [ -f "$r/.gitmodules" ]; then
      subs=$(submodules "$r" | sub_rows "$all")
      subsum=$(submodules "$r" | awk -F'|' '{t++; if($1=="+")d++; if($1=="-")u++} END{printf "subs:%d(drift %d,uninit %d", t, d, u}')
      [ -n "$subs" ] && [ "$all" = 0 ] && subsum="$subsum,attention $(printf '%s\n' "$subs" | grep -c .)"
      notes="$notes $subsum)"
    fi

    printf '%s' "$n|$b|$up|$ba|$def|$dba|$dirty|$untr|$stash|$op|$(last_commit_age "$r")|${notes# }"
    if [ "$plan" = 1 ]; then
      beh=${ba%/*}; ahd=${ba#*/}; [ "$ba" = - ] && { beh=0; ahd=0; }
      dbeh=${dba%/*}; dahd=${dba#*/}; [ "$dba" = - ] && { dbeh=0; dahd=0; }
      if [ -n "$lk" ]; then bucket=LOCKED
      elif [ -n "$fe" ] || [ "$op" != - ]; then bucket=BLOCKED
      else case "$b|$notes" in
        DETACHED@*|*UPSTREAM_GONE*|*MERGE_CONFLICT*) bucket=DECIDE ;;
        *) if [ "$dahd" -gt 0 ] || printf '%s' "$subs" | grep -q 'commits-on-no-remote\|MERGE_CONFLICT'; then bucket=DECIDE
           elif [ "$beh" -eq 0 ] && [ "$dbeh" -eq 0 ]; then bucket=CURRENT
           elif [ "$beh" -gt 0 ]; then
             if [ "$ahd" -eq 0 ] && ff_worktree_is_upstream "$r"; then bucket=FF; else bucket=DECIDE; fi
           elif [ "$b" != "$def" ]; then bucket=DEFAULT
           else bucket=DECIDE; fi ;;
      esac; fi
      printf '|%s' "$bucket"
    fi
    echo
    [ -n "$subs" ] && printf '%s\n' "$subs"
  done
  rm -rf "$log"
}
