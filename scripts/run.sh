#!/usr/bin/env bash
# Builds and runs the development app, build/ShotZ Dev.app (app.shotz.Shotz.dev).
# It is a separate app from the installed ShotZ: own name, icon, settings,
# history, login item, default shortcuts (⌃⌥⌘3/4/5) and Screen Recording
# permission. This script never quits, replaces or unregisters the production
# ShotZ; it only quits a previous instance of this same bundle (matched by its
# resolved executable path, under the old or new spelling).
#
# Usage: scripts/run.sh [app arguments...]
# Every argument is passed through to the app. Arguments naming an existing
# file are made absolute first (the app does not run in this directory), e.g.
#   scripts/run.sh --debug-present build/sample.png
#   scripts/run.sh --debug-edit-capture build/sample.png
#
# From a git worktree (an engineer/test checkout) the app is started with
# --no-hotkeys (a hermetic test run: own settings and data, no shortcuts, no
# menu-bar icon), executed directly and kept out of Launch Services, so several
# worktree copies of ShotZ Dev never fight over shortcuts or over which copy
# macOS opens.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/ShotZ Dev.app"
EXE="$APP/Contents/MacOS/ShotZ"
# The same bundle before the ShotZ rename (case-insensitive disk: same folder).
OLD_EXE="$ROOT/build/Shotz Dev.app/Contents/MacOS/Shotz"

ARGS=()
for arg in "$@"; do
  if [[ "$arg" != -* && -e "$arg" ]]; then
    arg="$(cd "$(dirname "$arg")" && pwd)/$(basename "$arg")"
  fi
  ARGS+=("$arg")
done

"$ROOT/scripts/bundle.sh" dev

# Quit a previous instance of this bundle only (paths compared case-insensitively).
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
this_bundle_pids() {
  local pid exe
  for pid in $(pgrep -x 'ShotZ|Shotz' || true); do
    exe="$(lower "$(lsof -a -p "$pid" -d txt -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)")"
    if [[ "$exe" == "$(lower "$EXE")" || "$exe" == "$(lower "$OLD_EXE")" ]]; then echo "$pid"; fi
  done
  return 0
}
PIDS="$(this_bundle_pids)"
if [[ -n "$PIDS" ]]; then
  echo "Quitting previous ShotZ Dev from this checkout: $PIDS"
  kill $PIDS 2>/dev/null || true
  for _ in {1..20}; do
    [[ -z "$(this_bundle_pids)" ]] && break
    sleep 0.1
  done
  PIDS="$(this_bundle_pids)"
  [[ -n "$PIDS" ]] && kill -9 $PIDS 2>/dev/null || true
fi

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
if [[ "$(git -C "$ROOT" rev-parse --git-dir 2>/dev/null)" != "$(git -C "$ROOT" rev-parse --git-common-dir 2>/dev/null)" ]]; then
  [[ " ${ARGS[*]:-} " == *" --no-hotkeys "* ]] || ARGS+=(--no-hotkeys)
  nohup "$EXE" "${ARGS[@]}" >/dev/null 2>&1 &
  disown
  sleep 1
  "$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true
elif [[ ${#ARGS[@]} -gt 0 ]]; then
  open -n "$APP" --args "${ARGS[@]}"
else
  open -n "$APP"
fi
echo "Launched $APP ${ARGS[*]:-}"
