# App icon and menu-bar glyph

ShotZ's icons are built from the owner's artwork with one command:

```bash
scripts/make-icons.sh path/to/AppIcon.png
```

The command writes `Resources/AppIcon.icns` (ShotZ) and `Resources/AppIcon-Dev.icns` (ShotZ Dev),
and keeps a copy of the master as `Resources/icon-master/AppIcon.<ext>`. Run it again with no
arguments to rebuild from that kept master.

Until a master is supplied, the placeholder icon drawn by `Resources/make-app-icon.swift` stays.
`scripts/make-icons.sh` with an empty `Resources/icon-master/` redraws it.

## The app icon master

| | |
|---|---|
| Formats | PNG, SVG or PDF (the first page). The format is checked from the file's contents, not only its name. |
| Shape | Square. A PNG must be at least 1024×1024 px; an SVG or PDF can be any square size, since it is drawn as a vector at each size. |
| Artwork | Supply the finished icon: macOS-style art is a rounded tile of about 824×824 on the 1024 canvas, with a transparent margin. The script **never reshapes** the artwork. If the master is fully opaque, has opaque corners or runs to the canvas edge, it says so and uses it as it is. |
| Colour | sRGB. |

Clear errors stop the run for: a missing file, an unsupported format, a file whose contents do not
match its extension, a non-square master, a PNG smaller than 1024 px, or fully transparent artwork.

### What gets built

- `AppIcon.icns` holds every size macOS uses: 16, 32, 128, 256 and 512 pt, each at 1x and 2x
  (16 to 1024 px). PNG masters are downsampled by repeated halving with high-quality
  interpolation, so edges keep no halo. SVG and PDF masters are drawn fresh at each size.
- `AppIcon-Dev.icns` is the same art with an amber band (`#FF9F0A`) across the lower part. The
  band is clipped to the artwork's own transparency, so it follows the tile's shape. "DEV" is
  written on it from 64 px up; smaller sizes get a slightly taller band with no text. ShotZ Dev
  therefore never looks like ShotZ in Finder, the Dock or System Settings.

## The menu-bar glyph (optional)

```bash
scripts/make-icons.sh --glyph path/to/MenuBarGlyph.svg
scripts/make-icons.sh path/to/AppIcon.png --glyph path/to/MenuBarGlyph.svg   # both at once
```

- Input: PNG, SVG or PDF, square, **one colour on a transparent background**. Only the shape (the
  alpha) is used, never the colour. A PNG should be at least 36 px; vectors are best.
- The glyph is trimmed to its visible shape and fitted into a 16 pt square, centred on the 18 pt
  canvas the menu bar uses. It is compiled as a template image (1x and 2x) into
  `Sources/AppShell/StatusItem/MenuBarGlyph.generated.swift`, and the master is kept as
  `Resources/icon-master/MenuBarGlyph.<ext>`.
- ShotZ shows it in the menu bar's own colour (a template image). ShotZ Dev tints it amber in
  code (`StatusItemIcon.devTint`).
- Without a glyph master, the glyph drawn in `StatusItemIcon` stays.

## Trying it without changing anything

```bash
scripts/make-icons.sh path/to/AppIcon.png --glyph path/to/glyph.svg --out /tmp/icon-try
```

`--out` writes `AppIcon.icns`, `AppIcon-Dev.icns` and `MenuBarGlyph.generated.swift` to that
folder only. To inspect every size: `iconutil -c iconset /tmp/icon-try/AppIcon-Dev.icns`.

## Seeing it in the app

The bundle script copies the icons in, so rebuild after running `make-icons.sh`:

```bash
scripts/bundle.sh release   # build/ShotZ.app with AppIcon.icns
scripts/run.sh              # build and run ShotZ Dev with AppIcon-Dev.icns
```

Finder and the Dock cache icons. If an old icon persists, open a fresh build from a new location
or log out and back in.

Commit `Resources/icon-master/*`, both `.icns` files and `MenuBarGlyph.generated.swift` together.
