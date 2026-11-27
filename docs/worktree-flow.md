# Worktree flow

[← README](../README.md)

A git worktree is a second working folder for the same repo, on its own branch.
You can work on a change, or run an agent on it, without touching your main
checkout, and you can have several at once. This page covers the whole life of
one: create it, work in it, open a PR, merge, clean up. There are separate
sections for Claude Code, Cursor and VS Code users.

## The idea: one name for folder, branch and PR

```text
<repo>/.claude/worktrees/<name>    the folder   (e.g. ~/work/rock/.claude/worktrees/login-fix)
<name>                             the branch   (login-fix)
<name>                             the PR title (login-fix)
```

You pick `<name>` once, when you create the worktree. For a new branch, the
branch gets the same name. `/gu-pr-create` offers it as the PR title. When the
PR is merged, `/gu-merge` and `/gu-worktree` find the worktree by that branch and
offer to remove it.

The folder is the one Claude Code uses for its own worktrees: Claude desktop
sessions and `claude --worktree` create theirs there too (branch `claude/<name>`).
So every worktree of a repo is in one place, and the tools see each other's.
A `.claude/worktrees/` line in the repo's `.git/info/exclude` keeps the folder
out of `git status`; `gu worktree add` writes it if Claude Code hasn't.

```text
┌──────────────────────────────────────────────┐
│ 1. Create                                    │
│    /gu-worktree → Add                        │
│    folder + branch = <name>                  │
└──────────────────────┬───────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────┐
│ 2. Rename (optional, before the first push)  │
│    /gu-worktree → Rename                     │
└──────────────────────┬───────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────┐
│ 3. Work                                      │
│    you, or an agent in that folder           │
└──────────────────────┬───────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────┐
│ 4. Open a PR                                 │
│    /gu-pr-create  (title = <name>)           │
└──────────────────────┬───────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────┐
│ 5. Merge                                     │
│    /gu-merge                                 │
└──────────────────────┬───────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────┐
│ 6. Clean up                                  │
│    /gu-merge offers it right after merging,  │
│    or later: /gu-worktree → Clean up         │
│    removes the folder and the local branch   │
└──────────────────────────────────────────────┘
```

## The commands

The skills call `gu worktree`, and you can run it yourself from any
terminal (`gu` is on your `PATH`):

| Command | What it does |
|---|---|
| `gu worktree add <repo> <branch> [--name <name>]` | New worktree. A new branch starts from `origin/<default>`; an existing branch is checked out as is. `<name>` defaults to the branch |
| `gu worktree add <repo> --pr <n> [--name <name>]` | Check out PR `n` as branch `pr-<n>` (for reviewing) |
| `gu worktree list [repo...] [--fetch] [--gh]` | Every worktree. On a terminal: grouped by repo, with PR number and status (below). Piped: `\|` rows with notes such as `merged`, `merged(#12)`, `upstream-gone`, `LOCKED` |
| `gu worktree move <path> <new-name> [--branch]` | Rename the folder; `--branch` also renames a branch that was never pushed |
| `gu worktree remove <path> [--delete-branch]` | Remove a clean worktree; `--delete-branch` deletes its branch only if the work is already merged |
| `gu worktree cleanup [repo...] [--apply\|-n]` | List the worktrees that are safe to delete (clean and merged, or folder already gone), then ask: all, select one by one, or none. `--apply` removes them all without asking; `-n` only lists |
| `gu worktree reset [repo...] [--all] [--apply]` | Move worktrees that live elsewhere into `<repo>/.claude/worktrees/` (see [Gather stray worktrees](#gather-stray-worktrees)) |

In your shell, the same commands have short aliases: `wt` (`gu worktree`), `wt-list`
(`list --fetch --gh`), `wt-add`, `wt-mv`, `wt-rm` (`remove --delete-branch`), `wt-cleanup` and `wt-reset`.

`add` also takes `--submodules` (needed for `pyxis` and `rock`), `--from <ref>`
(another start point) and `--detach` (read-only; works on a locked repo).

### What `wt list` shows

On a terminal, `wt list` (or `wt-list`, which fetches first) groups worktrees by repo:

```text
env : ~/work/env : amit-varde/env
     WORKTREE   PATH                                    PR     STATUS                   BRANCH
     login-fix  ~/work/env/.claude/worktrees/login-fix  PR#21  active dirty             login-fix
     old-docs   ~/work/env/.claude/worktrees/old-docs   PR#14  merged                   old-docs
     spike      ~/work/env/.claude/worktrees/spike      -      local-br-only behind(3)  spike
(4 repos without worktrees not shown)
```

The repo line is `<repo> : <main checkout> : <remote>`, followed by a header and
one line per worktree: its name (blue), path (white), PR (white,
`PR#<number>`: the open PR, else the merged one), status, and branch (grey).
A worktree can have several status words, colored in Google's palette:

| Status | Color | Meaning |
|---|---|---|
| `active` | blue | The branch has an open PR |
| `merged` | green | Its work is in the default branch (merge, rebase or squash merge). Safe to remove |
| `dirty` | yellow | Uncommitted or untracked files |
| `behind(N)` | yellow | `origin/<default>` has N commits the branch doesn't (not shown once merged) |
| `local-br-only` | red | The branch exists only on this machine: never pushed, or its remote branch was deleted |
| `missing` | red | The folder is gone; `wt-cleanup --apply` clears it |
| `outside` | dim | Not in `<repo>/.claude/worktrees`; `wt-reset` moves it there |

`wt list --rows` (and any piped use, such as the skills) prints the `|` rows
with the notes below instead.

### How "merged" is decided

`list` notes, and what `remove --delete-branch` does with each:

| Note | Meaning | `--delete-branch` |
|---|---|---|
| `merged` | The branch tip is already in the default branch (merge or rebase merge) | deletes the branch |
| `merged(#12)` | PR #12 was squash-merged, and its head is this branch's tip | deletes the branch |
| `pr-merged(#12)+local` | PR #12 was merged, but the branch has commits the PR did not | keeps it |
| `upstream-gone` | The remote branch was deleted (often by the merge), with no PR found | keeps it |

Squash merges leave no trace in git history, so finding them takes GitHub
(`--gh`; `remove` asks it on its own). `list --gh` looks at the 200 most recent
merged PRs per repo. The remote branch is never deleted here: GitHub can do that
on merge, or `/gu-repo` cleans up old ones.

## Gather stray worktrees

Worktrees made outside this flow can live anywhere, for example
`~/work/env-worktrees/` or a folder VS Code chose. `wt list` marks them
`outside`. `wt-reset` moves them into `<repo>/.claude/worktrees/<folder name>`:

```bash
wt-reset
```

```bash
wt-reset --apply
```

- Without `--apply` it only prints the plan: `move` rows, and `skip` rows with
  the reason.
- It skips Cursor's worktrees (`~/.cursor/worktrees/`), because Cursor tracks
  them and moving one breaks its open window. Close the window, then run
  `wt-reset --all --apply`.
- It also skips locked worktrees, folders that are already gone (`wt-cleanup`),
  and the folder your shell is in. git can't move a worktree that has
  submodules; `reset` reports it and moves on.
- A name that's already taken gets `-2`, `-3`, and so on.

Keep the desktop app's **Settings → Claude Code → worktree location** at
"Inside the project" (the default), so new session worktrees land in the same
folder.

## Claude Code users

This covers the CLI, the desktop app's Code tab and the VS Code extension. They
all read the skills in `~/.claude/skills`.

1. **Create.** `/gu-worktree` → `Add` (or "make a worktree in rock for the login
   fix"). Claude asks for the name first. It offers three free names and a
   `Write in` choice, and each option shows the full folder path. For `pyxis` and
   `rock` it asks whether to initialise submodules.
2. **Rename (optional).** Before any push, `/gu-worktree` → `Rename` can rename
   the folder, and the branch with it. Once the branch is pushed, only the
   folder can be renamed, because a local branch rename would split the branch
   from its PR.
3. **Work.** Start a Claude Code session in the new folder: `cd <path> && claude`,
   or choose the folder in the desktop app. The session that created the
   worktree stays where it is.
4. **PR.** In the worktree session, `/gu-pr-create`. `gu ctx` reports
   `worktree: <name>`, and the first title it offers is exactly that name.
5. **Merge.** `/gu-merge`. After merging, it looks for a worktree on the merged
   branch and offers `Remove the worktree and its branch`. Do this from a session
   that is not running inside that worktree.
6. **Clean up later.** `/gu-worktree` → `Clean up`, or `wt-cleanup` in a shell,
   lists the worktrees that are safe to delete (clean and merged, or folder
   already gone), numbered and colored. In a shell it then asks: `a` removes
   them all, `s` asks y/N for each one, `n` (the default) leaves them. Each
   removal also deletes the local branch. `wt-cleanup --apply` removes them all
   without asking.

**Under the sandbox.** Claude's command sandbox can block writes to another
repo's `.git` (so `git worktree add/move/remove` fail) and blocks opening apps.
When that happens Claude prints the exact command. Run it with `!` in the message
box, for example `! gu worktree add rock login-fix`.

**Desktop app session worktrees.** The Claude desktop app puts each session's
worktree in the same folder, `<repo>/.claude/worktrees/<name>`, on a branch
called `claude/<name>`. `wt list` shows them next to yours, and steps 4–6 work
for them too: the PR title offered is the session's worktree name. The app
tracks these, so don't rename or remove one while its session is open; archiving
the session in the app is the usual cleanup.

## Cursor users

Cursor also reads `~/.claude/skills`, so in Cursor's agent chat the same
`/gu-worktree`, `/gu-pr-create` and `/gu-merge` work as in the Claude Code steps
above. From a terminal:

```bash
gu worktree add rock login-fix --submodules
```

```bash
cursor ~/work/rock/.claude/worktrees/login-fix
```

- `cursor` is `cursor-ide`: it opens the folder in IDE mode (see [Cursor](cursor.md)).
  Open each worktree in its own window. The Source Control view shows that
  worktree's branch and changes.
- Make the PR from the agent chat (`/gu-pr-create`) or with `gh pr create --title login-fix`.
- After the merge, close the window first, then:

```bash
gu worktree list rock --fetch --gh
```

```bash
gu worktree remove ~/work/rock/.claude/worktrees/login-fix --delete-branch
```

## VS Code users

With the Claude Code extension for VS Code, the skills work as in the Claude
Code steps. Without it, use the integrated terminal:

```bash
gu worktree add rock login-fix --submodules
```

```bash
code ~/work/rock/.claude/worktrees/login-fix
```

- `code` opens the folder in VS Code. On macOS it's an alias for the app (see
  [Shell functions and aliases](shell.md)). Use one window per worktree.
- PR: `gh pr create --title login-fix` from the worktree's terminal, or the
  GitHub Pull Requests extension. Either way, use the worktree name as the title.
- VS Code's own "Create Worktree" command puts worktrees wherever you choose.
  `wt list` still shows them, marked `outside`, and `remove --delete-branch`
  works on them. `wt-reset` moves them into `<repo>/.claude/worktrees/`.
- After the merge, close the window, then run `list` and `remove` as in the Cursor section.

## Limits

- `move` can't move a worktree that has submodules; git refuses.
- `remove` refuses a worktree with uncommitted or untracked files unless you pass
  `--force`. The skills only pass it when you ask by name.
- A repo locked with `/gu-lock` refuses new branches. `add --detach` still makes a
  read-only worktree, and the lock refuses commits inside it.
- Worktrees share one `.git`: a branch can be checked out in only one worktree at
  a time, and `add` names the folder that already has it.
