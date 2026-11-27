#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File: env/tests/test-env-load.sh
# Description: env.sh and every lib/init-*.bash load cleanly on a real login
# -----------------------------------------------------------------------------
# env.sh runs on every login, which makes a fault in it both the most expensive
# kind and the easiest to miss: the shell prints a line or two and carries on
# with a half-built environment. These checks cover the ways that happens.
#
#   1. a clean load under zsh and bash: exit 0, NO stderr, BU and PATH set, and
#      the LAST function in lib/common.bash plus the LAST alias in the alias
#      file both defined -- the proof that nothing aborted partway;
#   2. every lib/init-*.bash took effect, and a module cannot be added without
#      a probe here (the table below must cover them all);
#   3. the parse-time alias cliff. Both shells expand aliases while PARSING, so
#      a pre-existing `alias backup=...` turns `backup() {` in lib/common.bash
#      into a parse error that kills the rest of that file. env.sh switches
#      expansion off while it loads; this proves it, and proves the aliases you
#      chose to have are still yours afterwards;
#   4. `so` (re-source) is idempotent: PATH and MANPATH must not grow;
#   5. iTerm2 integration: each shell loads its own file, so a bash login never
#      sources zsh code;
#   5b. nvm: nvm.sh loads in both shells, but nvm's bash-only completion script
#      is loaded under bash alone. This is checked against a stand-in nvm, so it
#      holds on machines that have no nvm at all -- the real one is present on
#      GitHub's Linux runner and absent from macOS, which is how the bug got
#      through the first CI run;
#   6. `set -u` (nounset) and a HOME whose path contains a space;
#   7. zsh -n AND bash -n over every file a login sources. Neither parser is a
#      superset of the other, so one alone is not enough: `echo ${x^^}` and
#      `echo ${!x}` are valid bash that zsh -n rejects, while `repeat 3 do :;
#      done`, `${(X)x}` and an empty `then` block are valid zsh that bash -n
#      rejects. Neither one sees a substitution that is accepted at parse time
#      and only fails when it runs -- quoted "${x^^}" is accepted by both
#      parsers and still errors at every login on bash 3.2 and on zsh. That
#      gap is what checks 1-6 exist to cover, and nothing in CI covered it
#      before this file.
#
# Probes run in isolated shells: `zsh -f` and `bash --noprofile --norc`, each
# with HOME pointed at a temp directory, so nothing here depends on the
# machine's own rc files. NB: zsh's -f means "skip rc files", but bash's -f
# means `set -f` (NO GLOBBING), which would stop env.sh's init-*.bash glob from
# matching and make this test pass for the wrong reason. Hence --noprofile
# --norc for bash, never -f.
#
# Usage: tests/test-env-load.sh
# Exit:  0 all checks passed, 1 a check failed
# -----------------------------------------------------------------------------
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# env.sh exports BU into every configured shell, so without pinning it a
# developer running the tests from their own shell would test ANOTHER checkout.
export BU="$REPO"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check() {
    if [ "$2" -eq 0 ]; then echo "  ok   $1"; pass=$((pass + 1)); else echo "  FAIL $1 ${3:-}"; fail=$((fail + 1)); fi
}

[ -f "$REPO/env.sh" ] || { echo "no env.sh at $REPO"; exit 1; }

# Every file a login sources, in load order. term-colors.bash is pulled in by
# common.bash rather than by env.sh, so it is listed explicitly.
CHAIN="env.sh lib/common.bash lib/term-colors.bash"
for m in "$REPO"/lib/init-*.bash; do
    [ -f "$m" ] && CHAIN="$CHAIN lib/$(basename "$m")"
done
CHAIN="$CHAIN alias"

# The last function in common.bash and the last alias in the alias file. If a
# parse error aborts either file partway, these are what go missing, so they are
# what proves the whole chain was read.
LAST_COMMON_FN="$(grep -oE '^[A-Za-z_][A-Za-z0-9_-]*\(\)' "$REPO/lib/common.bash" | tail -1 | tr -d '()')"
LAST_ALIAS="$(grep -oE '^alias [A-Za-z_][A-Za-z0-9_-]*=' "$REPO/alias" | tail -1 | sed 's/alias //;s/=//')"
check "found the last function in lib/common.bash to probe for" \
    "$([ -n "$LAST_COMMON_FN" ] && echo 0 || echo 1)"
check "found the last alias in the alias file to probe for" \
    "$([ -n "$LAST_ALIAS" ] && echo 0 || echo 1)"

# --- the init-*.bash probe table ---------------------------------------------
# module|kind|what proves it ran.  fn = defines this function, var = exports a
# non-empty variable, list = this colon list contains that entry.
INIT_TABLE='init-editor|var|EDITOR
init-go-projects|fn|go_project
init-iterm2|elsewhere|group 5 below, which needs a fake HOME
init-nvm|var|NVM_DIR
init-paths|list|MANPATH:/usr/local/man
init-project-aliases|fn|gen_project_aliases
init-pyenv|var|PYENV_ROOT
init-terminal|fn|change_prompt'

# A new module with no row here would otherwise be untested, so fail on it.
for m in "$REPO"/lib/init-*.bash; do
    mod="$(basename "$m" .bash)"
    if printf '%s\n' "$INIT_TABLE" | grep -q "^$mod|"; then
        check "the probe table covers $mod" 0
    else
        check "the probe table covers $mod" 1 "(add a row to INIT_TABLE in $0)"
    fi
done

# Generate the per-module assertions once; every probe below appends them.
: > "$T/init-checks"
# bash 3.2 has no here-strings, and `for x in $VAR` does not word-split in zsh.
while IFS='|' read -r mod kind val; do
    [ -n "${mod:-}" ] || continue
    case "$kind" in
        fn)  printf 'typeset -f %s >/dev/null 2>&1 || echo "MISSING %s (no function %s)"\n' \
                 "$val" "$mod" "$val" >> "$T/init-checks" ;;
        var) printf '[ -n "${%s:-}" ] || echo "MISSING %s (%s is empty)"\n' \
                 "$val" "$mod" "$val" >> "$T/init-checks" ;;
        list) nm="${val%%:*}"; want="${val#*:}"
             printf 'case ":${%s:-}:" in *":%s:"*) ;; *) echo "MISSING %s (%s has no %s)" ;; esac\n' \
                 "$nm" "$want" "$mod" "$nm" "$want" >> "$T/init-checks" ;;
        elsewhere) ;;
    esac
done <<EOF
$INIT_TABLE
EOF

# --- probe plumbing ----------------------------------------------------------
SHELLS="bash"
if command -v zsh >/dev/null 2>&1; then
    SHELLS="zsh $SHELLS"
elif [ -n "${CI:-}" ]; then
    # Half of what this file checks is zsh-specific. Skipping it quietly in CI
    # would leave the gap it was written to close, so in CI it is a failure.
    check "zsh is installed (required when CI is set)" 1 "(install zsh in the workflow)"
else
    echo "  skip zsh not installed (set CI=1 to make this a failure instead)"
fi

# Run a probe script in an isolated shell with a throwaway HOME.
# NB: never pipe `source`. A pipeline runs it in a SUBSHELL, so every definition
# is discarded and the probe reports a failure that is its own fault. Everything
# here redirects to files instead.
run() { # 1=shell 2=script 3=HOME
    OUT=""; ERRTXT=""; RC=0
    : > "$T/err"
    case "$1" in
        zsh)  HOME="$3" zsh -f "$2" > "$T/out" 2>"$T/shell-err" ;;
        bash) HOME="$3" bash --noprofile --norc "$2" > "$T/out" 2>"$T/shell-err" ;;
    esac
    RC=$?
    OUT="$(cat "$T/out")"
    # env.sh's own stderr, plus anything the probe shell itself complained about.
    ERRTXT="$(cat "$T/err" "$T/shell-err" 2>/dev/null | tr '\n' ' ')"
}

# Lines every probe needs: load env.sh with its stderr captured to a file.
load_lines() { # 1=extra line before the load (may be empty)
    [ -z "${1:-}" ] || printf '%s\n' "$1"
    echo 'unset BU'
    printf "source '%s/env.sh' 2>'%s'\n" "$REPO" "$T/err"
    echo 'echo "RC=$?"'
}

verdict() { # 1=label
    miss="$(printf '%s\n' "$OUT" | grep '^MISSING' | tr '\n' ' ')"
    rcline="$(printf '%s\n' "$OUT" | sed -n 's/^RC=//p')"
    ok=0
    [ "$RC" -eq 0 ] || ok=1
    [ "${rcline:-1}" = 0 ] || ok=1
    [ -z "$ERRTXT" ] || ok=1
    [ -z "$miss" ] || ok=1
    check "$1" "$ok" "${miss:-}${ERRTXT:+ stderr: $ERRTXT}$([ "$RC" -eq 0 ] || printf ' (shell rc=%s)' "$RC")"
}

HOMEDIR="$T/home"; mkdir -p "$HOMEDIR"

# --- 1 & 2. a clean load, and every init module took effect ------------------
{
    load_lines ""
    printf '[ "${BU:-}" = "%s" ] || echo "MISSING BU (got ${BU:-unset})"\n' "$REPO"
    printf 'case ":$PATH:" in *":%s/bin:"*) ;; *) echo "MISSING bin-on-PATH" ;; esac\n' "$REPO"
    printf 'typeset -f %s >/dev/null 2>&1 || echo "MISSING the last function in lib/common.bash (%s)"\n' \
        "$LAST_COMMON_FN" "$LAST_COMMON_FN"
    printf 'typeset -f path_prepend >/dev/null 2>&1 || echo "MISSING path_prepend (env.sh itself)"\n'
    printf 'alias %s >/dev/null 2>&1 || echo "MISSING the last alias in the alias file (%s)"\n' \
        "$LAST_ALIAS" "$LAST_ALIAS"
    cat "$T/init-checks"
} > "$T/clean"
for sh in $SHELLS; do
    run "$sh" "$T/clean" "$HOMEDIR"
    verdict "$sh: clean load defines the whole chain, with no stderr"
done

# --- 3. the parse-time alias cliff -------------------------------------------
# Every top-level function name the chain defines, which is every name a
# pre-existing alias could turn into a parse error.
CHAIN_FNS=""
for rel in $CHAIN; do
    CHAIN_FNS="$CHAIN_FNS
$(grep -oE '^[A-Za-z_][A-Za-z0-9_-]*\(\)' "$REPO/$rel" 2>/dev/null | tr -d '()')"
done
CHAIN_FNS="$(printf '%s\n' "$CHAIN_FNS" | grep -v '^$' | sort -u)"
check "found the chain's function names to alias ($(printf '%s\n' "$CHAIN_FNS" | wc -l | tr -d ' ') of them)" \
    "$([ -n "$CHAIN_FNS" ] && echo 0 || echo 1)"

# The alias file deliberately clears these three, so they must end up functions.
GUARDED="$(sed -n 's/^unalias \(.*\) 2>\/dev\/null.*$/\1/p' "$REPO/alias" | tr ' ' '\n' | grep -v '^$')"
# A name the chain defines that the alias file does NOT clear. After loading,
# this one must still be the user's own alias: env.sh protects the parse without
# destroying aliases you chose to have.
KEEP=""
while IFS= read -r fn; do
    [ -n "$fn" ] || continue
    printf '%s\n' "$GUARDED" | grep -qx "$fn" && continue
    KEEP="$fn"; break
done <<EOF
$CHAIN_FNS
EOF
check "found an unguarded chain function to prove user aliases survive ($KEEP)" \
    "$([ -n "$KEEP" ] && echo 0 || echo 1)"

{
    # bash expands aliases only when expand_aliases is on -- which it is in
    # every interactive shell, so a login really is this hostile. zsh has no
    # such switch and always expands; it has no `shopt`, hence the redirect.
    echo 'shopt -s expand_aliases 2>/dev/null || true'
    while IFS= read -r fn; do
        [ -n "$fn" ] || continue
        printf "alias %s='echo HOSTILE'\n" "$fn"
    done <<EOF
$CHAIN_FNS
EOF
    load_lines ""
    printf 'typeset -f %s >/dev/null 2>&1 || echo "MISSING the last function in lib/common.bash (%s)"\n' \
        "$LAST_COMMON_FN" "$LAST_COMMON_FN"
    printf 'alias %s >/dev/null 2>&1 || echo "MISSING the last alias in the alias file (%s)"\n' \
        "$LAST_ALIAS" "$LAST_ALIAS"
    cat "$T/init-checks"
    # The user's own alias must survive untouched...
    printf 'case "$(alias %s 2>/dev/null)" in *HOSTILE*) ;; *) echo "MISSING the user alias %s (env.sh destroyed it)" ;; esac\n' \
        "$KEEP" "$KEEP"
    # ...while the three the alias file clears on purpose are functions.
    while IFS= read -r fn; do
        [ -n "$fn" ] || continue
        printf 'typeset -f %s >/dev/null 2>&1 || echo "MISSING %s (the alias file should have made it a function)"\n' "$fn" "$fn"
    done <<EOF
$GUARDED
EOF
} > "$T/hostile"
for sh in $SHELLS; do
    run "$sh" "$T/hostile" "$HOMEDIR"
    verdict "$sh: whole chain survives an alias on every function it defines"
done

# --- 4. re-sourcing (what `so` does) must not grow any path ------------------
{
    load_lines ""
    echo 'p1="$PATH"; m1="${MANPATH:-}"'
    printf "source '%s/env.sh' 2>>'%s'\n" "$REPO" "$T/err"
    echo '[ "$p1" = "$PATH" ] || echo "MISSING stable PATH (re-sourcing grew it)"'
    echo '[ "$m1" = "${MANPATH:-}" ] || echo "MISSING stable MANPATH (re-sourcing grew it)"'
} > "$T/again"
for sh in $SHELLS; do
    run "$sh" "$T/again" "$HOMEDIR"
    verdict "$sh: re-sourcing env.sh leaves PATH and MANPATH unchanged"
done

# --- 5. iTerm2 integration is per-shell --------------------------------------
# The module only does anything on macOS, so on Linux there is nothing to test.
if [ "$(uname -s)" = Darwin ]; then
    IH="$T/iterm-home"; mkdir -p "$IH"
    # Stand-ins using the zsh-only constructs iTerm2's real file contains. If
    # env.sh loads the wrong one, the shell says so on stderr at every login.
    printf 'autoload -Uz add-zsh-hook\nsetopt prompt_subst\nexport BU_ITERM_PROOF=zsh\n' \
        > "$IH/.iterm2_shell_integration.zsh"
    printf 'export BU_ITERM_PROOF=bash\n' > "$IH/.iterm2_shell_integration.bash"
    for sh in $SHELLS; do
        { load_lines ""
          printf '[ "${BU_ITERM_PROOF:-}" = %s ] || echo "MISSING init-iterm2 (loaded ${BU_ITERM_PROOF:-nothing}, wanted %s)"\n' "$sh" "$sh"
        } > "$T/iterm"
        run "$sh" "$T/iterm" "$IH"
        verdict "$sh: loads its own iTerm2 integration file, not the other shell's"
    done
else
    echo "  skip init-iterm2 is macOS-only"
fi

# --- 5b. nvm's completion is bash-only; nvm.sh is not -----------------------
# A stand-in nvm, so this runs everywhere rather than only where nvm exists.
# NVM_DIR is honoured from the environment by init-nvm.bash, which is exactly
# how GitHub's Linux runner (which exports it) differs from macOS (which does
# not) -- so set it explicitly and test both shells on every platform.
NVMDIR="$T/nvm"; mkdir -p "$NVMDIR"
printf 'export BU_NVM_SH=loaded\n' > "$NVMDIR/nvm.sh"
# The real file ends in `complete`, a bash builtin zsh does not have.
printf '#!/usr/bin/env bash\nexport BU_NVM_COMPLETION=loaded\n_bu_fake_nvm() { :; }\ncomplete -o default -F _bu_fake_nvm nvm\n' \
    > "$NVMDIR/bash_completion"
for sh in $SHELLS; do
    { printf "export NVM_DIR='%s'\n" "$NVMDIR"
      load_lines ""
      echo '[ "${BU_NVM_SH:-}" = loaded ] || echo "MISSING nvm.sh (it supports both shells and must load)"'
      case "$sh" in
          bash) echo '[ "${BU_NVM_COMPLETION:-}" = loaded ] || echo "MISSING nvm bash_completion (bash should load it)"' ;;
          zsh*) echo '[ -z "${BU_NVM_COMPLETION:-}" ] || echo "MISSING the skip (zsh must NOT load nvm bash_completion)"' ;;
      esac
    } > "$T/nvm-probe"
    run "$sh" "$T/nvm-probe" "$HOMEDIR"
    verdict "$sh: loads nvm.sh, and nvm's bash-only completion only under bash"
done

# --- 6. nounset, and a HOME whose path contains a space ----------------------
{ load_lines 'set -u'; } > "$T/nounset"
for sh in $SHELLS; do
    run "$sh" "$T/nounset" "$HOMEDIR"
    verdict "$sh: loads under set -u (nounset)"
done

SPACEHOME="$T/a home with spaces"; mkdir -p "$SPACEHOME"
{ load_lines ""; } > "$T/spacehome"
for sh in $SHELLS; do
    run "$sh" "$T/spacehome" "$SPACEHOME"
    verdict "$sh: loads with a HOME whose path contains a space"
done

# --- 7. both parsers over every file a login sources -------------------------
# Each parser rejects constructs the other accepts (see note 7 in the header),
# so every file in the chain has to satisfy both. A file only bash ever reads
# would not need this, but every file below is sourced by both shells.
for rel in $CHAIN; do
    for parser in bash zsh; do
        command -v "$parser" >/dev/null 2>&1 || continue
        if out="$("$parser" -n "$REPO/$rel" 2>&1)"; then
            check "$parser -n $rel" 0
        else
            check "$parser -n $rel" 1 "($(printf '%s' "$out" | tr '\n' ' '))"
        fi
    done
done

echo
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ]
