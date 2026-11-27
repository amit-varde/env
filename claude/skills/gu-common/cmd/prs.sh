# shellcheck shell=bash  # sourced by bin/gu, so no shebang of its own
#: prs [mine|review|repo] [--repo owner/name] - PR lists; repo = open PRs here with CI/review/mergeable (default: mine)
main() {
  local mode="${1:-mine}"; [ $# -gt 0 ] && shift
  pr_repo_args "$@"
  case "$mode" in
    mine|review)
      local who="--author=@me"; [ "$mode" = review ] && who="--review-requested=@me"
      echo "repo|pr|title|draft|updated"
      ghq search prs "$who" --state=open --limit 50 --json repository,number,title,isDraft,updatedAt \
        --jq '.[] | "\(.repository.nameWithOwner)|#\(.number)|\(.title[0:70])|\(if .isDraft then "draft" else "" end)|\(.updatedAt[0:10])"' ;;
    repo)
      echo "pr|title|head->base|draft|ci|failing|review|mergeable|updated|author"
      ghq pr list "${REPO_ARGS[@]}" --state open --limit 50 \
        --json number,title,author,headRefName,baseRefName,isDraft,mergeable,reviewDecision,statusCheckRollup,updatedAt \
        --jq "$JQ_CI"' .[] | "#\(.number)|\(.title[0:60])|\(.headRefName)->\(.baseRefName)|\(if .isDraft then "draft" else "" end)|\(.statusCheckRollup|ci)|\(.statusCheckRollup|failing)|\(.reviewDecision // "-")|\(.mergeable)|\(.updatedAt[0:10])|\(.author.login)"' ;;
    *) die "prs: mode must be mine, review or repo" ;;
  esac
}
