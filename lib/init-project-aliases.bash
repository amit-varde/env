#!/usr/bin/env bash
# =============================================================================
# File: lib/init-project-aliases.bash
# Description: Generate project aliases for directories in WORK
# =============================================================================
# This script generates dynamic shell aliases for all projects found in the
# $WORK directory. Each project directory gets an alias in the form:
#   go-<project_name>
#
# This allows quick navigation to and initialization of any project in WORK.
#
# USAGE: source init-project-aliases.sh
#
# ALIASES GENERATED:
#   go-<project_name>    Navigate to and set up <project_name>
#
# ENVIRONMENT VARIABLES:
#   $WORK    Directory containing project subdirectories (optional)
#
# =============================================================================

# Generate aliases for all projects in the WORK directory
gen_project_aliases() {
    # Process WORK directory if it exists
    local dir project_name
    if [[ -n "${WORK:-}" ]] && [[ -d "$WORK" ]]; then
        for dir in "$WORK"/*/; do
            [[ -d "$dir" ]] || continue
            project_name=$(basename "$dir")
            # Only names that are valid alias names (skips e.g. "it's", "a b")
            case "$project_name" in *[!A-Za-z0-9._+-]*) continue ;; esac
            # shellcheck disable=SC2139  # expanding the name now is the point: one alias per project
            alias "go-$project_name=go_project $project_name 1"
        done
    fi
}

# Generate project aliases on load
gen_project_aliases
