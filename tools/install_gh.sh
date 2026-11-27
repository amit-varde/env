#!/usr/bin/env bash
# Install GitHub CLI (gh). Safe to re-run. Auth is separate: gh auth login
# macOS: Homebrew. Linux: the official release tarball, unpacked under
# ~/.local/share/gh/<version> and linked from ~/.local/bin/gh. No root needed,
# and it works on distros with no gh package (e.g. RHEL 8).
set -u
. "$(dirname "$0")/lib.sh"
parse_dry "$@"

if command -v gh >/dev/null 2>&1; then
  echo "already installed: gh ($(command -v gh))"
  exit 0
fi

if [ "$OS_NAME" = mac ]; then
  install_formula gh gh
  exit $?
fi

[ "$OS_NAME" = linux ] || { echo "unsupported OS for install_gh: $(uname -s)" >&2; exit 1; }
for t in curl tar; do
  command -v "$t" >/dev/null 2>&1 || { echo "$t is required to install gh" >&2; exit 1; }
done
arch="$(linux_arch)" || { echo "unsupported CPU for the gh tarball: $(uname -m)" >&2; exit 1; }

echo "installing gh from the official release tarball"
if [ "$DRY" -eq 1 ]; then
  echo "[dry-run] look up the latest cli/cli release tag"
  echo "[dry-run] curl -fsSL https://github.com/cli/cli/releases/download/<tag>/gh_<ver>_linux_${arch}.tar.gz | tar -xz -C ~/.local/share/gh/<ver> --strip-components=1"
  echo "[dry-run] ln -sf ~/.local/share/gh/<ver>/bin/gh ~/.local/bin/gh"
  exit 0
fi

tag="$(github_latest_tag cli/cli)"
[ -n "$tag" ] || { echo "Could not find the latest gh release (GitHub API rate limit? set GITHUB_TOKEN)." >&2; exit 1; }
ver="${tag#v}"
dest="$HOME/.local/share/gh/$ver"
mkdir -p "$dest" "$HOME/.local/bin"
curl -fsSL "https://github.com/cli/cli/releases/download/$tag/gh_${ver}_linux_${arch}.tar.gz" \
  | tar -xz -C "$dest" --strip-components=1 || { echo "Download or unpack failed." >&2; rm -rf "$dest"; exit 1; }
ln -sf "$dest/bin/gh" "$HOME/.local/bin/gh"
echo "installed: $("$HOME/.local/bin/gh" --version | head -n 1)"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "NOTE: add \$HOME/.local/bin to PATH (env.sh does this)." ;; esac
echo "Next: gh auth login"
