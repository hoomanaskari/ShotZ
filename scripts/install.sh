#!/usr/bin/env bash
# Builds a release bundle and installs it to /Applications/Shotz.app.
# Manager/owner only, from the main checkout (never from a worktree).
#
# - Quits only the installed copy (matched by its resolved executable path;
#   dev builds elsewhere are left alone), politely first (SIGTERM runs Shotz's
#   clean shutdown), then forcefully after 5 s.
# - Replaces the app atomically: the new bundle is copied next to the old one,
#   verified, then swapped in with two renames on the same volume. If anything
#   fails before the swap, the installed app is untouched.
# - Relaunches Shotz if it was running.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="/Applications/Shotz.app"
EXE="$DEST/Contents/MacOS/Shotz"

if [[ "$(git -C "$ROOT" rev-parse --git-dir 2>/dev/null)" != "$(git -C "$ROOT" rev-parse --git-common-dir 2>/dev/null)" ]]; then
  echo "install.sh runs from the main checkout only, not from a worktree." >&2
  exit 64
fi

"$ROOT/scripts/bundle.sh" release
NEW="$ROOT/build/Shotz.app"

installed_pids() {
  local pid exe
  for pid in $(pgrep -x Shotz || true); do
    exe="$(lsof -a -p "$pid" -d txt -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)"
    [[ "$exe" == "$EXE" ]] && echo "$pid"
  done
  return 0
}

STAGE="/Applications/.Shotz.app.installing.$$"
OLD="/Applications/.Shotz.app.previous.$$"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

# Stage and verify before touching the installed copy.
rm -rf "$STAGE"
ditto "$NEW" "$STAGE"
codesign --verify --strict --deep "$STAGE"

WAS_RUNNING=0
PIDS="$(installed_pids)"
if [[ -n "$PIDS" ]]; then
  WAS_RUNNING=1
  echo "Quitting installed Shotz: $PIDS"
  kill $PIDS 2>/dev/null || true
  for _ in {1..50}; do
    [[ -z "$(installed_pids)" ]] && break
    sleep 0.1
  done
  PIDS="$(installed_pids)"
  if [[ -n "$PIDS" ]]; then
    echo "Forcing quit: $PIDS"
    kill -9 $PIDS 2>/dev/null || true
  fi
fi

# Swap: old aside, new in place, then drop the old copy.
if [[ -e "$DEST" ]]; then
  mv "$DEST" "$OLD"
fi
if ! mv "$STAGE" "$DEST"; then
  echo "Install failed; restoring the previous copy." >&2
  [[ -e "$OLD" ]] && mv "$OLD" "$DEST"
  exit 1
fi
rm -rf "$OLD"

# The checkout's own build has the same bundle id. Keep it out of Launch
# Services so macOS always opens the installed copy, and warn if a copy from
# the checkout is still running (two instances would both answer hotkeys).
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -u "$NEW" >/dev/null 2>&1 || true
for pid in $(pgrep -x Shotz || true); do
  exe="$(lsof -a -p "$pid" -d txt -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)"
  if [[ "$exe" == "$NEW/Contents/MacOS/Shotz" ]]; then
    echo "Note: a Shotz from this checkout is still running (pid $pid). Quit it: kill $pid" >&2
  fi
done

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DEST/Contents/Info.plist")"
echo "Installed $DEST (version $VERSION)"

if [[ "$WAS_RUNNING" == "1" ]]; then
  open "$DEST"
  echo "Relaunched Shotz"
fi
