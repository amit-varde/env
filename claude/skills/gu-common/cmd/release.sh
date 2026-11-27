# shellcheck shell=bash  # sourced by bin/gu, so no shebang of its own
#: release [repo] [--target BRANCH] - last tag, what merged since, grouped notes draft and the suggested next version
main() {
  local repo="" target="" a
  while [ $# -gt 0 ]; do case "$1" in --target) target="$2"; shift ;; *) repo="$1" ;; esac; shift; done
  local top; top=$(resolve_repo "$repo"); cd "$top" || exit 1
  [ -n "$target" ] || target=$(default_branch "$top")
  G "$top" fetch --quiet --tags origin 2>/dev/null
  local last; last=$(git describe --tags --abbrev=0 "origin/$target" 2>/dev/null)
  kv target "origin/$target @ $(git rev-parse --short "origin/$target")"
  kv last-tag "${last:-none}$( [ -n "$last" ] && echo " ($(git log -1 --format=%cs "$last"))")"
  kv recent-tags "$(git tag --sort=-creatordate | head -5 | tr '\n' ' ')"
  local range="origin/$target"; [ -n "$last" ] && range="$last..origin/$target"
  local subjects; subjects=$(git log --format='%s' --no-merges "$range")
  kv commits-since "$(printf '%s\n' "$subjects" | grep -c .)"
  [ -n "$subjects" ] || { echo "nothing to release"; return; }

  local since=""; [ -n "$last" ] && since="merged:>=$(git log -1 --format=%cs "$last")"
  local prs; prs=$(ghq pr list --state merged --base "$target" --limit 200 ${since:+--search "$since"} \
      --json number,title,labels --jq '.[] | "\(.number)|\(.title)|\([.labels[].name]|join(","))"' 2>/dev/null)
  [ -n "$prs" ] || prs=$(printf '%s\n' "$subjects" | sed 's/^/-|/; s/$/|/')   # no gh: fall back to commit subjects
  local bump=patch
  printf '%s\n' "$prs" | grep -qiE '\|[a-z]+(\([^)]*\))?!:|BREAKING|\|.*breaking' && bump=major
  [ "$bump" = patch ] && printf '%s\n' "$prs" | grep -qiE '^[^|]*\|(feat|add|new)|\|.*(feature|enhancement)' && bump=minor
  local v="${last#v}" M m p
  M=$(echo "$v" | cut -d. -f1); m=$(echo "$v" | cut -d. -f2); p=$(echo "$v" | cut -d. -f3 | sed 's/[^0-9].*//')
  [ -z "$last" ] && { M=0; m=0; p=0; bump=minor; }     # first release -> v0.1.0
  case "$M$m$p" in *[!0-9]*|"") kv suggested "($bump) - last tag isn't SemVer; ask" ;;
    *) case "$bump" in major) M=$((M+1)); m=0; p=0 ;; minor) m=$((m+1)); p=0 ;; *) p=$((p+1)) ;; esac
       kv suggested "v$M.$m.$p ($bump)" ;;
  esac
  echo "--- notes draft"
  printf '%s\n' "$prs" | awk -F'|' '
    { t=$2; n=($1=="-")?"":" (#"$1")"; s=tolower($2); lb=tolower($3)
      if (lb ~ /breaking/ || s ~ /^[a-z]+(\([^)]*\))?!:|breaking/) b=b"- "t n"\n";
      else if (lb ~ /feature|enhancement/ || s ~ /^(feat|add|new|introduce)/) f=f"- "t n"\n";
      else if (lb ~ /bug/ || s ~ /^(fix|revert)/) x=x"- "t n"\n"; else o=o"- "t n"\n" }
    END { if(b)printf "## Breaking\n%s",b; if(f)printf "## Features\n%s",f; if(x)printf "## Fixes\n%s",x; if(o)printf "## Other\n%s",o }'
}
