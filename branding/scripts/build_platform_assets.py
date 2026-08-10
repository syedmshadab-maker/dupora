"""
Builds platform-ready icon assets (Windows .ico, Android launcher +
adaptive icon, macOS .iconset, Linux desktop icon, favicon set) from the
already-rendered symbol PNGs (render_icons.py) and writes copies into
branding/{windows,android,macos,favicon,linux}/ for reference, plus writes
directly into the Flutter app's platform directories where a build
actually consumes them from a fixed path.
"""

import os
import shutil

from PIL import Image

from render_icons import MIDNIGHT_NAVY, render_symbol

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
# Android: legacy mipmap launcher icons + adaptive icon (API 26+)
# --------------------------------------------------------------------------
ANDROID_DENSITIES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}
# Adaptive icon canvas is 108dp; density-relative px = 108 * (density scale).
ADAPTIVE_CANVAS = {
    "mdpi": 108,
    "hdpi": 162,
    "xhdpi": 216,
    "xxhdpi": 324,
    "xxxhdpi": 432,
}


def build_android_icons():
    out_dir = os.path.join(BRANDING, "android")
    res_dir = os.path.join(PROJECT_ROOT, "android", "app", "src", "main", "res")

    # Legacy square launcher icon per density.
    for density, size in ANDROID_DENSITIES.items():
        img = render_symbol(size)
        branding_path = os.path.join(out_dir, f"mipmap-{density}", "ic_launcher.png")
        os.makedirs(os.path.dirname(branding_path), exist_ok=True)
        img.save(branding_path)

        target = os.path.join(res_dir, f"mipmap-{density}", "ic_launcher.png")
        os.makedirs(os.path.dirname(target), exist_ok=True)
        img.save(target)
    print("wrote Android legacy mipmap ic_launcher.png (5 densities), integrated into android/app/src/main/res/")

    # Adaptive icon: background (solid Midnight Navy) + foreground (symbol
    # scaled to fit the 66dp safe zone inside the 108dp canvas) per density.
    for density, canvas_size in ADAPTIVE_CANVAS.items():
        bg = Image.new("RGBA", (canvas_size, canvas_size), (*MIDNIGHT_NAVY, 255))
        bg_path_branding = os.path.join(out_dir, f"mipmap-{density}", "ic_launcher_background.png")
        bg.save(bg_path_branding)
        bg_target = os.path.join(res_dir, f"mipmap-{density}", "ic_launcher_background.png")
        bg.save(bg_target)

        safe_zone_fraction = 62 / 108  # a little inside the 66dp max, for breathing room
        symbol_size = int(canvas_size * safe_zone_fraction)
        symbol = render_symbol(symbol_size)
        fg = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
        offset = (canvas_size - symbol_size) // 2
        fg.paste(symbol, (offset, offset), symbol)
        fg_path_branding = os.path.join(out_dir, f"mipmap-{density}", "ic_launcher_foreground.png")
        fg.save(fg_path_branding)
        fg_target = os.path.join(res_dir, f"mipmap-{density}", "ic_launcher_foreground.png")
        fg.save(fg_target)
    print("wrote Android adaptive icon background/foreground (5 densities), integrated")

    # mipmap-anydpi-v26/ic_launcher.xml ties background+foreground together.
    adaptive_xml = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@mipmap/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        "</adaptive-icon>\n"
    )
    anydpi_dir_branding = os.path.join(out_dir, "mipmap-anydpi-v26")
    os.makedirs(anydpi_dir_branding, exist_ok=True)
    with open(os.path.join(anydpi_dir_branding, "ic_launcher.xml"), "w", encoding="utf-8") as f:
        f.write(adaptive_xml)

    anydpi_dir_target = os.path.join(res_dir, "mipmap-anydpi-v26")
    os.makedirs(anydpi_dir_target, exist_ok=True)
    with open(os.path.join(anydpi_dir_target, "ic_launcher.xml"), "w", encoding="utf-8") as f:
        f.write(adaptive_xml)
    print("wrote mipmap-anydpi-v26/ic_launcher.xml, integrated")


# --------------------------------------------------------------------------
# macOS: .iconset folder (run `iconutil -c icns AppIcon.iconset` on a Mac)
# --------------------------------------------------------------------------
MACOS_ICONSET_SIZES = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]


def build_macos_iconset():
    out_dir = os.path.join(BRANDING, "macos", "AppIcon.iconset")
    os.makedirs(out_dir, exist_ok=True)
    for name, size in MACOS_ICONSET_SIZES:
        img = render_symbol(size)
        img.save(os.path.join(out_dir, f"{name}.png"))
    print(f"wrote macOS iconset -> {out_dir} (run `iconutil -c icns AppIcon.iconset` on macOS to produce the .icns)")

    # Also integrate into the Xcode asset catalog's AppIcon.appiconset with
    # a Contents.json, which Xcode can use directly without needing iconutil.
    appiconset = os.path.join(
        PROJECT_ROOT, "macos", "Runner", "Assets.xcassets", "AppIcon.appiconset"
    )
    os.makedirs(appiconset, exist_ok=True)
    contents_images = []
    xcode_map = [
        ("16x16", "1x", 16), ("16x16", "2x", 32),
        ("32x32", "1x", 32), ("32x32", "2x", 64),
        ("128x128", "1x", 128), ("128x128", "2x", 256),
        ("256x256", "1x", 256), ("256x256", "2x", 512),
        ("512x512", "1x", 512), ("512x512", "2x", 1024),
    ]
    for size_label, scale, px in xcode_map:
        filename = f"app_icon_{px}.png"
        render_symbol(px).save(os.path.join(appiconset, filename))
        contents_images.append({
            "size": size_label,
            "idiom": "mac",
            "filename": filename,
            "scale": scale,
        })
    import json
    with open(os.path.join(appiconset, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump({"images": contents_images, "info": {"version": 1, "author": "dupora-branding"}}, f, indent=2)
    print(f"integrated -> {appiconset}")


# --------------------------------------------------------------------------
# Linux: desktop icon (freedesktop hicolor theme convention) + .desktop file
# --------------------------------------------------------------------------
LINUX_SIZES = [16, 32, 48, 64, 128, 256, 512]


def build_linux_icons():
    out_dir = os.path.join(BRANDING, "linux")
    for size in LINUX_SIZES:
        img = render_symbol(size)
        sized_dir = os.path.join(out_dir, "hicolor", f"{size}x{size}", "apps")
        os.makedirs(sized_dir, exist_ok=True)
        img.save(os.path.join(sized_dir, "dupora.png"))
    scalable_dir = os.path.join(out_dir, "hicolor", "scalable", "apps")
    os.makedirs(scalable_dir, exist_ok=True)
    shutil.copyfile(
        os.path.join(BRANDING, "svg", "dupora-symbol.svg"),
        os.path.join(scalable_dir, "dupora.svg"),
    )

    desktop_entry = (
        "[Desktop Entry]\n"
        "Name=Dupora\n"
        "Comment=Find duplicates. Reclaim space.\n"
        "Exec=dupora\n"
        "Icon=dupora\n"
        "Terminal=false\n"
        "Type=Application\n"
        "Categories=Utility;FileTools;\n"
    )
    with open(os.path.join(out_dir, "dupora.desktop"), "w", encoding="utf-8") as f:
        f.write(desktop_entry)
    print(f"wrote Linux hicolor icon theme tree + dupora.desktop -> {out_dir}")


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
    build_android_icons()
    build_macos_iconset()
    build_linux_icons()
    build_favicons()


if __name__ == "__main__":
    main()
