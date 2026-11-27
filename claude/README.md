# claude/

- `CLAUDE.md.example` -> `~/.claude/CLAUDE.md` (user-level instructions). Shipped as
  `.example` so setup never overwrites a real one; `setup-env.sh` offers to copy it
  and defaults to no.
- `settings.json` -> linked as `~/.claude/settings.json` by `setup-env.sh`
  (permission baseline, sandbox, and Code Mode on by default; see
  [Claude Code](../docs/claude-code.md)). Opt out per machine with
  `settings.local.json.example`.
- `skills/` -> each folder holding a `SKILL.md` is linked into `~/.claude/skills/`
  (see [Claude Code skills](../docs/claude-skills.md)).

Your own `~/.claude` (agents, commands, skills, hooks) is not readable by the assistant. Run `scripts/export-claude.sh` locally;
it writes a scrubbed copy to `_review/claude/` (gitignored). Review it, then move what you want to keep into this folder, and run the scan ([Privacy](../docs/privacy.md)).

Not portable on purpose (never copy): `~/.claude.json`, `.credentials*`, `projects/`, `history`, `todos/`, `shell-snapshots/`, `statsig/`, MCP server configs with tokens.
