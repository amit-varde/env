# Claude Code skills (`claude/skills/`)

[← README](../README.md)

`~/.claude/skills` links here, so each folder is a `/command` in Claude Code. Cursor
also reads `~/.claude/skills`, so the same skills show up there. Every skill is
interactive: it asks before changing anything.

Shared **user** settings (permissions, sandbox, [Code Mode](claude-code.md) default)
live in `claude/settings.json`, not in individual skills.

`setup-env.sh` links every folder that contains a `SKILL.md`, and `env-doctor`
checks that each one has `name` and `description` front matter. `claude/skills/synced/`
is managed by your Claude account, not by this repo, so it is left alone.

Skills are grouped by the job they do. Type the example in Claude Code (or
Cursor's agent chat); a skill with no argument asks what you want first.

| Group | Skill | Use it to | Example |
|---|---|---|---|
| **Repo health across `$WORK`**<br>See where every repo under `$WORK` stands and bring them up to date without losing local work. Lock a repo when it must not change, for example during a release or tapeout. | `/gu-status` | Show branch, behind/ahead, uncommitted work and submodule state for every repo under `$WORK`, and what needs attention | `/gu-status`<br>`/gu-status rock pyxis` |
| | `/gu-update` | Fetch and fast-forward the current repo (or named ones, or all), and walk through dirty, diverged or conflicting ones interactively | `/gu-update`<br>`/gu-update rock --dry-run` |
| | `/gu-update-all` | Same as `/gu-update --all`: every repo under `$WORK` | `/gu-update-all`<br>`/gu-update-all --dry-run` |
| | `/gu-lock` | Lock a repo locally: block commits, branch changes, pulls and pushes, optionally make files read-only, and drop group/other access | `/gu-lock pyxis --reason "tapeout freeze"`<br>`/gu-lock status` |
| | `/gu-unlock` | Undo `/gu-lock` exactly (hooks, write access, group/other access) | `/gu-unlock pyxis` |
| **Branches and worktrees**<br>Work on several changes at once without touching your main checkout, and keep branches tidy. Worktrees live in `<repo>/.claude/worktrees`, next to Claude's own ([Worktree flow](worktree-flow.md)). | `/gu-worktree` | Add, list, rename and clean up worktrees, including removing ones whose PR was merged | `/gu-worktree add rock login-fix`<br>`/gu-worktree cleanup` |
| | `/gu-repo` | Clone, fork, clean up merged or gone branches, update submodules | `/gu-repo owner/repo`<br>"clean up merged branches in env" |
| | `/gu-fork-sync` | Pull the original's changes into your fork, send your commits back to the original, or (as the owner) take commits from forks, always through PRs ([Forks](fork.md)) | `/gu-fork-sync`<br>`/gu-fork-sync send env` |
| **Changes and pull requests**<br>Take a change from your working tree to `main`: commit and push it, open a PR, follow its CI and reviews, answer feedback, and merge. Every step that publishes something asks first. | `/gu-push` | Commit and push to the right branch (checks the README and docs when pushing to `main`) | `/gu-push`<br>`/gu-push fix/login-timeout` |
| | `/gu-pr-create` | Open a pull request from local changes, titled after its worktree | `/gu-pr-create`<br>`/gu-pr-create release-2.1` |
| | `/gu-pr-status` | Show CI, review state and mergeability of your PRs, and why CI failed | `/gu-pr-status`<br>`/gu-pr-status 42` |
| | `/gu-pr-feedback` | Address review comments, update the branch from its base, and get your PR ready to land | `/gu-pr-feedback 42` |
| | `/gu-pr-review` | Review someone else's PR, and post comments only after you approve them | `/gu-pr-review 57`<br>`/gu-pr-review https://github.com/owner/repo/pull/57` |
| | `/gu-merge` | Pick an open PR or branch and merge it into `main` after checking CI, reviews, conflicts and the README and docs, then clean up its branch and worktree | `/gu-merge`<br>`/gu-merge 42` |
| **GitHub project work**<br>The GitHub side of a project beyond a single PR: issues, Actions runs, and releases. Reading is free; filing, re-running, triggering and publishing ask first. | `/gu-issues` | Search, file, comment on and close issues | `/gu-issues 118`<br>`/gu-issues flaky regression` |
| | `/gu-actions` | View, re-run, cancel and trigger GitHub Actions runs, and read failing logs | `/gu-actions`<br>`/gu-actions 1234567890` |
| | `/gu-release` | Suggest the next version, draft grouped release notes, and tag and publish a release | `/gu-release`<br>`/gu-release v1.4.0` |
| **Access and machine setup**<br>Get a machine able to reach GitHub and your remote hosts. Run these once on a new machine, or when a login or key stops working. | `/gu-auth` | Log in to GitHub, fix invalid tokens, missing scopes and SSO | `/gu-auth`<br>"gh says my token is invalid" |
| | `/env-ssh` | Check `~/.ssh` permissions, link config and keys, set user/key, clean old backups, verify hosts ([details](ssh.md)) | `/env-ssh status`<br>`/env-ssh test myhost` |

The `/gu-*` skills are one kit: they share `claude/skills/gu-common/` — `CONVENTIONS.md`
(rules all of them follow), and `gu`, a bash command (`bin/gu` wraps it) that does the
fact-gathering and safety checks so the skills stay short. `gu help` lists its
commands, [gu](gu.md) documents them and their shell aliases; see [gu-common/README.md](../claude/skills/gu-common/README.md) for the map
of skills to commands and how to add one.

To add one: create `claude/skills/<name>/SKILL.md` with `name` and
`description` front matter. It appears as `/<name>` in new sessions.
