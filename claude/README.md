# claude/

- `CLAUDE.md`  -> copy to `~/.claude/CLAUDE.md` (user-level instructions)
- `settings.json` -> copy to `~/.claude/settings.json` (safe permission baseline; merge by hand if you already have one)

Your own `~/.claude` (agents, commands, skills, hooks) is not readable by the assistant. Run `scripts/export-claude.sh` locally;
it writes a scrubbed copy to `_review/claude/` (gitignored). Review it, then move what you want to keep into this folder.

Not portable on purpose (never copy): `~/.claude.json`, `.credentials*`, `projects/`, `history`, `todos/`, `shell-snapshots/`, `statsig/`, MCP server configs with tokens.
