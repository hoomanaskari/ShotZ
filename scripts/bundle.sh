#!/usr/bin/env bash
# Builds Shotz and wraps it into build/Shotz.app.
# Usage: scripts/bundle.sh [debug|release]
# Signing: $SHOTZ_SIGN_IDENTITY, else the first "Apple Development" identity,
# else ad-hoc. Release builds use the hardened runtime.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-debug}"
case "$CONFIG" in
  debug|release) ;;
  *) echo "usage: $0 [debug|release]" >&2; exit 64 ;;
esac

cd "$ROOT"
swift build -c "$CONFIG" --product Shotz
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="$ROOT/build/Shotz.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Shotz" "$APP/Contents/MacOS/Shotz"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

IDENTITY="${SHOTZ_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  # Use the certificate hash: several identities can share one name.
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk '/"Apple Development/ { print $2; exit }' || true)"
fi
IDENTITY="${IDENTITY:--}"

SIGN_ARGS=(--force --sign "$IDENTITY" --identifier app.shotz.Shotz)
if [[ "$CONFIG" == "release" ]]; then
  SIGN_ARGS+=(--options runtime)
fi
if [[ "$IDENTITY" == "-" ]]; then
  echo "Signing ad-hoc (no Apple Development identity found)"
else
  echo "Signing with identity $IDENTITY"
fi
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP ($CONFIG)"
