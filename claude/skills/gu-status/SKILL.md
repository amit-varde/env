---
name: gu-status
description: Read-only status of every repo under ~/work and their submodules - branch, behind/ahead, uncommitted work, stashes, rebases in progress, locks, submodules needing attention - and what to do about each. Use for "/gu-status", "status of all repos", "what's uncommitted in work", "which repos are behind", "check my submodules".
argument-hint: "[--no-fetch] [--all] [repo ...]"
---

# Status of all repos

Follow `~/.claude/skills/gu-common/CONVENTIONS.md`. `gu` = `bash ~/.claude/skills/gu-common/bin/gu`.

1. Run `gu ws --fetch [repo...] | column -t -s'|'`. Use `allowed_domains: github.com`.
   Drop `--fetch` for `--no-fetch`, "quick" or "offline". Use `--all` to list every
   submodule (by default only those needing attention are shown).
2. Show the table, then **Needs attention**, most urgent first, each with its fix:

| Finding | Fix |
|---|---|
| `op` REBASE/MERGE, `MERGE_CONFLICT` | finish or abort (`git -C <repo> status`) |
| `FETCH_FAILED` | 401/403 -> /gu-auth; `CONNECT tunnel` -> re-run with github.com allowed |
| submodule `commits-on-no-remote` or dirty | push it from the submodule (/gu-push) before any `submodule update` |
| dirty/untracked, ahead, `no-upstream` | /gu-push (or leave it if intentional) |
| behind, default behind, `not-at-recorded-commit` | /gu-update |
| `UPSTREAM_GONE` | /gu-repo branch cleanup |
| `LOCKED(level)` | informational; /gu-unlock to change |

3. End with one line, e.g. `4 clean and current; api 77 behind; infrastructure has 2 uncommitted files`.
