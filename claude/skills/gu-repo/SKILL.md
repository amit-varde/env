---
name: gu-repo
description: Repository housekeeping with git and gh - clone with submodules, fork and sync a fork, repo info, read a file on another branch, prune merged/gone branches, update or bump submodules. Use for "clone the X repo", "fork this", "sync my fork", "clean up old branches", "delete merged branches", "update submodules", "what's the default branch".
argument-hint: "[owner/name]"
---

# Repo housekeeping

Follow `~/.claude/skills/gu-common/CONVENTIONS.md`. `gu` = `bash ~/.claude/skills/gu-common/bin/gu`.
With a bare `/gu-repo`, ask first: `Clone` · `Sync fork` · `Clean up branches` · `Update submodules`.

## Clone
Ask: location `~/work/<name>` · current dir; depth `Full with submodules` · `--depth 1` · `No submodules`.
Run `gh repo clone owner/name [dir] -- --recursive`. Relative submodule URLs (`../rock`) resolve
against the parent's org, so clone from the org, not a personal fork.

## Info
`gu ctx <repo>` for local state. Also: `gh repo view owner/name --json name,defaultBranchRef,visibility,url`,
`gh api repos/O/R/contents/<path>?ref=<branch> --jq .content | base64 -d` (read a file without cloning),
`gh api repos/O/R/branches/<b>/protection` (a 404 means none, or no access).

## Forks
`gh repo fork owner/name --clone --remote` (adds `upstream`), then `gu fork wire <repo>` to disable pushing to
`upstream`. Syncing in either direction (pull the original in, send commits back, take from forks) is
`/gu-fork-sync`: hand off to it.

## Branch cleanup
Run `gu branches [repo]`. Ask the scope: `Local merged only` · `Also delete on the remote` · `Just list`.
Then ask which ones (multiSelect; LOCAL_MERGED and LOCAL_GONE first).
- Local: `git branch -d <b>`. LOCAL_SQUASHED needs `-D`, so only with an explicit yes and the PR named.
- Remote: `git push origin --delete <b>`, after confirming.
- Never delete LOCAL_UNPUSHED branches without showing their commits.

## Submodules
`gu ctx <repo>` shows moved and dirty submodules. Ask: `Update to the pinned commits` (`git submodule update --init --recursive`)
· `Bump to latest upstream` · `Bump to <sha>` (`git -C <sub> checkout <sha> && git add <sub>`, then commit).
Push a submodule change in its own repo before the parent's bump.

Admin actions (create, rename, archive, visibility, collaborators, protection) only on explicit request:
state the exact change and confirm.
