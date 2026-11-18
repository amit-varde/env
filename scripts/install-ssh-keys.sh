#!/usr/bin/env bash
# Install the private keys that match .ssh/keys/*.pub into ~/.ssh/ from 1Password.
# SSH Key items are matched by fingerprint. Other 1Password keys are left alone.
# Usage: ./scripts/install-ssh-keys.sh [--dry-run]
set -euo pipefail
. "$(dirname "$0")/lib.sh"
DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1
command -v op >/dev/null 2>&1 || { echo "1Password CLI (op) is required"; exit 1; }
command -v ssh-keygen >/dev/null 2>&1 || { echo "ssh-keygen is required"; exit 1; }
shopt -s nullglob
pubs=("$ROOT"/.ssh/keys/*.pub)
[ ${#pubs[@]} -gt 0 ] || { echo "no public keys in .ssh/keys"; exit 1; }

umask 077
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

wipe() {
  [ -f "$1" ] || return 0
  python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); p.write_bytes(b"\0"*p.stat().st_size)' "$1"
  rm -f "$1"
}

# vault-id, item-id, fingerprint. Fingerprint only; private keys are not requested here.
index="$(mktemp)"
list="$(mktemp)"
trap 'rm -f "$index" "$list"' EXIT
if ! op item list --categories "SSH Key" --format json > "$list"; then
  echo "1Password CLI did not return SSH keys. Approve the desktop prompt, then re-run."
  exit 1
fi
python3 -c '
import json, subprocess, sys
items = json.load(open(sys.argv[1]))
for item in items:
    iid = item["id"]
    raw = subprocess.check_output(["op", "item", "get", iid, "--fields", "label=fingerprint", "--format", "json"])
    field = json.loads(raw)
    if isinstance(field, list):
        field = field[0] if field else {}
    fp = (field or {}).get("value") or ""
    vault = item.get("vault") or {}
    vid = vault.get("id") or ""
    if fp and vid:
        sys.stdout.write(f"{vid}\t{iid}\t{fp}\n")
' "$list" > "$index"

install_one() { # pubfile
  local pub="$1" fp dest tmp got ref old
  fp="$(ssh-keygen -lf "$pub" | awk '{print $2}')"
  case "$(ssh-keygen -lf "$pub")" in
    *\(ED25519\)*) dest="id_ed25519" ;;
    *\(RSA\)*) dest="id_rsa" ;;
    *\(ECDSA\)*) dest="id_ecdsa" ;;
    *) echo "skip $(basename "$pub"): unrecognised key type"; return 0 ;;
  esac
  match="$(awk -F '\t' -v fp="$fp" '$3==fp {print $1, $2; exit}' "$index")"
  if [ -z "$match" ]; then
    echo "no 1Password SSH key matches $(basename "$pub") ($fp)"
    return 1
  fi
  vid="${match%% *}"
  iid="${match#* }"
  if [ "$DRY" -eq 1 ]; then
    echo "[dry-run] install ~/.ssh/$dest from 1Password ($fp)"
    return 0
  fi
  tmp="$(mktemp "$HOME/.ssh/.install-key.XXXXXX")"
  chmod 600 "$tmp"
  if ! op read "op://${vid}/${iid}/private key?ssh-format=openssh" > "$tmp"; then
    wipe "$tmp"
    echo "could not read the private key for ~/.ssh/$dest"
    return 1
  fi
  got="$(ssh-keygen -lf "$tmp" 2>/dev/null | awk '{print $2}' || true)"
  if [ "$got" != "$fp" ]; then
    wipe "$tmp"
    echo "refusing ~/.ssh/$dest: 1Password key fingerprint does not match $(basename "$pub")"
    return 1
  fi
  if [ -f "$HOME/.ssh/$dest" ]; then
    old="$(ssh-keygen -lf "$HOME/.ssh/$dest" 2>/dev/null | awk '{print $2}' || true)"
    if [ "$old" = "$fp" ]; then
      wipe "$tmp"
      echo "present ~/.ssh/$dest"
    else
      cp "$HOME/.ssh/$dest" "$HOME/.ssh/$dest.bak.$(date +%Y%m%d%H%M%S)"
      mv "$tmp" "$HOME/.ssh/$dest"
      echo "installed ~/.ssh/$dest (previous key backed up)"
    fi
  else
    mv "$tmp" "$HOME/.ssh/$dest"
    echo "installed ~/.ssh/$dest"
  fi
  chmod 600 "$HOME/.ssh/$dest"
  if [ -f "$HOME/.ssh/$dest.pub" ] && [ "$(awk '{print $2}' "$HOME/.ssh/$dest.pub")" = "$(awk '{print $2}' "$pub")" ]; then
    chmod 644 "$HOME/.ssh/$dest.pub"
    echo "present ~/.ssh/$dest.pub"
  else
    [ -f "$HOME/.ssh/$dest.pub" ] && cp "$HOME/.ssh/$dest.pub" "$HOME/.ssh/$dest.pub.bak.$(date +%Y%m%d%H%M%S)"
    cp "$pub" "$HOME/.ssh/$dest.pub"
    chmod 644 "$HOME/.ssh/$dest.pub"
    echo "installed ~/.ssh/$dest.pub"
  fi
}

fail=0
for pub in "${pubs[@]}"; do
  install_one "$pub" || fail=1
done
[ "$fail" -eq 0 ]
