---
name: gu-pr-review
description: Review someone's GitHub pull request - fetch diff and context, optionally check out in a worktree and run tests, find real problems, and (only after the user approves) post inline comments with an approve / comment / request-changes verdict. Use for "review PR 123", "look at this PR", "leave comments on", "approve this PR", or a PR URL asking for feedback.
argument-hint: "<pr-number | url>"
---

# Review a PR

Follow `~/.claude/skills/gu-common/CONVENTIONS.md`. `gu` = `bash ~/.claude/skills/gu-common/bin/gu`.
Reading is free; posting needs the user's OK.

1. **Pick:** use the argument, or offer up to 4 from `gu prs review`.
2. **Context:** `gu pr <n> [--repo o/r]`, `gh pr diff <n>`, and `gh pr view <n> --comments`. Also read any linked issue and the
   repo guides (including nested AGENTS.md in the touched folders). Ask: `Review the diff only` (small PR) ·
   `Check out in a worktree and run tests` (large or risky: ask for the directory name the way /gu-worktree does, then `gu worktree add <repo> --pr <n> [--name <name>]`)
   · `Use the code-review skill`.
3. **Review** in this order: correctness, security, data loss and concurrency, missing tests, API breaks, clarity.
   Skip lint nits. For each finding give file:line, a concrete failing scenario and a fix. Drop anything you can't back with the code.
4. **Show** the findings ranked by severity and ask for the verdict: `Request changes` (blocking bug) · `Comment` ·
   `Approve` (nothing blocking) · `Don't post`. Then pick which findings to post (multiSelect, blocking first).
5. **Post** as one review:
   ```bash
   gh api repos/O/R/pulls/N/reviews --method POST --input - <<'EOF'
   {"event":"REQUEST_CHANGES","body":"summary","comments":[
     {"path":"src/a.c","line":42,"side":"RIGHT","body":"..."},
     {"path":"src/b.c","start_line":10,"line":14,"side":"RIGHT","body":"```suggestion\n...\n```"}]}
   EOF
   ```
   `line` must be in the PR diff (`side: LEFT` for deleted lines); a 422 means it isn't. You can't approve your own PR.
   A plain review uses `gh pr review <n> --approve|--comment|--request-changes --body-file f`.
6. **Clean up:** ask `Remove the worktree` (`gu worktree remove <path>`) · `Keep it`. Report the review URL.
