# Third-party notices

Muxie is an independent SwiftUI frontend, not an official MKVToolNix product.
Muxie's original source and icon assets are licensed under GPL-2.0-only; see LICENSE.
No MKVToolNix source code is copied into the frontend.

## MKVToolNix

Copyright Moritz Bunkus and other contributors. GPL-2.0-only.
Website: https://mkvtoolnix.download/
Source: https://codeberg.org/mbunkus/mkvtoolnix
The personal local build uses mkvmerge 103.0, copied unchanged from the installed official macOS app.
The source archive does NOT contain the mkvmerge binary or third-party libraries.

## Qt Core

The personal bundle also copies libQt6Core.6.dylib 6.11.1 from the installed MKVToolNix app.
Qt is copyright The Qt Company Ltd. and other contributors; available under applicable Qt open-source/commercial terms, including LGPL-3.0. See Support/LGPL-3.0.txt and https://www.qt.io/licensing/open-source-lgpl-obligations .
The application does not link Qt; it launches the independent mkvmerge executable.

## Distribution boundary

The bundled DMG is a personal local build, not a public release or a claim of completed redistribution compliance.
Before publishing any binaries, obtain and provide the complete corresponding source, build/install scripts, modifications and required notices for the exact bundled upstream binaries and all covered components. An upstream homepage link alone is not a substitute.
The upstream README documents additional embedded components and notices: https://codeberg.org/mbunkus/mkvtoolnix/src/tag/release-103.0/README.md . Audit those and the actual build configuration before redistribution.
