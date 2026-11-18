#!/usr/bin/env bash
# Produce scrubbed COPIES of your real shell rc files in _review/dotfiles/ for you to read before publishing.
# Usage: ./scripts/export-dotfiles.sh [file ...]      default: ~/.zshrc ~/.bashrc ~/.cshrc ~/.tcshrc ~/.zprofile ~/.bash_profile
set -u; . "$(dirname "$0")/lib.sh"
OUT="$ROOT/_review/dotfiles"; mkdir -p "$OUT"; BL="$(blocklist_pattern)"
[ $# -eq 0 ] && set -- "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.cshrc" "$HOME/.tcshrc" "$HOME/.zprofile" "$HOME/.bash_profile"
for src in "$@"; do
  [ -f "$src" ] || { echo "skip (not found): $src"; continue; }
  name="$(basename "$src" | sed 's/^\.//')"; dst="$OUT/$name"; rm_log="$OUT/$name.removed.txt"; : > "$rm_log"
  n=0
  while IFS= read -r line || [ -n "$line" ]; do
    drop=""
    echo "$line" | grep -qE "$SECRET_RE" && drop="secret-pattern"
    [ -z "$drop" ] && echo "$line" | grep -Ei "^[[:space:]]*(export|setenv|set)?[[:space:]]*[A-Za-z0-9_]*(key|token|secret|passw|credential|auth)[A-Za-z0-9_]*[[:space:]=]" | grep -qvE '^[[:space:]]*#' && drop="secret-assignment"
    [ -z "$drop" ] && [ -n "$BL" ] && echo "$line" | grep -qEi "$BL" && drop="blocklist"
    [ -z "$drop" ] && echo "$line" | grep -qE '(ssh|scp|rsync)[^#]*@|[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' && drop="host-or-ip"
    if [ -n "$drop" ]; then n=$((n+1)); echo "[$drop] $(echo "$line" | cut -c1-30)..." >> "$rm_log"; echo "# [removed: $drop]" >> "$dst.tmp"
    else echo "$line" | sed -E "s#$HOME#\$HOME#g; s#/Users/[A-Za-z0-9._-]+#\$HOME#g; s#/home/[A-Za-z0-9._-]+#\$HOME#g" >> "$dst.tmp"; fi
  done < "$src"
  mv "$dst.tmp" "$dst"; echo "$src -> _review/dotfiles/$name  ($n line(s) removed; reasons in $name.removed.txt, values not logged)"
done
echo "NEXT: read each file in _review/dotfiles/, move keepers into dotfiles/, move employer bits to ~/.zshrc.local, then run scripts/scan.sh"
