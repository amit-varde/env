---
name: gu-merge
description: Interactively merge a pull request (or a branch without one) into main - lists open PRs and unmerged branches, checks draft, CI, reviews, conflicts and behind-ness, always checks the README, surfaces every decision with a recommendation, then merges and cleans up branches. Use for "/gu-merge", "merge my PR", "land PR 12", "which PRs can I merge", "squash and merge".
argument-hint: "[pr-number | branch]"
---

# Merge a PR

Follow `~/.claude/skills/gu-common/CONVENTIONS.md`. `gu` = `bash ~/.claude/skills/gu-common/bin/gu`.
Merging is outward-facing: always get an explicit yes on the final summary.

## 1. Inventory (skip if an argument names the PR)
Run `gu prs repo` and `gu branches --base <default>`. Show open PRs (CI pass/fail/pending with the failing names,
review, mergeable) and REMOTE_UNMERGED branches with no PR. If nothing is ready, say so and stop.
Ask which one: up to 3 PRs ranked ready-first, plus `A branch without a PR`.
- **A branch without a PR:** run `gu readme origin/<base>...origin/<branch>`, then ask
  `Open a PR first` (/gu-pr-create) · `Merge locally and push` (only if `gu ctx` shows the base isn't protected).

## 2. Check
`gu pr <n>`, then `gu readme origin/<base>...origin/<head>`. Before asking anything, list **every** open decision
for this PR with your recommendation, then ask them (batches of 4, dependent ones after):

| Applies when | Options (recommended first) |
|---|---|
| Base isn't the default | `Keep <base>` · `Retarget` (`gh pr edit <n> --base <default>`) |
| DRAFT | `Mark ready` (`gh pr ready <n>`) · `Stop` |
| CI fail | `Stop and diagnose` (`gu ci <n>`) · `Re-run the failed jobs` · `Merge anyway` (say what it bypasses) |
| CI pending | `Auto-merge when green` (if auto-merge is allowed) · `Wait` (`gh pr checks <n> --watch`) · `Merge now` |
| Review missing or changes requested | `Stop` · `Request review` · `Merge anyway` (only if the rules allow) |
| DIRTY (conflicts) | `Update from base locally and resolve` · `Rebase` (own branch, needs force-with-lease) · `Stop` |
| BEHIND | `Update with a merge` (`gh pr update-branch <n>`) · `Rebase update` (`--rebase`) · `Merge as is` (if not required) |
| readme shows MISSING, STALE or BROKEN, or behavior changed | `Update README/docs in this PR` (checkout, edit, push, re-check) · `Merge without` · `Stop`; for a FORK, `Ask the author` |
| Always | Method from `merge-options`: squash for one change or messy commits, merge to keep meaningful commits, rebase for clean linear history |
| Squash or merge | `Use the PR title and body` (show `<title> (#n)`) · `Edit` |
| Own branch, auto-delete=false | `Delete the branch after merging` · `Keep it` |

Never offer `--admin` unless the user asks by name; then confirm it naming the rule it bypasses. After each preparatory
action, re-run `gu pr <n>` and re-ask if anything changed.

## 3. Merge
Show the summary (`#n title head->base | method | CI | review | README | branch`) and ask `Merge now` · `Cancel`. Then:
`gh pr merge <n> --squash|--merge|--rebase [--subject ..] [--body ..] [--delete-branch] [--auto]`. If it's refused, show the reason
and go back to that one decision.

## 4. Clean up
**Worktree.** Run `gu worktree list <repo> --fetch --gh`. If a worktree has the merged head branch, ask
`Remove the worktree and its branch` (`gu worktree remove <path> --delete-branch`) · `Keep it`. If this session
runs inside that worktree, don't remove it: say to run `/gu-worktree` → `Clean up` from another folder. A `kept:` line
means the branch has work the PR did not; relay it.

**Main checkout.** `git switch <base> && git pull --ff-only` if the merged branch was checked out there. Run `gu branches` and offer to delete
the other LOCAL_MERGED branches (`git branch -d`). Report the merge commit, the URL and deleted branches, and name the next ready PR.
