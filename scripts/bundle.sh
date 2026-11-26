#!/usr/bin/env bash
# Builds Shotz and wraps it into build/Shotz.app.
# Usage: scripts/bundle.sh [debug|release]
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
CONFIG="${1:-debug}"
case "$CONFIG" in
  debug|release) ;;
  *) echo "usage: $0 [debug|release]" >&2; exit 64 ;;
esac

PLIST="$ROOT/Resources/Info.plist"
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null || true; }
BUNDLE_ID="$(plist CFBundleIdentifier)"
VERSION="$(plist CFBundleShortVersionString)"
BUILD="$(plist CFBundleVersion)"
if [[ "$BUNDLE_ID" != "app.shotz.Shotz" || -z "$VERSION" || -z "$BUILD" ]]; then
  echo "Resources/Info.plist: need CFBundleIdentifier app.shotz.Shotz, CFBundleShortVersionString and CFBundleVersion" >&2
  exit 65
fi

cd "$ROOT"
swift build -c "$CONFIG" --product Shotz
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="$ROOT/build/Shotz.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Shotz" "$APP/Contents/MacOS/Shotz"
cp "$PLIST" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
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

SIGN_ARGS=(--force --sign "$IDENTITY" --identifier "$BUNDLE_ID" --timestamp=none)
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
echo "Built $APP ($CONFIG, version $VERSION ($BUILD))"
