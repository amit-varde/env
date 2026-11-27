# gu and its aliases

[← README](../README.md)

`gu` (git utils, named like `bu` for bash utils and `fu` for file utils) is the
command-line half of the `/gu-*` Claude Code skills. The skills
decide what to ask and recommend; `gu` gathers the facts (git and GitHub
state, in one call) and does the safe mechanical steps. You can run it yourself
from any shell. `bin/gu` puts it on your `PATH`, and the aliases below make
it shorter to type.

```text
gu <command> [args]          the command itself
gu-<command> [args]          one command, e.g. gu-ws, gu-ctx, gu-pr 12
gu-<skill> [args]            what the /gu-<skill> skill looks at first, e.g. gu-status, gu-merge
wt <subcommand> / wt-*       worktrees (see Worktree flow)
```

`gu help` lists every command with its options.

## Output

- **On a terminal:** tables are aligned and colored in Google's palette. Green is
  good (`merged`, `pass`, `CURRENT`), red needs attention (`LOCKED`, `fail`,
  `missing`), yellow is a warning (`behind`, `pending`, `upstream-gone`), and
  blue marks names and open PRs.
- **Piped or captured** (`| less`, scripts, the skills): plain `|` rows and
  `key: value` lines, so other tools can read them.
- **Controls:**
  - `NO_COLOR=1` or `GU_COLOR=never` turns color off; `GU_COLOR=always`
    forces it on, even through a pipe.
  - `GU_STATUS=1` adds `git status` for the repos a command touched. It's off by default.
- **Repo arguments:** a folder name under `$WORK` (`rock`), a path, or nothing for
  the repo you're in.

## Commands

| Command | Alias | What it shows or does |
|---|---|---|
| `gu ws [--fetch] [--all] [--plan] [repo...]` | `gu-ws` | One row per repo under `$WORK`: branch, upstream, behind/ahead, default branch, dirty and untracked counts, stash, operation in progress, last commit and notes (`LOCKED`, `no-upstream`, submodule drift). `--plan` adds the bucket `/gu-update` uses |
| `gu ctx [repo] [--no-fetch] [--no-gh]` | `gu-ctx` | Everything about one repo: identity, branch and sync, worktree name, changed files, unpushed commits, submodules, its PR, branch protection, guides, templates, CI, commit style |
| `gu prs [mine\|review\|repo]` | `gu-prs` | PR lists: yours (default), waiting for your review, or this repo's open PRs with CI, review and mergeability |
| `gu pr [number\|branch\|url]` | `gu-pr` | One PR: state, CI (failing and pending names), review, mergeability, behind, unresolved threads, allowed merge methods |
| `gu ci [pr\|--run ID\|--branch B]` | `gu-ci` | Failing CI: the first errors from GitHub Actions logs, links for other CI, and whether the same check is flaky on the default branch |
| `gu threads [number] [--all]` | `gu-threads` | Unresolved review threads: thread id, comment id, path:line, author, text |
| `gu branches [repo] [--base B]` | `gu-branches` | Branch inventory: merged, squashed, gone, unpushed and remote-only branches, with ahead/behind, last commit and PR |
| `gu lock <repo>... [--level git\|files\|full]` | `gu-lock` | Lock repos against accidental commits, branch switches, pulls and pushes (fetch still works) |
| `gu unlock <repo>...` | `gu-unlock` | Undo `lock` exactly |
| `gu locks [repo...]` | `gu-locks` | Which repos and submodules are locked, since when and why |
| `gu readme [range] [--staged] [repo]` | `gu-readme` | README/docs check for a change: `MISSING` (new names not documented), `STALE` (removed names still mentioned), `BROKEN` links |
| `gu release [repo]` | `gu-release` | Last tag, what merged since, grouped release notes and the suggested next version |
| `gu auth` | `gu-auth` | gh and git authentication: accounts, token state, scopes, credential helper, with a diagnosis |
| `gu worktree <list\|add\|move\|remove\|cleanup\|reset>` | `gu-worktree`, `wt` | Worktrees in `<repo>/.claude/worktrees`. See [Worktree flow](worktree-flow.md) |
| `gu fork status\|wire\|pull\|land\|send\|forks\|take` | `gu-fork` | A fork and its original: what each lacks, the `upstream` remote, sync and send branches in worktrees, fast-forward landing. See [Forks](fork.md) |
| `gu update ff\|default\|stash-pull <repo>` | (none) | One safe update step. `gu-update` (a command of its own) runs the whole update; use that instead |

## Aliases by skill

Each `/gu-<skill>` skill in Claude Code has a shell alias of the same name, where
one command is what that skill looks at first. Run it to see what the skill would
start from.

| Skill | Shell alias | Runs |
|---|---|---|
| `/gu-status` | `gu-status` | `gu ws` |
| `/gu-update`, `/gu-update-all` | `gu-update`, `gu-update-all` | the `gu-update` command (not an alias of `gu`) |
| `/gu-pr-status` | `gu-pr-status` | `gu prs mine` |
| `/gu-pr-review` | `gu-pr-review` | `gu prs review` |
| `/gu-merge` | `gu-merge` | `gu prs repo` |
| `/gu-actions` | `gu-actions` | `gu ci` |
| `/gu-repo` | `gu-repo` | `gu branches` |
| `/gu-lock`, `/gu-unlock` | `gu-lock`, `gu-unlock` | `gu lock`, `gu unlock` |
| `/gu-release` | `gu-release` | `gu release` |
| `/gu-auth` | `gu-auth` | `gu auth` |
| `/gu-worktree` | `gu-worktree` (or `wt`) | `gu worktree` |
| `/gu-fork-sync` | `gu-fork-sync` | `gu fork status` |

`/gu-push`, `/gu-pr-create`, `/gu-pr-feedback` and `/gu-issues` have no alias:
they mostly run `git` and `gh` actions. Their facts come from `gu-ctx`, `gu-pr`
and `gu-threads`.

## Examples

```bash
gu-status
```

```bash
gu-ctx rock
```

```bash
gu-pr-status
```

```bash
gu-pr 12
```

```bash
gu-ci 12
```

```bash
gu-lock pyxis --reason "tapeout freeze"
```

## Notes

- Commands that ask GitHub (`prs`, `pr`, `ci`, `threads`, and the PR columns of
  `branches` and `worktree`) need `gh` signed in. `gu-auth` explains what's wrong
  when they fail.
- Inside Claude Code's sandbox, `gh` needs
  `sandbox.enableWeakerNetworkIsolation` (set in `claude/settings.json`), and
  writes to other repos' `.git` are blocked. `gu` then prints the exact
  command for you to run with `!`.
- Aliases load in interactive shells only. From scripts, call `gu <command>`.
