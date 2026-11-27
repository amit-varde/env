# gu-* skill kit

Eighteen Claude Code skills for GitHub and multi-repo work under `$WORK`, built as one kit:

- **Skills** (`../gu-*/SKILL.md`) hold the judgement: which question to ask, what to recommend, when to stop.
- **`gu`** (`bin/gu` + `cmd/*.sh` + `lib.sh`) holds the mechanics: gathering facts, classifying them, safety checks.
  It prints compact `|`-separated rows or `key: value` lines, so a skill makes one call instead of ten.
- **`CONVENTIONS.md`** holds the rules every skill shares (questions, safety, sandbox, handoffs), written once.

`gu` is also on your `PATH` (`env/bin/gu`), so you can run what the sandbox blocks: `! gu lock rock`.
In a shell, `gu-<command>` (`gu-ws`, `gu-pr 12`, ...) and `gu-<skill>` (`gu-status`, `gu-merge`, ...) are aliases
for it: see `docs/gu.md` in the env repo.
On a terminal, `gu` aligns its `|` tables and colors states (`pretty.awk`); piped or captured, as skills
run it, the output stays plain `|` rows. `GU_COLOR=always|never` or `NO_COLOR=1` overrides that.
`GU_STATUS=1` makes it end with `git status` for the repos it touched (off by default).

## Skills and the gu commands they use

| Skill | For | gu |
|---|---|---|
| /gu-status | status of all repos and submodules | `ws` |
| /gu-update, /gu-update-all | safely update this repo, named repos, or all (`--all`) | `ws --plan`, `update` |
| /gu-lock, /gu-unlock | freeze or unfreeze repos | `lock`, `unlock`, `locks` |
| /gu-push | commit and push to the right branch | `ctx`, `readme` |
| /gu-pr-create | open a PR (titled after its worktree) | `ctx`, `pr` |
| /gu-pr-status | PR and CI state, failure diagnosis | `prs`, `pr`, `threads`, `ci` |
| /gu-pr-feedback | address review comments, update, push | `pr`, `ctx`, `threads` |
| /gu-pr-review | review someone's PR | `prs review`, `pr` |
| /gu-merge | merge a PR or branch, then clean up its worktree | `prs repo`, `branches`, `pr`, `readme`, `ci`, `worktree` |
| /gu-actions | runs, logs, reruns, dispatch, YAML | `ctx`, `ci` |
| /gu-release | versions, notes, releases | `release`, `ci` |
| /gu-repo | clone, fork, branch cleanup, submodules | `ctx`, `branches` |
| /gu-worktree | add, list, rename, and clean up linked worktrees | `worktree`, `ctx` |
| /gu-fork-sync | pull the original into a fork, send commits back, take from forks (PRs) | `fork`, `worktree`, `readme`, `pr` |
| /gu-issues | find, file and triage issues | `ctx` |
| /gu-auth | fix gh/git authentication | `auth` |

`gu help` lists every command with its usage.

## Adding a command

1. Create `cmd/<name>.sh`. Its first line is `#: <usage> - <summary>` (shown by `gu help`); it defines `main()` and uses
   `lib.sh` helpers: `resolve_repo`, `ws_repos`, `submodules`, `branch`, `upstream`, `behind_ahead`, `default_branch`,
   `n_dirty`, `op_in_progress`, `lock_level`, `slug`, `fetch_all`, `ghq` (a gh call with classified errors), `protected`, `JQ_CI`, `kv`.
2. Print `|` rows and `key: value` lines; `pretty.awk` makes them readable on a terminal, so don't add color in
   the command. Keep it bash 3.2-safe: no here-docs or here-strings, and no `set -u` with arrays. It must be read-only unless it's an action command.
3. Reference it from the skill that needs it, and add it to the table above.
