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
