# owner-artwork-clean.png: what was done to the matte

`owner-artwork.webp` is the owner's file, byte for byte (1401×1123, RGBA). `owner-artwork-clean.png`
is the cut-out the icon is built from (same size, 16-bit RGBA, sRGB), made with:

```bash
swift Resources/clean-matte.swift Resources/icon-master/owner-artwork.webp Resources/icon-master/owner-artwork-clean.png
```

## What the original's alpha looked like

| Alpha | Share of pixels | What it was |
|---|---|---|
| 0 | 18.9 % | clean transparency |
| 1–12 | 28.7 % | haze: leftover glow with saturated blue, teal, yellow, red and grey speckle all round the art |
| 13–246 | 1.0 % | antialiased edges; every one within 1 px of a solid shape (164 px at 2–3 px), none further out |
| 247–254 | 51.3 % | the solid artwork, slightly short of opaque (mean 254) |
| 255 | 0.1 % | |

The solid shapes are four clean pieces (the camera with marker and stroke, plus three brackets),
with no stray islands. There is no usable soft-shadow data: the haze is all that is left of it.

## What changed

1. **Alpha remap:** a' = (a − 12/255) / (247/255 − 12/255), clamped to 0…1. The haze floor goes to 0,
   the solid interior becomes fully opaque, and the antialiased ramp keeps its shape.
2. **Cut-off:** nothing more than 3 px from a solid shape (alpha ≥ 50 %) is kept, which removes any
   stray glow above the floor.
3. **Edge decontamination:** semi-transparent edge pixels (15,429 of them) take the colour of the
   adjoining opaque artwork, grown outward one pixel at a time, so no glow colour shows against
   either end of the tile gradient.
4. **Shadow:** none is kept. The generated tile draws one soft, neutral contact shadow under the
   artwork instead (`contactShadow` in `icon.json`).

No opaque pixel's colour changed. Nothing was redrawn, recoloured or reshaped. 453,971 haze pixels
were cleared and 820,900 pixels had their alpha remapped (mostly 253 → 255).

# owner-artwork-2-clean.png

`owner-artwork-2.webp` is the owner's second artwork, byte for byte (1293×1216, RGBA): two tilted
photo cards, a magnifying glass and a yellow marker. Its matte has the same pattern, milder:

| Alpha | What it was |
|---|---|
| 1–12 | haze: about 19,000 pixels of faint white and grey speckle beside the cards, plus a slight fringe |
| 13–247 | antialiased edges, every one within 1 px of the solid shape (a single piece) |
| 248–254 | the solid artwork, slightly short of opaque (mean 254) |

The same tool and thresholds were used:

```bash
swift Resources/clean-matte.swift Resources/icon-master/owner-artwork-2.webp Resources/icon-master/owner-artwork-2-clean.png
```

19,226 haze pixels were cleared, 957,620 pixels had their alpha remapped and 5,872 edge pixels were
decontaminated. No opaque pixel's colour changed, and nothing was redrawn. On a blue tile, the
uncleaned white haze would show as light speckle.
