# shellcheck shell=bash
# =============================================================================
# File:        lib/cursor-shortcut.bash
# =============================================================================
#
# DESCRIPTION:
#   Shared body of bin/create-cursor-ide-shortcut and
#   bin/create-cursor-agent-shortcut. Sourced, not run. The caller sets:
#     CURSOR_SHORTCUT_MODE     ide | agent     (wording, and the app-name suffix)
#     CURSOR_SHORTCUT_SUFFIX   "" or "-agent"  (added to the app name, unless --name)
#     CURSOR_SHORTCUT_ARGS     extra cursor-ide arguments, e.g. --agent
#
# =============================================================================

[ -n "${CURSOR_SHORTCUT_MODE:-}" ] || { err "cursor-shortcut: CURSOR_SHORTCUT_MODE is not set"; exit 1; }
case "$CURSOR_SHORTCUT_MODE" in
    ide)   MODE_WORD="IDE" ;;
    agent) MODE_WORD="Agents" ;;
    *) err "cursor-shortcut: CURSOR_SHORTCUT_MODE must be ide or agent"; exit 1 ;;
esac

[ "$(uname -s)" = Darwin ] || { err "This builds a macOS .app. This machine is $(uname -s)."; exit 1; }

CURSOR_IDE="$BU/bin/cursor-ide"
[ -x "$CURSOR_IDE" ] || { err "Not executable: $CURSOR_IDE"; exit 1; }
CURSOR_IDE="$(cd "$(dirname "$CURSOR_IDE")" && pwd)/$(basename "$CURSOR_IDE")"

DIRS=()
NAME=""
DESK=""
WORK_DIR="${WORK:-}"
YES=0

while [ $# -gt 0 ]; do
    case "$1" in
        --dir)     [ $# -ge 2 ] || { err "--dir needs a path"; exit 2; }; DIRS+=("$2"); shift ;;
        --name)    [ $# -ge 2 ] || { err "--name needs a name"; exit 2; }; NAME="$2"; shift ;;
        --desktop) [ $# -ge 2 ] || { err "--desktop needs a directory"; exit 2; }; DESK="$2"; shift ;;
        --work)    [ $# -ge 2 ] || { err "--work needs a directory"; exit 2; }; WORK_DIR="$2"; shift ;;
        -y|--yes)  YES=1 ;;
        *) err "Unknown option: $1 (try --help)"; exit 2 ;;
    esac
    shift
done

[ -z "$NAME" ] || [ "${#DIRS[@]}" -eq 1 ] || { err "--name applies to a single --dir."; exit 2; }

if [ -z "$DESK" ]; then DESK="$HOME/Desktop"; fi
DESK="${DESK/#\~/$HOME}"
[ -d "$DESK" ] || { err "No Desktop folder at $DESK"; exit 1; }
DESK="$(cd "$DESK" && pwd)"

abs_dir() {
    local p="${1/#\~/$HOME}"
    case "$p" in /*) ;; *) p="$PWD/$p" ;; esac
    [ -d "$p" ] || return 1
    (cd "$p" && pwd)
}

if [ "${#DIRS[@]}" -eq 0 ]; then
    WORK_DIR="${WORK_DIR/#\~/$HOME}"
    [ -n "$WORK_DIR" ] || { err "WORK is not set. Export WORK, pass --work DIR, or pass --dir PATH."; exit 1; }
    [ -d "$WORK_DIR" ] || { err "Work directory not found: $WORK_DIR"; exit 1; }
    WORK_DIR="$(cd "$WORK_DIR" && pwd)"

    projects=()
    for d in "$WORK_DIR"/*/; do
        [ -d "$d" ] || continue
        case "$(basename "$d")" in .*) continue ;; esac
        projects+=("$(cd "$d" && pwd)")
    done
    [ "${#projects[@]}" -gt 0 ] || { info "No project directories under $WORK_DIR"; exit 0; }

    if [ "$YES" -eq 1 ]; then
        DIRS=("${projects[@]}")
    else
        [ -r /dev/tty ] && { : </dev/tty; } 2>/dev/null || { err "No terminal to ask. Pass --dir PATH, or -y for every directory under $WORK_DIR."; exit 2; }
        echo "Desktop apps open a workspace in Cursor's $MODE_WORD mode. An existing app is replaced."
        echo "Workspaces in $WORK_DIR:"
        i=1
        for d in "${projects[@]}"; do
            printf '  %2d  %s\n' "$i" "$(basename "$d")"
            i=$((i + 1))
        done
        read -r -p "Create apps for which? [all] " ans </dev/tty
        ans="${ans:-all}"
        case "$ans" in
            all|ALL|y|Y|yes|YES) DIRS=("${projects[@]}") ;;
            n|N|no|NO|none) info "Cancelled. Nothing was written."; exit 0 ;;
            *)
                oldIFS="$IFS"; IFS=' ,'
                # shellcheck disable=SC2086  # split the answer on spaces and commas
                set -- $ans
                IFS="$oldIFS"
                for tok in "$@"; do
                    [ -n "$tok" ] || continue
                    case "$tok" in
                        ''|*[!0-9]*)
                            hit=""
                            for d in "${projects[@]}"; do
                                [ "$(basename "$d")" = "$tok" ] && hit="$d"
                            done
                            [ -n "$hit" ] || { err "No workspace named '$tok' under $WORK_DIR"; exit 2; }
                            DIRS+=("$hit") ;;
                        *)
                            [ "$tok" -ge 1 ] && [ "$tok" -le "${#projects[@]}" ] || { err "No workspace number $tok (1-${#projects[@]})"; exit 2; }
                            DIRS+=("${projects[$((tok - 1))]}") ;;
                    esac
                done
                [ "${#DIRS[@]}" -gt 0 ] || { err "Nothing selected."; exit 2; }
                ;;
        esac
    fi
fi

xml_escape() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

# jpeg_to_icns SRC DEST: macOS .icns from the repo JPEG (sips + iconutil).
jpeg_to_icns() {
    local src="$1" dest="$2" work png size name px
    command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1 || { err "sips and iconutil are needed to build the app icon."; return 1; }
    work="$(mktemp -d)" || return 1
    png="$work/src.png"
    sips -s format png "$src" --out "$png" >/dev/null || { rm -rf "$work"; return 1; }
    mkdir -p "$work/AppIcon.iconset"
    for size in 16 32 128 256 512; do
        name="icon_${size}x${size}.png"
        sips -z "$size" "$size" "$png" --out "$work/AppIcon.iconset/$name" >/dev/null || { rm -rf "$work"; return 1; }
        px=$((size * 2))
        sips -z "$px" "$px" "$png" --out "$work/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null || { rm -rf "$work"; return 1; }
    done
    mkdir -p "$(dirname "$dest")"
    iconutil -c icns "$work/AppIcon.iconset" -o "$dest" || { rm -rf "$work"; return 1; }
    rm -rf "$work"
}

n=0
for raw in "${DIRS[@]}"; do
    target="$(abs_dir "$raw")" || { err "Not a directory: $raw"; exit 1; }
    app_name="${NAME:-$(basename "$target")${CURSOR_SHORTCUT_SUFFIX:-}}"
    [ -n "$app_name" ] || { err "Cannot name an app for $target"; exit 1; }
    app="$DESK/$app_name.app"
    id="$(printf '%s' "$app_name" | tr -c 'A-Za-z0-9.-' '-')"

    if [ -e "$app" ]; then verb="Replaced"; rm -rf "$app"; else verb="Created"; fi
    mkdir -p "$app/Contents/MacOS" || { err "Could not create $app"; exit 1; }
    {
        echo '#!/bin/bash'
        # shellcheck disable=SC2086  # CURSOR_SHORTCUT_ARGS is a list of flag words
        printf 'exec %q %s--yes %q\n' "$CURSOR_IDE" "${CURSOR_SHORTCUT_ARGS:+$CURSOR_SHORTCUT_ARGS }" "$target"
    } > "$app/Contents/MacOS/launch"
    chmod +x "$app/Contents/MacOS/launch"
    icon="$BU/cursor/icons/$CURSOR_SHORTCUT_MODE.jpg"
    [ -f "$icon" ] || { err "Icon not found: $icon"; exit 1; }
    mkdir -p "$app/Contents/Resources"
    jpeg_to_icns "$icon" "$app/Contents/Resources/AppIcon.icns" || { err "Could not build an icon from $icon"; exit 1; }
    cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>launch</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>local.cursor-$CURSOR_SHORTCUT_MODE.$id</string>
  <key>CFBundleName</key><string>$(xml_escape "$app_name")</string>
  <key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
EOF
    success "$verb $app  ->  $target"
    n=$((n + 1))
done
info "$n app(s) on $DESK. Double-click one to open that workspace in $MODE_WORD mode."
