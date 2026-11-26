#!/usr/bin/env bash
# Bundles a debug build and launches it, quitting a previous dev instance of
# Shotz first (matched by this repo's bundle path only; no other app is touched).
# Usage: scripts/run.sh [--dev-hotkeys]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Shotz.app"
EXE="$APP/Contents/MacOS/Shotz"

ARGS=()
for arg in "$@"; do
  case "$arg" in
    --dev-hotkeys) ARGS+=(--dev-hotkeys) ;;
    *) echo "usage: $0 [--dev-hotkeys]" >&2; exit 64 ;;
  esac
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
