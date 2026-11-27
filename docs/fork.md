# Forks

[← README](../README.md)

Make your own copy of this repo on GitHub, change it however you like, and still
take in what changes in the original, or send your improvements back. Both
directions go through pull requests.

## Fork when you set up

`bootstrap.sh` asks after you log in to GitHub:

```
Fork amit-varde/env into your own GitHub repo and work on the fork? [Y/n]
Fork owner (your login or an organization) [<you>]:
Fork name [env]:
```

The default is **yes**, unless your GitHub login owns the repo (then it is no).
Saying yes creates the fork with `gh repo fork` (or reuses it if you already
have one), clones the fork to `<WORK>/env`, and adds the original as the
`upstream` remote with pushing to it disabled. The fork is a normal GitHub fork:
it stays private if the original is, and GitHub deletes it if you lose access
to the original.

| Option | Effect |
|---|---|
| `--fork` | Fork without asking |
| `--fork-org ORG` | Create the fork in an organization instead of your account (implies `--fork`) |
| `--fork-name NAME` | Name the fork (default `env`; implies `--fork`) |
| `--no-fork` | Clone the original itself |
| `ENV_FORK=1\|0\|auto` | Same, from the environment |

`-y` never forks unless you also pass `--fork` (or one of the options that imply it).

Already have a clone of a fork (made by hand, say)? Re-run `bootstrap.sh` or
`setup-env.sh`: the repo step asks GitHub for the fork's parent and offers to add
the `upstream` remote. `env-doctor` shows the fork and how far behind it is.

## Keep it in step: `/gu-fork-sync`

In Claude Code, `/gu-fork-sync` (in any repo that is a GitHub fork, not only this one):

| You want to | It does |
|---|---|
| See what changed | `gu fork status`: commits in the original that your fork lacks, your commits the original lacks, and files changed on both sides |
| Pull the original's changes into your fork | Asks merge or rebase every time, makes a `sync/upstream-<date>` branch in a worktree, walks through conflicts one file at a time, opens a PR into your fork, and after CI lands it as a fast-forward so the original's commits keep their SHAs |
| Send your changes to the original | You pick commits; it cherry-picks them onto the original's `main` in a `send/<name>` branch, checks the original's README, pushes to your fork and opens a PR on the original |
| (The original's owner) take changes from forks | Lists every fork with its new commits, cherry-picks the ones you pick (authors kept) onto a `take/<name>` branch and opens a PR |

For this repo it also runs the tests after a pull, offers to re-run
`setup-env.sh` for the steps whose files changed (Claude settings and skills,
SSH, Cursor, dotfiles, tools, shell), and runs `env-doctor`.

Never squash-merge or rebase-merge a sync PR: that rewrites the original's
commits, and every later sync conflicts with them. `/gu-fork-sync` lands it as a
fast-forward, or with a merge commit when the branch is protected.

## Keep merges easy

Put what only you need in the git-ignored files, so it never conflicts:

| Personal | Where |
|---|---|
| Machine paths (`WORK`, `DL`, `DOCS`, `EDITOR_APP`) | `.env.host` |
| Your SSH user and key | `ssh/config.d/local.conf` |
| Claude Code opt-outs | `claude/settings.local.json` |
| Secret-scan terms | `.blocklist.local` |

Edits to shared files (`alias`, `lib/`, `ssh/config.d/<host>.conf`, skills) are
fine in a fork; they are what can conflict on the next pull, and the ones worth
sending back. Keep a change you mean to send back in its own commit.

## By hand

`gu fork` is the command half of the skill (`gu help`):

```bash
gu fork status
gu fork wire            # add `upstream` (from GitHub's parent link), disable pushing to it
gu fork pull --merge    # sync/upstream-<date> worktree branch; then push it and open a PR
gu fork land <branch>   # fast-forward your fork's main to the reviewed branch
gu fork send --name send/fix-x <sha>...
gu fork forks --fetch   # the original's owner: what each fork has
gu fork take --name take/alice-fix-x <sha>...
```
