---
name: gu-issues
description: Work with GitHub issues - search and list, read with comments, file a well-formed bug or feature using the repo's templates, comment, label, assign, link to PRs, close or reopen, triage a batch. Use for "file an issue", "open a bug for", "issues assigned to me", "find the issue about", "comment on issue 42", "close this issue", "triage issues".
argument-hint: "[issue-number | keywords]"
---

# GitHub issues

Follow `~/.claude/skills/gu-common/CONVENTIONS.md`. `gu` = `bash ~/.claude/skills/gu-common/bin/gu`.
Reads: run them yourself. Creating, commenting, labeling, assigning, closing: show the exact text first, then act on the user's OK.

## Find and read
For a vague request, ask: `Assigned to me` (`gh search issues --assignee=@me --state=open`) · `Keywords`
(`gh issue list --search "<kw>" --state all`) · `Recent in this repo` (`gh issue list --limit 20`) · `Across the org` (`--owner <org>`).
Read one with `gh issue view <n> --comments`. Add `--repo o/r` outside the repo.

## Create
1. Duplicates: `gh issue list --search "<kw>" --state all`. If one fits: `Comment on #N instead` · `New issue anyway` · `Cancel`.
2. Template: `gu ctx` lists `.github/ISSUE_TEMPLATE`. Offer the best match first, or `Blank`. Keep its headings and required fields.
3. Draft it. A bug needs a summary, repro steps, expected vs actual, version, trimmed logs and what's been ruled out.
   A feature needs the problem, a proposal, alternatives and acceptance criteria. Redact secrets, internal hosts and customer data.
4. Ask `Create as drafted` · `Edit` · `Cancel`; then labels (multiSelect of real ones from `gh label list`) and
   `Assign to me` · `Leave unassigned`.
   ```bash
   gh issue create --title "<t>" --label bug --body-file - <<'EOF'
   ...
   EOF
   ```

## Update
`gh issue comment <n> --body-file f` · `gh issue edit <n> --add-label x --add-assignee @me` · close:
`Completed` (`gh issue close <n> --reason completed --comment "Fixed by #123"`) · `Not planned` · `Duplicate of #N` ·
`gh issue reopen <n>` · `gh issue develop <n> --checkout` (a linked branch). `Closes #n` in a PR body closes the issue on merge.

## Triage a batch
`gh issue list --json number,title,labels,createdAt,comments --limit 50`. Group by theme and propose labels, owners and
closures as a table. Per issue: `Apply proposed` · `Close` · `Skip`. Apply the approved ones in one pass.
