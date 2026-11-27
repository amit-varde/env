# Privacy

[← README](../README.md)

This repo is public. Everything in it is meant to be readable by anyone, which
means the interesting question is not "what is in it" but "what keeps the rest
out". This page is that answer.

## What must never be committed

| Never | Instead |
|---|---|
| Private keys (`id_*`, `*.pem`, `*.key`) | 1Password; `scripts/install-ssh-keys.sh` writes them to `~/.ssh` |
| Employer, project, customer or internal host names | `.blocklist.local`, and `~/.zshrc.local` for anything in your shell |
| Internal hostnames and addresses in SSH config | `ssh/config.d/*.conf` (git-ignored), published only as `*.conf.gpg` |
| Tokens, API keys, passwords | A secrets manager or the OS keychain, never an rc file or `settings.json` `env` |
| Absolute home paths (`/Users/you`, `/home/you`) | `$HOME` |
| Your email address | `git@`, `you@` or a `users.noreply.github.com` address |
| `~/.claude.json`, `.credentials*`, `projects/`, `history`, `todos/`, `shell-snapshots/`, `statsig/`, MCP configs with tokens | Nothing: these are not portable, and the export scrubber refuses to copy them |

`.gitignore` already excludes the obvious shapes (`_review/`, `*.local`,
`ssh/config.d/*.conf`, `id_*` except `*.pub`, `*.pem`, `*.key`, `.env*`), but
`.gitignore` only stops a file being added by accident. The scan is what stops
the content.

## The scan

One engine, `bin/env-scan`, behind every entry point: `env-scan` on the command
line, `./scripts/scan.sh`, the pre-commit hook, and CI. Its patterns live in
`lib/scan-patterns.bash` and nowhere else, so the scrubbers and the gate cannot
drift apart.

Five categories:

| Category | What it flags |
|---|---|
| `secret` | Private-key blocks, and AWS, GitHub, Slack, Google, OpenAI-shaped and JWT tokens |
| `assign` | A `key`/`token`/`secret`/`password`/`credential`/`auth` assignment whose value looks literal |
| `abs-path` | `/Users/<name>` or `/home/<name>`, unless the name is a known placeholder (`yourname`, `runner`, `ubuntu`, …) |
| `email` | Any address, unless it is a placeholder or a `noreply` / `users.noreply.github.com` / `openssh.com` address |
| `blocklist` | Your own terms from `.blocklist.local` |

It reports the file and line only, never the matching text, so its own output is
safe to paste. A line with `env-scan:ignore` in it is skipped. Narrow a run with
`--only`/`--skip`, and use `--staged` for staged changes alone.

```bash
env-scan                      # everything git would commit
env-scan --only secret        # one category
env-scan --skip email         # all but one
```

### Your own terms

`blocklist.example` is a template, not a live blocklist: copy it.

```bash
cp blocklist.example .blocklist.local
```

One case-insensitive extended regex per line — your employer, products,
internal projects, host and domain names. `.blocklist.local` is git-ignored,
which is unavoidable: a public repo cannot carry the list of names it must not
mention. Two consequences worth being clear about:

- **Without it, the blocklist category does nothing.** The scan says so when it
  runs. The other four categories still work.
- **CI cannot see it.** Add the same list as a repository secret named
  `ENV_BLOCKLIST` (Settings → Secrets and variables → Actions) and the workflow
  writes it before scanning. Secrets are not available to pull requests from
  forks, so on those runs the blocklist category is skipped.

The pre-commit hook on your own machine is therefore the real gate for your own
terms. CI is the backstop for everything else.

## The two gates

**Pre-commit hook.** `setup-env.sh --only hooks` installs it. It runs
`env-scan --staged` and refuses the commit on any finding:

```
git commit -m "..."        # refused, with the file and line
git commit --no-verify     # bypasses it
```

`--no-verify` exists, which is exactly why there is a second gate.

**CI.** `.github/workflows/ci.yml` runs the full scan on every push to `main`
and every pull request, so anything committed with `--no-verify` is caught
before it merges. The same workflow proves the hook still works, by installing
it in a throwaway repo and checking that a commit carrying a fake AWS key is
refused — a change that quietly disables the hook fails the build.

## Exporting your real files

The scrubbers never write into the tracked tree (public keys are the one
exception). They write to `_review/`, which is git-ignored, and you decide what
moves.

```bash
./scripts/export-claude.sh                    # ~/.claude      -> _review/claude/
./scripts/export-dotfiles.sh                  # your rc files  -> _review/dotfiles/
./scripts/export-ssh-pub.sh amit-varde        # ~/.ssh/*.pub   -> .ssh/keys/
```

- `export-claude.sh` copies an allowlist only (`CLAUDE.md`, `settings.json`,
  `agents`, `commands`, `skills`, `output-styles`) and strips `env`,
  `apiKeyHelper`, the AWS credential helpers, `mcpServers` and any permission
  rule mentioning an absolute path or a secret word. It keeps `hooks` and tells
  you to read them, because a hook command can embed anything.
- `export-dotfiles.sh` works line by line, replacing each dropped line with
  `# [removed: <reason>]` and rewriting `$HOME` paths. The reasons go to
  `<name>.removed.txt` as a line number and a category — never the text of the
  line, since that file would otherwise hold the secret it just removed.
- `export-ssh-pub.sh` is the one scrubber that writes into the repo, into
  `.ssh/keys/`. It renames each key's comment to the file name, so a key's
  `user@host` label does not leak, and never reads a private key.

Then read `_review/`, move what you want into `claude/` and `dotfiles/`, and run
the scan.

## SSH host config

Host files are per-host, under `ssh/config.d/`. Plaintext `*.conf` is
git-ignored; the published form is `*.conf.gpg`.

```bash
cp ssh/config.d/host.conf.template ssh/config.d/myhost.conf
$EDITOR ssh/config.d/myhost.conf
# add:  Include config.d/myhost.conf   to ssh/config
./scripts/export-ssh-config.sh        # -> myhost.conf.gpg
```

`ssh/config` is an explicit index: a file in `config.d/` does nothing until
`ssh/config` lists it. `setup-env.sh`'s ssh step decrypts every `*.conf.gpg`
back to its git-ignored plaintext and warns when `ssh/config` has no `Include`
line for the result.

Keep the passphrase in a password manager, never in this repo. For a run with no
terminal, point `SSH_CONFIG_PASS_FILE` at a file holding it; without a terminal
and without that variable, the ssh step skips decryption rather than hanging.

Host files hold shared settings only. `User` and `IdentityFile` are yours and go
in `ssh/config.d/local.conf`, which is git-ignored and which `ssh/config`
includes first, so it wins.

## SSH keys

Private keys stay in 1Password.

```bash
./scripts/install-ssh-keys.sh --dry-run
./scripts/install-ssh-keys.sh
~/.ssh/perms.sh --verify              # add --fix to correct the modes
```

It matches each `.ssh/keys/*.pub` to a 1Password SSH Key item **by fingerprint**,
writes the private half to `~/.ssh/id_<type>` at mode 600, re-checks the
fingerprint afterwards and refuses on a mismatch, overwrites its temporary file
before deleting it, and leaves an existing key alone when the fingerprint
already matches.

Prefer a separate key per employer or account. One public key reused everywhere
is a stable identifier that lets anyone correlate your accounts, and `.ssh/keys/`
is public.

`setup-env.sh --authorize-keys` appends `.ssh/keys/*.pub` to
`~/.ssh/authorized_keys`. It is off by default because it grants login to
whoever holds the matching private keys.

## If something did get committed

Treat it as disclosed. A public repo is cloned, cached and mirrored, so removing
the file in a later commit does not unpublish it.

1. Rotate first: revoke the key or token, change the password. That is the only
   step that actually helps.
2. Add the term to `.blocklist.local` (and to the `ENV_BLOCKLIST` secret) so it
   cannot come back.
3. Only then worry about history.
