# Shell functions and aliases

[← README](../README.md)

## Functions and modules (`lib/`)

`env.sh` sources `lib/common.bash` first. Every `lib/init-*.bash` file then loads automatically.

While it loads, `env.sh` switches alias expansion off (`unsetopt aliases` in
zsh, `shopt -u expand_aliases` in bash) and restores it afterwards. Both shells
expand aliases at *parse* time, so an alias you already have whose name matches
one of the 64 functions this chain defines — `info`, `ok`, `step` and `backup`
among them — would otherwise turn that function's definition into a parse error
that silently discards the rest of the file. Your own aliases are left alone;
only expansion is paused, and only until the last line of `env.sh`.

| Function / variable | Module | Description |
|---|---|---|
| `go_project <name> [0\|1]` | `init-go-projects` | `cd` to `$WORK/<name>`, set `PROJECT_NAME`, update the prompt, open its workspace in your editor (`$EDITOR_APP`, default Cursor via `cursor-ide`; `0` = don't) |
| `go-<name>` | `init-project-aliases` | Generated alias per folder in `$WORK` for `go_project <name>` |
| `change_prompt <text>` | `init-terminal` | Set the prompt prefix |
| `info` `warn` `err` `debug` `success` `ok` `die` | `common` | Colored log helpers. `ok` is `success`. `die` prints with `err` and exits 1. `warn` shows at the default verbosity; `BU_VERBOSE_LEVEL` 2 adds `debug` |
| `show_help` `handle_help` `file_mode` `editor_open` | `common` | Help text for `bin/` and `tools/install.sh` (header comments), file modes, and opening a path in `$EDITOR_APP` |
| `path_prepend VAR DIR` | `env.sh` | Put `DIR` at the front of a colon list such as `PATH`, once |
| `EDITOR`, `LANG` | `init-editor` | Editor and locale defaults |
| — | `init-paths`, `init-pyenv`, `init-nvm`, `init-iterm2` | `PATH`/`MANPATH`, pyenv, nvm and iTerm2 integration if installed. The two that ship one file per shell are loaded per shell: iTerm2's `~/.iterm2_shell_integration.zsh` under zsh and `.bash` under bash, and nvm's `bash_completion` under bash only (`nvm.sh` itself loads in both). For nvm completion under zsh, run `autoload -U +X bashcompinit && bashcompinit` in `~/.zshrc.local` before `env.sh` and source the file yourself |

## Install helpers (`tools/` + `alias`)

Install entry points live in `tools/`, not `bin/`. Per-tool scripts are always
`install_<name>.sh`; the orchestrator is `install.sh` (see [Tools](setup.md#tools)).

After `env.sh` loads, these shell functions forward to the scripts:

| Function | Script | Description |
|---|---|---|
| `env-install` | `tools/install.sh` | Dev tools: interactive by default; or `--list`, `--all`, `--tool NAME` (also `all` and bare tool names) |
| `pydev-install` | `tools/install_pydev.sh` | pyenv (pyenv.run, with confirmation) plus default Python (`PYDEV_PYTHON`, default 3.11.8) |

`env-install` with no arguments runs `install.sh` interactively (table, then
prompt). With tool names it becomes `--tool` for each name; `all` becomes
`--all`. Pass through native flags when you use them:

```bash
env-install --list
env-install --dry-run --all
env-install --tool gh
```

In scripts, call `"$BU/tools/install.sh"` directly (functions are not available
in non-interactive shells). Use `-y` when the caller already confirmed.

## Aliases (`alias`)

| Alias | Does |
|---|---|
| `up` | `cd ..` |
| `wrk` | `cd $WORK` |
| `so` | Reload your shell rc file |
| `c`, `cls` / `x` | Clear screen / exit |
| `ll` / `la` / `l1` | `ls -lart` / `ls -a` / `ls -1` |
| `h` / `t` / `m` | `head -20` / `tail -20` / `more` |
| `o` | `fu-open` |
| `lock` / `unlock` / `mkexe` | `chmod -R 700` / `755` / `755` |
| `bckup <name> <files>` | Timestamped `tar.gz` of files |
| `chkpath` / `chkenv` | `env-check-path` / `env-check` |
| `check-path` / `check-env` | `env-check-path` / `env-check` |
| `env-check-ld-library-path` | `env-check-path --var LD_LIBRARY_PATH` |
| `fu-unix2dos` | `fu-dos2unix --to-dos` |
| `gu-update-all` | `gu-update --all` |
| `gu-<command>`, `gu-<skill>` | One alias per `gu` command (`gu-ws`, `gu-ctx`, `gu-prs`, `gu-pr`, `gu-ci`, `gu-threads`, `gu-branches`, `gu-lock`, `gu-unlock`, `gu-locks`, `gu-readme`, `gu-release`, `gu-auth`, `gu-worktree`) and per skill (`gu-status`, `gu-pr-status`, `gu-pr-review`, `gu-merge`, `gu-actions`, `gu-repo`). See [gu](gu.md) |
| `wt` | `gu worktree` (any subcommand: `wt list`, `wt add`, …). `wt list` groups worktrees by repo with PR and status. See [Worktree flow](worktree-flow.md) |
| `wt-list` | `gu worktree list --fetch --gh`: every worktree, with `merged` / `merged(#n)` notes |
| `wt-add` | `gu worktree add`: `wt-add <repo> <branch> [--name <name>]`, or `wt-add <repo> --pr <n>` |
| `wt-mv` | `gu worktree move`: `wt-mv <path> <new-name> [--branch]` |
| `wt-rm` | `gu worktree remove --delete-branch`: removes a clean worktree, and its branch only if merged |
| `wt-cleanup` | `gu worktree cleanup`: lists worktrees that are safe to delete (clean and merged, or folder already gone), then asks: remove all, select one by one, or none. `--apply` removes them all without asking; `-n` only lists |
| `wt-reset` | `gu worktree reset`: plan moving stray worktrees into `<repo>/.claude/worktrees`; add `--apply` to move (`--all` includes Cursor's). See [Worktree flow](worktree-flow.md#gather-stray-worktrees) |
| `cleanup` | Delete `.DS_Store` files below `.` |
| `clean-temp-files` | Delete `*~ *.swp *.bak *.tmp ...` in `.` |
| `pyclean` / `pipclean` / `brewclean` | Clear `__pycache__` / pip cache / Homebrew cache |
| `showfiles` / `hidefiles` | Show / hide hidden files in Finder (macOS) |
| `code`, `vscode`, `gh-desktop` | Open the app (macOS) |
| `cursor` | `cursor-ide`: open Cursor in IDE mode (see [Cursor](cursor.md)) |
| `wsc` | `create-work-shortcuts`: a Desktop workspace file per directory in `$WORK` |
| `pbps` | `pbpaste` |
| `env-install` | `tools/install.sh` (function; see [Install helpers](#install-helpers-tools--alias)) |
| `pydev-install` | `tools/install_pydev.sh` (function) |
