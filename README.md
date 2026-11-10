# Muxie

A native Mac app for choosing which video, audio and subtitle tracks go into an MKV, naming them, setting language / default / forced flags, and exporting without re-encoding. SwiftUI with Liquid Glass; macOS 26 or later, Apple Silicon.

Source: https://github.com/joey4wong/Muxie

## Requirements

Nothing else needs to be installed: Muxie.app contains its own copy of `mkvmerge` from [MKVToolNix](https://mkvtoolnix.download/) in `Contents/Resources/bin`. If that copy is missing, Muxie falls back to an installed MKVToolNix in `/Applications`, `~/Applications` or Homebrew.

## Use

1. Open a video, or drop it into the window.
2. Add tracks from an audio file, a subtitle file or another video. Imported tracks start unchecked, and no row is focused.
3. Check the tracks to include. Click a row to edit its name, language, default and forced flags.
4. Click **Export** and save to a new filename. Originals are never modified, and existing files are never overwritten.

Export remuxes only: no transcoding, mixing or DRM handling. External audio becomes a separate selectable track. Subtitles stay soft subtitles. Chapters, tags and attachments from the first file are kept; subtitle fonts from added files are kept too.

Unnamed tracks are labeled Video / Audio / Subtitle (numbered per type when there are several); these labels are not written into the file. The window's minimum height grows with the track count, so every row stays visible without a scroller. Only if the rows cannot fit on the display are they paginated.

## Updates

**Muxie > Check for Updates…** looks for a newer version on GitHub Releases. Checks are manual only: there are no background checks and no prompts. The item is disabled while an import or export is running. Updates are signed with an EdDSA key and verified before they are unpacked; Muxie then replaces itself and relaunches. Update archives contain the bundled `mkvmerge`. See `RELEASING.md` to publish one.

## Build and test

Xcode with the macOS 26 SDK is required.

```sh
./build.sh          # dist/Muxie.app, with the Sparkle framework embedded
./package-dmg.sh    # dist/Muxie-<version>-arm64.dmg
./test.sh           # integration tests (ffmpeg is needed only to generate fixtures)
```

`build.sh` downloads Sparkle and MKVToolNix at pinned versions and refuses them unless their SHA-256 matches. Builds are ad-hoc signed unless `SIGN_IDENTITY` is set, and are not notarized. `TESTING.md` records what has been verified and what has not.

## License and third-party software

Muxie's own source is licensed under **GPL-2.0-only** (see `LICENSE`). It embeds Sparkle (MIT) and bundles the `mkvmerge` executable from MKVToolNix, which is GPL-2.0-only and run as a separate process; its corresponding source is linked in `THIRD-PARTY-NOTICES.md`. Muxie is not an official MKVToolNix product; MKVToolNix is by Moritz Bunkus and contributors. Details are in `THIRD-PARTY-NOTICES.md`.
