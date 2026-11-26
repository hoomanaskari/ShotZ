# App icon and menu-bar glyph

ShotZ's icon is the owner's artwork on a generated macOS tile. One command rebuilds both apps' icons:

```bash
scripts/make-icons.sh
```

It reads `Resources/icon-master/` and writes `Resources/AppIcon.icns` (ShotZ) and
`Resources/AppIcon-Dev.icns` (ShotZ Dev). Rebuild the app afterwards to see the result (see
"Seeing it in the app" below).

## Inputs: `Resources/icon-master/`

| File | Role |
|---|---|
| `owner-artwork.webp` | The owner's artwork, untouched (the source of truth). |
| `owner-artwork-clean.png` | The cleaned cut-out the icon is built from. [MATTE.md](../Resources/icon-master/MATTE.md) records exactly what was done. |
| `icon.json` | Where and how the artwork sits on the tile. |
| `AppIcon.{png,svg,pdf}` | Optional finished tile master. When present, it replaces the generated tile. |
| `MenuBarGlyph.{png,svg,pdf}` | Optional menu-bar glyph master. |

The script picks its source in this order:
1. a full tile master, `AppIcon.*`;
2. otherwise, the artwork on the generated tile, from `icon.json`;
3. with neither, the placeholder icon drawn by `Resources/make-app-icon.swift`.

### `icon.json`

```json
{
  "artwork": "owner-artwork-2-clean.png",
  "artworkScale": 0.82,
  "artworkOffset": [0, -0.01],
  "tileGradient": ["#2F6FD6", "#0E2A6B"],
  "contactShadow": 0.18
}
```

This is the owner's second artwork on option B of the blue-tile sheet (mid blue → deep navy). It is
proposed and awaiting the owner's pick; `main` still ships the first artwork on the white tile, whose
settings are kept in `icon-artwork-1.json`. To go back to it, copy that file over `icon.json` and run
`scripts/make-icons.sh`. Every key except `artwork` is optional.

| Key | Meaning |
|---|---|
| `artwork` | Transparent PNG cut-out, relative to `icon.json`. |
| `artworkScale` | Width of the artwork's visible bounds as a fraction of the tile width (0.3–0.95). The script warns when the art comes within 6 % of the tile edge. |
| `artworkOffset` | Extra shift as fractions of the tile, `[x right, y down]`, applied after centring. `-0.01` lifts the art 1 % above the optical centre. |
| `gradientStrength` | 0 is a flat white tile; 1 runs from white to light grey (`#DADDE2`), top left to bottom right. Ignored when `tileGradient` is set. |
| `tileGradient` | Optional coloured tile: two sRGB hex colours, top left → bottom right, e.g. `["#2F6FD6", "#0E2A6B"]`. |
| `contactShadow` | Opacity of the soft neutral shadow under the artwork, drawn on the tile (0–1). |

### The generated tile

- 1024 canvas, macOS grid: an 824×824 tile with the system continuous-corner shape (radius 185.4,
  from SwiftUI's `RoundedRectangle(style: .continuous)`) and the standard 100 px margins.
- The usual soft drop shadow under the tile (10 px down, 20 px blur, 28 % black).
- A linear gradient from the top-left to the bottom-right corner: white → light grey by default,
  or the two `tileGradient` colours.
- A hairline inner edge (2 px at 1024, at least half a pixel at small sizes): 10 % black on a light
  tile, so it reads on a light Dock; 14 % white on a dark tile, so it reads on a dark Dock.
- The artwork is centred on its **visual weight**, not its bounding box: each pixel counts by its
  opacity and its contrast with the light tile (darker and more saturated pixels weigh more).
  For the current artwork that puts the visible bounds 3 % right and 2 % lower than plain box
  centring, before the 1 % lift.
- Each size is rendered fresh (the tile as vectors, the artwork downsampled by repeated halving
  with high-quality interpolation). At 1024 the 1256 px source is downsampled about 2×, so it
  stays sharp.

## Replacing the artwork

1. Put the new file in `Resources/icon-master/`, keeping the original untouched.
2. If its matte needs cleaning, run
   `swift Resources/clean-matte.swift <original> Resources/icon-master/owner-artwork-clean.png`
   and check the result on black, grey and white. The tool only remaps alpha, cuts stray haze and
   decontaminates edge colours; see [MATTE.md](../Resources/icon-master/MATTE.md).
3. Point `artwork` in `icon.json` at the cut-out, then run `scripts/make-icons.sh --preview /tmp/icon`
   to inspect the result at 1024, 128, 64, 32 and 16 px.

## Alternative: a finished tile master

```bash
scripts/make-icons.sh path/to/AppIcon.png
```

| | |
|---|---|
| Formats | PNG, SVG or PDF (the first page). The format is checked from the file's contents. |
| Shape | Square. A PNG must be at least 1024×1024; SVG and PDF are drawn as vectors at each size. |
| Artwork | Used as it is and **never reshaped**. If it is fully opaque, has opaque corners or runs to the edge, the script says so. |

The master is kept as `Resources/icon-master/AppIcon.<ext>` and from then on overrides `icon.json`;
delete it to go back to the generated tile. Errors stop the run for: a missing file, an
unsupported format, contents that don't match the extension, a non-square master, a PNG smaller
than 1024 px, or fully transparent art.

## Both icons

- `AppIcon.icns` holds every size macOS uses: 16, 32, 128, 256 and 512 pt at 1x and 2x (16 to
  1024 px).
- `AppIcon-Dev.icns` is derived automatically: an amber band (`#FF9F0A`) across the lower part of
  the tile, clipped to the tile (or to a full master's own alpha). "DEV" is written on it from
  64 px up; smaller sizes get a slightly taller band with no text. ShotZ Dev therefore never looks
  like ShotZ in Finder, the Dock or System Settings.
- At 16 px the current artwork reads as a framed camera, but the marker is lost. A simplified
  16 px treatment has been proposed to the owner and is not shipped.

## The menu-bar glyph

By default ShotZ draws its menu-bar glyph in code: **corners + lens**, four rounded capture corners
around a lens ring, echoing the capture corners and lens of the app icon (the owner's pick from the
options in `scripts/menubar-glyph-options.swift`). The geometry is in
`Sources/AppShell/StatusItem/MenuBarGlyphGeometry.swift`, on ShotzIcon's 256-unit grid with round
caps and joins, at menu-bar weight (2 px strokes at 1x, 3 px at 2x). Each backing scale gets its own
pixel-snapped bitmap at the 18 pt status-item size; at 1x the lens dot is left out so the ring stays
open. ShotZ uses it as a template image (menu-bar colour); ShotZ Dev draws it in amber
(`StatusItemIcon.devTint`).

### Replacing it with a supplied glyph (optional)

```bash
scripts/make-icons.sh --glyph path/to/MenuBarGlyph.svg
```

- Input: PNG, SVG or PDF, square, **one colour on a transparent background**. Only the shape (the
  alpha) is used; a PNG should be at least 36 px, and vectors are best.
- The glyph is trimmed and fitted into a 16 pt square on the 18 pt menu-bar canvas, then compiled as a
  template image into `Sources/AppShell/StatusItem/MenuBarGlyph.generated.swift`. The master is
  kept as `Resources/icon-master/MenuBarGlyph.<ext>`.
- ShotZ shows it in the menu bar's own colour. ShotZ Dev tints it amber in code
  (`StatusItemIcon.devTint`). A supplied glyph overrides the drawn one; without a glyph master,
  the drawn corners + lens glyph is used.

## Trying it without changing anything

```bash
scripts/make-icons.sh --out /tmp/icon-try --preview /tmp/icon-try
```

`--out` writes the `.icns` files (and the glyph source) to that folder only, and `--preview` adds
PNGs at 1024, 128, 64, 32 and 16 px. To list every size in an icon:
`iconutil -c iconset /tmp/icon-try/AppIcon-Dev.icns`.

## Seeing it in the app

```bash
scripts/bundle.sh release   # build/ShotZ.app with AppIcon.icns
scripts/bundle.sh dev       # build/ShotZ Dev.app with AppIcon-Dev.icns (scripts/run.sh also runs it)
```

Finder and the Dock cache icons. If an old one persists, open a fresh build from a new location or
log out and back in. Commit `Resources/icon-master/*`, both `.icns` files and
`MenuBarGlyph.generated.swift` together.
