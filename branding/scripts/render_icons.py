"""
Renders the Dupora symbol mark to PNG at every size the brand/platform
asset list requires, from the same vector geometry as
branding/svg/dupora-symbol.svg (kept in sync by hand - see that file's
path/coordinates).

Why Pillow instead of an SVG rasterizer: no SVG rendering tool (Inkscape,
rsvg-convert, ImageMagick, cairosvg) was available in this build
environment. Rather than add a new dependency, this script reconstructs the
same geometry directly and rasterizes it, which also satisfies the brief's
"do not simply resize the 1024px artwork - create optimized small-size
versions" requirement: sizes below 96px drop the fragment squares (they
become illegible noise at that scale) and use a slightly heavier silhouette
so the D + play-cut stays readable at 16x16.

Every size is supersampled at 8x and downsampled with LANCZOS for clean
anti-aliasing, matching how the SVG would rasterize.
"""

import math
import os

import numpy as np
from PIL import Image, ImageDraw

ELECTRIC_BLUE = (14, 165, 255)
CYAN = (34, 211, 238)
MIDNIGHT_NAVY = (8, 16, 32)
LIGHT = (248, 250, 252)
BLACK = (10, 10, 12)
WHITE = (255, 255, 255)

CANVAS = 1024
SUPERSAMPLE = 8
SS_CANVAS = CANVAS * SUPERSAMPLE


def cubic_bezier_points(p0, p1, p2, p3, n=64):
    pts = []
    for i in range(n + 1):
        t = i / n
        mt = 1 - t
        x = (mt**3) * p0[0] + 3 * (mt**2) * t * p1[0] + 3 * mt * (t**2) * p2[0] + (t**3) * p3[0]
        y = (mt**3) * p0[1] + 3 * (mt**2) * t * p1[1] + 3 * mt * (t**2) * p2[1] + (t**3) * p3[1]
        pts.append((x, y))
    return pts


def quad_bezier_points(p0, p1, p2, n=24):
    pts = []
    for i in range(n + 1):
        t = i / n
        mt = 1 - t
        x = (mt**2) * p0[0] + 2 * mt * t * p1[0] + (t**2) * p2[0]
        y = (mt**2) * p0[1] + 2 * mt * t * p1[1] + (t**2) * p2[1]
        pts.append((x, y))
    return pts


def d_shape_polygon(scale=1.0):
    """Mirrors the path in branding/svg/dupora-symbol.svg."""
    pts = []
    pts += quad_bezier_points((150, 150), (150, 120), (180, 120))
    pts.append((320, 120))
    pts += cubic_bezier_points((320, 120), (580, 120), (780, 290), (780, 510))
    pts += cubic_bezier_points((780, 510), (780, 730), (580, 900), (320, 900))
    pts.append((180, 900))
    pts += quad_bezier_points((180, 900), (150, 900), (150, 870))
    return [(x * scale, y * scale) for x, y in pts]


def play_triangle(scale=1.0, bold=False):
    if bold:
        # A slightly larger, simpler cut for small sizes so it stays a
        # crisp readable notch instead of vanishing into a grey blur.
        pts = [(452, 380), (452, 640), (676, 510)]
    else:
        pts = [(468, 392), (468, 628), (662, 510)]
    return [(x * scale, y * scale) for x, y in pts]


def rotated_rect(cx, cy, size, angle_deg):
    a = math.radians(angle_deg)
    hs = size / 2
    corners = [(-hs, -hs), (hs, -hs), (hs, hs), (-hs, hs)]
    out = []
    for x, y in corners:
        rx = x * math.cos(a) - y * math.sin(a)
        ry = x * math.sin(a) + y * math.cos(a)
        out.append((cx + rx, cy + ry))
    return out


def make_gradient(size, color_a, color_b):
    """Diagonal top-left -> bottom-right linear gradient, RGBA."""
    t = np.linspace(0, 1, size)
    grad_1d = np.add.outer(t, t) / 2.0  # diagonal blend factor per pixel
    grad_1d = np.clip(grad_1d, 0, 1)
    r = (color_a[0] + (color_b[0] - color_a[0]) * grad_1d).astype(np.uint8)
    g = (color_a[1] + (color_b[1] - color_a[1]) * grad_1d).astype(np.uint8)
    b = (color_a[2] + (color_b[2] - color_a[2]) * grad_1d).astype(np.uint8)
    a = np.full_like(r, 255)
    arr = np.dstack([r, g, b, a])
    return Image.fromarray(arr, mode="RGBA")


def render_symbol(px, *, monochrome=None, include_fragments=None, bg=None):
    """
    px: output size in pixels (square).
    monochrome: None for full gradient, or an (r,g,b) solid fill color.
    include_fragments: defaults to True for px >= 96, else False.
    bg: optional (r,g,b) solid background (for light/dark-card exports);
        None keeps the canvas transparent.
    """
    if include_fragments is None:
        include_fragments = px >= 96
    bold_cut = px < 96

    ss = px * SUPERSAMPLE
    scale = ss / CANVAS

    canvas = Image.new("RGBA", (ss, ss), (0, 0, 0, 0))
    if bg is not None:
        canvas.paste(Image.new("RGBA", (ss, ss), (*bg, 255)), (0, 0))

    # --- fragments (drawn first, behind the mark) ---
    if include_fragments:
        frag_layer = Image.new("RGBA", (ss, ss), (0, 0, 0, 0))
        fd = ImageDraw.Draw(frag_layer)
        fragments = [
            (42, 110, 44, -10, CYAN, 0.45),
            (109, 173, 54, -7, ELECTRIC_BLUE, 0.68),
            (68, 238, 32, -12, ELECTRIC_BLUE, 0.9),
        ]
        for cx, cy, size, angle, color, opacity in fragments:
            poly = rotated_rect(cx * scale, cy * scale, size * scale, angle)
            fd.polygon(poly, fill=(*color, int(255 * opacity)))
        canvas = Image.alpha_composite(canvas, frag_layer)

    # --- D shape mask ---
    shape_mask = Image.new("L", (ss, ss), 0)
    smd = ImageDraw.Draw(shape_mask)
    smd.polygon(d_shape_polygon(scale), fill=255)
    # cut the play-button negative space
    smd.polygon(play_triangle(scale, bold=bold_cut), fill=0)

    # --- fill (gradient or solid) ---
    if monochrome is not None:
        fill_layer = Image.new("RGBA", (ss, ss), (*monochrome, 255))
    else:
        fill_layer = make_gradient(ss, ELECTRIC_BLUE, CYAN)

    shape_rgba = Image.new("RGBA", (ss, ss), (0, 0, 0, 0))
    shape_rgba.paste(fill_layer, (0, 0), shape_mask)

    canvas = Image.alpha_composite(canvas, shape_rgba)
    return canvas.resize((px, px), Image.LANCZOS)


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print(f"wrote {path} ({img.size[0]}x{img.size[1]})")


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # branding/

    sizes = [16, 32, 48, 64, 128, 180, 192, 256, 512, 1024]
    for s in sizes:
        img = render_symbol(s)
        save(img, os.path.join(root, "png", f"dupora-symbol-{s}.png"))

    # Monochrome masters (1024, transparent)
    save(render_symbol(1024, monochrome=BLACK), os.path.join(root, "png", "dupora-symbol-black.png"))
    save(render_symbol(1024, monochrome=WHITE), os.path.join(root, "png", "dupora-symbol-white.png"))

    # Light/dark background cards (1024)
    save(render_symbol(1024, bg=LIGHT), os.path.join(root, "png", "dupora-symbol-on-light.png"))
    save(render_symbol(1024, bg=MIDNIGHT_NAVY), os.path.join(root, "png", "dupora-symbol-on-dark.png"))

    # Master transparent PNG
    save(render_symbol(1024), os.path.join(root, "master", "dupora-symbol-master-1024.png"))


if __name__ == "__main__":
    main()
