# Shared helpers for tools/ installers (sourced). macOS only.
: "${DRY:=0}"

# Bootstrap order for install_all.sh (and install.sh with no args).
# Add a tool: drop in install_<name>.sh and append the name below.
INSTALL_ORDER=(
  # 1. Package manager (needed by most brew-based installers)
  homebrew

  # 2. Shell framework (portable zshrc sources it when present)
  oh_my_zsh

  # 3. Python stack (pyenv -> versions -> pip)
  pyenv
  python
  pip

  # 4. Node version manager
  nvm

  # 5. Editors
  vim
  macvim

  # 6. Containers
  docker

  # 7. CLI, terminal, IDEs
  gh
  iterm2
  cursor
  vscode
  claude
)

run() {
  if [ "$DRY" -eq 1 ]; then echo "[dry-run] $*"; else "$@"; fi
}

parse_dry() {
  for a in "$@"; do
    case "$a" in --dry-run) DRY=1 ;; esac
  done
}

need_macos() {
  [ "$(uname -s)" = "Darwin" ] || { echo "macOS only" >&2; exit 1; }
}

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

install_formula() { # formula [binary]
  bin="${2:-$1}"
  if command -v "$bin" >/dev/null 2>&1; then
    echo "already installed: $bin ($(command -v "$bin"))"
    return 0
  fi
  ensure_brew || return 1
  if brew_has formula "$1"; then echo "already installed: $1"; return 0; fi
  echo "installing $1"
  run brew install "$1"
}

install_cask() { # cask [app-path] [binary]
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
