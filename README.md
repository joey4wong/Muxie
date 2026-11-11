# Muxie

A native Mac app for choosing which video, audio and subtitle tracks go into an MKV, naming them, setting language / default / forced flags, and exporting without re-encoding. SwiftUI with Liquid Glass; macOS 26 or later, Apple Silicon.

Source: https://github.com/joey4wong/Muxie

## Features

- **Track editor for MKV.** Open a video, add audio from another file, add SRT subtitle tracks or tracks from another video, choose which tracks go in, and edit each track's name, language, default flag and forced flag.
- **Mux (lossless).** Copies tracks into a new MKV without re-encoding. Chapters, tags and attachments from the first file are kept, plus subtitle fonts from added files. Subtitles stay soft subtitles.
- **Compress.** Re-encodes video to H.265 10-bit to make large files (for example a 22 to 30 GB Blu-ray) much smaller. Pick the encoder in the **Encoder** menu in the window toolbar (shown when Compress is selected):
  - **Hardware (Apple VideoToolbox):** the default; uses the Mac's media engine.
  - **x265 (software):** slower, usually the smallest files and the best detail and film grain.
  - 1080p sources stay 1080p and 4K stay 4K, constant frame rate, black bars kept, HDR10 preserved. Every checked audio track becomes AAC with the same channel layout (mono 96 kbps, stereo 192 kbps, 3 to 6 channels 384 kbps; 7.1 becomes 5.1). AAC tracks up to 5.1 are copied as they are. Checked subtitles are kept.
  - Compress is hidden when the video is already HEVC 10-bit at 1080p or below.
- **Blu-ray ISO.** Drop a Blu-ray `.iso`; Muxie mounts it and uses the main feature (the largest playlist).
- **Export queue.** Queue several exports and watch their progress at the top of the main window.
- **Safe by design.** Originals are never modified and existing files are never overwritten. Muxie prevents idle system sleep while exporting. No decryption or DRM handling.
- **Updates.** **Muxie > Check for Updates…** (manual only).

## How to use

1. Open a video (**File > Open Video…**, Cmd+O, or drop it into the window). A Blu-ray ISO works too.
2. Add tracks with **Add Tracks** (an audio file, a subtitle file or another video). Imported tracks start unchecked.
3. Check the tracks to include. Click a row to edit its name, language, default and forced flags.
4. Choose **Mux** or **Compress** with the switch above the Export button. For Compress, pick **Hardware** or **x265** in the toolbar **Encoder** menu.
5. Click **Export** (Cmd+E) and choose a new filename. Exports are queued and run one after another; you can keep adding jobs.

Unnamed tracks are labeled Video / Audio / Subtitle (numbered per type when there are several); these labels are not written into the file.

## Requirements

macOS 26 or later, Apple Silicon. Nothing else needs to be installed: Muxie.app contains its own copies of `mkvmerge` and `HandBrakeCLI` in `Contents/Resources/bin`.

## Open-source software Muxie builds on

| Project | Used for | License |
| --- | --- | --- |
| [MKVToolNix](https://mkvtoolnix.download/) (`mkvmerge`) | Reading tracks and writing the MKV in Mux mode | GPL-2.0 |
| [HandBrake](https://handbrake.fr/) (`HandBrakeCLI`) | Compress: video and audio re-encoding | GPL-2.0 |
| [x265](https://www.x265.org/) (inside HandBrake) | Software H.265 encoder | GPL-2.0 |
| Apple VideoToolbox | Hardware H.265 encoder (system framework, reached through HandBrake) | Apple system API |
| [Sparkle](https://sparkle-project.org/) | In-app update checks | MIT |

MKVToolNix and HandBrake run as separate processes. Muxie is independent and is not an official MKVToolNix or HandBrake product. Versions, sources and license texts are in `THIRD-PARTY-NOTICES.md`.

## Help and contact

There is no separate help manual. For questions or problems, use **Help > Contact Developer** in the app (opens this repository), or open an issue on GitHub.

## Updates

**Muxie > Check for Updates…** looks for a newer version on GitHub Releases. Checks are manual only: there are no background checks and no prompts. The item is disabled while an import or export is running. Updates are signed with an EdDSA key and verified before they are unpacked; Muxie then replaces itself and relaunches. Update archives contain the bundled `mkvmerge`. See `RELEASING.md` to publish one.

## Build and test

Xcode with the macOS 26 SDK is required.

```sh
./build.sh          # dist/Muxie.app, with the Sparkle framework embedded
./package-dmg.sh    # dist/Muxie-<version>-arm64.dmg
./test.sh           # integration tests (ffmpeg is needed only to generate fixtures)
```

`build.sh` downloads Sparkle, MKVToolNix and HandBrake CLI at pinned versions and refuses them unless their SHA-256 matches published checksums. Builds are ad-hoc signed unless `SIGN_IDENTITY` is set, and are not notarized. `TESTING.md` records what has been verified and what has not.

## License and third-party software

Muxie's own source is licensed under **GPL-2.0-only** (see `LICENSE`). It embeds Sparkle (MIT) and bundles `mkvmerge` (MKVToolNix) and `HandBrakeCLI` (HandBrake), both GPL-2.0 and run as separate processes; corresponding sources are linked in `THIRD-PARTY-NOTICES.md`. Muxie is not an official MKVToolNix or HandBrake product. Details are in `THIRD-PARTY-NOTICES.md`.
