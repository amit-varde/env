# shellcheck shell=bash
# =============================================================================
# File:        lib/scan-patterns.bash
# =============================================================================
#
# DESCRIPTION: The one home for the secret / PII patterns this repo scans for.
#   Sourced by bin/env-scan (the scanner behind scripts/scan.sh and the
#   pre-commit hook) and by scripts/lib.sh (the export scrubbers). Keep the
#   definitions here and nowhere else: a copy that drifts is a hole in the gate.
#
#   Deliberately has no dependencies - not even lib/common.bash - because
#   scripts/lib.sh is sourced by scripts that never load the shell library.
#   Not named init-*, so env.sh's module loop does not source it into shells.
#
# VARIABLES:
#   SECRET_RE         private-key blocks and well-known token formats
#   ASSIGN_STRICT_RE  key/token/secret assignment whose value contains a digit.
#                     For scanning the repo, where a false positive blocks a
#                     commit, so precision matters more than reach.
#   ASSIGN_RE         the same, without the digit requirement. For scrubbing
#                     your own rc files on export, where dropping one extra
#                     line is cheap and the reason is logged.
#   PATH_RE           absolute home paths, themselves treated as PII
#   PATH_OK_RE        placeholder home paths that are fine to publish
#   EMAIL_RE          email addresses
#   EMAIL_OK_RE       placeholder / machine addresses that are fine to publish
#
# FUNCTIONS:
#   blocklist_file DIR    print the blocklist path for repo DIR, or nothing
#   blocklist_pattern DIR print the terms as one alternation, or nothing
#
#   Both print nothing when DIR/.blocklist.local is absent, and the blocklist
#   check is then skipped. blocklist.example is a TEMPLATE, never a live
#   blocklist: its placeholder terms (/Users/yourname, your\.name@) are exactly
#   the strings PATH_OK_RE and EMAIL_OK_RE allow on purpose, so using it as a
#   blocklist would flag the documentation it is meant to illustrate.
#
#   Your real terms are per-machine and uncommittable by nature: a public repo
#   cannot carry the list of names it must not mention. So CI cannot check
#   them - the pre-commit hook on your machine is the gate for those, and CI
#   can only check them if you give it the list as a repository secret. See
#   docs/privacy.md.
#
# =============================================================================

SECRET_RE='(-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[abprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{30,}|eyJ[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{15,}\.)'

# A literal with a digit inside it; words and $VARS are not secrets.
ASSIGN_STRICT_RE='(key|token|secret|passw(or)?d|passwd|credential|auth|bearer)[A-Za-z0-9_]*[[:space:]]*[=:][[:space:]]*["'"'"']?[A-Za-z0-9_/+.=-]{3,}[0-9][A-Za-z0-9_/+.=-]{3,}'

# No digit required: reaches "password=correcthorsebattery" too.
ASSIGN_RE='(key|token|secret|passw(or)?d|passwd|credential|auth|bearer)[A-Za-z0-9_]*[[:space:]]*[=:][[:space:]]*["'"'"']?[^[:space:]"'"'"'$(]{6,}'

PATH_RE='/Users/[A-Za-z0-9._-]+|/home/[A-Za-z0-9._-]+'
PATH_OK_RE='^/(Users|home)/(username|me|you|yourname|your_name|name|user|USER|someone|runner|ubuntu|ec2-user|\.\.\.)$'
EMAIL_RE='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
EMAIL_OK_RE='^(git@|first[._]last@|firstname[._]lastname@|\.+@|you@|me@|user@|name@|your[._]?name@|noreply@|[A-Za-z0-9._%+-]*@users\.noreply\.github\.com$|[A-Za-z0-9._%+-]+@openssh\.com$)'

# blocklist_file [DIR]: the live blocklist for repo DIR, or nothing when absent.
# DIR defaults to $SCAN_ROOT, which each caller sets to the repo it means.
# Do NOT fall back to $BU here: $BU is exported into every login shell by
# env.sh and may point at a DIFFERENT checkout than the one being scanned.
blocklist_file() {
    local dir="${1:-${SCAN_ROOT:-}}"
    [ -n "$dir" ] || return 0
    [ -f "$dir/.blocklist.local" ] && printf '%s\n' "$dir/.blocklist.local"
    return 0
}

# blocklist_pattern [DIR]: the terms as one ERE alternation, or nothing.
blocklist_pattern() {
    local f
    f="$(blocklist_file "${1:-}")"
    [ -n "$f" ] || return 0
    grep -v '^[[:space:]]*#' "$f" | grep -v '^[[:space:]]*$' | paste -sd'|' -
    return 0
}
