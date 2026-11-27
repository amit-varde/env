---
name: env-ssh
description: Interactively manage SSH config through the env repo - always checks and fixes ~/.ssh permissions first, then can check status, clean up old config backups and known_hosts.old files, link ~/.ssh/config to <env>/ssh/config and ~/.ssh/config.d to <env>/ssh/config.d (migrating an old real config.d folder), move public keys (*.pub) into <env>/ssh/ and link them back (or undo that), write per-machine user/key settings to the git-ignored <env>/ssh/config.d/local.conf, add or edit a host (one config.d/<host>.conf per host, each Included by name from ssh/config), verify what ssh will actually use, and test a login. Asks before every change and backs up whatever it replaces. Use when the user says "/env-ssh", "fix my ssh config", "my ~/.ssh/config link is broken", "move my ssh keys into the env repo", "link my pub keys", "add an ssh host", "which key/user will ssh use for X", "ssh to my host uses the wrong key", or wants to undo or audit how ~/.ssh is wired to the repo.
argument-hint: "[status | link | keys | unkeys | user | host <name> | cleanup | verify [host] | test <host>]"
---

# Manage SSH config through the env repo

Goal: `~/.ssh` stays wired to the env repo the way the user wants, and `ssh`
resolves each host to the right user and key. Every change is shown first,
confirmed, and reversible.

## Layout

| Path | In git | Role |
|---|---|---|
| `<env>/ssh/config` | yes | Index; `~/.ssh/config` links here. Lists every file by name, then `Host *` |
| `<env>/ssh/config.d/` | - | `~/.ssh/config.d` links here |
| `<env>/ssh/config.d/local.conf` | no | The user's `User` / `IdentityFile`; Included **first**, so it wins |
| `<env>/ssh/config.d/<host>.conf` | yes | One file per host: `Host`, `HostName`, shared options only |
| `<env>/ssh/*.pub` | no | Public keys, linked back from `~/.ssh` |

Rules to keep in mind:
- `ssh/config` uses one explicit `Include config.d/<file>` line per file, never
  a wildcard. A file without an Include line is ignored; `status` flags it.
- Relative Includes resolve under `~/.ssh`, so they only reach the repo when
  `~/.ssh/config.d` is a link to `<env>/ssh/config.d`.
- ssh uses the **first** value per option. Never put `IdentityFile` under
  `Host *` in `local.conf`: with an explicit IdentityFile ssh stops trying its
  default keys, so every host gets only that key (that is the classic break: the
  key is `id_ed25519` but the remote side only has a different key registered).

## Paths (never hardcode them)

All work goes through the bundled script, which resolves paths itself:

```bash
S="<this skill's directory>/scripts/env-ssh.sh"
bash "$S" paths
```

| Name | Resolved from (first that applies) |
|---|---|
| `ENV_DIR` | `$ENV_SSH_ENV_DIR` · `$BU` (set by `env.sh`) · the repo holding this skill, if it has `env.sh` · `~/work/env` |
| `REPO_SSH` | `$ENV_DIR/ssh` (shared config is `$REPO_SSH/config`) |
| `CONF_D` | `$REPO_SSH/config.d` (`$SSH_HOME/config.d` links here) |
| `SSH_HOME` | `$ENV_SSH_SSH_HOME` · `~/.ssh` |
| `USER_CONF` | `$CONF_D/local.conf` (git-ignored) |

Use the paths `paths` prints in everything you show the user; don't assume
`/Users/<name>` or `~/work/env`. If `ENV_DIR` looks wrong (no `env.sh`, not a git
repo), ask for the right one and pass it as `ENV_SSH_ENV_DIR=<path>` on every call.

## Interaction rules

This skill is interactive. Ask with **AskUserQuestion** at each decision point:
- One question per decision; batch up to 4 independent ones in one call.
- 2-4 options, recommended option **first** with ` (Recommended)` appended; each
  description says what will change and, for the recommended one, why (from the
  status report).
- Don't add an "Other" option (the tool adds one). Use `multiSelect: true` for
  choosing keys or tasks.
- If AskUserQuestion is unavailable, print a numbered list, mark the
  recommendation, and wait.
- An argument picks the task directly (`keys` = adopt-keys, `unkeys` =
  release-keys, `user` = user-conf, `link` = link-config, `cleanup` = cleanup);
  skip the task menu then.

## 0. Permissions check (mandatory - every run, before anything else)

Run this on every invocation of the skill, whatever the argument, even for
`verify` or `status`. ssh silently ignores or refuses keys and configs with loose
permissions ("UNPROTECTED PRIVATE KEY FILE", "Bad owner or permissions"), so
every later step depends on this check.

```bash
bash "$S" perms        # exit 0 = all OK, 3 = issues found (dry run)
```

Show only the `FIX`/`BAD` lines (or "Permissions OK."). If there are `FIX` lines,
ask: `Fix them now (Recommended)` · `Skip for this run`. A fix only removes
access (`chmod`), so it is safe to recommend. On yes run `bash "$S" perms --apply`
(or hand the user that command if the sandbox blocks it), then run `perms` once
more to confirm. `BAD` (wrong owner) lines need `chown`: tell the user the exact
command - never run `sudo` yourself. If the user skips, carry on, but note the
issues again in the wrap-up.

## 1. Status (read-only - always run next)

```bash
bash "$S" status
```

Summarise it in a few lines: is `config` linked to the repo, missing, broken, or
the user's own file; is `config.d` linked to the repo or still an old real
folder; which Includes are present or `MISSING`, and any `NOT INCLUDED` file in
`config.d/`; which `.pub` files are regular files, linked to the repo,
or broken links; whether every `.pub` has its private key; whether `ssh/*.pub`
is git-ignored; whether the repo config parses. Name each problem you see.

## 2. Pick tasks

Ask (multiSelect) which to do, pre-recommending the ones status shows are needed:

| Task | Recommend when |
|---|---|
| Link `~/.ssh/config` and `~/.ssh/config.d` to the repo | either is missing, broken, a real folder/file, or a link to an old repo path |
| Move public keys into the repo and link them back | any `.pub` in `SSH_HOME` is a regular file |
| Set my remote username and key (`local.conf`) | file missing, its key file missing, or it sets `IdentityFile` under `Host *` |
| Add or edit a host (`config.d/<host>.conf`) | user mentioned a host, or status shows a `NOT INCLUDED` file |
| Clean up old backups and `known_hosts.*` files | status reports any (do it after the other tasks, since they create backups) |
| Verify / test a host | always useful last |
| Undo: move public keys back to `~/.ssh` | only if the user asks |

## 3. Do each task: dry run → confirm → apply

Every change command is a **dry run by default**. For each task:
1. Run it without `--apply` and show the `would run:` lines.
2. Ask: `Apply (Recommended)` · `Skip`. For destructive-looking plans (replacing a
   regular file, a key collision) explain the backup that will be kept.
3. Run the same command with `--apply`.
4. **If it fails with "Operation not permitted"**, the sandbox is blocking writes
   to `~/.ssh`. Don't look for a way around it: give the user the exact command
   in a `bash` block, e.g. `bash "<S>" adopt-keys --apply`, wait for them to run
   it, then re-run `status` to confirm.

### Link config

```bash
bash "$S" link-config [--apply]
```
This links both `~/.ssh/config` and `~/.ssh/config.d`. If `~/.ssh/config.d` is
an old real folder (e.g. holding `00-env-user.conf`), the dry run lists what it
holds and the `User`/`IdentityFile` lines in it; `--apply` moves the folder to
`config.d.bak-<stamp>` (nothing is deleted). Carry those settings into
`local.conf` with the user-conf task next.

If `~/.ssh/config` is the user's **own regular file** with real content, don't
replace it by default. Offer `Add 'Include <REPO_CFG>' at the top (Recommended)` ·
`Replace it with a link (backup kept)` · `Skip`. For the Include option, edit the
file yourself (backup first): `Include` must be the first line, because an
`Include` after a `Host` block only applies inside that block.

### Move public keys into the repo

```bash
bash "$S" adopt-keys [name.pub ...] [--apply]   # no names = every regular .pub
```
Ask which keys (multiSelect, all regular `.pub` files preselected in the
recommendation). Never touch private keys. If status shows `ssh/*.pub` is not
git-ignored, ask: `Keep them out of git - add ssh/*.pub to .gitignore
(Recommended)` · `Commit them` - public keys aren't secret, but the repo is
shared with other users, who shouldn't get this person's keys.

Mention: tools that regenerate a key (e.g. `gcloud` rewriting
`google_compute_engine.pub`) may replace the link with a regular file; re-run
`/env-ssh keys` if so.

### Undo key move

```bash
bash "$S" release-keys [name.pub ...] [--apply]
```

### Username and key (`local.conf`)

Ask both in one AskUserQuestion call:
- Username: recommend the `User` already in `USER_CONF` if present, else
  `$USER`. Some sites require a different form (for example `first_last`
  instead of `first.last`); ask rather than assume.
- Key: list the private keys status found. Recommend the one the remote
  side is known to accept - that is whichever key is in the host's
  `authorized_keys`, not necessarily `id_ed25519`. Say why.

```bash
bash "$S" user-conf --user <u> --key <path> [--hosts "<patterns>"] [--force] [--apply]
```
`--hosts` defaults to `*`; pass a narrower pattern when you have one host
family in mind. The file sets `User` and
`IdentityFile` under that pattern only - never under `Host *`. Use `--force`
only after the user agreed to replace an existing file (a backup is kept). The
file is in the repo folder but git-ignored; confirm with `status`.

### Add or edit a host

Each host has its own file, `<CONF_D>/<alias>.conf`, Included by name. Edit the
repo files yourself (normal file edits work):
1. Ask for alias, HostName, and anything non-default (port, ProxyJump, X11).
2. Copy `<CONF_D>/host.conf.template` to `<CONF_D>/<alias>.conf`.
   Keep its header block and fill it in: file path, one-line description of the
   host, `Included by: env/ssh/config  (Include config.d/<alias>.conf)`.
   `Host <alias> <fqdn>` and `HostName <fqdn>`.
3. Put **no** personal `User`/`IdentityFile` in it - those go in `local.conf`
   (widen its `Host` pattern with user-conf `--hosts` if needed) - because the
   repo is shared.
4. In `<REPO_CFG>`, under "2. Hosts", add a comment line describing the host
   and `Include config.d/<alias>.conf`. Without this line ssh ignores the file.
5. Check: `bash "$S" status` (no `NOT INCLUDED`/`MISSING`) and
   `bash "$S" verify <alias>`.
6. Offer to commit it with the gu-push skill if the user wants.

### Clean up old backups and known_hosts files

Run this after the other tasks (they make fresh backups), and before the wrap-up.

```bash
bash "$S" cleanup [--keep N] [--delete] [--apply]
```
Covers `*.bak`, `*.bak-*`, `*.bak.*`, `*.old` and `known_hosts.*` in `SSH_HOME`
and `CONF_D`, including a `config.d.bak-*` folder left by link-config. It never touches `known_hosts` itself, keys, or
`google_compute_known_hosts` (gcloud's live file).

1. Run it as a dry run and show the list (each file with its date).
2. Ask both in one AskUserQuestion call:
   - **What to keep**: `Keep the newest backup of each file (Recommended)`
     (`--keep 1`, in case this session's change needs undoing) · `Remove them all`
     (`--keep 0`) · `Let me pick` (multiSelect of the listed files, then
     `mv`/`rm` just those yourself, backing nothing up twice).
   - **How**: `Archive to ~/.ssh/.env-ssh-archive/ (Recommended)` (reversible;
     delete the folder later) · `Delete permanently` (`--delete`; say it can't be
     undone).
3. Re-run with the chosen flags and `--apply`.

`known_hosts.old` is the copy `ssh-keygen -R` leaves behind; removing it is
safe. If the user wants stale host entries removed from `known_hosts` itself,
use `ssh-keygen -R <host>` per host after confirming each one.

### Verify and test

```bash
bash "$S" verify [host ...]   # no hosts = every concrete Host in the repo config
bash "$S" test <host>          # BatchMode login, 8s timeout; never prompts
```
Show `user@hostname` and the keys per host and flag missing keys. Ask before
`test`, because it connects to the remote machine. On failure, read the error:
- `Permission denied (publickey)` → wrong key or user; offer the user-conf task
  with the other key. If the key is simply not on the host yet, the public key
  has to be added to the host's `authorized_keys` first.
- `Could not resolve hostname` / timeout → network or VPN, not this config.
- `Bad configuration option` → show the line; fix it in the repo config
  (macOS-only options need `IgnoreUnknown` before them).

## 4. Wrap up

Re-run `perms` (new files such as backups or a rewritten `local.conf`
must be locked down too) and `status`, and report in a few lines what changed, where the backups are
(`*.bak-<timestamp>`), and anything left for the user to do. If repo files
changed (`ssh/config`, `ssh/config.d/<host>.conf`, `.gitignore`), say they are
uncommitted and offer the gu-push skill. `local.conf` is never committed.
