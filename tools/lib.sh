# shellcheck shell=bash
# Shared helpers for tools/ installers (sourced). macOS and Linux.
# Adapted from github.com/amit-varde/env-kit (tools/lib.sh), made OS-aware.
# shellcheck disable=SC2034  # INSTALL_ORDER and MAC_ONLY_TOOLS are read by the scripts that source this
: "${DRY:=0}"

# Package install, log helpers, and have() live in lib/common.bash.
_TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.bash
source "$_TOOLS_DIR/../lib/common.bash"
unset _TOOLS_DIR

case "$(uname -s)" in Darwin) OS_NAME=mac ;; Linux) OS_NAME=linux ;; *) OS_NAME=other ;; esac

# Bootstrap order for install.sh (--all and interactive full stack).
# Add a tool: drop in install_<name>.sh and append the name below.
INSTALL_ORDER=(
  # 1. Package manager (macOS only; needed by most brew-based installers)
  homebrew

  # 2. Prerequisite used by cursor-ide
  sqlite3

  # 3. Shell framework (needs zsh)
  oh_my_zsh

  # 4. Python stack (pyenv -> versions -> pip)
  pyenv
  python
  pip

  # 5. Node version manager
  nvm

  # 6. Editors
  vim
  macvim

  # 7. Containers
  docker

  # 8. CLI, terminal, IDEs
  gh
  iterm2
  cursor
  vscode
  claude
)

# Tools that only install on macOS. On Linux their installer prints how to get
# the tool by hand and exits 0 ("skipped"), so install.sh --all still succeeds.
MAC_ONLY_TOOLS=" homebrew macvim docker iterm2 cursor vscode "

run() {
  if [ "$DRY" -eq 1 ]; then echo "[dry-run] $*"; else "$@"; fi
}

parse_dry() {
  for a in "$@"; do
    case "$a" in --dry-run) DRY=1 ;; esac
  done
}

# mac_only "hint for other systems": exit 0 (skipped) when not on macOS.
mac_only() {
  [ "$OS_NAME" = mac ] && return 0
  echo "skipped: macOS only. ${1:-}"
  exit 0
}

# Kept for installers that really cannot work elsewhere.
need_macos() {
  [ "$OS_NAME" = mac ] || { echo "macOS only" >&2; exit 1; }
}

# ---- Homebrew (macOS) ---------------------------------------------------------
ensure_brew() {
  if command -v brew >/dev/null 2>&1; then return 0; fi
  for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$p" ]; then eval "$("$p" shellenv)"; return 0; fi
  done
  if [ "$DRY" -eq 1 ]; then
    echo "[dry-run] brew is not on PATH; commands below assume install_homebrew.sh ran"
    return 0
  fi
  echo "Homebrew is not installed. Run tools/install_homebrew.sh first." >&2
  return 1
}

brew_has() { # formula|cask name
  command -v brew >/dev/null 2>&1 || return 1
  brew list "--$1" "$2" >/dev/null 2>&1
}

# install_formula formula [binary]: brew on macOS, the system package manager on Linux
install_formula() {
  bin="${2:-$1}"
  if command -v "$bin" >/dev/null 2>&1; then
    echo "already installed: $bin ($(command -v "$bin"))"
    return 0
  fi
  if [ "$OS_NAME" = linux ]; then
    echo "installing $1"
    pkg_install "$(linux_pkg "$1")"
    return $?
  fi
  ensure_brew || return 1
  if brew_has formula "$1"; then echo "already installed: $1"; return 0; fi
  echo "installing $1"
  run brew install "$1"
}

install_cask() { # cask [app-path] [binary]   (macOS only)
  app="${2:-}"; bin="${3:-}"
  if [ -n "$bin" ] && command -v "$bin" >/dev/null 2>&1; then
    echo "already installed: $bin ($(command -v "$bin"))"
    return 0
  fi
  if [ -n "$app" ] && [ -d "$app" ]; then
    echo "already present: $app"
    return 0
  fi
  ensure_brew || return 1
  if brew_has cask "$1"; then echo "already installed: $1"; return 0; fi
  echo "installing $1"
  run brew install --cask "$1"
}

# ---- Python -------------------------------------------------------------------
# Build dependencies for python-build. Without root on Linux it only warns:
# pyenv may still work if the libraries are already there.
install_python_build_deps() {
  if [ "$OS_NAME" = mac ]; then
    ensure_brew || return 1
    for f in openssl readline sqlite3 xz zlib; do
      if brew_has formula "$f"; then echo "already installed: $f"
      else echo "installing build dep: $f"; run brew install "$f"; fi
    done
    return 0
  fi
  case "$(pkg_mgr 2>/dev/null)" in
    apt-get) deps="build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev" ;;
    dnf|yum) deps="gcc make zlib-devel bzip2 bzip2-devel readline-devel sqlite sqlite-devel openssl-devel tk-devel libffi-devel xz-devel" ;;
    pacman)  deps="base-devel openssl zlib xz tk sqlite" ;;
    *)       echo "WARNING: unknown package manager; install Python build dependencies yourself (pyenv wiki)." >&2; return 0 ;;
  esac
  echo "installing Python build dependencies"
  # shellcheck disable=SC2086
  pkg_install $deps || echo "WARNING: could not install build dependencies; building Python may fail." >&2
  return 0
}

ensure_pyenv() {
  export PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"
  if command -v pyenv >/dev/null 2>&1; then
    eval "$(pyenv init -)" 2>/dev/null || true
    return 0
  fi
  if [ -x "$PYENV_ROOT/bin/pyenv" ]; then
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)" 2>/dev/null || true
    return 0
  fi
  if [ "$DRY" -eq 1 ]; then
    echo "[dry-run] pyenv is not on PATH; commands below assume install_pyenv.sh ran"
    return 0
  fi
  echo "pyenv is not installed. Run tools/install_pyenv.sh first." >&2
  return 1
}

# ---- GitHub release downloads (user-space installs on Linux) --------------------
# github_latest_tag owner/repo -> v1.2.3
github_latest_tag() {
  local auth=()
  [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
  curl -fsSL ${auth[@]+"${auth[@]}"} "https://api.github.com/repos/$1/releases/latest" \
    | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1
}

# linux_arch -> amd64 | arm64 (the names GitHub release assets use)
linux_arch() {
  case "$(uname -m)" in
    x86_64|amd64)  echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
    *) return 1 ;;
  esac
}
