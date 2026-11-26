# Icon masters

The owner's icon artwork lives here. `scripts/make-icons.sh` copies a master in when you pass it
one, and reuses what is here when you run it with no arguments.

| File | What it is |
|---|---|
| `AppIcon.png` / `.svg` / `.pdf` | App icon master: square; a PNG must be at least 1024×1024. |
| `MenuBarGlyph.png` / `.svg` / `.pdf` | Optional menu-bar glyph: one colour on a transparent background. |

Keep one file per role. To replace one, run the script with the new file, for example:

```bash
scripts/make-icons.sh ~/Desktop/AppIcon.png
scripts/make-icons.sh --glyph ~/Desktop/MenuBarGlyph.svg
```

With no `AppIcon.*` here, the placeholder icon drawn by `Resources/make-app-icon.swift` is used.
Full guide: [docs/ICON.md](../../docs/ICON.md).
