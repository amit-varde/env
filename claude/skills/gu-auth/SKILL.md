---
name: gu-auth
description: Set up, check and fix GitHub CLI authentication - log in, refresh an invalid token, add scopes, authorize SSO, choose HTTPS or SSH, make git use gh credentials, switch accounts. Use when gh says "token is invalid", "not logged in", HTTP 401/403, SAML enforcement, missing scope, git asks for a password, or the user says "log in to GitHub", "fix gh auth".
---

# GitHub auth

Follow `~/.claude/skills/gu-common/CONVENTIONS.md`. `gu` = `bash ~/.claude/skills/gu-common/bin/gu`.
**Never ask for, print or type tokens or passwords.** Login and refresh open a browser, so the user runs them
(give `! <command>`). Changing git credential or global config is persistent: ask first.

1. **Diagnose:** `gu auth` ends with `diagnosis:` codes. Fix them in this order:

| Code | Fix (user runs; recommended option first) |
|---|---|
| `ENV_TOKEN` | gh uses `GH_TOKEN`/`GITHUB_TOKEN` over the keyring. Find it (`grep -n 'GH_TOKEN\|GITHUB_TOKEN' ~/.zshrc ~/.zprofile ~/.bashrc ~/work/env/.env.host`), show the line, and let the user remove it or `unset` it |
| `TOKEN_INVALID` | `Refresh` (`gh auth refresh -h github.com`) · `Log out and in again` (`gh auth logout -h github.com`, then log in) |
| `NOT_LOGGED_IN` | `Browser login` (`gh auth login -h github.com -p https -w`) · `With a token file` (`gh auth login --with-token < file`, the user runs it; never read the file) |
| `MISSING_SCOPE:<s>` | `Add <s>` (`gh auth refresh -h github.com -s <s>`); ask for the smallest scope that fixes the failing command |
| `SSO` | The user opens github.com/settings/applications (GitHub CLI) or settings/tokens -> Configure SSO -> Authorize <org> |
| `MULTI_ACCOUNT` | One option per account, the one matching the repo's org first: `gh auth switch -h github.com -u <login>` |
| `GIT_NOT_USING_GH` | `HTTPS via gh` (`gh auth setup-git`; `gh config set git_protocol https -h github.com`) · `SSH` (recommend if remotes use `git@github.com:`) |
| `NET` | Not an auth problem: GitHub is unreachable from the sandbox. Tell the user to run `! gu auth` |

2. **SSH, if chosen:** check `ls ~/.ssh/*.pub` and `gh ssh-key list`. Ask: `Upload the existing key` (`gh ssh-key add <pub> --title "$(hostname -s)"`,
   needs the `admin:public_key` scope) · `New key` (the user runs `ssh-keygen -t ed25519`) · `I'll do it`. Test with `ssh -T git@github.com`.
   Switching a clone's remote (`git remote set-url origin git@github.com:O/R.git`) is per repo: ask first.
3. **Verify:** re-run `gu auth` (it should print `all good`, or only expected codes). Report the account, scopes, protocol and anything still failing.
