# shellcheck shell=bash  # sourced by bin/gu, so no shebang of its own
#: ci [pr|--run ID|--branch B] [--repo owner/name] - failing CI: first errors from Actions logs, links for other CI, flakiness on the default branch
# No argument: recent runs of the current branch.

errors() {  # stdin: log -> the first error-looking lines with a little context, capped
  grep -n -i -E -B2 -A3 'error|fail(ed|ure)?[: ]|assert|exception|panic|fatal' | head -60
}

main() {
  local run="" br="" args=() a
  while [ $# -gt 0 ]; do
    case "$1" in --run) run="$2"; shift ;; --branch) br="$2"; shift ;; *) args+=("$1") ;; esac; shift
  done
  pr_repo_args ${args[@]+"${args[@]}"}
  if [ -n "$run" ]; then
    ghq run view "$run" "${REPO_ARGS[@]}" --json name,headBranch,conclusion,url,jobs \
      --jq '"run: \(.name) on \(.headBranch) -> \(.conclusion) \(.url)", (.jobs[] | select(.conclusion=="failure") | "failed job: \(.name) (\(.databaseId))")'
    echo "--- first errors"; ghq run view "$run" "${REPO_ARGS[@]}" --log-failed | cut -c1-300 | errors
    return
  fi
  if [ -z "$PR_ARG" ]; then
    [ -n "$br" ] || br=$(git branch --show-current)
    echo "run_id|workflow|status|conclusion|event|age"
    ghq run list "${REPO_ARGS[@]}" --branch "$br" --limit 10 --json databaseId,workflowName,status,conclusion,event,createdAt \
      --jq '.[] | "\(.databaseId)|\(.workflowName)|\(.status)|\(.conclusion // "-")|\(.event)|\(.createdAt[0:16])"'
    return
  fi
  # PR: list failing checks; Actions ones get their log excerpt, others just the link
  local rows id def
  rows=$(ghq pr checks "$PR_ARG" "${REPO_ARGS[@]}" --json name,state,link,workflow --jq '.[] | select(.state=="FAILURE" or .state=="ERROR" or .state=="CANCELLED" or .state=="TIMED_OUT") | "\(.name)|\(.workflow)|\(.link)"') || exit 3
  [ -n "$rows" ] || { echo "no failing checks"; return; }
  def=$(ghq repo view "${REPO_ARGS[@]:1}" --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null)
  printf '%s\n' "$rows" | while IFS='|' read -r name wf link; do
    echo "=== FAILING: $name  $link"
    id=$(echo "$link" | sed -n 's#.*/actions/runs/\([0-9]*\).*#\1#p')
    if [ -z "$id" ]; then echo "(not GitHub Actions - gh can't read this log; open the link)"; continue; fi
    ghq run view "$id" "${REPO_ARGS[@]}" --log-failed | cut -c1-300 | errors
    [ -n "$wf" ] && [ -n "$def" ] && echo "flaky? last runs of '$wf' on $def: $(ghq run list "${REPO_ARGS[@]}" --workflow "$wf" --branch "$def" --limit 10 --json conclusion --jq '[.[].conclusion // "running"] | join(" ")')"
  done
}
