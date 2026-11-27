# env

A portable shell environment for macOS and Linux (bash or zsh): command-line
tools, aliases, shell setup modules, a shared SSH config and Claude Code skills,
loaded into every shell from one file.

It is also built to be published safely. This repo is public, so everything in
it is account- and employer-neutral: no secrets, no company names, no internal
hostnames. The machinery that keeps it that way — scrubbing exports, an
encrypted path for host config, and a scan that runs as a pre-commit hook and
in CI — is part of the repo, not an afterthought. See [Privacy](docs/privacy.md).

Fork or clone it, then make it yours.

## Quick start

Download `bootstrap.sh` to the machine and run it. It is one standalone file and
does not need the repo to exist yet. It asks where your work directory is
(default `~/work`), offers to fork this repo into your GitHub account
([Forks](docs/fork.md)), fetches it, and sets everything up, asking before each
change:

```bash
curl -fsSL https://raw.githubusercontent.com/amit-varde/env/main/bootstrap.sh -o bootstrap.sh
bash bootstrap.sh
```

Already cloned? Run `./setup-env.sh`. Check a machine any time with `env-doctor`.
Install dev tools with `env-install` (interactive) or see [Tools](docs/setup.md#tools).

Before your first commit, copy `blocklist.example` to `.blocklist.local` and add
your own employer, project and host names. That file is git-ignored and is what
the scan checks your commits against.

## The two halves

**Set up a machine** — `bootstrap.sh` → `setup-env.sh` → `env-doctor`.
`setup-env.sh` is the only installer: shell wiring, the pre-commit hook, host
paths, dotfiles, SSH (including decrypting published host config and linking
`~/.ssh/perms.sh`), Claude Code settings and skills, Cursor, dev tools and
Desktop shortcuts. Every step asks first, backs up what it replaces, and is
recorded in `~/.setup-env.log`. Re-running is safe and is how you add a tool
later. `scripts/install.sh` and `tools/install_all.sh` are thin shims kept for
older notes.

**Publish a change safely** — export, review, scan, commit.

```bash
./scripts/export-claude.sh      # scrubbed copy of ~/.claude in _review/
./scripts/export-dotfiles.sh    # scrubbed copies of your rc files in _review/
# read _review/, move keepers into claude/ and dotfiles/
env-scan                        # or ./scripts/scan.sh - must report clean
```

Nothing moves from `_review/` into the repo on its own: you read it and decide.
[Privacy](docs/privacy.md) covers the whole flow, including keys and encrypted
host config.

## Docs

| Topic | What's in it |
|---|---|
| [Setup](docs/setup.md) | `bootstrap.sh` and `setup-env.sh` steps and options, supported platforms, tools, `env-doctor`, and how `env.sh` loads everything |
| [Privacy](docs/privacy.md) | What must never be committed and what enforces it: the scan, the pre-commit hook, CI, the export scrubbers, encrypted host config and SSH keys |
| [Commands](docs/commands.md) | The tools in `bin/` |
| [Shell functions and aliases](docs/shell.md) | `env-install`, `pydev-install`, `go_project`, logging helpers, init modules, every alias |
| [SSH](docs/ssh.md) | Shared `ssh/config`, per-machine overrides, encrypted host files, keys, `/env-ssh` |
| [Cursor](docs/cursor.md) | `cursor-ide` (open in IDE mode) and `cursor-sync` (shared settings) |
| [Claude Code](docs/claude-code.md) | Shared `claude/settings.json`, Code Mode default, local opt-out, permissions, sandbox, and `env-doctor` checks |
| [Claude Code skills](docs/claude-skills.md) | The `/commands` in `claude/skills/`, grouped: repo health across `$WORK`, branches and worktrees, changes and pull requests, GitHub project work, access and machine setup |
| [gu](docs/gu.md) | The command half of the `/gu-*` skills, git utils (like `bu` and `fu`), and its `gu-<command>` / `gu-<skill>` aliases |
| [Forks](docs/fork.md) | Fork the repo from `bootstrap.sh`, and `/gu-fork-sync` to pull the original's changes into your fork or send yours back, always through PRs |
| [Worktree flow](docs/worktree-flow.md) | Create a worktree, work in it, PR, merge and clean up; for Claude Code, Cursor and VS Code users |
| [Customize](docs/customize.md) | Which file to edit to make it yours, and what to change first |

## Layout

| Path | Contents |
|---|---|
| `env.sh` | The one file your shell sources |
| `env.conf` | Where the repo lives (`ENV_REPO`, `ENV_BRANCH`, `ENV_UPSTREAM`): the one place to change when you fork |
| `bootstrap.sh` | Entry point: asks for `WORK`, fetches the repo, runs `setup-env.sh` |
| `setup-env.sh` | The installer: pre-commit hook, shell rc, SSH, Claude Code, Cursor, dotfiles, tools and shortcuts |
| `tools/` | `install.sh` orchestrator + `install_<name>.sh` per tool (macOS and Linux); shell: `env-install`, `pydev-install` |
| `tests/` | Standalone bash scripts, each in a throwaway `HOME` and `WORK` with no network. `check-helper-drift.sh` keeps `bootstrap.sh` honest; the rest cover the tool manifest, `gu worktree`, `gu fork`, the bootstrap prompts and the Cursor shortcut ([CI](docs/setup.md#ci)) |
| `bin/` | Commands, on `PATH` |
| `lib/` | Shell modules (`init-*.bash` load automatically) and shared libraries: `common.bash`, `scan-patterns.bash` |
| `alias` | Aliases and small functions |
| `scripts/` | The publishing side: `export-*` scrubbers, `install-ssh-keys.sh`, `scan.sh` |
| `ssh/` | Shared SSH config installed into `~/.ssh`: `config` (an explicit index) and `config.d/` (one file per host, plaintext git-ignored, `*.conf.gpg` published) |
| `.ssh/` | Repo-side SSH material: `keys/*.pub` published on purpose, and `perms.sh` |
| `dotfiles/` | `zshrc`, `bashrc`, `cshrc`, `vimrc` and `gitconfig.template` |
| `cursor/` | Shared Cursor settings and extension list (`cursor-sync` applies them) |
| `claude/` | Claude Code user settings, Code Mode default, and skills (`~/.claude` links here; see [Claude Code](docs/claude-code.md)) |
| `docs/` | These docs |
| `blocklist.example` | Template for the git-ignored `.blocklist.local`: your own terms the scan must flag |

## Privacy rules baked in

- Private keys are not stored in this repo. `scripts/install-ssh-keys.sh` reads them from 1Password and writes `~/.ssh/id_<type>`, matching by fingerprint and refusing a mismatch. The scan fails on key headers.
- Host-specific SSH config is edited in `ssh/config.d/` and published only as `*.conf.gpg`. Plaintext `*.conf` is git-ignored. `~/.ssh/config.d` is a symlink to `ssh/config.d/`, so host entries have one copy.
- Prefer a fresh key per employer/account (`ssh-keygen -t ed25519 -C ""`): one public key reused everywhere lets anyone correlate your accounts.
- Credentials belong in a secrets manager or the OS keychain, not in rc files or `settings.json` `env`.
- Never copy: `~/.claude.json`, `.credentials*`, `projects/`, `history`, `todos/`, `shell-snapshots/`, `statsig/`, MCP configs containing tokens.
- Machine- and employer-specific shell settings go in `~/.zshrc.local`, `~/.bashrc.local` or `~/.cshrc.local`, which the committed rc files source and which are never committed.
- Per-employer git identity: use `[includeIf "gitdir:~/work/<employer>/"] path = ~/.gitconfig-<employer>` instead of one global email.
