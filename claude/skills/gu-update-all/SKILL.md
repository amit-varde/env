---
name: gu-update-all
description: Alias for /gu-update --all - safely update every repo under ~/work (fetch all, fast-forward clean repos in one confirmed batch, walk through the rest one at a time). Use for "/gu-update-all", "update all my repos", "pull everything", "sync all repos".
argument-hint: "[--dry-run]"
---

# Update all repos

Run the /gu-update skill with `--all`: read `~/.claude/skills/gu-update/SKILL.md` and follow it,
with every repo under `$WORK` as the target. Pass `--dry-run` through if given.
