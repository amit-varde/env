#!/usr/bin/env bash
# Report and repair permissions for ~/.ssh.
# Usage: ~/.ssh/perms.sh [--verify] [--fix]
#   --verify   print the report and exit 1 if anything is wrong
#   --fix      chmod files to the modes below, then report
#   both       fix, then verify the result
# With no flags, --verify is assumed.
#
#   ~/.ssh and other directories                         700
#   private keys, *.pem, authorized_keys, *.conf         600 (400 is already owner-only and is left alone)
#   *.pub, config, known_hosts, and backups of those     644
#   *.sh                                                 700
# Symlinks are reported and not chmod'd. Their target is checked
# when it is ~/.ssh/config.d.
set -u
VERIFY=0
FIX=0
for a in "$@"; do
  case "$a" in
    --verify) VERIFY=1 ;;
    --fix) FIX=1 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "usage: perms.sh [--verify] [--fix]" >&2; exit 2 ;;
  esac
done
[ "$VERIFY" -eq 0 ] && [ "$FIX" -eq 0 ] && VERIFY=1

SSH="${HOME}/.ssh"
fail=0
pretty() { case "$1" in "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;; *) printf '%s' "$1" ;; esac; }

acceptable() { # got class -> 0 if got is allowed
  case "$2" in
    700) [ "$1" = 700 ] ;;
    644) [ "$1" = 644 ] || [ "$1" = 600 ] ;;
    private) [ "$1" = 600 ] || [ "$1" = 400 ] ;;
    *) return 1 ;;
  esac
}
canon() { # class -> mode --fix applies
  case "$1" in private) echo 600 ;; *) echo "$1" ;; esac
}

check() { # path class
  local path="$1" class="$2" got now label target
  [ -e "$path" ] || [ -L "$path" ] || { printf 'missing  %s\n' "$(pretty "$path")"; fail=1; return; }
  if [ -L "$path" ]; then
    printf 'ok    link  %s -> %s\n' "$(pretty "$path")" "$(readlink "$path")"
    return
  fi
  got="$(stat -f '%Lp' "$path")"
  label="$(pretty "$path")"
  if acceptable "$got" "$class"; then
    printf 'ok    %s  %s\n' "$got" "$label"
    return
  fi
  target="$(canon "$class")"
  if [ "$FIX" -eq 1 ]; then
    chmod "$target" "$path" || { printf 'bad   %s  %s  chmod failed\n' "$got" "$label"; fail=1; return; }
    now="$(stat -f '%Lp' "$path")"
    if acceptable "$now" "$class"; then
      printf 'fixed %s -> %s  %s\n' "$got" "$now" "$label"
    else
      printf 'bad   %s  %s  want %s\n' "$now" "$label" "$target"
      fail=1
    fi
    return
  fi
  printf 'bad   %s  %s  want %s\n' "$got" "$label" "$target"
  fail=1
}

want_for() { # path -> prints class (700, 644, private) or empty
  local base
  base="$(basename "$1")"
  case "$base" in
    *.pub|config|known_hosts|known_hosts.old|config.bak*|known_hosts.bak*) echo 644 ;;
    *.sh) echo 700 ;;
    *.pem|*.pem.bak*|authorized_keys|authorized_keys.bak*|*.conf|id_*|id_*.bak*) echo private ;;
    *)
      if [ -f "$1" ] && head -n 1 "$1" | grep -q 'PRIVATE KEY'; then echo private
      else echo ""
      fi
      ;;
  esac
}

[ -d "$SSH" ] || { echo "missing $SSH"; exit 1; }
check "$SSH" 700

shopt -s nullglob
for path in "$SSH"/* "$SSH"/.[!.]*; do
  base="$(basename "$path")"
  case "$base" in .|..|.DS_Store) continue ;; esac
  if [ -L "$path" ]; then
    check "$path" 777
    continue
  fi
  if [ -d "$path" ]; then
    check "$path" 700
    continue
  fi
  [ -f "$path" ] || continue
  mode="$(want_for "$path")"
  if [ -n "$mode" ]; then
    check "$path" "$mode"
  else
    printf 'skip  %s  %s\n' "$(stat -f '%Lp' "$path")" "$(pretty "$path")"
  fi
done

cfg="$SSH/config.d"
if [ -d "$cfg" ]; then
  if [ ! -L "$cfg" ]; then
    check "$cfg" 700
  else
    check "$(cd "$cfg" && pwd -P)" 700
  fi
  for conf in "$cfg"/*.conf; do
    [ -f "$conf" ] || continue
    check "$conf" private
  done
fi

[ "$fail" -eq 0 ]
