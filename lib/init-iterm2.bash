#!/usr/bin/env bash
# =============================================================================
# File: lib/init-iterm2.bash
# Description: Initialize iTerm2 shell integration
# =============================================================================
# This script enables iTerm2 shell integration if it is available on the
# system. This provides enhanced features like recent directories and
# command history integration with iTerm2.
#
# iTerm2 installs ~/.iterm2_shell_integration.<shell>. This loads the one
# matching the running shell, so a bash login never sources the zsh file.
#
# USAGE: source init-iterm2.sh
#
# PLATFORM: macOS with iTerm2
#
# =============================================================================

# Only load on macOS. `local` cannot be used at module scope when this file
# is sourced from top-level (vs. from within a function), so use a regular
# assignment scoped to a subshell-style block.
if [[ "$(uname -s)" == "Darwin" ]]; then
    # iTerm2 installs one integration file per shell. Sourcing the zsh one from
    # bash prints "setopt: command not found" at every single login, so pick the
    # file that matches the shell actually running and load nothing otherwise.
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        _bu_iterm2_integration="$HOME/.iterm2_shell_integration.zsh"
    elif [[ -n "${BASH_VERSION:-}" ]]; then
        _bu_iterm2_integration="$HOME/.iterm2_shell_integration.bash"
    else
        _bu_iterm2_integration=""
    fi
    if [[ -n "$_bu_iterm2_integration" ]] && [[ -e "$_bu_iterm2_integration" ]]; then
        source "$_bu_iterm2_integration"
    fi
    unset _bu_iterm2_integration
fi
