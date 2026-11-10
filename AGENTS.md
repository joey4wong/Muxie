# Agent instructions (Muxie)

## Cursor Cloud: ship the full release

When the user asks for a feature fix or approves merging work, treat **ship to users** as one job—not “merge only.” Unless the user says `/no-test` or explicitly skips release:

1. **Branch and PR** — Implement on `cursor/<name>-<suffix>`, open a PR to `main`.
2. **Test** — On Apple Silicon macOS: `./build.sh` then `./test.sh`. Do not merge on red tests.
3. **Merge** — Merge the PR when tests pass (or user asks to merge).
4. **Version bump** — Edit `Support/Info.plist`:
   - Raise `CFBundleShortVersionString` (semver the repo uses, e.g. `1.14.0`).
   - Raise `CFBundleVersion` to a **strictly larger integer** (Sparkle compares this).
   - Commit on `main` with the repo style, e.g. `1.14.0: compress remux, queue persistence, HDR`.
5. **Build release artifacts** — On macOS in **Terminal.app** (not a sandbox without Keychain access), run `./release.sh`. It needs the Sparkle EdDSA private key in the login Keychain. Output: `dist/release/Muxie-<version>.zip` and `dist/release/appcast.xml`.
6. **GitHub Release** — Create release tag `v<version>`, attach **both** the zip and `appcast.xml` (exact filename `appcast.xml` for the Sparkle feed).
7. **Verify** — `curl -sL https://github.com/joey4wong/Muxie/releases/latest/download/appcast.xml` and confirm the enclosure URL and sparkle version.

Document in the PR or agent summary: version, tag, and release URL.

### When the cloud VM is Linux only

The repo agent cannot run `xcrun`, `release.sh`, or Keychain signing on Linux. In that case still complete steps 1–4 and push `main`, then either:

- Run `./test.sh` and `./release.sh` on a **self-hosted macOS** worker or the owner’s Mac, and upload assets to the GitHub release; or
- Stop with a clear checklist listing exactly what the owner must run locally—do **not** claim the release is published without the zip and appcast.

Never merge substantial app changes without a version bump + release plan unless the user explicitly wants “code only, no release.”

See `RELEASING.md` for Sparkle key backup, DMG packaging (`./package-dmg.sh`), and Developer ID notes.
