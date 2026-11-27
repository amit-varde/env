---
name: gu-actions
description: Operate GitHub Actions - list workflows and runs, read failing logs, download artifacts, re-run failed jobs, cancel runs, trigger workflow_dispatch with inputs, and write or fix workflow YAML safely. Use for "rerun CI", "trigger the workflow", "cancel that run", "download the build artifact", "why did the workflow fail", or editing .github/workflows.
argument-hint: "[run-id | workflow]"
---

# GitHub Actions

Follow `~/.claude/skills/gu-common/CONVENTIONS.md`. `gu` = `bash ~/.claude/skills/gu-common/bin/gu`.
`gu ctx` shows `ci:`. With `jenkins` and no `actions(...)`, gh can't see this CI: say so and give the link.

## Read (run yourself)
- Recent runs on the branch: `gu ci` (or `--branch B`). With several runs, ask which, the latest failed one first.
- A run's failing jobs and first errors: `gu ci --run <id>`. A PR's failures: `gu ci <pr>` (includes the flaky check on main).
- Full logs if needed: `gh run view <id> --job <job-id> --log | tail -200`. Workflows: `gh workflow list`.

## Change things (state exactly what will run, then confirm)
| When | Options (recommended first) |
|---|---|
| Failed run | `Diagnose` · `Re-run failed jobs` (`gh run rerun <id> --failed`; recommend if flaky on main) · `Re-run all` · `Cancel` (`gh run cancel <id>`) |
| Dispatch | `Ref`: current branch · main; then one question per YAML input, with its `options:`/`default` (default first). Run: `gh workflow run <file> --ref <r> -f k=v` (needs `on: workflow_dispatch`) |
| Deploy or release workflow | `Just show what it would do` · `Run it` |
| Artifact | `Download <name> (<size>)` -> `gh run download <id> --name <n> --dir "$TMPDIR/run-<id>"` (fresh dir, untrusted, never execute) · `Just list` |

Don't re-run more than once to "make it pass"; report the flake. `gh secret list`/`gh variable list` are read-only;
setting secrets only on explicit request, and never echo the values.

## Editing workflow YAML
Pin third-party actions to a commit SHA; give each job minimal `permissions:`; never `pull_request_target` with a PR
checkout; pass untrusted `${{ github.event.* }}` through `env:`, never inline in `run:`. Validate with `actionlint` if
available. Changes take effect only once pushed, so test on a branch via dispatch or a PR. Ask `Apply` · `Show the diff only`.
