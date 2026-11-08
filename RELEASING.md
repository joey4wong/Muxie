# Releasing an update

Muxie updates itself through Sparkle: **Muxie > Check for Updates…**. Checks are manual only. The feed is
`https://github.com/joey4wong/Muxie/releases/latest/download/appcast.xml`, so every release must contain a file named exactly `appcast.xml`.

## Steps

1. Edit `Support/Info.plist`: raise `CFBundleShortVersionString` (e.g. 1.4.1) and `CFBundleVersion` (a larger integer; Sparkle compares this one).
2. Run `./test.sh`.
3. In **Terminal.app** (not a sandboxed tool), run `./release.sh`. It builds the app, zips it, signs the zip with the EdDSA key from your login Keychain and writes `dist/release/Muxie-<version>.zip` and `dist/release/appcast.xml`.
4. Commit and push, then create a GitHub release tagged `v<version>` and attach **both** files.
5. Verify: `curl -sL https://github.com/joey4wong/Muxie/releases/latest/download/appcast.xml`, then run an older build and choose Check for Updates….

The update archive contains Muxie only. MKVToolNix is not bundled and must be installed separately.

## The signing key

The private EdDSA key lives only in your login Keychain (service `https://sparkle-project.org`, account `ed25519`). The public half is `SUPublicEDKey` in `Info.plist`.

- **Back it up.** Run `./.build/Sparkle-2.9.6/bin/generate_keys -x muxie-update-key` in Terminal, store that file in a password manager, then delete it. Never commit it.
- If the key is lost, installed copies cannot verify new updates and must be reinstalled manually, because key rotation needs Developer ID signing.

## Developer ID and notarization (not yet used)

Builds are ad-hoc signed. With a Developer ID Application certificate in the Keychain, build with `SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" ./release.sh`. That path also enables the hardened runtime, but it has not been exercised, and notarizing (`xcrun notarytool`) and stapling are not scripted yet.

## Updating Sparkle

Change `SPARKLE_VERSION` and `SPARKLE_SHA256` in `build.sh` together, after confirming the checksum from a source other than the download itself.
