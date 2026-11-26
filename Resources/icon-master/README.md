# Icon masters

The owner's icon artwork lives here. `scripts/make-icons.sh` reads this folder; see
[docs/ICON.md](../../docs/ICON.md).

| File | What it is |
|---|---|
| `owner-artwork.webp` | The owner's artwork, untouched. Never edit it. |
| `owner-artwork-clean.png` | Its cleaned cut-out ([MATTE.md](MATTE.md) says what was done); the icon shipped in 0.1.0 and 0.1.1. |
| `owner-artwork-2.webp` | The owner's second artwork, untouched. Never edit it. |
| `owner-artwork-2-clean.png` | Its cleaned cut-out (same clean-up, see [MATTE.md](MATTE.md)). |
| `icon.json` | How the artwork sits on the generated tile: scale, offset, tile gradient, contact shadow. Now: artwork 2 on the blue tile (the owner's choice, option B, from 0.1.1). |
| `icon-artwork-1.json` | The settings for the first artwork on the white tile; copy over `icon.json` to go back. |
| `AppIcon.png` / `.svg` / `.pdf` | Optional: a finished tile master. If present, it is used instead of `icon.json`. |
| `MenuBarGlyph.png` / `.svg` / `.pdf` | Optional menu-bar glyph: one colour on a transparent background. |

Rebuild the icons after changing anything here:

```bash
scripts/make-icons.sh
```

## Provenance

Both versions of the icon artwork (`owner-artwork.webp`, the camera in capture corners used in
0.1.0, and `owner-artwork-2.webp`, the photo cards with a magnifier and marker used from 0.1.1)
were supplied by the owner. ShotZ's own files here are derived from them: the cleaned cut-outs
(see [MATTE.md](MATTE.md)) and the generated tiles.

**Origin and licence: to be confirmed by the owner.**
