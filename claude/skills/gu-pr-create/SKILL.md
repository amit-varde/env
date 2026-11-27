---
name: gu-pr-create
description: Turn local changes into a GitHub pull request - branch, stage, commit, push and open a (draft) PR with a title and body following the repo's template. Use for "open a PR", "create a pull request", "push this up for review", "make a draft PR", "commit and PR this".
argument-hint: "[base-branch]"
---

# Create a PR

Follow `~/.claude/skills/gu-common/CONVENTIONS.md`. `gu` = `bash ~/.claude/skills/gu-common/bin/gu`.

1. **Facts:** `gu ctx`. If `pr:` already shows an open PR, this is an update: push to it (/gu-push or /gu-pr-feedback).
   A submodule change is its own PR in the submodule's repo, followed by a bump PR in the parent.
2. **Commit** as /gu-push steps 2-4 do (branch off the default if needed, stage explicit paths, scan for secrets, commit).
3. **Decisions:**

| When | Options (recommended first) |
|---|---|
| `ON DEFAULT` | `Create <type>/<topic>` (suggest a name) · `Different name` · `Cancel` |
| ctx shows `worktree: <name>` (any linked worktree) | Title: `<name>` (exactly the worktree name, so the PR, branch and folder match) · `<drafted title>` · `Edit` |
| Base unclear (stacked or release work) | `<default>` · `<parent branch>` · `<release branch>` |
| Ready to publish | `Push and open a draft PR` · `Push and open ready for review` · `Commit only` |
| `templates:` has CODEOWNERS, or the user named people | `No reviewers yet` (drafts) · `Request CODEOWNERS` · `Name reviewers` |

4. **Body:** fill the repo template (`templates:` in ctx) without dropping its required checklists.
   Otherwise use `## Summary` (what and why) and `## Testing` (what ran, and plainly what didn't).
   Write `Closes #N` only when the PR really resolves it. Show the title and body as part of the publish question.
5. **Publish:**
   ```bash
   git push -u origin HEAD
   gh pr create --draft --base <base> --title "<title>" --body-file - <<'EOF'
   ...
   EOF
   ```
   Add `--reviewer`, `--label` or `--assignee` only if chosen. For a fork, use
   `--repo upstream/repo --head <you>:<branch>`. For stacked work, set `--base` to the parent branch.
6. **Report** the PR URL, then `gu pr` once for the initial CI state; CI follow-up goes to /gu-pr-status.
