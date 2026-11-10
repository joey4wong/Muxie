#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
FFMPEG="${FFMPEG:-$(command -v ffmpeg || true)}"
[[ -n "$FFMPEG" ]] || { echo 'Install ffmpeg to generate test fixtures (not needed by the app).' >&2; exit 1; }
T="$(mktemp -d "${TMPDIR:-/tmp}/muxie-tests.XXXXXX")"
"$FFMPEG" -hide_banner -loglevel error -f lavfi -i 'testsrc2=size=1280x720:rate=24' -f lavfi -i 'sine=frequency=440:sample_rate=48000' -t 8 -c:v libx264 -pix_fmt yuv420p -c:a aac -metadata:s:a:0 language=eng "$T/测试影片 sample.mp4"
"$FFMPEG" -hide_banner -loglevel error -f lavfi -i 'sine=frequency=660:sample_rate=48000' -t 8 -c:a aac "$T/国语音轨.m4a"
printf '1\n00:00:00,500 --> 00:00:03,500\n你好，Muxie。\n' > "$T/简体中文.srt"
printf '1\n00:00:00,500 --> 00:00:03,500\nHello, Muxie.\n' > "$T/English.srt"
xcrun swiftc -disable-sandbox -swift-version 5 -target arm64-apple-macosx26.0 "$ROOT/Sources/Muxie/WorkspaceLayout.swift" "$ROOT/Sources/Muxie/Engine.swift" "$ROOT/Sources/Muxie/AppModel.swift" "$ROOT/Tests/Integration.swift" -o "$T/integration"
# The engine under test is the one bundled in the built app (build.sh first), so tests pass without MKVToolNix installed.
BUNDLED_BIN="${MUXIE_APP:-$ROOT/dist/Muxie.app}/Contents/Resources/bin"
[[ -x "$BUNDLED_BIN/mkvmerge" ]] || { echo "Run ./build.sh first: no bundled mkvmerge at $BUNDLED_BIN" >&2; exit 1; }
ditto "$BUNDLED_BIN" "$T/bin"
if otool -L "$T/bin/mkvmerge" "$T"/bin/lib/*.dylib | awk '{print $1}' | grep -E '^(/opt/|/usr/local/|/Users/|/Applications/)' ; then echo 'Bundled mkvmerge links to a library outside the app.' >&2; exit 1; fi
codesign --force --sign - --timestamp=none "$T/integration"
xattr -d com.apple.quarantine "$T/integration" 2>/dev/null || true
"$T/integration" "$T"
echo "Test fixtures and outputs: $T"
