# shellcheck shell=bash  # sourced by bin/gu, so no shebang of its own
#: threads [number] [--repo owner/name] [--all] - unresolved review threads: thread_id|comment_id|path:line|author|text
main() {
  local all=0 a args=()
  for a in "$@"; do [ "$a" = --all ] && all=1 || args+=("$a"); done
  pr_repo_args ${args[@]+"${args[@]}"}
  local url
  url=$(ghq pr view $PR_ARG "${REPO_ARGS[@]}" --json url --jq .url) || exit 3
  pr_url_parts "$url"
  echo "thread_id|comment_id|path:line|author|text (first comment; +N replies)"
  pr_threads "$PR_SLUG" "$PR_NUM" \
    --jq ".data.repository.pullRequest.reviewThreads.nodes[] | select($all == 1 or (.isResolved|not)) |
      \"\(.id)|\(.comments.nodes[0].databaseId)|\(.path):\(.line // \"outdated\")|\(.comments.nodes[0].author.login)|\(.comments.nodes[0].body | gsub(\"\\\\s+\"; \" \") | .[0:200])\(if .comments.totalCount > 1 then \" (+\(.comments.totalCount-1) replies)\" else \"\" end)\""
  echo "# reply:   gh api repos/$PR_SLUG/pulls/$PR_NUM/comments/<comment_id>/replies -f body='...'"
  echo "# resolve: gh api graphql -f query='mutation(\$id:ID!){resolveReviewThread(input:{threadId:\$id}){thread{isResolved}}}' -f id=<thread_id>"
}
