---
name: gu-unlock
description: Undo /gu-lock on repos under ~/work - restores the previous hooks, write access (keeping files that were already read-only) and group/other access. Use for "/gu-unlock", "unlock rock", "unfreeze this repo", or when git says "gu-lock: ... is locked".
argument-hint: "<repo>... [--recursive]"
---

# Unlock repos

Follow `~/.claude/skills/gu-common/CONVENTIONS.md`. `gu` = `bash ~/.claude/skills/gu-common/bin/gu`.

1. Run `gu locks`. With no repo given, ask which LOCKED ones to unlock (multiSelect,
   with level and reason). If the given repo isn't locked, say so and stop.
2. Locked submodules under it: ask `Unlock submodules too` (`--recursive`) · `Only the top repo`.
3. Run `gu unlock <repo> [--recursive]`. On `(sandbox? ...)`, give the user the printed `! gu unlock ...`.
4. Verify with `gu locks` and `git -C <repo> status --short`, which should show no mode noise.
   Unlock restores `core.hooksPath`, write access and `go+rX` (the `unlock` alias, 755,
   without making plain files executable).

If the lock state is gone but files are still read-only, offer `chmod -R u+w,go+rX <repo>`,
and warn that it also makes intentionally read-only files writable.
