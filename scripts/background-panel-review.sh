#!/bin/zsh
# Renders the editor's Background panel and canvas at several slider and position-grid settings,
# light and dark, into build/review/0.1.2-background/ (or the folder given as $1).
#
# Runs inside the test host: a real editor window that is never shown, driven by the editor
# script runner's panel commands (real in-process mouse events through the controls' own
# tracking). Nothing appears on screen, no app is launched or activated, no global input is sent.
set -euo pipefail
cd "${0:A:h}/.."
out="${1:-$PWD/build/review/0.1.2-background}"
rm -rf "$out"
mkdir -p "$out"
SHOTZ_REVIEW_DIR="${out:A}" swift test --filter BackgroundReviewRenders
echo "$(ls "$out" | wc -l | tr -d ' ') renders in $out"
