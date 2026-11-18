#!/usr/bin/env bash
# Produce a scrubbed COPY of your global Claude Code config in _review/claude/ (allowlist only).
# Usage: ./scripts/export-claude.sh [~/.claude]
set -u; . "$(dirname "$0")/lib.sh"
SRC="${1:-$HOME/.claude}"; OUT="$ROOT/_review/claude"; mkdir -p "$OUT"; BL="$(blocklist_pattern)"
[ -d "$SRC" ] || { echo "no $SRC"; exit 1; }
# allowlist: only these are ever copied
for item in CLAUDE.md settings.json agents commands skills output-styles; do
  [ -e "$SRC/$item" ] && cp -R "$SRC/$item" "$OUT/" && echo "copied $item"
done
# settings.json: drop env/credentials helpers/absolute-path permission rules
if [ -f "$OUT/settings.json" ]; then
python3 - "$OUT/settings.json" <<'PY'
import json,re,sys
p=sys.argv[1]; d=json.load(open(p))
for k in ("env","apiKeyHelper","awsAuthRefresh","awsCredentialExport","otelHeadersHelper","mcpServers","enabledMcpjsonServers","statusLine"):
    if k in d: print("  dropped key:",k); d.pop(k)
perm=d.get("permissions",{})
for lst in ("allow","ask","deny"):
    if lst in perm:
        keep=[r for r in perm[lst] if not re.search(r"/Users/|/home/|AKIA|token|secret|password",r,re.I)]
        if len(keep)!=len(perm[lst]): print("  dropped %d %s rule(s) with absolute paths/secret words"%(len(perm[lst])-len(keep),lst))
        perm[lst]=keep
perm.pop("additionalDirectories",None)
if "hooks" in d: print("  NOTE: hooks kept - review commands for employer paths")
json.dump(d,open(p,"w"),indent=2); open(p,"a").write("\n")
PY
fi
echo "--- files with secret patterns / blocklist hits (review or delete these) ---"
grep -rIlE "$SECRET_RE" "$OUT" 2>/dev/null | sed "s#$ROOT/##" | sed 's/^/[SECRET] /'
[ -n "$BL" ] && grep -rIliE "$BL" "$OUT" 2>/dev/null | sed "s#$ROOT/##" | sed 's/^/[BLOCKLIST] /'
echo "NEXT: review _review/claude/, move generic items into claude/, then scripts/scan.sh"
