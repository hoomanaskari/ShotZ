#!/usr/bin/env bash
# Builds ShotZ's app icons (and optionally the menu-bar glyph) from the owner's artwork.
# Full guide: docs/ICON.md.
#
#   scripts/make-icons.sh [<master>] [--glyph <glyph-master>] [--out <dir>]
#
#   <master>        app icon master: a PNG of at least 1024×1024, or an SVG or PDF, square.
#                   It is copied to Resources/icon-master/AppIcon.<ext>, and
#                   Resources/AppIcon.icns and Resources/AppIcon-Dev.icns are rebuilt from it.
#                   Without <master>, Resources/icon-master/AppIcon.{png,svg,pdf} is used if
#                   present; if there is none (and no --glyph), the placeholder icon is redrawn
#                   with Resources/make-app-icon.swift.
#   --glyph <file>  menu-bar glyph master (PNG, SVG or PDF, one colour on transparent). Copied to
#                   Resources/icon-master/MenuBarGlyph.<ext> and compiled into
#                   Sources/AppShell/StatusItem/MenuBarGlyph.generated.swift. Without it, a glyph
#                   master already in Resources/icon-master/ is used; with none, the drawn glyph stays.
#   --out <dir>     dry run: write AppIcon.icns, AppIcon-Dev.icns and MenuBarGlyph.generated.swift
#                   to <dir> only; nothing in the repository changes.
#
# Then rebuild the app to see it: scripts/bundle.sh release (or scripts/run.sh for ShotZ Dev).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MASTER_DIR="$ROOT/Resources/icon-master"
GLYPH_SWIFT="$ROOT/Sources/AppShell/StatusItem/MenuBarGlyph.generated.swift"

usage() { sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }

MASTER=""; GLYPH=""; OUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --glyph) [[ $# -ge 2 ]] || usage; GLYPH="$2"; shift 2 ;;
    --out) [[ $# -ge 2 ]] || usage; OUT="$2"; shift 2 ;;
    -h|--help) usage ;;
    --*) echo "make-icons: unknown option $1" >&2; usage ;;
    *) [[ -z "$MASTER" ]] || usage; MASTER="$1"; shift ;;
  esac
done

# Absolute paths before anything changes directory.
abspath() { [[ -e "$1" ]] || { echo "make-icons: no such file: $1" >&2; exit 66; }; echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"; }
[[ -n "$MASTER" ]] && MASTER="$(abspath "$MASTER")"
[[ -n "$GLYPH" ]] && GLYPH="$(abspath "$GLYPH")"

find_master() { # find_master <basename>: the first <basename>.{png,svg,pdf} in icon-master/
  local ext
  for ext in png svg pdf; do
    [[ -f "$MASTER_DIR/$1.$ext" ]] && { echo "$MASTER_DIR/$1.$ext"; return; }
  done
  return 0
}
[[ -z "$MASTER" ]] && MASTER="$(find_master AppIcon)"
[[ -z "$GLYPH" ]] && GLYPH="$(find_master MenuBarGlyph)"

if [[ -z "$MASTER" && -z "$GLYPH" ]]; then
  if [[ -n "$OUT" ]]; then echo "make-icons: no master to dry-run with" >&2; exit 66; fi
  echo "make-icons: no master in Resources/icon-master/: redrawing the placeholder icon"
  exec swift "$ROOT/Resources/make-app-icon.swift"
fi

ARGS=()
if [[ -n "$OUT" ]]; then
  mkdir -p "$OUT"
  ARGS+=(--out "$OUT" --glyph-swift "$OUT/MenuBarGlyph.generated.swift")
else
  ARGS+=(--out "$ROOT/Resources" --glyph-swift "$GLYPH_SWIFT")
fi
[[ -n "$MASTER" ]] && ARGS+=(--master "$MASTER")
[[ -n "$GLYPH" ]] && ARGS+=(--glyph "$GLYPH")

swift "$ROOT/Resources/make-icons.swift" "${ARGS[@]}"

[[ -n "$OUT" ]] && exit 0

# Keep the masters next to what was built from them (one file per role).
keep_master() { # keep_master <source> <basename>
  local src="$1" base="$2" ext dest
  ext="$(echo "${src##*.}" | tr '[:upper:]' '[:lower:]')"
  dest="$MASTER_DIR/$base.$ext"
  [[ "$src" == "$dest" ]] && return
  mkdir -p "$MASTER_DIR"
  for old in png svg pdf; do [[ "$old" != "$ext" ]] && rm -f "${MASTER_DIR:?}/$base.$old"; done
  cp "$src" "$dest"
  echo "make-icons: kept master as ${dest#"$ROOT"/}"
}
[[ -n "$MASTER" ]] && keep_master "$MASTER" AppIcon
[[ -n "$GLYPH" ]] && keep_master "$GLYPH" MenuBarGlyph
echo "make-icons: done. Rebuild to see it: scripts/bundle.sh release (ShotZ) or scripts/run.sh (ShotZ Dev)."
