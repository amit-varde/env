---
name: gu-push
description: Commit current changes and push them to the right branch safely - avoids protected/default branches, syncs a behind or diverged branch, handles submodules and forks, checks the README when pushing to main. Use for "/gu-push", "commit and push", "push this", "push my changes", "sync my branch".
argument-hint: "[commit message | target-branch]"
---

# Commit and push

Follow `~/.claude/skills/gu-common/CONVENTIONS.md`. `gu` = `bash ~/.claude/skills/gu-common/bin/gu`.

## 1. Facts
`gu ctx [repo]` covers the branch, upstream, behind/ahead, changed files, unpushed
commits, submodules, PR, protection, guides and commit style. Several repos changed?
Run it per repo and ask which repo first (submodules before their parent).
`upstream: GONE` or `LOCKED` -> stop and say why.

An argument that looks like a branch name (no spaces, `type/topic`) is the target
branch. Otherwise it's the commit message.

## 2. Decisions (ask only those that apply)
| When | Options (recommended first) |
|---|---|
| `ON DEFAULT` or protected=yes | `Create <type>/<topic> and push there` · `Push to <default>` (only if not protected; recommend for a personal repo with no PR flow) · `Cancel` |
| Unrelated, generated, binary or secret-looking files in the change list | `Only this change's files` · `Everything` · `Let me pick` (multiSelect) |
| Message drafted (show it) | `Use it` · `Edit` · `Split into several commits` |
| behind>0 and ahead>0 | `Rebase onto upstream` · `Merge upstream` · `Stop` (never force here) |
| Own branch rewritten | `Push --force-with-lease` · `Push to a new branch` |
| Pushed, `pr: none`, not default | `Open draft PR via /gu-pr-create` · `No PR now` |

## 3. Actions
1. Submodule changes: run this skill in the submodule first, then `git add <path>` in the parent.
2. Stage explicit paths (`git add <paths>`). Secret scan:
   `git diff --cached | grep -inE 'api[_-]?key|secret|token|password|PRIVATE KEY'`.
3. Target is the default branch: `gu readme --staged`, and fix the gaps in this commit.
4. Commit. Run cheap documented hooks or linters; never `--no-verify`.
5. Behind only: `git pull --ff-only`. Diverged: `git pull --rebase` or `--no-rebase`.
   On conflicts, resolve with the user; `git rebase --abort` backs out.
6. `git push` / `git push -u origin HEAD` (first push). Rejected as non-fast-forward:
   go back to step 5. Rejected by rules (GH006): new branch. 401/403: /gu-auth.

## 4. Report
The commit SHA and subject, `origin/<branch>`, and the PR link if there is one.
