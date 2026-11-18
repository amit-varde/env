#!/usr/bin/env bash
# Copy ONLY public keys into .ssh/keys/, with the comment replaced by amit-varde-<type>.
# Usage: ./scripts/export-ssh-pub.sh [label]     e.g. ./scripts/export-ssh-pub.sh amit-varde
set -u; . "$(dirname "$0")/lib.sh"
LABEL="${1:-amit-varde}"; OUT="$ROOT/.ssh/keys"; mkdir -p "$OUT"; n=0
for pub in "$HOME"/.ssh/*.pub; do
  [ -f "$pub" ] || continue
  first="$(head -1 "$pub")"
  case "$first" in
    ssh-ed25519\ *|ssh-rsa\ *|ecdsa-sha2-*\ *|sk-ssh-ed25519@openssh.com\ *|sk-ecdsa-sha2-*\ *) ;;
    *) echo "skip (not a recognised public key): $pub"; continue;;
  esac
  type="$(echo "$first" | awk '{print $1}')"; blob="$(echo "$first" | awk '{print $2}')"
  alg="$(printf '%s' "$type" | sed -E 's/^ssh-//; s/^sk-ssh-/sk-/; s/@openssh\.com$//; s/^ecdsa-sha2-/ecdsa-/')"
  n=$((n+1)); base="$(basename "$pub" .pub)"; stem="${LABEL}-${alg}"
  name="${stem}.pub"
  if [ -e "$OUT/$name" ] && [ "$(awk '{print $2}' "$OUT/$name")" != "$blob" ]; then
    name="${stem}-${base}.pub"
  fi
  printf '%s %s %s\n' "$type" "$blob" "$stem" > "$OUT/$name"
  echo "exported $base -> .ssh/keys/$name   fingerprint: $(ssh-keygen -lf "$OUT/$name" 2>/dev/null | awk '{print $2}')"
done
[ $n -eq 0 ] && echo "no public keys found in ~/.ssh"
echo "Private keys are never read by this script."
