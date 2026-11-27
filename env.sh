#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File: env/env.sh
# Description: Load this repo into the current shell
# -----------------------------------------------------------------------------
# Usage (add to ~/.zshrc or ~/.bashrc):
#   source ~/work/env/env.sh
#
# This sets up:
#   - $BU pointing to this directory (scripts in bin/ look for $BU/lib)
#   - $BU/bin on PATH
#   - lib/common.bash (log helpers and other shared functions)
#   - .env.host, lib/init-*.bash and alias, in that order
#
# Trimmed version of bu/bu.sh: no BU_ENV / .env.<env> support.
# -----------------------------------------------------------------------------

# Find this file's directory (bash and zsh)
if [[ -n "${BASH_SOURCE:-}" ]]; then
    _ENV_SCRIPT_PATH="${BASH_SOURCE[0]}"
elif [[ -n "${ZSH_VERSION:-}" ]]; then
    # zsh's own idiom for "the path of the file being sourced". bash cannot
    # parse it, but bash never gets here: BASH_SOURCE is set, so the branch
    # above wins. shellcheck reads this file as bash (per the shebang), so it
    # flags valid zsh. Disabled for this one line only, not file-wide.
    # shellcheck disable=SC2296
    _ENV_SCRIPT_PATH="${(%):-%N}"
else
    echo "ERROR: env.sh must be sourced from bash or zsh" >&2
    return 1 2>/dev/null || exit 1
fi
BU="$(cd "$(dirname "$_ENV_SCRIPT_PATH")" && pwd)"
export BU
unset _ENV_SCRIPT_PATH

# -----------------------------------------------------------------------------
# Turn alias expansion off for everything this file loads, then restore it.
#
# Both shells expand aliases at PARSE time -- zsh always, bash whenever
# expand_aliases is on, which it is in every interactive shell. So if you
# already have, say, `alias backup=...` or `alias info=...`, then the line
# `backup() {` in lib/common.bash is not a warning: it is a parse error that
# ABORTS THE REST OF THAT FILE, leaving a half-loaded lib/common.bash whose
# missing helpers break bin/ and setup-env.sh in ways that point nowhere near
# the real cause. The chain below defines 64 top-level function names, among
# them err, info, ok, die, have, ask, confirm, step and backup -- all of them
# plausible things for a shell to already alias.
#
# Switching expansion off is better than clearing those names with `unalias`:
# it protects the parse without destroying aliases you chose to have. Your
# aliases are untouched and work again as soon as the option is restored below.
#
# FAILURE MODE: if env.sh is edited into a parse error between here and the
# restore at the bottom, alias expansion stays off for that one shell until it
# is reloaded. CI parses this file with both `bash -n` and `zsh -n` to keep
# that window shut.
# -----------------------------------------------------------------------------
_bu_alias_opt=none
if [[ -n "${ZSH_VERSION:-}" ]]; then
    if [[ -o aliases ]]; then _bu_alias_opt=zsh; unsetopt aliases; fi
elif shopt -q expand_aliases 2>/dev/null; then
    _bu_alias_opt=bash; shopt -u expand_aliases
fi

# path_prepend VAR DIR - put DIR at the front of the colon list VAR, once.
# Used by lib/init-*.bash too, so re-sourcing (`so`) never grows a path.
path_prepend() {
    local cur
    eval "cur=\${$1:-}"
    case ":$cur:" in *":$2:"*) return 0 ;; esac
    eval "export $1=\"\$2\${cur:+:\$cur}\""
}

# Add bin/ to PATH once. lib/ holds sourceables only and stays off PATH.
path_prepend PATH "$BU/bin"

export BU_VERBOSE_LEVEL="${BU_VERBOSE_LEVEL:-0}"

# Shared functions, which load the colors. Not init-*, so list it here.
[[ -f "$BU/lib/common.bash" ]] && source "$BU/lib/common.bash"

# Host paths (WORK, DL, DOCS, iDrive) before anything that refers to them.
[[ -f "$BU/.env.host" ]] && source "$BU/.env.host"

# Shell modules: every lib/init-*.bash, picked up automatically.
for _env_module in "$BU/lib"/init-*.bash; do
    [[ -f "$_env_module" ]] && source "$_env_module"
done
unset _env_module

# Aliases last, so they can use everything above.
[[ -f "$BU/alias" ]] && source "$BU/alias"

# Restore alias expansion to exactly the state it was in on entry. Keep this
# last: everything above is inside the window opened near the top of this file.
case "$_bu_alias_opt" in
    zsh) setopt aliases ;;
    bash) shopt -s expand_aliases ;;
esac
unset _bu_alias_opt
