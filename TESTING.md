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

## Version 1.4.0 (build 5): in-app updates

Verified on 2026-11-08 in the environment above (Apple Silicon, macOS 27.3).

Automated: 26 integration checks pass. New: the Info.plist update settings (HTTPS feed, 44-character EdDSA public key, integer build number, manual checks only, verify-before-extraction) and the absence of any bundled-engine lookup.

End-to-end update, run for real against Sparkle 2.9.6:

- Two test builds of the same source: 1.4.0 (build 5) and 1.4.1 (build 6). They used a separate bundle ID, so the user's installed Muxie was untouched, and a feed on 127.0.0.1 that served an appcast plus a zip signed with the real EdDSA key.
- In 1.4.0, Muxie > Check for Updates… opened Sparkle's dialog: "A new version of Muxie is available! Muxie 1.4.1 is now available—you have 1.4.0." Text was English; buttons were Skip This Version and Install Update.
- Install Update downloaded and verified the archive and reached "Ready to Install". Install and Relaunch then replaced the app: Info.plist on disk went from 1.4.0/5 to 1.4.1/6, the code signature verified, and About showed 1.4.1.
- The feed server log shows the requests in order: appcast, zip, then an appcast request again for a second check after the update.

Release build: `release.sh` ran in Terminal.app and produced Muxie-1.4.0.zip with an appcast. The appcast's declared length equals the zip size. The zip holds no MKVToolNix files and no quarantine attributes. Without the engine, the app is 4.7 MB, down from about 15 MB. Sparkle's XPC services and non-English localizations are removed; the English dialog above confirms the framework still works that way.

Issues found and fixed during testing:

- Sparkle's `generate_keys` failed from a sandboxed shell (Keychain error 100001) and succeeded from Terminal.app. The signing step is therefore documented as a Terminal step.
- `xattr -cr` skips symlinks. Sparkle.framework's symlinks kept an inherited quarantine attribute and ended up inside the first test archive. `build.sh` now also clears symlink attributes, and the final archive was checked by reading its raw contents.
- Sparkle 2.10.1 was the newest release, but its archive checksum could not be confirmed from an independent source, so 2.9.6 is pinned. Its checksum matches the Homebrew cask record.

Not verified:

- The result shown when already up to date: the second check reached the feed, but the dialog was not observed.
- Updating a copy installed in /Applications, or by a non-admin user.
- Whether Sparkle itself relaunched the app, or my test harness reopened it.
- Gatekeeper behavior for a first install on a machine that never ran this build. Builds are ad-hoc signed and not notarized; Developer ID signing and notarization are untested.
- Skipping a version, interrupted downloads and a tampered archive were not exercised.

### After publishing the v1.4.0 release

- The feed fetched through GitHub's `releases/latest/download/appcast.xml` redirect is byte-identical to the appcast that was signed, and the download URL inside it returns a zip byte-identical to the signed archive. Tag `v1.4.0` points at commit `05dcd1a`.
- Real-feed update: the shipped 1.4.0 app was relabelled 1.3.9 (build 4), re-signed ad-hoc and kept the real feed URL and bundle ID. Check for Updates offered "Muxie 1.4.0 is now available—you have 1.3.9", downloaded the archive from GitHub, verified it and installed it. Afterwards the app on disk was 1.4.0 (build 5), its signature verified, it carried no quarantine attributes, and its executable and Info.plist were byte-identical to the GitHub release.
- Checking again from 1.4.0 opened a small untitled alert window, which is consistent with Sparkle's "up to date" message. The window could not be read by the automation, so its text is not confirmed.
- The test run wrote two Sparkle keys into the app's preferences domain; they were deleted afterwards.


## Version 1.15.0 (build 44): 2026-11-11

Environment: Apple M4 (MacBook Air), macOS 27.3, HandBrakeCLI 1.11.2 and mkvmerge 103.0 as bundled.

`test.sh`: 85 checks, including new ones for the queued encoder, Dolby Vision parsing from Matroska and MP4 records, Profile 7-only warning, a +1000 ms delay on a re-encoded audio track, and hardware decoding only on the Fast encoder.

End to end through Muxie's own Compress code (10 s 1080p clips made with libx265, `hdr10plus_tool` 1.7.2 and `dovi_tool` 2.3.4):
- HDR10+: all 259 frames of dynamic metadata survive with x265 and with VideoToolbox.
- Dolby Vision 8.1: detected at import (badge DV, profile 8); all 259 RPUs and the `dvvC` record survive with x265 and with VideoToolbox; no warning.
- Dolby Vision 8.1 without mastering metadata: HandBrake drops DV and Muxie reports "Dolby Vision (Profile 8) was not kept".
- MPEG-2 source with the Fast encoder (hardware decoding requested) encodes normally.
- Not verified on real files: Profile 5 and Profile 7 (tools cannot generate them); behaviour taken from HandBrake 1.11.2 `libhb/work.c`.

Speed and quality, 60 s of a 1080p H.264 film (grainy 1968 source), MacBook Air M4:
| Setting | Time | Size | VMAF |
| --- | --- | --- | --- |
| x265 medium RF 21 (Best) | 54 to 69 s | 24.6 MB | 74.6 |
| x265 fast RF 21 | 60 to 67 s | 21.8 MB | 74.4 |
| VideoToolbox quality 65 (Fast) | 9.1 s | 32.7 MB | 76.1 |
| VideoToolbox + hardware decoding | 7.9 s, CPU 31.9 s -> 3.1 s | 32.0 MB | 76.1 |
x265 timings vary with heat on the fanless Air. Hardware decoding gives x265 bit-identical output and no gain, so it is used for Fast only. Remux into the HandBrake input runs at about 240 MB/s on an external SSD (about 95 s for 22.7 GB), so staging on the internal disk or skipping the remux was not worth the risk.

## Version 1.15.1 (build 45): 2026-11-11

Environment: Apple M4 (MacBook Air), macOS 27.3, HandBrakeCLI 1.11.2 and mkvmerge 103.0 as bundled.

`test.sh`: 91 checks; the new ones cover the HandBrake progress scanner (partial lines, `\r` endings, newest line per chunk, unfinished last line) and the log tail buffer (size cap, a character split across chunks).

What this release changes is Muxie's own CPU use during Compress (HandBrake itself is unchanged). A `sample` of 1.15.0 during an x265 encode showed Muxie at 9 to 16% of one core.
- HandBrake output is read as bytes. The old code recounted and rebuilt a 64 KB String for every chunk. Same simulated stream (23 000 chunks): 9.65 s of CPU before, 0.87 s after, with identical parsed progress and log tail. End to end (60 s clip, Chinese file name, whole Compress run, Muxie's own CPU): 1.34 s before, 1.14 s after, about 0.5% of one core either way. So this is a cleanup that mattered much less than the sample suggested.
- Charging bar in the queue: redraws 24 times per second instead of 60 (counted: 60.0 to 24.0 body evaluations per second) and not at all while every Muxie window is hidden or covered. Measured in a test window with only the bar: 3.9% to 3.2% of one core (static bar: 0.0%). Removing the glow shadow or switching the schedule to a fixed timer made no further difference; CPU time per frame rises as the frame rate drops, so the saving is smaller than the frame count suggests.
- Not measured: the whole app window during an encode, and the hidden-window case.
