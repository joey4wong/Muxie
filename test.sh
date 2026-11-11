#!/bin/bash
set -euo pipefail
exec 0</dev/null
ROOT="$(cd "$(dirname "$0")" && pwd)"
FFMPEG="${FFMPEG:-$(command -v ffmpeg || true)}"
[[ -n "$FFMPEG" ]] || { echo 'Install ffmpeg to generate test fixtures (not needed by the app).' >&2; exit 1; }
export FFMPEG
# mkvpropedit stamps container-level colour onto the HDR fixture: ffmpeg writes HDR signalling into the
# bitstream but not into MKV Colour elements. PATH first, else the MKVToolNix copy build.sh caches in .build.
MKVPROPEDIT="${MKVPROPEDIT:-$(command -v mkvpropedit || true)}"
if [[ -z "$MKVPROPEDIT" ]]; then
  for CANDIDATE in "$ROOT"/.build/MKVToolNix-*/MKVToolNix.app/Contents/MacOS/mkvpropedit; do
    if [[ -x "$CANDIDATE" ]]; then MKVPROPEDIT="$CANDIDATE"; break; fi
  done
fi
[[ -n "$MKVPROPEDIT" ]] || { echo 'Need mkvpropedit to stamp HDR fixture colour metadata (run ./build.sh once or install mkvtoolnix; the app itself does not need it).' >&2; exit 1; }
T="$(mktemp -d "${TMPDIR:-/tmp}/muxie-tests.XXXXXX")"
"$FFMPEG" -nostdin -hide_banner -loglevel error -f lavfi -i 'testsrc2=size=1280x720:rate=24' -f lavfi -i 'sine=frequency=440:sample_rate=48000' -t 8 -c:v libx264 -pix_fmt yuv420p -c:a aac -metadata:s:a:0 language=eng "$T/测试影片 sample.mp4"
"$FFMPEG" -nostdin -hide_banner -loglevel error -f lavfi -i 'sine=frequency=660:sample_rate=48000' -t 8 -c:a aac "$T/国语音轨.m4a"
printf '1\n00:00:00,500 --> 00:00:03,500\n你好，Muxie。\n' > "$T/简体中文.srt"
printf '1\n00:00:00,500 --> 00:00:03,500\nHello, Muxie.\n' > "$T/English.srt"
# Letterboxed 1080p: an 800-pixel-high picture with black bars (HandBrake would crop to 1920x800 by default).
"$FFMPEG" -nostdin -hide_banner -loglevel error -f lavfi -i 'testsrc2=size=1920x800:rate=24' -f lavfi -i 'sine=frequency=440:sample_rate=48000' -t 3 -vf 'pad=1920:1080:0:140:black' -c:v libx264 -pix_fmt yuv420p -c:a aac "$T/letterbox.mkv"
# 4K HDR10: BT.2020, PQ, mastering display and MaxCLL/MaxFALL.
"$FFMPEG" -nostdin -hide_banner -loglevel error -f lavfi -i 'testsrc2=size=3840x2160:rate=24' -t 1 -pix_fmt yuv420p10le -c:v libx265 -preset ultrafast -x265-params 'colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:master-display=G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1):max-cll=1000,400:repeat-headers=1:hdr10=1:log-level=error' "$T/hdr10-4k.mkv"
# Stamp the same colour onto the MKV container: the HDR badge reads transfer via mkvmerge -J, and HandBrake
# propagates container colour plus in-band SEI (mastering display, MaxCLL) to the compressed output.
"$MKVPROPEDIT" "$T/hdr10-4k.mkv" --edit track:v1 \
  --set colour-transfer-characteristics=16 \
  --set colour-primaries=9 \
  --set colour-matrix-coefficients=9 \
  --set max-content-light=1000 \
  --set max-frame-light=400 >/dev/null
# Two short .m2ts clips (video + AC-3 audio) for the Blu-ray main-title tests; the test writes the playlists itself.
for n in 0 1; do
  "$FFMPEG" -nostdin -hide_banner -loglevel error -f lavfi -i 'testsrc2=size=640x360:rate=24' -f lavfi -i "sine=frequency=$((440 + n * 110)):sample_rate=48000" -t 2 -c:v libx264 -pix_fmt yuv420p -c:a ac3 -f mpegts "$T/clip$n.m2ts"
done
# AC-3 5.1 source: a non-AAC track that Compress must re-encode.
"$FFMPEG" -nostdin -hide_banner -loglevel error -f lavfi -i 'testsrc2=size=640x360:rate=24' -f lavfi -i 'sine=frequency=300:sample_rate=48000' -t 3 \
  -filter_complex '[1:a]aformat=sample_fmts=fltp:channel_layouts=5.1[a]' -map 0:v -map '[a]' -c:v libx264 -pix_fmt yuv420p -c:a ac3 "$T/ac3-51.mkv"
# Stereo + 5.1 audio for compress channel-layout tests.
"$FFMPEG" -nostdin -hide_banner -loglevel error -f lavfi -i 'testsrc2=size=640x360:rate=24' -f lavfi -i 'sine=frequency=440:sample_rate=48000' -f lavfi -i 'sine=frequency=330:sample_rate=48000' -t 4 \
  -filter_complex '[1:a]aformat=sample_fmts=fltp:channel_layouts=stereo[a0];[2:a]aformat=sample_fmts=fltp:channel_layouts=5.1[a1]' \
  -map 0:v -map '[a0]' -map '[a1]' -c:v libx264 -pix_fmt yuv420p -c:a aac -metadata:s:a:0 language=eng -metadata:s:a:1 language=eng "$T/dual-audio.mp4"
xcrun swiftc -disable-sandbox -swift-version 5 -target arm64-apple-macosx26.0 \
  "$ROOT/Sources/Muxie/WorkspaceLayout.swift" "$ROOT/Sources/Muxie/Engine.swift" "$ROOT/Sources/Muxie/Compress.swift" \
  "$ROOT/Sources/Muxie/ExportSpace.swift" "$ROOT/Sources/Muxie/IdleSleepActivity.swift" "$ROOT/Sources/Muxie/TempFileRegistry.swift" \
  "$ROOT/Sources/Muxie/ExportQueue.swift" "$ROOT/Sources/Muxie/JobProgress.swift" "$ROOT/Sources/Muxie/VideoHDR.swift" \
  "$ROOT/Sources/Muxie/QueuePersistence.swift" "$ROOT/Sources/Muxie/ExportNotifications.swift" \
  "$ROOT/Sources/Muxie/AppModel.swift" "$ROOT/Sources/Muxie/BluRayISO.swift" "$ROOT/Tests/Integration.swift" \
  -framework UserNotifications -o "$T/integration"
# The engine under test is the one bundled in the built app (build.sh first), so tests pass without MKVToolNix installed.
BUNDLED_BIN="${MUXIE_APP:-$ROOT/dist/Muxie.app}/Contents/Resources/bin"
[[ -x "$BUNDLED_BIN/mkvmerge" ]] || { echo "Run ./build.sh first: no bundled mkvmerge at $BUNDLED_BIN" >&2; exit 1; }
[[ -x "$BUNDLED_BIN/HandBrakeCLI" ]] || { echo "Run ./build.sh first: no bundled HandBrakeCLI at $BUNDLED_BIN" >&2; exit 1; }
ditto "$BUNDLED_BIN" "$T/bin"
if otool -L "$T/bin/mkvmerge" "$T/bin/HandBrakeCLI" "$T"/bin/lib/*.dylib 2>/dev/null | awk '{print $1}' | grep -E '^(/opt/|/usr/local/|/Users/|/Applications/)' ; then echo 'Bundled tools link to a library outside the app.' >&2; exit 1; fi
codesign --force --sign - --timestamp=none "$T/integration"
xattr -d com.apple.quarantine "$T/integration" 2>/dev/null || true
"$T/integration" "$T"
echo "Test fixtures and outputs: $T"
