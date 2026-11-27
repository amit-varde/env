# SSH

[← README](../README.md)

## Layout

| File | In git | Role |
|---|---|---|
| `ssh/config` | yes | The index. `~/.ssh/config` links here. Names every file ssh reads, in order, then the `Host *` defaults |
| `ssh/config.d/` | - | `~/.ssh/config.d` links here |
| `ssh/config.d/local.conf` | **no** (git-ignored) | Your `User` and `IdentityFile`, written by `setup-env.sh` or `/env-ssh user` |
| `ssh/config.d/host.conf.template` | yes | Starting point for a new host file |
| `ssh/config.d/*.conf` | **no** (git-ignored) | Your host files, plaintext |
| `ssh/config.d/*.conf.gpg` | yes | The published, encrypted form of a host file ([Privacy](privacy.md)) |
| `ssh/*.pub` | no (git-ignored) | Public keys moved here by `/env-ssh`, linked back from `~/.ssh` |
| `.ssh/keys/*.pub` | yes | Public keys published on purpose, one file per key ([Privacy](privacy.md)) |
| `.ssh/perms.sh` | yes | `~/.ssh` permission report; `~/.ssh/perms.sh --verify` / `--fix` |

`ssh/config` reads its files in this order:

```
Include config.d/local.conf          # 1. yours: User, IdentityFile
Include config.d/hosts.conf          # 2. one file per host
Include config.d/<alias>.conf
Host *                               # 3. defaults
```

How ssh reads these files:

- **The first value wins.** For each option, ssh keeps the first value it finds.
  `local.conf` is read first, so your user and key win over the host files. The
  `Host *` block comes last, so it only fills in options nothing above it set.
- **Only listed files count.** Nothing is picked up by wildcard, so a file in
  `config.d/` does nothing until `ssh/config` has an `Include` line for it.
  `/env-ssh status` flags any file that isn't included.
- **Relative paths resolve under `~/.ssh`.** So `config.d/hosts.conf` means
  `~/.ssh/config.d/hosts.conf`. That's why `~/.ssh/config.d` has to link to the
  repo. A listed file that doesn't exist is skipped without an error.
- **No personal settings in host files.** Host files hold only shared settings:
  `HostName`, forwarding, keepalives. `User` and `IdentityFile` go in
  `local.conf`, because the repo is shared.

### Add a host

1. Copy `ssh/config.d/host.conf.template` to `ssh/config.d/<alias>.conf` and
   edit its header, `Host` and `HostName` lines.
2. In `ssh/config`, add `Include config.d/<alias>.conf` under "2. Hosts", with a
   one-line comment that says what the host is.
3. Check it: `ssh -G <alias> | grep -E '^(user|hostname|identityfile) '`.
4. Plaintext `config.d/*.conf` is git-ignored, so the host stays private by
   default. To publish it, encrypt it with `./scripts/export-ssh-config.sh` and
   commit the `.conf.gpg` it writes - never the plaintext. See
   [Privacy](privacy.md).

Host files carry no hostnames or internal names into git unless you encrypt and
commit them on purpose. That is deliberate: this repo is public.

## `/env-ssh` (Claude Code skill)

The skill always checks `~/.ssh` permissions first, then asks which tasks to run.

| Task | Script command (`claude/skills/env-ssh/scripts/env-ssh.sh`) |
|---|---|
| Check and fix permissions | `perms [--apply]` |
| Report how `~/.ssh` is wired, and which Includes exist | `status` |
| Link `~/.ssh/config` and `~/.ssh/config.d` to the repo | `link-config [--apply]` |
| Link only `~/.ssh/config.d` (used by `setup-env.sh`) | `link-conf-d [--apply]` |
| Move public keys into the repo / undo | `adopt-keys` / `release-keys [--apply]` |
| Set your user and key (`local.conf`) | `user-conf --user U --key K [--hosts P] [--apply]` |
| Archive old backups and `known_hosts.*` | `cleanup [--keep N] [--delete] [--apply]` |
| Show what ssh resolves / test a login | `verify [host]` / `test <host>` |

Change commands are dry runs until you add `--apply`. Paths come from
`ENV_SSH_ENV_DIR` (else `$BU`) and `ENV_SSH_SSH_HOME` (else `~/.ssh`).

## Moving from the old layout

The old layout kept `~/.ssh/config.d/` as a real folder with
`00-env-user.conf`. `link-config` (or `setup-env.sh`) moves that folder to
`~/.ssh/config.d.bak-<timestamp>`, prints the `User`/`IdentityFile` it held, and
links `~/.ssh/config.d` to the repo. Then write `local.conf` with `user-conf`,
using whichever private key the remote side already accepts.

## Encrypted host files

A host file you want on every machine but not in public goes in as GPG:

```
./scripts/export-ssh-config.sh      # ssh/config.d/<alias>.conf -> <alias>.conf.gpg
```

The passphrase is yours to keep in a password manager, never in this repo. On a
new machine, `setup-env.sh`'s ssh step (or `./scripts/install.sh`) decrypts every
`config.d/*.conf.gpg` back to plaintext next to it, and that plaintext is
git-ignored. `ssh/config` has to list the decrypted name with an `Include` line
or ssh will not read it.

## Keys

Private keys are never stored in this repo. `./scripts/install-ssh-keys.sh`
matches each `.ssh/keys/*.pub` to a 1Password SSH Key item by fingerprint and
writes the private half to `~/.ssh/id_<type>`, refusing anything whose
fingerprint does not match. `~/.ssh/perms.sh --verify` reports the modes
afterwards and `--fix` corrects them.

Prefer a separate key per account: one public key reused everywhere lets anyone
correlate your accounts. See [Privacy](privacy.md).
