#: lock <repo>... [--level git|files|full] [--recursive] [--reason TEXT] - lock repos against accidental changes
# git:   hooks (core.hooksPath -> <gitdir>/gu-lock/hooks) refuse every local ref change except
#        refs/remotes/* (reference-transaction; --no-verify can't skip it) and any push. Fetch works.
# files: tracked files + their dirs chmod a-w.   full: both.
# Every level also chmod -R go-rwx (mode-safe form of the `lock` alias, chmod -R 700).
# State in <gitdir>/gu-lock/state so `gu unlock` restores hooksPath and permissions exactly.

LOCK_HOOKS="pre-commit prepare-commit-msg commit-msg pre-merge-commit pre-rebase pre-push pre-applypatch applypatch-msg reference-transaction"
SANDBOX_HINT="(sandbox? run it yourself: ! gu $GU_CMDLINE)"

tracked_paths() {   # $1 top -> NUL-separated tracked regular files, their dirs and top (no symlinks/gitlinks)
  ( cd "$1" && git ls-files -z | perl -0ne '
      chomp; next unless -f $_ && ! -l $_;
      print "$ENV{PWD}/$_\0";
      my $d = $_; while ($d =~ s{/[^/]+$}{}) { $dirs{$d}=1 }
      END { print "$ENV{PWD}/$_\0" for sort keys %dirs; print "$ENV{PWD}\0" }' )
}

lock_targets() {    # $1 top, $2 recursive -> top and (optionally) initialized submodules, one per line
  [ "$2" = 1 ] && init_submodules "$1"
  echo "$1"
}

lock_one() {        # $1 top, $2 level, $3 reason
  local top="$1" level="$2" reason="$3" gd ld prev prev_set=0 h
  gd=$(commondir "$top"); ld="$gd/gu-lock"
  [ -f "$ld/state" ] && { echo "already locked: $top ($(lock_level "$top"))"; return 0; }
  [ "$(n_dirty "$top")" != 0 ] && echo "note: $top has uncommitted changes; they stay (read-only with files/full)"
  prev=$(G "$top" config --local --get core.hooksPath) && prev_set=1
  mkdir -p "$ld/hooks" 2>/dev/null || die "cannot write $ld $SANDBOX_HINT"
  for h in $LOCK_HOOKS; do
    cp "$GU_HOME/hooks/guard-hook.sh" "$ld/hooks/$h" && chmod +x "$ld/hooks/$h" || { rm -rf "$ld"; die "cannot write $ld/hooks $SANDBOX_HINT"; }
  done
  printf 'level=%s\nreason=%s\ndate=%s\nprev_hooks_set=%s\nprev_hooks=%s\n' \
    "$level" "$reason" "$(date '+%Y-%m-%d %H:%M')" "$prev_set" "$prev" >"$ld/state.tmp"
  if [ "$level" != files ] && ! G "$top" config --local core.hooksPath "$ld/hooks"; then
    rm -rf "$ld"; die "cannot write $gd/config $SANDBOX_HINT"
  fi
  chmod -R go-rwx "$top" 2>/dev/null
  if [ "$level" != git ]; then
    tracked_paths "$top" | perl -0ne 'chomp; print "$_\0" unless -w $_' >"$ld/readonly-before"
    tracked_paths "$top" | xargs -0 chmod a-w 2>/dev/null
  fi
  mv "$ld/state.tmp" "$ld/state"
  echo "locked ($level): $top"
}

unlock_one() {      # $1 top
  local top="$1" gd ld level st
  gd=$(commondir "$top"); ld="$gd/gu-lock"; st="$ld/state"
  [ -f "$st" ] || { echo "not locked: $top"; return 0; }
  level=$(lock_level "$top")
  if [ "$level" != files ]; then
    if [ "$(lock_field "$top" prev_hooks_set)" = 1 ]; then
      G "$top" config --local core.hooksPath "$(lock_field "$top" prev_hooks)"
    else
      G "$top" config --local --unset core.hooksPath
    fi
    [ "$(G "$top" config --local --get core.hooksPath)" = "$ld/hooks" ] && die "cannot write $gd/config $SANDBOX_HINT"
  fi
  if [ "$level" != git ]; then
    tracked_paths "$top" | perl -0ne '
        BEGIN { open my $f, "<", shift @ARGV or die; local $/="\0"; while (<$f>) { chomp; $ro{$_}=1 } }
        chomp; print "$_\0" unless $ro{$_}' "$ld/readonly-before" | xargs -0 chmod u+w 2>/dev/null
  fi
  chmod -R go+rX "$top" 2>/dev/null     # mode-safe `unlock` alias: dirs/executables 755, files 644
  rm -rf "$ld"
  echo "unlocked: $top"
}

lock_main() {       # $1 lock|unlock, rest: args
  local action="$1" level=git recursive=0 reason="" repos=() r t; shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --level) level="$2"; shift ;; --level=*) level="${1#*=}" ;;
      --recursive|-r) recursive=1 ;;
      --reason) reason="$2"; shift ;; --reason=*) reason="${1#*=}" ;;
      -*) die "$action: unknown option $1" ;;
      *) repos+=("$1") ;;
    esac; shift
  done
  case "$level" in git|files|full) ;; *) die "level must be git, files or full" ;; esac
  [ ${#repos[@]} -gt 0 ] || die "usage: gu $action <repo>..."
  for r in "${repos[@]}"; do
    for t in $(lock_targets "$(resolve_repo "$r")" "$recursive"); do
      if [ "$action" = lock ]; then lock_one "$t" "$level" "$reason"; else unlock_one "$t"; fi
    done
  done
}

main() { lock_main lock "$@"; }
