#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="${1:-$ROOT/dist/Muxie.app}"
OUT="${2:-$ROOT/dist/Muxie-1.0.0-arm64.dmg}"
[[ -d "$APP/Contents" ]] || { echo "Missing app: $APP" >&2; exit 1; }
[[ ! -e "$OUT" ]] || { echo "Output exists: $OUT" >&2; exit 1; }
codesign --verify --deep --strict "$APP"
T="$(mktemp -d "${TMPDIR:-/tmp}/muxie-dmg.XXXXXX")"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/stage" "$(dirname "$OUT")"
ditto "$APP" "$T/stage/Muxie.app"
ln -s /Applications "$T/stage/Applications"
printf 'Muxie\n将 Muxie 拖入 Applications 即可安装。\nmacOS 26+ / Apple Silicon。\n本地开发构建，无 Developer ID 公证。\n' > "$T/stage/安装说明.txt"
# A hybrid HFS image can be made entirely in user space; no temporary volume mount is needed.
hdiutil makehybrid -hfs -hfs-volume-name Muxie -o "$T/Muxie-hybrid.dmg" "$T/stage"
hdiutil convert "$T/Muxie-hybrid.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUT"
hdiutil verify "$OUT"
echo "Created $OUT"
