# Icon masters

The owner's icon artwork lives here. `scripts/make-icons.sh` reads this folder; see
[docs/ICON.md](../../docs/ICON.md).

| File | What it is |
|---|---|
| `owner-artwork.webp` | The owner's artwork, untouched. Never edit it. |
| `owner-artwork-clean.png` | The cleaned cut-out the icon is built from ([MATTE.md](MATTE.md) says what was done). |
| `icon.json` | How the artwork sits on the generated tile: scale, offset, gradient strength, contact shadow. |
| `AppIcon.png` / `.svg` / `.pdf` | Optional: a finished tile master. If present, it is used instead of `icon.json`. |
| `MenuBarGlyph.png` / `.svg` / `.pdf` | Optional menu-bar glyph: one colour on a transparent background. |

Rebuild the icons after changing anything here:

```bash
scripts/make-icons.sh
```
