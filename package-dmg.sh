#!/bin/bash
# Usage: package-dmg.sh [path/to/Muxie.app] [output.dmg]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="${1:-$ROOT/dist/Muxie.app}"
[[ -d "$APP/Contents" ]] || { echo "Missing app: $APP" >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
OUT="${2:-$ROOT/dist/Muxie-$VERSION-arm64.dmg}"
[[ ! -e "$OUT" ]] || { echo "Output exists: $OUT" >&2; exit 1; }
codesign --verify --deep --strict "$APP"
T="$(mktemp -d "${TMPDIR:-/tmp}/muxie-dmg.XXXXXX")"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/stage" "$(dirname "$OUT")"
ditto "$APP" "$T/stage/Muxie.app"
ln -s /Applications "$T/stage/Applications"
# A hybrid HFS image can be made entirely in user space; no temporary volume mount is needed.
hdiutil makehybrid -hfs -hfs-volume-name Muxie -o "$T/Muxie-hybrid.dmg" "$T/stage"
hdiutil convert "$T/Muxie-hybrid.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUT"
hdiutil verify "$OUT"
echo "Created $OUT"
