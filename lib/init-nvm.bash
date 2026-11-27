#!/usr/bin/env bash
# =============================================================================
# File: lib/init-nvm.bash
# Description: Initialize Node Version Manager (NVM)
# =============================================================================
# This script initializes NVM if it is installed on the system.
# It sources the main nvm.sh script and bash completion if available.
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

# Load NVM bash completion if it exists
if [[ -s "$NVM_DIR/bash_completion" ]]; then
    \. "$NVM_DIR/bash_completion"
fi
