#!/usr/bin/env bash
# Builds a releasable ShotZ: signed with the Developer ID and the hardened runtime, notarized and
# stapled, as a Sparkle update archive and a DMG, plus the regenerated appcast. See docs/RELEASE.md.
#
#   scripts/release.sh                               the real release (clean main, new version, untagged)
#   scripts/release.sh --skip-notarize               everything except the two notarization
#                                                    submissions and stapling: NOT RELEASABLE
#   scripts/release.sh --skip-appcast                no appcast (no Sparkle signing): NOT RELEASABLE
#   scripts/release.sh --dry-run-dir <dir> --rehearse-appcast
#                                                    a rehearsal that also signs the appcast with the
#                                                    Sparkle key, inside <dir>, and verifies it against
#                                                    the committed public key (still not notarized)
#   scripts/release.sh --dry-run-dir <dir> [...]     a rehearsal: outputs go to <dir> (dist, sparkle
#                                                    releases, appcast); git checks only warn; allowed
#                                                    from a worktree
# Rehearsals (--skip-notarize or --dry-run-dir) never touch the notary profile, and never touch the
# Sparkle key unless --rehearse-appcast is given; they say NOT RELEASABLE.
#
# Outputs (in dist/, or <dir>/dist for a rehearsal):
#   ShotZ.app                 the signed (and, when notarized, stapled) app
#   ShotZ-<version>.zip       the Sparkle update archive
#   ShotZ-<version>.dmg       the manual download, with an Applications link
#   ShotZ<build>-<old>.delta  Sparkle deltas from earlier archives in sparkle-releases/ (second and
#                             later releases)
#   SHA256SUMS.txt            checksums of everything to upload (DMG, zip, deltas)
# and the appcast (appcast.xml, or <dir>/appcast.xml) from sparkle-releases/ (archives, deltas).
#
# This script never pushes, tags, publishes or uploads anything: it prints the go-live steps.
# It never prints secrets and never runs with `set -x`.
#
# Environment (all optional):
#   SHOTZ_DEVELOPER_ID   Developer ID Application identity (SHA-1 or exact name); default: the one
#                        on this Mac whose certificate lasts longest (several can share a name)
#   NOTARY_PROFILE       notarytool keychain profile (default: notarytool-profile)
# Committed configuration: Resources/DeveloperTeamID.txt (the only team allowed to sign a release),
# Resources/SparkleKeyAccount.txt and Resources/SparklePublicKey.txt.
#   SHOTZ_GITHUB_REPO    owner/name of the GitHub repository the downloads come from (default:
#                        the repository in SUFeedURL; must match it when both are set)
#   SPARKLE_BIN          folder with Sparkle's generate_appcast (default: found in .build/artifacts)
#   SPARKLE_KEY_ACCOUNT  keychain account of the Sparkle EdDSA key (default: Resources/SparkleKeyAccount.txt,
#                        i.e. shotz; empty = Sparkle's default account)
set -euo pipefail
set +x

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SKIP_NOTARIZE=0
SKIP_APPCAST=0
REHEARSE_APPCAST=0
DRY_RUN_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-notarize) SKIP_NOTARIZE=1; shift ;;
    --skip-appcast) SKIP_APPCAST=1; shift ;;
    --rehearse-appcast) REHEARSE_APPCAST=1; shift ;;
    --dry-run-dir)
      [[ $# -ge 2 && -n "$2" ]] || { echo "release.sh: --dry-run-dir needs a directory" >&2; exit 64; }
      DRY_RUN_DIR="$2"; shift 2 ;;
    -h|--help) sed -n '2,39p' "$0"; exit 0 ;;
    *) echo "release.sh: unknown option $1 (see --help)" >&2; exit 64 ;;
  esac
done

APP_NAME="ShotZ"
NOTARY_PROFILE="${NOTARY_PROFILE:-notarytool-profile}"
# The Sparkle key's keychain account is committed next to the public key, not set in a shell profile.
SPARKLE_KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT-$(tr -d '[:space:]' < "$ROOT/Resources/SparkleKeyAccount.txt" 2>/dev/null || true)}"
if [[ "$REHEARSE_APPCAST" == 1 && ( -z "$DRY_RUN_DIR" || "$SKIP_APPCAST" == 1 ) ]]; then
  echo "release.sh: --rehearse-appcast needs --dry-run-dir <dir> (and not --skip-appcast)" >&2; exit 64
fi
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

for cmd in git swift codesign spctl hdiutil ditto shasum plutil openssl create-dmg security xmllint; do
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
# Only identities of the committed team can sign a release (Resources/DeveloperTeamID.txt).
EXPECTED_TEAM_ID="$(tr -d '[:space:]' < "$ROOT/Resources/DeveloperTeamID.txt" 2>/dev/null || true)"
[[ "$EXPECTED_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || stop "Resources/DeveloperTeamID.txt must hold the 10-character Apple team id."
identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
team_identities="$(grep '"Developer ID Application:' <<<"$identities" | grep -F "($EXPECTED_TEAM_ID)\"" || true)"
IDENTITY="${SHOTZ_DEVELOPER_ID:-}"
if [[ -z "$IDENTITY" ]]; then
  newest=0
  for hash in $(awk '{ print $2 }' <<<"$team_identities"); do
    ends="$(cert_end_epoch "$hash")"
    if [[ "$ends" -gt "$newest" ]]; then newest="$ends"; IDENTITY="$hash"; fi
  done
  [[ -n "$IDENTITY" ]] || stop "no Developer ID Application certificate for team $EXPECTED_TEAM_ID on this Mac (see docs/RELEASE.md, one-time setup)."
  ok "Developer ID Application identity of team $EXPECTED_TEAM_ID selected (longest-lasting; expires $(date -j -f %s "$newest" +%Y-%m-%d))"
else
  grep -F -- "$IDENTITY" <<<"$team_identities" >/dev/null \
    || stop "SHOTZ_DEVELOPER_ID does not name a valid Developer ID Application identity of team $EXPECTED_TEAM_ID on this Mac."
  ok "Developer ID Application identity of team $EXPECTED_TEAM_ID from SHOTZ_DEVELOPER_ID"
fi

REHEARSAL=0
[[ "$SKIP_NOTARIZE" == 1 || -n "$DRY_RUN_DIR" ]] && REHEARSAL=1
[[ "$REHEARSAL" == 1 && "$REHEARSE_APPCAST" == 0 ]] && SKIP_APPCAST=1
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
elif [[ ( "$REHEARSAL" == 1 && "$REHEARSE_APPCAST" == 0 ) || "$SKIP_APPCAST" == 1 ]]; then
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

# Second and later releases: the feed already has items. They are kept unchanged and the new build
# must be newer than all of them. A rehearsal works on a copy: <dir>/appcast.xml if a previous
# rehearsal left one there, else the committed appcast.xml (copied in the appcast step).
FEED_SOURCE="$ROOT/appcast.xml"
[[ -n "$DRY_RUN_DIR" && -f "$APPCAST" ]] && FEED_SOURCE="$APPCAST"
PREV_BUILDS=()
PREV_VERSIONS=()
if [[ "$HAVE_SPARKLE" == 1 && -s "$FEED_SOURCE" ]]; then
  xmllint --noout "$FEED_SOURCE" 2>/dev/null || stop "$FEED_SOURCE is not well-formed XML."
  feed_xp() { xmllint --xpath "$1" "$FEED_SOURCE" 2>/dev/null || true; }
  n_items="$(feed_xp "count(//*[local-name()='item'])")"
  for ((i = 1; i <= n_items; i++)); do
    b="$(feed_xp "string((//*[local-name()='item'])[$i]/*[local-name()='version'])")"
    v="$(feed_xp "string((//*[local-name()='item'])[$i]/*[local-name()='shortVersionString'])")"
    [[ "$b" =~ ^[0-9]+$ ]] || stop "item $i of the feed has no whole-number sparkle:version ('$b')."
    [[ "$b" -lt "$BUILD" ]] || stop "the feed already has build $b ($v): build $BUILD must be higher than every build in it (scripts/bump-version.sh)."
    [[ "$v" != "$VERSION" ]] || stop "the feed already has version $VERSION (build $b)."
    PREV_BUILDS+=("$b")
    PREV_VERSIONS+=("$v")
  done
  if [[ "$n_items" -gt 0 ]]; then
    ok "the feed has $n_items earlier item(s) (${PREV_VERSIONS[*]}): build $BUILD is newer than all of them"
    for v in "${PREV_VERSIONS[@]}"; do
      [[ -f "$ROOT/sparkle-releases/$APP_NAME-$v.zip" || -f "$RELEASES_DIR/$APP_NAME-$v.zip" ]] \
        || warn "no delta from $v: sparkle-releases/$APP_NAME-$v.zip is missing (installed $v copies download the full ZIP)"
    done
  fi
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
team_of() { codesign -dvv "$1" 2>&1 | sed -n 's/^TeamIdentifier=//p' || true; }
[[ "$(team_of "$APP")" == "$EXPECTED_TEAM_ID" ]] || stop "the app's TeamIdentifier is not $EXPECTED_TEAM_ID."
if [[ -d "$SPARKLE_FW" ]]; then
  [[ "$(team_of "$SPARKLE_FW")" == "$EXPECTED_TEAM_ID" ]] || stop "Sparkle.framework's TeamIdentifier is not $EXPECTED_TEAM_ID."
fi
ok "TeamIdentifier $EXPECTED_TEAM_ID on the app$([[ -d "$SPARKLE_FW" ]] && echo ' and Sparkle.framework')"
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

# The licences ship inside the app, identical to the repository's copies.
for notice in LICENSE THIRD-PARTY-NOTICES; do
  [[ -s "$APP/Contents/Resources/$notice" ]] || stop "the app has no (or an empty) Contents/Resources/$notice."
  cmp -s "$APP/Contents/Resources/$notice" "$ROOT/$notice" || stop "the app's $notice differs from the repository's."
done
ok "LICENSE and THIRD-PARTY-NOTICES are in the app and match the repository"

# No build-machine paths in anything shipped: every Mach-O in the app (main executable, Sparkle,
# Autoupdate, Updater.app, the XPC services), each architecture on its own, checked as raw bytes
# (the symbol string table, which `strings` skips) and with `strings -a`. bundle.sh strips the
# executable; Sparkle's prebuilt binaries are used as they are.
BUILD_USER="$(id -un)"
path_leaks=()
while IFS= read -r f; do
  file -b "$f" | grep -q 'Mach-O' || continue
  for arch in $(xcrun lipo -archs "$f" 2>/dev/null || echo single); do
    thin="$STAGE/thin-check"
    xcrun lipo "$f" -thin "$arch" -output "$thin" 2>/dev/null || cp "$f" "$thin"
    hits="$( { LC_ALL=C grep -a -o '/Users/[[:print:]]*' "$thin" || true; strings -a "$thin" | grep -e '/Users/' || true; } | head -3)"
    if [[ ${#BUILD_USER} -ge 3 ]]; then
      hits+="$( { LC_ALL=C grep -a -o "[[:print:]]\{0,30\}$BUILD_USER[[:print:]]\{0,30\}" "$thin" || true; } | head -3)"
    fi
    [[ -z "$hits" ]] || path_leaks+=("${f#$APP/} ($arch): $(head -1 <<<"$hits")")
  done
done < <(find "$APP" -type f)
rm -f "$STAGE/thin-check"
if [[ ${#path_leaks[@]} -eq 0 ]]; then
  ok "no /Users/ paths or the build user's name in any Mach-O (every architecture)"
else
  for l in "${path_leaks[@]}"; do printf '    build path in: %s\n' "$l"; done
  stop "shipped binaries contain build-machine paths (see above). Release builds must be stripped (bundle.sh)."
fi

# ---------------------------------------------------------------------------------------------
notarize() { # notarize <file>: prints the submission id; on failure saves Apple's log in dist/
  local file="$1" name result id status
  name="$(basename "$file")"
  printf '    submitting %s (Apple usually takes a few minutes)\n' "$name"
  result="$STAGE/notary-$name.json"
  set +e
  xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$result" 2>"$STAGE/notary-$name.err"
  set -e
  id="$(plutil -extract id raw -o - "$result" 2>/dev/null || true)"
  status="$(plutil -extract status raw -o - "$result" 2>/dev/null || true)"
  printf '    submission id for %s: %s (status: %s)\n' "$name" "${id:-unknown}" "${status:-unknown}"
  if [[ "$status" != Accepted ]]; then
    if [[ -n "$id" ]]; then
      # The log lists the issues Apple found; it holds no credentials.
      xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" "$DIST/notary-log-$name-$id.json" >/dev/null 2>&1 || true
      printf '    notarization log: %s\n' "$DIST/notary-log-$name-$id.json"
    else
      sed 's/^/    /' "$STAGE/notary-$name.err" >&2
    fi
    stop "notarization of $name was not accepted (status: ${status:-unknown})."
  fi
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
[[ "$(sed -n 's/^TeamIdentifier=//p' <<<"$dmg_sig")" == "$EXPECTED_TEAM_ID" ]] || stop "the DMG's TeamIdentifier is not $EXPECTED_TEAM_ID."
hdiutil verify -quiet "$DMG" || stop "hdiutil verify fails for the DMG."
ok "$(basename "$DMG") (Developer ID signature, team $EXPECTED_TEAM_ID, image checksum)"
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
  # sparkle-releases/ keeps the archives (the next release makes deltas from them) but only its
  # .gitignore is committed: archives, deltas and the notes copies here are build products.
  touch "$RELEASES_DIR/.gitignore"
  for pattern in '*.zip' '*.delta' '*.dmg' '*.md'; do
    grep -qxF "$pattern" "$RELEASES_DIR/.gitignore" || printf '%s\n' "$pattern" >> "$RELEASES_DIR/.gitignore"
  done
  if [[ -n "$DRY_RUN_DIR" ]]; then
    # A rehearsal works on copies of the real previous archives, notes and feed (never changed in
    # place), so it exercises the real case: older items kept, deltas from the previous archives.
    [[ -d "$ROOT/sparkle-releases" ]] && find "$ROOT/sparkle-releases" -maxdepth 1 \( -name '*.zip' -o -name '*.md' \) -exec cp -n {} "$RELEASES_DIR/" \;
    [[ -f "$APPCAST" || ! -f "$ROOT/appcast.xml" ]] || cp "$ROOT/appcast.xml" "$APPCAST"
  fi
  cp "$ZIP" "$RELEASES_DIR/"
  # Sparkle pairs release notes with the archive of the same name.
  [[ -s "$NOTES" ]] && cp "$NOTES" "$RELEASES_DIR/$APP_NAME-$VERSION.md"
  # Snapshot the earlier items, and note which earlier versions have their archive here (Sparkle
  # makes a delta from each of the newest 5).
  xp() { xmllint --xpath "$1" "$APPCAST" 2>/dev/null || true; }
  item_of() { printf "//*[local-name()='item'][*[local-name()='version']='%s']" "$1"; }
  EXPECTED_DELTAS=()
  for ((i = 0; i < ${#PREV_BUILDS[@]}; i++)); do
    b="${PREV_BUILDS[$i]}"
    xp "$(item_of "$b")" > "$STAGE/item-$b.before.xml"
    [[ -s "$STAGE/item-$b.before.xml" ]] || stop "could not read the feed's item for build $b."
    if [[ -f "$RELEASES_DIR/$APP_NAME-${PREV_VERSIONS[$i]}.zip" && ${#EXPECTED_DELTAS[@]} -lt 5 ]]; then
      EXPECTED_DELTAS+=("$b")
    fi
  done
  [[ ${#PREV_BUILDS[@]} -gt 0 ]] && cp "$APPCAST" "$STAGE/feed-before.xml"
  # Reached in a real run, or in a rehearsal with --rehearse-appcast (all inside the dry-run dir).
  account_args=()
  [[ -n "$SPARKLE_KEY_ACCOUNT" ]] && account_args=(--account "$SPARKLE_KEY_ACCOUNT")
  # Run once, with a time limit: the first use of the key can show a keychain access dialog. A
  # timeout or keychain error stops the release; it is never retried automatically.
  set +e
  perl -e 'alarm shift; exec @ARGV' 180 "$SPARKLE_BIN/generate_appcast" \
    ${account_args[@]+"${account_args[@]}"} \
    --download-url-prefix "https://github.com/$SHOTZ_GITHUB_REPO/releases/download/$TAG/" \
    --embed-release-notes \
    --link "https://github.com/$SHOTZ_GITHUB_REPO" \
    --versions "$BUILD" \
    --maximum-versions 0 \
    -o "$APPCAST" \
    "$RELEASES_DIR" > "$STAGE/generate_appcast.log" 2>&1
  status=$?
  set -e
  sed 's/^/    /' "$STAGE/generate_appcast.log"
  if [[ $status -eq 142 ]]; then
    stop "generate_appcast did not finish within 180 s (a keychain access dialog may be waiting). Not retried."
  elif [[ $status -ne 0 ]]; then
    stop "generate_appcast failed (exit $status, output above). Not retried."
  fi
  # generate_appcast rewrites the enclosure (and delta) URLs of every earlier item whose archive is
  # in sparkle-releases/ to this release's --download-url-prefix, where those files don't exist.
  # Put each earlier <item> block back exactly as it was (the appcast itself is not signed); the
  # byte-for-byte check below confirms it.
  if [[ ${#PREV_BUILDS[@]} -gt 0 ]]; then
    cat > "$STAGE/restore-items.swift" <<'SWIFT'
import Foundation
// restore-items <before.xml> <appcast.xml> <build>...: replaces each build's <item> block in the
// appcast with the block from before.xml, line for line. Prints how many blocks changed.
let a = CommandLine.arguments
func blocks(_ lines: [String]) -> [String: Range<Int>] {
    var out: [String: Range<Int>] = [:], start: Int?
    for (i, l) in lines.enumerated() {
        let t = l.trimmingCharacters(in: .whitespaces)
        if t == "<item>" { start = i }
        else if t == "</item>", let s = start {
            if let v = lines[s...i].first(where: { $0.contains("<sparkle:version>") }) {
                out[v.trimmingCharacters(in: .whitespaces)] = s..<(i + 1)
            }
            start = nil
        }
    }
    return out
}
guard a.count >= 4, let before = try? String(contentsOfFile: a[1], encoding: .utf8),
      let after = try? String(contentsOfFile: a[2], encoding: .utf8) else { print("unreadable"); exit(2) }
let old = before.components(separatedBy: "\n")
var new = after.components(separatedBy: "\n")
var changed = 0
for build in a[3...] {
    let key = "<sparkle:version>\(build)</sparkle:version>"
    guard let o = blocks(old)[key], let n = blocks(new)[key] else { print("no item block for build \(build)"); exit(1) }
    let original = Array(old[o])
    if Array(new[n]) != original { new.replaceSubrange(n, with: original); changed += 1 }
}
do { try new.joined(separator: "\n").write(toFile: a[2], atomically: true, encoding: .utf8) } catch { print("write failed"); exit(1) }
print(changed)
SWIFT
    restored="$(swift "$STAGE/restore-items.swift" "$STAGE/feed-before.xml" "$APPCAST" "${PREV_BUILDS[@]}" 2>&1)" \
      || stop "could not restore the earlier appcast items ($restored)."
    [[ "$restored" =~ ^[0-9]+$ ]] || stop "could not restore the earlier appcast items ($restored)."
    [[ "$restored" == 0 ]] || ok "restored $restored earlier item(s) that generate_appcast had pointed at the $TAG release"
  fi
  # Verify the new item: version, build, enclosure URL, length and the EdDSA signature against
  # the committed public key (checked here with CryptoKit, without the private key).
  item="$(item_of "$BUILD")"
  [[ -n "$(xp "string($item/*[local-name()='version'])")" ]] || stop "the appcast has no item for build $BUILD."
  [[ "$(xp "string($item/*[local-name()='shortVersionString'])")" == "$VERSION" ]] || stop "the appcast item for build $BUILD is not version $VERSION."
  enc_url="$(xp "string($item/*[local-name()='enclosure']/@url)")"
  expected_url="https://github.com/$SHOTZ_GITHUB_REPO/releases/download/$TAG/$APP_NAME-$VERSION.zip"
  [[ "$enc_url" == "$expected_url" ]] || stop "the enclosure URL is $enc_url, expected $expected_url."
  enc_sig="$(xp "string($item/*[local-name()='enclosure']/@*[local-name()='edSignature'])")"
  enc_len="$(xp "string($item/*[local-name()='enclosure']/@length)")"
  [[ -n "$enc_sig" ]] || stop "the appcast enclosure has no sparkle:edSignature."
  [[ "$enc_len" == "$(stat -f %z "$ZIP")" ]] || stop "the enclosure length ($enc_len) doesn't match the zip."
  cat > "$STAGE/verify-ed25519.swift" <<'SWIFT'
import CryptoKit
import Foundation
let args = CommandLine.arguments
guard args.count == 4, let key = Data(base64Encoded: args[1]), let sig = Data(base64Encoded: args[2]),
      let data = FileManager.default.contents(atPath: args[3]),
      let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: key) else { print("unreadable"); exit(2) }
print(publicKey.isValidSignature(sig, for: data) ? "valid" : "invalid")
SWIFT
  verdict="$(swift "$STAGE/verify-ed25519.swift" "$PUBLIC_KEY" "$enc_sig" "$ZIP" 2>/dev/null || true)"
  [[ "$verdict" == valid ]] || stop "the enclosure's EdDSA signature does not verify against Resources/SparklePublicKey.txt ($verdict)."
  cp "$ZIP" "$STAGE/tampered.zip"
  printf 'x' >> "$STAGE/tampered.zip"
  tampered="$(swift "$STAGE/verify-ed25519.swift" "$PUBLIC_KEY" "$enc_sig" "$STAGE/tampered.zip" 2>/dev/null || true)"
  [[ "$tampered" == invalid ]] || stop "signature check is not discriminating (a changed archive gave '$tampered')."
  ok "appcast item $VERSION ($BUILD): enclosure $enc_url, length matches, EdDSA signature verifies against the committed public key (a changed archive fails)"

  # The new item is the newest, and every earlier item is still there, byte for byte.
  [[ "$(xp "count(//*[local-name()='item'])")" == "$(( ${#PREV_BUILDS[@]} + 1 ))" ]] \
    || stop "the appcast should have $(( ${#PREV_BUILDS[@]} + 1 )) items (${#PREV_BUILDS[@]} earlier + $VERSION)."
  [[ "$(xp "string((//*[local-name()='item'])[1]/*[local-name()='version'])")" == "$BUILD" ]] \
    || stop "the first appcast item is not build $BUILD."
  for b in ${PREV_BUILDS[@]+"${PREV_BUILDS[@]}"}; do
    xp "$(item_of "$b")" > "$STAGE/item-$b.after.xml"
    cmp -s "$STAGE/item-$b.before.xml" "$STAGE/item-$b.after.xml" \
      || { diff "$STAGE/item-$b.before.xml" "$STAGE/item-$b.after.xml" | head -n 20 | sed 's/^/    /'; stop "generate_appcast changed the earlier item for build $b."; }
  done
  [[ ${#PREV_BUILDS[@]} -gt 0 ]] && ok "newest item is $VERSION ($BUILD); the ${#PREV_BUILDS[@]} earlier item(s) (${PREV_VERSIONS[*]}) are unchanged"

  # Deltas: one from each earlier archive found here (newest 5), each listed in the new item with
  # the right URL, length and a valid EdDSA signature. They are uploaded with the release.
  for b in ${EXPECTED_DELTAS[@]+"${EXPECTED_DELTAS[@]}"}; do
    [[ -f "$RELEASES_DIR/$APP_NAME$BUILD-$b.delta" ]] || stop "no delta from build $b ($APP_NAME$BUILD-$b.delta) although its archive is in sparkle-releases/."
  done
  while IFS= read -r d; do DELTAS+=("$d"); done < <(find "$RELEASES_DIR" -maxdepth 1 -name "${APP_NAME}${BUILD}-*.delta" | sort)
  for d in ${DELTAS[@]+"${DELTAS[@]}"}; do
    name="$(basename "$d")"
    from="${name#"$APP_NAME$BUILD-"}"; from="${from%.delta}"
    delta="$item/*[local-name()='deltas']/*[local-name()='enclosure'][@*[local-name()='deltaFrom']='$from']"
    [[ "$(xp "string($delta/@url)")" == "https://github.com/$SHOTZ_GITHUB_REPO/releases/download/$TAG/$name" ]] \
      || stop "the appcast has no delta enclosure for $name at the $TAG release URL."
    [[ "$(xp "string($delta/@length)")" == "$(stat -f %z "$d")" ]] || stop "the delta enclosure length for $name doesn't match the file."
    dsig="$(xp "string($delta/@*[local-name()='edSignature'])")"
    [[ "$(swift "$STAGE/verify-ed25519.swift" "$PUBLIC_KEY" "$dsig" "$d" 2>/dev/null || true)" == valid ]] \
      || stop "the EdDSA signature of $name does not verify against Resources/SparklePublicKey.txt."
    cp "$d" "$DIST/"
    ok "delta $name (from build $from): URL, length and EdDSA signature verify; copied to dist/ for upload"
  done
fi

# ---------------------------------------------------------------------------------------------
step "Checksums"
UPLOADS=("$(basename "$DMG")" "$(basename "$ZIP")")
for d in ${DELTAS[@]+"${DELTAS[@]}"}; do UPLOADS+=("$(basename "$d")"); done
(cd "$DIST" && shasum -a 256 "${UPLOADS[@]}" > SHA256SUMS.txt && sed 's/^/    /' SHA256SUMS.txt)

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
  printf ' Deltas:\n'; for d in "${DELTAS[@]}"; do printf '   %s\n' "$DIST/$(basename "$d")"; done
fi
printf ' Upload:   %s (from %s, as listed in SHA256SUMS.txt)\n' "${UPLOADS[*]}" "$DIST"
if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  printf ' Warnings:\n'; for w in "${WARNINGS[@]}"; do printf '   - %s\n' "$w"; done
fi

if [[ ${#NOT_RELEASABLE[@]} -eq 0 && -z "$DRY_RUN_DIR" ]]; then
  cat <<EOF

Go-live steps (this script does none of them; see docs/RELEASE.md):
  1. Review appcast.xml and release-notes/$VERSION.md, then commit exactly these three files
     (never the ZIP, DMG, deltas or anything else in dist/ or sparkle-releases/):
       git add appcast.xml release-notes/$VERSION.md sparkle-releases/.gitignore && git commit -m "Release $TAG"
  2. Tag:                              git tag $TAG
  3. Push the tag only:                git push origin refs/tags/$TAG
  4. Create the GitHub release $TAG from release-notes/$VERSION.md and upload these files from dist/
     (exactly the files in SHA256SUMS.txt):
$(for u in "${UPLOADS[@]}"; do printf '       %s\n' "$u"; done)
     Check each asset is public and matches SHA256SUMS.txt.
  5. Only then expose the update feed:  git push origin main
     and check the public appcast matches the local file.
EOF
else
  printf '\nNo go-live steps: this run is a rehearsal or not releasable.\n'
fi
