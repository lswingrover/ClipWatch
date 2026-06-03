#!/usr/bin/env python3
"""
make_icon.py — Generate ClipWatch.icns using Pillow (headless-safe).
Replaces AppKit-based make_icon.swift which requires a display session.

Design: deep navy gradient, white clipboard silhouette, blue magnifying
glass accent. Consistent with MacWatch/NetWatch visual language.

Usage: python3 make_icon.py [output_dir]
Output: {output_dir}/AppIcon.icns
"""
import math
import os
import shutil
import subprocess
import sys
import tempfile

try:
    from PIL import Image, ImageDraw
except ImportError:
    subprocess.run(
        [sys.executable, "-m", "pip", "install", "Pillow", "--quiet",
         "--break-system-packages"],
        capture_output=True
    )
    from PIL import Image, ImageDraw

SIZES = [16, 32, 64, 128, 256, 512, 1024]

BG_TOP    = (14,  42, 100)   # deep navy
BG_BOTTOM = (6,   20,  60)   # darker navy
WHITE     = (255, 255, 255)
ACCENT    = (100, 180, 255)  # blue accent for magnifier
NAVY      = (14,  42, 100)


def lerp_color(c1, c2, t):
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))


def draw_rounded_rect(draw, xy, radius, fill):
    """Draw a rounded rectangle (RGBA fill) using Pillow's native method."""
    x0, y0, x1, y1 = xy
    r = min(radius, (x1 - x0) // 2, (y1 - y0) // 2)
    draw.rounded_rectangle([x0, y0, x1, y1], radius=r, fill=fill)


def draw_icon(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # ── Gradient background ──────────────────────────────────────
    for y in range(size):
        t = y / max(size - 1, 1)
        color = lerp_color(BG_TOP, BG_BOTTOM, t)
        draw.line([(0, y), (size - 1, y)], fill=(*color, 255))

    # Apply rounded rect mask
    radius = int(size * 0.22)
    mask = Image.new("L", (size, size), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    img.putalpha(mask)
    draw = ImageDraw.Draw(img)

    # ── Clipboard body ───────────────────────────────────────────
    bw = size * 0.44
    bh = size * 0.52
    bx = (size - bw) / 2
    by = size * 0.17
    br = max(2, int(size * 0.06))

    draw_rounded_rect(
        draw,
        (int(bx), int(by), int(bx + bw), int(by + bh)),
        br,
        (*WHITE, 230)
    )

    # ── Clipboard clip (top centre) ──────────────────────────────
    cw = bw * 0.38
    ch = bh * 0.10
    cx = (size - cw) / 2
    cy = by + bh - ch * 0.5
    cr = max(2, int(size * 0.03))

    draw_rounded_rect(
        draw,
        (int(cx), int(cy), int(cx + cw), int(cy + ch)),
        cr,
        (*NAVY, 255)
    )
    # Inner hole
    hw = cw * 0.55
    hh = ch * 0.55
    hx = cx + (cw - hw) / 2
    hy_pos = cy + (ch - hh) / 2
    draw_rounded_rect(
        draw,
        (int(hx), int(hy_pos), int(hx + hw), int(hy_pos + hh)),
        max(1, cr // 2),
        (*WHITE, 220)
    )

    # ── Lines on clipboard ───────────────────────────────────────
    line_color = (*NAVY, 64)   # translucent navy
    lx = bx + bw * 0.14
    lw_full = bw * 0.72
    lh = max(2, size // 80)
    gap = bh * 0.13
    lstart = by + bh * 0.20

    for i in range(3):
        ly = lstart + i * gap
        lw_i = lw_full * (0.55 if i == 2 else 1.0)
        draw_rounded_rect(
            draw,
            (int(lx), int(ly), int(lx + lw_i), int(ly + lh)),
            int(lh / 2),
            line_color
        )

    # ── Magnifying glass (at sizes ≥ 32) ────────────────────────
    if size >= 32:
        mg_cx = bx + bw * 0.80
        mg_cy = by + bh * 0.22
        mg_r  = size * 0.10
        mg_lw = max(2, size // 42)

        # Circle (draw as ellipse outline)
        draw.ellipse(
            [mg_cx - mg_r, mg_cy - mg_r, mg_cx + mg_r, mg_cy + mg_r],
            outline=(*ACCENT, 255),
            width=mg_lw
        )

        # Handle at ~135°
        angle = math.pi * 0.75
        hx_start = mg_cx + (mg_r + mg_lw * 0.5) * math.cos(angle)
        hy_start = mg_cy - (mg_r + mg_lw * 0.5) * math.sin(angle)
        handle_l = mg_r * 0.75
        hx_end = hx_start + handle_l * math.cos(angle)
        hy_end = hy_start - handle_l * math.sin(angle)

        draw.line(
            [(hx_start, hy_start), (hx_end, hy_end)],
            fill=(*ACCENT, 255),
            width=mg_lw
        )

    return img


def build_iconset(out_dir: str) -> str:
    iconset_path = os.path.join(out_dir, "AppIcon.iconset")
    os.makedirs(iconset_path, exist_ok=True)

    iconset_map = [
        ("icon_16x16.png",      16),
        ("icon_16x16@2x.png",   32),
        ("icon_32x32.png",      32),
        ("icon_32x32@2x.png",   64),
        ("icon_128x128.png",    128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png",    256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png",    512),
        ("icon_512x512@2x.png", 1024),
    ]

    png_cache = {}
    for size in SIZES:
        png_cache[size] = draw_icon(size)

    for filename, sz in iconset_map:
        img = png_cache.get(sz, draw_icon(sz))
        img.save(os.path.join(iconset_path, filename))

    return iconset_path


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "/tmp/clipwatch_icon_build"
    os.makedirs(out_dir, exist_ok=True)

    with tempfile.TemporaryDirectory() as tmpdir:
        iconset = build_iconset(tmpdir)
        icns_out = os.path.join(out_dir, "AppIcon.icns")
        r = subprocess.run(
            ["iconutil", "-c", "icns", iconset, "-o", icns_out],
            capture_output=True, text=True
        )
        if r.returncode != 0:
            print(f"⚠️  iconutil failed: {r.stderr}", file=sys.stderr)
            sys.exit(1)

    print(f"✅  Icon written to {icns_out}")


if __name__ == "__main__":
    main()
