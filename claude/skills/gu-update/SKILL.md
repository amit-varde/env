---
name: gu-update
description: Safely update git repos under ~/work - the current repo, named repos, or all of them (--all, or /gu-update-all) - fetches, fast-forwards repos that are behind and not ahead (including a worktree whose local files already match the incoming commit) in one confirmed batch, then walks through real local edits, diverged, detached, gone-upstream or conflicting repos one at a time. Never forces, resets, discards real local edits, or pushes. Use for "/gu-update", "update this repo", "pull rock", "update all my repos", "pull everything", "sync all repos".
argument-hint: "[repo ...] | --all | --dry-run"
---

# Update repos

Follow `~/.claude/skills/gu-common/CONVENTIONS.md`. `gu` = `bash ~/.claude/skills/gu-common/bin/gu`.
This skill pulls and never pushes. Don't run builds or `setup.sh`.

**Which repos:** the ones named; with `--all` (or when invoked as /gu-update-all) every repo under
`$WORK` (pass no repo to `gu ws`); with neither, the repo containing the working directory
(`git rev-parse --show-toplevel`). If there is none, ask: `All repos` · `Pick repos`.
The same logic without the walk-through is the `gu-update` command (`gu-update-all` = `gu-update --all`).

## 1. Plan (read-only)
`gu ws --fetch --plan [repo...] | column -t -s'|'` (allowed_domains: github.com). The last column is the bucket:

| Bucket | Meaning | Action |
|---|---|---|
| CURRENT | nothing incoming | none (mention dirty files and `no-upstream` branches) |
| FF | behind, not ahead; clean, or every local change already matches the incoming commit | `gu update ff <repo>` |
| DEFAULT | feature branch is current, local default is behind | `gu update default <repo>` |
| DECIDE | local edits that are not already the incoming commit, diverged, detached, `UPSTREAM_GONE`, default ahead, submodule work | step 3 |
| BLOCKED | `FETCH_FAILED`, or an operation in progress | step 3 |
| LOCKED | locked by /gu-lock | skip; mention /gu-unlock |

Show the buckets in a few lines. Ask once: `Run the FF and DEFAULT updates now` ·
`Let me pick` (multiSelect) · `Dry run - stop` (always stop here for `--dry-run`).

## 2. Batch
Run `gu update ...` per repo and read its result line:
- `updated:` done (plus any `submodules updated:` line).
- `REFUSED:` the repo moves to DECIDE.
- `NEEDS_USER:` the sandbox can't write some incoming files (often `.claude/`). Nothing
  was changed; give the user the printed `!` command.
- `CONFLICT:` go to step 4.
- `SUBMODULE_NEEDS_DECISION:` ask: `Leave it` · `Stash in the submodule, then update` · `Show the difference`.

## 3. Per-repo decisions (one repo at a time; state the facts in each question)
- **Dirty and behind:** check overlap with `comm -12 <(git -C R diff --name-only | sort) <(git -C R diff --name-only HEAD @{u} | sort)`.
  No overlap: `Stash, pull, restore` (`gu update stash-pull R`) · `Commit first (/gu-push)` · `Skip`.
  Overlap: recommend `Skip`.
- **Diverged:** show `git log --oneline @{u}..HEAD` and `HEAD..@{u}`. Options: `Rebase` (`gu update stash-pull R --rebase`,
  or `git -C R pull --rebase` if clean) · `Merge` (`git -C R pull --no-rebase`) · `Skip`. Print `git rev-parse HEAD` first as the undo point.
- **Ahead only:** `Leave it` · `Push with /gu-push`.
- **Default ahead of origin:** show the commits. `Leave it` · `Move them to a new branch` · `/gu-push`.
- **Detached:** `Leave it` · `Switch to <default> and fast-forward` (only if clean and contained in a branch) · `Create a branch here`.
- **Upstream gone:** if `gh pr list --head <b> --state merged` shows it was merged: `Switch to <default> and update; keep the branch` · `Leave it` · `/gu-repo cleanup`.
- **Blocked:** `FETCH_FAILED` -> `Skip` · `Fix (/gu-auth), then retry`. Operation in progress -> `Skip, I'll finish it` · `Help me finish` · `Abort it`.

## 4. Conflicts
Show `git -C R status --short` and the hunks. Propose a resolution per file (for generated files,
regenerate them instead of merging by hand). Options: `Apply proposed` · `Keep mine` · `Take theirs` · `Abort`
(`git rebase --abort` / `merge --abort`). Then `git add`, and `--continue` or commit. Drop a
`gu-update` stash only after the user confirms the result. Never leave a repo mid-rebase without saying so.

## 5. Report
Re-run `gu ws --plan`. Show a before/after table, then any stashes left, skipped repos and why, unpushed commits (/gu-push),
and the undo SHAs for rebased or merged repos.
