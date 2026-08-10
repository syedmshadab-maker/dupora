"""
Writes the real, editable-vector SVG deliverables (symbol variants + logo
lockups). Shares exact path/coordinate geometry with render_icons.py's
Python reconstruction, so the SVG and the rasterized PNGs are the same
artwork, not two different drawings.

Text is real SVG <text> (not outlined-to-paths, not a rasterized image),
using Manrope with documented system-font fallbacks - see
BRAND_GUIDELINES.md for why (font availability at arbitrary render time
makes baked static bezier outlines brittle to hand-author accurately for a
7-letter wordmark; <text> stays genuinely editable, which is what "real
editable vector paths, not embedded raster" is protecting against here -
the reference composite screenshot never being pasted in as an <image>).
"""

import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # branding/

D_PATH = (
    "M 150,150 Q 150,120 180,120 L 320,120 "
    "C 580,120 780,290 780,510 C 780,730 580,900 320,900 "
    "L 180,900 Q 150,900 150,870 Z"
)
PLAY_TRIANGLE = "M 468,392 L 468,628 L 662,510 Z"

FRAGMENTS = [
    # (x, y, size, rx, rotation-about-center, fill, opacity)
    (20, 88, 44, 8, -10, "#22D3EE", 0.45),
    (82, 146, 54, 9, -7, "#0EA5FF", 0.68),
    (52, 222, 32, 6, -12, "#0EA5FF", 0.9),
]

FONT_STACK = "Manrope, Inter, 'Segoe UI', system-ui, sans-serif"


def fragments_svg(mono_fill=None):
    out = []
    for x, y, size, rx, rot, fill, op in FRAGMENTS:
        cx, cy = x + size / 2, y + size / 2
        actual_fill = mono_fill if mono_fill else fill
        out.append(
            f'    <rect x="{x}" y="{y}" width="{size}" height="{size}" rx="{rx}" '
            f'transform="rotate({rot} {cx} {cy})" fill="{actual_fill}" opacity="{op}"/>'
        )
    return "\n".join(out)


def symbol_defs(gradient=True):
    grad = ""
    if gradient:
        grad = """    <linearGradient id="duporaGradient" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#0EA5FF"/>
      <stop offset="100%" stop-color="#22D3EE"/>
    </linearGradient>
"""
    return f"""  <defs>
{grad}    <mask id="duporaPlayCut" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024">
      <rect x="0" y="0" width="1024" height="1024" fill="#ffffff"/>
      <path d="{PLAY_TRIANGLE}" fill="#000000"/>
    </mask>
  </defs>"""


def symbol_group(fill, gradient):
    mono_fill = None if gradient else fill
    return (
        f'  <g>\n{fragments_svg(mono_fill)}\n  </g>\n'
        f'  <path d="{D_PATH}" fill="{fill}" mask="url(#duporaPlayCut)"/>'
    )


def write(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"wrote {path}")


def symbol_svg(title, fill, gradient):
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <title>{title}</title>
{symbol_defs(gradient)}
{symbol_group(fill, gradient)}
</svg>
"""


def logo_svg(*, title, fill, gradient, text_color, bg=None, with_tagline=False, layout="horizontal"):
    symbol_w = 300
    if layout == "horizontal":
        text_x = symbol_w + 60
        canvas_w = 1180 if not with_tagline else 1250
        canvas_h = 340 if not with_tagline else 400
        symbol_transform = f"translate(20,{(canvas_h - symbol_w) / 2 - (40 if with_tagline else 0)}) scale({symbol_w/1024})"
        word_y = canvas_h / 2 + 30 - (40 if with_tagline else 0)
        tag_y = word_y + 60
    else:  # stacked
        canvas_w = 420
        canvas_h = 460
        symbol_transform = f"translate({(canvas_w - symbol_w)/2},20) scale({symbol_w/1024})"
        text_x = canvas_w / 2
        word_y = symbol_w + 110

    bg_rect = f'  <rect x="0" y="0" width="{canvas_w}" height="{canvas_h}" fill="{bg}"/>\n' if bg else ""
    text_anchor = "start" if layout == "horizontal" else "middle"

    tagline = ""
    if with_tagline:
        tagline = (
            f'  <text x="{text_x}" y="{tag_y}" font-family="{FONT_STACK}" font-weight="600" '
            f'font-size="34" letter-spacing="4" fill="{text_color}" opacity="0.8" '
            f'text-anchor="{text_anchor}">FIND DUPLICATES. RECLAIM SPACE.</text>\n'
        )

    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {canvas_w} {canvas_h}" width="{canvas_w}" height="{canvas_h}">
  <title>{title}</title>
{bg_rect}{symbol_defs(gradient)}
  <g transform="{symbol_transform}">
{symbol_group(fill, gradient)}
  </g>
  <text x="{text_x}" y="{word_y}" font-family="{FONT_STACK}" font-weight="800" font-size="140" \
letter-spacing="1" fill="{text_color}" text-anchor="{text_anchor}">Dupora</text>
{tagline}</svg>
"""


def main():
    svg_dir = os.path.join(ROOT, "svg")
    master_dir = os.path.join(ROOT, "master")

    write(os.path.join(master_dir, "dupora-symbol.svg"), symbol_svg("Dupora Symbol", "url(#duporaGradient)", True))
    write(os.path.join(svg_dir, "dupora-symbol.svg"), symbol_svg("Dupora Symbol", "url(#duporaGradient)", True))
    write(os.path.join(svg_dir, "dupora-symbol-mono-black.svg"), symbol_svg("Dupora Symbol - Black", "#0A0A0C", False))
    write(os.path.join(svg_dir, "dupora-symbol-mono-white.svg"), symbol_svg("Dupora Symbol - White", "#FFFFFF", False))

    write(
        os.path.join(master_dir, "dupora-logo-horizontal.svg"),
        logo_svg(title="Dupora Logo - Horizontal", fill="url(#duporaGradient)", gradient=True,
                 text_color="#081020", layout="horizontal"),
    )
    write(
        os.path.join(svg_dir, "dupora-logo-horizontal.svg"),
        logo_svg(title="Dupora Logo - Horizontal", fill="url(#duporaGradient)", gradient=True,
                 text_color="#081020", layout="horizontal"),
    )
    write(
        os.path.join(master_dir, "dupora-logo-stacked.svg"),
        logo_svg(title="Dupora Logo - Stacked", fill="url(#duporaGradient)", gradient=True,
                 text_color="#081020", layout="stacked"),
    )
    write(
        os.path.join(svg_dir, "dupora-logo-light-bg.svg"),
        logo_svg(title="Dupora Logo - Light Background", fill="url(#duporaGradient)", gradient=True,
                 text_color="#081020", bg="#F8FAFC", with_tagline=True, layout="horizontal"),
    )
    write(
        os.path.join(svg_dir, "dupora-logo-dark-bg.svg"),
        logo_svg(title="Dupora Logo - Dark Background", fill="url(#duporaGradient)", gradient=True,
                 text_color="#F8FAFC", bg="#081020", with_tagline=True, layout="horizontal"),
    )
    write(
        os.path.join(svg_dir, "dupora-logo-mono-black.svg"),
        logo_svg(title="Dupora Logo - Black Monochrome", fill="#0A0A0C", gradient=False,
                 text_color="#0A0A0C", layout="horizontal"),
    )
    write(
        os.path.join(svg_dir, "dupora-logo-mono-white.svg"),
        logo_svg(title="Dupora Logo - White Monochrome", fill="#FFFFFF", gradient=False,
                 text_color="#FFFFFF", layout="horizontal"),
    )


if __name__ == "__main__":
    main()
