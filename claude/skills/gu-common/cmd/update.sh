#: update ff|default|stash-pull <repo> [--rebase] - one safe update step (used by gu-update); refuses anything risky
# ff          behind and not ahead: pull --ff-only, then sync moved submodules if they are clean.
#             A dirty tree is included when every local change already matches the incoming
#             commit. Those copies are cleared (not stashed) so the fast-forward can update
#             the rest; a failed pull puts them back. Real local edits are refused.
# default     on a feature branch: move local <default> to origin/<default> without checkout (fast-forward only)
# stash-pull  dirty and behind: stash -u (named), pull --ff-only (or --rebase), pop. Conflicts stop with the stash kept.
# Before touching files, checks every incoming path is writable from here; if not (sandbox), prints
# NEEDS_USER: <command> and changes nothing. Exit codes: 0 done, 2 refused, 4 needs user, 5 conflict.

writable_check() {  # $1 top, $2 target ref -> prints unwritable paths (max 5)
  ( cd "$1" && git diff --name-only HEAD "$2" | perl -ne '
      chomp; my $p = $_;
      if (-e $p) { open(my $f, ">>", $p) or print "$p\n"; next }
      my $d = $p; do { $d =~ s{/[^/]*$}{} or $d = "." } until -d $d;
      next if $seen{$d}++;
      my $t = "$d/.gu-probe-$$";
      if (open(my $f, ">", $t)) { close $f; unlink $t } else { print "$d/\n" }' | head -5 )
}

sync_submodules() { # $1 top: update submodules whose checkout differs from the recorded commit, if clean
  local top="$1" st p moved="" busy=""
  [ -f "$top/.gitmodules" ] || return 0
  while IFS='|' read -r st p; do
    [ "$st" = + ] || continue
    if [ "$(n_dirty "$p")" != 0 ] || [ "$(G "$p" rev-list --count HEAD --not --remotes --tags)" != 0 ]; then
      busy="$busy ${p#$top/}"
    else moved="$moved ${p#$top/}"; fi
  done < <(submodules "$top")
  [ -n "$moved" ] && G "$top" submodule update --recursive -- $moved && echo "submodules updated:$moved"
  [ -n "$busy" ] && echo "SUBMODULE_NEEDS_DECISION:$busy (local changes or unpushed commits; left as is)"
  return 0
}

main() {
  local action="${1:-}" rebase=0 top b def before bad up
  [ $# -ge 2 ] || die "usage: gu update ff|default|stash-pull <repo> [--rebase]"
  top=$(resolve_repo "$2"); [ "${3:-}" = --rebase ] && rebase=1
  [ -n "$(lock_level "$top")" ] && { echo "REFUSED: locked ($(lock_level "$top")) - /gu-unlock first"; exit 2; }
  [ "$(op_in_progress "$top")" != - ] && { echo "REFUSED: $(op_in_progress "$top") in progress"; exit 2; }
  b=$(branch "$top"); before=$(G "$top" rev-parse --short HEAD)

  case "$action" in
    ff|stash-pull)
      up=$(upstream "$top"); [ "$up" = - ] && { echo "REFUSED: $b has no upstream"; exit 2; }
      if [ "$action" = ff ]; then
        [ "$(behind_ahead "$top" '@{u}' HEAD | cut -d/ -f2)" = 0 ] || { echo "REFUSED: has local commits (diverged)"; exit 2; }
        ff_worktree_is_upstream "$top" || { echo "REFUSED: uncommitted changes (use stash-pull)"; exit 2; }
      fi
      bad=$(writable_check "$top" '@{u}')
      if [ -n "$bad" ]; then
        echo "NEEDS_USER: can't write here (sandbox):"; printf '  %s\n' $bad
        if [ "$action" = ff ]; then echo "run: ! git -C $top pull --ff-only && git -C $top submodule update --recursive"
        else echo "run: ! gu update stash-pull ${top#$GU_WORK/}"; fi
        exit 4
      fi
      if [ "$action" = stash-pull ]; then
        local msg; msg="gu-update $(date +%F) $b"
        G "$top" stash push -u -m "$msg" >/dev/null || { echo "REFUSED: stash failed"; exit 2; }
        echo "stashed: $msg"
        if [ "$rebase" = 1 ]; then G "$top" pull --rebase --quiet; else G "$top" pull --ff-only --quiet; fi \
          || { echo "CONFLICT: pull failed; stash kept ($msg). git -C $top status"; exit 5; }
        if ! G "$top" stash pop --quiet; then
          echo "CONFLICT: stash pop conflicted; stash kept ($msg). Files:"; G "$top" diff --name-only --diff-filter=U | sed 's/^/  /'
          exit 5
        fi
        echo "restored local changes"
      else
        ff_clear_upstream_copies "$top" || {
          ff_restore_upstream_copies "$top"; ff_drop_clear_lists
          echo "REFUSED: could not clear files that already match the incoming commit"; exit 2; }
        [ -n "$FF_CLEAR_MSG" ] && echo "$FF_CLEAR_MSG"
        if ! G "$top" pull --ff-only --quiet; then
          ff_restore_upstream_copies "$top"; ff_drop_clear_lists
          echo "CONFLICT: pull --ff-only failed"; exit 5
        fi
        ff_drop_clear_lists
      fi
      echo "updated: ${top#$GU_WORK/} $b $before..$(G "$top" rev-parse --short HEAD)"
      sync_submodules "$top" ;;
    default)
      def=$(default_branch "$top")
      [ "$b" = "$def" ] && { echo "REFUSED: $def is checked out (use ff)"; exit 2; }
      before=$(G "$top" rev-parse --short "$def")
      G "$top" fetch --quiet origin "$def:$def" || { echo "REFUSED: $def has local commits (not a fast-forward)"; exit 2; }
      echo "updated: ${top#$GU_WORK/} $def $before..$(G "$top" rev-parse --short "$def") (not checked out)" ;;
    *) die "update: unknown action $action" ;;
  esac
}
