#!/usr/bin/env bash
# =============================================================================
# File: lib/init-paths.bash
# Description: Initialize system PATH and MANPATH
# =============================================================================
# This script sets up common path directories including local bin, man pages,
# and user-specific executables.
#
# USAGE: sourced by env.sh (needs its path_prepend)
#
# DIRECTORIES ADDED:
#   - $HOME/.local/bin    User local executables
#   - /usr/local/man      Local man pages
#
# =============================================================================

path_prepend PATH "$HOME/.local/bin"

# /usr/local/man first. Keep a trailing ':' (= "then the system man pages")
# when MANPATH was empty, and add the dir only once.
case ":${MANPATH:-}:" in
    *":/usr/local/man:"*) ;;
    *) export MANPATH="/usr/local/man:${MANPATH:-}" ;;
esac
