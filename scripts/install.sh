#!/usr/bin/env bash
# Install on a new machine/account. Backs up anything it would replace. Safe to re-run.
# Usage: ./scripts/install.sh [--dry-run] [--authorize-keys]
set -u; . "$(dirname "$0")/lib.sh"
DRY=0; AUTH=0
for a in "$@"; do case "$a" in --dry-run) DRY=1;; --authorize-keys) AUTH=1;; esac; done
run() { if [ $DRY -eq 1 ]; then echo "[dry-run] $*"; else "$@"; fi; }
put() { # src dst
  [ -f "$1" ] || return 0
  if [ -f "$2" ] && ! cmp -s "$1" "$2"; then run cp "$2" "$2.bak.$(date +%Y%m%d%H%M%S)"; fi
  run cp "$1" "$2"; echo "installed $2"
}
put "$ROOT/dotfiles/zshrc"  "$HOME/.zshrc"
put "$ROOT/dotfiles/bashrc" "$HOME/.bashrc"
put "$ROOT/dotfiles/cshrc"  "$HOME/.cshrc"
put "$ROOT/dotfiles/vimrc"  "$HOME/.vimrc"
[ -f "$HOME/.gitconfig" ] || echo "NOTE: copy dotfiles/gitconfig.template to ~/.gitconfig and fill in name/email (not auto-installed)"
run mkdir -p "$HOME/.claude"
[ -f "$HOME/.claude/CLAUDE.md" ]    && echo "kept existing ~/.claude/CLAUDE.md (merge by hand)"    || put "$ROOT/claude/CLAUDE.md"    "$HOME/.claude/CLAUDE.md"
[ -f "$HOME/.claude/settings.json" ] && echo "kept existing ~/.claude/settings.json (merge by hand)" || put "$ROOT/claude/settings.json" "$HOME/.claude/settings.json"
run mkdir -p "$HOME/.ssh"
run chmod 700 "$HOME/.ssh"
put "$ROOT/ssh/config" "$HOME/.ssh/config"
perm_src="$ROOT/.ssh/perms.sh"
perm_dst="$HOME/.ssh/perms.sh"
if [ -L "$perm_dst" ] && [ "$(readlink "$perm_dst")" = "$perm_src" ]; then
  echo "linked $perm_dst"
elif [ $DRY -eq 1 ]; then
  echo "[dry-run] ln -sfn $perm_src $perm_dst"
else
  if [ -e "$perm_dst" ] || [ -L "$perm_dst" ]; then
    mv "$perm_dst" "$perm_dst.bak.$(date +%Y%m%d%H%M%S)"
  fi
  ln -s "$perm_src" "$perm_dst"
  chmod 700 "$perm_src"
  echo "linked $perm_dst"
fi
# ~/.ssh/config.d points at this repo, so host entries have one copy.
link="$HOME/.ssh/config.d"
target="$ROOT/ssh/config.d"
if [ -L "$link" ] && [ "$(readlink "$link")" = "$target" ]; then
  echo "linked $link"
elif [ $DRY -eq 1 ]; then
  echo "[dry-run] ln -sfn $target $link"
else
  if [ -e "$link" ] || [ -L "$link" ]; then
    bak="$link.bak.$(date +%Y%m%d%H%M%S)"
    mv "$link" "$bak"
    echo "saved previous $link at $bak"
  fi
  ln -s "$target" "$link"
  echo "linked $link"
fi
shopt -s nullglob
for enc in "$ROOT"/ssh/config.d/*.conf.gpg; do
  dst="${enc%.gpg}"
  if [ $DRY -eq 1 ]; then
    echo "[dry-run] gpg --decrypt ${enc#$ROOT/} -> ${dst#$ROOT/}"
    continue
  fi
  tmp="$(mktemp)"
  if gpg --decrypt -o "$tmp" "$enc"; then
    if [ -f "$dst" ] && ! cmp -s "$tmp" "$dst"; then
      cp "$dst" "$HOME/.ssh/$(basename "$dst").bak.$(date +%Y%m%d%H%M%S)"
    fi
    mv "$tmp" "$dst"
    chmod 600 "$dst"
    echo "installed $dst"
  else
    rm -f "$tmp"
    echo "could not decrypt ${enc#$ROOT/}"
    exit 1
  fi
done
if [ $AUTH -eq 1 ]; then
  run mkdir -p "$HOME/.ssh"; run chmod 700 "$HOME/.ssh"; touch "$HOME/.ssh/authorized_keys" 2>/dev/null
  for k in "$ROOT"/.ssh/keys/*.pub; do [ -f "$k" ] || continue
    grep -qF "$(awk '{print $2}' "$k")" "$HOME/.ssh/authorized_keys" 2>/dev/null || { run sh -c "cat '$k' >> '$HOME/.ssh/authorized_keys'"; echo "authorized $(basename "$k")"; }
  done; run chmod 600 "$HOME/.ssh/authorized_keys"
fi
echo "Create ~/.zshrc.local / ~/.bashrc.local for employer-specific settings (they are sourced if present)."
