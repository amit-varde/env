# Customize

[← README](../README.md)

## Change these first

| What | Where | Why |
|---|---|---|
| Clone source | `ENV_REPO` in `env.conf` **and** in `bootstrap.sh` | Repo `setup-env.sh` clones and updates from. Two places because `bootstrap.sh` runs before any clone exists and so cannot read `env.conf`; `tests/check-helper-drift.sh` fails the build if they disagree. To make the whole repo yours, fork it ([Forks](fork.md)) |
| Claude settings | `claude/settings.json` | User settings linked by `setup-env.sh` or a `~/.claude` → `claude/` symlink. Code Mode is **on** by default (`env.CLAUDE_CODE_EXPERIMENTAL_CODE_MODE: "1"`). Full detail: [Claude Code](claude-code.md). |

## Where to change what

| To change | Edit | Notes |
|---|---|---|
| Machine paths | `.env.host` | Not in git; or export `WORK`/`DL`/`DOCS` before sourcing |
| Editor for workspaces (macOS) | `EDITOR_APP` in `.env.host` | Default `Cursor.app` (opened via `cursor-ide`); e.g. `export EDITOR_APP="Visual Studio Code.app"`. Used by `fu-open` and `go-<project>` |
| Cursor settings | `cursor/settings.json`, `cursor/extensions.txt` | Applied by `cursor-sync apply`; see [Cursor](cursor.md) |
| Claude working preferences | `claude/CLAUDE.md.example` | `setup-env.sh` offers to copy it to `~/.claude/CLAUDE.md` only when you have none (default no). Edit your copy; keep company names and credentials out of it |
| Code Mode opt-out (one machine) | `claude/settings.local.json` | Copy from `claude/settings.local.json.example`; git-ignored. See [Claude Code](claude-code.md#turn-code-mode-off) |
| vim, git identity | `dotfiles/vimrc`, `dotfiles/gitconfig.template` | `setup-env.sh --only dotfiles` links `~/.vimrc` and creates `~/.gitconfig` from the template, each only when you have none. The template shows per-employer `includeIf` identities |
| Secret-scan terms | `.blocklist.local` (git-ignored; start from `blocklist.example`) | One regex per line (employer, project or personal terms); `env-scan` flags any file that matches |
| Aliases | `alias` | Loaded last, can use everything else |
| Shell setup | add `lib/init-<name>.bash` | Picked up automatically |
| Commands | add a script to `bin/` | `chmod +x`; on `PATH` in new shells |
| SSH hosts | `ssh/config.d/<host>.conf` + an `Include` line in `ssh/config` | Personal user/key go in `ssh/config.d/local.conf` (git-ignored) |
| Claude skills | `claude/skills/<name>/SKILL.md` | Appears as `/<name>` |

When you add or rename any of these, update the matching page in `docs/` and
the index in `README.md`.
