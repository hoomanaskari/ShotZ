"""Composes the README screenshots from the app's own in-process renders.

Usage: python3 scripts/screenshots/compose.py <raw-folder> <docs/screenshots>
Needs Pillow (pip install pillow). Called by scripts/screenshots/make-screenshots.sh.

The renders come from the app itself (editor script snapshots, the stack
self-test, the Settings snapshot run). They show the window's content and
title bar without the window's rounded corners or shadow, so this adds both
(corner radius and shadow approximate the system's) and places the window on
a neutral backdrop. Nothing inside the window is changed.
"""
import os
import sys

try:
    from PIL import Image, ImageChops, ImageDraw, ImageFilter
except ImportError:
    sys.exit("compose.py needs Pillow: python3 -m pip install pillow")

RAW, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
LIMIT = 400 * 1024


def rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.width - 1, img.height - 1], radius, fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def framed(img, scale, backdrop, pad=48, radius=12, edge=None):
    """The window with rounded corners, a hairline edge and a soft shadow on a plain backdrop."""
    win = rounded(img, radius * scale)
    if edge:
        ImageDraw.Draw(win).rounded_rectangle([0, 0, win.width - 1, win.height - 1], radius * scale, outline=edge, width=scale)
    p = pad * scale
    canvas = Image.new("RGBA", (win.width + 2 * p, win.height + 2 * p), backdrop)
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    alpha = win.split()[3].point(lambda a: int(a * 0.32))
    shadow.paste((0, 0, 0, 255), (p, p + 10 * scale), alpha)
    shadow = shadow.filter(ImageFilter.GaussianBlur(18 * scale))
    canvas = Image.alpha_composite(canvas, shadow)
    canvas.alpha_composite(win, (p, p))
    return canvas


def save(img, name, max_width=None):
    """Saves a PNG under the size limit: full colour if it fits, else 256 colours."""
    if max_width and img.width > max_width:
        img = img.resize((max_width, round(img.height * max_width / img.width)), Image.LANCZOS)
    path = os.path.join(OUT, name)
    rgb = img.convert("RGB")
    rgb.save(path, optimize=True)
    if os.path.getsize(path) > LIMIT:
        rgb.quantize(256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.FLOYDSTEINBERG).save(path, optimize=True)
    size = os.path.getsize(path)
    print(f"{name}: {img.width}×{img.height}, {size // 1024} KB{'  (over 400 KB)' if size > LIMIT else ''}")


def raw(name):
    return Image.open(os.path.join(RAW, name))


LIGHT, DARK = (232, 234, 238, 255), (36, 38, 43, 255)
DARK_EDGE = (255, 255, 255, 40)

# Hero and editor: the annotated capture in light and dark.
save(framed(raw("editor-light@2x.png"), 2, LIGHT), "editor-light.png", 1600)
save(framed(raw("editor-dark@2x.png"), 2, DARK, edge=DARK_EDGE), "editor-dark.png", 1600)

# Background panel and the exported result.
save(framed(raw("background-light@2x.png"), 2, LIGHT), "background-panel.png", 1600)
save(framed(raw("background-dark@2x.png"), 2, DARK, edge=DARK_EDGE), "background-panel-dark.png", 1600)
save(raw("background-export.png"), "background-result.png", 1200)

# Stack: the cards only (the panel render includes empty space above them),
# on the self-test's neutral grey.
for mode in ("light", "dark"):
    img = raw(f"stack-hover-{mode}.png").convert("RGB")
    grey = img.getpixel((2, 2))
    bbox = ImageChops.difference(img, Image.new("RGB", img.size, grey)).getbbox() or (0, 0, img.width, img.height)
    m = 32
    crop = img.crop((max(bbox[0] - m, 0), max(bbox[1] - m, 0), min(bbox[2] + m, img.width), min(bbox[3] + m, img.height)))
    save(crop, f"stack-{mode}.png")

# Settings: General, light and dark.
save(framed(raw("settings-general-light@2x.png"), 2, LIGHT), "settings-general.png", 1000)
save(framed(raw("settings-general-dark@2x.png"), 2, DARK, edge=DARK_EDGE), "settings-general-dark.png", 1000)
