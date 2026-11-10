#!/bin/bash
# Builds dist/Muxie.app: Muxie + the Sparkle updater framework. mkvmerge is bundled.
# mkvmerge comes from the checksum-verified official MKVToolNix release (override with MKVMERGE_BIN).
# Env: OUT_DIR (default ./dist), SIGN_IDENTITY (default "-" = ad-hoc).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="${OUT_DIR:-$ROOT/dist}"
BUILD="$ROOT/.build/local"
APP="$OUT/Muxie.app"
PLIST="$ROOT/Support/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

# Sparkle is pinned and verified against a checksum published independently (Homebrew cask record).
SPARKLE_VERSION=2.9.6
SPARKLE_SHA256=52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192
SPARKLE_DIR="$ROOT/.build/Sparkle-$SPARKLE_VERSION"

if [[ -e "$APP" ]]; then echo "Output already exists: $APP. Move it first, or choose a new OUT_DIR." >&2; exit 1; fi
if [[ "$(uname -m)" != arm64 ]]; then echo 'This build targets Apple Silicon.' >&2; exit 1; fi

if [[ ! -d "$SPARKLE_DIR/Sparkle.framework" ]]; then
    mkdir -p "$SPARKLE_DIR"
    curl -fsSL -o "$SPARKLE_DIR/Sparkle.tar.xz" "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
    ACTUAL="$(shasum -a 256 "$SPARKLE_DIR/Sparkle.tar.xz" | awk '{print $1}')"
    if [[ "$ACTUAL" != "$SPARKLE_SHA256" ]]; then
        echo "Sparkle checksum mismatch (got $ACTUAL). Refusing to use it." >&2
        rm -rf "$SPARKLE_DIR"; exit 1
    fi
    tar -xf "$SPARKLE_DIR/Sparkle.tar.xz" -C "$SPARKLE_DIR"
    # Checksum-verified files only: drop a download quarantine flag that would stop the tools from running.
    xattr -dr com.apple.quarantine "$SPARKLE_DIR" 2>/dev/null || true
fi

mkdir -p "$BUILD" "$APP/Contents/MacOS" "$APP/Contents/Resources/Licenses" "$APP/Contents/Frameworks"
xcrun swiftc -disable-sandbox -swift-version 5 -O -target arm64-apple-macosx26.0 -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -F "$SPARKLE_DIR" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    "$ROOT"/Sources/Muxie/*.swift -o "$BUILD/Muxie"
cp "$BUILD/Muxie" "$APP/Contents/MacOS/Muxie"
cp "$PLIST" "$APP/Contents/Info.plist"
cp "$ROOT/Support/Knot.png" "$APP/Contents/Resources/"
# AppIcon.icon carries the default and dark appearances; actool also writes the AppIcon.icns fallback.
xcrun actool "$ROOT/Support/Assets.xcassets" "$ROOT/Support/AppIcon.icon" --app-icon AppIcon --compile "$APP/Contents/Resources" --platform macosx --minimum-deployment-target 26.0 --accent-color AccentColor --output-format human-readable-text --output-partial-info-plist "$BUILD/AssetInfo.plist" > "$BUILD/assets.log" 2>&1 || { cat "$BUILD/assets.log"; exit 1; }
cp "$ROOT/LICENSE" "$APP/Contents/Resources/Licenses/GPL-2.0.txt"
cp "$ROOT/THIRD-PARTY-NOTICES.md" "$APP/Contents/Resources/Licenses/"
cp "$SPARKLE_DIR/LICENSE" "$APP/Contents/Resources/Licenses/Sparkle-LICENSE.txt"

# Embed Sparkle (symlinks preserved). Muxie is not sandboxed, so the XPC services are not needed.
# Muxie's interface is English-only, so keep only Sparkle's English strings.
FW="$APP/Contents/Frameworks/Sparkle.framework"
ditto "$SPARKLE_DIR/Sparkle.framework" "$FW"
rm -rf "$FW/Versions/B/XPCServices" "$FW/XPCServices"
find "$FW/Versions/B/Resources" -maxdepth 1 -name '*.lproj' ! -name 'en.lproj' ! -name 'Base.lproj' -exec rm -rf {} +

if [[ "$SIGN_IDENTITY" == "-" ]]; then SIGN=(codesign --force --sign - --timestamp=none)
else SIGN=(codesign --force --sign "$SIGN_IDENTITY" --timestamp --options runtime); fi
MKVTOOLNIX_VERSION=103.0
MKVTOOLNIX_SHA256=05670ef070783a4afa23b9a289373472ac168112c83926dae17e29ab32198501
MKVTOOLNIX_DMG="$ROOT/.build/MKVToolNix-$MKVTOOLNIX_VERSION-1-arm64.dmg"
MKVMERGE_SRC="${MKVMERGE_BIN:-}"
if [[ -z "$MKVMERGE_SRC" ]]; then
    if [[ ! -f "$MKVTOOLNIX_DMG" ]]; then
        mkdir -p "$ROOT/.build"
        curl -fsSL -o "$MKVTOOLNIX_DMG" "https://mkvtoolnix.download/macos/releases/$MKVTOOLNIX_VERSION/MKVToolNix-$MKVTOOLNIX_VERSION-1-arm64.dmg"
    fi
    ACTUAL="$(shasum -a 256 "$MKVTOOLNIX_DMG" | awk '{print $1}')"
    if [[ "$ACTUAL" != "$MKVTOOLNIX_SHA256" ]]; then echo "MKVToolNix checksum mismatch (got $ACTUAL)." >&2; rm -f "$MKVTOOLNIX_DMG"; exit 1; fi
    MNT="$(mktemp -d)"; MKV_COPY="$ROOT/.build/MKVToolNix-$MKVTOOLNIX_VERSION"
    rm -rf "$MKV_COPY"; mkdir -p "$MKV_COPY"
    hdiutil attach -nobrowse -readonly -mountpoint "$MNT" "$MKVTOOLNIX_DMG" >/dev/null
    ditto "$MNT"/MKVToolNix*.app "$MKV_COPY/MKVToolNix.app"
    hdiutil detach "$MNT" >/dev/null
    xattr -dr com.apple.quarantine "$MKV_COPY" 2>/dev/null || true
    MKVMERGE_SRC="$MKV_COPY/MKVToolNix.app/Contents/MacOS/mkvmerge"
fi
[[ -x "$MKVMERGE_SRC" ]] || { echo "mkvmerge not found: $MKVMERGE_SRC" >&2; exit 1; }
BIN="$APP/Contents/Resources/bin"; LIBS="$APP/Contents/Resources/bin/lib"
mkdir -p "$BIN" "$LIBS"
cp "$MKVMERGE_SRC" "$BIN/mkvmerge"; chmod u+w "$BIN/mkvmerge"
# MKVToolNix DMG SHA-256 from https://mkvtoolnix.download/macos/releases/103.0/MKVToolNix-103.0-1-arm64.dmg.sha256
bundle_deps() {
    local target="$1" dep base real mkv_libs
    mkv_libs="$(dirname "$MKVMERGE_SRC")/libs"
    while IFS= read -r dep; do
        case "$dep" in /usr/lib/*|/System/*|"") continue;; esac
        base="$(basename "$dep")"
        if [[ ! -f "$LIBS/$base" ]]; then
            if [[ -f "$dep" ]]; then real="$dep"
            else
                real="$(find "$mkv_libs" "$(dirname "$MKVMERGE_SRC")" "$(dirname "$MKVMERGE_SRC")/.." /opt/homebrew/lib /usr/local/lib -name "$base" \( -type f -o -type l \) 2>/dev/null | head -1 || true)"
            fi
            [[ -n "$real" && -e "$real" ]] || { echo "Bundling failed: non-system dependency $dep (from $target) is not in the app or MKVToolNix bundle." >&2; exit 1; }
            cp -L "$real" "$LIBS/$base"; chmod u+w "$LIBS/$base"
            install_name_tool -id "@loader_path/lib/$base" "$LIBS/$base" 2>/dev/null || true
            bundle_deps "$LIBS/$base"
        fi
        if [[ "$target" == "$BIN/mkvmerge" ]]; then install_name_tool -change "$dep" "@executable_path/lib/$base" "$target"
        else install_name_tool -change "$dep" "@loader_path/$base" "$target"; fi
    done < <(otool -L "$target" | tail -n +2 | awk '{print $1}')
}
bundle_deps "$BIN/mkvmerge"
for f in "$LIBS"/*.dylib; do [[ -e "$f" ]] && "${SIGN[@]}" "$f"; done
"${SIGN[@]}" "$BIN/mkvmerge"
"$BIN/mkvmerge" --version

# Sign inside-out. Developer ID builds also get the hardened runtime and a secure timestamp.
"${SIGN[@]}" "$FW/Versions/B/Autoupdate"
"${SIGN[@]}" "$FW/Versions/B/Updater.app"
"${SIGN[@]}" "$FW"
"${SIGN[@]}" "$APP"
# Clear inherited extended attributes, including those on the framework's symlinks (xattr -r skips links).
xattr -cr "$APP" 2>/dev/null || true
find "$APP" -type l -exec xattr -s -c {} \; 2>/dev/null || true
codesign --verify --deep --strict "$APP"
echo "Built $APP (version $VERSION, build $BUILD_NUMBER, signed: $SIGN_IDENTITY)"
