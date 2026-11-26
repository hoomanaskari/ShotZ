#!/usr/bin/env bash
# Builds one of the two Shotz apps (ARCHITECTURE §8):
#   scripts/bundle.sh dev       → build/ShotZ Dev.app  (<id>.dev, debug build)
#   scripts/bundle.sh release   → build/ShotZ.app      (<id>, release build)
# <id> is CFBundleIdentifier in Resources/Info.plist (com.pixelforty.shotz), the one
# place scripts read it from; Swift has the same value in AppVariant (a test checks).
# `debug` is accepted as an alias for `dev`. The two apps are separate: own
# bundle id, name, icon, preferences, data folder, login item, default
# shortcuts and Screen Recording permission. Building one never touches the other.
#
# Version: CFBundleShortVersionString / CFBundleVersion come from
# Resources/Info.plist (the single source of truth); they are checked and printed.
#
# Signing identity: $SHOTZ_SIGN_IDENTITY (name or SHA-1), else the first
# "Apple Development" identity, else ad-hoc. Debug and release use the SAME
# rule on purpose: macOS ties the Screen Recording grant to the signing
# identity, so switching certificates would silently drop the grant. A release
# build refuses to sign ad-hoc unless SHOTZ_ALLOW_ADHOC=1 (an ad-hoc release
# loses the grant on every rebuild).
#
# Architectures: release builds are universal (arm64 + x86_64; checked with
# lipo for the app and every Sparkle binary). Dev builds are host-only.
# SHOTZ_UNIVERSAL=0 makes a release host-only, SHOTZ_UNIVERSAL=1 makes dev universal.
#
# Sparkle.framework (software updates) is embedded in Contents/Frameworks with an
# @executable_path/../Frameworks rpath and signed inside-out with the same identity:
# the XPC services, Autoupdate, Updater.app, the framework, then the app.
#
# Hardened runtime on release builds (verified after signing). Secure timestamp
# (--timestamp, needed for notarization) when the identity is a Developer ID;
# otherwise --timestamp=none so Apple Development and ad-hoc builds sign offline.
# SHOTZ_TIMESTAMP=1/0 forces it either way.
#
# Updates (production only): SUFeedURL and SUEnableAutomaticChecks come from
# Resources/Info.plist; SUPublicEDKey is filled from Resources/SparklePublicKey.txt
# (empty until a key exists: the app then shows "updates unavailable"). ShotZ Dev's
# Info.plist drops all three; it never creates an updater anyway.
#
# For a fully signed release (e.g. scripts/release.sh):
#   SHOTZ_SIGN_IDENTITY="Developer ID Application: … (TEAMID)" scripts/bundle.sh release
# The last line printed is "Built <path> (<id>, <config>, version <v> (<build>))".
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VARIANT="${1:-dev}"
case "$VARIANT" in
  dev|debug) VARIANT=dev; CONFIG=debug; APP_NAME="ShotZ Dev"; OLD_NAME="Shotz Dev"; ID_SUFFIX=".dev"; ICON="AppIcon-Dev.icns" ;;
  release) CONFIG=release; APP_NAME="ShotZ"; OLD_NAME="Shotz"; ID_SUFFIX=""; ICON="AppIcon.icns" ;;
  *) echo "usage: $0 [dev|release]" >&2; exit 64 ;;
esac

PLIST="$ROOT/Resources/Info.plist"
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null || true; }
BUNDLE_ID="$(plist CFBundleIdentifier)"
VERSION="$(plist CFBundleShortVersionString)"
BUILD="$(plist CFBundleVersion)"
if [[ -z "$BUNDLE_ID" || "$BUNDLE_ID" == *.dev || -z "$VERSION" || -z "$BUILD" ]]; then
  echo "Resources/Info.plist: need the production CFBundleIdentifier, CFBundleShortVersionString and CFBundleVersion" >&2
  exit 65
fi
APP_ID="$BUNDLE_ID$ID_SUFFIX"

cd "$ROOT"
UNIVERSAL="${SHOTZ_UNIVERSAL:-$([[ "$CONFIG" == "release" ]] && echo 1 || echo 0)}"
ARCH_ARGS=()
[[ "$UNIVERSAL" == "1" ]] && ARCH_ARGS=(--arch arm64 --arch x86_64)
swift build -c "$CONFIG" ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"} --product Shotz
BIN_DIR="$(swift build -c "$CONFIG" ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"} --show-bin-path)"
SPARKLE_SRC="$BIN_DIR/Sparkle.framework"
[[ -d "$SPARKLE_SRC" ]] || { echo "Sparkle.framework not found in $BIN_DIR" >&2; exit 68; }

# The product is ShotZ; the SwiftPM product stays `Shotz` and is renamed into
# the bundle. Built under a temporary name and moved into place at the end:
# on a case-insensitive disk `Shotz.app` and `ShotZ.app` are the same path, so
# renaming in place would keep the old spelling.
EXE_NAME="$(plist CFBundleExecutable)"
FINAL="$ROOT/build/$APP_NAME.app"
APP="$ROOT/build/.bundle-$VARIANT-$$.app"
trap 'rm -rf "$APP"' EXIT
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
EXE="$APP/Contents/MacOS/$EXE_NAME"
cp "$BIN_DIR/Shotz" "$EXE"
# Load Sparkle from inside the bundle; drop rpaths that point into this machine's build folder.
install_name_tool -add_rpath "@executable_path/../Frameworks" "$EXE"
while IFS= read -r rpath; do
  [[ "$rpath" == "$ROOT"/* ]] && install_name_tool -delete_rpath "$rpath" "$EXE"
done < <(otool -l "$EXE" | awk '/LC_RPATH/ { getline; getline; print $2 }')
ditto "$SPARKLE_SRC" "$APP/Contents/Frameworks/Sparkle.framework"

INFO="$APP/Contents/Info.plist"
cp "$PLIST" "$INFO"
if [[ "$VARIANT" == "dev" ]]; then
  # Same Info.plist, development identity. The app reads its variant from the bundle id.
  /usr/libexec/PlistBuddy \
    -c "Set :CFBundleIdentifier $APP_ID" \
    -c "Set :CFBundleName $APP_NAME" \
    -c "Set :CFBundleDisplayName $APP_NAME" \
    -c "Delete :SUFeedURL" \
    -c "Delete :SUEnableAutomaticChecks" \
    "$INFO"
else
  # The public EdDSA key lives in one committed file; empty means "no updates yet".
  PUBLIC_KEY="$(tr -d '[:space:]' < "$ROOT/Resources/SparklePublicKey.txt" 2>/dev/null || true)"
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $PUBLIC_KEY" "$INFO"
  [[ -n "$PUBLIC_KEY" ]] || echo "Note: Resources/SparklePublicKey.txt is empty: this build reports updates as unavailable"
fi

if [[ "$UNIVERSAL" == "1" ]]; then
  SPK="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
  for bin in "$EXE" "$SPK/Sparkle" "$SPK/Autoupdate" "$SPK/Updater.app/Contents/MacOS/Updater" \
             "$SPK/XPCServices/Downloader.xpc/Contents/MacOS/Downloader" "$SPK/XPCServices/Installer.xpc/Contents/MacOS/Installer"; do
    archs="$(lipo -archs "$bin")"
    if [[ " $archs " != *" arm64 "* || " $archs " != *" x86_64 "* ]]; then
      echo "Not universal: ${bin#"$APP"/} has [$archs]" >&2
      exit 69
    fi
  done
  echo "Universal: app and Sparkle binaries contain arm64 and x86_64"
fi
cp "$ROOT/Resources/$ICON" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

IDENTITY="${SHOTZ_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  # Use the certificate hash: several identities can share one name.
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk '/"Apple Development/ { print $2; exit }' || true)"
fi
IDENTITY="${IDENTITY:--}"

if [[ "$IDENTITY" == "-" && "$CONFIG" == "release" && "${SHOTZ_ALLOW_ADHOC:-0}" != "1" ]]; then
  echo "No signing identity for a release build. Set SHOTZ_SIGN_IDENTITY, or SHOTZ_ALLOW_ADHOC=1 to sign ad-hoc" >&2
  echo "(an ad-hoc build loses the Screen Recording grant on every rebuild)." >&2
  exit 66
fi

# Developer ID identities get a secure timestamp (notarization requires it).
IDENTITY_NAME="$IDENTITY"
if [[ "$IDENTITY" != "-" ]]; then
  IDENTITY_NAME="$(security find-identity -v -p codesigning 2>/dev/null | awk -v id="$IDENTITY" 'index($0, id) { sub(/^[^"]*"/, ""); sub(/"[^"]*$/, ""); print; exit }')"
  IDENTITY_NAME="${IDENTITY_NAME:-$IDENTITY}"
fi
if [[ "${SHOTZ_TIMESTAMP:-}" == "1" || ( -z "${SHOTZ_TIMESTAMP:-}" && "$IDENTITY_NAME" == "Developer ID Application"* ) ]]; then
  TIMESTAMP=(--timestamp)
else
  TIMESTAMP=(--timestamp=none)
fi
COMMON=(--force --sign "$IDENTITY" "${TIMESTAMP[@]}")
[[ "$CONFIG" == "release" ]] && COMMON+=(--options runtime)
if [[ "$IDENTITY" == "-" ]]; then
  echo "Signing ad-hoc (no Apple Development identity found)"
else
  echo "Signing with identity $IDENTITY_NAME (${TIMESTAMP[*]})"
fi

# Inside-out: Sparkle's helpers, the framework, then the app.
SPK="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
codesign "${COMMON[@]}" "$SPK/XPCServices/Installer.xpc"
codesign "${COMMON[@]}" --preserve-metadata=entitlements "$SPK/XPCServices/Downloader.xpc"
codesign "${COMMON[@]}" "$SPK/Autoupdate"
codesign "${COMMON[@]}" "$SPK/Updater.app"
codesign "${COMMON[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
codesign "${COMMON[@]}" --identifier "$APP_ID" "$APP"
codesign --verify --strict --deep "$APP"

if [[ "$CONFIG" == "release" ]]; then
  # Capture first: with pipefail, `grep -q` exiting early would fail the pipe.
  SIGNATURE="$(codesign -d --verbose=2 "$APP" 2>&1)"
  if [[ "$SIGNATURE" != *"(runtime)"* ]]; then
    echo "Release bundle is missing the hardened runtime flag" >&2
    exit 67
  fi
fi
# Replace the previous bundle under either spelling, then move the new one in.
rm -rf "$ROOT/build/$OLD_NAME.app" "$FINAL"
mv "$APP" "$FINAL"
codesign --verify --strict --deep "$FINAL"
echo "Built $FINAL ($APP_ID, $CONFIG, version $VERSION ($BUILD))"
