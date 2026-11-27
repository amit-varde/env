---
name: gu-pr-status
description: Where pull requests stand - my open PRs, PRs waiting on my review, CI checks, review decision, mergeability, conflicts, unresolved threads, and diagnosis of failing GitHub Actions jobs from their logs. Use for "status of my PR", "why is CI red", "is my PR approved / mergeable", "what PRs need my review", "show failing checks".
argument-hint: "[pr-number | url | branch]"
---

# PR status and CI triage

Follow `~/.claude/skills/gu-common/CONVENTIONS.md`. `gu` = `bash ~/.claude/skills/gu-common/bin/gu`. Everything here is read-only.

1. **Which PR:** with an argument, use it. Otherwise ask: `This branch's PR` (if `gu ctx` shows one) ·
   `All my open PRs` (`gu prs mine`) · `Waiting on my review` (`gu prs review`) · `A specific PR`.
   For a list, offer up to 4, failing or changes-requested first.
2. **Detail:** `gu pr <n> [--repo o/r]` gives CI with failing and pending names, review, mergeability, behind, unresolved
   thread count and merge options. Summarize it in a short table. `gu threads <n>` lists the unresolved threads.
3. **Failing check:** ask `Diagnose from the logs` · `Re-run the failed jobs` (recommend this when the
   flaky line shows the job also fails on main; rerunning is /gu-actions) · `Just report`.
   For a diagnosis, run `gu ci <n>`: it prints the first errors per failing Actions job, a link for non-Actions CI
   (Jenkins: gh can't read it), and the recent results of the same workflow on the default branch.
   Open the workflow YAML to find the exact command. Report the job, the first real error, the
   likely cause and a proposed fix. Then ask: `Fix it here` · `Open an issue` (/gu-issues) · `Leave it`.
4. **Pending:** `Watch in the background and report back` (`gh pr checks <n> --watch --fail-fast`, run in the background)
   · `Check again later`. Don't poll in a loop.
