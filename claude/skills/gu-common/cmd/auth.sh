#: auth - diagnose gh/git GitHub auth: accounts, token state, scopes, env overrides, git credential helper, protocol -> diagnosis codes
# Never prints tokens. Diagnosis codes map to gu-auth/SKILL.md steps.
main() {
  local st codes=""
  kv gh "$(gh --version 2>/dev/null | head -1)"
  st=$(gh auth status 2>&1)
  printf '%s\n' "$st" | grep -E 'Logged in|Failed|Active account|Token scopes|invalid|not logged|Git operations protocol' | sed 's/^ *[-✓X] */  /'
  case "$st" in *"not logged into any"*) codes="$codes NOT_LOGGED_IN" ;; esac
  case "$st" in *invalid*|*Failed\ to\ log\ in*) codes="$codes TOKEN_INVALID" ;; esac
  [ "$(printf '%s\n' "$st" | grep -c 'Logged in\|Failed to log in')" -gt 1 ] && codes="$codes MULTI_ACCOUNT"
  local v; for v in GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GH_HOST; do
    [ -n "$(printenv $v)" ] && { kv env "$v is set (overrides keyring)"; codes="$codes ENV_TOKEN"; }
  done
  local scopes; scopes=$(printf '%s\n' "$st" | sed -n "s/.*Token scopes: //p" | head -1)
  for v in repo read:org workflow; do case "$scopes" in *"'$v'"*|"") ;; *) codes="$codes MISSING_SCOPE:$v" ;; esac; done
  kv credential.helper "$(git config --get-all credential.https://github.com.helper | tr '\n' ' ')$(git config --get-all credential.helper | tr '\n' ' ')"
  git config --get-all credential.https://github.com.helper 2>/dev/null | grep -q 'gh auth git-credential' || codes="$codes GIT_NOT_USING_GH"
  kv git_protocol "$(gh config get git_protocol -h github.com 2>/dev/null)"
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 && kv remote "$(git remote get-url origin 2>/dev/null)"
  if [ -z "$codes" ] || [ "$codes" = " GIT_NOT_USING_GH" ]; then
    local u; if u=$(ghq api user --jq .login 2>&1); then kv api "ok as $u"; else kv api "$u"; case "$u" in *NET*) codes="$codes NET" ;; *SSO*) codes="$codes SSO" ;; *AUTH*) codes="$codes TOKEN_INVALID" ;; esac; fi
  fi
  kv diagnosis "${codes# }"
  [ -z "$codes" ] && echo "all good"
  return 0
}
