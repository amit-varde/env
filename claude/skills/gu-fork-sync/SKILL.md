---
name: gu-fork-sync
description: Keep a GitHub fork and the repo it was forked from in step, always through pull requests - pull the original's new commits into your fork (merge or rebase, conflicts walked one file at a time), send chosen fork commits back to the original as a PR, and, for the original's owner, pick commits out of forks into a PR. For the env repo it also runs the tests, setup-env.sh and env-doctor after a sync. Use for "/gu-fork-sync", "sync my fork", "pull from upstream", "update my fork from the original", "send this change upstream", "contribute back to the original", "what's new in the original", "take changes from a fork", "what have forks changed".
argument-hint: "[status|pull|send|take] [repo]"
---

# Fork sync

Follow `~/.claude/skills/gu-common/CONVENTIONS.md`. `gu` = `bash ~/.claude/skills/gu-common/bin/gu`.
The repo is the argument, else the current repo, else `$BU` (the env repo). Every change, in either
direction, goes through a PR. Never push to the original's branches; the fork's default branch only
moves by a fast-forward of a reviewed PR branch (`gu fork land`).

## Start

Run `gu fork status <repo>`. Summarize in a few lines: role, behind/ahead, incoming and outgoing counts,
overlapping files, open sync/send PRs.
- `upstream: MISSING remote` -> say so and run `gu fork wire <repo>` (adds `upstream`, disables pushing to it).
  A `NEEDS_USER:` line means the sandbox blocked `.git/config`: give the user that command with `!`.
- `push=ENABLED` -> recommend `gu fork wire <repo>` so nobody pushes to the original by accident.
- `role: original` -> go to **Take from a fork**.
- A `LOCKED` repo is off limits: point at `/gu-unlock`.

With a bare `/gu-fork-sync` on a fork, ask: `Pull from the original` (recommended when incoming > 0) ·
`Send changes to the original` (recommended when incoming is 0 and outgoing > 0) · `Status only`.
An open `sync/*` or `send/*` PR from an earlier run: offer to continue it instead of starting another.

## Pull from the original

1. **Method.** Ask every time, even when one is obviously right:
   - `Merge` (recommended): keeps the original's commits with their SHAs and the fork's history as is; lands as a fast-forward.
   - `Rebase`: replays the fork's commits on top of the original. The fork's default branch is published, so
     landing needs `git push --force-with-lease` to it: only with the user's explicit yes, naming that command.
   When the fork has no commits of its own (ahead 0), say both give the same fast-forward and recommend `Merge`.
2. Run `gu fork pull <repo> --merge|--rebase`. It makes `sync/upstream-<date>` in `<repo>/.claude/worktrees/` from
   `origin/<default>`. Nothing is pushed yet.
3. **Conflicts** (`result: CONFLICT`). One file at a time: show what each side changed (`git -C <wt> diff`,
   `git log --oneline -3 -- <file>` on both sides) and ask `Keep both (merged by hand)` · `Take the original's` ·
   `Keep the fork's` · `Stop and abort`, recommending from what the changes do (a fork's local hosts or
   settings usually win, the original's fixes and refactors usually win). Then `git add`, and
   `git commit --no-edit` (merge) or `git rebase --continue`. `Stop` runs `merge --abort` / `rebase --abort` and
   offers to remove the worktree.
4. **Check.** Show `git -C <wt> log --oneline origin/<default>..HEAD | head` and the diff stat. Run the repo's
   own tests on the worktree when they are quick (for env: `tests/check-helper-drift.sh`, `tests/test-gu-fork.sh`,
   `tests/test-gu-worktree.sh`, and `shellcheck` as CI runs it, when installed).
5. **PR (always, even for a fast-forward).** Ask, then `git -C <wt> push -u origin <branch>` and
   `gh pr create --repo <fork> --base <default> --head <branch>`, titled `Sync with <upstream>`; the body lists the
   incoming commits and any conflicts and how they were resolved. Run `gu readme` on it (README rule).
6. **Land** once CI passes (`gu pr <n>`) and the user says so: `gu fork land <wt> <branch>`. It fast-forwards the
   fork's default branch to the PR branch, so the original's commits keep their SHAs and GitHub marks the PR merged.
   - `REFUSED: ... protected` -> `gh pr merge <n> --merge`. Never `--squash` or `--rebase`: they rewrite the
     original's commits, and every later sync then conflicts with them.
   - `REFUSED: not a fast-forward` -> the default branch moved: pull again (step 2) on a fresh branch.
7. **After.** Fast-forward the main checkout (`/gu-update <repo>`), then remove the worktree and branch with
   `gu worktree remove <wt> --delete-branch`.

## Send changes to the original

1. List the `outgoing` commits from the status. Ask which to send: AskUserQuestion with multiSelect for up to four,
   else a numbered list the user answers in text. Flag commits that look personal and should stay in the fork:
   `ssh/config.d/<host>.conf` for hosts only this user has, `.env.host`-style paths, names, emails, tokens.
   A commit mixing shared and personal changes: suggest splitting it first (a new commit on the fork) and stop.
2. Ask for the branch name (`send/<kebab-slug>` recommended). Run `gu fork send <repo> --name <branch> <sha>...`
   (oldest first). It branches from `upstream/<default>` and cherry-picks with `-x`. Conflicts: as in Pull,
   ending with `git cherry-pick --continue`.
3. Read the original's guides (`gu ctx <wt> --no-gh` lists them) and run its README check:
   `gu readme upstream/<default>...HEAD <wt>`. Fix MISSING/STALE/BROKEN lines in the same branch.
4. Ask, then push the branch to the fork and open the PR on the original:
   `gh pr create --repo <upstream> --base <default> --head <fork-owner>:<branch>`, using the original's PR template.
   Report the URL. Review follow-ups go to `/gu-pr-feedback`.
5. Once the PR is merged there, the next **Pull** brings it back; the original commit drops out of `outgoing`.

## Take from a fork (the original's owner)

1. `gu fork forks <repo> --fetch`: every fork, behind/ahead, and the commits the original does not have.
   A fork that cannot be fetched is private to someone else: say so and skip it.
2. Ask which fork, then which commits (as in Send). Ask for the branch name (`take/<owner>-<slug>`).
3. `gu fork take <repo> --name <branch> <sha>...`: a branch from `origin/<default>`, cherry-picked with `-x`.
   Authors are kept, so the fork owner is credited; name them in the PR body (no `@mention` unless asked).
4. README check (`gu readme`), then ask, push and `gh pr create --base <default> --head <branch>` on the original.
   Merging goes through `/gu-merge`.

## The env repo

When `gu fork status` prints `env: yes` (the repo is `$BU`), after **Land** and the checkout update:
- `wiring:` files changed -> offer `./setup-env.sh --only <steps>` in `$BU`, picking steps from the paths:
  `claude/` -> claude, `ssh/` -> ssh, `cursor/` -> cursor, `dotfiles/` -> dotfiles, `tools/` -> tools,
  `env.sh`/`lib/`/`setup-env.sh` -> shell. It asks before each change and backs up what it replaces.
- Then run `env-doctor -q` and report any `warn`/`FAIL` line with its fix.
- Remind the user to open a new terminal (or `source $BU/env.sh`) if `env.sh`, `lib/` or `alias` changed.
Personal settings belong in the git-ignored files (`.env.host`, `ssh/config.d/local.conf`); edits to shared files
are what conflict on the next pull.
