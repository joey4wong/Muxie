#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="${OUT_DIR:-$ROOT/dist}"
BUILD="$ROOT/.build/local"
mkdir -p "$OUT" "$BUILD"
APP="$OUT/Muxie.app"
if [[ -e "$APP" ]]; then echo "Output already exists: $APP. Move it first, or choose a new OUT_DIR." >&2; exit 1; fi
ARCH="$(uname -m)"
if [[ "$ARCH" != arm64 ]]; then echo 'This personal build targets Apple Silicon.' >&2; exit 1; fi
xcrun swiftc -disable-sandbox -swift-version 5 -O -target arm64-apple-macosx26.0 -sdk "$(xcrun --sdk macosx --show-sdk-path)" "$ROOT"/Sources/Muxie/*.swift -o "$BUILD/Muxie"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Licenses"
cp "$BUILD/Muxie" "$APP/Contents/MacOS/Muxie"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Support/AppIcon.icns" "$APP/Contents/Resources/"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/Licenses/GPL-2.0.txt"
cp "$ROOT/THIRD-PARTY-NOTICES.md" "$APP/Contents/Resources/Licenses/"
if [[ "${1:-}" == --bundle-installed-engine ]]; then
    ENGINE_APP="${MKVTOOLNIX_APP:-/Applications/MKVToolNix.app}"
    ENGINE="$APP/Contents/Resources/Engine"
    mkdir -p "$ENGINE/libs"
    cp "$ENGINE_APP/Contents/MacOS/mkvmerge" "$ENGINE/mkvmerge"
    cp -L "$ENGINE_APP/Contents/MacOS/libs/libQt6Core.6.dylib" "$ENGINE/libs/"
    cp "$ROOT/Support/LGPL-3.0.txt" "$APP/Contents/Resources/Licenses/"
    codesign --verify --strict "$ENGINE/mkvmerge"
    codesign --verify --strict "$ENGINE/libs/libQt6Core.6.dylib"
    # These unchanged copies come from the already-installed, signed app.
    xattr -d com.apple.quarantine "$ENGINE/mkvmerge" "$ENGINE/libs/libQt6Core.6.dylib" 2>/dev/null || true
    "$ENGINE/mkvmerge" --version > "$APP/Contents/Resources/Engine-Version.txt"
    "$ENGINE/mkvmerge" --ui-language en_US -J /dev/null >/dev/null 2>&1 || [[ $? == 2 ]]
    echo 'Bundled engine: personal local build. Do not publish this DMG before preparing corresponding source and complete dependency notices.'
fi
# The app binary is compiled locally. macOS can inherit the creator app's quarantine.
# Clear the inherited marker only within this newly assembled development bundle.
# Copied engine files were signature-verified above; the installed source app is never modified.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP"
