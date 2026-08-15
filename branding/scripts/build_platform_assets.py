"""
Builds platform-ready icon assets (Windows .ico, favicon set) from the
already-rendered symbol PNGs (render_icons.py) and writes copies into
branding/{windows,favicon}/ for reference, plus writes directly into the
Flutter app's windows/ directory where a build actually consumes it from
a fixed path.
"""

import os
import shutil

from PIL import Image

from render_icons import render_symbol

BRANDING = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT_ROOT = os.path.dirname(BRANDING)
PNG_DIR = os.path.join(BRANDING, "png")


def png(size):
    return Image.open(os.path.join(PNG_DIR, f"dupora-symbol-{size}.png"))


# --------------------------------------------------------------------------
# Windows: multi-resolution .ico
# --------------------------------------------------------------------------
def build_windows_ico():
    out_dir = os.path.join(BRANDING, "windows")
    os.makedirs(out_dir, exist_ok=True)
    ico_path = os.path.join(out_dir, "dupora.ico")

    base = png(256).convert("RGBA")
    sizes = [16, 32, 48, 64, 128, 256]
    append_images = [png(s).convert("RGBA") for s in sizes if s != 256]
    base.save(
        ico_path,
        format="ICO",
        sizes=[(s, s) for s in sizes],
        append_images=append_images,
    )
    print(f"wrote {ico_path}")

    # Integrate: this is the exact path windows/runner/Runner.rc references.
    target = os.path.join(PROJECT_ROOT, "windows", "runner", "resources", "app_icon.ico")
    shutil.copyfile(ico_path, target)
    print(f"integrated -> {target}")


# --------------------------------------------------------------------------
# Favicon set (standalone deliverable; this Flutter app has no web/ target)
# --------------------------------------------------------------------------
FAVICON_SIZES = [16, 32, 48, 180, 192, 512]


def build_favicons():
    out_dir = os.path.join(BRANDING, "favicon")
    os.makedirs(out_dir, exist_ok=True)
    for size in FAVICON_SIZES:
        render_symbol(size).save(os.path.join(out_dir, f"favicon-{size}.png"))

    ico_sizes = [16, 32, 48]
    base = png(48).convert("RGBA")
    append = [png(s).convert("RGBA") for s in ico_sizes if s != 48]
    base.save(
        os.path.join(out_dir, "favicon.ico"),
        format="ICO",
        sizes=[(s, s) for s in ico_sizes],
        append_images=append,
    )
    print(f"wrote favicon set -> {out_dir}")


def main():
    build_windows_ico()
    build_favicons()


if __name__ == "__main__":
    main()
