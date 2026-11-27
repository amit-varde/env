#!/usr/bin/env bash
# Install this repo onto a machine or account. Safe to re-run.
#
# This is a shim. The installer is ./setup-env.sh, which does everything this
# script used to do and more: shell wiring, SSH (including decrypting the
# published ssh/config.d/*.conf.gpg and linking ~/.ssh/perms.sh), Claude Code
# settings and skills, dotfiles, Cursor, dev tools and the health report. It
# asks before every change, backs up whatever it replaces, and records what it
# did in ~/.setup-env.log. Keeping two installers meant two sets of rules for
# the same files, so there is now one.
#
# Usage:
#   ./scripts/install.sh [--authorize-keys] [-y] [--only STEPS] [--skip STEPS]
#   ./scripts/install.sh --dry-run        # list the steps; changes nothing
#
# Everything is passed through to ./setup-env.sh; see `./setup-env.sh --help`.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTRY="$ROOT/setup-env.sh"
[ -f "$ENTRY" ] || { echo "$ENTRY not found" >&2; exit 1; }

args=()
for a in "$@"; do
  case "$a" in
    --dry-run)
      # setup-env.sh has no --dry-run: it is interactive and confirms each
      # change instead. Show what would run rather than pretending to simulate.
      echo "setup-env.sh asks before every change, so there is no separate dry run."
      echo "Steps it would work through, in order:"
      bash "$ENTRY" --list-steps | sed 's/^/  /'
      echo
      echo "Run one step at a time with:  ./setup-env.sh --only <step>"
      exit 0 ;;
    *) args+=("$a") ;;
  esac
done

echo "scripts/install.sh now runs ./setup-env.sh (see the header of this file)."
if [ "${#args[@]}" -gt 0 ]; then exec bash "$ENTRY" "${args[@]}"; else exec bash "$ENTRY"; fi
