#!/usr/bin/env bash
# Builds a release bundle and installs it to /Applications/Shotz.app.
# Manager/owner only. Quits a running /Applications/Shotz.app first.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="/Applications/Shotz.app"

"$ROOT/scripts/bundle.sh" release

EXE="$DEST/Contents/MacOS/Shotz"
PIDS="$(pgrep -f -x "$EXE( .*)?" || true)"
if [[ -n "$PIDS" ]]; then
  echo "Quitting installed Shotz: $PIDS"
  kill $PIDS 2>/dev/null || true
  sleep 1
fi

rm -rf "$DEST"
ditto "$ROOT/build/Shotz.app" "$DEST"
echo "Installed $DEST"
