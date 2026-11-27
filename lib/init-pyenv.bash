#!/usr/bin/env bash
# =============================================================================
# File: lib/init-pyenv.bash
# Description: Initialize Python version management with Pyenv
# =============================================================================
# This script initializes Pyenv and Pyenv-virtualenv if they are installed
# on the system. Sets up the necessary environment variables and evaluates
# the initialization hooks.
#
# USAGE: sourced by env.sh (needs its path_prepend)
#
# =============================================================================

export PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"
path_prepend PATH "$PYENV_ROOT/bin"

# Initialize pyenv if it exists
if command -v pyenv >/dev/null 2>&1; then
    eval "$(pyenv init -)"
fi

# Initialize pyenv-virtualenv if it exists
if command -v pyenv-virtualenv >/dev/null 2>&1; then
    eval "$(pyenv virtualenv-init -)"
fi
