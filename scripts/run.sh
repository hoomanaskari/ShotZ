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
dev_pids() {
  pgrep -f -x "$EXE( .*)?" || true
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

if [[ ${#ARGS[@]} -gt 0 ]]; then
  open -n "$APP" --args "${ARGS[@]}"
else
  open -n "$APP"
fi
echo "Launched $APP ${ARGS[*]:-}"
