"""Turns the generated art into the TGA files the addon ships.

Build-time tool, not part of the shipped addon.

Two jobs:

  1. Convert the ComfyUI renders in tools/out/ into power-of-two 32-bit
     uncompressed TGAs. The renders are gold on black and have no alpha, so the
     alpha channel is derived from the luminance: black becomes transparent and
     the bright gold stays opaque, which preserves the soft falloff of a glow
     far better than keying out a background colour would.

  2. Draw the tab pills directly. Those are crisp rounded shapes; a diffusion
     model cannot hit them reliably at 128x64, and there is nothing to gain by
     trying. (The frame's edge glow needs no file at all - Dialog.lua draws it
     with SetGradient.)

WoW only loads .tga and .blp, always at power-of-two dimensions.

Usage:
    python tools/png2tga.py
"""

import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "out")
TEX_DIR = os.path.join(os.path.dirname(HERE), "Textures")

# Rendered by gen_textures.py. "trim" crops the render down to the art itself, so
# the ornament fills its texture instead of floating in a mostly empty quad;
# "fade" ramps the left and right ends out to nothing, so a divider that the model
# drew running off both edges tapers away instead of ending in a hard cut.
CONVERT = {
    "corner-ornament.png": ("corner-ornament.tga", (256, 256), {"trim": True}),
    "header-flourish.png": ("header-flourish.tga", (512, 128), {"fade": 0.22}),
    "check-ring.png": ("check-ring.tga", (128, 128), {}),
}

# Tab glyphs: cropped square to their own outline so every icon ends up the same
# visual weight, and pushed to flat white so the per-palette tint is predictable.
for _icon in ("icon-check", "icon-group", "icon-talents", "icon-travel",
              "icon-shopping", "icon-options"):
    CONVERT[_icon + ".png"] = (_icon + ".tga", (64, 64),
                               {"trim": True, "square": True, "flatten": True})

GOLD_BRIGHT = (255, 224, 150)
# Corner radius of the tab plates. Small: the mockup's tabs are rectangles with
# the corners just taken off, not pills.
TAB_RADIUS = 4
GOLD_DARK = (120, 86, 28)


def save_tga(image, name):
    """32-bit uncompressed TGA, which is what the client is happiest with."""
    path = os.path.join(TEX_DIR, name)
    os.makedirs(TEX_DIR, exist_ok=True)
    image.convert("RGBA").save(path, format="TGA", compression=None)
    print("  %-22s %s" % (name, "x".join(str(v) for v in image.size)))
    return path


# The model paints a faint vignette rather than a truly black field, and anything
# above zero here becomes a visible rectangular haze around the art. Everything
# below this luminance is forced fully transparent.
BLACK_POINT = 18


def alpha_from_luminance(image):
    """Gold on black -> gold with an alpha channel.

    The RGB is kept as rendered and only pushed back towards full saturation
    where it is faint, so the semi-transparent edge pixels do not turn muddy
    grey once the client blends them over the panel.
    """
    rgb = image.convert("RGB")
    alpha = rgb.convert("L").point(
        lambda v: 0 if v <= BLACK_POINT
        else int(255 * (v - BLACK_POINT) / (255 - BLACK_POINT)))
    pixels = rgb.load()
    mask = alpha.load()
    for y in range(rgb.height):
        for x in range(rgb.width):
            a = mask[x, y]
            if a == 0:
                continue
            r, g, b = pixels[x, y]
            # Renormalise so dim pixels keep their hue instead of going grey.
            scale = 255.0 / max(r, g, b, 1)
            pixels[x, y] = (min(255, int(r * scale)),
                            min(255, int(g * scale)),
                            min(255, int(b * scale)))
    out = rgb.convert("RGBA")
    out.putalpha(alpha)
    return out


def flatten_to_white(image):
    """Drop whatever shading the model added and keep a clean white mask.

    The glyphs get tinted in the client, and a tint multiplies: any grey left in
    the RGB would darken the result unevenly across one icon.
    """
    white = Image.new("RGBA", image.size, (255, 255, 255, 0))
    white.putalpha(image.getchannel("A"))
    return white


def trim_to_content(image, threshold=16, centre=False):
    """Crop away the empty black field, then pad back out to a square.

    The corner ornament is drawn into one corner of a large canvas; without this
    most of the texture would be transparent and the art would shrink to nothing
    once the quad is scaled down to its place on the frame.
    """
    bbox = image.getchannel("A").point(lambda v: 255 if v > threshold else 0).getbbox()
    if not bbox:
        return image
    cropped = image.crop(bbox)
    side = max(cropped.size)
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    if centre:
        square.paste(cropped, ((side - cropped.width) // 2,
                               (side - cropped.height) // 2))
    else:
        square.paste(cropped, (0, 0))  # flush to the top-left, where the corner sits
    return square


def fade_ends(image, fraction):
    """Ramp the alpha out over the outer `fraction` of each end."""
    width, height = image.size
    span = max(1, int(width * fraction))
    ramp = Image.new("L", (width, 1), 255)
    pixels = ramp.load()
    for x in range(span):
        value = int(255 * (x / span) ** 1.5)
        pixels[x, 0] = value
        pixels[width - 1 - x, 0] = value
    alpha = ImageChops.multiply(image.getchannel("A"),
                                ramp.resize((width, height), Image.BILINEAR))
    faded = image.copy()
    faded.putalpha(alpha)
    return faded


def convert_renders():
    missing = []
    for source, (name, size, options) in CONVERT.items():
        path = os.path.join(OUT_DIR, source)
        if not os.path.exists(path):
            missing.append(source)
            continue
        image = alpha_from_luminance(Image.open(path))
        if options.get("flatten"):
            image = flatten_to_white(image)
        if options.get("trim"):
            image = trim_to_content(image, centre=options.get("square", False))
        if options.get("fade"):
            image = fade_ends(image, options["fade"])
        image = image.resize(size, Image.LANCZOS)
        save_tga(image, name)
    if missing:
        print("  missing renders (run tools/gen_textures.py): %s"
              % ", ".join(missing))


def vertical_gradient(size, top, bottom):
    gradient = Image.new("RGB", (1, size[1]))
    pixels = gradient.load()
    for y in range(size[1]):
        t = y / max(1, size[1] - 1)
        pixels[0, y] = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    return gradient.resize(size, Image.BILINEAR)


def pill_mask(size, radius, supersample=4):
    """A rounded-rectangle mask, drawn big and shrunk down for clean edges."""
    big = (size[0] * supersample, size[1] * supersample)
    mask = Image.new("L", big, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, big[0] - 1, big[1] - 1], radius=radius * supersample, fill=255)
    return mask.resize(size, Image.LANCZOS)


def draw_tab(size, fill_top, fill_bottom, edge, glow=None):
    mask = pill_mask(size, radius=TAB_RADIUS)
    tab = vertical_gradient(size, fill_top, fill_bottom).convert("RGBA")

    # The rim is the ring between the full silhouette and an inset copy of it.
    inner = pill_mask((size[0] - 4, size[1] - 4), radius=max(1, TAB_RADIUS - 2))
    inset = Image.new("L", size, 0)
    inset.paste(inner, (2, 2))
    rim = Image.new("RGBA", size, edge + (255,))
    tab.paste(rim, (0, 0), ImageChops.subtract(mask, inset))

    if glow:
        halo = Image.new("RGBA", size, glow + (0,))
        halo.putalpha(inset.point(lambda v: int(v * 0.22))
                      .filter(ImageFilter.GaussianBlur(4)))
        tab = Image.alpha_composite(tab, halo)

    tab.putalpha(mask)
    return tab


def draw_primitives():
    # Selected tab: warm gold, lit from the top, with a soft inner glow.
    save_tga(draw_tab((128, 64), (188, 142, 56), (96, 66, 20), GOLD_BRIGHT,
                      glow=GOLD_BRIGHT), "tab-active.tga")

    # Unselected tab: the same silhouette, nearly black, with a dim gold rim.
    save_tga(draw_tab((128, 64), (34, 30, 26), (18, 16, 14), GOLD_DARK),
             "tab-inactive.tga")



def main():
    print("Textures ->", TEX_DIR)
    convert_renders()
    draw_primitives()


if __name__ == "__main__":
    main()
