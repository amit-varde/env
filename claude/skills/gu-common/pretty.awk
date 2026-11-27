# gu-common/pretty.awk - terminal view of gu output. bin/gu pipes stdout through it only when
# stdout is a terminal (lib.sh: gu_color), so skills and scripts always get the plain | rows.
# - A run of 2+ lines with the same number of | fields is a table: columns are aligned, a header row
#   (all lowercase words) is bold, and known states are colored. Other | lines (log text) are left alone.
# - "key: value" lines get a cyan key; added:/removed:/kept:/REFUSED and similar lines are colored.
# POSIX awk (macOS awk and gawk). Lines stream, except table runs, which print when the run ends.

BEGIN {
  R = "\033[0m"; B = "\033[1m"; DIM = "\033[2m"
  # Google palette (lib.sh: gu_palette): blue, red, yellow, green. CYN is the blue.
  if (truecolor == 1) {
    CYN = "\033[38;2;66;133;244m"; RED = "\033[38;2;234;67;53m"
    YEL = "\033[38;2;251;188;5m"; GRN = "\033[38;2;52;168;83m"
  } else {
    CYN = "\033[38;5;69m"; RED = "\033[38;5;203m"; YEL = "\033[38;5;214m"; GRN = "\033[38;5;71m"
  }
  MAG = "\033[35m"
  n = 0
}

function word(t) {                      # color one space-separated state word
  if (t ~ /^(merged|merged\(#[0-9]+\)|pass|CURRENT|FF|ok)$/) return GRN t R
  if (t ~ /^(LOCKED|LOCKED\(.*\)|missing|MERGE_CONFLICT|fail|FETCH_FAILED.*|BLOCKED|DIRTY|UPSTREAM_GONE|GONE)$/) return RED t R
  if (t ~ /^(upstream-gone|pr-merged.*|pending|DECIDE|BEHIND|DEFAULT|no-upstream|LFS|incoming-\.claude|not-at-recorded-commit|.*commits-on-no-remote|DRAFT)$/) return YEL t R
  if (t ~ /^main$/) return CYN t R
  if (t ~ /^(outside|-)$/) return DIM t R
  if (t ~ /^DETACHED@/) return MAG t R
  return t
}

function cell(v, col,   k, a, i, out) {
  if (hdr[col] ~ /^(dirty|untracked|stash)$/ && v ~ /^[1-9][0-9]*$/) return YEL v R
  if (hdr[col] ~ /behind\/ahead$/ && v ~ /^[0-9]+\/[0-9]+$/ && v != "0/0") return YEL v R
  # Names and paths keep their own text (a branch called "main" is not the "main" note).
  if (hdr[col] ~ /^(repo|path|branch|upstream|default|title|url|last commit|author|head|base)$/)
    return (v ~ /^DETACHED@/) ? MAG v R : v
  k = split(v, a, " "); out = ""
  for (i = 1; i <= k; i++) out = out (i > 1 ? " " : "") word(a[i])
  return out
}

function is_header(line,   k, a, i) {
  k = split(line, a, "|")
  for (i = 1; i <= k; i++) if (a[i] !~ /^ *[a-z][a-z_\/ .]*$/) return 0
  return 1
}

function flush(   i, j, k, a, w, nf, v, out, header) {
  if (n == 0) return
  nf = split(rows[1], a, "|")
  for (i = 2; i <= n; i++) if (split(rows[i], a, "|") != nf) nf = -1
  if (n < 2 || nf < 2) {                 # not a table: print as it came
    for (i = 1; i <= n; i++) print rows[i]
    n = 0; return
  }
  header = is_header(rows[1])
  for (j = 1; j <= nf; j++) { w[j] = 0; hdr[j] = "" }
  for (i = 1; i <= n; i++) {
    k = split(rows[i], a, "|")
    for (j = 1; j <= k; j++) if (length(a[j]) > w[j]) w[j] = length(a[j])
  }
  if (header) { split(rows[1], a, "|"); for (j = 1; j <= nf; j++) { hdr[j] = a[j]; sub(/^ +/, "", hdr[j]) } }
  for (i = 1; i <= n; i++) {
    k = split(rows[i], a, "|"); out = ""
    for (j = 1; j <= k; j++) {
      v = a[j]
      out = out ((i == 1 && header) ? B v R : cell(v, j))
      if (j < k) out = out sprintf("%" (w[j] - length(v) + 2) "s", "")
    }
    print out
  }
  n = 0
  fflush()
}

/\|/ { rows[++n] = $0; next }
{ flush() }
/^== .* ==$/                                   { print B $0 R; fflush(); next }
/^(REFUSED|NEEDS_USER|gh: )/                   { print RED $0 R; fflush(); next }
/^(added|removed|moved|deleted branch|branch|pruned|locked|unlocked):? / { print GRN $0 R; fflush(); next }
/^(kept|already locked|not locked|nothing to prune|note): ?/ { print YEL $0 R; fflush(); next }
/^[a-z][a-z_\/-]*: / {
  i = index($0, ": ")
  print CYN substr($0, 1, i) R substr($0, i + 1); fflush(); next
}
{ print; fflush() }
END { flush() }
