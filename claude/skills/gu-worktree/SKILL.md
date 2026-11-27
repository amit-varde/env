---
name: gu-worktree
description: Add, list, rename, remove, and clean up git worktrees in <repo>/.claude/worktrees (where Claude Code keeps its own), so the main checkout stays untouched; shows each worktree's PR and status (active, merged, dirty, behind, local-only), finds worktrees whose PR was merged (squash merges too) and removes them with their branch, and gathers stray worktrees into place. Use for "/gu-worktree", "add a worktree", "new worktree", "list worktrees", "rename a worktree", "remove a worktree", "clean up merged worktrees", "prune worktrees", "move my worktrees", or "check out in a worktree".
argument-hint: "[add|list|rename|cleanup] [repo] [branch|pr]"
---

# Worktrees

Follow `~/.claude/skills/gu-common/CONVENTIONS.md`. `gu` = `bash ~/.claude/skills/gu-common/bin/gu`.
A worktree lives where Claude Code puts its own: `<repo>/.claude/worktrees/<name>`, kept out of `git status` by a
`.claude/worktrees/` line in `.git/info/exclude` (`gu worktree add` writes it when missing). `<name>` defaults
to the branch (`pr-<n>` for a pull request). Claude desktop sessions create worktrees in the same folder, with
branches named `claude/<name>`. With a bare `/gu-worktree`, ask first: `Add` · `List` · `Rename` · `Clean up`.
The flow end to end (create, work, PR, merge, clean up) is `docs/worktree-flow.md` in the env repo.

## Add

Resolve the repo (argument, or the current repo). `gu ctx <repo>` for the branch, the lock, and `.gitmodules`.

**Locked.** Creating a branch updates a local ref, which `/gu-lock` refuses. If the repo is `LOCKED` and this add
would create a branch, say so and point at `/gu-unlock`. A detached worktree (`--detach`) is still allowed for
reading: `gu` skips the hooks for that one `git worktree add`, and the lock then refuses commits and checkouts
inside the new worktree. A repo locked before linked-worktree support keeps its old hook copy until the next
`gu lock`: when `<gitdir>/gu-lock/hooks/reference-transaction` does not mention `commondir`, say that the lock
does not cover linked worktrees yet and suggest `/gu-unlock` then `/gu-lock`. `gu worktree add` warns about this too.

**Name.** Ask before creating anything. This question is the exception to "Don't add Other": four choices,
recommended first, last is `Write in`. Each description is the full path (`<repo>/.claude/worktrees/<name>`).
Skip it when the user already gave the name, and say in one line which name you are using. `Write in` asks
for the text next. Refuse an empty name, an absolute path, a trailing slash, or a `.` or `..` component.
Slashes are allowed. If that directory already exists, say so and ask again.

Build three distinct names whose directories are free. Drop a duplicate or a name that already exists, and
take the next candidate so there are always three:

- New branch (no name yet). The choice is both the branch and the directory. Candidates: a kebab slug of the
  task; `<current-branch>-<slug>`; `<slug>-<shortsha>` of `origin/<default>` (or the current commit if there
  is no origin); `<slug>-2`; `<slug>-3`.
- Existing local branch. The branch stays as it is. Candidates: the branch name (recommended); its leaf
  (`feature/foo` becomes `foo`) when that differs; `<leaf>-<shortsha>` of that branch; `<leaf>-2`.
- Pull request. The local branch stays `pr-<n>`. Candidates: `pr-<n>` (recommended); the PR head branch's
  leaf (`gh pr view <n> --json headRefName,author`); `pr-<n>-<author>`; `pr-<n>-<shortsha>`.

Pass the choice as `--name`. Omit `--name` when it equals the branch.

- New branch from `origin/<default>`: `gu worktree add <repo> <branch> [--name <name>]`.
- Existing local branch that is not checked out: the same command (no `-b`; the command checks the branch out).
- Branch already checked out: stop. The error names the path that has it. Offer a new branch name (through
  this same name question) or `--detach`.
- Pull request: `gu worktree add <repo> --pr <n> [--name <name>]`.

**Submodules.** If the repo has `.gitmodules`, ask: `Init submodules` (recommended for pyxis and rock) · `Skip`.
Pass `--submodules` only after a yes.

**After.** Print the path. Ask: `Open in Cursor` (`cursor-ide <path>`) · `Open in VS Code` (`code <path>`) · `Leave it`.
Do not change the user's shell directory. Under the sandbox, opening an app is blocked: give the user the
command to run with `!`. Say in one line how to work there with Claude: a new Claude Code session in that folder
(`cd <path> && claude`, or choose the folder in the desktop app). This session stays where it is.

## List

Run `gu worktree list [repo...] --fetch --gh`. Captured (as here) it prints `|` rows; on the user's terminal
the same command shows a grouped view. `--fetch` makes `upstream-gone` current and `--gh` finds PRs and squash
merges; drop `--gh` (and say so) when gh is unreachable. Summarize grouped by repo, one line per worktree: name,
branch, PR, and status. Do not paste the raw rows. Notes:
- `merged`, `merged(#n)`: the branch's work is in the default branch (merge, or squash merge of PR #n). Safe to clean up.
- `pr-merged(#n)+local`: PR #n was merged, but the local branch has commits the PR did not. Show them
  (`git log <default>..<branch>`) before suggesting anything.
- `upstream-gone`: its remote branch was deleted, usually by a merge. Not proof: check the PR before cleanup.
- `main` (the main checkout), `LOCKED`, `missing` (directory gone; Clean up clears it), `outside` (a linked worktree not
  in `<repo>/.claude/worktrees`; see Gather).

**Gather.** When there are `outside` worktrees, offer `gu worktree reset [repo...]`: a dry run that prints
`move` and `skip` rows. Show the plan and run it with `--apply` only after a yes. Cursor's worktrees
(`~/.cursor/worktrees/`) are skipped unless the user says to include them (`--all`), since Cursor tracks them.

## Rename

Ask which worktree (from `list`) and the new name, with the same name rules and question as Add. Then ask:
`Rename the folder only` · `Rename the folder and the branch` (only when the branch was never pushed: once it tracks
a remote branch, a local rename splits it from its PR, and the command refuses). Run
`gu worktree move <path> <new-name> [--branch]`. A worktree with submodules cannot be moved (git refuses).
Don't rename a Claude desktop session's worktree (branch `claude/...`): the app tracks its path. If a Claude, Cursor
or VS Code window is open on the old path, say it must reopen on the new one.

## Clean up

Run `gu worktree cleanup [repo...]`. It lists what is safe to delete: `remove|repo|path|branch|note` rows for
clean worktrees whose branch is merged (`merged` or `merged(#n)`), and `stale|repo|path|...` rows for worktrees whose
folder is already gone. Everything else (dirty, unmerged, detached, this shell's) is kept and only counted. Show the
list, then ask `Remove all of them` (`gu worktree cleanup --apply`) · `Let me pick` · `Cancel`. For `Let me pick`
(multiSelect, up to 4), run `gu worktree remove <path> --delete-branch` for each pick. Either way:
- It refuses the main worktree and a dirty one. `--force` only when the user names it.
- `--delete-branch` deletes the local branch only when its work is provably in the default branch (an ancestor, or
  the head of a merged PR). Otherwise it prints `kept: ...`; relay that, and never run `branch -D` yourself unless
  the user names it.
- A `claude/...` branch usually belongs to a Claude desktop session. Say that archiving the session in the app is
  the usual cleanup; remove it here only if the session is already archived.
- Never remove the worktree this session is running in; say to do it from another folder.
- The remote branch is left alone; `/gu-repo` cleans those up.

To remove a worktree that cleanup keeps (dirty or not merged), use `gu worktree remove <path>` after showing
the user what would be lost (`git -C <path> status --short`, `git log <default>..<branch>`).
