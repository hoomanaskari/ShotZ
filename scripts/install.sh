#!/usr/bin/env bash
# Builds a release bundle and installs it to /Applications/ShotZ.app.
# Manager/owner only, from the main checkout (never from a worktree).
# Production only: it never quits, replaces or unregisters ShotZ Dev
# (build/ShotZ Dev.app, com.pixelforty.shotz.dev), which runs side by side.
#
# - Replaces an installed copy under either spelling (/Applications/Shotz.app
#   from before the rename, or ShotZ.app); afterwards only ShotZ.app remains.
#   On a case-insensitive disk both names are the same folder, so the swap
#   below is what changes the spelling.
# - Quits only the installed copy (matched by its resolved executable path,
#   old or new name; dev builds elsewhere are left alone), politely first
#   (SIGTERM runs ShotZ's clean shutdown), then forcefully after 5 s.
# - Replaces the app atomically: the new bundle is copied next to the old one,
#   verified, then swapped in with renames on the same volume. If anything
#   fails before the swap, the installed app is untouched; if the swap fails,
#   the previous copy is put back.
# - Relaunches ShotZ if it was running.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="/Applications/ShotZ.app"
LEGACY="/Applications/Shotz.app"
EXE_NAMES=("$DEST/Contents/MacOS/ShotZ" "$LEGACY/Contents/MacOS/Shotz" "$DEST/Contents/MacOS/Shotz" "$LEGACY/Contents/MacOS/ShotZ")

if [[ "$(git -C "$ROOT" rev-parse --git-dir 2>/dev/null)" != "$(git -C "$ROOT" rev-parse --git-common-dir 2>/dev/null)" ]]; then
  echo "install.sh runs from the main checkout only, not from a worktree." >&2
  exit 64
fi

"$ROOT/scripts/bundle.sh" release
NEW="$ROOT/build/ShotZ.app"

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
is_installed_exe() {
  local candidate
  candidate="$(lower "$1")"
  for exe in "${EXE_NAMES[@]}"; do
    [[ "$candidate" == "$(lower "$exe")" ]] && return 0
  done
  return 1
}
installed_pids() {
  local pid exe
  for pid in $(pgrep -x 'ShotZ|Shotz' || true); do
    exe="$(lsof -a -p "$pid" -d txt -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)"
    is_installed_exe "$exe" && echo "$pid"
  done
  return 0
}

STAGE="/Applications/.ShotZ.app.installing.$$"
OLD="/Applications/.ShotZ.app.previous.$$"
OLD_LEGACY="/Applications/.Shotz.app.previous.$$"
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
  echo "Quitting installed ShotZ: $PIDS"
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

# Swap. `-e "$DEST"` is true for either spelling on a case-insensitive disk.
# On a case-sensitive disk an old Shotz.app is a separate folder: move it too.
inode() { stat -f %i "$1" 2>/dev/null || echo none; }
MOVED_DEST=0
MOVED_LEGACY=0
if [[ -e "$DEST" ]]; then
  mv "$DEST" "$OLD"
  MOVED_DEST=1
fi
if [[ -e "$LEGACY" ]]; then
  mv "$LEGACY" "$OLD_LEGACY"
  MOVED_LEGACY=1
fi
if ! mv "$STAGE" "$DEST"; then
  echo "Install failed; restoring the previous copy." >&2
  [[ "$MOVED_DEST" == "1" ]] && mv "$OLD" "$DEST"
  [[ "$MOVED_LEGACY" == "1" ]] && mv "$OLD_LEGACY" "$LEGACY"
  exit 1
fi
rm -rf "$OLD" "$OLD_LEGACY"
if [[ "$(inode "$LEGACY")" != "none" && "$(inode "$LEGACY")" != "$(inode "$DEST")" ]]; then
  echo "Warning: $LEGACY still exists next to $DEST." >&2
fi

# The checkout's own build has the same bundle id. Keep it out of Launch
# Services so macOS always opens the installed copy, and warn if a copy from
# the checkout is still running (two instances would both answer hotkeys).
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -u "$NEW" >/dev/null 2>&1 || true
for pid in $(pgrep -x 'ShotZ|Shotz' || true); do
  exe="$(lower "$(lsof -a -p "$pid" -d txt -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)")"
  if [[ "$exe" == "$(lower "$NEW/Contents/MacOS/ShotZ")" || "$exe" == "$(lower "$ROOT/build/Shotz.app/Contents/MacOS/Shotz")" ]]; then
    echo "Note: a ShotZ from this checkout is still running (pid $pid). Quit it: kill $pid" >&2
  fi
done

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DEST/Contents/Info.plist")"
echo "Installed $DEST (version $VERSION)"

if [[ "$WAS_RUNNING" == "1" ]]; then
  open "$DEST"
  echo "Relaunched ShotZ"
fi
