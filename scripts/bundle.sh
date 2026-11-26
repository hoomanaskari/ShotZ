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
# Release builds use the hardened runtime (verified after signing). No secure
# timestamp: signing never contacts the network.
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
swift build -c "$CONFIG" --product Shotz
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

# The product is ShotZ; the SwiftPM product stays `Shotz` and is renamed into
# the bundle. Built under a temporary name and moved into place at the end:
# on a case-insensitive disk `Shotz.app` and `ShotZ.app` are the same path, so
# renaming in place would keep the old spelling.
EXE_NAME="$(plist CFBundleExecutable)"
FINAL="$ROOT/build/$APP_NAME.app"
APP="$ROOT/build/.bundle-$VARIANT-$$.app"
trap 'rm -rf "$APP"' EXIT
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Shotz" "$APP/Contents/MacOS/$EXE_NAME"
cp "$PLIST" "$APP/Contents/Info.plist"
if [[ "$VARIANT" == "dev" ]]; then
  # Same Info.plist, development identity. The app reads its variant from the bundle id.
  /usr/libexec/PlistBuddy \
    -c "Set :CFBundleIdentifier $APP_ID" \
    -c "Set :CFBundleName $APP_NAME" \
    -c "Set :CFBundleDisplayName $APP_NAME" \
    "$APP/Contents/Info.plist"
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

SIGN_ARGS=(--force --sign "$IDENTITY" --identifier "$APP_ID" --timestamp=none)
if [[ "$CONFIG" == "release" ]]; then
  SIGN_ARGS+=(--options runtime)
fi
if [[ "$IDENTITY" == "-" ]]; then
  echo "Signing ad-hoc (no Apple Development identity found)"
else
  echo "Signing with identity $IDENTITY"
fi
codesign "${SIGN_ARGS[@]}" "$APP"
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
