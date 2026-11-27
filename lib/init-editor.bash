#!/usr/bin/env bash
# =============================================================================
# File: lib/init-editor.bash
# Description: Initialize editor and locale settings
# =============================================================================
# This script configures the system locale and sets the preferred text editor
# based on the execution environment.
#
# USAGE: source init-editor.sh
#
# SETTINGS:
#   LANG          System locale (default: en_US.UTF-8)
#   EDITOR        Preferred text editor:
#                 - vim on SSH connections
#                 - mvim if available locally (macOS)
#                 - vim as fallback
#
# =============================================================================

# Set locale
export LANG="${LANG:-en_US.UTF-8}"

# Preferred editor: vim when on SSH, mvim locally when available, else vim
if [[ -n "${SSH_CONNECTION:-}" ]]; then
    export EDITOR="vim"
elif command -v mvim >/dev/null 2>&1; then
    export EDITOR="${EDITOR:-mvim}"
else
    export EDITOR="${EDITOR:-vim}"
fi
