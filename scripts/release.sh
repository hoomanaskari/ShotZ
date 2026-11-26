#!/usr/bin/env bash
# Builds a releasable ShotZ: signed with the Developer ID and the hardened runtime, notarized and
# stapled, as a Sparkle update archive and a DMG, plus the regenerated appcast. See docs/RELEASE.md.
#
#   scripts/release.sh                               the real release (clean main, new version, untagged)
#   scripts/release.sh --skip-notarize               everything except the two notarization
#                                                    submissions and stapling: NOT RELEASABLE
#   scripts/release.sh --skip-appcast                no appcast (no Sparkle signing): NOT RELEASABLE
#   scripts/release.sh --dry-run-dir <dir> [...]     a rehearsal: outputs go to <dir> (dist, sparkle
#                                                    releases, appcast); git checks only warn; allowed
#                                                    from a worktree
# Rehearsals (--skip-notarize or --dry-run-dir) never touch the notary profile or the Sparkle
# key: they skip the notarization and appcast steps and say NOT RELEASABLE.
#
# Outputs (in dist/, or <dir>/dist for a rehearsal):
#   ShotZ.app                 the signed (and, when notarized, stapled) app
#   ShotZ-<version>.zip       the Sparkle update archive
#   ShotZ-<version>.dmg       the manual download, with an Applications link
#   SHA256SUMS.txt            checksums of the zip and the DMG
# and the appcast (appcast.xml, or <dir>/appcast.xml) from sparkle-releases/ (archives, deltas).
#
# This script never pushes, tags, publishes or uploads anything: it prints the go-live steps.
# It never prints secrets and never runs with `set -x`.
#
# Environment (all optional):
#   SHOTZ_DEVELOPER_ID   Developer ID Application identity (SHA-1 or exact name); default: the one
#                        on this Mac whose certificate lasts longest (several can share a name)
#   NOTARY_PROFILE       notarytool keychain profile (default: notarytool-profile)
#   SHOTZ_GITHUB_REPO    owner/name of the GitHub repository the downloads come from (default:
#                        the repository in SUFeedURL; must match it when both are set)
#   SPARKLE_BIN          folder with Sparkle's generate_appcast (default: found in .build/artifacts)
#   SPARKLE_KEY_ACCOUNT  keychain account of the Sparkle EdDSA key; empty = Sparkle's default account
#                        (passed to generate_appcast as --account only when set)
set -euo pipefail
set +x

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SKIP_NOTARIZE=0
SKIP_APPCAST=0
DRY_RUN_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-notarize) SKIP_NOTARIZE=1; shift ;;
    --skip-appcast) SKIP_APPCAST=1; shift ;;
    --dry-run-dir)
      [[ $# -ge 2 && -n "$2" ]] || { echo "release.sh: --dry-run-dir needs a directory" >&2; exit 64; }
      DRY_RUN_DIR="$2"; shift 2 ;;
    -h|--help) sed -n '2,33p' "$0"; exit 0 ;;
    *) echo "release.sh: unknown option $1 (see --help)" >&2; exit 64 ;;
  esac
done

APP_NAME="ShotZ"
NOTARY_PROFILE="${NOTARY_PROFILE:-notarytool-profile}"
SPARKLE_KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-}"
PLIST="$ROOT/Resources/Info.plist"
NOTES_DIR="$ROOT/release-notes"
BUILT_APP="$ROOT/build/$APP_NAME.app"

if [[ -n "$DRY_RUN_DIR" ]]; then
  mkdir -p "$DRY_RUN_DIR"
  OUT_ROOT="$(cd "$DRY_RUN_DIR" && pwd)"
  DIST="$OUT_ROOT/dist"
  RELEASES_DIR="$OUT_ROOT/sparkle-releases"
  APPCAST="$OUT_ROOT/appcast.xml"
else
  DIST="$ROOT/dist"
  RELEASES_DIR="$ROOT/sparkle-releases"
  APPCAST="$ROOT/appcast.xml"
fi

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/shotz-release.XXXXXX")"
MOUNT_POINT=""
cleanup() {
  if [[ -n "$MOUNT_POINT" ]]; then hdiutil detach "$MOUNT_POINT" -quiet -force >/dev/null 2>&1 || true; fi
  rm -rf "$STAGE"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

WARNINGS=()
NOT_RELEASABLE=()
DELTAS=()
step() { printf '\n==> %s\n' "$1"; }
ok() { printf '    ok: %s\n' "$1"; }
warn() { printf '    warning: %s\n' "$1"; WARNINGS+=("$1"); }
blocker() { NOT_RELEASABLE+=("$1"); printf '    NOT RELEASABLE: %s\n' "$1"; }
stop() { printf '\nStopped: %s\n' "$1" >&2; exit 1; }

# In production every check is fatal; in a rehearsal git/tag checks only warn.
check() { # check <description> <fatal-in-dry-run: 0|1> <command...>
  local what="$1" fatal_dry="$2"; shift 2
  if "$@"; then ok "$what"; return 0; fi
  if [[ -n "$DRY_RUN_DIR" && "$fatal_dry" == 0 ]]; then warn "not met: $what (rehearsal: continuing)"; return 0; fi
  stop "not met: $what"
}

# ---------------------------------------------------------------------------------------------
step "Preflight"

[[ "$(uname)" == Darwin ]] || stop "ShotZ releases are made on a Mac."
in_worktree() { [[ "$(git rev-parse --git-dir)" != "$(git rev-parse --git-common-dir)" ]]; }
if in_worktree && [[ -z "$DRY_RUN_DIR" ]]; then
  stop "this checkout is a git worktree. Release from the main checkout, or rehearse with --dry-run-dir <dir>."
fi

for cmd in git swift codesign spctl hdiutil ditto shasum plutil openssl create-dmg security; do
  command -v "$cmd" >/dev/null 2>&1 || stop "missing command: $cmd$([[ $cmd == create-dmg ]] && echo ' (install: brew install create-dmg)')"
done
for tool in notarytool stapler lipo; do
  xcrun --find "$tool" >/dev/null 2>&1 || stop "missing Xcode tool: $tool (install the Xcode command line tools)"
done
ok "required commands present"

plist_value() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null || true; }
VERSION="$(plist_value CFBundleShortVersionString)"
BUILD="$(plist_value CFBundleVersion)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || stop "Resources/Info.plist: CFBundleShortVersionString '$VERSION' is not a release version (x.y or x.y.z)."
[[ "$BUILD" =~ ^[0-9]+$ ]] || stop "Resources/Info.plist: CFBundleVersion '$BUILD' must be a whole number (Sparkle compares it)."
# The production bundle id comes from the single source, never from this script. The built app is
# checked against it after the build (signing identifier, notarization and appcast follow from it).
expected_bundle_id() { plist_value CFBundleIdentifier; }
BUNDLE_ID="$(expected_bundle_id)"
[[ "$BUNDLE_ID" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] || stop "Resources/Info.plist: CFBundleIdentifier '$BUNDLE_ID' is not a reverse-DNS id."
[[ "$BUNDLE_ID" != *.dev ]] || stop "Resources/Info.plist: '$BUNDLE_ID' is the development id, not the production one."
TAG="v$VERSION"
ZIP="$DIST/$APP_NAME-$VERSION.zip"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
ok "version $VERSION (build $BUILD), bundle id $BUNDLE_ID, from Resources/Info.plist"

check "working tree is clean" 0 test -z "$(git status --porcelain)"
check "on branch main" 0 test "$(git branch --show-current)" = main
check "tag $TAG does not exist yet" 0 test -z "$(git tag --list "$TAG")"
NOTES="$NOTES_DIR/$VERSION.md"
check "release notes at release-notes/$VERSION.md" 0 test -s "$NOTES"
# The GitHub repository that hosts the downloads is the one whose main branch serves the feed
# (SUFeedURL = https://raw.githubusercontent.com/<owner>/<name>/main/appcast.xml).
FEED_URL="$(plist_value SUFeedURL)"
FEED_REPO=""
if [[ "$FEED_URL" =~ ^https://raw\.githubusercontent\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/main/appcast\.xml$ ]]; then
  FEED_REPO="${BASH_REMATCH[1]}"
fi
if [[ -z "${SHOTZ_GITHUB_REPO:-}" ]]; then
  [[ -n "$FEED_REPO" ]] || stop "Resources/Info.plist: SUFeedURL must be https://raw.githubusercontent.com/<owner>/<name>/main/appcast.xml (or set SHOTZ_GITHUB_REPO)."
  SHOTZ_GITHUB_REPO="$FEED_REPO"
elif [[ -n "$FEED_REPO" && "$SHOTZ_GITHUB_REPO" != "$FEED_REPO" ]]; then
  stop "SHOTZ_GITHUB_REPO ($SHOTZ_GITHUB_REPO) differs from the repository in SUFeedURL ($FEED_REPO)."
fi
ok "downloads and feed from github.com/$SHOTZ_GITHUB_REPO"
[[ "$SHOTZ_GITHUB_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || stop "SHOTZ_GITHUB_REPO must look like owner/name."

# Developer ID Application identity: explicit, or the longest-lasting one (by SHA-1, since a
# renewed certificate keeps the old name). Only the expiry date is ever printed.
cert_end_epoch() { # SHA-1 → expiry as epoch seconds
  local pem end
  pem="$(security find-certificate -a -Z -p 2>/dev/null | awk -v h="$1" '/^SHA-1 hash:/ { keep = ($3 == h) } keep')"
  [[ -n "$pem" ]] || { echo 0; return; }
  end="$(printf '%s\n' "$pem" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)"
  date -j -f "%b %e %T %Y %Z" "$end" +%s 2>/dev/null || echo 0
}
IDENTITY="${SHOTZ_DEVELOPER_ID:-}"
if [[ -z "$IDENTITY" ]]; then
  newest=0
  for hash in $(security find-identity -v -p codesigning 2>/dev/null | awk '/"Developer ID Application:/ { print $2 }'); do
    ends="$(cert_end_epoch "$hash")"
    if [[ "$ends" -gt "$newest" ]]; then newest="$ends"; IDENTITY="$hash"; fi
  done
  [[ -n "$IDENTITY" ]] || stop "no Developer ID Application certificate on this Mac (see docs/RELEASE.md, one-time setup)."
  ok "Developer ID Application identity selected (longest-lasting; expires $(date -j -f %s "$newest" +%Y-%m-%d))"
else
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  grep -F -- "$IDENTITY" <<<"$identities" | grep '"Developer ID Application:' >/dev/null \
    || stop "SHOTZ_DEVELOPER_ID does not name a valid Developer ID Application identity on this Mac."
  ok "Developer ID Application identity from SHOTZ_DEVELOPER_ID"
fi

REHEARSAL=0
[[ "$SKIP_NOTARIZE" == 1 || -n "$DRY_RUN_DIR" ]] && REHEARSAL=1
[[ "$REHEARSAL" == 1 ]] && SKIP_APPCAST=1
if [[ "$SKIP_NOTARIZE" == 1 || -n "$DRY_RUN_DIR" ]]; then
  SKIP_NOTARIZE=1
  warn "rehearsal: notary profile not checked, nothing is submitted or stapled"
  warn "without notarization Gatekeeper rejects this app and DMG on other Macs"
  blocker "notarization skipped"
else
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || stop "notary profile '$NOTARY_PROFILE' is missing or unusable. Run: xcrun notarytool store-credentials \"$NOTARY_PROFILE\" (docs/RELEASE.md)."
  ok "notary profile '$NOTARY_PROFILE' usable"
fi

SPARKLE_BIN="${SPARKLE_BIN:-}"
if [[ -z "$SPARKLE_BIN" ]]; then
  found="$(find "$ROOT/.build/artifacts" -path '*/bin/generate_appcast' -type f 2>/dev/null | head -n 1 || true)"
  [[ -n "$found" ]] && SPARKLE_BIN="$(dirname "$found")"
fi
HAVE_SPARKLE=0
if [[ -n "$SPARKLE_BIN" && -x "$SPARKLE_BIN/generate_appcast" ]]; then
  ok "Sparkle tools found (generate_appcast)"
  HAVE_SPARKLE=1
elif [[ "$SKIP_APPCAST" == 0 ]]; then
  stop "Sparkle's generate_appcast not found in .build/artifacts. Run 'swift package resolve' (Sparkle must be a dependency) or set SPARKLE_BIN."
else
  warn "Sparkle's generate_appcast not found (resolve the Sparkle package first)"
fi
# The public key installed copies verify updates with (bundle.sh writes it into SUPublicEDKey).
PUBLIC_KEY="$(tr -d '[:space:]' < "$ROOT/Resources/SparklePublicKey.txt" 2>/dev/null || true)"
if [[ -n "$PUBLIC_KEY" ]]; then
  ok "Sparkle public key set (Resources/SparklePublicKey.txt)"
elif [[ "$REHEARSAL" == 1 || "$SKIP_APPCAST" == 1 ]]; then
  warn "Resources/SparklePublicKey.txt is empty (the Sparkle key isn't chosen yet): this build reports updates as unavailable"
else
  stop "Resources/SparklePublicKey.txt is empty. Choose the Sparkle key and put its public key there (docs/RELEASE.md, one-time setup)."
fi
KEY_ACCOUNT_LABEL="${SPARKLE_KEY_ACCOUNT:-Sparkle default}"
if [[ "$SKIP_APPCAST" == 1 ]]; then
  # Rehearsals and --skip-appcast never touch the Sparkle key (no presence check, no signing).
  warn "appcast skipped$([[ "$REHEARSAL" == 1 ]] && echo ' (rehearsal)'): the Sparkle key is not used"
  blocker "appcast not generated or signed"
  HAVE_SPARKLE=0
elif security find-generic-password -s "https://sparkle-project.org" -a "${SPARKLE_KEY_ACCOUNT:-ed25519}" >/dev/null 2>&1; then
  # Only the item's presence is checked (exit status); the key itself is never read.
  ok "Sparkle EdDSA signing key present in the keychain (account: $KEY_ACCOUNT_LABEL)"
else
  stop "no Sparkle EdDSA key in the keychain (account: $KEY_ACCOUNT_LABEL). See docs/RELEASE.md (one-time setup, Sparkle key)."
fi

# ---------------------------------------------------------------------------------------------
step "Building ShotZ $VERSION ($BUILD), release configuration"
SHOTZ_SIGN_IDENTITY="$IDENTITY" "$ROOT/scripts/bundle.sh" release
[[ -d "$BUILT_APP" ]] || stop "bundle.sh did not produce build/$APP_NAME.app."
mkdir -p "$DIST"
# Keep dist/ out of git without touching the repository's .gitignore.
[[ -f "$DIST/.gitignore" ]] || printf '*\n' > "$DIST/.gitignore"
APP="$DIST/$APP_NAME.app"
rm -rf "$APP" "$ZIP" "$DMG"
ditto "$BUILT_APP" "$APP"

# ---------------------------------------------------------------------------------------------
step "Signing inside-out with the Developer ID (hardened runtime, secure timestamp)"
sign() { # sign <path> [extra codesign args]
  local path="$1"; shift
  codesign --force --sign "$IDENTITY" --timestamp --options runtime \
    --preserve-metadata=identifier,entitlements,requirements,flags "$@" "$path" >/dev/null
}
SPARKLE_FW="$APP/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE_FW" ]]; then
  SPARKLE_V="$SPARKLE_FW/Versions/B"
  for nested in "$SPARKLE_V/XPCServices/Downloader.xpc" "$SPARKLE_V/XPCServices/Installer.xpc" "$SPARKLE_V/Autoupdate" "$SPARKLE_V/Updater.app"; do
    [[ -e "$nested" ]] && sign "$nested"
  done
  sign "$SPARKLE_FW"
  ok "Sparkle.framework and its helpers signed"
else
  warn "no Sparkle.framework in the app (Sparkle not embedded yet): in-app updates won't work"
  blocker "Sparkle.framework is not embedded"
fi
sign "$APP"
ok "app signed"

# ---------------------------------------------------------------------------------------------
step "Verifying the signed app"
codesign --verify --strict --deep --verbose=2 "$APP" 2>&1 | sed 's/^/    /'
SIGNATURE="$(codesign -dvv "$APP" 2>&1)"
grep -q '^Authority=Developer ID Application:' <<<"$SIGNATURE" || stop "the app is not signed with a Developer ID Application certificate."
grep -q 'flags=.*(runtime)' <<<"$SIGNATURE" || stop "the app is not signed with the hardened runtime."
grep -q '^Timestamp=' <<<"$SIGNATURE" || stop "the app's signature has no secure timestamp (notarization requires one)."
ok "Developer ID authority, hardened runtime and secure timestamp"
if [[ -d "$SPARKLE_FW" ]]; then
  while IFS= read -r nested; do
    codesign --verify --strict "$nested" >/dev/null 2>&1 || stop "nested code is not validly signed: ${nested#$APP/}"
    nested_sig="$(codesign -dvv "$nested" 2>&1 || true)"
    grep -q 'flags=.*(runtime)' <<<"$nested_sig" || stop "nested code lacks the hardened runtime: ${nested#$APP/}"
  done < <(find "$SPARKLE_FW" \( -name '*.xpc' -o -name '*.app' -o -name Autoupdate \) -prune -print)
  ok "nested Sparkle helpers and XPC services signed with the hardened runtime"
fi
info="$APP/Contents/Info.plist"
[[ "$(plutil -extract CFBundleIdentifier raw -o - "$info")" == "$BUNDLE_ID" ]] || stop "the app's bundle id is not $BUNDLE_ID."
[[ "$(plutil -extract CFBundleShortVersionString raw -o - "$info")" == "$VERSION" ]] || stop "the app is not version $VERSION."
[[ "$(plutil -extract CFBundleVersion raw -o - "$info")" == "$BUILD" ]] || stop "the app is not build $BUILD."
[[ "$(plutil -extract LSUIElement raw -o - "$info" 2>/dev/null)" == true ]] || stop "the app is not an agent app (LSUIElement)."
ok "bundle id, version, build and LSUIElement"
feed="$(plutil -extract SUFeedURL raw -o - "$info" 2>/dev/null || true)"
[[ "$feed" == https://* ]] || stop "the app has no https SUFeedURL."
shipped_key="$(plutil -extract SUPublicEDKey raw -o - "$info" 2>/dev/null || true)"
[[ "$shipped_key" == "$PUBLIC_KEY" ]] || stop "the app's SUPublicEDKey doesn't match Resources/SparklePublicKey.txt."
ok "SUFeedURL ($feed) and SUPublicEDKey$([[ -z "$PUBLIC_KEY" ]] && echo ' (empty, as in the source)' || echo ' (matches the source)')"
printf '    entitlements:\n'
ents="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -p - 2>/dev/null || true)"
if [[ -z "$ents" || "$ents" == "{}" ]]; then printf '      (none)\n'; else printf '%s\n' "$ents" | sed 's/^/      /'; fi
# Architectures: the owner's convention is a universal app (arm64 + x86_64).
single_arch=()
while IFS= read -r macho; do
  archs="$(xcrun lipo -archs "$macho" 2>/dev/null || true)"
  [[ -z "$archs" ]] && continue
  [[ "$archs" == *arm64* && "$archs" == *x86_64* ]] || single_arch+=("${macho#$APP/} ($archs)")
done < <(find "$APP" -type f -perm -u+x)
if [[ ${#single_arch[@]} -eq 0 ]]; then
  ok "every executable is universal (arm64 + x86_64)"
else
  for s in "${single_arch[@]}"; do printf '    not universal: %s\n' "$s"; done
  if [[ -n "$DRY_RUN_DIR" || "$SKIP_NOTARIZE" == 1 ]]; then
    blocker "the app is not universal (Intel Macs can't run it)"
  else
    stop "the app is not universal. Build arm64 + x86_64 (see docs/RELEASE.md)."
  fi
fi

# ---------------------------------------------------------------------------------------------
notarize() { # notarize <file>
  printf '    submitting %s (Apple usually takes a few minutes)\n' "$(basename "$1")"
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
}
if [[ "$SKIP_NOTARIZE" == 0 ]]; then
  step "Notarizing the app"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$STAGE/$APP_NAME-notary.zip"
  notarize "$STAGE/$APP_NAME-notary.zip"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
fi
step "Gatekeeper assessment of the app"
if spctl -a -vv --type execute "$APP" 2>"$STAGE/spctl.txt"; then
  sed 's/^/    /' "$STAGE/spctl.txt"; ok "accepted"
else
  sed 's/^/    /' "$STAGE/spctl.txt"
  if [[ "$SKIP_NOTARIZE" == 1 ]]; then warn "spctl rejects the app (expected without notarization)"; else stop "Gatekeeper rejects the notarized app."; fi
fi

# ---------------------------------------------------------------------------------------------
step "Sparkle update archive"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
ok "$(basename "$ZIP")"

step "DMG"
mkdir "$STAGE/dmg"
ditto "$APP" "$STAGE/dmg/$APP_NAME.app"
dmg_args=(--volname "$APP_NAME $VERSION" --window-pos 200 120 --window-size 540 360 --icon-size 96
  --icon "$APP_NAME.app" 140 170 --hide-extension "$APP_NAME.app" --app-drop-link 400 170
  --codesign "$IDENTITY" --no-internet-enable)
# A rehearsal skips create-dmg's Finder AppleScript (window layout), which would ask for
# Automation permission; the Applications link is still added.
[[ -n "$DRY_RUN_DIR" ]] && dmg_args+=(--skip-jenkins)
create-dmg "${dmg_args[@]}" "$DMG" "$STAGE/dmg" >"$STAGE/create-dmg.log" 2>&1 \
  || { tail -n 20 "$STAGE/create-dmg.log" | sed 's/^/    /'; stop "create-dmg failed."; }
codesign --verify --strict "$DMG" >/dev/null 2>&1 || stop "the DMG is not validly signed."
# Capture before grepping: with pipefail, `grep -q` exiting early would fail the pipe.
dmg_sig="$(codesign -dvv "$DMG" 2>&1 || true)"
grep -q '^Authority=Developer ID Application:' <<<"$dmg_sig" || stop "the DMG is not signed with the Developer ID."
hdiutil verify -quiet "$DMG" || stop "hdiutil verify fails for the DMG."
ok "$(basename "$DMG") (Developer ID signature, image checksum)"
if [[ "$SKIP_NOTARIZE" == 0 ]]; then
  step "Notarizing the DMG"
  notarize "$DMG"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl -a -vv --type open --context context:primary-signature "$DMG" 2>&1 | sed 's/^/    /'
fi

step "Mounting the DMG and verifying its contents"
MOUNT_POINT="$STAGE/mount"
mkdir -p "$MOUNT_POINT"
hdiutil attach "$DMG" -mountpoint "$MOUNT_POINT" -nobrowse -readonly -quiet
[[ -d "$MOUNT_POINT/$APP_NAME.app" ]] || stop "the DMG has no $APP_NAME.app."
[[ -L "$MOUNT_POINT/Applications" && "$(readlink "$MOUNT_POINT/Applications")" == /Applications ]] || stop "the DMG has no Applications link."
codesign --verify --strict --deep "$MOUNT_POINT/$APP_NAME.app" || stop "the app inside the DMG fails signature verification."
[[ "$(plutil -extract CFBundleVersion raw -o - "$MOUNT_POINT/$APP_NAME.app/Contents/Info.plist")" == "$BUILD" ]] || stop "the app inside the DMG is not build $BUILD."
if [[ "$SKIP_NOTARIZE" == 0 ]]; then
  spctl -a -vv --type execute "$MOUNT_POINT/$APP_NAME.app" 2>&1 | sed 's/^/    /'
fi
hdiutil detach "$MOUNT_POINT" -quiet
MOUNT_POINT=""
ok "ShotZ.app (signature, build) and the Applications link"

# ---------------------------------------------------------------------------------------------
if [[ "$HAVE_SPARKLE" == 1 ]]; then
  step "Appcast"
  mkdir -p "$RELEASES_DIR"
  [[ -f "$RELEASES_DIR/.gitignore" ]] || printf '*.zip\n*.delta\n*.dmg\n' > "$RELEASES_DIR/.gitignore"
  if [[ -n "$DRY_RUN_DIR" && -d "$ROOT/sparkle-releases" ]]; then
    # Rehearse deltas against the real previous archives without changing them.
    find "$ROOT/sparkle-releases" -maxdepth 1 \( -name '*.zip' -o -name '*.md' \) -exec cp -n {} "$RELEASES_DIR/" \;
  fi
  cp "$ZIP" "$RELEASES_DIR/"
  # Sparkle pairs release notes with the archive of the same name.
  [[ -s "$NOTES" ]] && cp "$NOTES" "$RELEASES_DIR/$APP_NAME-$VERSION.md"
  [[ -f "$APPCAST" ]] || cp "$ROOT/appcast.xml" "$APPCAST" 2>/dev/null || true
  # (Only reached in a production run: rehearsals skip the appcast and never use the key.)
  account_args=()
  [[ -n "$SPARKLE_KEY_ACCOUNT" ]] && account_args=(--account "$SPARKLE_KEY_ACCOUNT")
  "$SPARKLE_BIN/generate_appcast" \
    ${account_args[@]+"${account_args[@]}"} \
    --download-url-prefix "https://github.com/$SHOTZ_GITHUB_REPO/releases/download/$TAG/" \
    --embed-release-notes \
    --link "https://github.com/$SHOTZ_GITHUB_REPO" \
    -o "$APPCAST" \
    "$RELEASES_DIR" 2>&1 | sed 's/^/    /'
  grep -q "sparkle:version=\"$BUILD\"\|<sparkle:version>$BUILD</sparkle:version>" "$APPCAST" || stop "the appcast has no item for build $BUILD."
  grep -q 'sparkle:edSignature=' "$APPCAST" || stop "the appcast's enclosures are not EdDSA-signed."
  ok "appcast item for $VERSION ($BUILD), EdDSA-signed"
  while IFS= read -r d; do DELTAS+=("$d"); done < <(find "$RELEASES_DIR" -maxdepth 1 -name "${APP_NAME}${BUILD}-*.delta" | sort)
fi

# ---------------------------------------------------------------------------------------------
step "Checksums"
(cd "$DIST" && shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")" > SHA256SUMS.txt && sed 's/^/    /' SHA256SUMS.txt)

printf '\n==================================================================\n'
if [[ ${#NOT_RELEASABLE[@]} -gt 0 ]]; then
  printf ' ShotZ %s (%s): NOT RELEASABLE\n' "$VERSION" "$BUILD"
  for b in "${NOT_RELEASABLE[@]}"; do printf '   - %s\n' "$b"; done
else
  printf ' ShotZ %s (%s): ready to publish\n' "$VERSION" "$BUILD"
fi
printf '==================================================================\n'
printf ' App:      %s\n ZIP:      %s\n DMG:      %s\n Sums:     %s\n' "$APP" "$ZIP" "$DMG" "$DIST/SHA256SUMS.txt"
[[ "$HAVE_SPARKLE" == 1 ]] && printf ' Appcast:  %s\n' "$APPCAST"
if [[ "$HAVE_SPARKLE" == 1 && ${#DELTAS[@]} -gt 0 ]]; then
  printf ' Deltas:\n'; for d in "${DELTAS[@]}"; do printf '   %s\n' "$d"; done
fi
if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  printf ' Warnings:\n'; for w in "${WARNINGS[@]}"; do printf '   - %s\n' "$w"; done
fi

if [[ ${#NOT_RELEASABLE[@]} -eq 0 && -z "$DRY_RUN_DIR" ]]; then
  cat <<EOF

Go-live steps (this script does none of them; see docs/RELEASE.md):
  1. Review appcast.xml and release-notes/$VERSION.md, then commit the source, notes and appcast
     (never the ZIP, DMG or deltas):   git add appcast.xml release-notes/$VERSION.md && git commit -m "Release $TAG"
  2. Tag:                              git tag $TAG
  3. Push the tag only:                git push origin refs/tags/$TAG
  4. Create the GitHub release $TAG from release-notes/$VERSION.md and upload:
       $(basename "$DMG"), $(basename "$ZIP")$([[ ${#DELTAS[@]} -gt 0 ]] && printf ' and every delta listed above')
     Check each asset is public and matches SHA256SUMS.txt.
  5. Only then expose the update feed:  git push origin main
     and check the public appcast matches the local file.
EOF
else
  printf '\nNo go-live steps: this run is a rehearsal or not releasable.\n'
fi
