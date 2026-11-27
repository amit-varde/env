# Claude Code settings and Code Mode

[← README](../README.md)

This repo keeps **user** Claude Code settings in `claude/` and wires them to
`~/.claude` during setup. Skills live in the same tree; see
[Claude Code skills](claude-skills.md) for `/gu-*` and the rest.

Anthropic's [Code Mode](https://code.claude.com/docs/en/code-mode) is an
experimental way for the terminal CLI to run several tool calls from one piece of
JavaScript instead of one round trip per tool. **This repo turns Code Mode on by
default** in the shared `settings.json`, checks it in `env-doctor`, and documents
how to opt out on one machine without changing the team baseline.

Code Mode is **terminal `claude` only**. It does not apply to the Cursor agent
panel, the Claude Desktop app, or cloud sessions. Nothing in `env.sh` or your
shell rc is required beyond the usual `source …/env.sh` line.

## What landed on `main`

When the Code Mode work merged, these paths changed:

| Path | Change |
|---|---|
| `claude/settings.json` | New `env` block: `"CLAUDE_CODE_EXPERIMENTAL_CODE_MODE": "1"` |
| `claude/settings.local.json.example` | Template to set `"0"` on one machine (copy to `settings.local.json`) |
| `.gitignore` | Track `settings.local.json.example`; real `settings.local.json` stays ignored under `claude/*` |
| `bin/env-doctor` | Reports effective Code Mode flag and whether `claude` is ≥ 2.1.323 |
| `lib/common.bash` (`do_claude`) | Notes Code Mode when linking settings or when `~/.claude` is already the repo folder |
| `docs/customize.md`, `docs/setup.md` | Short pointers; this page is the full reference |

Related work on the same branch train (not Code Mode itself): dev tools moved to
interactive `tools/install.sh`, with `env-install` / `pydev-install` as shell
front doors — see [Setup → Tools](setup.md#tools) and [Shell](shell.md).

## Layout

| File in the repo | Role |
|---|---|
| `claude/settings.json` | Shared user settings: permissions, sandbox, **Code Mode on**, theme |
| `claude/settings.local.json` | Per-machine overrides (git-ignored). Not committed; create from the example |
| `claude/settings.local.json.example` | Shows how to turn Code Mode off locally |
| `claude/skills/` | Skills exposed as `/commands` |
| `claude/CLAUDE.md.example` | Optional starter for `~/.claude/CLAUDE.md` (your working preferences) |

Claude Code reads **`~/.claude/settings.json` as user settings**. It does **not**
honour `CLAUDE_CODE_EXPERIMENTAL_CODE_MODE` in a **project** `.claude/settings.json`
inside a repo you are working in — only user-level config counts.

### How `~/.claude` is wired

`setup-env.sh` step `claude` does one of two things:

1. **Recommended:** `~/.claude` is a symlink to `<env-repo>/claude/`. Settings,
   skills, and a local `settings.local.json` all live in the repo working tree
   (local file stays untracked).
2. **Alternative:** `~/.claude` is a normal directory; `settings.json` and each
   skill folder are **links** into the repo.

`env-doctor` reports which layout you have and whether settings match the repo.

## Code Mode default

The shared baseline includes:

```json
"env": {
  "CLAUDE_CODE_EXPERIMENTAL_CODE_MODE": "1"
}
```

After setup, start an interactive terminal session:

```bash
claude
```

The first time, Claude Code asks you to confirm Code Mode. When it is active you
should see a line near the top of the session:

```text
Code Mode (experimental) is on · this session can be resumed only with Code Mode on
```

Press `Ctrl+O` in the session to open the transcript viewer and expand **Code**
rows to see the JavaScript behind batched tool calls.

### Who sets the flag (precedence)

Claude Code merges user settings. For the effective value of
`CLAUDE_CODE_EXPERIMENTAL_CODE_MODE`:

1. **Shell environment** for this launch (e.g. `CLAUDE_CODE_EXPERIMENTAL_CODE_MODE=0 claude`)
2. **`settings.local.json`** `env` block (machine-specific)
3. **`settings.json`** `env` block (this repo's shared default)

If **any** layer sets `"0"`, Code Mode stays off even if another layer sets `"1"`.

`env-doctor` computes the effective value (settings → local → shell) and prints
`ok` or `warn` with the source.

### Requirements (Anthropic)

Code Mode still needs Anthropic's own gates. If it does not start, run `/status`
in the session; the banner often names the reason. Common requirements:

| Requirement | Notes |
|---|---|
| CLI version | **≥ 2.1.323** (`claude update`; `env-doctor` checks this) |
| Surface | Interactive **terminal** `claude` |
| Account | Claude subscription or Console; direct Anthropic API (no Bedrock, gateway, or custom `ANTHROPIC_BASE_URL` unless docs allow) |
| Model | Opus 5.5, Sonnet 5.5, Haiku 5.5, or Fable 5.2 |
| Installation | Native Claude Code build (install via `env-install claude` or `tools/install_claude.sh`) |

Version-specific extras (agent teams, mods with hooks, OpenTelemetry) are listed
in [Anthropic's requirements](https://code.claude.com/docs/en/code-mode#requirements).

### Limitations (summary)

Plan around these before relying on Code Mode for long sessions:

- **Resume / continue:** Code Mode sessions resume only with the flag still `"1"`.
  `claude --continue` or `claude --resume` with Code Mode off refuses those sessions.
- **No** Remote Control, Claude in Chrome, or computer use in Code Mode sessions.
- **No** moving the session to Desktop or starting a background copy with `/fork`.
- Auto mode reviews the **code**, not each tool call; sandbox still applies to **shell**
  commands inside that code.
- Long-running code: up to ten minutes in the foreground (with caveats in Anthropic's docs).

Full list: [Code Mode limitations](https://code.claude.com/docs/en/code-mode#code-mode-limitations).

## Turn Code Mode off

Pick one layer; prefer local override so the shared repo stays `"1"` for everyone else.

### One machine only (recommended)

```bash
cp claude/settings.local.json.example claude/settings.local.json
```

Edit if needed — the example sets `"CLAUDE_CODE_EXPERIMENTAL_CODE_MODE": "0"`. The
file is git-ignored (`claude/*` with exceptions in `.gitignore`).

### Every machine using this env repo

Edit `claude/settings.json` and set `"0"`, or remove the `env` key. Commit and pull
on other machines.

### One shell invocation

```bash
CLAUDE_CODE_EXPERIMENTAL_CODE_MODE=0 claude
```

## Shared settings beyond Code Mode

`claude/settings.json` is the team baseline for **permissions** and **sandbox** as
well as Code Mode. Code Mode does not replace those rules: each tool call inside
generated code still goes through `allow` / `ask` / `deny`, `PreToolUse` hooks, and
sandbox settings.

| Area | What the repo configures |
|---|---|
| `permissions.allow` | Read-only and normal `git` / `gh` workflows |
| `permissions.ask` | Force-push, hard branch delete, destructive `gh api` |
| `permissions.deny` | `.env`, keys, `~/.ssh`, `~/.aws`, `~/.gnupg` |
| `sandbox` | Enabled; no unsandboxed commands; weaker network isolation on macOS for `gh` via `trustd` |

Optional hardening for Code Mode (not in the default file): add `"ask": ["REPL"]` so
you approve each code blob before it runs — see
[Anthropic: approve each piece of code](https://code.claude.com/docs/en/code-mode#approve-each-piece-of-code-first).

To tighten or loosen behaviour, edit `claude/settings.json` and commit, or use
Claude Code's settings UI on a linked file and commit the diff.

## Setup and health checks

| Action | Command |
|---|---|
| Wire Claude settings and skills | `./setup-env.sh --only claude` |
| Full report | `env-doctor` |
| Problems only | `env-doctor -q` |

In the **Claude Code settings and skills** section, `env-doctor` reports:

- Whether `~/.claude` is the repo's `claude/` folder or linked files
- Skill front matter and broken skill links
- **Code Mode** on/off and which layer set it
- **`claude` version** versus 2.1.323

Example when everything matches the default:

```text
  ok    ~/.claude is the repo's claude/ folder
  ok    Code Mode on (CLAUDE_CODE_EXPERIMENTAL_CODE_MODE=1 in shared settings.json)
  ok    claude 2.1.326 (>= 2.1.323 for Code Mode)
```

## Troubleshooting

| Symptom | What to check |
|---|---|
| No Code Mode banner | `env-doctor`; `claude --version`; effective flag not `0`; terminal `claude`, not IDE panel |
| `isn't open to your account yet` | Update CLI; account rollout; try again later |
| `only works directly with the Anthropic API` | Remove gateway / Bedrock / custom base URL / `apiKeyHelper` |
| Can't resume session | Start with Code Mode on (`"1"` in user settings); see [resume warning](https://code.claude.com/docs/en/code-mode#turn-off-code-mode) |
| Hook timeouts under Code Mode | `PreToolUse` hooks must finish; bash hooks should match compound commands — [tool call refused](https://code.claude.com/docs/en/code-mode#tool-call-refused-by-a-hook) |

Anthropic's table for banner reasons:
[Code Mode doesn't start](https://code.claude.com/docs/en/code-mode#code-mode-doesnt-start).

## Customize checklist

| Goal | Edit |
|---|---|
| Code Mode default for everyone | `claude/settings.json` → `env.CLAUDE_CODE_EXPERIMENTAL_CODE_MODE` |
| Opt out on this Mac only | `claude/settings.local.json` from `settings.local.json.example` |
| Git/gh permission policy | `claude/settings.json` → `permissions` |
| New skill | `claude/skills/<name>/SKILL.md` ([skills doc](claude-skills.md)) |
| Personal instructions file | `~/.claude/CLAUDE.md` (from `CLAUDE.md.example` via setup) |

After doc or path changes, update [Customize](customize.md) and the index in
[README](../README.md).

## Related

- [Claude Code skills](claude-skills.md) — `/gu-*` and machine setup skills
- [Customize](customize.md) — first files to edit in a fork
- [Setup](setup.md) — `setup-env.sh` steps and `env-doctor`
- [Worktree flow](worktree-flow.md) — worktrees under `<repo>/.claude/worktrees/`
- [Anthropic: Code Mode](https://code.claude.com/docs/en/code-mode) — upstream behaviour and API details