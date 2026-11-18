# shared helpers (sourced)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BLOCKLIST="$ROOT/.blocklist.local"; [ -f "$BLOCKLIST" ] || BLOCKLIST="$ROOT/blocklist.example"
# regexes for secrets (extended, case-insensitive where noted by grep -i)
SECRET_RE='(-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[abprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{30,}|eyJ[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{15,}\.)'
ASSIGN_RE='(key|token|secret|passw(or)?d|passwd|credential|auth|bearer)[A-Za-z0-9_]*[[:space:]]*[=:][[:space:]]*["'"'"']?[^[:space:]"'"'"'$(]{6,}'
blocklist_pattern() { grep -v '^[[:space:]]*#' "$BLOCKLIST" | grep -v '^[[:space:]]*$' | paste -sd'|' -; }
