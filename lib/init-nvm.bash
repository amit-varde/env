#!/usr/bin/env bash
# =============================================================================
# File: lib/init-nvm.bash
# Description: Initialize Node Version Manager (NVM)
# =============================================================================
# This script initializes NVM if it is installed on the system.
# It sources the main nvm.sh script in either shell, and nvm's bash-specific
# completion script only under bash.
#
# USAGE: source init-nvm.sh
#
# =============================================================================

if [[ -z "${NVM_DIR:-}" ]]; then
    export NVM_DIR="$HOME/.nvm"
fi

# Load NVM if it exists
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    \. "$NVM_DIR/nvm.sh"
fi

# Load NVM's completion if it exists -- under bash only.
#
# nvm ships a BASH completion script: it ends in a `complete` call, which zsh
# has no builtin for. Sourcing it from zsh prints "command not found: complete"
# at every login, or, where zsh autoloads its bash-compatibility function
# instead, the worse pair "compinit: initialization aborted" and "complete:13:
# command not found: compdef". nvm.sh itself supports zsh and still loads for
# both shells; it is only the completion file that is bash-specific.
#
# For completion under zsh, put this in ~/.zshrc.local BEFORE env.sh:
#   autoload -U +X bashcompinit && bashcompinit
# and source "$NVM_DIR/bash_completion" yourself.
if [[ -n "${BASH_VERSION:-}" ]] && [[ -s "$NVM_DIR/bash_completion" ]]; then
    \. "$NVM_DIR/bash_completion"
fi
