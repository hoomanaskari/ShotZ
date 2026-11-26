# Releasing ShotZ

A release is two downloads and one feed:

- `ShotZ-<version>.zip`: the Sparkle update archive (installed copies update from it).
- `ShotZ-<version>.dmg`: the manual download, with an Applications link.
- `appcast.xml` (repository root, served from `main`): the update feed every installed ShotZ reads.

Both downloads contain the same universal `ShotZ.app` (Apple silicon and Intel, about 2.4 MB more
than Apple silicon alone), with Sparkle embedded, signed with your Developer ID Application
certificate, the hardened runtime and a secure timestamp, notarized and stapled. `scripts/release.sh` builds and checks all of it;
it never pushes, tags, publishes or uploads anything. You do those steps yourself, in the order below.

## One-time setup

### 1. Developer ID Application certificate

Your login keychain needs a valid **Developer ID Application** certificate (not Apple Development).
Check how many you have:

```bash
security find-identity -v -p codesigning | grep -c '"Developer ID Application:'
```

Only certificates of the team committed in `Resources/DeveloperTeamID.txt` (Pixel Forty,
`2SQ9JNU8XE`) can sign a release. If that team has several (for example the old and the renewed G2
certificate, which share a name), `release.sh` picks the one whose certificate lasts longest, by its
SHA-1. After signing it checks the `TeamIdentifier` of the app, of `Sparkle.framework` and of the DMG. To pin one instead, set
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

Sparkle signs every update with an EdDSA private key; installed copies check it against the public
key built into the app (`SUPublicEDKey`). ShotZ has its own key:

- **Keychain account:** `shotz`, committed in `Resources/SparkleKeyAccount.txt`. `release.sh` reads
  it from there (no shell profile needed) and passes it to `generate_appcast --account`.
  `SPARKLE_KEY_ACCOUNT` overrides it for one run.
- **Public key:** committed in `Resources/SparklePublicKey.txt`. `bundle.sh` writes it into the app's
  `SUPublicEDKey`, and `release.sh` checks the built app carries exactly that key.
- **Private key:** only in your login keychain, never in the repository or anywhere else on disk.
  Keep your own backup of it; without it, installed copies can never update again.

The first time `generate_appcast` uses the key, macOS may ask whether it may access the keychain
item. Allow it (Always Allow avoids the question next time). If the dialog is dismissed or the run
times out, `release.sh` stops without retrying; run it again when you're at the Mac.

### 4. Tools and repository

```bash
brew install create-dmg
```

and the Xcode command line tools (`xcrun notarytool`, `stapler`, `lipo`). The update feed is
`SUFeedURL` in `Resources/Info.plist` (`https://raw.githubusercontent.com/<owner>/<name>/main/appcast.xml`;
the repository's default branch must be `main`, since installed copies read the appcast from there);
`release.sh` takes the download repository from it, so the appcast links point to
`https://github.com/<owner>/<name>/releases/download/v<version>/`. (`SHOTZ_GITHUB_REPO=owner/name`
overrides it only if it matches.)

## Making a release

1. **Version.** Set the new version; the build number goes up by one (or give it explicitly):

   ```bash
   scripts/bump-version.sh 1.2.0        # or: scripts/bump-version.sh 1.2.0 42
   scripts/bump-version.sh --print      # shows "1.2.0 42"
   ```

   It edits `Resources/Info.plist`, the single source. Sparkle compares build numbers, so a build
   number must never repeat or go down.
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
   - `SUFeedURL` isn't the raw `appcast.xml` on `main` of a GitHub repository
   - `Resources/SparklePublicKey.txt` is empty
   - the bundle id in the single source (`CFBundleIdentifier` in `Resources/Info.plist`) isn't a
     production id; after the build, the app's own `Info.plist` must carry exactly that id

   Then it:
   1. builds through `scripts/bundle.sh release` (universal, Sparkle embedded and signed inside-out
      with the Developer ID, the hardened runtime and a secure timestamp), re-signs the same way as a
      safety net, and verifies the signatures (including Sparkle's XPC services, Autoupdate and
      Updater.app), the entitlements, the bundle id, version and build, `SUFeedURL`,
      `SUPublicEDKey` against `Resources/SparklePublicKey.txt`, and that every binary is universal;
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
rehearsal never touches the notary profile, and doesn't use the Sparkle key unless you ask:

```bash
scripts/release.sh --skip-notarize --dry-run-dir /tmp/shotz-rehearsal --rehearse-appcast
```

also signs an appcast with the Sparkle key, entirely inside the given folder (its own
`sparkle-releases/` and `appcast.xml`; the repository's are never touched), and verifies it: the new
item's version and build, the enclosure URL (the GitHub release asset), its length, and its EdDSA
signature against the committed public key (a deliberately changed copy of the archive must fail).
Its summary then lists only "notarization skipped".
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
   and commit exactly these files:

   | File | Why |
   |---|---|
   | `appcast.xml` | the feed, exposed when `main` is pushed (step 4) |
   | `release-notes/<version>.md` | the notes (the GitHub release description and the update window) |
   | `sparkle-releases/.gitignore` | keeps the folder's build products out of git (unchanged after the first release) |

   Everything else the run produced is a build product and stays uncommitted: all of `dist/` (it
   ignores itself) and, in `sparkle-releases/`, the ZIPs, deltas and the notes copies
   (`ShotZ-<version>.md`, made from `release-notes/` for `generate_appcast`).

   ```bash
   git add appcast.xml release-notes/$VERSION.md sparkle-releases/.gitignore && git commit -m "Release v$VERSION"
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
- **Notarization "Invalid"**: `release.sh` prints each submission id and saves Apple's log as
  `dist/notary-log-<file>-<id>.json` (it lists the problems and contains no credentials). To fetch it
  again: `xcrun notarytool log <submission-id> --keychain-profile notarytool-profile`. Usual causes: missing hardened runtime or secure timestamp on nested code,
  or an unsigned helper. `release.sh` checks both before submitting.
- **"the app is not universal"**: `bundle.sh release` builds universal by default; check nothing
  forced a host-only build.
- **"Resources/SparklePublicKey.txt is empty"**: choose the Sparkle key and add its public key
  (one-time setup, step 3).
- **"no Sparkle EdDSA key"**: the key for the account in `Resources/SparkleKeyAccount.txt` (`shotz`)
  isn't in this Mac's login keychain; restore it from your backup.
- **"generate_appcast did not finish within 180 s"**: a keychain access dialog was probably waiting.
  Run again at the Mac and allow access.
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
