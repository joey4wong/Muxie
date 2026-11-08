#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="${1:-$ROOT/dist/Muxie.app}"
OUT="${2:-$ROOT/dist/Muxie-1.1.0-arm64.dmg}"
[[ -d "$APP/Contents" ]] || { echo "Missing app: $APP" >&2; exit 1; }
[[ ! -e "$OUT" ]] || { echo "Output exists: $OUT" >&2; exit 1; }
codesign --verify --deep --strict "$APP"
T="$(mktemp -d "${TMPDIR:-/tmp}/muxie-dmg.XXXXXX")"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/stage" "$(dirname "$OUT")"
ditto "$APP" "$T/stage/Muxie.app"
ln -s /Applications "$T/stage/Applications"
printf 'Muxie\nDrag Muxie into Applications to install.\nRequires macOS 26 or later and Apple Silicon.\nLocal development build; not notarized with Developer ID.\n' > "$T/stage/Installation.txt"
# A hybrid HFS image can be made entirely in user space; no temporary volume mount is needed.
hdiutil makehybrid -hfs -hfs-volume-name Muxie -o "$T/Muxie-hybrid.dmg" "$T/stage"
hdiutil convert "$T/Muxie-hybrid.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUT"
hdiutil verify "$OUT"
echo "Created $OUT"
