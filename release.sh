#!/bin/bash
# Builds an update archive and its appcast. RUN THIS IN Terminal.app: sign_update reads the private
# EdDSA key from your login Keychain. Nothing here writes or prints that key.
# Output: dist/release/Muxie-<version>.zip and dist/release/appcast.xml
# Upload both to a GitHub release tagged v<version>. Bump CFBundleShortVersionString and
# CFBundleVersion (a larger integer) in Support/Info.plist first.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO:-joey4wong/Muxie}"
OUT="${OUT_DIR:-$ROOT/dist/release}"
PLIST="$ROOT/Support/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
[[ ! -e "$OUT" ]] || { echo "Release output already exists: $OUT" >&2; exit 1; }
mkdir -p "$OUT"
OUT_DIR="$OUT" "$ROOT/build.sh"
SIGN_UPDATE="$(ls -d "$ROOT"/.build/Sparkle-*/bin/sign_update | tail -1)"
ZIP="$OUT/Muxie-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent "$OUT/Muxie.app" "$ZIP"
# CI passes the private key as a file (SPARKLE_ED_KEY_FILE); locally sign_update reads the login Keychain.
if [[ -n "${SPARKLE_ED_KEY_FILE:-}" ]]; then
  SIGNATURE="$("$SIGN_UPDATE" --ed-key-file "$SPARKLE_ED_KEY_FILE" "$ZIP")"
else
  SIGNATURE="$("$SIGN_UPDATE" "$ZIP")"   # prints: sparkle:edSignature="..." length="..."
fi
URL_BASE="${DOWNLOAD_URL_BASE:-https://github.com/$REPO/releases/download/v$VERSION}"
cat > "$OUT/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Muxie</title>
        <item>
            <title>Version $VERSION</title>
            <sparkle:version>$BUILD_NUMBER</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>26.0.0</sparkle:minimumSystemVersion>
            <pubDate>$(LC_ALL=C date -u +"%a, %d %b %Y %H:%M:%S +0000")</pubDate>
            <enclosure url="$URL_BASE/Muxie-$VERSION.zip" $SIGNATURE type="application/octet-stream"/>
        </item>
    </channel>
</rss>
XML
echo "Update archive: $ZIP"; echo "Appcast:        $OUT/appcast.xml"
