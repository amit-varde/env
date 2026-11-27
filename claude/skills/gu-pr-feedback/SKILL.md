---
name: gu-pr-feedback
description: Move your own open PR toward merge - address review comments, reply to and resolve threads, update the branch from base (rebase or merge), resolve conflicts, push, mark ready, re-request review. Use for "address the review comments", "fix what the reviewer asked", "rebase my PR", "my PR has conflicts", "update the branch", "mark ready".
argument-hint: "[pr-number]"
---

# Address PR feedback

Follow `~/.claude/skills/gu-common/CONVENTIONS.md`. `gu` = `bash ~/.claude/skills/gu-common/bin/gu`.

1. **Facts:** `gu pr [n]` and `gu ctx`. The local branch must be the PR head (`gh pr checkout <n>`) and the tree clean.
   A FORK PR you can't push to: stop and say so.
2. **Feedback:** `gu threads <n>` for inline threads, and `gh pr view <n> --comments` for review summaries. Batch up to 4 per question,
   quoting each briefly: `Fix as suggested` · `Push back` (recommend this when the suggestion is wrong, and say why) ·
   `Ask the reviewer to clarify` · `Skip`. Never skip one silently.
3. **Changes:** edit, run the repo's tests, and add new commits (easier to re-review) unless the repo uses fixup and autosquash.
4. **Update from base** if `mergeable` shows BEHIND or DIRTY: `Rebase on origin/<base>` (recommend when the base history is linear) ·
   `Merge origin/<base>` (recommend when the base has merge commits) · `Don't update`. Before a rebase, print
   `git rev-parse HEAD` as the undo point. Explain any non-obvious conflict resolution. In a submodule conflict, choose
   the intended SHA (`git -C <sub> checkout <sha> && git add <sub>`).
5. **Push** (`Push now` · `Show the diff first`): `git push`, or `git push --force-with-lease` after a rebase.
6. **Replies** (show the wording): `Reply and resolve` · `Reply only, reviewer resolves` · `No replies`. Use the
   reply and resolve commands that `gu threads` prints. Then re-request review with `gh pr edit <n> --add-reviewer <login>`.
7. **Next:** draft -> `gh pr ready <n>` if wanted. When it's green and approved, hand off to /gu-merge.
