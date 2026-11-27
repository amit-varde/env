#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File: env/bootstrap.sh
# Description: Download this file, run it, answer a few questions. It sets up
#              the env repo on a Mac or a Linux box (interactive).
# -----------------------------------------------------------------------------
# This is the one entry point. It is a standalone file: it does not need the
# repo to exist yet, and it hands off to the repo's setup-env.sh once it has
# cloned it.
#
# Get it (the repo is private, so a plain curl of the raw URL will not work):
#   gh api repos/amit-varde/env/contents/bootstrap.sh --jq .content | base64 -d > bootstrap.sh
#   or the Raw / Download button on GitHub
#   or: curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" \
#         -H "Accept: application/vnd.github.raw" \
#         https://api.github.com/repos/amit-varde/env/contents/bootstrap.sh -o bootstrap.sh
# Read it, then run:   bash bootstrap.sh
#
# Questions it asks (Enter accepts the [default]):
#   1. Work/projects directory (WORK)        [~/work]
#   2. Where the env repo should live        [$WORK/env]
#   3. GitHub repo to clone, and branch      [amit-varde/env] [main]
#   4. A summary, then "Proceed?"
#   After GitHub login: "Fork it into your account?" [Y unless you own the repo],
#   then the fork's owner [your login] and name [env]. A fork is your own copy
#   on GitHub; the original becomes the `upstream` remote, with pushing to it
#   disabled. /gu-fork-sync moves changes between the two through PRs.
#
# Then it: checks git, curl, gh and sqlite3 (offers to install what is missing),
# gets GitHub access (gh login, or a token you paste; the token is used for the
# clone only and never written to disk), clones the repo (a tarball if git is
# unavailable), and runs <repo>/setup-env.sh with your answers, so you are not
# asked for WORK twice. Re-run it any time; it only fills in what is missing.
#
# Options:
#   --work PATH      WORK directory (skips question 1)
#   --dir PATH       Where the repo lives (skips question 2)
#   --repo OWNER/NAME  GitHub repo (skips question 3)
#   --branch NAME    Branch (skips question 3)
#   --fork           Fork the repo into your GitHub account and clone the fork
#   --no-fork        Clone the repo itself (the default with -y)
#   --fork-org ORG   Create the fork in this organization instead of your account
#   --fork-name NAME Name of the fork (default: the repo's name)
#   -y, --yes        Accept every default, no questions
#   -h, --help       Show this help
#   -- ARGS...       Anything after -- is passed to setup-env.sh
#
# Environment: ENV_REPO, ENV_BRANCH, ENV_FORK (1, 0 or auto), GITHUB_TOKEN (used for the clone only),
#   ENV_REPO_URL (a full git URL or path instead of github.com/<ENV_REPO>; for
#   forks on other hosts and for testing)
# -----------------------------------------------------------------------------

set -uo pipefail

ENV_REPO="${ENV_REPO:-amit-varde/env}"
ENV_BRANCH="${ENV_BRANCH:-main}"
ENV_REPO_URL="${ENV_REPO_URL:-}"
ENV_FORK="${ENV_FORK:-auto}"
FORK_ORG=""
FORK_NAME=""
ENV_UPSTREAM=""
WORK_DIR=""
ENV_DIR=""
ASSUME_YES=0
PASS_ARGS=()
OS="$(uname -s)"

# ---- Output helpers (same text as lib/common.bash; tests/check-helper-drift.sh) ----
if [ -t 1 ]; then
    C_B=$'\033[1m'; C_0=$'\033[0m'
else
    C_B=""; C_0=""
fi
step() { printf '\n%s==> %s%s\n' "$C_B" "$*" "$C_0"; }
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
success() {
    if [[ "${BU_VERBOSE_LEVEL:-0}" -ge 0 ]]; then
        echo -e "${SUCCESS_COLOR:-\033[0;32m}$(_get_timestamp)$*${RESET:-\033[0m}"
    fi
}
ok() { success "$@"; }
warn() {
    if [[ "${BU_VERBOSE_LEVEL:-0}" -ge 0 ]]; then
        echo -e "${WARN_COLOR:-\033[0;33m}$(_get_timestamp)Warning: $*${RESET:-\033[0m}" >&2
    fi
}
die() { err "$@"; exit 1; }

# Prompts read from /dev/tty so they still work when the script is piped.
HAVE_TTY=0
if [ -r /dev/tty ] && { : </dev/tty; } 2>/dev/null; then HAVE_TTY=1; fi

# ask "Question" default  -> echoes the answer (default when non-interactive)
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

have() { command -v "$1" >/dev/null 2>&1; }

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

# ---- Arguments ---------------------------------------------------------------
usage() {
    awk '/^# -----/{n++; next} n==2 && /^#/{sub(/^# ?/,""); print} n>=3{exit}' "${BASH_SOURCE[0]:-$0}" 2>/dev/null \
        || echo "See the header of bootstrap.sh"
}
while [ $# -gt 0 ]; do
    case "$1" in
        --work)   [ $# -ge 2 ] || die "--work needs a path";   WORK_DIR="$2"; shift ;;
        --dir)    [ $# -ge 2 ] || die "--dir needs a path";    ENV_DIR="$2"; shift ;;
        --repo)   [ $# -ge 2 ] || die "--repo needs OWNER/NAME"; ENV_REPO="$2"; shift ;;
        --branch) [ $# -ge 2 ] || die "--branch needs a name"; ENV_BRANCH="$2"; shift ;;
        --fork)   ENV_FORK=1 ;;
        --no-fork) ENV_FORK=0 ;;
        --fork-org)  [ $# -ge 2 ] || die "--fork-org needs a name"; FORK_ORG="$2"; ENV_FORK=1; shift ;;
        --fork-name) [ $# -ge 2 ] || die "--fork-name needs a name"; FORK_NAME="$2"; ENV_FORK=1; shift ;;
        -y|--yes) ASSUME_YES=1 ;;
        -h|--help) usage; exit 0 ;;
        --) shift; PASS_ARGS=("$@"); break ;;
        *) die "Unknown option: $1 (try --help)" ;;
    esac
    shift
done
case "$ENV_FORK" in 1|0|auto) ;; *) die "ENV_FORK must be 1, 0 or auto (got $ENV_FORK)" ;; esac
# -y never forks unless asked to; a fork through a full git URL is not possible.
[ "$ENV_FORK" = auto ] && [ "$ASSUME_YES" -eq 1 ] && ENV_FORK=0
if [ -n "$ENV_REPO_URL" ]; then
    [ "$ENV_FORK" = 1 ] && die "--fork needs a GitHub repo (OWNER/NAME), not ENV_REPO_URL."
    ENV_FORK=0
fi
# Remember which questions were answered on the command line (they are not asked).
GIVEN_WORK=0; [ -n "$WORK_DIR" ] && GIVEN_WORK=1
GIVEN_DIR=0;  [ -n "$ENV_DIR" ]  && GIVEN_DIR=1

# norm_path P -> absolute path: ~ expanded, relative made absolute, no trailing slash
norm_path() {
    local p="$1"
    p="${p/#\~/$HOME}"
    case "$p" in /*) ;; *) p="$PWD/$p" ;; esac
    while [ "${#p}" -gt 1 ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done
    printf '%s' "$p"
}

# Running from inside a clone (./bootstrap.sh in the repo)? Then that clone is the repo.
SELF_CLONE=""
SELF_PATH="${BASH_SOURCE[0]:-}"
if [ -n "$SELF_PATH" ] && [ -f "$SELF_PATH" ]; then
    SELF_DIR="$(cd "$(dirname "$SELF_PATH")" && pwd)"
    if [ -f "$SELF_DIR/setup-env.sh" ] && [ -f "$SELF_DIR/env.sh" ] && [ -d "$SELF_DIR/.git" ]; then SELF_CLONE="$SELF_DIR"; fi
fi

printf '%sEnvironment bootstrap%s  (%s)\n' "$C_B" "$C_0" "$OS"
[ "$HAVE_TTY" -eq 0 ] && warn "No terminal for prompts: using defaults for every question."

# ---- 1-4. Questions ----------------------------------------------------------
step "1. Where do you keep your projects?"
if [ "$GIVEN_WORK" -eq 0 ]; then
    WORK_DIR="$(ask 'Work/projects directory (WORK)' "${WORK:-$HOME/work}")"
fi
WORK_DIR="$(norm_path "$WORK_DIR")"
if [ -e "$WORK_DIR" ] && [ ! -d "$WORK_DIR" ]; then
    die "$WORK_DIR exists but is not a directory. Pick another path."
fi
if [ ! -d "$WORK_DIR" ]; then
    if confirm "$WORK_DIR does not exist. Create it?" Y; then
        mkdir -p "$WORK_DIR" || die "Could not create $WORK_DIR"
        ok "Created $WORK_DIR"
    else
        die "Cannot continue without a work directory."
    fi
else
    ok "$WORK_DIR exists"
fi
WORK_DIR="$(cd "$WORK_DIR" && pwd)"

step "2. Where should the env repo live?"
if [ "$GIVEN_DIR" -eq 0 ]; then
    if [ -n "$SELF_CLONE" ]; then DEF_DIR="$SELF_CLONE"; else DEF_DIR="${WORK_DIR}/env"; fi
    ENV_DIR="$(ask 'Env repo location' "$DEF_DIR")"
fi
ENV_DIR="$(norm_path "$ENV_DIR")"
if [ -e "$ENV_DIR" ] && [ ! -d "$ENV_DIR" ]; then die "$ENV_DIR exists but is not a directory."; fi
if [ -d "$ENV_DIR" ] && [ ! -d "$ENV_DIR/.git" ] && [ -n "$(ls -A "$ENV_DIR" 2>/dev/null)" ]; then
    die "$ENV_DIR exists, is not empty and is not a git clone. Move it or choose another location."
fi

step "3. Which repo?"
if [ -z "$ENV_REPO_URL" ]; then
    ENV_REPO="$(ask 'GitHub repo to clone (OWNER/NAME)' "$ENV_REPO")"
    ENV_BRANCH="$(ask 'Branch' "$ENV_BRANCH")"
fi

step "4. Summary"
SHELL_NAME="$(basename "${SHELL:-unknown}")"
printf '  %-10s %s\n' "OS" "$OS ($(uname -m)), shell $SHELL_NAME" \
    "WORK" "$WORK_DIR" "Env repo" "$ENV_DIR" "Source" "${ENV_REPO_URL:-github.com/$ENV_REPO} ($ENV_BRANCH)"
if [ ! -d "$ENV_DIR/.git" ]; then
    case "$ENV_FORK" in
        1) printf '  %-10s %s\n' "Fork" "yes, into ${FORK_ORG:-your account} as ${FORK_NAME:-${ENV_REPO#*/}}" ;;
        auto) printf '  %-10s %s\n' "Fork" "asked after GitHub login (default: yes, unless you own $ENV_REPO)" ;;
    esac
fi
confirm "Proceed?" Y || die "Cancelled. Nothing was changed except directories you agreed to create."

# ---- Prerequisites -----------------------------------------------------------
# In-repo installs use pkg_install in lib/common.bash (brew on macOS, the
# distro package manager on Linux). This copy stays here because bootstrap.sh
# runs before the repo exists, so it is not compared with common.bash.
pkg_install() {
    local cmd
    case "$OS" in
        Darwin)
            have brew || { warn "Homebrew is missing: install it from https://brew.sh, then re-run."; return 1; }
            brew install "$@"; return ;;
        Linux)
            if   have apt-get; then cmd="apt-get install -y"
            elif have dnf;     then cmd="dnf install -y"
            elif have yum;     then cmd="yum install -y"
            elif have pacman;  then cmd="pacman -S --noconfirm"
            else warn "Unknown package manager: install $* yourself."; return 1; fi
            if [ "$(id -u)" -ne 0 ]; then
                if have sudo && { sudo -n true 2>/dev/null || [ "$HAVE_TTY" -eq 1 ]; }; then cmd="sudo $cmd"
                else warn "Root is needed to install $*. As root run: $cmd $*"; return 1; fi
            fi
            [ "${cmd#*apt-get}" != "$cmd" ] && ${cmd%% install*} update -qq
            # shellcheck disable=SC2086
            $cmd "$@" ;;
        *) warn "Unsupported OS $OS: install $* yourself."; return 1 ;;
    esac
}

# Package name for a tool (RHEL-family calls sqlite3 "sqlite")
pkg_for() {
    case "$1:$OS" in
        sqlite3:Linux) if have dnf || have yum || have pacman; then echo sqlite; else echo sqlite3; fi ;;
        *) echo "$1" ;;
    esac
}

# gh on Linux: the official tarball in ~/.local (works without root and on distros with no gh package)
install_gh_linux() {
    local arch tag ver dest
    have curl && have tar || { warn "curl and tar are needed to install gh."; return 1; }
    case "$(uname -m)" in x86_64|amd64) arch=amd64 ;; aarch64|arm64) arch=arm64 ;; *) warn "No gh tarball for $(uname -m)."; return 1 ;; esac
    tag="$(curl -fsSL "https://api.github.com/repos/cli/cli/releases/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)"
    [ -n "$tag" ] || { warn "Could not look up the latest gh release."; return 1; }
    ver="${tag#v}"; dest="$HOME/.local/share/gh/$ver"
    mkdir -p "$dest" "$HOME/.local/bin"
    curl -fsSL "https://github.com/cli/cli/releases/download/$tag/gh_${ver}_linux_${arch}.tar.gz" \
        | tar -xz -C "$dest" --strip-components=1 || { rm -rf "$dest"; return 1; }
    ln -sf "$dest/bin/gh" "$HOME/.local/bin/gh"
    export PATH="$HOME/.local/bin:$PATH"
}

step "5. Prerequisites"
for tool in git curl sqlite3; do
    if have "$tool"; then ok "$tool found"
    elif confirm "$tool is missing. Install it now?" Y; then
        pkg_install "$(pkg_for "$tool")" && have "$tool" && ok "$tool installed" || warn "Could not install $tool."
    else warn "Skipped $tool."; fi
done
if have gh; then ok "gh found"
elif confirm "gh (GitHub CLI) is missing. Install it now? It is the easiest way to clone a private repo." Y; then
    if [ "$OS" = Darwin ]; then pkg_install gh; else install_gh_linux; fi
    have gh && ok "gh installed" || warn "Could not install gh; a token will work instead."
else warn "Skipped gh."; fi
have curl || die "curl is required."

# ---- Get the repo ------------------------------------------------------------
# A token is read once, passed to git for that command only, and never stored.
TOKEN="${GITHUB_TOKEN:-}"
git_clone_token() { # dest ; uses $TOKEN
    local b64; b64="$(printf 'x-access-token:%s' "$TOKEN" | base64 | tr -d '\n')"
    GIT_TERMINAL_PROMPT=0 git -c "http.extraheader=AUTHORIZATION: basic $b64" clone --branch "$ENV_BRANCH" "https://github.com/$ENV_REPO.git" "$1"
}

tarball_fetch() { # dest ; uses $TOKEN (optional)
    local auth=()
    [ -n "$TOKEN" ] && auth=(-H "Authorization: Bearer $TOKEN")
    mkdir -p "$1" && curl -fsSL ${auth[@]+"${auth[@]}"} "https://api.github.com/repos/$ENV_REPO/tarball/$ENV_BRANCH" \
        | tar -xz -C "$1" --strip-components=1
}

# make_fork: decide (ENV_FORK auto -> ask; default yes unless you own the repo), create
# the fork if it does not exist yet, and point ENV_REPO at it. Needs gh logged in.
make_fork() {
    local login owner def name slug
    [ "$ENV_FORK" = 0 ] && return 0
    login="$(gh api user --jq .login 2>/dev/null)"
    [ -n "$login" ] || { warn "Could not read your GitHub login."; return 1; }
    owner="${ENV_REPO%%/*}"
    if [ "$ENV_FORK" = auto ]; then
        def=Y; [ "$login" = "$owner" ] && def=N
        if confirm "Fork $ENV_REPO into your own GitHub repo and work on the fork?" "$def"; then ENV_FORK=1; else ENV_FORK=0; return 0; fi
        [ -n "$FORK_ORG" ] || { FORK_ORG="$(ask 'Fork owner (your login or an organization)' "$login")"; [ "$FORK_ORG" = "$login" ] && FORK_ORG=""; }
        [ -n "$FORK_NAME" ] || FORK_NAME="$(ask 'Fork name' "${ENV_REPO#*/}")"
    fi
    name="${FORK_NAME:-${ENV_REPO#*/}}"
    slug="${FORK_ORG:-$login}/$name"
    [ "$slug" = "$ENV_REPO" ] && { warn "$ENV_REPO is already yours: nothing to fork. Use --no-fork."; return 1; }
    if gh repo view "$slug" --json name >/dev/null 2>&1; then
        ok "Fork $slug already exists; using it"
    else
        gh repo fork "$ENV_REPO" --clone=false ${FORK_ORG:+--org "$FORK_ORG"} --fork-name "$name" || return 1
        for _ in 1 2 3 4 5 6 7 8 9 10; do   # GitHub creates forks asynchronously
            gh repo view "$slug" --json name >/dev/null 2>&1 && break
            sleep 2
        done
        ok "Forked $ENV_REPO to $slug"
    fi
    ENV_UPSTREAM="$ENV_REPO"
    ENV_REPO="$slug"
}

step "6. Repository"
if [ -d "$ENV_DIR/.git" ]; then
    ok "Found clone at $ENV_DIR"
    if have git && confirm "Pull latest changes (fast-forward only)?" Y; then
        git -C "$ENV_DIR" pull --ff-only || warn "Pull failed (see the error above); leaving the clone as is."
    fi
    env_wire_upstream "$ENV_DIR"
else
    mkdir -p "$(dirname "$ENV_DIR")"
    cloned=0
    if [ -n "$ENV_REPO_URL" ]; then
        have git || die "git is required to clone $ENV_REPO_URL."
        git clone --branch "$ENV_BRANCH" "$ENV_REPO_URL" "$ENV_DIR" && cloned=1
    else
        if have git && have gh; then
            if ! gh auth status >/dev/null 2>&1; then
                warn "Not logged in to GitHub."
                if [ "$HAVE_TTY" -eq 1 ] && confirm "Run 'gh auth login' now?" Y; then gh auth login </dev/tty || warn "gh auth login failed."; fi
            fi
            if gh auth status >/dev/null 2>&1; then
                gh auth setup-git >/dev/null 2>&1 || true   # let plain git pull/push use gh's token
                make_fork || die "Could not fork $ENV_REPO (see above). Re-run with --no-fork to clone it directly."
                gh repo clone "$ENV_REPO" "$ENV_DIR" -- --branch "$ENV_BRANCH" && cloned=1
            fi
        fi
        [ "$ENV_FORK" = 1 ] && [ "$cloned" -eq 0 ] && die "Forking needs the GitHub CLI logged in: install gh, run 'gh auth login', and re-run (or use --no-fork)."
        if [ "$cloned" -eq 0 ] && have git && [ -n "$TOKEN" ]; then
            git_clone_token "$ENV_DIR" && cloned=1
        fi
        if [ "$cloned" -eq 0 ] && have git; then
            warn "Trying an anonymous HTTPS clone (works only if the repo is public)."
            GIT_TERMINAL_PROMPT=0 git clone --branch "$ENV_BRANCH" "https://github.com/$ENV_REPO.git" "$ENV_DIR" 2>/dev/null && cloned=1
        fi
        if [ "$cloned" -eq 0 ] && [ -z "$TOKEN" ] && [ "$HAVE_TTY" -eq 1 ] && [ "$ASSUME_YES" -eq 0 ]; then
            warn "The clone failed. For a private repo, paste a GitHub token with read access to $ENV_REPO."
            printf '  Token (input hidden, Enter to give up): '
            read -r -s TOKEN </dev/tty; echo
            if [ -n "$TOKEN" ]; then
                if have git; then git_clone_token "$ENV_DIR" && cloned=1
                else tarball_fetch "$ENV_DIR" && cloned=1; fi
            fi
        fi
        if [ "$cloned" -eq 0 ] && ! have git; then
            warn "git is not available: downloading a tarball instead (no git history; install git to update later)."
            tarball_fetch "$ENV_DIR" && cloned=1
        fi
    fi
    TOKEN=""
    [ "$cloned" -eq 1 ] || { rm -rf "$ENV_DIR" 2>/dev/null; die "Could not get $ENV_REPO. Run 'gh auth login' (or set GITHUB_TOKEN) and re-run."; }
    ok "Cloned to $ENV_DIR"
    [ -n "$ENV_UPSTREAM" ] && env_wire_upstream "$ENV_DIR" "$ENV_UPSTREAM"
fi
[ -f "$ENV_DIR/setup-env.sh" ] || die "$ENV_DIR/setup-env.sh not found; is this the right repo?"

# ---- Hand off ----------------------------------------------------------------
step "7. Handing over to setup-env.sh"
SETUP_ARGS=(--work "$WORK_DIR" --dir "$ENV_DIR")   # WORK and the repo location are already chosen
[ "$ASSUME_YES" -eq 1 ] && SETUP_ARGS+=(-y)
export ENV_REPO ENV_BRANCH ENV_UPSTREAM
export ENV_JUST_CLONED=1       # setup-env.sh then skips its own "pull latest" question
exec bash "$ENV_DIR/setup-env.sh" "${SETUP_ARGS[@]}" ${PASS_ARGS[@]+"${PASS_ARGS[@]}"}
