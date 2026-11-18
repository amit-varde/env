#!/usr/bin/env bash
# Scan the publishable tree (default: repo root) for secrets, absolute home paths, and blocklisted terms.
# Exit 1 on any finding. Use as a pre-commit gate:  ./scripts/scan.sh
set -u
. "$(dirname "$0")/lib.sh"
TARGET="${1:-$ROOT}"
BL="$(blocklist_pattern)"; fail=0
FILES=$(find "$TARGET" -type f -not -path '*/.git/*' -not -path '*/_review/*' -not -path '*/ssh/config.d/*.conf' -not -name '.blocklist.local' -not -name 'blocklist.example' -not -name 'lib.sh' -not -name 'scan.sh')
echo "scanning $(echo "$FILES" | grep -c .) files (blocklist: $(basename "$BLOCKLIST"))"
hit() { echo "  [$1] $2"; fail=1; }
while IFS= read -r f; do
  [ -z "$f" ] && continue
  rel="${f#$ROOT/}"
  # A public-key comment is a label (often user@host), not an account email.
  pubkey=0
  head -n 1 "$f" | grep -qE '^(ssh-(ed25519|rsa)|ecdsa-sha2-|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-)[[:space:]]' && pubkey=1
  grep -InE "$SECRET_RE" "$f" >/dev/null 2>&1 && hit "SECRET-PATTERN" "$rel: $(grep -InE "$SECRET_RE" "$f" | head -2 | cut -c1-60)"
  grep -InEi "$ASSIGN_RE" "$f" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#' | grep -vEi 'name|YOUR_|placeholder|example' >/tmp/.scan_assign.$$ && hit "ASSIGNMENT" "$rel: $(head -1 /tmp/.scan_assign.$$ | cut -c1-60)"
  grep -InE '/Users/[A-Za-z0-9._-]+|/home/[A-Za-z0-9._-]+' "$f" >/dev/null 2>&1 && hit "ABS-HOME-PATH" "$rel"
  if [ "$pubkey" -eq 0 ]; then
    grep -InE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$f" 2>/dev/null | grep -vE 'noreply@anthropic|YOUR_|@openssh\.com' >/dev/null && hit "EMAIL" "$rel"
    [ -n "$BL" ] && grep -InEi "$BL" "$f" >/dev/null 2>&1 && hit "BLOCKLIST" "$rel: matches '$(grep -oEi "$BL" "$f" | head -1)'"
  fi
  case "$f" in */.ssh/keys/*|*/ssh/keys/*) head -c 400 "$f" | grep -qE '^(ssh-(ed25519|rsa)|ecdsa-sha2-|sk-ssh-|sk-ecdsa-)' || hit "SSH-NOT-PUBKEY" "$rel";; esac
done <<< "$FILES"
rm -f /tmp/.scan_assign.$$
[ $fail -eq 0 ] && echo "CLEAN" || { echo "FINDINGS above - fix before publishing"; exit 1; }
