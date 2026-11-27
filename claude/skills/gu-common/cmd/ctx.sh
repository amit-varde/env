#: ctx [repo] [--no-fetch] [--no-gh] - everything a gu-* skill needs to know about one repo, in one call
# Read-only (fetch touches remote-tracking refs only). Sections: identity, branch/sync, working tree,
# unpushed commits, submodules, PR for this branch, protection, repo guides/templates/CI, commit style.

main() {
  local repo="" fetch=1 usegh=1 a top b up ba def sl fork pr
  for a in "$@"; do case "$a" in --no-fetch) fetch=0 ;; --no-gh) usegh=0 ;; -*) die "ctx: unknown option $a" ;; *) repo="$a" ;; esac; done
  top=$(resolve_repo "$repo")
  [ "$fetch" = 1 ] && { GIT_TERMINAL_PROMPT=0 G "$top" fetch --prune --quiet origin || warn "fetch failed (network/sandbox?) - remote state may be stale"; }
  b=$(branch "$top"); up=$(upstream "$top"); def=$(default_branch "$top"); sl=$(slug "$top")
  ba="-"; [ "$up" != - ] && ba=$(behind_ahead "$top" '@{u}' HEAD)
  fork=""; G "$top" remote get-url upstream >/dev/null && fork=" (fork; upstream=$(slug "$top" upstream))"

  kv repo "${top/#$HOME/~}  $sl$fork"
  local wgd wroot wn
  wgd=$(gitdir "$top")
  if [ -f "$wgd/commondir" ]; then           # a linked worktree: name it (the PR title /gu-pr-create offers)
    wroot="$(cd "$(dirname "$(commondir "$top")")" && pwd -P)/.claude/worktrees/"
    case "$(cd "$top" && pwd -P)/" in
      "$wroot"*/*) wn=$(cd "$top" && pwd -P); wn=${wn#"$wroot"}; kv worktree "$wn  (main checkout: $(dirname "$(commondir "$top")"))" ;;
      *) kv worktree "$(basename "$top")  (linked, outside <repo>/.claude/worktrees; main checkout: $(dirname "$(commondir "$top")"))" ;;
    esac
  fi
  kv branch "$b -> $up  behind/ahead=$ba  default=$def$( [ "$b" = "$def" ] && echo '  ON DEFAULT')"
  [ "$up" = - ] && case "$b" in DETACHED@*) ;; *) upstream_gone "$top" "$b" && kv upstream GONE || kv upstream "none (first push needs -u)";; esac
  [ "$def" != "?" ] && kv vs-default "$(behind_ahead "$top" "origin/$def" HEAD) (behind/ahead origin/$def)"
  kv tree "dirty=$(n_dirty "$top") untracked=$(n_untracked "$top") stash=$(n_stash "$top") op=$(op_in_progress "$top") lock=$(lock_level "$top")"
  G "$top" status --porcelain --ignore-submodules=dirty | head -30 | sed 's/^/  /'
  local base='@{u}'; [ "$up" = - ] && base="origin/$def"
  local un; un=$(G "$top" log --oneline "$base..HEAD" | head -10)
  [ -n "$un" ] && { kv unpushed "(vs $base)"; printf '%s\n' "$un" | sed 's/^/  /'; }
  if [ -f "$top/.gitmodules" ]; then
    kv submodules "$(submodules "$top" | awk -F'|' '{t++; if($1=="+")d++; if($1=="-")u++; if($1=="U")c++} END{printf "%d total, %d moved, %d uninit, %d conflict", t,d,u,c}')"
    submodules "$top" | while IFS='|' read -r st p; do
      [ "$st" = - ] && continue
      [ "$st" = + ] || [ "$(n_dirty "$p")" != 0 ] && echo "  ${p#$top/} state=$st dirty=$(n_dirty "$p")"
    done
  fi

  if [ "$usegh" = 1 ]; then
    case "$b" in DETACHED@*) ;; *)
      if pr=$(cd "$top" && ghq pr view --json number,state,isDraft,baseRefName,url \
              --jq '"#\(.number) \(.state)\(if .isDraft then " DRAFT" else "" end) base=\(.baseRefName) \(.url)"' 2>&1); then
        kv pr "$pr"
      else case "$pr" in *NOTFOUND*) kv pr none ;; *) kv pr "unknown - $pr" ;; esac; fi
      kv protected "$b=$(protected "$sl" "$b") $def=$(protected "$sl" "$def")" ;;
    esac
  fi

  local f g=""; for f in AGENTS.md CLAUDE.md CONTRIBUTING.md README.md; do [ -f "$top/$f" ] && g="$g $f"; done
  kv guides "${g# }"
  g=""; for f in .github/pull_request_template.md .github/PULL_REQUEST_TEMPLATE docs/pull_request_template.md .github/ISSUE_TEMPLATE .github/CODEOWNERS CODEOWNERS; do [ -e "$top/$f" ] && g="$g $f"; done
  kv templates "${g# }"
  g=""; [ -d "$top/.github/workflows" ] && g="actions($(ls "$top/.github/workflows" | grep -c 'ya\?ml$'))"
  ls "$top"/*Jenkinsfile >/dev/null 2>&1 && g="$g jenkins"
  kv ci "${g# }"
  kv style ""; G "$top" log --format='  %s' -8 "origin/$def" 2>/dev/null || G "$top" log --format='  %s' -8
}
