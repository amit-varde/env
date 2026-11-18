#!/usr/bin/env bash
# Encrypt each ssh/config.d/*.conf into ssh/config.d/*.conf.gpg (ASCII-armored, AES256).
# gpg prompts for the passphrase. Store that passphrase in 1Password, not in this repo.
# Non-interactive: SSH_CONFIG_PASS_FILE=/path/to/mode-600-file ./scripts/export-ssh-config.sh
set -eu
. "$(dirname "$0")/lib.sh"
shopt -s nullglob
srcs=("$ROOT"/ssh/config.d/*.conf)
[ ${#srcs[@]} -gt 0 ] || { echo "no plaintext files in ssh/config.d/"; exit 1; }
if [ -n "${SSH_CONFIG_PASS_FILE:-}" ]; then
  [ -f "$SSH_CONFIG_PASS_FILE" ] || { echo "missing SSH_CONFIG_PASS_FILE"; exit 1; }
fi
for src in "${srcs[@]}"; do
  out="$src.gpg"
  if [ -n "${SSH_CONFIG_PASS_FILE:-}" ]; then
    gpg --batch --yes --pinentry-mode loopback --passphrase-file "$SSH_CONFIG_PASS_FILE" \
      --symmetric --cipher-algo AES256 --armor -o "$out" "$src"
  else
    gpg --symmetric --cipher-algo AES256 --armor --yes -o "$out" "$src"
  fi
  echo "wrote ${out#$ROOT/}"
done
