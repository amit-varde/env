# Portable Claude + shell config

Account- and employer-neutral setup you can move between Claude accounts and machines. No secrets, no company names.

## Layout
| Path | What |
|---|---|
| `claude/` | `CLAUDE.md` template + safe `settings.json` baseline for `~/.claude` |
| `dotfiles/` | `zshrc`, `bashrc`, `cshrc` (tcsh), `vimrc`, `gitconfig.template` |
| `ssh/config` | portable SSH defaults; includes `~/.ssh/config.d/*.conf` |
| `ssh/config.d/` | host SSH config for this repo. `install.sh` symlinks `~/.ssh/config.d` here |
| `ssh/config.d/*.conf.gpg` | encrypted host entries (passphrase in 1Password) |
| `ssh/config.d/*.conf` | decrypted host entries, gitignored |
| `.ssh/keys/` | public keys for other people, named `amit-varde-<type>.pub` |
| `.ssh/perms.sh` | `~/.ssh/perms.sh --verify` / `--fix` permission report |
| `scripts/` | `export-*` (scrub your real files), `scan.sh` (gate), `install.sh` |
| `tools/` | macOS installers; `install_all.sh` runs the full stack in dependency order |

## Workflow
1. `cp blocklist.example .blocklist.local` and add your own sensitive terms (employer, project, host names). It is gitignored.
2. `./scripts/export-claude.sh`      -> scrubbed copy of `~/.claude` in `_review/claude/`
3. `./scripts/export-dotfiles.sh`    -> scrubbed copies of `~/.zshrc`, `~/.bashrc`, `~/.cshrc` in `_review/dotfiles/`
4. `./scripts/export-ssh-pub.sh amit-varde` -> public keys into `.ssh/keys/`
5. Edit `ssh/config.d/*.conf`, then `./scripts/export-ssh-config.sh` to refresh the matching `.conf.gpg` files. gpg prompts; the passphrase lives in 1Password (Private vault, "claude-portable-config ssh config").
6. Read `_review/`, move keepers into `claude/` and `dotfiles/`. Put anything employer/host specific in `~/.zshrc.local` (sourced, never committed).
7. `./scripts/scan.sh` must print `CLEAN`, then `git init && git add -A && git commit`. Use a **private** repo.
8. On the new account/machine: `./scripts/install.sh --dry-run`, then `./scripts/install.sh` (gpg prompts to decrypt the SSH hosts; add `--authorize-keys` to append `.ssh/keys/*.pub` to `~/.ssh/authorized_keys`). `./scripts/install-ssh-keys.sh` writes the matching private keys from 1Password into `~/.ssh/id_<type>`. `~/.ssh/perms.sh --verify` reports modes; add `--fix` to correct them.
9. Dev tools (macOS): `./tools/install_all.sh --dry-run`, then `./tools/install_all.sh`. One tool: `./tools/install_cursor.sh`. Re-running skips anything already present. Add a tool with `tools/install_<name>.sh` and append `<name>` to `INSTALL_ORDER` in `tools/lib.sh`.

## Privacy rules baked in
- Private keys are not stored in this repo. `scripts/install-ssh-keys.sh` reads them from 1Password and writes `~/.ssh/id_<type>`. The scan fails on key headers.
- Host-specific SSH config is edited in `ssh/config.d/` and published only as `*.conf.gpg`. `scan.sh` skips the plaintext `*.conf` files. `~/.ssh/config.d` is a symlink to `ssh/config.d/`.
- Prefer a fresh key per employer/account (`ssh-keygen -t ed25519 -C ""`): one public key reused everywhere lets anyone correlate your accounts.
- Credentials belong in a secrets manager or the OS keychain, not in rc files or `settings.json` `env`.
- Never copy: `~/.claude.json`, `.credentials*`, `projects/`, `history`, `todos/`, MCP configs containing tokens.
- Per-employer git identity: use `[includeIf "gitdir:~/work/<employer>/"] path = ~/.gitconfig-<employer>` instead of one global email.
