# shellcheck shell=bash
# =============================================================================
# File:        tools/detect.sh
# =============================================================================
#
# DESCRIPTION: Detect dev tools (installed or not, and which version) and keep
#   the manifest $HOME/.setup-env.manifest in step with them. Sourced by
#   tools/install.sh, setup-env.sh and bin/env-toolcheck.sh. Only manifest_write
#   changes anything (it rewrites the manifest file); the rest only look.
#
#   MANIFEST FORMAT: one line per tool in INSTALL_ORDER, no spaces:
#       <tool>:<version>:<Y|N>
#     Y = installed when the manifest was written, N = not installed. The
#     version is empty for N. Examples:
#       gh:2.63.0:Y
#       pyenv::N
#   Lines starting with # are comments.
#
# FUNCTIONS:
#   tool_present NAME    exit 0 when NAME is installed
#   tool_version NAME    print its version ("" when unknown or not installed)
#   manifest_path        print the manifest path ($SETUP_ENV_MANIFEST overrides)
#   manifest_write       regenerate the manifest from what is on disk now
#
# =============================================================================

_DETECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$_DETECT_DIR/lib.sh"
unset _DETECT_DIR

# tool_present NAME: is it installed? (read-only)
tool_present() {
  case "$1" in
    homebrew)  command -v brew >/dev/null 2>&1 || [ -x /opt/homebrew/bin/brew ] || [ -x /usr/local/bin/brew ] ;;
    sqlite3)   command -v sqlite3 >/dev/null 2>&1 ;;
    oh_my_zsh) [ -d "$HOME/.oh-my-zsh" ] ;;
    pyenv)     command -v pyenv >/dev/null 2>&1 || [ -x "${PYENV_ROOT:-$HOME/.pyenv}/bin/pyenv" ] ;;
    python)    command -v python >/dev/null 2>&1 || [ -x "${PYENV_ROOT:-$HOME/.pyenv}/shims/python" ] ;;
    pip)       command -v pip >/dev/null 2>&1 || [ -x "${PYENV_ROOT:-$HOME/.pyenv}/shims/pip" ] ;;
    nvm)       [ -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ] ;;
    vim)       command -v vim >/dev/null 2>&1 ;;
    macvim)    command -v mvim >/dev/null 2>&1 || [ -d /Applications/MacVim.app ] ;;
    docker)    command -v docker >/dev/null 2>&1 || [ -d /Applications/Docker.app ] ;;
    gh)        command -v gh >/dev/null 2>&1 ;;
    iterm2)    [ -d /Applications/iTerm.app ] ;;
    cursor)    command -v cursor >/dev/null 2>&1 || [ -d /Applications/Cursor.app ] || [ -d "$HOME/Applications/Cursor.app" ] ;;
    vscode)    command -v code >/dev/null 2>&1 || [ -d "/Applications/Visual Studio Code.app" ] ;;
    claude)    command -v claude >/dev/null 2>&1 ;;
    *)         return 1 ;;
  esac
}

# _app_version APP_PATH: CFBundleShortVersionString of a macOS app, or nothing.
_app_version() {
  [ -d "$1" ] || return 0
  defaults read "$1/Contents/Info" CFBundleShortVersionString 2>/dev/null
}

# tool_version NAME: the version of an installed tool, or nothing. Never fails the
# caller: a tool whose version cannot be read is recorded with an empty version.
tool_version() {
  local v=""
  case "$1" in
    homebrew)  v="$(brew --version 2>/dev/null | sed -n 's/^Homebrew \([0-9.]*\).*/\1/p' | head -n 1)" ;;
    sqlite3)   v="$(sqlite3 --version 2>/dev/null | awk '{print $1}')" ;;
    oh_my_zsh) v="$(git -C "$HOME/.oh-my-zsh" describe --tags --always 2>/dev/null)" ;;
    pyenv)     v="$(pyenv --version 2>/dev/null | awk '{print $2}')" ;;
    python)    v="$(python --version 2>&1 | sed -n 's/^Python \([0-9.]*\).*/\1/p' | head -n 1)" ;;
    pip)       v="$(pip --version 2>/dev/null | awk '{print $2}')" ;;
    nvm)       v="$( . "${NVM_DIR:-$HOME/.nvm}/nvm.sh" >/dev/null 2>&1; nvm --version 2>/dev/null)" ;;
    vim)       v="$(vim --version 2>/dev/null | sed -n 's/^VIM - Vi IMproved \([0-9.]*\).*/\1/p' | head -n 1)" ;;
    macvim)    v="$(_app_version /Applications/MacVim.app)" ;;
    docker)    v="$(docker --version 2>/dev/null | sed -n 's/^Docker version \([^,]*\).*/\1/p')" ;;
    gh)        v="$(gh --version 2>/dev/null | awk 'NR == 1 {print $3}')" ;;
    iterm2)    v="$(_app_version /Applications/iTerm.app)" ;;
    cursor)    v="$(_app_version /Applications/Cursor.app)"
               [ -n "$v" ] || v="$(_app_version "$HOME/Applications/Cursor.app")" ;;
    vscode)    v="$(_app_version "/Applications/Visual Studio Code.app")" ;;
    claude)    v="$(claude --version 2>/dev/null | awk '{print $1}')" ;;
  esac
  # The manifest is colon-separated, one line per tool: keep the version to one field.
  v="${v//:/_}"; v="${v// /}"
  printf '%s\n' "$v"
}

# manifest_path: where the manifest lives. SETUP_ENV_MANIFEST overrides it (tests).
manifest_path() {
  printf '%s\n' "${SETUP_ENV_MANIFEST:-$HOME/.setup-env.manifest}"
}

# manifest_write: rewrite the manifest for every tool in INSTALL_ORDER from a fresh
# check of this machine. Written to a temp file first, then moved into place.
manifest_write() {
  local f tmp t v yn
  f="$(manifest_path)"
  mkdir -p "$(dirname "$f")" || return 1
  tmp="$f.tmp-$$"
  : > "$tmp" || return 1
  {
    echo "# tool:version:installed (Y|N). Written by setup-env.sh and env-toolcheck.sh --reset."
    for t in "${INSTALL_ORDER[@]}"; do
      if tool_present "$t"; then yn=Y; v="$(tool_version "$t")"; else yn=N; v=""; fi
      printf '%s:%s:%s\n' "$t" "$v" "$yn"
    done
  } >> "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$f"
}
