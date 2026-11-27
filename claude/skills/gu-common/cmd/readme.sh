# shellcheck shell=bash  # sourced by bin/gu, so no shebang of its own
#: readme [range] [--staged] [repo] - README/docs check for a change: MISSING (new names not documented), STALE (removed names still mentioned), BROKEN links
# range default: origin/<default>...HEAD. --staged also includes the index (for a commit about to be made).
# Mechanical part only; the skill still judges whether changed behaviour is described correctly.
main() {
  local range="" staged=0 repo="" a
  for a in "$@"; do case "$a" in --staged) staged=1 ;; *...*|*..*) range="$a" ;; *) repo="$a" ;; esac; done
  local top; top=$(resolve_repo "$repo"); cd "$top" || exit 1
  [ -f README.md ] || { echo "readme: none (skip check)"; return; }
  [ -n "$range" ] || range="origin/$(default_branch "$top")...HEAD"
  local docs="README.md"; [ -d docs ] && docs="README.md docs"
  local changes; changes=$( { git diff --name-status "$range"; [ "$staged" = 1 ] && git diff --cached --name-status; } | sort -u)
  echo "range: $range$( [ "$staged" = 1 ] && echo ' + staged')"
  echo "changed: $(printf '%s\n' "$changes" | grep -c .) files"; printf '%s\n' "$changes" | head -40 | sed 's/^/  /'

  # names a reader would look for: skill dir names, script/command basenames, docs pages
  name_of() { case "$1" in
      */skills/*/SKILL.md) echo "$1" | sed 's#.*/skills/\([^/]*\)/SKILL.md#\1#' ;;
      */skills/*) ;;                                   # skill internals aren't user-facing
      */gu-common/*) [ "${1##*/}" = gu ] && echo gu ;;
      bin/*|*/bin/*|scripts/*|*.sh|*.py|*.pl) basename "$1" | sed 's/\.[a-z]*$//' ;;
      docs/*.md) echo "$1" ;;
    esac; }
  printf '%s\n' "$changes" | while IFS="$(printf '\t')" read -r st p1 p2; do
    case "$st" in
      A*) n=$(name_of "$p1"); [ -n "$n" ] && ! grep -rqF -- "$n" $docs && echo "MISSING: '$n' (added $p1) not mentioned in $docs" ;;
      D*|R*) n=$(name_of "$p1"); [ -n "$n" ] && { [ "${st#R}" = "$st" ] || [ "$(name_of "$p2")" != "$n" ]; } \
               && grep -rnF -- "$n" $docs | head -3 | sed "s#^#STALE: '$n' ($( [ "${st#R}" = "$st" ] && echo removed || echo "renamed to $p2")) still at #" ;;
    esac
  done
  # aliases / functions added to an alias file
  git diff "$range" -- alias aliases '*.alias' 2>/dev/null | sed -n 's/^+alias \([^=]*\)=.*/\1/p' | while read -r n; do
    grep -rqF -- "$n" $docs || echo "MISSING: alias '$n' not mentioned in $docs"
  done
  # local links in README and docs that point nowhere
  grep -rnoE '\]\([^)#:]+(#[^)]*)?\)' $docs 2>/dev/null | while IFS=: read -r f l m; do
    t=$(echo "$m" | sed -E 's/^\]\(//; s/\)$//; s/#.*//'); [ -n "$t" ] || continue
    [ -e "$(dirname "$f")/$t" ] || echo "BROKEN: $f:$l -> $t"
  done
  echo "done (no MISSING/STALE/BROKEN lines = mechanically clean)"
}
