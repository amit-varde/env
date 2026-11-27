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
