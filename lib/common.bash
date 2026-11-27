#!/usr/bin/env bash
# =============================================================================
# File:        lib/common.bash
# =============================================================================
#
# DESCRIPTION:
#   Shared functions for this repo. Sourced by env.sh (so a shell has the log
#   helpers), by bin/ scripts, by tools/lib.sh, and by setup-env.sh. Sourcing
#   defines functions only. It is not named init-*, so the env.sh loop does
#   not pick it up a second time.
#
#   bootstrap.sh copies the small helpers (ok, warn, die, err, success, have,
#   ask, confirm, norm_path, and the two functions they call). It cannot source
#   this file: it runs before a clone exists. tests/check-helper-drift.sh keeps
#   those copies identical.
#
# OUTPUT:
#   info, info_bold, warn, err, debug, success, ok, die, bu_print, print
#   warn prints at the default verbosity (BU_VERBOSE_LEVEL >= 0). debug needs 2.
#   ok is success. die prints with err and exits 1.
#
# OTHER:
#   have, norm_path, file_mode, ask, confirm, show_help, handle_help
#   cursor_os, cursor_user_dir, cursor_state_db, cursor_find_cli, cursor_running
#   editor_open
#   pkg_mgr, linux_pkg, can_root, as_root, pkg_install
#   setup_env_main   (the setup-env.sh steps)
#
# =============================================================================

# Colors, if the caller has not loaded them yet. Works from bash and zsh, and
# when $BU is not set (tools/install_*.sh, the first lines of a bin/ script).
if [[ -z "${RESET:-}" ]]; then
    if [[ -n "${BASH_SOURCE:-}" ]]; then
        _COMMON_PATH="${BASH_SOURCE[0]}"
    elif [[ -n "${ZSH_VERSION:-}" ]]; then
        # shellcheck disable=SC2296  # zsh prompt expansion, not bash
        _COMMON_PATH="${(%):-%N}"
    else
        _COMMON_PATH="$0"
    fi
    _COMMON_DIR="$(cd "$(dirname "${_COMMON_PATH}")" && pwd)"
    # shellcheck source=term-colors.bash
    source "$_COMMON_DIR/term-colors.bash"
    unset _COMMON_PATH _COMMON_DIR
fi

# -1 = errors only, 0 = info/success/warn/error (default), 2 = + debug
export BU_VERBOSE_LEVEL=${BU_VERBOSE_LEVEL:-0}

# ---- Output (copied into bootstrap.sh) --------------------------------------
_get_caller_info() {
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        # funcfiletrace = call sites ([1] called us, [2] called err/debug);
        # funcsourcetrace would give where functions were defined.
        # shellcheck disable=SC2154  # funcfiletrace is a zsh variable
        local trace=("${funcfiletrace[@]}")
        if [[ ${#trace[@]} -gt 1 ]]; then
            echo "${trace[2]##*:}:$(basename "${trace[2]%:*}" 2>/dev/null)"
            return
        fi
    fi

    local lineno="${BASH_LINENO[1]:-}"
    local file="${BASH_SOURCE[2]:-}"
    echo "${lineno}:$(basename "${file}" 2>/dev/null)"
}

_get_timestamp() {
    [[ "${BU_LOG_SHOWDATES:-0}" = "1" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] "
}

err() {
    local caller_info; caller_info="$(_get_caller_info)"
    if [[ "${BU_VERBOSE_LEVEL:-0}" -gt -1 ]]; then
        echo -e "${ERR_COLOR:-\033[0;31m}Error: $(_get_timestamp)[${caller_info}] $*${RESET:-\033[0m}" >&2
    fi
}

warn() {
    if [[ "${BU_VERBOSE_LEVEL:-0}" -ge 0 ]]; then
        echo -e "${WARN_COLOR:-\033[0;33m}$(_get_timestamp)Warning: $*${RESET:-\033[0m}" >&2
    fi
}

info() {
    if [[ "${BU_VERBOSE_LEVEL:-0}" -ge 0 ]]; then
        echo -e "${INFO_COLOR:-\033[0;36m}$(_get_timestamp)Info: $*${RESET:-\033[0m}"
    fi
}

info_bold() {
    if [[ "${BU_VERBOSE_LEVEL:-0}" -ge 0 ]]; then
        echo -e "${BOLD:-\033[1m}${INFO_COLOR:-\033[0;36m}$(_get_timestamp)Info: $*${RESET:-\033[0m}"
    fi
}

debug() {
    if [[ "${BU_VERBOSE_LEVEL:-0}" -ge 2 ]]; then
        local caller_info; caller_info="$(_get_caller_info)"
        echo -e "${DEBUG_COLOR:-\033[0;35m}$(_get_timestamp)Debug [${caller_info}]: $*${RESET:-\033[0m}"
    fi
}

success() {
    if [[ "${BU_VERBOSE_LEVEL:-0}" -ge 0 ]]; then
        echo -e "${SUCCESS_COLOR:-\033[0;32m}$(_get_timestamp)$*${RESET:-\033[0m}"
    fi
}

ok() { success "$@"; }

die() { err "$@"; exit 1; }

bu_print() {
    if [[ "${BU_VERBOSE_LEVEL:-0}" -ge 0 ]]; then
        if [[ $# -eq 0 ]]; then
            printf "\n"
        else
            printf "$@"
            printf "\n"
        fi
    fi
}

# Avoid shadowing zsh's builtin print used in prompts; enable shim only when requested.
if [[ -z "${ZSH_VERSION:-}" ]] || [[ "${BU_ENABLE_PRINT_SHIM:-0}" == "1" ]]; then
    print() { bu_print "$@"; }
fi

# ---- Small helpers (have, norm_path, ask, confirm copied into bootstrap.sh) --
have() { command -v "$1" >/dev/null 2>&1; }

# Absolute path: ~ expanded, relative made absolute, no trailing slash.
norm_path() {
    local p="$1"
    p="${p/#\~/$HOME}"
    case "$p" in /*) ;; *) p="$PWD/$p" ;; esac
    while [ "${#p}" -gt 1 ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done
    printf '%s' "$p"
}

# ask "Question" default  -> echoes the answer (default when -y or no terminal)
ask() {
    local q="$1" def="${2:-}" ans
    if [ "$ASSUME_YES" -eq 1 ] || [ "$HAVE_TTY" -eq 0 ]; then echo "$def"; return; fi
    read -r -p "  $q [$def]: " ans </dev/tty
    echo "${ans:-$def}"
}

# confirm "Question" [Y|N]  -> exit status 0 for yes
confirm() {
    local q="$1" def="${2:-Y}" ans hint="[Y/n]"
    [ "$def" = "N" ] && hint="[y/N]"
    if [ "$ASSUME_YES" -eq 1 ]; then [ "$def" = "Y" ]; return; fi
    if [ "$HAVE_TTY" -eq 0 ]; then [ "$def" = "Y" ]; return; fi
    read -r -p "  $q $hint " ans </dev/tty
    ans="${ans:-$def}"
    case "$ans" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

# Octal permission bits (GNU and macOS stat). GNU stat goes first: its -f means
# "file system" and prints a dump to stdout before failing, while BSD stat rejects
# -c without printing anything.
file_mode() {
    stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}

# Print a script's header comment (between its 2nd and 3rd "# ====" lines).
show_help() {
    awk 'NR > 1 && /^# =+$/ { if (++n == 3) exit; next } n == 2 { sub(/^# ?/, ""); if (!body && $0 == "") next; body = 1; print }' "${1:-$0}"
}

handle_help() {
    case "${1:-}" in -h|--help) show_help; exit 0 ;; esac
}

# ---- Cursor -------------------------------------------------------------------
cursor_os() {
    case "$(uname -s)" in Darwin) echo mac ;; *) echo linux ;; esac
}

cursor_user_dir() {
    if [ -n "${CURSOR_USER_DIR:-}" ]; then echo "$CURSOR_USER_DIR"; return; fi
    if [ "$(cursor_os)" = mac ]; then echo "$HOME/Library/Application Support/Cursor/User"
    else echo "${XDG_CONFIG_HOME:-$HOME/.config}/Cursor/User"; fi
}

cursor_state_db() {
    echo "${CURSOR_STATE_DB:-$(cursor_user_dir)/globalStorage/state.vscdb}"
}

cursor_find_cli() {
    local self="${1:-}" c
    [ -n "$self" ] && self="$(realpath "$self" 2>/dev/null || echo "$self")"
    for c in "${CURSOR_CLI:-}" "$(command -v cursor 2>/dev/null || true)" \
             /usr/local/bin/cursor /usr/bin/cursor \
             "/Applications/Cursor.app/Contents/Resources/app/bin/cursor" \
             "$HOME/Applications/Cursor.app/Contents/Resources/app/bin/cursor"; do
        [ -n "$c" ] && [ -x "$c" ] || continue
        [ -n "$self" ] && [ "$(realpath "$c" 2>/dev/null || echo "$c")" = "$self" ] && continue
        echo "$c"; return 0
    done
    return 1
}

cursor_running() {
    case "${CURSOR_IDE_RUNNING:-}" in 1) return 0 ;; 0) return 1 ;; esac
    if [ "$(cursor_os)" = mac ]; then pgrep -x Cursor >/dev/null 2>&1
    else pgrep -xi cursor >/dev/null 2>&1; fi
}

# ---- Editor -------------------------------------------------------------------
editor_open() {
    local app="${EDITOR_APP:-Cursor.app}" rc
    case "$app" in
        Cursor|Cursor.app)
            if have cursor-ide; then
                cursor-ide "$@"; rc=$?
                [ "$rc" -ne 2 ] && return "$rc"      # 2 = Cursor/sqlite3 not found: try the OS opener
            fi
            app="Cursor.app" ;;
    esac
    if [[ "${OSTYPE:-}" == darwin* ]]; then
        open -a "$app" "$@"
    elif have xdg-open; then
        xdg-open "$@"
    else
        return 1
    fi
}

# ---- Packages -----------------------------------------------------------------
# can_root: true when we are root, sudo needs no password, or /dev/tty can ask.
can_root() {
    [ "$(id -u)" -eq 0 ] && return 0
    have sudo || return 1
    sudo -n true 2>/dev/null && return 0
    [ -r /dev/tty ] && { : </dev/tty; } 2>/dev/null && return 0
    return 1
}

as_root() {
    if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

pkg_mgr() {
    local m
    for m in apt-get dnf yum pacman; do
        have "$m" && { echo "$m"; return 0; }
    done
    return 1
}

# linux_pkg TOOL: the distro package name (default: the same name)
linux_pkg() {
    case "$(pkg_mgr 2>/dev/null):$1" in
        dnf:sqlite3|yum:sqlite3|pacman:sqlite3) echo sqlite ;;
        dnf:vim|yum:vim)                        echo vim-enhanced ;;
        *)                                      echo "$1" ;;
    esac
}

# pkg_install PKG...: brew on macOS, the distro package manager on Linux.
# ${DRY:-0} skips the install and prints the command. Without root on Linux,
# prints the command to run and returns 1.
pkg_install() {
    local mgr cmd
    if [ "$(uname -s)" = Darwin ]; then
        if [ "${DRY:-0}" -eq 1 ]; then echo "[dry-run] brew install $*"; return 0; fi
        have brew || { echo "Homebrew is missing: install it from https://brew.sh, then re-run." >&2; return 1; }
        brew install "$@"
        return $?
    fi
    mgr="$(pkg_mgr)" || { echo "No supported package manager (apt/dnf/yum/pacman): install $* yourself." >&2; return 1; }
    case "$mgr" in
        apt-get) cmd="apt-get install -y" ;;
        dnf)     cmd="dnf install -y" ;;
        yum)     cmd="yum install -y" ;;
        pacman)  cmd="pacman -S --noconfirm" ;;
    esac
    if [ "${DRY:-0}" -eq 1 ]; then echo "[dry-run] sudo $cmd $*"; return 0; fi
    if ! can_root; then
        echo "Root is needed to install $*, and sudo is not available here." >&2
        echo "  Ask an admin, or run as root:  $cmd $*" >&2
        return 1
    fi
    [ "$mgr" = apt-get ] && as_root apt-get update -qq
    # shellcheck disable=SC2086
    as_root $cmd "$@"
}

# ---- setup-env.sh -------------------------------------------------------------
# Numbered step heading. bootstrap.sh has its own step() and is not compared.
step() { STEP_N=$((STEP_N + 1)); printf '\n%s==> %s. %s%s\n' "$C_B" "$STEP_N" "$*" "$C_0"; }

# setup_log MESSAGE...  -> append "<date> <message>" to $SETUP_ENV_LOG (default
# ~/.setup-env.log). Records every change setup-env.sh, tools/install.sh and
# bin/env-toolcheck.sh make, so you can see which tools were installed when.
setup_log() {
    local f="${SETUP_ENV_LOG:-$HOME/.setup-env.log}"
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$f" 2>/dev/null || true
}

backup() { [ -e "$1" ] || [ -L "$1" ] || return 0; cp -P "$1" "$1.bak-$STAMP" && { ok "Backed up $1 -> $1.bak-$STAMP"; setup_log "BACKUP $1 -> $1.bak-$STAMP"; }; }

# link_to TARGET LINK  -> make LINK a symlink to TARGET, backing up whatever was there
link_to() {
    local target="$1" link="$2"
    if [ -L "$link" ] && [ "$(readlink "$link")" = "$target" ]; then ok "$link already linked"; return 0; fi
    backup "$link"
    rm -rf "$link"
    ln -s "$target" "$link" && { ok "Linked $link -> $target"; setup_log "LINK $link -> $target"; }
}

# env_conf_get KEY [FILE]  -> the value of KEY in env.conf, or nothing.
# Parsed with sed, never sourced: a config file must not be able to run
# commands. Strips a trailing comment, surrounding quotes and trailing spaces.
# The last assignment wins, so an appended line overrides an earlier one.
env_conf_get() {
    local key="$1" f="${2:-}"
    [ -n "$f" ] || return 0
    [ -f "$f" ] || return 0
    sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//p" "$f" \
        | sed -e 's/[[:space:]]*#.*$//' \
              -e 's/^"\(.*\)"$/\1/' \
              -e "s/^'\(.*\)'\$/\1/" \
              -e 's/[[:space:]]*$//' \
        | tail -1
}

# copy_rc SRC DST LABEL  -> install a dotfile as a real COPY, not a symlink.
# Never link an rc file: do_shell appends its "source env.sh" block to ~/.zshrc,
# and appending through a symlink would edit the file inside the repo.
copy_rc() {
    local src="$1" dst="$2" label="$3"
    [ -f "$src" ] || { warn "$src not found; skipping $label."; return 0; }
    if [ ! -e "$dst" ] && [ ! -L "$dst" ]; then
        if confirm "Install $dst from the repo's $label?" Y; then
            cp "$src" "$dst" && { ok "Installed $dst"; setup_log "DOTFILES installed $dst"; }
        else
            ok "Skipped $label."
        fi
        return 0
    fi
    if cmp -s "$src" "$dst"; then ok "$dst already matches the repo"; return 0; fi
    if confirm "$dst exists and differs from the repo's $label. Replace it (a backup is kept)?" N; then
        backup "$dst"
        cp "$src" "$dst" && { ok "Replaced $dst"; setup_log "DOTFILES replaced $dst"; }
    else
        ok "$dst left alone. Machine-specific settings belong in $dst.local, which it sources."
    fi
}

step_enabled() {
    if [ -n "$ONLY" ]; then case " $ONLY " in *" $1 "*) return 0 ;; *) return 1 ;; esac; fi
    case " $SKIP " in *" $1 "*) return 1 ;; *) return 0 ;; esac
}

# Steps after "repo" need a checkout to exist.
need_checkout() { [ -f "$ENV_DIR/env.sh" ] || { warn "$ENV_DIR/env.sh not found (run the repo step first); skipping."; return 1; }; }

do_prereqs() {
    step "Checking prerequisites"
    local tool MISSING=() pk=()
    for tool in git curl gh sqlite3; do
        if have "$tool"; then ok "$tool found"; else warn "$tool missing"; MISSING+=("$tool"); fi
    done
    [ ${#MISSING[@]} -gt 0 ] || return 0
    if confirm "Install ${MISSING[*]} now?" Y; then
        for tool in "${MISSING[@]}"; do
            if [ "$tool" = gh ] && [ "$OS" = Linux ]; then
                # gh has no package on many distros (e.g. RHEL): use the release tarball, no root needed.
                if [ -x "$ENV_DIR/tools/install_gh.sh" ]; then
                    if "$ENV_DIR/tools/install_gh.sh"; then setup_log "PREREQ installed: gh (release tarball)"; else warn "gh install failed."; fi
                    continue
                fi
            fi
            pk+=("$(linux_pkg "$tool")")
        done
        if [ ${#pk[@]} -gt 0 ]; then
            if pkg_install "${pk[@]}"; then setup_log "PREREQ installed: ${pk[*]}"
            else warn "Install failed; continuing with what is available."; fi
        fi
    else
        warn "Skipped. Install hints: macOS 'brew install ${MISSING[*]}', Linux use apt/dnf, or tools/install_<name>.sh after the clone."
    fi
    have git || die "git is required."
}

# env_wire_upstream DIR [OWNER/NAME]: in a clone of a fork, make the original the
# `upstream` remote and disable pushing to it (changes go back through PRs). With
# no OWNER/NAME it asks GitHub for the fork's parent; not a fork = nothing to do.
env_wire_upstream() {
    local dir="$1" up="${2:-}" url o
    have git || return 0
    if ! git -C "$dir" remote get-url upstream >/dev/null 2>&1; then
        o="$(git -C "$dir" remote get-url origin 2>/dev/null | sed -E 's#^(https://[^/]+/|git@[^:]+:|ssh://git@[^/]+/)##; s#\.git$##')"
        if [ -z "$up" ] && [ -n "$o" ] && have gh && gh auth status >/dev/null 2>&1; then
            up="$(gh repo view "$o" --json parent --jq 'if .parent then "\(.parent.owner.login)/\(.parent.name)" else "" end' 2>/dev/null)"
        fi
        [ -n "$up" ] || return 0
        confirm "$o is a fork of $up. Add $up as the 'upstream' remote (pushing to it disabled)?" Y || return 0
        url="https://github.com/$up.git"
        case "$(git -C "$dir" remote get-url origin)" in git@*|ssh://*) url="git@github.com:$up.git" ;; esac
        git -C "$dir" remote add upstream "$url" || { warn "Could not add the upstream remote."; return 0; }
    fi
    git -C "$dir" remote set-url --push upstream no_push--send-changes-with-a-PR || return 0
    ok "upstream = $(git -C "$dir" remote get-url upstream); pushing to it is disabled (use /gu-fork-sync)"
}

# env_wire_upstream_logged DIR [OWNER/NAME]: env_wire_upstream, logging it when it adds the remote.
env_wire_upstream_logged() {
    local had=0
    git -C "$1" remote get-url upstream >/dev/null 2>&1 && had=1
    env_wire_upstream "$@"
    if [ "$had" -eq 0 ] && git -C "$1" remote get-url upstream >/dev/null 2>&1; then
        setup_log "REPO added remote upstream -> $(git -C "$1" remote get-url upstream)"
    fi
}

do_repo() {
    step "Repository"
    if [ -d "$ENV_DIR/.git" ]; then
        ok "Found clone at $ENV_DIR"
        if [ "${ENV_JUST_CLONED:-0}" = 1 ]; then
            ok "Already fetched by bootstrap.sh; not pulling again"
        elif confirm "Pull latest changes (fast-forward only)?" Y; then
            if git -C "$ENV_DIR" pull --ff-only; then setup_log "REPO pulled (fast-forward) $ENV_DIR"
            else warn "Pull failed (see the error above); leaving the clone as is."; fi
        fi
        env_wire_upstream_logged "$ENV_DIR" "${ENV_UPSTREAM:-}"
    elif [ -f "$ENV_DIR/env.sh" ]; then
        ok "Found $ENV_DIR (not a git clone, e.g. from a tarball); updates need a real clone"
    else
        [ -e "$ENV_DIR" ] && [ -n "$(ls -A "$ENV_DIR" 2>/dev/null)" ] && die "$ENV_DIR exists and is not a git clone. Move it or use --dir."
        mkdir -p "$(dirname "$ENV_DIR")"
        local cloned=0
        if have gh; then
            if ! gh auth status >/dev/null 2>&1; then
                warn "Not logged in to GitHub."
                if [ "$HAVE_TTY" -eq 1 ] && confirm "Run 'gh auth login' now?" Y; then
                    gh auth login </dev/tty || warn "gh auth login failed."
                fi
            fi
            if gh auth status >/dev/null 2>&1; then
                gh auth setup-git >/dev/null 2>&1 || true   # let plain git pull/push use gh's token
                gh repo clone "$ENV_REPO" "$ENV_DIR" -- --branch "$ENV_BRANCH" && cloned=1
            fi
        fi
        if [ "$cloned" -eq 0 ]; then
            warn "Trying an anonymous HTTPS clone (works only if the repo is public)."
            GIT_TERMINAL_PROMPT=0 git clone --branch "$ENV_BRANCH" "https://github.com/$ENV_REPO.git" "$ENV_DIR" && cloned=1
        fi
        [ "$cloned" -eq 1 ] || die "Could not clone $ENV_REPO. Install gh, run 'gh auth login', and re-run (or use bootstrap.sh with a token)."
        ok "Cloned to $ENV_DIR"
        setup_log "REPO cloned $ENV_REPO (branch $ENV_BRANCH) to $ENV_DIR"
        env_wire_upstream_logged "$ENV_DIR" "${ENV_UPSTREAM:-}"
    fi
    [ -f "$ENV_DIR/env.sh" ] || die "$ENV_DIR/env.sh not found; is this the right repo?"
}

do_hooks() {
    step "Git pre-commit scan"
    need_checkout || return 0

    # This repo is public, so the cost of one careless commit is permanent. The
    # hook is the local half of the gate; .github/workflows/ci.yml is the other
    # half, and catches anything committed with --no-verify.
    local hooks_dir hook
    hooks_dir="$(cd "$ENV_DIR" 2>/dev/null && git rev-parse --git-path hooks 2>/dev/null)" || hooks_dir=""
    if [ -z "$hooks_dir" ]; then
        warn "$ENV_DIR is not a git repository; skipping the pre-commit hook."
        return 0
    fi
    case "$hooks_dir" in /*) ;; *) hooks_dir="$ENV_DIR/$hooks_dir" ;; esac
    hook="$hooks_dir/pre-commit"

    local want
    want="$(hook_body)"
    if [ -f "$hook" ] && [ "$(cat "$hook" 2>/dev/null)" = "$want" ]; then
        ok "pre-commit hook already installed"
        return 0
    fi
    if [ -e "$hook" ] || [ -L "$hook" ]; then
        confirm "$hook exists. Replace it with the env-scan hook (a backup is kept)?" N || {
            ok "Left $hook alone. Run the scan by hand with: env-scan --staged"
            return 0; }
        backup "$hook"
    else
        confirm "Install a pre-commit hook that blocks commits containing secrets or blocklisted terms?" Y || {
            ok "Skipped the pre-commit hook."
            return 0; }
    fi
    mkdir -p "$hooks_dir"
    printf '%s\n' "$want" > "$hook" && chmod 755 "$hook" \
        && { ok "Installed $hook"; setup_log "HOOKS installed $hook (env-scan --staged)"; }
    [ -f "$ENV_DIR/.blocklist.local" ] \
        || info "No .blocklist.local yet, so your own terms are not checked. Start from blocklist.example."
}

# The pre-commit hook's text. A function so do_hooks can compare what is on
# disk with what it would write, and so stay idempotent.
hook_body() {
    cat <<'HOOK'
#!/bin/sh
# Installed by setup-env.sh (hooks step). Do not edit: it is rewritten.
#
# Refuses a commit whose staged content holds a private key, a token, an
# absolute home path, an email address, or a term from .blocklist.local.
# This repo is public; this hook is what keeps a local-only name out of it.
#
# Bypass for one commit (think first):  git commit --no-verify
root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -f "$root/bin/env-scan" ] || exit 0
exec env BU="$root" bash "$root/bin/env-scan" --staged
HOOK
}

do_host() {
    step "Host paths (.env.host)"
    need_checkout || return 0
    if [ -f "$ENV_DIR/.env.host" ]; then
        ok ".env.host exists; leaving it alone"
        if [ -n "$WORK_OPT" ]; then
            local cur; cur="$(WORK='' bash -c '. "$1/.env.host" 2>/dev/null; echo "${WORK:-}"' _ "$ENV_DIR")"
            [ "$cur" = "$WORK_OPT" ] || warn "--work $WORK_OPT ignored: .env.host has WORK=$cur. Edit $ENV_DIR/.env.host to change it."
        fi
        return 0
    fi
    local W D O
    if [ -n "$WORK_OPT" ]; then W="$WORK_OPT"; ok "WORK = $W (from --work)"
    else W="$(norm_path "$(ask 'Work/projects directory (WORK)' "${WORK:-$HOME/work}")")"; fi
    D="$(ask 'Downloads directory (DL)' "$HOME/Downloads")"
    O="$(ask 'Documents directory (DOCS)' "$HOME/Documents")"
    [ -d "$W" ] || { mkdir -p "$W" && ok "Created $W"; }
    cat > "$ENV_DIR/.env.host" <<EOF
#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File: env/.env.host
# Description: Host-specific path defaults (generated by setup-env.sh)
# -----------------------------------------------------------------------------
# Sourced by env.sh before everything else. Values already exported in your
# shell profile win over these defaults.
# -----------------------------------------------------------------------------

export WORK="\${WORK:-$W}"
export DL="\${DL:-$D}"
export DOCS="\${DOCS:-$O}"

# Editor that opens .code-workspace files from fu-open and go-<project> (macOS app name).
# Cursor is opened through cursor-ide, so it starts in IDE mode.
export EDITOR_APP="\${EDITOR_APP:-Cursor.app}"

# iCloud Drive (macOS only). Left unset elsewhere so consumers can detect it.
if [[ "\$(uname -s)" == "Darwin" ]]; then
    export iDrive="\${iDrive:-\$HOME/Library/Mobile Documents/com~apple~CloudDocs}"
    export iDOC="\${iDOC:-\$iDrive/Documents}"
    export iDownloads="\${iDownloads:-\$iDrive/Downloads}"
fi
EOF
    ok "Wrote $ENV_DIR/.env.host"
    setup_log "HOST wrote $ENV_DIR/.env.host (WORK=$W)"
}

do_shell() {
    step "Shell startup file"
    need_checkout || return 0
    local RC
    case "$(basename "${SHELL:-bash}")" in
        zsh)  RC="$HOME/.zshrc" ;;
        bash) if [ "$OS" = "Darwin" ]; then RC="$HOME/.bash_profile"; else RC="$HOME/.bashrc"; fi ;;
        *)    RC="" ; warn "Login shell ${SHELL:-?} is not bash/zsh; add 'source $ENV_DIR/env.sh' yourself." ;;
    esac
    [ -n "$RC" ] || return 0
    if grep -qsF "$ENV_DIR/env.sh" "$RC"; then
        ok "$RC already sources env.sh"
    elif confirm "Add 'source $ENV_DIR/env.sh' to $RC?" Y; then
        backup "$RC"
        {
            printf '\n# >>> env (setup-env.sh) >>>\n'
            printf '[ -f "%s/env.sh" ] && source "%s/env.sh"\n' "$ENV_DIR" "$ENV_DIR"
            printf '# <<< env (setup-env.sh) <<<\n'
        } >> "$RC"
        ok "Updated $RC"
        setup_log "SHELL added source line for $ENV_DIR/env.sh to $RC"
    fi
}

do_ssh() {
    step "SSH config"
    need_checkout || return 0
    local SSH_SRC="$ENV_DIR/ssh/config"
    if [ ! -f "$SSH_SRC" ]; then
        warn "$SSH_SRC not found; skipping SSH."
    elif confirm "Set up SSH config?" Y; then
        mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"

        # The SSH layout lives in the env-ssh skill's script; reuse it here.
        # ssh/config Includes config.d/<file> relative to ~/.ssh, so ~/.ssh/config.d
        # must link to the repo's ssh/config.d (an old real folder is moved aside).
        env_ssh() { ENV_SSH_ENV_DIR="$ENV_DIR" bash "$ENV_DIR/claude/skills/env-ssh/scripts/env-ssh.sh" "$@" --apply; }
        if env_ssh link-conf-d; then setup_log "SSH linked ~/.ssh/config.d -> $ENV_DIR/ssh/config.d"
        else warn "Linking ~/.ssh/config.d failed (see above)."; fi

        # Per-user settings are git-ignored; ssh/config Includes them first, so they win.
        local USER_CONF="$ENV_DIR/ssh/config.d/local.conf"
        if [ -f "$USER_CONF" ]; then
            ok "$USER_CONF exists; leaving it alone"
        else
            # First existing key wins as the default; the user can override it.
            local DEF_KEY="$HOME/.ssh/id_ed25519" k REMOTE_USER KEY
            for k in id_ed25519 id_rsa id_ecdsa; do
                [ -f "$HOME/.ssh/$k" ] && { DEF_KEY="$HOME/.ssh/$k"; break; }
            done
            REMOTE_USER="$(ask 'Username on your remote hosts' "${USER:-me}")"
            KEY="$(ask 'SSH private key for your remote hosts' "$DEF_KEY")"
            env_ssh user-conf --user "$REMOTE_USER" --key "$KEY" && { ok "Wrote $USER_CONF"; setup_log "SSH wrote $USER_CONF"; }
            [ -f "${KEY/#\~/$HOME}" ] || warn "$KEY does not exist yet. Create one with: ssh-keygen -t ed25519 -C ''"
        fi

        local CFG="$HOME/.ssh/config"
        # Safe to (re)point CFG at the repo when it is missing, a broken link,
        # or a link into this repo (possibly stale after a file move).
        local cfg_is_ours=0
        if [ ! -e "$CFG" ]; then
            cfg_is_ours=1
        elif [ -L "$CFG" ]; then
            case "$(readlink "$CFG")" in "$ENV_DIR"/*) cfg_is_ours=1 ;; esac
        fi
        if [ "$cfg_is_ours" -eq 1 ]; then
            link_to "$SSH_SRC" "$CFG"
        elif grep -qsF "Include $SSH_SRC" "$CFG"; then
            ok "$CFG already includes $SSH_SRC"
        elif confirm "$CFG is your own file. Add 'Include $SSH_SRC' at its top?" Y; then
            backup "$CFG"
            { echo "Include $SSH_SRC"; echo ""; cat "$CFG.bak-$STAMP"; } > "$CFG"
            chmod 600 "$CFG"
            ok "Added Include to $CFG"
            setup_log "SSH added Include $SSH_SRC to $CFG"
        fi

        # ~/.ssh/perms.sh reports and fixes the modes under ~/.ssh. Linked, so the
        # repo stays the one copy.
        if [ -f "$ENV_DIR/.ssh/perms.sh" ]; then
            chmod 700 "$ENV_DIR/.ssh/perms.sh" 2>/dev/null || true
            link_to "$ENV_DIR/.ssh/perms.sh" "$HOME/.ssh/perms.sh"
            info "Check modes any time: ~/.ssh/perms.sh --verify  (add --fix to correct them)"
        fi

        ssh_decrypt_hosts
        ssh_authorize_keys
    fi
}

# gpg_decrypt_to DST ENC -> decrypt ENC to DST. Uses SSH_CONFIG_PASS_FILE when
# set (non-interactive), else prompts through gpg's own pinentry.
gpg_decrypt_to() {
    local dst="$1" enc="$2"
    if [ -n "${SSH_CONFIG_PASS_FILE:-}" ]; then
        gpg --quiet --batch --yes --pinentry-mode loopback \
            --passphrase-file "$SSH_CONFIG_PASS_FILE" --decrypt -o "$dst" "$enc"
    else
        gpg --quiet --decrypt -o "$dst" "$enc"
    fi
}

# Decrypt every published ssh/config.d/*.conf.gpg next to itself. The plaintext
# is git-ignored; the .gpg file is what the repo publishes. Fails closed: a bad
# passphrase leaves no partial file behind.
#
# Remember that ssh/config is an explicit index. A decrypted file does nothing
# until ssh/config has an "Include config.d/<name>" line for it.
ssh_decrypt_hosts() {
    local enc dst tmp found=0
    for enc in "$ENV_DIR"/ssh/config.d/*.conf.gpg; do
        [ -e "$enc" ] || continue
        found=1
        dst="${enc%.gpg}"
        if ! have gpg; then
            warn "gpg not installed; cannot decrypt ${enc#$ENV_DIR/}. Install it and re-run --only ssh."
            return 0
        fi
        # A passphrase needs either a terminal or SSH_CONFIG_PASS_FILE (the same
        # variable scripts/export-ssh-config.sh uses). Without one, skip rather
        # than hang: bootstrap.sh -y and CI run with no terminal.
        if [ "$HAVE_TTY" -eq 0 ] && [ -z "${SSH_CONFIG_PASS_FILE:-}" ]; then
            warn "No terminal and no SSH_CONFIG_PASS_FILE; skipping ${enc#$ENV_DIR/}. Re-run: setup-env.sh --only ssh"
            continue
        fi
        if ! confirm "Decrypt ${enc#$ENV_DIR/} (gpg will ask for the passphrase)?" Y; then
            ok "Skipped ${enc#$ENV_DIR/}."
            continue
        fi
        tmp="$(mktemp)" || { warn "Cannot create a temporary file; skipping ${enc#$ENV_DIR/}."; continue; }
        if gpg_decrypt_to "$tmp" "$enc"; then
            if [ -f "$dst" ] && cmp -s "$tmp" "$dst"; then
                rm -f "$tmp"
                ok "${dst#$ENV_DIR/} already up to date"
            else
                [ -f "$dst" ] && backup "$dst"
                mv "$tmp" "$dst" && chmod 600 "$dst" \
                    && { ok "Wrote ${dst#$ENV_DIR/} (git-ignored)"; setup_log "SSH decrypted ${enc#$ENV_DIR/} -> ${dst#$ENV_DIR/}"; }
            fi
            grep -qsE "^[[:space:]]*Include[[:space:]]+config\.d/$(basename "$dst")([[:space:]]|$)" "$ENV_DIR/ssh/config" \
                || warn "ssh/config has no 'Include config.d/$(basename "$dst")' line, so ssh will not read it."
        else
            rm -f "$tmp"
            warn "Could not decrypt ${enc#$ENV_DIR/} (wrong passphrase?). Nothing was written."
            setup_log "FAILED SSH decrypt ${enc#$ENV_DIR/}"
        fi
    done
    [ "$found" -eq 1 ] || return 0
}

# With --authorize-keys, append the repo's published public keys to
# ~/.ssh/authorized_keys so this machine accepts logins signed by them.
# Off by default: it grants access, so it should never be a side effect.
ssh_authorize_keys() {
    [ "${AUTH_KEYS:-0}" -eq 1 ] || return 0
    local AK="$HOME/.ssh/authorized_keys" k blob n=0
    local -a pubs=()
    for k in "$ENV_DIR"/.ssh/keys/*.pub; do [ -e "$k" ] && pubs+=("$k"); done
    [ "${#pubs[@]}" -gt 0 ] || { warn "No .ssh/keys/*.pub to authorize."; return 0; }
    # Default Y: you already opted in with --authorize-keys, and `confirm ... N`
    # would make the flag a no-op under -y.
    confirm "Append ${#pubs[@]} public key(s) from .ssh/keys/ to $AK? This grants login to whoever holds the matching private keys." Y || {
        ok "Skipped authorized_keys."; return 0; }
    touch "$AK" 2>/dev/null || { warn "Cannot write $AK."; return 0; }
    for k in "${pubs[@]}"; do
        blob="$(awk 'NF>=2 {print $2; exit}' "$k")"
        [ -n "$blob" ] || { warn "$(basename "$k") is not a public key; skipping."; continue; }
        if grep -qF "$blob" "$AK" 2>/dev/null; then
            ok "$(basename "$k") already authorized"
        else
            cat "$k" >> "$AK" && { n=$((n+1)); ok "Authorized $(basename "$k")"; setup_log "SSH authorized $(basename "$k")"; }
        fi
    done
    chmod 600 "$AK"
    [ "$n" -eq 0 ] || info "$n key(s) added to $AK"
}

do_claude() {
    step "Claude Code settings and skills"
    need_checkout || return 0
    # Skills live in the repo's claude/skills/. When ~/.claude is a symlink to the
    # repo's claude/ folder (the normal setup), settings and skills are already in
    # place. Otherwise link settings.json and each skill individually.
    local CLAUDE_HOME="$HOME/.claude" skill
    if [ -L "$CLAUDE_HOME" ] && [ "$(cd "$CLAUDE_HOME" 2>/dev/null && pwd -P)" = "$(cd "$ENV_DIR/claude" 2>/dev/null && pwd -P)" ]; then
        ok "~/.claude is the repo's claude/ folder; settings and skills are already in place"
        info "Terminal claude uses Code Mode when supported (env.CLAUDE_CODE_EXPERIMENTAL_CODE_MODE=1 in settings.json; opt out: cp claude/settings.local.json.example → settings.local.json)"
    elif confirm "Link Claude Code settings.json and skills from the repo?" Y; then
        mkdir -p "$CLAUDE_HOME/skills"
        if [ -f "$ENV_DIR/claude/settings.json" ]; then
            if [ -f "$CLAUDE_HOME/settings.json" ] && [ ! -L "$CLAUDE_HOME/settings.json" ] \
               && ! confirm "Replace your existing ~/.claude/settings.json (a backup is kept)?" N; then
                warn "Kept your settings.json"
            else
                link_to "$ENV_DIR/claude/settings.json" "$CLAUDE_HOME/settings.json"
                info "Code Mode is on in the linked settings (CLAUDE_CODE_EXPERIMENTAL_CODE_MODE=1); use settings.local.json to opt out on this machine"
            fi
        fi
        for skill in "$ENV_DIR"/claude/skills/*/; do
            [ -f "$skill/SKILL.md" ] || continue      # skips synced/ and other app folders
            skill="${skill%/}"
            link_to "$skill" "$CLAUDE_HOME/skills/$(basename "$skill")"
        done
    fi

    # A starter for your own working preferences. Only when you have none, and only if you
    # say yes (default no), so it never changes how Claude behaves on an existing machine.
    local TPL="$ENV_DIR/claude/CLAUDE.md.example"
    if [ -f "$TPL" ] && [ ! -e "$CLAUDE_HOME/CLAUDE.md" ] && [ ! -L "$CLAUDE_HOME/CLAUDE.md" ]; then
        if confirm "Install a starter ~/.claude/CLAUDE.md (your working preferences for Claude; edit it afterwards)?" N; then
            mkdir -p "$CLAUDE_HOME" && cp "$TPL" "$CLAUDE_HOME/CLAUDE.md" && { ok "Installed ~/.claude/CLAUDE.md from claude/CLAUDE.md.example"; setup_log "CLAUDE installed ~/.claude/CLAUDE.md from the example"; }
        fi
    fi
}

do_cursor() {
    step "Cursor settings and IDE mode"
    need_checkout || return 0
    if [ ! -x "$ENV_DIR/bin/cursor-sync" ]; then
        warn "$ENV_DIR/bin/cursor-sync not found; skipping Cursor."
    elif [ -d /Applications/Cursor.app ] || [ -d "$HOME/Applications/Cursor.app" ] || have cursor; then
        if confirm "Link Cursor's settings.json to the repo's cursor/ folder and install its extensions?" Y; then
            # Without --force it leaves a differing settings.json alone (or asks, with a terminal).
            if "$ENV_DIR/bin/cursor-sync" apply; then setup_log "CURSOR ran cursor-sync apply"
            else warn "cursor-sync left something alone (see above)."; fi
        fi
        if [ "$("$ENV_DIR/bin/cursor-ide" --check 2>/dev/null)" = "agent" ]; then
            warn "Cursor will start in Agents mode. Quit Cursor, then run 'cursor' (the cursor-ide alias) to switch it to IDE mode."
        fi
    else
        warn "Cursor is not installed; skipping. Install it (macOS: env-install cursor), then re-run this script."
    fi
}

do_dotfiles() {
    step "Dotfiles (shell rc, vim, git)"
    need_checkout || return 0

    # Portable rc files. Copied, never linked (see copy_rc). Each one sources its
    # own ~/.<name>.local last, which is where employer/machine settings go.
    copy_rc "$ENV_DIR/dotfiles/zshrc"  "$HOME/.zshrc"  "zshrc"
    copy_rc "$ENV_DIR/dotfiles/bashrc" "$HOME/.bashrc" "bashrc"
    copy_rc "$ENV_DIR/dotfiles/cshrc"  "$HOME/.cshrc"  "cshrc (tcsh)"

    # vimrc: only when you have none. Linked, so edits in the repo apply everywhere.
    local VIMRC="$HOME/.vimrc"
    if [ ! -f "$ENV_DIR/dotfiles/vimrc" ]; then
        warn "$ENV_DIR/dotfiles/vimrc not found; skipping vim."
    elif [ -L "$VIMRC" ] && [ "$(readlink "$VIMRC")" = "$ENV_DIR/dotfiles/vimrc" ]; then
        ok "~/.vimrc already linked"
    elif [ -e "$VIMRC" ] || [ -L "$VIMRC" ]; then
        ok "~/.vimrc exists; leaving it alone"
    elif confirm "Link ~/.vimrc to the repo's dotfiles/vimrc (line numbers, 4-space tabs, search highlighting)?" N; then
        link_to "$ENV_DIR/dotfiles/vimrc" "$VIMRC"
    else
        ok "Skipped vim."
    fi

    # gitconfig: written once from the template, never edited afterwards. Needs your
    # identity, so it is skipped without a terminal (-y).
    local GITCFG="$HOME/.gitconfig" TPL="$ENV_DIR/dotfiles/gitconfig.template" GN GE
    if [ ! -f "$TPL" ]; then
        warn "$TPL not found; skipping git."
    elif [ -e "$GITCFG" ] || [ -L "$GITCFG" ]; then
        ok "~/.gitconfig exists; leaving it alone (dotfiles/gitconfig.template shows per-employer includeIf)"
    elif confirm "Create ~/.gitconfig from dotfiles/gitconfig.template (asks your name and email)?" N; then
        GN="$(ask 'Your name for git commits' '')"
        GE="$(ask 'Your email for git commits' '')"
        if [ -z "$GN" ] || [ -z "$GE" ]; then
            warn "Name and email are both needed; ~/.gitconfig not created."
        else
            # git config values: quote them and escape \ and " so any name or email stays valid
            GN="${GN//\\/\\\\}"; GN="\"${GN//\"/\\\"}\""
            GE="${GE//\\/\\\\}"; GE="\"${GE//\"/\\\"}\""
            # Plain-text replacement via awk ENVIRON (sub() would treat '&' in a name as "the match")
            GN="$GN" GE="$GE" awk 'function rep(s, from, to,   i) { i = index(s, from); return i ? substr(s, 1, i - 1) to substr(s, i + length(from)) : s }
                { print rep(rep($0, "YOUR NAME", ENVIRON["GN"]), "YOUR_WORK_EMAIL", ENVIRON["GE"]) }' "$TPL" > "$GITCFG.tmp-$$" \
                && mv "$GITCFG.tmp-$$" "$GITCFG" && { ok "Created ~/.gitconfig"; setup_log "DOTFILES created ~/.gitconfig from the template"; }
        fi
    else
        ok "Skipped git."
    fi
}

# pick_tools: numbered menu of every dev tool with its state on this machine. Prints
# the chosen names (space-separated) on stdout. Accepts numbers, names, and
# "missing" (every tool not installed). Returns 1 on a bad entry.
pick_tools() {
    local t i=0 state ans w n out=""
    local -a names=()
    for t in "${INSTALL_ORDER[@]}"; do names+=("$t"); done
    {
        echo ""
        echo "  Dev tools (number or name; state is as found on this machine):"
        for t in "${names[@]}"; do
            i=$((i + 1))
            if tool_present "$t"; then state="installed ($(tool_version "$t"))"; else state="missing"; fi
            printf '    %2d) %-10s %s\n' "$i" "$t" "$state"
        done
    } >&2
    ans="$(ask "Pick tools: numbers or names, 'missing' for all missing, Enter for none" "")"
    for w in $ans; do
        case "$w" in
            missing) for t in "${names[@]}"; do tool_present "$t" || out="$out $t"; done ;;
            *[!0-9]*)
                case " ${names[*]} " in
                    *" $w "*) out="$out $w" ;;
                    *) err "Unknown tool: $w" ; return 1 ;;
                esac ;;
            *)
                n=$w
                if [ "$n" -ge 1 ] && [ "$n" -le "${#names[@]}" ]; then out="$out ${names[$((n - 1))]}"
                else err "No tool number $n (1-${#names[@]})"; return 1; fi ;;
        esac
    done
    echo "$out"
}

# Dev tools (tools/): choose tools by menu (a terminal, no -y), by --tools LIST, or
# not at all. Each chosen tool runs its installer; an installer leaves a tool that is
# already present alone, so choosing an installed tool is a no-op. Every change is logged.
do_tools() {
    step "Dev tools (tools/)"
    need_checkout || return 0
    local f="$ENV_DIR/tools/install.sh" sel="" t
    if [ ! -x "$f" ]; then warn "$f not found; skipping."; return 0; fi
    # detect.sh gives INSTALL_ORDER, tool_present and tool_version (see tools/detect.sh).
    # shellcheck source=../tools/detect.sh
    . "$ENV_DIR/tools/detect.sh" || { warn "$ENV_DIR/tools/detect.sh did not load; skipping tools."; return 0; }
    if [ -n "$TOOLS_SEL" ]; then
        for t in $TOOLS_SEL; do
            case " ${INSTALL_ORDER[*]} " in *" $t "*) ;; *) warn "Unknown tool '$t' in --tools (choose from: ${INSTALL_ORDER[*]}). No tools installed."; return 0 ;; esac
        done
        sel="$TOOLS_SEL"
    elif [ "$HAVE_TTY" -eq 1 ] && [ "$ASSUME_YES" -eq 0 ]; then
        if ! sel="$(pick_tools)"; then warn "Could not read that choice; no tools installed. Re-run to pick again."; return 0; fi
    else
        "$f" --list
        ok "No tools chosen. Pick them with --tools LIST (e.g. --tools gh,pyenv) or run in a terminal to choose from a menu."
        setup_log "TOOLS none chosen"
        return 0
    fi
    if [ -z "$sel" ]; then ok "No tools chosen."; setup_log "TOOLS none chosen"; return 0; fi
    local -a args=()
    for t in $sel; do args+=(--tool "$t"); done
    setup_log "TOOLS chosen: $sel"
    if "$f" "${args[@]}" -y; then ok "Tools done."
    else warn "Some tools failed to install (see above)."; fi
}

do_shortcuts() {
    step "Desktop shortcuts for the projects in \$WORK"
    need_checkout || return 0
    if [ ! -x "$ENV_DIR/bin/create-work-shortcuts" ]; then
        warn "$ENV_DIR/bin/create-work-shortcuts not found; skipping."
        return 0
    fi
    # .env.host (host step) is where WORK lives; read it the same way env.sh does.
    local SC_WORK SC_DESK="$HOME/Desktop"
    SC_WORK="$(WORK="${WORK_OPT:-${WORK:-}}" bash -c '[ -f "$1/.env.host" ] && . "$1/.env.host"; echo "${WORK:-}"' _ "$ENV_DIR")"
    if [ -z "$SC_WORK" ] || [ ! -d "$SC_WORK" ]; then
        warn "Work directory '${SC_WORK:-unset}' not found; skipping."
    elif [ ! -d "$SC_DESK" ]; then
        ok "No Desktop folder here (headless host?); skipping."
    elif confirm "Create a .code-workspace shortcut on the Desktop for each directory in $SC_WORK?" N; then
        # Never touches hand-made files; add --adopt yourself to take them over.
        if WORK="$SC_WORK" "$ENV_DIR/bin/create-work-shortcuts"; then setup_log "SHORTCUTS ran create-work-shortcuts for $SC_WORK"
        else warn "create-work-shortcuts reported a problem (see above)."; fi
    else
        ok "Skipped. Run 'create-work-shortcuts' (alias wsc) any time."
    fi
}

do_doctor() {
    step "Health report"
    need_checkout || return 0
    if [ -x "$ENV_DIR/bin/env-doctor" ]; then
        BU="$ENV_DIR" "$ENV_DIR/bin/env-doctor" || true
    else
        warn "$ENV_DIR/bin/env-doctor not found; skipping."
    fi
}

# entry is setup-env.sh (its header is what --help prints). The rest are its args.
setup_env_main() {
    SETUP_ENTRY="$1"
    shift

    ENV_REPO_SET="${ENV_REPO:-}"

    # Repo coordinates come from env.conf next to setup-env.sh, so there is one
    # place to change them when you fork. An environment variable still wins.
    # bootstrap.sh runs before any clone exists and so keeps its own default;
    # tests/check-helper-drift.sh asserts the two agree.
    ENV_CONF=""
    if [ -n "$SETUP_ENTRY" ] && [ -f "$SETUP_ENTRY" ]; then
        _ec_dir="$(cd "$(dirname "$SETUP_ENTRY")" && pwd)"
        [ -f "$_ec_dir/env.conf" ] && ENV_CONF="$_ec_dir/env.conf"
        unset _ec_dir
    fi
    _ec_repo="$(env_conf_get ENV_REPO "$ENV_CONF")"
    _ec_branch="$(env_conf_get ENV_BRANCH "$ENV_CONF")"
    _ec_upstream="$(env_conf_get ENV_UPSTREAM "$ENV_CONF")"
    ENV_REPO="${ENV_REPO:-${_ec_repo:-amit-varde/env}}"
    ENV_BRANCH="${ENV_BRANCH:-${_ec_branch:-main}}"
    [ -n "${ENV_UPSTREAM:-}" ] || ENV_UPSTREAM="${_ec_upstream:-}"
    unset _ec_repo _ec_branch _ec_upstream
    WORK_OPT=""
    ASSUME_YES=0
    AUTH_KEYS=0
    ONLY=""
    SKIP=""
    TOOLS_SEL=""
    STAMP="$(date +%Y%m%d-%H%M%S)"
    OS="$(uname -s)"
    # dotfiles runs BEFORE shell on purpose: it may write ~/.zshrc from the
    # template, and shell then appends its source block to that file.
    STEPS="prereqs repo hooks host dotfiles shell ssh claude cursor tools shortcuts doctor"
    STEP_N=0
    if [ -t 1 ]; then
        C_B=$'\033[1m'; C_0=$'\033[0m'
    else
        C_B=""; C_0=""
    fi
    HAVE_TTY=0
    if [ -r /dev/tty ] && { : </dev/tty; } 2>/dev/null; then HAVE_TTY=1; fi

    while [ $# -gt 0 ]; do
        case "$1" in
            -y|--yes) ASSUME_YES=1 ;;
            --authorize-keys) AUTH_KEYS=1 ;;
            -d|--dir)  [ $# -ge 2 ] || die "--dir needs a path"; ENV_DIR="$(norm_path "$2")"; shift ;;
            -w|--work) [ $# -ge 2 ] || die "--work needs a path"; WORK_OPT="$(norm_path "$2")"; shift ;;
            --only)    [ $# -ge 2 ] || die "--only needs a list"; ONLY="$(echo "$2" | tr ',' ' ')"; shift ;;
            --skip)    [ $# -ge 2 ] || die "--skip needs a list"; SKIP="$(echo "$2" | tr ',' ' ')"; shift ;;
            --tools)   [ $# -ge 2 ] || die "--tools needs a list of tool names"; TOOLS_SEL="$(echo "$2" | tr ',' ' ')"; shift ;;
            --list-steps) echo "$STEPS" | tr ' ' '\n'; exit 0 ;;
            -h|--help) awk '/^# -----/{n++; next} n==2 && /^#/{sub(/^# ?/,""); print} n>=3{exit}' \
                           "$SETUP_ENTRY" 2>/dev/null || echo "See the header of setup-env.sh"; exit 0 ;;
            *) die "Unknown option: $1 (try --help)" ;;
        esac
        shift
    done
    for s in $ONLY $SKIP; do
        case " $STEPS " in *" $s "*) ;; *) die "Unknown step '$s'. Steps: $STEPS" ;; esac
    done

    # ENV_DIR: --dir, else $ENV_DIR, else <work>/env (work from --work, $WORK, or ~/work).
    if [ -z "${ENV_DIR:-}" ]; then ENV_DIR="${WORK_OPT:-${WORK:-$HOME/work}}/env"; fi

    # If this script lives in a checkout of the repo, use that checkout.
    # -e, not -d: in a git worktree .git is a FILE pointing at the common dir,
    # and this repo's own worktree flow (gu worktree, docs/worktree-flow.md)
    # means setup-env.sh is often run from one.
    if [ -n "$SETUP_ENTRY" ] && [ -f "$SETUP_ENTRY" ]; then
        SCRIPT_DIR="$(cd "$(dirname "$SETUP_ENTRY")" && pwd)"
        if [ -f "$SCRIPT_DIR/env.sh" ] && [ -e "$SCRIPT_DIR/.git" ]; then ENV_DIR="$SCRIPT_DIR"; fi
    fi
    ENV_DIR="$(norm_path "$ENV_DIR")"
    # The bin/ scripts trust $BU (set by env.sh) to find their repo. Point it at the repo
    # being set up, not at whatever an older install left in the environment.
    export BU="$ENV_DIR"
    # In an existing clone (a fork, say), name the repo it really comes from.
    if [ -z "${ENV_REPO_SET:-}" ] && [ -d "$ENV_DIR/.git" ]; then
        _o="$(git -C "$ENV_DIR" remote get-url origin 2>/dev/null | sed -E 's#^(https://[^/]+/|git@[^:]+:|ssh://git@[^/]+/)##; s#\.git$##')"
        [ -n "$_o" ] && ENV_REPO="$_o"
    fi

    printf '%sEnvironment setup%s  (%s, repo %s -> %s)\n' "$C_B" "$C_0" "$OS" "$ENV_REPO" "$ENV_DIR"
    [ "$HAVE_TTY" -eq 0 ] && warn "No terminal for prompts: using defaults for every question."
    setup_log "SETUP start: repo=$ENV_DIR only=${ONLY:-all} skip=${SKIP:-none} tools=${TOOLS_SEL:-none}"

    for s in $STEPS; do
        step_enabled "$s" && "do_$s"
    done

    # Refresh the tool manifest (~/.setup-env.manifest) from what is installed now.
    if [ -f "$ENV_DIR/tools/detect.sh" ] && . "$ENV_DIR/tools/detect.sh" && manifest_write; then
        ok "Tool manifest: $(manifest_path)"
        setup_log "MANIFEST written: $(manifest_path)"
    fi
    setup_log "SETUP done"

    step "Done"
    echo "  Open a new terminal, or run:  source $ENV_DIR/env.sh"
    echo "  Re-run this script any time; it only changes what is missing."
}
