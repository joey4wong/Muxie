# Muxie

Muxie is a native Mac app for selecting and editing media tracks, then exporting an MKV without re-encoding the video or audio. Version 1.2.0 (build 3) has an English-only interface with no sidebar or engine chooser. It targets macOS 26 or later; the personal build is for Apple Silicon (arm64).

Source repository: https://github.com/joey4wong/Muxie

## Use

1. Drag Muxie from the DMG into Applications, then launch it.
2. Open a video, or drop it into the window.
3. Add tracks from an audio file, subtitle file, or another video. Imported tracks start unchecked; no row is automatically focused.
4. Check the tracks to include, then click a row to edit its name, language, default or forced flags.
5. Click **Export**, centered below the track area, to save an MKV to a new filename. The original files are not modified.

Unnamed tracks are labeled Video, Audio or Subtitle. Numbering is per type and appears only when there is more than one track of that type. Existing names are retained; generated labels are not written into track-name metadata.

The empty-window content minimum is 380 × 280 points and the loaded-project content minimum is 520 × 360 points. macOS adds its title/toolbar height. Below 720 points wide, clicking a row opens a compact, scrollable inspector sheet instead of a fixed right-hand column.

External audio remains a separate, selectable track; it is not mixed into the original audio. Subtitles remain selectable soft subtitles, not burned-in text. Burned-in subtitles cannot be removed. A player's own language preferences may override default-track flags.

Muxie does not transcode, mix audio, repair synchronization, or handle DRM. Input compatibility depends on MKVToolNix. Export includes progress reporting, cancellation, partial-output cleanup, track validation, and protection against overwriting input files or existing output files.

Chapters, global tags, and attachments from the primary source are retained. Importing subtitles from an additional source also retains its attachments, such as ASS fonts. Chapters and global tags from additional sources are not merged.

Processing is local, with no account, uploads, or telemetry. Website links open only when clicked.

## Build

Install Xcode with the macOS 26 SDK or later. Open `Package.swift` in Xcode to browse the source. To assemble an installable app and DMG:

```sh
chmod +x build.sh test.sh package-dmg.sh
./build.sh
./package-dmg.sh
```

The default build creates `dist/Muxie.app` without a third-party engine. At runtime, Muxie automatically looks for an installed MKVToolNix app in `/Applications` or the user's Applications folder, or an installation supplied by Homebrew. There is no in-app engine chooser or custom engine-path field. Install MKVToolNix separately when using this source-only build.

Existing output apps and DMGs are not silently removed. Move an old output before rebuilding, or choose another `OUT_DIR` for `build.sh`. The packaging script accepts the app path and output DMG path as its first and second arguments. Its default output is `dist/Muxie-1.2.0-arm64.dmg`.

To copy the engine from an installed official app into a personal local build:

```sh
./build.sh --bundle-installed-engine
./package-dmg.sh
```

The personal bundled-engine build uses MKVToolNix 103.0 with Qt Core 6.11.1. By default, the script copies it from `/Applications/MKVToolNix.app`; `MKVTOOLNIX_APP` can select a different installed app at build time. This is not an in-app path setting. The source package does not contain those binaries.

These are ad-hoc-signed local development builds, without Developer ID notarization or automatic updates. The build script removes inherited quarantine attributes only from the newly assembled development bundle. It does not change system protection settings or the installed MKVToolNix app. Public distribution requires a separate signing, notarization, and license-compliance review.

## Testing

```sh
# ffmpeg is needed only to generate test fixtures, not to run Muxie.
./test.sh
```

### Historical 1.0.0 results

On 2026-11-08, version 1.0.0 completed 14 checks on the development Mac (Apple Silicon, macOS 27.3, SDK 27.2). Those checks covered multiple audio and subtitle tracks, Unicode names, language and default flags, track removal, MP4 remuxing, overwrite protection, cancellation, and progress parsing. An export through the native interface was also verified. Encoded video and audio packet SHA-256 hashes matched between the input and output samples. See `TESTING.md` for the recorded results and scope limits.

### Version 1.1.0 (build 2)

On 2026-11-08, all 16 integration checks passed, including two new checks for English-only application source, removed sidebar/engine chooser, and English track filters. The revised native interface was used to add an external audio track and SRT, edit names and languages, set a default subtitle and export a four-track MKV. The empty window and About sheet were also checked. Bundle signatures and DMG checksums passed verification. See `TESTING.md` for details. This does not include an actual drag-install, an independent macOS 26 device, or Intel hardware.

### Version 1.2.0 (build 3)

On 2026-11-08, all 20 integration checks passed. New checks cover unchecked/unfocused import defaults and per-type labels. Native UI tests verified the supplied icon, smaller windows, compact inspector, manual inclusion and the centered Export action. An export through the compact workflow preserved the encoded video and audio packet hashes. The HFS/UDZO DMG is a personal development package, not a notarized public release. See `TESTING.md`.

## License and third-party software

Muxie's application code is licensed under **GPL-2.0-only**. See `LICENSE`. The current icon uses user-supplied artwork preserved in `Support/IconSource.png`; no third-party authorship or ownership is asserted. `Support/GenerateIcon.swift` reproducibly converts that image into the macOS icon assets without redrawing it.

Muxie is an independent native frontend, not an official MKVToolNix product, and does not copy its GUI code. Media processing is performed by the separate `mkvmerge` process. MKVToolNix is developed by Moritz Bunkus and its contributors.

- Official website: https://mkvtoolnix.download/
- Upstream source: https://codeberg.org/mbunkus/mkvtoolnix
- MKVToolNix license: GPL-2.0-only.
- The source archive contains no mkvmerge or Qt binaries.

Acknowledgment in a README alone is not sufficient to distribute a DMG containing the engine. Before public distribution, prepare the complete corresponding source for the actual bundled versions, modifications and build/install scripts, license texts, and third-party notices. Review every bundled dependency's license. An upstream homepage link is not a substitute for providing corresponding source. See `THIRD-PARTY-NOTICES.md`.

The public repository provides Muxie source only, not the personal DMG containing third-party binaries.
