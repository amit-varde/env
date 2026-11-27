---
name: gu-release
description: Cut and manage GitHub releases and tags - suggest the next version, draft grouped release notes from what merged since the last tag, create a (draft) release and tag, upload assets, publish, list, download, edit or delete releases. Use for "cut a release", "tag v1.2.0", "write release notes", "what changed since the last release", "publish the release".
argument-hint: "[version]"
---

# Releases

Follow `~/.claude/skills/gu-common/CONVENTIONS.md`. `gu` = `bash ~/.claude/skills/gu-common/bin/gu`.

## Cut a release
1. **Facts:** `gu release [repo] [--target B]` prints the last tag, commits since, the suggested version with the reason,
   and a notes draft grouped Breaking / Features / Fixes / Other. Also `gh release list --limit 5`.
2. **Version** (skip if given): `<suggested>` · the other SemVer bumps · `-rc.1` prerelease. Follow the repo's tag scheme.
3. **Notes:** `Use the grouped draft` (show it, edited into one line per PR) · `GitHub --generate-notes` · `I'll write them`.
4. **Check:** CI is green on the target (`gu ci --branch <target>`), and version files or the changelog are bumped if the repo keeps them.
5. **Create:** `Draft release` · `Publish now` (notifies watchers and may trigger deploys) · `Tag only`.
   ```bash
   gh release create vX.Y.Z --target <target> --draft --title "vX.Y.Z" --notes-file notes.md   # or --generate-notes; --prerelease for rc
   gh release upload vX.Y.Z dist/*                    # assets, if any
   gh release edit vX.Y.Z --draft=false               # publish, after another yes
   git tag -a vX.Y.Z -m vX.Y.Z <sha> && git push origin vX.Y.Z   # tag only
   ```

## Other
- View: `gh release view <tag>`. Download: ask (file and size), then
  `gh release download <tag> --pattern '<p>' --dir "$TMPDIR/rel-<tag>"`. Verify checksums; never execute downloads unasked.
- Mistakes: prefer a new patch release. Deleting or moving a published tag breaks anyone who has pulled it.
  `gh release delete <tag> --cleanup-tag` only with an explicit yes.
