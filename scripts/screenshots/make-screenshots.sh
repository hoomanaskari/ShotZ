#!/usr/bin/env bash
# Rebuilds the README screenshots in docs/screenshots/ from the real app.
#
#   scripts/screenshots/make-screenshots.sh
#
# Everything is synthetic and in-process: sample captures drawn by samples.swift,
# a hermetic ShotZ Dev test run (--no-hotkeys: own settings and data, no
# shortcuts, no menu-bar icon), the editor driven by its script harness
# (SHOTZ_EDITOR_SCRIPT), the stack by its self-test (-QuickAccessSelfTest) and
# Settings by --debug-snapshot-ui. Nothing reads the screen, sends global input
# or takes focus; windows render themselves to PNG. compose.py (needs Pillow)
# adds window corners and shadow and sizes the files (≤ 400 KB each).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$ROOT/scripts/screenshots"
WORK="$ROOT/build/screenshots"
EXE="$ROOT/build/ShotZ Dev.app/Contents/MacOS/ShotZ"
mkdir -p "$WORK/samples" "$WORK/raw" "$WORK/stack" "$WORK/ui"

"$ROOT/scripts/bundle.sh" dev
swift "$HERE/samples.swift" "$WORK/samples"

# Runs the dev app with the given arguments until it quits (at most $1 seconds).
run_app() {
  local limit=$1; shift
  "$EXE" --no-hotkeys "$@" >/dev/null 2>&1 &
  local pid=$!
  for _ in $(seq 1 "$limit"); do
    sleep 1
    kill -0 "$pid" 2>/dev/null || return 0
  done
  kill "$pid" 2>/dev/null || true
}

# 1. Editor: annotations, light and dark, then the background panel and its export.
sed "s#{{RAW}}#$WORK/raw#g" "$HERE/editor.script" > "$WORK/editor.script"
SHOTZ_EDITOR_SCRIPT="$WORK/editor.script" run_app 20 --debug-edit "$WORK/samples/Sign-ups report.png"

# 2. Stack: three captures, the newest hovered (the self-test quits when done).
run_app 90 --debug-present "$WORK/samples/photo.png" "$WORK/samples/notes.png" "$WORK/samples/banner.png" \
  -QuickAccessSelfTest "$WORK/stack"
cp "$WORK/stack/03-hover-light-"*.png "$WORK/raw/stack-hover-light.png"
cp "$WORK/stack/04-hover-dark-"*.png "$WORK/raw/stack-hover-dark.png"

# 3. Settings ▸ General.
run_app 30 --debug-snapshot-ui "$WORK/ui"
cp "$WORK/ui/settings-general-light@2x.png" "$WORK/ui/settings-general-dark@2x.png" "$WORK/raw/"

python3 "$HERE/compose.py" "$WORK/raw" "$ROOT/docs/screenshots"
