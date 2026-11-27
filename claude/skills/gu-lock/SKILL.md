---
name: gu-lock
description: Lock repos under ~/work against accidental changes - blocks commits, branch switches, resets, pulls, stashes and pushes (even --no-verify) while fetch still works; optionally makes tracked files read-only; drops group/other access. Undo with /gu-unlock. Use for "/gu-lock", "lock rock", "freeze this repo", "make pyxis read-only", "which repos are locked".
argument-hint: "<repo>... [--level git|files|full] [--recursive] [--reason TEXT] | status"
---

# Lock repos

Follow `~/.claude/skills/gu-common/CONVENTIONS.md`. `gu` = `bash ~/.claude/skills/gu-common/bin/gu`.

| Level | Blocks | Still allowed |
|---|---|---|
| `git` (default) | commit, branch create/switch/delete, reset, merge, pull, rebase, stash, tag, push | fetch, builds, editing files |
| `files` | editing, creating or deleting tracked files (so also `reset --hard`, `checkout --`, `clean`) and in-tree build outputs | git ref changes |
| `full` | both | fetch, reading |

Every level also runs `chmod -R go-rwx`. That's the `lock` alias (700) without touching
the execute bits, because literal 700/755 would show every file as a mode change in git.
`git` alone does not protect uncommitted edits from `reset --hard`, `checkout -- f` or `clean`.
Repo hooks are off while a repo is locked.

1. `gu locks` shows the current state. With no repo or `status`, show it and stop.
2. `gu ctx <repo> --no-gh` shows dirty files, any operation in progress and submodules.
3. Ask only what the arguments leave open:
   - Level: recommend `full` if the repo is dirty or the user said "read-only". Warn
     that `files`/`full` break in-tree builds (EDA repos).
   - `Include submodules` (`--recursive`) when any are initialized.
   - The reason, in the user's words.
4. Run `gu lock <repo> --level L [--recursive] --reason "..."`. On `(sandbox? ...)`,
   nothing was changed; give the user the printed `! gu lock ...` command.
5. Verify with `gu locks`. Report the level, what's blocked, and "undo: /gu-unlock <repo>".
