#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File: env/setup-env.sh
# Description: Install and wire up this shell environment (macOS + Linux)
# -----------------------------------------------------------------------------
# Run this from a clone of the repo. The functions live in lib/common.bash.
# On a machine that does not have the repo yet, use bootstrap.sh: that file
# can be copied and run by itself, and it hands off to this script.
#
#   ./setup-env.sh
#
# What it does (each step asks before changing anything, and is safe to re-run):
#   prereqs    Checks git, curl, gh, sqlite3 and offers to install missing ones
#   repo       Clones the repo to <work>/env (via gh, logging in if needed), or
#              fast-forwards an existing clone. In a clone of a fork it adds
#              the original as the `upstream` remote, with pushing disabled
#   hooks      Installs a git pre-commit hook that runs `env-scan --staged`, so a
#              commit carrying a secret, an absolute home path or a term from
#              .blocklist.local is refused before it exists
#   host       Creates .env.host (per-machine paths: WORK, DL, DOCS, EDITOR_APP)
#   dotfiles   Installs the portable ~/.zshrc, ~/.bashrc and ~/.cshrc as copies
#              (each sources its own ~/.<name>.local last, which is where
#              employer and machine settings go and is never committed).
#              Optionally links ~/.vimrc and, when you have no ~/.gitconfig,
#              creates one from dotfiles/gitconfig.template (never changes an
#              existing one). Runs before `shell`, which appends to ~/.zshrc
#   shell      Adds `source <repo>/env.sh` to your shell rc file
#   ssh        Links ~/.ssh/config and ~/.ssh/config.d to the repo; writes your
#              user/key to ssh/config.d/local.conf (git-ignored); links
#              ~/.ssh/perms.sh; decrypts each published ssh/config.d/*.conf.gpg
#              to its git-ignored plaintext (needs a terminal, or
#              SSH_CONFIG_PASS_FILE). With --authorize-keys it also appends
#              .ssh/keys/*.pub to ~/.ssh/authorized_keys
#   claude     Links ~/.claude/settings.json and claude/skills/* (not needed when
#              ~/.claude is a symlink to the repo's claude/ folder). settings.json
#              enables terminal Code Mode by default; see docs/claude-code.md
#   cursor     Links Cursor's settings (cursor-sync) and checks IDE mode
#   tools      Pick dev tools from a numbered menu (installed or missing, with
#              versions), or pass --tools; each choice runs its tools/install_<name>.sh
#   shortcuts  Optionally writes a Desktop .code-workspace per directory in WORK
#   doctor     Prints a read-only health report (env-doctor)
#
# Every file it replaces is first copied to <file>.bak-<timestamp>.
#
# Re-running is safe and is the way to add a tool later: each step only changes
# what is missing, and the tools step lists every tool with its state, so you can
# install one you skipped before (see --tools, or pick from the menu).
#
# Records (in your home directory):
#   ~/.setup-env.log       one line per change, with the date: tools installed, links,
#                          backups, shell line, repo clone/pull, and each run's start/end
#   ~/.setup-env.manifest  every dev tool as  <tool>:<version>:<Y|N>  (Y = installed).
#                          Check it with bin/env-toolcheck.sh; rebuild with --reset
#
# Options:
#   -y, --yes        Accept every default without prompting. Installs no tools unless
#                    you also pass --tools
#   -d, --dir PATH   Install location of the repo (default: $ENV_DIR, else <work>/env)
#   -w, --work PATH  Work/projects directory (WORK). Skips the question. Default
#                    location of the repo is <work>/env
#   --only LIST      Run only these steps (comma-separated names from above)
#   --skip LIST      Run every step except these
#   --tools LIST     Dev tools to install or re-run, comma-separated (e.g. gh,pyenv),
#                    without the menu. Names: tools/install.sh --list
#   --authorize-keys Append .ssh/keys/*.pub to ~/.ssh/authorized_keys in the ssh
#                    step. Off by default: it grants login to whoever holds the
#                    matching private keys
#   --list-steps     Print the step names and exit
#   -h, --help       Show this help
#
# Environment overrides: ENV_DIR, ENV_REPO (owner/name), ENV_BRANCH, WORK (default
# for the WORK question), ENV_JUST_CLONED=1 (set by bootstrap.sh: skip the pull),
# ENV_UPSTREAM (owner/name of the original, set by bootstrap.sh after forking),
# SETUP_ENV_LOG (default ~/.setup-env.log), SETUP_ENV_MANIFEST (default ~/.setup-env.manifest),
# SSH_CONFIG_PASS_FILE (file holding the gpg passphrase for ssh/config.d/*.conf.gpg,
# for runs with no terminal; the same variable scripts/export-ssh-config.sh uses)
# -----------------------------------------------------------------------------

set -uo pipefail

_SETUP_SELF="${BASH_SOURCE[0]:-}"
if [ -z "$_SETUP_SELF" ] || [ ! -f "$_SETUP_SELF" ]; then
    printf 'ERROR: setup-env.sh must be run from a clone (bash path/to/setup-env.sh). For a machine without the repo, use bootstrap.sh.\n' >&2
    exit 1
fi
_SETUP_DIR="$(cd "$(dirname "$_SETUP_SELF")" && pwd)"
if [ ! -f "$_SETUP_DIR/lib/common.bash" ]; then
    printf 'ERROR: %s/lib/common.bash not found. Run this from the env repo, or use bootstrap.sh.\n' "$_SETUP_DIR" >&2
    exit 1
fi
# shellcheck source=lib/common.bash
source "$_SETUP_DIR/lib/common.bash"
setup_env_main "$_SETUP_SELF" "$@"
