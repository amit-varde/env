#!/usr/bin/env bash
# =============================================================================
# File:        tools/install.sh
# =============================================================================
#
# DESCRIPTION: Install dev tools from tools/install_<name>.sh (macOS and Linux)
#   Orchestrates the per-tool installers in dependency order. Safe to re-run;
#   each installer skips what is already present.
#
#   With no arguments, prints the tool list and prompts for what to install
#   (unless there is no TTY or you pass -y/--yes).
#
# OPTIONS:
#   --list       Show each tool, platform, and whether it is installed; exit
#   --all        Install the full stack (INSTALL_ORDER in lib.sh)
#   --tool NAME  Install one tool (repeat for several; order follows INSTALL_ORDER)
#   --dry-run    Print what each installer would do; change nothing
#   -y, --yes    Skip confirmation prompts (non-interactive installs)
#   -h, --help   Show this help
#
# EXIT CODES:
#   0 - Success, list-only, user declined, or nothing to do
#   1 - An installer failed
#   2 - Bad usage or unknown tool name
#
# USAGE:
#   ./tools/install.sh
#   ./tools/install.sh --list
#   ./tools/install.sh --all
#   ./tools/install.sh --tool gh --tool pyenv
#   ./tools/install.sh --dry-run --all
#   env-install              # same script (via alias), interactive
#   env-install all          # --all
#   env-install gh python    # --tool gh --tool python
#
# =============================================================================
set -uo pipefail

: "${BU:=$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.bash
source "$BU/lib/common.bash"
handle_help "$@"

ASSUME_YES=0
HAVE_TTY=0
if [ -r /dev/tty ] && { : </dev/tty; } 2>/dev/null; then HAVE_TTY=1; fi

# shellcheck source=detect.sh
# detect.sh sources lib.sh (INSTALL_ORDER) and defines tool_present, tool_version
# and manifest_write.
. "$DIR/detect.sh"

tool_in_order() {
  local want="$1" t
  for t in "${INSTALL_ORDER[@]}"; do
    [ "$t" = "$want" ] && return 0
  done
  return 1
}

print_tool_list() {
  printf '%-12s %-10s %s\n' TOOL PLATFORM STATE
  local t plat state
  for t in "${INSTALL_ORDER[@]}"; do
    plat=all
    case "$MAC_ONLY_TOOLS" in *" $t "*) plat="macOS only" ;; esac
    if tool_present "$t"; then state=present; else
      state=missing
      if [ "$plat" != all ] && [ "$OS_NAME" != mac ]; then state="missing (manual on this OS)"; fi
    fi
    printf '%-12s %-10s %s\n' "$t" "$plat" "$state"
  done
}

# Build selected[] in INSTALL_ORDER from a space-separated want-list.
select_in_order() {
  selected=()
  local want="$1" t
  for t in "${INSTALL_ORDER[@]}"; do
    case " $want " in *" $t "*) selected+=("$t") ;; esac
  done
}

confirm_install() {
  local label="$1"
  if [ "$DRY" -eq 1 ] || [ "$ASSUME_YES" -eq 1 ]; then return 0; fi
  if [ "$HAVE_TTY" -eq 0 ]; then
    warn "No TTY; refusing to install without --yes."
    return 1
  fi
  confirm "Proceed with: $label?" N
}

run_installers() {
  local t script fail=0
  if [ "$#" -eq 0 ]; then
    info "No tools selected."
    return 0
  fi
  for t in "$@"; do
    script="$DIR/install_${t}.sh"
    echo "==> $t"
    if [ ! -f "$script" ]; then
      err "no installer: $script"
      fail=1
      continue
    fi
    if [ "$DRY" -eq 1 ]; then "$script" --dry-run; continue; fi
    before=N; tool_present "$t" && before=Y
    if "$script"; then
      # Log what changed, so $HOME/.setup-env.log shows which tools were installed when.
      if tool_present "$t"; then
        if [ "$before" = N ]; then setup_log "INSTALLED $t version=$(tool_version "$t")"
        else setup_log "RUN $t (already present, version=$(tool_version "$t")); installer left it as is"; fi
      else
        setup_log "NOT-INSTALLED $t (installer ran, tool still missing; skipped on this OS or needs a manual step)"
      fi
    else
      err "failed: $t"; setup_log "FAILED $t (installer exit non-zero)"; fail=1
    fi
  done
  if [ "$DRY" -eq 0 ]; then manifest_write && setup_log "MANIFEST written: $(manifest_path)"; fi
  if [ $fail -eq 0 ] && [ "$DRY" -eq 0 ]; then
    ok "Finished (installed, already present, or skipped on this OS)."
  elif [ $fail -ne 0 ]; then
    warn "Finished with errors. Re-run after fixing failed steps."
  fi
  return $fail
}

interactive_install() {
  info "Dev tools (tools/)"
  print_tool_list
  echo
  if [ "$HAVE_TTY" -eq 0 ] && [ "$ASSUME_YES" -eq 0 ]; then
    info "No TTY. Use --list, --all, or --tool NAME (add --yes to install without prompts)."
    return 0
  fi
  if confirm "Install all missing tools (full stack, dependency order)?" N; then
    run_installers "${INSTALL_ORDER[@]}"
    return $?
  fi
  local names
  names="$(ask "Tool names (space-separated; see list above, or Enter to quit)" "")"
  [ -z "$names" ] && { info "Nothing to do."; return 0; }
  local bad=0 w
  for w in $names; do
    if ! tool_in_order "$w"; then err "Unknown tool: $w (see --list)"; bad=1; fi
  done
  [ "$bad" -ne 0 ] && return 2
  select_in_order "$names"
  confirm_install "tools: $names" || return 0
  run_installers "${selected[@]}"
}

mode=""
want_tools=""
list_only=0
DRY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --list) list_only=1 ;;
    --all) mode=all ;;
    --tool)
      shift
      [ $# -eq 0 ] && { err "Missing name after --tool"; exit 2; }
      if ! tool_in_order "$1"; then err "Unknown tool: $1 (see --list)"; exit 2; fi
      want_tools="$want_tools $1"
      mode=tool
      ;;
    --dry-run) DRY=1 ;;
    -y|--yes) ASSUME_YES=1 ;;
    -h|--help) show_help; exit 0 ;;
    *)
      err "Unknown option or argument: $1"
      err "Use --list, --all, --tool NAME, --dry-run, or -y"
      exit 2
      ;;
  esac
  shift
done

if [ "$list_only" -eq 1 ]; then
  print_tool_list
  exit 0
fi

if [ -z "$mode" ]; then
  interactive_install
  exit $?
fi

if [ "$mode" = all ]; then
  confirm_install "full dev-tool stack (${#INSTALL_ORDER[@]} installers)" || exit 0
  run_installers "${INSTALL_ORDER[@]}"
  exit $?
fi

# --tool (one or more)
select_in_order "$want_tools"
if [ "${#selected[@]}" -eq 0 ]; then
  err "No tools selected."
  exit 2
fi
confirm_install "tools:${want_tools}" || exit 0
run_installers "${selected[@]}"
exit $?
