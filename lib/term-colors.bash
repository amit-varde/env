#!/usr/bin/env bash
# =============================================================================
# File:        lib/term-colors.bash
# =============================================================================
#
# DESCRIPTION:
#   Provides ANSI color code definitions for consistent terminal output across
#   all BU framework utilities. Exports color variables for regular colors,
#   bright/bold variants, background colors, text styles, and semantic aliases
#   used throughout the framework for info, warning, error, and success messages.
#
# FUNCTIONS:
#   (none - this file only exports color variables)
#
# EXPORTED VARIABLES:
#   Regular Colors:
#     BLACK, RED, GREEN, YELLOW, BLUE, MAGENTA, CYAN, WHITE
#
#   Bright (Bold) Colors:
#     BBLACK, BRED, BGREEN, BYELLOW, BBLUE, BMAGENTA, BCYAN, BWHITE
#
#   Background Colors:
#     ON_BLACK, ON_RED, ON_GREEN, ON_YELLOW, ON_BLUE, ON_MAGENTA, ON_CYAN, ON_WHITE
#
#   Text Styles:
#     BOLD, DIM, UNDERLINE, BLINK, REVERSED
#
#   Reset:
#     RESET - Resets all formatting to terminal defaults
#
#   Semantic Aliases:
#     INFO_COLOR, WARN_COLOR, ERR_COLOR, DEBUG_COLOR, SUCCESS_COLOR
#     COLOR_HEADER, COLOR_ORG, COLOR_REPO, COLOR_PATH, COLOR_BRANCH
#     COLOR_MAIN, COLOR_FEATURE, COLOR_MISSING, COLOR_SEPARATOR, COLOR_RESET
#
# USAGE:
#   # Source this file to access color variables
#   source "$BU/lib/term-colors.bash"
#
#   # Use in echo/printf statements
#   echo -e "${GREEN}Success!${RESET}"
#   echo -e "${BRED}Critical Error${RESET}"
#   printf "${CYAN}%-20s${RESET} %s\n" "Label" "Value"
#
# EXAMPLES:
#   # Display a warning message
#   echo -e "${WARN_COLOR}Warning: File not found${RESET}"
#
#   # Display formatted header
#   echo -e "${COLOR_HEADER}=== Repository Status ===${RESET}"
#
#   # Use in function output
#   echo -e "${SUCCESS_COLOR}✓${RESET} Task completed"
#
# =============================================================================

# Regular colors
export BLACK=$'\033[0;30m'
export RED=$'\033[0;31m'
export GREEN=$'\033[0;32m'
export YELLOW=$'\033[0;33m'
export BLUE=$'\033[0;34m'
export MAGENTA=$'\033[0;35m'
export CYAN=$'\033[0;36m'
export WHITE=$'\033[0;37m'

# Bright (bold) colors
export BBLACK=$'\033[1;30m'
export BRED=$'\033[1;31m'
export BGREEN=$'\033[1;32m'
export BYELLOW=$'\033[1;33m'
export BBLUE=$'\033[1;34m'
export BMAGENTA=$'\033[1;35m'
export BCYAN=$'\033[1;36m'
export BWHITE=$'\033[1;37m'

# Background colors
export ON_BLACK=$'\033[40m'
export ON_RED=$'\033[41m'
export ON_GREEN=$'\033[42m'
export ON_YELLOW=$'\033[43m'
export ON_BLUE=$'\033[44m'
export ON_MAGENTA=$'\033[45m'
export ON_CYAN=$'\033[46m'
export ON_WHITE=$'\033[47m'

# Text styles
export BOLD=$'\033[1m'
export DIM=$'\033[2m'
export UNDERLINE=$'\033[4m'
export BLINK=$'\033[5m'
export REVERSED=$'\033[7m'

# Reset
export RESET=$'\033[0m'

# Semantic color aliases
export INFO_COLOR="$CYAN"
export WARN_COLOR="$YELLOW"
export ERR_COLOR="$RED"
export DEBUG_COLOR="$MAGENTA"
export SUCCESS_COLOR="$GREEN"

# Extended aliases for scripts that need consistent palette
export COLOR_HEADER="$BCYAN"
export COLOR_ORG="$MAGENTA"
export COLOR_REPO="$GREEN"
export COLOR_PATH="$YELLOW"
export COLOR_BRANCH="$BYELLOW"
export COLOR_MAIN="$BGREEN"
export COLOR_FEATURE="$CYAN"
export COLOR_MISSING="$BRED"
export COLOR_SEPARATOR="$WHITE"
export COLOR_RESET="$RESET"
