#: branches [repo] [--base B] [--no-gh] - branch inventory: kind|branch|ahead/behind|last commit|author|pr
# Kinds: REMOTE_UNMERGED (on origin, ahead of base), LOCAL_MERGED (safe to delete with -d), LOCAL_GONE
# (upstream deleted), LOCAL_UNPUSHED (commits on no remote), LOCAL_SQUASHED (merged PR, not an ancestor).
main() {
  local repo="" base="" usegh=1
  while [ $# -gt 0 ]; do case "$1" in --base) base="$2"; shift ;; --no-gh) usegh=0 ;; *) repo="$1" ;; esac; shift; done
  local top; top=$(resolve_repo "$repo"); [ -n "$base" ] || base=$(default_branch "$top")
  local prs=""
  [ "$usegh" = 1 ] && prs=$(cd "$top" && ghq pr list --state all --limit 200 --json headRefName,number,state --jq '.[] | "\(.headRefName) #\(.number) \(.state)"' 2>/dev/null)
  prof() { printf '%s\n' "$prs" | awk -v b="$1" '$1==b {print $2" "$3; exit}'; }
  echo "kind|branch|ahead/behind|last commit|author|pr"
  G "$top" for-each-ref --sort=-committerdate refs/remotes/origin --format='%(refname:lstrip=3)|%(committerdate:relative)|%(authorname)' |
  while IFS='|' read -r b when who; do
    case "$b" in HEAD|"$base") continue ;; esac
    local ab; ab=$(behind_ahead "$top" "origin/$base" "origin/$b"); [ "${ab#*/}" = 0 ] && continue
    echo "REMOTE_UNMERGED|$b|${ab#*/}/${ab%/*}|$when|$who|$(prof "$b")"
  done
  G "$top" for-each-ref refs/heads --format='%(refname:short)|%(upstream:short)|%(upstream:track)|%(committerdate:relative)|%(authorname)' |
  while IFS='|' read -r b up track when who; do
    [ "$b" = "$base" ] && continue
    local k="" p; p=$(prof "$b")
    if G "$top" merge-base --is-ancestor "$b" "origin/$base"; then k=LOCAL_MERGED
    elif [ "$track" = "[gone]" ]; then k=LOCAL_GONE
    elif case "$p" in *MERGED*) true ;; *) false ;; esac; then k=LOCAL_SQUASHED
    elif [ "$(G "$top" rev-list --count "$b" --not --remotes)" != 0 ]; then k=LOCAL_UNPUSHED
    fi
    [ -n "$k" ] && echo "$k|$b|$(behind_ahead "$top" "origin/$base" "$b" | awk -F/ '{print $2"/"$1}')|$when|$who|$p"
  done
}
