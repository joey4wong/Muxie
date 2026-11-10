#!/bin/bash
# Builds dist/Muxie.app: Muxie + the Sparkle updater framework. mkvmerge is bundled.
# Env: MKVMERGE_BIN (default: auto-detect installed mkvmerge).
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
MKVMERGE_SRC="${MKVMERGE_BIN:-}"
for c in "$MKVMERGE_SRC" /Applications/MKVToolNix*.app/Contents/MacOS/mkvmerge /opt/homebrew/bin/mkvmerge /usr/local/bin/mkvmerge; do
    if [[ -n "$c" && -x "$c" ]]; then MKVMERGE_SRC="$c"; break; fi
done
if [[ -z "$MKVMERGE_SRC" || ! -x "$MKVMERGE_SRC" ]]; then echo "mkvmerge not found. Install MKVToolNix or set MKVMERGE_BIN." >&2; exit 1; fi
BIN="$APP/Contents/Resources/bin"; LIBS="$APP/Contents/Resources/bin/lib"
mkdir -p "$BIN" "$LIBS"
cp "$MKVMERGE_SRC" "$BIN/mkvmerge"; chmod u+w "$BIN/mkvmerge"
bundle_deps() {
    local target="$1" dep base
    while IFS= read -r dep; do
        case "$dep" in /usr/lib/*|/System/*|"") continue;; esac
        base="$(basename "$dep")"
        if [[ ! -f "$LIBS/$base" ]]; then
            local real="$dep"
            [[ "$dep" == @rpath/* || "$dep" == @loader_path/* || "$dep" == @executable_path/* ]] && real="$(find "$(dirname "$MKVMERGE_SRC")/.." "$(dirname "$MKVMERGE_SRC")" /opt/homebrew/lib /usr/local/lib /opt/homebrew/opt -name "$base" -type f 2>/dev/null | head -1)"
            [[ -f "$real" ]] || { echo "Cannot locate dependency $dep" >&2; exit 1; }
            cp "$real" "$LIBS/$base"; chmod u+w "$LIBS/$base"
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
