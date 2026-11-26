# Releasing ShotZ

A release is two downloads and one feed:

- `ShotZ-<version>.zip`: the Sparkle update archive (installed copies update from it).
- `ShotZ-<version>.dmg`: the manual download, with an Applications link.
- `appcast.xml` (repository root, served from `main`): the update feed every installed ShotZ reads.

Both downloads contain the same `ShotZ.app`, signed with your Developer ID Application certificate
and the hardened runtime, notarized and stapled. `scripts/release.sh` builds and checks all of it;
it never pushes, tags, publishes or uploads anything. You do those steps yourself, in the order below.

## One-time setup

### 1. Developer ID Application certificate

Your login keychain needs a valid **Developer ID Application** certificate (not Apple Development).
Check how many you have:

```bash
security find-identity -v -p codesigning | grep -c '"Developer ID Application:'
```

If you have several (for example the old and the renewed G2 certificate, which share a name),
`release.sh` picks the one whose certificate lasts longest, by its SHA-1. To pin one instead, set
`SHOTZ_DEVELOPER_ID` to its SHA-1 (shown by the command above without `| grep -c …`) in your
shell profile. The first signing may show a keychain dialog asking to let `codesign` use the key:
choose **Always Allow**.

### 2. Notarization profile

`release.sh` uses the notarytool keychain profile named by `NOTARY_PROFILE`, default
`notarytool-profile` (the same name your other app uses, so an existing profile works as is).
If you don't have it yet:

```bash
xcrun notarytool store-credentials "notarytool-profile"
```

It asks for your Apple ID, an app-specific password (create one at appleid.apple.com, Sign-In and
Security) and your team ID, checks them with Apple and saves them in the keychain. Verify:

```bash
xcrun notarytool history --keychain-profile "notarytool-profile"
```

It lists your past submissions (or none). An error means the profile is missing or wrong.

### 3. Sparkle EdDSA key

Sparkle signs every update with an EdDSA private key kept in your keychain; installed copies check
it against the public key in ShotZ's `Info.plist` (`SUPublicEDKey`). Keep the private key backed up:
losing it means installed copies can never update again.

ShotZ either reuses the key you already have (Sparkle's default keychain account, used by your
other app) or gets its own account. One variable covers both:

- `SPARKLE_KEY_ACCOUNT` unset or empty: Sparkle's default account (the existing key).
- `SPARKLE_KEY_ACCOUNT=shotz` (or any name): that account. `release.sh` passes it to
  `generate_appcast` as `--account`.

To give ShotZ its own key (Sparkle's tools are in the Sparkle package artefacts after
`swift package resolve`):

```bash
SPARKLE_BIN="$(dirname "$(find .build/artifacts -path '*/bin/generate_keys' | head -1)")"
"$SPARKLE_BIN/generate_keys" --account shotz      # creates the key, prints the public key
"$SPARKLE_BIN/generate_keys" --account shotz -x shotz-sparkle-private.key   # backup; store it safely, never in git
```

With either choice, put the matching public key in `Resources/Info.plist` as `SUPublicEDKey`
(`generate_keys [--account <name>] -p` prints it), and set `SPARKLE_KEY_ACCOUNT` in your shell
profile if you use a named account. On a new Mac, import the backup with
`generate_keys [--account <name>] -f <backup file>`.

### 4. Tools and repository

```bash
brew install create-dmg
```

and the Xcode command line tools (`xcrun notarytool`, `stapler`, `lipo`). Set the GitHub repository
that hosts the downloads, for example in your shell profile:

```bash
export SHOTZ_GITHUB_REPO=owner/name
```

The appcast links point to `https://github.com/$SHOTZ_GITHUB_REPO/releases/download/v<version>/`.
`SUFeedURL` in `Info.plist` must be `https://raw.githubusercontent.com/<owner>/<name>/main/appcast.xml`.

## Making a release

1. **Version.** Set the new version and a higher build number in the single source
   (`scripts/bump-version.sh`, or `CFBundleShortVersionString` / `CFBundleVersion` in
   `Resources/Info.plist`). Sparkle compares the build number: it must always increase.
2. **Notes.** Write `release-notes/<version>.md` (see `release-notes/README.md`).
3. **Check.** `swift build`, `swift test`, and try the release build: `scripts/bundle.sh release`.
4. **Commit** the version and notes on `main`. The tree must be clean.
5. **Build, notarize, package** from the main checkout:

   ```bash
   scripts/release.sh
   ```

   It stops before the long build if anything is missing:
   - the tree isn't clean, you're not on `main`, or the tag already exists
   - the release notes are missing
   - a tool is missing
   - there's no Developer ID identity
   - the notary profile doesn't work
   - Sparkle's tools or EdDSA key are missing (only the key's presence is checked)
   - `SHOTZ_GITHUB_REPO` isn't set
   - the bundle id in the single source (`CFBundleIdentifier` in `Resources/Info.plist`) isn't a
     production id; after the build, the app's own `Info.plist` must carry exactly that id

   Then it:
   1. builds through `scripts/bundle.sh release`, signs inside-out (Sparkle's XPC services,
      Autoupdate and Updater.app, the framework, then the app) with the Developer ID, the hardened
      runtime and a secure timestamp, and verifies the signatures, the entitlements, the bundle
      identity and version, and that every binary is universal;
   2. notarizes the app (`notarytool submit --wait`, a few minutes), staples it and checks Gatekeeper;
   3. makes the Sparkle zip and the DMG (signed), notarizes and staples the DMG, and validates it;
   4. mounts the DMG and verifies the app inside and the Applications link;
   5. regenerates `appcast.xml` from `sparkle-releases/` (making deltas from the previous archives
      kept there), with the release notes embedded;
   6. writes `dist/SHA256SUMS.txt` and prints the go-live steps.

### Rehearsing

```bash
scripts/release.sh --skip-notarize --dry-run-dir /tmp/shotz-rehearsal
```

Everything except notarization and the appcast, with all outputs under the given folder. A
rehearsal never touches the notary profile or the Sparkle key (no check, no submission, no signing).
The git checks only warn, so it runs from a worktree or with uncommitted changes. The summary says
**NOT RELEASABLE** and lists why. `--skip-appcast` also skips the appcast step in a normal run. Never upload a
rehearsal's files: Gatekeeper rejects them on other Macs. Rehearsals skip `create-dmg`'s Finder
window layout (it needs Automation permission); the Applications link is still there.

## Verifying before you publish

`release.sh` has already done these, but they are the checks that matter:

```bash
VERSION=1.2.3
spctl -a -vv dist/ShotZ.app                     # accepted, source=Notarized Developer ID
xcrun stapler validate dist/ShotZ-$VERSION.dmg  # The validate action worked!
codesign --verify --strict --deep dist/ShotZ.app
shasum -a 256 -c dist/SHA256SUMS.txt
```

Open the DMG on another Mac (or a new user account), drag ShotZ to Applications and launch it: no
Gatekeeper warning. To check the update itself, keep the previous version installed and let it
find the new one once the feed is live (step 5 below).

## Going live

In this order, so the feed never points to downloads that aren't public yet:

1. Review `appcast.xml` (new item, version, build, enclosure URL, `sparkle:edSignature`, deltas)
   and commit it with the notes. Never commit the ZIP, DMG or deltas (`dist/` and
   `sparkle-releases/` ignore them).

   ```bash
   git add appcast.xml release-notes/$VERSION.md && git commit -m "Release v$VERSION"
   ```

2. Tag and push the tag only: `git tag v$VERSION && git push origin refs/tags/v$VERSION`
3. Create the GitHub release `v$VERSION` with `release-notes/$VERSION.md` as its description and
   upload `ShotZ-$VERSION.dmg`, `ShotZ-$VERSION.zip` and every `.delta` the new appcast item
   references (listed in the summary). Check each asset is public and matches `SHA256SUMS.txt`.
4. Expose the feed: `git push origin main`.
5. Check the public appcast (`SUFeedURL`) matches your local `appcast.xml`, and that an installed
   older ShotZ offers the update.

Keep the ZIPs in `sparkle-releases/` after releasing: the next release makes its deltas from them.

## Rollback

- **Before step 4** nothing is exposed: delete the GitHub release and the tag
  (`git push origin :refs/tags/v$VERSION`), fix, and release again with a new build number.
- **After step 4** installed copies may already have updated. Sparkle never downgrades, so ship a
  fix as a new version with a higher build number. To stop the update spreading meanwhile, revert
  the appcast commit on `main` and push; copies that haven't updated stop seeing it. Leave the
  GitHub release assets in place while any appcast still points to them.
- Never re-upload different bytes under an existing file name: the EdDSA signature in the appcast
  would no longer match and Sparkle refuses the update.

## Troubleshooting

- **"no Developer ID Application certificate on this Mac"**: install it (Xcode, Settings, Accounts,
  Manage Certificates, or developer.apple.com) into the login keychain.
- **"notary profile 'notarytool-profile' is missing or unusable"**: run the store-credentials
  command above; if it exists, the app-specific password may have been revoked.
- **Notarization "Invalid"**: run `xcrun notarytool log <submission-id> --keychain-profile
  notarytool-profile`. Usual causes: missing hardened runtime or secure timestamp on nested code,
  or an unsigned helper. `release.sh` checks both before submitting.
- **"the app is not universal"**: `bundle.sh release` must build `--arch arm64 --arch x86_64`.
- **"no Sparkle EdDSA key"**: create or import it (one-time setup, step 3); check
  `SPARKLE_KEY_ACCOUNT`.
- **Sparkle refuses the update** ("improperly signed"): `SUPublicEDKey` in the shipped app doesn't
  match the key that signed the appcast, or the asset was changed after the appcast was made.
- **Gatekeeper still warns for the DMG**: `xcrun stapler validate` it; if that fails, don't upload.
- **`create-dmg` hangs or fails**: unmount stray "ShotZ" volumes (`hdiutil info`) and retry.
- **Tag push says "matches more than one"**: push `refs/tags/v<version>` explicitly.

## GitHub Actions

Your other app has a workflow that runs when a `v*` tag is pushed and creates a **draft** GitHub
release with generated notes and install instructions; it builds and uploads nothing. ShotZ doesn't
add it: the release is created by hand in step 3, after the assets are verified. If you want the
draft created automatically, that workflow is safe to copy (it only drafts), but nothing that
publishes or uploads on its own should be added.
