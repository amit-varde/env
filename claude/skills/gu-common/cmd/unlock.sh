#: unlock <repo>... [--recursive] - undo `gu lock` exactly (hooksPath, write access, group/other access)
. "$GU_HOME/cmd/lock.sh"
main() { lock_main unlock "$@"; }
