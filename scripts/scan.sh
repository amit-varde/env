#!/usr/bin/env bash
# Scan what git would commit for secrets, absolute home paths and blocklisted
# terms. Exit 1 on any finding. Use before every commit:  ./scripts/scan.sh
#
# This is a shim. The scanner is bin/env-scan, which this repo also installs as
# a pre-commit hook and runs in CI, so there is one engine and one set of
# patterns (lib/scan-patterns.bash) behind every entry point.
#
# Options are passed straight through; see `bin/env-scan --help`:
#   --staged         only what is staged (what the pre-commit hook uses)
#   --skip CATEGORY  / --only CATEGORY   (secret assign abs-path email blocklist)
#   -q, --quiet
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# BU is what bin/ scripts use to locate the repo. Set it explicitly: the user's
# login shell exports a BU that may point at a different checkout.
exec env BU="$ROOT" bash "$ROOT/bin/env-scan" "$@"
