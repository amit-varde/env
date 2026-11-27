# Setup

[← README](../README.md)

## Install

Download `bootstrap.sh` to the machine and run it. It is a single standalone file:
it does not need the repo to exist yet.

```bash
curl -fsSL https://raw.githubusercontent.com/amit-varde/env/main/bootstrap.sh -o bootstrap.sh
bash bootstrap.sh
```

If you forked it to a private repo, a plain `curl` will not work there; use `gh`
(or the Raw / Download button on GitHub) instead:

```bash
gh api repos/<owner>/env/contents/bootstrap.sh \
  -H 'Accept: application/vnd.github.raw' > bootstrap.sh
```

It asks, in order (Enter accepts the `[default]`):

1. **Work directory (`WORK`)**, default `~/work`. Use any path you like: `~` is
   expanded, spaces are fine, and it is created after you confirm. A path that is
   a file is refused.
2. **Where the repo lives**, default `<WORK>/env`. An existing clone is reused; a
   non-empty folder that is not a clone is never touched.
3. **GitHub repo and branch**, default `amit-varde/env` and `main`.
4. A summary and `Proceed? [Y/n]`. Answering `n` changes nothing.
5. After GitHub login: **fork it into your own GitHub repo?** Default yes, unless
   you own the repo; then the fork's owner and name. A fork gets the original as
   its `upstream` remote, with pushing to it disabled ([Forks](fork.md)).

Then it checks `git`, `curl`, `sqlite3` and `gh` (offering to install what is
missing), gets GitHub access, clones the repo and runs `setup-env.sh` with your
answers, so `WORK` is not asked twice. Access order: an existing `gh` login, then
`gh auth login`, then a token (`GITHUB_TOKEN`, or pasted when asked; used for that
one clone and never written to disk), then an anonymous clone for a public repo.
Without `git` it falls back to a tarball download.

| `bootstrap.sh` option | Effect |
|---|---|
| `-y`, `--yes` | Accept every default; ask nothing |
| `--work PATH`, `--dir PATH` | Answer questions 1 and 2 on the command line |
| `--repo OWNER/NAME`, `--branch NAME` | Use a fork or another branch |
| `--fork`, `--no-fork`, `--fork-org ORG`, `--fork-name NAME` | Fork into your account (or an organization) without asking, or clone the original. `-y` alone never forks ([Forks](fork.md)) |
| `-- ARGS...` | Pass the rest to `setup-env.sh`, e.g. `-- --skip tools` |
| `ENV_REPO_URL` | A full git URL or path instead of `github.com/<ENV_REPO>` (a mirror, or for testing) |

Already have a clone? Run `./setup-env.sh` (or `./bootstrap.sh`) from inside it.
`setup-env.sh` loads `lib/common.bash` and will not run as a lone downloaded file.

`setup-env.sh` asks before each step, backs up anything it replaces
(`<file>.bak-<timestamp>`), and is safe to re-run.

| Option | Effect |
|---|---|
| `-y`, `--yes` | Accept every default without prompting |
| `-w`, `--work PATH` | Work directory; skips the `WORK` question. The repo defaults to `<work>/env` |
| `-d`, `--dir PATH` | Where the repo lives |
| `--only LIST`, `--skip LIST` | Run only, or leave out, these comma-separated steps |
| `--tools LIST` | Dev tools to install or re-run, e.g. `--tools gh,pyenv` (names: `tools/install.sh --list`) |
| `--authorize-keys` | In the `ssh` step, append `.ssh/keys/*.pub` to `~/.ssh/authorized_keys`. Off by default: it grants login to whoever holds the matching private keys |
| `--list-steps` | Print the step names |
| `ENV_REPO`, `ENV_BRANCH`, `ENV_DIR` | Environment overrides for the repo, branch and location. The committed defaults live in `env.conf` |
| `SSH_CONFIG_PASS_FILE` | File holding the gpg passphrase for `ssh/config.d/*.conf.gpg`, for runs with no terminal ([Privacy](privacy.md#ssh-host-config)) |

| Step (`--only` name) | What it does |
|---|---|
| Prerequisites (`prereqs`) | Checks `git`, `curl`, `gh`, `sqlite3`; offers to install them (brew / apt / dnf / yum / pacman; `gh` from its release tarball on Linux) |
| Repo (`repo`) | Clones via `gh` (logs in if needed), or pulls an existing clone. In a clone of a fork it adds the original as the `upstream` remote, with pushing disabled |
| Pre-commit scan (`hooks`) | Installs a git pre-commit hook that runs `env-scan --staged`, so a commit carrying a secret, an absolute home path or a term from `.blocklist.local` is refused ([Privacy](privacy.md#the-two-gates)) |
| `.env.host` (`host`) | Creates per-machine paths (`WORK`, `DL`, `DOCS`, `EDITOR_APP`) |
| Dotfiles (`dotfiles`) | Installs the portable `~/.zshrc`, `~/.bashrc` and `~/.cshrc` as copies, never links, since the next step appends to `~/.zshrc`. Each sources its own `~/.<name>.local` last, which is where employer and machine settings go and is never committed. An existing file that differs is only replaced if you say so, and is backed up first. Also optional (default no): links `~/.vimrc` and creates `~/.gitconfig` from the template, each only when you have none |
| Shell (`shell`) | Adds `source <repo>/env.sh` to `~/.zshrc`, `~/.bashrc` or `~/.bash_profile`. Runs after `dotfiles` for that reason |
| SSH (`ssh`) | Links `~/.ssh/config` to `ssh/config` and `~/.ssh/config.d` to `ssh/config.d`; writes your user/key to `ssh/config.d/local.conf` (git-ignored); links `~/.ssh/perms.sh`; decrypts each published `ssh/config.d/*.conf.gpg` to its git-ignored plaintext, and warns when `ssh/config` has no `Include` line for the result. With `--authorize-keys`, also appends `.ssh/keys/*.pub` to `~/.ssh/authorized_keys` ([Privacy](privacy.md#ssh-host-config)) |
| Claude Code (`claude`) | Links `claude/settings.json` and `claude/skills/*` into `~/.claude` (or uses a `~/.claude` → `claude/` symlink). Shared settings enable [Code Mode](claude-code.md) in terminal `claude` by default |
| Cursor (`cursor`) | Runs `cursor-sync apply` (settings link, extensions) and warns if Cursor will start in Agents mode ([details](cursor.md)) |
| Tools (`tools`) | Pick tools from a numbered menu (each shows installed + version, or missing), or pass `--tools`. Nothing is installed unless you choose it ([details](#tools)) |
| Desktop shortcuts (`shortcuts`) | Optional (default no): runs `create-work-shortcuts` ([details](#desktop-shortcuts)) |
| Health report (`doctor`) | Runs `env-doctor` |

### Re-running, the change log and the tool manifest

`setup-env.sh` is safe to re-run at any time. Each step changes only what is missing,
so to add a tool you skipped the first time, run it again and pick it in the tools
step (or `./setup-env.sh --only tools --tools <name>`).

Two files in your home directory record what happened:

- **`~/.setup-env.log`**: one dated line per change (`INSTALLED gh version=…`, `LINK …`,
  `BACKUP …`, `SHELL …`, `REPO cloned …`, start and end of each run). Use it to see
  which tools were installed when.
- **`~/.setup-env.manifest`**: one line per dev tool, `<tool>:<version>:<Y|N>`
  (`Y` = installed). It is rewritten at the end of every run.

`bin/env-toolcheck.sh` compares the manifest with the machine and marks `DRIFT` where
they disagree (a tool recorded as installed that is gone, or the reverse). Exit 1 on
drift. `env-toolcheck.sh --reset` rebuilds the manifest from a fresh check of every
tool, so the manifest matches the machine.

Choosing a tool that is already installed runs its installer, which leaves a present
tool alone. A real reinstall is not offered yet.

## Checking a machine

`env-doctor` is a read-only report: the shell line and `PATH`, `.env.host` and
`WORK`, the fork's `upstream` remote and how far behind it is (from the last fetch), prerequisites, `~/.claude` settings and skills (each `SKILL.md` needs a
`name` and `description`), [Claude Code](claude-code.md) Code Mode flag and `claude` CLI version, the `~/.ssh` links and permissions, Cursor settings and
IDE mode, Desktop shortcuts, and which dev tools are installed. Each `warn` or
`FAIL` line says how to fix it. It exits 1 only when something is broken (`-q`
prints just the problems).

## CI

`.github/workflows/ci.yml` runs on every push to `main` and every pull request,
in three jobs.

**scan** (Ubuntu) runs `bin/env-scan` over the whole tree. Because this repo is
public, this is the job that matters most: it is what still catches a secret or
an internal name committed with `git commit --no-verify`. Your own blocklist
terms are git-ignored and so invisible to CI unless you add them as a repository
secret named `ENV_BLOCKLIST`; the job says so when it is missing. See
[Privacy](privacy.md#your-own-terms).

**lint** (Ubuntu) parses every shell file with `bash -n`, then runs `shellcheck
--severity=error` over `bin/`, `lib/`, `tools/`, `scripts/`, `tests/`, the `gu`
command kit, `setup-env.sh`, `bootstrap.sh` and `env.sh`. It is pinned at
`error` on purpose: the tree still carries older style warnings, and a gate that
is red from the start gets ignored. Raising it to `warning` means triaging those
first.

**test** (Ubuntu and macOS, both to completion even if one fails) runs:

- `tests/check-helper-drift.sh` — the helpers `bootstrap.sh` carries must match
  `lib/common.bash`, and its built-in `ENV_REPO` must match `env.conf`
- `tests/test-setup-env-tools.sh` — the tool manifest, the change log,
  `env-toolcheck.sh` and `--tools`, in a throwaway `HOME`
- `tests/test-alias.sh` — every function the `alias` file defines is cleared of
  any same-named alias first, and the whole file still loads under `zsh` and
  `bash` when those names are already aliased. zsh expands aliases at *parse*
  time, so without that an alias you already have turns a function definition
  into a parse error that aborts the rest of the file and silently costs you
  every alias below it
- `tests/test-gu-worktree.sh` — `gu worktree` add/list/remove/prune and the lock
  hook in linked worktrees, against a throwaway repo
- `tests/test-gu-fork.sh` — `gu fork` wire, status, pull, land, send and take
  against a throwaway original and fork
- `tests/test-bootstrap.sh` — `bootstrap.sh`'s prompts through a pseudo-terminal
  against a local bare repo and a fake `gh` (needs `expect`)
- `tests/test-create-cursor-shortcut.sh` — macOS only
- `./setup-env.sh -y --skip repo,tools` twice into a temporary `HOME` whose path
  contains a space, then `env-doctor`. Twice, because the second run must be a
  no-op rather than a second set of changes. `repo` is skipped because the
  checkout already is the repo, and `tools` because it would install Homebrew
  and friends onto the runner
- a check that the pre-commit hook still refuses a commit carrying a fake AWS
  key or a blocklisted term, in a throwaway repo, so a change that quietly
  disables the hook fails the build

Every test builds its own `HOME`, `WORK` and git repos under its own temporary
directory and puts fakes for `gh`, `ssh` and `curl` on `PATH`. Nothing outside
that directory is touched and nothing reaches the network. They also pin `BU` to
the checkout under test: `env.sh` exports `BU` into every configured shell, so
without that a developer running the tests from their own shell would silently
test a different checkout.

## Supported platforms

| Platform | Status | Notes |
|---|---|---|
| macOS (Apple silicon or Intel), zsh or bash | Supported | Developed here (macOS 26, zsh). `/bin/bash` is 3.2, so scripts avoid bash 4 features |
| Ubuntu / Debian (`apt`) | Supported | Checked in CI |
| RHEL, Rocky, Alma, Fedora (`dnf`/`yum`) | Supported | Checked on RHEL 8.9 (bash 4.4). `gh` has no default package there: the installer uses the official release tarball in `~/.local` |
| Arch (`pacman`) | Best effort | Package install only; not checked |
| tcsh / csh login shells | Not supported | `env.sh` needs bash or zsh. Hosts that have tcsh installed still use bash as the login shell; if yours does not, run `bash` first or set bash as the login shell |

Linux hosts often have no `sudo`. The installers print what is missing and use
user-space installs (under `~/.local`, `~/.nvm`, `~/.pyenv`) where they can,
instead of failing.

## How it loads

`env.sh` is the only file your shell sources. In order:

| # | Loads | Purpose |
|---|---|---|
| 1 | `$BU` | Set to the repo path; used by every script |
| 2 | `bin/` | Added to `PATH` (via `path_prepend`, so re-sourcing never duplicates it) |
| 3 | `lib/common.bash` | Shared functions (`info`, `warn`, `editor_open`, ...) and color variables from `lib/term-colors.bash` |
| 4 | `.env.host` | Per-machine paths (not in git) |
| 5 | `lib/init-*.bash` | Every module, picked up automatically |
| 6 | `alias` | Aliases and small functions |

## Tools

`tools/` holds dev-tool installers adapted from
[env-kit](https://github.com/amit-varde/env-kit), for macOS and Linux.

| Path | Role |
|---|---|
| `tools/install.sh` | Orchestrator: list, pick tools, or install the full stack (interactive by default) |
| `tools/install_<name>.sh` | One installer per tool (safe to re-run; skips if already present) |
| `tools/install_pydev.sh` | Separate flow: pyenv via pyenv.run, then a default Python (`PYDEV_PYTHON`) |
| `tools/lib.sh` | Shared helpers and `INSTALL_ORDER` (dependency order) |
| `tools/detect.sh` | `tool_present`, `tool_version` and `manifest_write` (the `~/.setup-env.manifest` file; see [Re-running](#re-running-the-change-log-and-the-tool-manifest)) |

Nothing install-related lives in `bin/`. After `env.sh` loads, `env-install` and
`pydev-install` in `alias` forward to `install.sh` and `install_pydev.sh`. In
scripts, call `"$BU/tools/install.sh"` directly.

### `tools/install.sh`

Run `tools/install.sh -h` for the full header. Summary:

| Flag | Action |
|---|---|
| *(no args)* | Print the tool table, then prompt: full stack, name tools, or quit |
| `--list` | Table only (tool, platform, present / missing) |
| `--all` | Every tool in `INSTALL_ORDER` |
| `--tool NAME` | One or more tools (repeat the flag; runs in dependency order, not argv order) |
| `--dry-run` | Show what each `install_<name>.sh` would do |
| `-y`, `--yes` | Skip confirmation (used by `setup-env.sh` after its own prompt) |

Shell shortcut `env-install` maps legacy spellings: `env-install all` → `--all`;
`env-install gh python` → `--tool gh --tool python`; bare `env-install` →
interactive. Flags such as `--list` and `--dry-run` pass through unchanged.

```bash
tools/install.sh                           # interactive
tools/install.sh --list
tools/install.sh --dry-run --all
tools/install.sh --tool oh_my_zsh --tool gh
env-install                                # same as plain install.sh
env-install all
env-install --list
env-install gh pyenv python
```

Real installs ask for confirmation unless you pass `-y` or use `--dry-run`.

### `pydev-install`

`pydev-install` (function → `tools/install_pydev.sh`) is for a one-shot pyenv
setup with curl-to-bash confirmation. Prefer `env-install --tool pyenv --tool
python` when you want the same stack as the rest of the tools.

### Tool names (`INSTALL_ORDER`)

| Tool | macOS | Linux |
|---|---|---|
| `homebrew` | installs Homebrew | skipped |
| `sqlite3` | preinstalled | package manager (root) |
| `oh_my_zsh` | zsh if needed, then Oh My Zsh into `~/.oh-my-zsh` | same (does not edit `.zshrc` or change login shell) |
| `pyenv`, `python`, `pip`, `nvm` | home directory (`~/.pyenv`, `~/.nvm`); build libraries via brew | same; build libraries via the package manager if root is available, else a warning |
| `vim` | brew | package manager (root) |
| `gh` | brew | official release tarball in `~/.local/share/gh`, linked from `~/.local/bin` (no root) |
| `claude` | brew cask | Anthropic's installer script, under `~/.local` |
| `macvim`, `docker`, `iterm2`, `cursor`, `vscode` | brew casks | skipped; it prints where to get it |

Without root, a package that needs the package manager is not installed: the
installer prints the exact command to give an admin and moves on. Add a tool by
dropping in `tools/install_<name>.sh` and appending its name to `INSTALL_ORDER`
in `tools/lib.sh`.

## Desktop shortcuts

`create-work-shortcuts` (alias `wsc`) writes `<Desktop>/<name>.code-workspace` for each
directory directly under `$WORK`. Double-click one to open that directory in your
editor. The files hold absolute paths for this machine, so they are generated
locally and never committed.

```bash
create-work-shortcuts --list       # what exists, what would change
create-work-shortcuts              # create or refresh
create-work-shortcuts --exclude scratch --exclude archive
create-work-shortcuts --adopt      # also take over hand-made files of the same name
create-work-shortcuts --prune      # drop shortcuts whose directory is gone
```

- Each generated file starts with `// generated by create-work-shortcuts` (the
  old `// generated by work-shortcuts` line is still recognized). Only those
  files are updated or pruned; a hand-made file is reported and left alone
  unless you pass `--adopt`.
- Replaced and pruned files are moved to `Desktop/.work-shortcuts-bak/`, not
  deleted.
- On Linux the Desktop is `xdg-user-dir DESKTOP` (else `~/Desktop`). With no
  Desktop folder (a headless host), it does nothing.
- Shortcuts open in your default app for `.code-workspace` files. Opening them
  from the Dock or Finder does not go through `cursor-ide`; see
  [Cursor](cursor.md) for what that means for IDE mode.
