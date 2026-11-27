# Cursor

[← README](../README.md)

Two commands keep Cursor the same on every machine: `cursor-ide` starts it in
IDE mode, and `cursor-sync` keeps its settings in step with the repo's `cursor/`
folder.

## IDE mode: `cursor-ide`

Cursor can start in IDE mode or in Agents mode. There is no `settings.json` key
for this. Cursor keeps the choice as `cursor/unifiedAppLayout` (`editor` or
`agent`) in its state database, `state.vscdb`, in the `globalStorage` folder of
its User folder.

`cursor-ide` reads that value and, if it is `agent`, sets it to `editor` and
then launches Cursor. In your shell, `cursor` is an alias for it, so
`cursor ~/work/env` and plain `cursor` both open in IDE mode.

```bash
cursor-ide --check            # prints editor, agent or unknown; exit 1 on agent
cursor-ide --dry-run          # show what it would do
cursor-ide --restart <dir>    # Cursor running in Agents mode: quit, fix, reopen
cursor-ide --no-fix <dir>     # open as it is, never touch the database
```

Rules it follows:

- It writes only while Cursor is **not** running. Cursor owns the database and
  rewrites it when it quits. If Cursor is running in Agents mode it asks whether
  to quit, fix and reopen it (`--restart` or `--yes` answer yes). Without a
  terminal it just opens Cursor and prints a warning.
- Before a write it backs the database up as `state.vscdb.bak-<time>` (the
  newest 3 are kept) and reads the value back to check it.
- Anything else on the command line goes to the real `cursor` command
  (a folder, a file, `--new-window`, `--wait`).

Limits:

- It only covers launches that go through it. Starting Cursor from the Dock,
  Spotlight or Finder (including double-clicking a `.code-workspace` file)
  bypasses it. `create-cursor-ide-shortcut` writes a Desktop `.app` that does
  go through it (`cursor-ide --yes <dir>`). `create-cursor-agent-shortcut`
  does the same for Agents mode (`cursor-ide --agent --yes <dir>`). Cursor
  saves its mode when it quits, so the last of these apps you open sets the
  mode until you open the other one or switch it yourself.
- This relies on an internal storage key, not a documented setting. A Cursor
  update could rename it. `cursor-ide --check` prints `unknown` when the key is
  missing, and `env-doctor` reports the mode.
- It has been tested against copies of the database. To check it end to end
  on your machine: quit Cursor, run `cursor-ide`, quit Cursor again and run
  `cursor-ide --check`; it should print `editor`.

## Settings: `cursor-sync`

| File in the repo | Goes to (macOS) |
|---|---|
| `cursor/settings.json` | `~/Library/Application Support/Cursor/User/settings.json` |
| `cursor/keybindings.json` (optional) | `.../User/keybindings.json` |
| `cursor/extensions.txt` | installed with `cursor --install-extension` |

On Linux the User folder is `~/.config/Cursor/User`.

```bash
cursor-sync                 # status of each file and the extensions
cursor-sync apply           # link the files, install missing extensions
cursor-sync apply --copy    # copy instead of link
cursor-sync export          # copy your current settings and extensions into cursor/
```

- `apply` links the files, so a change in Cursor's settings screen lands in the
  repo and shows in `git diff`. If a file already exists and differs, it asks
  first (or, without a terminal, leaves it alone); anything it replaces is saved
  as `<file>.bak-<time>`. `--force` replaces without asking.
- If Cursor ever swaps the link for a regular file, `status` shows `DIFFERS`.
  Run `export` to keep your version, or `apply --force` to take the repo's.
- `setup-env.sh` runs `cursor-sync apply` in its Cursor step.

To change the shared baseline, edit `cursor/settings.json` (it is plain JSON
that Cursor reads), or change a setting in Cursor and commit the diff.

`workbench.externalBrowser` is `default`, so links open in the system browser
rather than one named here. Two switches that live in Cursor's own storage, not
in this file, also have to be off or links still open in Cursor's built-in
browser: "Show Localhost Links in Browser" and "Open Web Links in Browser".

Working on several changes at once? Open each worktree in its own Cursor window: see [Worktree flow](worktree-flow.md#cursor-users).
