# Third-party notices

Muxie is an independent SwiftUI frontend, not an official MKVToolNix product.
Muxie's application source is licensed under GPL-2.0-only; see LICENSE.
The current icon is user-supplied artwork (Support/IconSource.png), converted without redrawing. No third-party authorship or ownership is asserted; the converter script's license does not claim ownership of its input image.

## Sparkle (bundled)

Muxie.app embeds the Sparkle update framework, version 2.9.6.
Website: https://sparkle-project.org/ , source: https://github.com/sparkle-project/Sparkle
License: MIT (with notices for the components Sparkle includes). The complete license text is shipped in the app at Contents/Resources/Licenses/Sparkle-LICENSE.txt.
The framework is embedded from the official release archive, verified against a published checksum before use. Changes: Sparkle's XPC services (unused by a non-sandboxed app) and its non-English localizations are removed, and the helper tools are re-signed.

## MKVToolNix (bundled)

Muxie.app embeds the `mkvmerge` command-line executable and its shared libraries from MKVToolNix, in Contents/Resources/bin. Muxie runs it as a separate process.
Copyright Moritz Bunkus and other contributors. GPL-2.0-only; the license text ships at Contents/Resources/Licenses/GPL-2.0.txt.
Bundled version: 103.0. Website: https://mkvtoolnix.download/ , corresponding source: https://codeberg.org/mbunkus/mkvtoolnix (tag `release-103.0`, matching `mkvmerge --version`). Muxie does not modify it.
Bundled libraries keep their own licenses; their sources are available from their upstream projects.

## HandBrake (bundled)

Muxie.app embeds the `HandBrakeCLI` command-line executable and its shared libraries from HandBrake, in Contents/Resources/bin. Muxie runs it as a separate process for optional H.265/AAC compress export only (no fdk-aac).
Copyright HandBrake Contributors. GPL-2.0; the license text ships at Contents/Resources/Licenses/GPL-2.0.txt.
Bundled version: 1.11.2. Website: https://handbrake.fr/ , source: https://github.com/HandBrake/HandBrake (tag `1.11.2`).
The DMG checksum is verified against https://handbrake.fr/checksums.php before use.

## x265 (inside HandBrake)

The bundled HandBrakeCLI includes the x265 H.265 software encoder, used when "x265" is chosen as the Compress encoder. Website: https://www.x265.org/ , source: https://bitbucket.org/multicoreware/x265_git . License: GPL-2.0.
The hardware encoder option uses Apple's VideoToolbox framework, which is part of macOS and is not redistributed.
