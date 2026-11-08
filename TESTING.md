# Verification: 2026-11-08

Environment: Apple Silicon, macOS 27.3, Swift 6.4.2 / SDK 27.2, deployment target macOS 26.0.
Engine: MKVToolNix 103.0, Qt Core 6.11.1 from the installed official app.

## Version 1.0.0 (historical)

14 integration checks passed:
1. MP4 import and video/audio identification.
2. MP4 → MKV export with track validation.
3. Import external audio and SRT subtitles.
4. Output two selectable audio tracks and two subtitle tracks.
5. Persist Unicode names, zh-Hans language and default flag.
6. Exclude selected audio and subtitle tracks.
7. Reject overwriting an existing output, preserving its bytes.
8. Reject using an input path as output, preserving source bytes.
9. Pre-cancelled job leaves no output or partial file.
10. Remove all audio/subtitles from an existing MKV.
11. Reject subtitle-only input as the primary movie.
12. Parse GUI percentage progress and cancel an active job, leaving no finished output.
13. Disable export when all video tracks are excluded.
14. Verify input bytes remain unchanged after the suite.

Native UI verification:
- Launch assembled app and verify empty workspace and Liquid Glass rendering.
- Open MP4 through Finder/document-opening entry point.
- Edit audio display name in the inspector; track row updates.
- Use actual save panel and export; UI reports completion.
- Probe saved MKV and confirm edited track name.
- Verify bundled mkvmerge launches with only the included Qt Core dependency.

Encoded packet data hashes (ffmpeg stream copy → SHA-256):
- Video input = output: cff1970d02f8802593e5f2b59f5f5809f91356a55da14a9044506e3944962d5b
- Audio input = output: 0cb3c98ab21f94a6a82a22120922c319a1a89310ae32151f05b279e4d1169359

Scope limits: short generated H.264/AAC/SRT fixtures, not a full codec matrix. No physical macOS 26-only or Intel test, no public distribution/notarization review, no multi-hour/large-library soak test. Dark appearance follows system settings but was not separately visually checked.

Packaging:
- Personal app bundle: `codesign --verify --deep --strict` passed.
- HFS/UDZO DMG generated without a temporary volume mount.
- `hdiutil verify` validated all image checksums.
- Actual drag-install from a mounted DMG was not performed in this session.

## Version 1.1.0 (build 2)

Verified on 2026-11-08 in the environment above:

- All 14 existing integration checks passed again.
- New check: no CJK literals in application runtime source, no sidebar and no custom engine chooser/path override.
- New check: English Audio and Subtitles filters return the expected tracks.
- Total: **16 checks passed**. Unicode media filenames and track names remain supported as user data.
- A separate development bundle was used for UI testing; the user's running 1.0.0 application was not closed or modified.
- Native UI: open MP4, import Commentary.m4a and English.srt using the actual file picker, edit names and language, select the default subtitle, then export through the actual save panel.
- Output inspection confirmed one video, two audio tracks and one subtitle, with names/language/default metadata.
- Encoded video packet SHA-256 matched before and after the native export: cff1970d02f8802593e5f2b59f5f5809f91356a55da14a9044506e3944962d5b.
- Empty window contains only the app title, icon and Open Video action. No source sidebar or idle status footer.
- Editing window contains tracks and track properties, without explanatory cards, slogans or engine status.
- Language menu and file dialogs are English. About contains only name, version, copyright and licensing attribution; no engine path or chooser.
- Assembled app metadata is version 1.1.0, build 2, English development region/localizations.
- Bundle signature verification passed. Bundled MKVToolNix 103.0 launches successfully; integration tests also use automatically discovered installed MKVToolNix.
- Muxie-1.1.0-arm64.dmg uses an English Installation.txt; hdiutil verified all image checksums.

Scope limits remain: short generated fixtures, no full codec matrix, no independent macOS 26-only or Intel test, no dark-mode visual pass, and no actual drag-install from a mounted image. The personal DMG is not a notarized public release.

## Version 1.2.0 (build 3)

Verified on 2026-11-08 in the environment above:

- All 20 integration checks passed. Newly covered: imported tracks unchecked with no focused row; generated Video/Audio labels do not modify metadata; additional tracks remain unchecked; numbering is per track type. All existing mux, Unicode, metadata, overwrite, cancellation and filtering tests still pass after explicitly selecting tracks.
- Source image is copied unchanged to Support/IconSource.png. New 1024 PNG and all ten ICNS representations decode; generation is reproducible.
- New icon was visually confirmed in the empty window.
- Empty window resized to an observed outer frame of 380 × 312 points; project window to 520 × 412 points. The macOS title/toolbar accounts for the difference from the content minimums.
- Actual file-picker import showed unchecked Video and Audio, no highlighted row, no inspector, and a disabled centered Export button. The toolbar contains only New Project and Add Tracks.
- Manually checking Video and Audio enabled Export without focusing a row.
- At compact width, clicking Audio opened a scrollable inspector sheet. A custom name was entered, then Export opened the native save panel and produced a valid MKV.
- Output retained two tracks; the untouched video track name stayed empty and the edited audio name was Original Audio. Encoded packet hashes matched both input streams:
  - Video: cff1970d02f8802593e5f2b59f5f5809f91356a55da14a9044506e3944962d5b
  - Audio: 0cb3c98ab21f94a6a82a22120922c319a1a89310ae32151f05b279e4d1169359
- Widening the window restored the inline inspector; Export remained centered on the entire window, not the track column.
- Version metadata is 1.2.0, build 3, English-only localization. Bundle signature verification passed.

Packaging: Muxie-1.2.0-arm64.dmg was created as HFS/UDZO and hdiutil verified all image checksums. Shell syntax, plist lint and git diff whitespace checks passed. No actual drag-install from a mounted image was performed. Previous hardware/codec/notarization scope limits still apply.

## Version 1.3.0 (build 4)

Verified on 2026-11-08 in the environment above:

- All 24 integration checks passed on the final source. New checks cover the absence of scroll/fractional-height clipping, exact per-row minimum-height growth, stable status-space reservation, and screen-bound complete-row pagination with no lost/duplicated tracks.
- Supplied teal knot artwork copied unchanged to IconSource.png and aspect-fit without stretching. PNG and all 10 ICNS representations decode. The app's empty window visually showed the new teal icon.
- Graphite neutral interface, native muted gray-green AccentColor asset, and neutral Liquid Glass action buttons visually checked. Asset compilation passed; no purple or bright blue app fills remain. System window-sharing indicators are not app palette elements.
- Actual files with 2, 3, 4, 5 and 6 tracks were opened in the native app. At width 520 points, observed outer minimum heights were 424, 492, 560, 628 and 696 points respectively. Every track was fully present, with no track scroll area or scroll bar.
- The native window refused an attempt to shrink the six-track window to the two-track height: it stayed at 520 × 696 rather than the requested 520 × 424.
- Both the two-track and six-track workflows exported through the actual save panel. All rows remained visible after progress/results appeared; footer space had been reserved in advance.
- Final six-track output contains 1 video, 1 audio and 4 subtitle tracks. Encoded audio/video packet hashes match the input:
  - Video: cff1970d02f8802593e5f2b59f5f5809f91356a55da14a9044506e3944962d5b
  - Audio: 0cb3c98ab21f94a6a82a22120922c319a1a89310ae32151f05b279e4d1169359
- Checkbox inclusion is still manual and initial row focus is still empty. Default flags and existing track names are preserved as metadata.
- Source-only integration used automatically found MKVToolNix; the personal app used its bundled 103.0 engine.
- The screen-overflow pagination logic was integration-tested with 24 synthetic track records, not visually exercised with an actual 24-track media file.
- Bundle signature and version 1.3.0 / build 4 metadata verified. Dark-mode colors are supplied in the accent asset but were not separately visually checked.

Packaging: Muxie-1.3.0-arm64.dmg was created as HFS/UDZO and all hdiutil image checksums verified. Bundle signatures, shell syntax, Info.plist and accent-resource JSON validation passed. Actual drag-install from a mounted image was not performed. Prior hardware/codec/notarization limits still apply.
