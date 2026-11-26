#!/usr/bin/env bash
# Sets ShotZ's version in Resources/Info.plist, the single source of truth that
# bundle.sh copies into ShotZ.app and ShotZ Dev.app.
#
#   scripts/bump-version.sh <marketing> [build]
#
#   <marketing>  CFBundleShortVersionString: two or three numbers, e.g. 1.2.0
#   [build]      CFBundleVersion: a whole number greater than the current one
#                (Sparkle compares builds). Default: the current build + 1.
#
#   scripts/bump-version.sh --print   prints the current "marketing build"
#
# It only edits the plist; commit the change yourself.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST="$ROOT/Resources/Info.plist"
get() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST"; }

CURRENT_MARKETING="$(get CFBundleShortVersionString)"
CURRENT_BUILD="$(get CFBundleVersion)"

if [[ "${1:-}" == "--print" ]]; then
  echo "$CURRENT_MARKETING $CURRENT_BUILD"
  exit 0
fi
if [[ $# -lt 1 || $# -gt 2 || "$1" == -* ]]; then
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 64
fi

MARKETING="$1"
BUILD="${2:-$((CURRENT_BUILD + 1))}"
if ! [[ "$MARKETING" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "bump-version: marketing version must look like 1.2 or 1.2.3 (got '$MARKETING')" >&2
  exit 65
fi
if ! [[ "$BUILD" =~ ^[1-9][0-9]*$ ]]; then
  echo "bump-version: build must be a positive whole number (got '$BUILD')" >&2
  exit 65
fi
if (( BUILD <= CURRENT_BUILD )); then
  echo "bump-version: build $BUILD must be greater than the current build $CURRENT_BUILD" >&2
  exit 65
fi

/usr/libexec/PlistBuddy \
  -c "Set :CFBundleShortVersionString $MARKETING" \
  -c "Set :CFBundleVersion $BUILD" \
  "$PLIST"
echo "ShotZ $CURRENT_MARKETING ($CURRENT_BUILD) → $MARKETING ($BUILD) in Resources/Info.plist"
