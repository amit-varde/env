#!/usr/bin/env bash
# =============================================================================
# File:        tools/install_pydev.sh
# =============================================================================
#
# DESCRIPTION: Install pyenv and a default Python
#   Installs pyenv with the official pyenv-installer (pyenv.run, after asking
#   for confirmation), then installs Python $PYDEV_PYTHON (default 3.11.8) and
#   makes it the pyenv global default. No shell rc file is edited: env.sh
#   already initialises pyenv and pyenv-virtualenv (lib/init-pyenv.bash).
#
# PREREQUISITES:
#   - curl (for downloading installer)
#   - Build dependencies for Python compilation (see pyenv wiki)
#
# EXIT CODES:
#   0 - Success
#   1 - Installation failed
#
# USAGE:
#   pydev-install
#   PYDEV_PYTHON=3.12.7 pydev-install
#   pydev-install -h | --help
#
# =============================================================================
set -euo pipefail

: "${BU:=$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)}"
source "$BU/lib/common.bash"
handle_help "$@"

PYTHON_VERSION="${PYDEV_PYTHON:-3.11.8}"

pydev_install() {
    # Curl-pipe-bash is a supply-chain risk: a compromised pyenv.run host,
    # DNS, CA, or proxy would let an attacker run arbitrary code as the
    # current user. Warn and require explicit confirmation.
    warn "About to run: curl -fsSL https://pyenv.run | bash"
    warn "This downloads and executes remote code without integrity checks."
    info "For a verified install, follow https://github.com/pyenv/pyenv#installation manually."
    local confirm
    read -r -p "Proceed? [y/N] " confirm
    case "$confirm" in
        y|Y|yes|YES) ;;
        *) info "Aborted."; return 1 ;;
    esac

    info "Installing pyenv..."
    if ! curl -fsSL https://pyenv.run | bash; then
        err "Failed to install pyenv."
        return 1
    fi
    success "pyenv installed."

    # Activate pyenv for the rest of this script only. New shells get it from
    # env.sh (lib/init-pyenv.bash), so no shell rc file is edited.
    export PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)"

    info "Installing Python $PYTHON_VERSION..."
    if pyenv install --skip-existing "$PYTHON_VERSION" && pyenv global "$PYTHON_VERSION"; then
        success "Python $PYTHON_VERSION installed and set as the global default."
        python -m pip install --upgrade pip || warn "Failed to upgrade pip"
    else
        warn "Failed to install Python. Run manually:"
        warn "  pyenv install $PYTHON_VERSION && pyenv global $PYTHON_VERSION"
    fi

    info "Open a new terminal (or run: source \"$BU/env.sh\") to use pyenv, then check:"
    info "  pydev"
}

pydev_install "$@"
