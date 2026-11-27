# Commands (`bin/`)

[← README](../README.md)

Everything in `bin/` is on `PATH`. Run any command with `-h` for usage: it prints
the script's header comment.

| Command | Description |
|---|---|
| `env-check` | Check that environment variables are set (alias `check-env`) |
| `env-check-path [--var NAME] [term]` | Show `PATH` (or any path variable) entries and flag duplicates (alias `check-path`) |
| `env-check-ld-library-path` | Same for `LD_LIBRARY_PATH` (alias: `env-check-path --var LD_LIBRARY_PATH`) |
| `fu-open` | Open a file with the right app for its extension |
| `fu-split-file` | Split a text file into chunks at line boundaries |
| `fu-dos2unix [--to-dos]` | Convert line endings, in place, for one or more files (alias `fu-unix2dos` = `--to-dos`) |
| `fname [file\|dir]` | Full path with symlinks resolved (`realpath`; same output without it). No argument = current dir |
| `run-cmd` | Run a command, logging its output to `$RUN_OUT` |
| `run-make` | `run-cmd make ...`, after checking for a Makefile |
| `run-py` | `run-cmd python ...`, after checking the script exists |
| `pydev` | Show Python environment info (pyenv, pip, venv) |
| `pypi-setup-project` | Create PyPI packaging files (`pyproject.toml`, `setup.py`) |
| `pypi-validate-project` | Check a project for PyPI compliance |
| `default-browser` | Switch the default browser (macOS: Chrome / Choosy) |
| `cursor-ide [--check\|--restart\|--no-fix\|--agent] [args]` | Open Cursor in IDE mode, fixing the saved mode first when needed. `--agent` switches to Agents mode instead (alias `cursor`; see [Cursor](cursor.md)) |
| `cursor-sync [status\|apply\|export]` | Link the repo's `cursor/` settings into Cursor's User folder and install its extensions (see [Cursor](cursor.md)) |
| `env-toolcheck.sh [--reset] [-q]` | Dev tools as recorded in `~/.setup-env.manifest` against the machine now; `DRIFT` lines where they differ (exit 1). `--reset` rebuilds the manifest from a fresh check. See [Setup](setup.md#re-running-the-change-log-and-the-tool-manifest) |
| `env-doctor [-q]` | Read-only health report: shell wiring, `PATH`, `.env.host`, prerequisites, Claude skills, [Code Mode](claude-code.md), SSH links, Cursor settings and IDE mode, Desktop shortcuts, tools. `warn`/`FAIL` lines say how to fix them; exit 1 only on `FAIL` (see [Setup](setup.md#checking-a-machine)) |
| `env-scan [--staged] [--skip CATEGORY]` | Scan what git would commit for secrets, key/token assignments, absolute home paths, email addresses and your own `.blocklist.local` terms. Prints file and line, never the matching text; exit 1 on findings. Use it before pushing or sharing the repo |
| `create-work-shortcuts [--list\|--dry-run\|--adopt\|--prune\|--exclude NAME]` | Write a `<name>.code-workspace` on the Desktop for each directory in `$WORK` (alias `wsc`; see [Desktop shortcuts](setup.md#desktop-shortcuts)) |
| `create-cursor-ide-shortcut [--dir PATH] [--name NAME] [-y]` | macOS: write `<Desktop>/<name>.app` that opens that workspace through `cursor-ide --yes`, so a double-click starts Cursor in IDE mode. No arguments: ask which directories under `$WORK`. An existing app is replaced (see [Cursor](cursor.md)) |
| `create-cursor-agent-shortcut [--dir PATH] [--name NAME] [-y]` | Same, for Agents mode: `<Desktop>/<name>-agent.app` runs `cursor-ide --agent --yes`. An existing app is replaced |
| `gu-update [-a] [-n] [-y] [repo...]` | Fetch and fast-forward the current repo (or the named ones, or all with `-a`); list what it left alone. The non-interactive side of `/gu-update` |
| `gu-update-all [-n] [-y]` | Alias for `gu-update --all`: every repo under `$WORK` |
| `gu` | git utils: the command-line half of the `gu-*` skills (`gu help`); a wrapper for `claude/skills/gu-common/bin/gu`. On a terminal its tables are aligned and colored (`NO_COLOR=1` or `GU_COLOR=never` turns that off); piped, it prints plain `\|` rows. `GU_STATUS=1` adds `git status` after the command. Aliases: `gu-<command>` and `gu-<skill>` (see [gu](gu.md)), and `wt` / `wt-*` for worktrees (see [Worktree flow](worktree-flow.md)) |

Dev-tool installers are **not** in `bin/`. They live under `tools/` (`install.sh`
and `install_<name>.sh`). After you source `env.sh`, use the shell functions
`env-install` and `pydev-install` (see [Shell](shell.md#install-helpers-tools--alias)
and [Tools](setup.md#tools)).

Names marked *alias* are defined in `alias`, so they work in your interactive
shell but not inside scripts; call the real command there. `bin/` holds no
symlinks.

To add one: put an executable script in `bin/` (`chmod +x`). It is on `PATH`
in every new shell. Start it like the others, so it gets the log helpers and
`-h` for free:

```bash
: "${BU:=$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)}"
source "$BU/lib/common.bash"   # log helpers, show_help, handle_help, file_mode
handle_help "$@"                   # -h/--help prints the header comment
```
