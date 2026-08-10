"""
Renders full logo lockups (symbol + "Dupora" wordmark + tagline) for the
marketing/brand deliverables. App/platform icons use the symbol alone (see
render_icons.py) - per brief, the tagline never goes in an icon.

Font: Manrope, a variable font (SIL Open Font License 1.1, bundled under
branding/scripts/fonts/Manrope-Variable.ttf, license text alongside it) -
the first choice listed against the approved reference, and freely
redistributable. Loaded at its named "ExtraBold"/"SemiBold" instances via
Pillow's variable-font support rather than shipping separate static files.
"""

import os

from PIL import Image, ImageDraw, ImageFont

from render_icons import (
    BLACK,
    CYAN,
    ELECTRIC_BLUE,
    LIGHT,
    MIDNIGHT_NAVY,
    WHITE,
    render_symbol,
)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # branding/
FONT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fonts")
VARIABLE_FONT = os.path.join(FONT_DIR, "Manrope-Variable.ttf")

SCALE = 4  # supersample factor for text/composite crispness


def load_font(size, instance_name):
    font = ImageFont.truetype(VARIABLE_FONT, size)
    try:
        font.set_variation_by_name(instance_name)
    except Exception:
        pass  # falls back to the font's default instance
    return font


def text_with_tracking(draw, xy, text, font, fill, tracking=0):
    """Draws text letter-by-letter with extra tracking (letter-spacing),
    which Pillow's basic text() doesn't support natively. Returns total
    width drawn."""
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=font, fill=fill)
        w = draw.textlength(ch, font=font)
        x += w + tracking
    return x - xy[0] - tracking


def measure_tracked(draw, text, font, tracking=0):
    total = 0
    for ch in text:
        total += draw.textlength(ch, font=font) + tracking
    return total - tracking if text else 0


def make_horizontal_logo(*, symbol_color=None, text_color, bg=None, with_tagline=False, out_path):
    symbol_px = 512 * SCALE
    symbol = render_symbol(512, monochrome=symbol_color)
    symbol = symbol.resize((symbol_px, symbol_px), Image.LANCZOS)

    word_font = load_font(220 * SCALE, "ExtraBold")
    tag_font = load_font(46 * SCALE, "SemiBold")

    tmp = Image.new("RGBA", (10, 10))
    tmp_draw = ImageDraw.Draw(tmp)
    tracking = 2 * SCALE
    word_w = measure_tracked(tmp_draw, "Dupora", word_font, tracking)
    word_ascent, word_descent = word_font.getmetrics()

    tag_tracking = 3 * SCALE
    tag_text = "FIND DUPLICATES. RECLAIM SPACE."
    tag_w = measure_tracked(tmp_draw, tag_text, tag_font, tag_tracking) if with_tagline else 0

    pad = 40 * SCALE
    gap = 36 * SCALE
    text_col_w = max(int(word_w), int(tag_w))
    canvas_w = pad + symbol_px + gap + text_col_w + pad
    canvas_h = symbol_px + pad * 2

    tag_h = 0
    if with_tagline:
        tag_h = int(tag_font.size * 1.6)
        canvas_h += tag_h

    canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    if bg is not None:
        canvas.paste(Image.new("RGBA", canvas.size, (*bg, 255)), (0, 0))

    canvas.paste(symbol, (pad, pad), symbol)

    draw = ImageDraw.Draw(canvas)
    text_x = pad + symbol_px + gap
    text_y = pad + (symbol_px - (word_ascent + word_descent)) // 2 - int(word_descent * 0.15)
    text_with_tracking(draw, (text_x, text_y), "Dupora", word_font, (*text_color, 255), tracking)

    if with_tagline:
        tag_y = pad + symbol_px - tag_h + 10 * SCALE
        tag_color = (*text_color, 200)
        text_with_tracking(
            draw,
            (text_x, tag_y),
            tag_text,
            tag_font,
            tag_color,
            tracking=tag_tracking,
        )

    canvas = canvas.resize((canvas_w // SCALE, canvas_h // SCALE), Image.LANCZOS)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    canvas.save(out_path)
    print(f"wrote {out_path} ({canvas.size[0]}x{canvas.size[1]})")


def make_stacked_logo(*, symbol_color=None, text_color, bg=None, out_path):
    symbol_px = 512 * SCALE
    symbol = render_symbol(512, monochrome=symbol_color)
    symbol = symbol.resize((symbol_px, symbol_px), Image.LANCZOS)

    word_font = load_font(150 * SCALE, "ExtraBold")
    tmp = Image.new("RGBA", (10, 10))
    tmp_draw = ImageDraw.Draw(tmp)
    tracking = 2 * SCALE
    word_w = measure_tracked(tmp_draw, "Dupora", word_font, tracking)
    ascent, descent = word_font.getmetrics()

    pad = 40 * SCALE
    gap = 24 * SCALE
    canvas_w = max(symbol_px, int(word_w)) + pad * 2
    canvas_h = symbol_px + gap + (ascent + descent) + pad * 2

    canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    if bg is not None:
        canvas.paste(Image.new("RGBA", canvas.size, (*bg, 255)), (0, 0))

    symbol_x = (canvas_w - symbol_px) // 2
    canvas.paste(symbol, (symbol_x, pad), symbol)

    draw = ImageDraw.Draw(canvas)
    text_x = (canvas_w - int(word_w)) // 2
    text_y = pad + symbol_px + gap
    text_with_tracking(draw, (text_x, text_y), "Dupora", word_font, (*text_color, 255), tracking)

    canvas = canvas.resize((canvas_w // SCALE, canvas_h // SCALE), Image.LANCZOS)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    canvas.save(out_path)
    print(f"wrote {out_path} ({canvas.size[0]}x{canvas.size[1]})")


def main():
    # Horizontal lockup, transparent, full-color symbol + navy wordmark (for light backgrounds)
    make_horizontal_logo(
        symbol_color=None,
        text_color=MIDNIGHT_NAVY,
        bg=None,
        out_path=os.path.join(ROOT, "master", "dupora-logo-horizontal.png"),
    )

    # Symbol + wordmark stacked, transparent
    make_stacked_logo(
        symbol_color=None,
        text_color=MIDNIGHT_NAVY,
        bg=None,
        out_path=os.path.join(ROOT, "master", "dupora-logo-stacked.png"),
    )

    # Light-background card (with tagline)
    make_horizontal_logo(
        symbol_color=None,
        text_color=MIDNIGHT_NAVY,
        bg=LIGHT,
        with_tagline=True,
        out_path=os.path.join(ROOT, "png", "dupora-logo-light-bg.png"),
    )

    # Dark-background card (with tagline)
    make_horizontal_logo(
        symbol_color=None,
        text_color=WHITE,
        bg=MIDNIGHT_NAVY,
        with_tagline=True,
        out_path=os.path.join(ROOT, "png", "dupora-logo-dark-bg.png"),
    )

    # Black monochrome (transparent bg, for light-surface print/merch use)
    make_horizontal_logo(
        symbol_color=BLACK,
        text_color=BLACK,
        bg=None,
        out_path=os.path.join(ROOT, "png", "dupora-logo-mono-black.png"),
    )

    # White monochrome (transparent bg, for dark-surface print/merch use)
    make_horizontal_logo(
        symbol_color=WHITE,
        text_color=WHITE,
        bg=None,
        out_path=os.path.join(ROOT, "png", "dupora-logo-mono-white.png"),
    )


if __name__ == "__main__":
    main()
