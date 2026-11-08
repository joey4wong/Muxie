# Third-party notices

Muxie is an independent SwiftUI frontend, not an official MKVToolNix product.
Muxie's application source is licensed under GPL-2.0-only; see LICENSE.
The current icon is user-supplied artwork (Support/IconSource.png), converted without redrawing. No third-party authorship or ownership is asserted; the converter script's license does not claim ownership of its input image.

## Sparkle (bundled)

Muxie.app embeds the Sparkle update framework, version 2.9.6.
Website: https://sparkle-project.org/ , source: https://github.com/sparkle-project/Sparkle
License: MIT (with notices for the components Sparkle includes). The complete license text is shipped in the app at Contents/Resources/Licenses/Sparkle-LICENSE.txt.
The framework is embedded from the official release archive, verified against a published checksum before use. Changes: Sparkle's XPC services (unused by a non-sandboxed app) and its non-English localizations are removed, and the helper tools are re-signed.

## MKVToolNix (not bundled)

Muxie runs the separately installed `mkvmerge` executable. No MKVToolNix code or binary is included in Muxie, its DMG or its update archives.
Copyright Moritz Bunkus and other contributors. GPL-2.0-only.
Website: https://mkvtoolnix.download/ , source: https://codeberg.org/mbunkus/mkvtoolnix

## Distribution boundary

Because Muxie does not redistribute MKVToolNix, the GPL obligations for that program stay with its own distribution. If a future build ever bundles `mkvmerge` or any of its libraries, first provide the complete corresponding source, build and install scripts, license texts and notices for the exact bundled versions. A link to the upstream homepage is not a substitute.
