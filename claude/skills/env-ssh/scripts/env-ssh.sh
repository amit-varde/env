#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File: env-ssh/scripts/env-ssh.sh
# Description: Keep ~/.ssh wired to an env repo's ssh/ folder
# -----------------------------------------------------------------------------
# Usage: env-ssh.sh <command> [args] [--apply]
#
# Commands (all change-making ones are a dry run unless --apply is given):
#   paths                          Print the resolved paths
#   perms                          Check ~/.ssh ownership and modes; --apply chmods
#                                  what is wrong (exit 3 = issues found, dry run)
#   status                         Read-only report: links, Includes, keys
#   link-config                    Link $SSH_HOME/config   -> $REPO_SSH/config
#                                  and  $SSH_HOME/config.d -> $REPO_SSH/config.d
#                                  (an old real config.d dir is moved aside)
#   link-conf-d                    Only the config.d link (setup-env.sh uses
#                                  this; it handles ~/.ssh/config itself)
#   adopt-keys [name.pub ...]      Move public keys into $REPO_SSH, link them back
#   release-keys [name.pub ...]    Undo adopt-keys: copy back, remove from repo
#   user-conf --user U --key K [--hosts "PATTERNS"] [--force]
#                                  Write $REPO_SSH/config.d/local.conf (git-ignored)
#   verify [host ...]              ssh -G summary per host; flags missing keys
#   test <host>                    Non-interactive login test (BatchMode, 8s)
#   cleanup [--keep N] [--delete]  Archive (or delete) old *.bak*/*.old and
#                                  known_hosts.* files, keeping the newest N
#                                  of each; archive is $SSH_HOME/.env-ssh-archive/
#
# Paths (override with environment variables):
#   ENV_DIR   $ENV_SSH_ENV_DIR, else $BU, else the repo holding this skill
#             (if it has env.sh), else ~/work/env
#   SSH_HOME  $ENV_SSH_SSH_HOME, else ~/.ssh
#   REPO_SSH  $ENV_DIR/ssh      (shared config lives in $REPO_SSH/config,
#                                one file per host in $REPO_SSH/config.d/)
#
# Every replaced file is first copied to <file>.bak-<timestamp>.
# Private keys are never moved, copied or read.
# -----------------------------------------------------------------------------

set -uo pipefail

APPLY=0
ARGS=()
for a in "$@"; do
    if [ "$a" = "--apply" ]; then APPLY=1; else ARGS+=("$a"); fi
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

# ---- Resolve paths -----------------------------------------------------------
_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
_guess="$(cd "$_script_dir/../../../.." 2>/dev/null && pwd -P)"   # <repo>/claude/skills/env-ssh/scripts
if   [ -n "${ENV_SSH_ENV_DIR:-}" ]; then ENV_DIR="$ENV_SSH_ENV_DIR"
elif [ -n "${BU:-}" ] && [ -f "$BU/env.sh" ]; then ENV_DIR="$BU"
elif [ -n "$_guess" ] && [ -f "$_guess/env.sh" ]; then ENV_DIR="$_guess"
else ENV_DIR="$HOME/work/env"; fi
SSH_HOME="${ENV_SSH_SSH_HOME:-$HOME/.ssh}"
REPO_SSH="$ENV_DIR/ssh"
REPO_CFG="$REPO_SSH/config"
CONF_D="$REPO_SSH/config.d"          # the real folder, in the repo
SSH_CONF_D="$SSH_HOME/config.d"      # a link to $CONF_D
USER_CONF="$CONF_D/local.conf"       # personal User/IdentityFile, git-ignored
STAMP="$(date +%Y%m%d-%H%M%S)"

if [ -f "$ENV_DIR/lib/common.bash" ]; then
    # shellcheck source=../../../../lib/common.bash
    source "$ENV_DIR/lib/common.bash"
fi

say()  { printf '%s\n' "$*"; }
# run CMD...  -> print it; execute only with --apply
run() {
    if [ "$APPLY" -eq 1 ]; then printf '+ %s\n' "$*"; "$@" || { say "FAILED: $*"; exit 1; }
    else printf 'would run: %s\n' "$*"; fi
}
backup() { if [ -e "$1" ] || [ -L "$1" ]; then run cp -P "$1" "$1.bak-$STAMP"; fi; }
footer() { [ "$APPLY" -eq 1 ] || say "(dry run - re-run with --apply to make these changes)"; }
# file_mode comes from lib/common.bash. A copied script outside the repo still works.
type file_mode >/dev/null 2>&1 || file_mode() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }
# GNU stat first: GNU's -f means "file system" and prints to stdout before failing.
owner_of() { stat -c '%U' "$1" 2>/dev/null || stat -f '%Su' "$1"; }
mtime_of() { { stat -c '' "$1" >/dev/null 2>&1 && date -r "$1" '+%b %e %H:%M'; } 2>/dev/null || stat -f '%Sm' -t '%b %e %H:%M' "$1" 2>/dev/null; }

# Describe what a path is, relative to the repo.
describe() {
    local p="$1" t
    if [ -L "$p" ]; then
        t="$(readlink "$p")"
        if [ ! -e "$p" ]; then echo "BROKEN link -> $t"
        else case "$t" in "$REPO_SSH"/*) echo "linked to repo ($t)";; *) echo "link elsewhere -> $t";; esac; fi
    elif [ -f "$p" ]; then echo "regular file"
    elif [ -e "$p" ]; then echo "exists (not a file)"
    else echo "missing"; fi
}

pub_keys() {   # names of *.pub in SSH_HOME (files or links)
    local f
    for f in "$SSH_HOME"/*.pub; do [ -e "$f" ] || [ -L "$f" ] || continue; basename "$f"; done
}

cmd_paths() {
    say "ENV_DIR   $ENV_DIR"
    say "REPO_SSH  $REPO_SSH"
    say "REPO_CFG  $REPO_CFG"
    say "CONF_D    $CONF_D"
    say "SSH_HOME  $SSH_HOME"
    say "USER_CONF $USER_CONF"
}

# Include arguments in the repo config, in the order ssh reads them.
includes() {
    [ -f "$REPO_CFG" ] || return 0
    awk 'tolower($1)=="include"{for(i=2;i<=NF;i++) print $i}' "$REPO_CFG"
}
# Where an Include argument points: relative paths are under ~/.ssh, and
# ~/.ssh/config.d is the repo's config.d, so map config.d/x to $CONF_D/x.
include_path() {
    case "$1" in
        /*) echo "$1" ;;
        "~/.ssh/config.d/"*) echo "$CONF_D/${1#"~/.ssh/config.d/"}" ;;
        "~/"*) echo "$HOME/${1#"~/"}" ;;
        config.d/*) echo "$CONF_D/${1#config.d/}" ;;
        *) echo "$SSH_HOME/$1" ;;
    esac
}

cmd_status() {
    cmd_paths; say ""
    [ -d "$ENV_DIR/.git" ] || say "WARN: $ENV_DIR is not a git repo"
    [ -f "$REPO_CFG" ] && say "repo config: present" || say "repo config: MISSING ($REPO_CFG)"
    say "$SSH_HOME/config: $(describe "$SSH_HOME/config")"
    if [ -f "$REPO_CFG" ] && [ ! -L "$SSH_HOME/config" ] && [ -f "$SSH_HOME/config" ]; then
        grep -qsF "Include $REPO_CFG" "$SSH_HOME/config" && say "  (it Includes the repo config)"
    fi
    say "$SSH_CONF_D: $(describe "$SSH_CONF_D")"
    [ -L "$SSH_CONF_D" ] && [ "$(readlink "$SSH_CONF_D")" = "$CONF_D" ] \
        || say "  (should be a link to $CONF_D - see: link-config)"
    say ""
    say "Includes in $REPO_CFG (read in this order):"
    local inc p listed="" any=0
    for inc in $(includes); do
        any=1; p="$(include_path "$inc")"; listed="$listed $p"
        if [ -f "$p" ]; then say "  $inc: present"
        elif [ "$p" = "$USER_CONF" ]; then say "  $inc: MISSING (no personal user/key yet - see: user-conf)"
        else say "  $inc: MISSING ($p)"; fi
    done
    [ "$any" -eq 1 ] || say "  (none)"
    for p in "$CONF_D"/*.conf; do
        [ -f "$p" ] || continue
        case " $listed " in *" $p "*) ;; *) say "  NOT INCLUDED: $p (ssh ignores it until ssh/config has an Include for it)";; esac
    done
    if [ -f "$USER_CONF" ]; then
        say "local.conf settings:"
        grep -E '^\s*(Host|User|IdentityFile)\b' "$USER_CONF" | sed 's/^/    /'
    fi
    say ""
    say "public keys in $SSH_HOME:"
    local k any=0
    for k in $(pub_keys); do any=1; say "  $k: $(describe "$SSH_HOME/$k")"; done
    [ "$any" -eq 1 ] || say "  (none)"
    say "public keys in $REPO_SSH:"
    any=0
    for k in "$REPO_SSH"/*.pub; do [ -f "$k" ] || continue; any=1; k="$(basename "$k")"
        [ -L "$SSH_HOME/$k" ] || say "  $k: NOT linked from $SSH_HOME"; done
    say "private keys (names only):"
    for k in $(pub_keys); do
        k="${k%.pub}"
        if [ -f "$SSH_HOME/$k" ]; then say "  $k: present (mode $(file_mode "$SSH_HOME/$k"))"
        else say "  $k: MISSING for $k.pub"; fi
    done
    say ""
    if [ -d "$ENV_DIR/.git" ]; then
        if git -C "$ENV_DIR" check-ignore -q "ssh/x.pub"; then say "git: ssh/*.pub ignored"
        else say "git: ssh/*.pub NOT ignored (public keys would be committable)"; fi
        if git -C "$ENV_DIR" check-ignore -q "ssh/config.d/local.conf"; then say "git: ssh/config.d/local.conf ignored"
        else say "git: ssh/config.d/local.conf NOT ignored (your user/key would be committable)"; fi
    fi
    local nclean; nclean="$(cleanup_candidates | grep -c .)"
    say "old backup / known_hosts.* files: $nclean (see: cleanup)"
    if [ -f "$REPO_CFG" ]; then
        if ssh -G -F "$REPO_CFG" localhost >/dev/null 2>&1; then say "repo config parses OK"
        else say "repo config PARSE ERROR:"; ssh -G -F "$REPO_CFG" localhost 2>&1 | head -5 | sed 's/^/  /'; fi
    fi
}

# link_path TARGET LINK  -> make LINK a symlink to TARGET. A regular file is
# backed up; a real directory is moved aside to LINK.bak-<stamp>.
link_path() {
    local target="$1" link="$2" f
    if [ -L "$link" ] && [ "$(readlink "$link")" = "$target" ]; then say "$link already linked."; return; fi
    say "$link is: $(describe "$link")"
    if [ -d "$link" ] && [ ! -L "$link" ]; then
        say "  it holds:"; ls -1A "$link" | sed 's/^/    /'
        for f in "$link"/*.conf; do
            [ -f "$f" ] || continue
            say "  settings in $(basename "$f") (carry them into local.conf or a host file):"
            grep -E '^\s*(Host|User|IdentityFile|HostName)\b' "$f" | sed 's/^/    /'
        done
        run mv "$link" "$link.bak-$STAMP"
    else
        backup "$link"
        run rm -f "$link"
    fi
    run ln -s "$target" "$link"
}

# config.d must be a link: ssh/config Includes config.d/<file> relative to ~/.ssh.
link_conf_d() {
    [ -d "$CONF_D" ] || { say "No $CONF_D to link to."; exit 1; }
    [ -d "$SSH_HOME" ] || { run mkdir -p "$SSH_HOME"; run chmod 700 "$SSH_HOME"; }
    link_path "$CONF_D" "$SSH_CONF_D"
}

cmd_link_config() {
    [ -f "$REPO_CFG" ] || { say "No $REPO_CFG to link to."; exit 1; }
    [ -d "$CONF_D" ] || { say "No $CONF_D to link to."; exit 1; }
    if [ ! -L "$SSH_HOME/config" ] && [ -f "$SSH_HOME/config" ] && grep -qsF "Include $REPO_CFG" "$SSH_HOME/config"; then
        say "$SSH_HOME/config is your own file and Includes the repo config; leaving it."
    else
        [ -d "$SSH_HOME" ] || { run mkdir -p "$SSH_HOME"; run chmod 700 "$SSH_HOME"; }
        link_path "$REPO_CFG" "$SSH_HOME/config"
    fi
    link_conf_d
    footer
}

cmd_adopt_keys() {
    local names="$*" k src dst
    [ -n "$names" ] || names="$(pub_keys)"
    run mkdir -p "$REPO_SSH"
    for k in $names; do
        case "$k" in *.pub) ;; *) say "skip $k: not a .pub file"; continue;; esac
        src="$SSH_HOME/$k"; dst="$REPO_SSH/$k"
        if [ -L "$src" ]; then say "skip $k: already a link ($(describe "$src"))"; continue; fi
        [ -f "$src" ] || { say "skip $k: not found"; continue; }
        if [ -e "$dst" ]; then
            if cmp -s "$src" "$dst"; then say "$k: identical copy already in repo; replacing $src with a link"
                backup "$src"; run rm -f "$src"; run ln -s "$dst" "$src"; continue
            fi
            say "skip $k: a DIFFERENT $dst already exists - resolve by hand"; continue
        fi
        run mv "$src" "$dst"
        run ln -s "$dst" "$src"
    done
    footer
}

cmd_release_keys() {
    local names="$*" k src dst
    [ -n "$names" ] || { for k in "$REPO_SSH"/*.pub; do [ -f "$k" ] && names="$names $(basename "$k")"; done; }
    for k in $names; do
        src="$SSH_HOME/$k"; dst="$REPO_SSH/$k"
        [ -f "$dst" ] || { say "skip $k: not in repo"; continue; }
        if [ -L "$src" ] && [ "$(readlink "$src")" = "$dst" ]; then run rm -f "$src"
        elif [ -e "$src" ]; then say "skip $k: $src is not a link to the repo"; continue; fi
        run mv "$dst" "$src"
    done
    footer
}

cmd_user_conf() {
    local user="" key="" force=0 hosts="*"
    while [ $# -gt 0 ]; do
        case "$1" in
            --hosts) hosts="${2:-}"; shift ;;
            --user) user="${2:-}"; shift ;;
            --key)  key="${2:-}"; shift ;;
            --force) force=1 ;;
            *) say "unknown option $1"; exit 2 ;;
        esac; shift
    done
    [ -n "$user" ] && [ -n "$key" ] || { say "need --user and --key"; exit 2; }
    key="${key/#\~/$HOME}"
    if [ -f "$USER_CONF" ] && [ "$force" -eq 0 ]; then say "$USER_CONF exists; pass --force to replace it."; exit 1; fi
    [ -f "$key" ] || say "WARN: $key does not exist"
    local body
    body="# -----------------------------------------------------------------------------
# File: env/ssh/config.d/local.conf   (git-ignored; this machine only)
# Generated by env-ssh on $(date +%Y-%m-%d). Edit freely.
# Included by: env/ssh/config  (Include config.d/local.conf), FIRST, so the
# User and IdentityFile here win over every host file.
# -----------------------------------------------------------------------------

Host $hosts
    User $user
    IdentityFile $key"
    [ "$(uname -s)" = "Darwin" ] && body="$body
    XAuthLocation /opt/X11/bin/xauth"
    say "--- $USER_CONF ---"; say "$body"; say "---"
    [ -d "$CONF_D" ] || run mkdir -p "$CONF_D"
    backup "$USER_CONF"
    if [ "$APPLY" -eq 1 ]; then printf '%s\n' "$body" > "$USER_CONF" && chmod 600 "$USER_CONF" && say "+ wrote $USER_CONF"
    else say "would write: $USER_CONF (mode 600)"; fi
    footer
}

cmd_verify() {
    local hosts="$*" h out idf
    if [ -z "$hosts" ]; then   # the first name of each Host line in the included files
        local inc p
        for inc in $(includes); do
            p="$(include_path "$inc")"; [ -f "$p" ] || continue
            hosts="$hosts $(awk 'tolower($1)=="host" && $2 !~ /[*!?]/ {print $2}' "$p")"
        done
    fi
    [ -n "$hosts" ] || { say "No concrete hosts found; pass host names."; return; }
    for h in $hosts; do
        out="$(ssh -G "$h" 2>&1)" || { say "$h: ssh -G failed: $out"; continue; }
        say "$h -> $(echo "$out" | awk '$1=="user"{u=$2} $1=="hostname"{n=$2} END{print u"@"n}')"
        echo "$out" | awk '$1=="identityfile"{print $2}' | while read -r idf; do
            idf="${idf/#\~/$HOME}"
            if [ -f "$idf" ]; then say "    key $idf"; else say "    key $idf (missing - ssh skips it)"; fi
        done
    done
}

# ---- Permissions ---------------------------------------------------------------
# ssh refuses keys and configs that others can read/write ("UNPROTECTED PRIVATE
# KEY FILE", "Bad owner or permissions"). Rules, as the most permissive allowed mode:
#   ~/.ssh, archive dirs  700               private keys, authorized_keys  600
#   config (and its link target)  644 but recommend 600
#   repo config.d dir  755, its *.conf  644 (shared; must not be g/o-writable)
#   config.d/local.conf  644 but recommend 600
#   *.pub, known_hosts*            644      anything else in ~/.ssh: not g/o-writable
PERM_ISSUES=0
# perm_check PATH MAX_MODE FIX_MODE LABEL  (PATH followed if it is a link)
perm_check() {
    local p="$1" max="$2" fix="$3" label="$4" real m o
    [ -e "$p" ] || return 0
    real="$p"; [ -L "$p" ] && real="$(cd "$(dirname "$p")" && cd "$(dirname "$(readlink "$p")")" 2>/dev/null && pwd -P)/$(basename "$(readlink "$p")")"
    m="$(file_mode "$real")"; o="$(owner_of "$real")"
    if [ "$o" != "$(id -un)" ] && [ "$o" != "root" ]; then
        say "  BAD   $real owned by $o ($label) - fix by hand: chown $(id -un) \"$real\""; PERM_ISSUES=$((PERM_ISSUES+1))
    fi
    if [ $(( 8#$m & ~8#$max )) -ne 0 ]; then
        say "  FIX   $real is $m, want $fix ($label)"; PERM_ISSUES=$((PERM_ISSUES+1))
        run chmod "$fix" "$real"
    else
        say "  ok    $real $m ($label)"
    fi
}

cmd_perms() {
    local f b
    PERM_ISSUES=0
    say "Permissions in $SSH_HOME (owner must be $(id -un)):"
    [ -d "$SSH_HOME" ] || { say "  $SSH_HOME does not exist"; return 0; }
    perm_check "$SSH_HOME" 700 700 "ssh dir"
    if [ -L "$SSH_CONF_D" ]; then
        [ -d "$CONF_D" ] && perm_check "$CONF_D" 755 "go-w" "repo config.d"
        for f in "$CONF_D"/*.conf; do
            [ -f "$f" ] || continue
            if [ "$f" = "$USER_CONF" ]; then perm_check "$f" 644 600 "local.conf"
            else perm_check "$f" 644 "go-w" "host file"; fi
        done
    elif [ -d "$SSH_CONF_D" ]; then   # old layout: a real folder in ~/.ssh
        perm_check "$SSH_CONF_D" 700 700 "config.d (old layout)"
        for f in "$SSH_CONF_D"/*.conf; do [ -f "$f" ] && perm_check "$f" 644 600 "config.d file"; done
    fi
    [ -d "$SSH_HOME/.env-ssh-archive" ] && perm_check "$SSH_HOME/.env-ssh-archive" 700 700 "archive"
    perm_check "$SSH_HOME/config" 644 600 "config"
    perm_check "$SSH_HOME/authorized_keys" 600 600 "authorized_keys"
    for f in "$SSH_HOME"/*; do
        [ -e "$f" ] || continue
        b="$(basename "$f")"
        [ -d "$f" ] && [ ! -L "$f" ] && continue
        case "$b" in
            config|config.d|authorized_keys) ;;                          # done above
            *.pub)                perm_check "$f" 644 644 "public key" ;;
            known_hosts*|google_compute_known_hosts) perm_check "$f" 644 644 "known hosts" ;;
            *.bak|*.bak-*|*.bak.*|*.old) perm_check "$f" 600 600 "backup" ;;
            *)  if [ -e "$f.pub" ] || [ -L "$f.pub" ] || case "$b" in id_*|google_compute_engine) true;; *) false;; esac; then
                    perm_check "$f" 600 600 "private key"
                else
                    perm_check "$f" 755 "go-w" "other file"
                fi ;;
        esac
    done
    if [ "$PERM_ISSUES" -eq 0 ]; then say "Permissions OK."; return 0; fi
    say "$PERM_ISSUES permission issue(s)."
    footer
    [ "$APPLY" -eq 1 ] || return 3
}

# Backup and stale known_hosts files in SSH_HOME and the repo config.d, newest
# first (including a config.d.bak-* folder left by link-config).
# Matches *.bak, *.bak-*, *.bak.*, *.old, known_hosts.* (never known_hosts itself,
# google_compute_known_hosts, keys, or the archive folder).
cleanup_candidates() {
    local d f
    for d in "$SSH_HOME" "$CONF_D"; do
        [ -d "$d" ] || continue
        ( cd "$d" && ls -1t 2>/dev/null ) | while read -r f; do
            case "$f" in
                *.bak|*.bak-*|*.bak.*|*.old|known_hosts.*) echo "$d/$f" ;;
            esac
        done
    done
}
# Group name used by --keep: the file name up to its backup suffix.
cleanup_base() { local b; b="$(basename "$1")"; b="${b%%.bak*}"; b="${b%.old}"; echo "$(dirname "$1")/${b%%.[0-9]*}"; }

cmd_cleanup() {
    local keep=0 mode=archive f base seen="" n line
    while [ $# -gt 0 ]; do
        case "$1" in
            --keep) keep="${2:-0}"; shift ;;
            --delete) mode=delete ;;
            *) say "unknown option $1"; exit 2 ;;
        esac; shift
    done
    local list removes=""; list="$(cleanup_candidates)"
    [ -n "$list" ] || { say "Nothing to clean up in $SSH_HOME."; return; }
    local archive="$SSH_HOME/.env-ssh-archive/$STAMP"
    say "Candidates (newest first; keep=$keep per file, mode=$mode):"
    while read -r f; do
        [ -n "$f" ] || continue
        base="$(cleanup_base "$f")"
        n="$(printf '%s\n' "$seen" | grep -cxF "$base")"
        seen="$seen
$base"
        line="$(mtime_of "$f")"
        if [ "$n" -lt "$keep" ]; then say "  keep    $f  ($line)"; continue; fi
        say "  remove  $f  ($line)"
        removes="$removes
$f"
    done <<EOF
$list
EOF
    [ -n "$removes" ] || { say "Nothing beyond the kept files."; return; }
    [ "$mode" = "archive" ] && run mkdir -p "$archive"
    while read -r f; do
        [ -n "$f" ] || continue
        if [ "$mode" = "archive" ]; then run mv "$f" "$archive/"
        elif [ -d "$f" ] && [ ! -L "$f" ]; then run rm -rf "$f"
        else run rm -f "$f"; fi
    done <<EOF
$removes
EOF
    [ "$mode" = "archive" ] && say "Archive: $archive (delete it later with: rm -rf \"$SSH_HOME/.env-ssh-archive\")"
    footer
}

cmd_test() {
    [ $# -ge 1 ] || { say "usage: test <host>"; exit 2; }
    say "Testing $1 (no prompts, 8s timeout)..."
    if ssh -o BatchMode=yes -o ConnectTimeout=8 "$1" true 2>&1; then say "OK: logged in to $1"
    else say "FAILED: see the error above"; exit 1; fi
}

case "${1:-}" in
    paths)        cmd_paths ;;
    status)       cmd_status ;;
    link-config)  cmd_link_config ;;
    link-conf-d)  link_conf_d; footer ;;
    adopt-keys)   shift; cmd_adopt_keys "$@" ;;
    release-keys) shift; cmd_release_keys "$@" ;;
    user-conf)    shift; cmd_user_conf "$@" ;;
    verify)       shift; cmd_verify "$@" ;;
    test)         shift; cmd_test "$@" ;;
    cleanup)      shift; cmd_cleanup "$@" ;;
    perms)        cmd_perms; exit $? ;;
    *) sed -n '6,/^# ----/{/^# ----/d;s/^# \{0,1\}//;p;}' "${BASH_SOURCE[0]}"; exit 2 ;;
esac
