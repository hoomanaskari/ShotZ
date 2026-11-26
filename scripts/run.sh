#!/usr/bin/env bash
# Bundles a debug build and launches it, quitting a previous dev instance of
# Shotz first (matched by this repo's bundle path only; no other app is touched).
# Usage: scripts/run.sh [--dev-hotkeys] [other app arguments...]
# Every argument is passed through to the app. Arguments naming an existing
# file are made absolute first (the app does not run in this directory), e.g.
#   scripts/run.sh --dev-hotkeys --debug-present build/sample.png
#   scripts/run.sh --dev-hotkeys --debug-edit build/sample.png
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Shotz.app"
EXE="$APP/Contents/MacOS/Shotz"

ARGS=()
for arg in "$@"; do
  if [[ "$arg" != -* && -e "$arg" ]]; then
    arg="$(cd "$(dirname "$arg")" && pwd)/$(basename "$arg")"
  fi
  ARGS+=("$arg")
done

"$ROOT/scripts/bundle.sh" debug

# Quit a previous dev instance: only processes whose executable is this bundle's.
# Matched by the resolved executable path of each running Shotz process, so an
# instance started with a relative or symlinked path is found too.
dev_pids() {
  local pid exe
  for pid in $(pgrep -x Shotz || true); do
    exe="$(lsof -a -p "$pid" -d txt -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)"
    [[ "$exe" == "$EXE" ]] && echo "$pid"
  done
  return 0
}
PIDS="$(dev_pids)"
if [[ -n "$PIDS" ]]; then
  echo "Quitting previous dev instance: $PIDS"
  kill $PIDS 2>/dev/null || true
  for _ in {1..20}; do
    [[ -z "$(dev_pids)" ]] && break
    sleep 0.1
  done
  PIDS="$(dev_pids)"
  [[ -n "$PIDS" ]] && kill -9 $PIDS 2>/dev/null || true
fi

# A git worktree is an engineer/test checkout. Several copies with the same
# bundle id confuse Launch Services (macOS may relaunch the wrong copy by
# bundle id), and test runs must not touch the owner's real data. So from a
# worktree: always use the dev profile, start the executable directly, and
# keep the bundle out of the Launch Services database.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
if [[ "$(git -C "$ROOT" rev-parse --git-dir 2>/dev/null)" != "$(git -C "$ROOT" rev-parse --git-common-dir 2>/dev/null)" ]]; then
  [[ " ${ARGS[*]:-} " == *" --dev-profile "* ]] || ARGS+=(--dev-profile)
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
