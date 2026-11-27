# shellcheck shell=bash  # sourced by bin/gu, so no shebang of its own
#: locks [repo...] - which repos/submodules are locked: repo|state|level|since|reason
main() {
  local r t lv
  repos_from_args "$@"
  echo "repo|state|level|since|reason"
  for r in "${REPOS[@]}"; do
    for t in "$r" $(init_submodules "$r"); do
      lv=$(lock_level "$t")
      if [ -n "$lv" ]; then
        echo "${t#$GU_WORK/}|LOCKED|$lv|$(lock_field "$t" date)|$(lock_field "$t" reason)"
      elif [ "$t" = "$r" ]; then
        echo "${t#$GU_WORK/}|unlocked|-|-|-"
      fi
    done
  done
}
