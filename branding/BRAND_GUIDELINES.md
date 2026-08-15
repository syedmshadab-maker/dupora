# Dupora Brand Guidelines

## Status

This is a **reconstruction** of the approved reference concept (a flattened
presentation-board image), rebuilt as genuine, editable vector artwork. It
preserves the reference's approved identity - the D-shaped mark, the
play-button negative-space cutout, the duplicate/separation fragment
squares, the blue-to-cyan gradient, and the overall silhouette and
proportions - without simply cropping or re-embedding the reference image.
See "How this was built" below for exactly how.

## Logo construction

The symbol is a single, bold, rounded "D" silhouette (no open letter
counter) with one cut: a right-pointing play-button triangle removed as
true negative space, so it reads as transparent/background-colored on any
surface rather than a flat black shape. Three small squares are scattered
above-left of the mark, fading in from transparent to solid as they
approach the D - a "duplicate separating into fragments" motif that
reinforces what the app does without needing words.

```
        ◻
      ◻◻
        ◻     ┌──────╮
              │  D    ╲___
              │  ▶        ╲   <- play-button cut as negative space
              │      ______╱
              └──────╯
```

The symbol must always work **without** the "Dupora" wordmark - it's the
app icon, favicon, and launcher icon on every platform. Never place the
tagline inside the icon.

## Color

| Name | Hex | RGB | Usage |
|---|---|---|---|
| Midnight Navy | `#081020` | `8, 16, 32` | Dark backgrounds, dark-mode surfaces, adaptive-icon background |
| Electric Blue | `#0EA5FF` | `14, 165, 255` | Gradient start (top-left), primary UI accent/seed color |
| Cyan | `#22D3EE` | `34, 211, 238` | Gradient end (bottom-right) |
| Light | `#F8FAFC` | `248, 250, 252` | Light backgrounds, dark-mode text |

The symbol's fill is always a linear gradient from Electric Blue (top-left)
to Cyan (bottom-right) at 135°, except monochrome variants (solid black or
solid white - see below).

## Typography

**Manrope** (SIL Open Font License 1.1), a geometric sans-serif - the first
choice against the approved reference. Bundled as a variable font at
`branding/scripts/fonts/Manrope-Variable.ttf` (license: `OFL.txt` alongside
it); SVG deliverables reference it by name with `Inter`/system-sans
fallbacks for environments where it isn't installed.

- **Wordmark** ("Dupora"): Manrope ExtraBold (800), +1px letter-spacing.
- **Tagline** ("FIND DUPLICATES. RECLAIM SPACE."): Manrope SemiBold (600),
  uppercase, +3-4px letter-spacing, 80% opacity of the surrounding text
  color.

## Clear space & minimum size

Keep clear space around the symbol equal to **20%** of its width on every
side (e.g. a 1024px symbol wants ≥205px of clear space around it) before
any other UI chrome, text, or edge.

Minimum sizes:
- **Symbol alone:** 16×16px (app favicon/taskbar minimum) - verified
  legible at this size; see `branding/png/dupora-symbol-16.png`.
- **Symbol + wordmark:** don't go below ~120px tall; the wordmark stops
  being comfortably legible before the symbol does.

## Light/dark usage

- **On light surfaces:** full-color gradient symbol + Midnight Navy
  wordmark (`branding/png/dupora-logo-light-bg.png`).
- **On dark surfaces:** full-color gradient symbol + Light (`#F8FAFC`)
  wordmark (`branding/png/dupora-logo-dark-bg.png`).
- **On busy photography or unpredictable backgrounds:** use a monochrome
  variant (solid black or solid white symbol) instead of the gradient
  version, so the negative-space play-cut and fragment squares stay
  readable regardless of what's behind them.

## Monochrome

Two single-color variants exist for cases where the gradient can't be
reproduced reliably (embossing, single-color print, some watch/status-bar
contexts):
- `dupora-symbol-mono-black.svg` / `.png` - `#0A0A0C`
- `dupora-symbol-mono-white.svg` / `.png` - `#FFFFFF`

Both keep the play-button negative-space cutout and the fragment squares
(rendered in the same solid color at reduced opacity), preserving the
identity rather than just silhouette-filling the D.

## Icon usage per platform

| Platform | Format | Where |
|---|---|---|
| Windows | Multi-res `.ico` (16/32/48/64/128/256) | `windows/runner/resources/app_icon.ico` |
| Web/favicon | ICO + 6 PNG sizes (16/32/48/180/192/512) | `branding/favicon/` (this app has no `web/` platform target; kept as standalone deliverables) |

Never resize the 1024px master down for small sizes. Below 96px, the
fragment squares are dropped (they become illegible noise) and the
play-button cut is drawn slightly larger/bolder so the silhouette stays
crisp at 16×16 - see "small-size versions" in `render_icons.py`.

## How this was built

No SVG rasterizer (Inkscape, rsvg-convert, ImageMagick, cairosvg) was
available in the build environment, so every asset here was produced with
a from-scratch Python/Pillow + numpy pipeline
(`branding/scripts/render_icons.py`, `render_logo.py`, `render_svgs.py`,
`build_platform_assets.py`) that:

1. Reconstructs the D-shape and play-button cut as literal Bezier-sampled
   polygons (matching the hand-authored SVG path data byte-for-byte in
   intent - both are driven by the same coordinates).
2. Renders every PNG at 8x supersampling, downsampled with Lanczos, for
   clean anti-aliasing without a dedicated vector renderer.
3. Writes real SVG `<path>`/`<mask>`/`<linearGradient>` elements (never an
   embedded raster `<image>` of the reference) plus real SVG `<text>` for
   wordmarks (never outlined-to-path, so it stays genuinely editable).

Re-run the whole pipeline any time the design changes:

```bash
cd branding/scripts
python render_icons.py            # symbol PNGs, all sizes + mono + bg cards
python render_logo.py             # full lockups with wordmark + tagline
python render_svgs.py             # SVG source files
python build_platform_assets.py   # .ico / favicon, integrated into the app
```

## File index

```
branding/
├── master/          Primary approved-reference-quality assets (transparent PNG + SVG)
├── svg/              All SVG variants (symbol, mono, lockups, backgrounds)
├── png/              All PNG variants (symbol sizes, mono, lockups, backgrounds)
├── icons/            (reserved for ad-hoc exports)
├── windows/          dupora.ico (also integrated into windows/runner/resources/)
├── favicon/          favicon.ico + 6 PNG sizes
├── scripts/           the generation pipeline (Python) + bundled Manrope font
└── BRAND_GUIDELINES.md  this file
```
