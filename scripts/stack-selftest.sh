#!/usr/bin/env bash
# Runs the quick-access stack's in-process self-test (-QuickAccessSelfTest) with
# 1, 3 and 5 presented captures, using synthetic samples only, and prints a
# summary. Each run quits its own ShotZ Dev instance when done.
#   scripts/stack-selftest.sh [output-dir]
# Pass extra app arguments through SELFTEST_ARGS, e.g.
#   SELFTEST_ARGS="-general.exportFolder /tmp/exports -QuickAccessSelfTestCapture YES" scripts/stack-selftest.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/build/stack-selftest}"
SAMPLES="$OUT/samples"
mkdir -p "$SAMPLES"

# Three README samples (photo 1280×800, notes 840×1120, banner 1800×440) plus two more shapes.
swift "$ROOT/scripts/screenshots/samples.swift" "$SAMPLES" >/dev/null
swift "$ROOT/scripts/make-sample.swift" 5120 2880 "$SAMPLES/wide-5k.png" >/dev/null
swift "$ROOT/scripts/make-sample.swift" 600 600 "$SAMPLES/square.png" >/dev/null

status=0
# run_case <name> <capture>...
run_case() {
  local name="$1"; shift
  local dir="$OUT/$name"
  rm -f "$dir/selftest.txt"
  mkdir -p "$dir"
  # shellcheck disable=SC2086
  "$ROOT/scripts/run.sh" ${SELFTEST_ARGS:-} -QuickAccessSelfTest "$dir" --debug-present "$@" >/dev/null
  local i
  for i in $(seq 1 90); do [[ -f "$dir/selftest.txt" ]] && break; sleep 1; done
  if [[ ! -f "$dir/selftest.txt" ]]; then
    echo "$name: no result after 90 s"; status=1; return
  fi
  local passes fails
  passes=$(grep -c '^PASS' "$dir/selftest.txt" || true)
  fails=$(grep -c '^FAIL' "$dir/selftest.txt" || true)
  echo "$name ($# captures): $passes passed, $fails failed"
  grep '^FAIL' "$dir/selftest.txt" || true
  [[ "$fails" == 0 ]] || status=1
}

run_case one "$SAMPLES/photo.png"
run_case three "$SAMPLES/photo.png" "$SAMPLES/notes.png" "$SAMPLES/banner.png"
run_case five "$SAMPLES/photo.png" "$SAMPLES/notes.png" "$SAMPLES/banner.png" "$SAMPLES/wide-5k.png" "$SAMPLES/square.png"
exit $status
