#!/usr/bin/env bash
# =============================================================================
# File: lib/init-terminal.bash
# Description: Terminal and shell configuration
# =============================================================================
# This script configures terminal-specific shell options and behaviors.
#
# USAGE: source init-terminal.sh
#
# SETTINGS:
#   - unsetopt share_history: Disable shared history between shell sessions
#     Each shell session maintains its own independent history.
#
# =============================================================================

# Disable shared history between shell sessions (zsh only)
if [[ -n "${ZSH_VERSION:-}" ]]; then
    unsetopt share_history
fi

# Change the shell prompt to show project name
change_prompt() {
    local prompt_prefix=${PROJECT_NAME:-"NONE"}
    export PROMPT="($prompt_prefix) %~> "
    return 0
}
