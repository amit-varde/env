#: pr [number|branch|url] [--repo owner/name] - one PR: state, CI (failing/pending names), review, mergeability, behind, threads, merge options
main() {
  pr_repo_args "$@"
  local j
  j=$(ghq pr view $PR_ARG "${REPO_ARGS[@]}" --json number,title,state,isDraft,author,baseRefName,headRefName,isCrossRepository,mergeable,mergeStateStatus,reviewDecision,reviewRequests,statusCheckRollup,commits,changedFiles,additions,deletions,url \
      --jq "$JQ_CI"' "pr: #\(.number) \(.state)\(if .isDraft then " DRAFT" else "" end) \(.url)
title: \(.title)
author: \(.author.login)\(if .isCrossRepository then "  (FORK - cannot push to or delete its branch)" else "" end)
branch: \(.headRefName) -> \(.baseRefName)
size: \(.commits|length) commits, \(.changedFiles) files, +\(.additions)/-\(.deletions)
ci: \(.statusCheckRollup|ci)  failing=[\(.statusCheckRollup|failing)]  pending=[\(.statusCheckRollup|pending)]
review: \(.reviewDecision // "none required")  requested=[\([.reviewRequests[]? | .login // .name] | join(","))]
mergeable: \(.mergeable)  state=\(.mergeStateStatus)  (BEHIND=needs update, DIRTY=conflicts, BLOCKED=rules/reviews)"') || exit 3
  printf '%s\n' "$j"
  local base head
  base=$(printf '%s\n' "$j" | sed -n 's/^branch: .* -> //p'); head=$(printf '%s\n' "$j" | sed -n 's/^branch: \(.*\) -> .*/\1/p')
  if git rev-parse -q --verify "origin/$head" >/dev/null 2>&1; then
    kv behind/ahead "$(behind_ahead . "origin/$base" "origin/$head") vs origin/$base"
  fi
  pr_url_parts "$(printf '%s\n' "$j" | sed -n '1s/.* //p')"
  kv threads "$(pr_threads "$PR_SLUG" "$PR_NUM" --jq '[.data.repository.pullRequest.reviewThreads.nodes[]|select(.isResolved|not)]|length') unresolved"
  kv merge-options "$(ghq repo view "$PR_SLUG" --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed,deleteBranchOnMerge,autoMergeAllowed \
      --jq '[(if .squashMergeAllowed then "squash" else empty end),(if .mergeCommitAllowed then "merge" else empty end),(if .rebaseMergeAllowed then "rebase" else empty end)]|join(",") + "  auto-delete=\(.deleteBranchOnMerge) auto-merge=\(.autoMergeAllowed)"')"
}
