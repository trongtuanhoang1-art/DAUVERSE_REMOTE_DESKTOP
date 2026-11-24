#!/usr/bin/env python3
"""
Pure-Python zero-dependency generator for DAUVERSE REMOTE DESKTOP V1 branding:
- Vector SVGs (res/dauverse-logo.svg, dauverse-tray.svg, dauverse-banner.svg)
- Anti-aliased 32-bit RGBA PNGs (512, 256, 128, 64, 32, 16)
- Multi-resolution Windows ICO files (res/icon.ico, flutter/windows/.../app_icon.ico, res/tray-icon.ico)
Works identically on Linux, Windows, and macOS without external binary delegates.
"""

import math
import struct
import zlib
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

APP_SVG = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">
  <defs>
    <linearGradient id="bgGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#070B14"/>
      <stop offset="55%" stop-color="#0F172A"/>
      <stop offset="100%" stop-color="#1E1B4B"/>
    </linearGradient>
    <linearGradient id="brandGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#06B6D4"/>
      <stop offset="50%" stop-color="#3B82F6"/>
      <stop offset="100%" stop-color="#8B5CF6"/>
    </linearGradient>
  </defs>
  <rect x="20" y="20" width="472" height="472" rx="108" fill="url(#bgGrad)" stroke="url(#brandGrad)" stroke-width="14"/>
  <path d="M148 132 H262 C338 132 388 182 388 256 C388 330 338 380 262 380 H148 Z"
        fill="none" stroke="url(#brandGrad)" stroke-width="38" stroke-linejoin="round"/>
  <path d="M206 204 L306 256 L246 274 L228 334 Z" fill="#22D3EE"/>
  <circle cx="332" cy="176" r="16" fill="#38BDF8"/>
</svg>
"""

TRAY_SVG = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128" width="128" height="128">
  <rect x="6" y="6" width="116" height="116" rx="28" fill="#0B1120" stroke="#06B6D4" stroke-width="8"/>
  <path d="M34 30 H64 C86 30 100 44 100 64 C100 84 86 98 64 98 H34 Z"
        fill="none" stroke="#3B82F6" stroke-width="14" stroke-linejoin="round"/>
  <circle cx="62" cy="64" r="12" fill="#22D3EE"/>
</svg>
"""

HEADER_LOGO_SVG = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 640 140" width="640" height="140">
  <rect x="10" y="14" width="112" height="112" rx="26" fill="#0B1120" stroke="#06B6D4" stroke-width="6"/>
  <path d="M38 38 H66 C86 38 98 50 98 70 C98 90 86 102 66 102 H38 Z"
        fill="none" stroke="#3B82F6" stroke-width="11" stroke-linejoin="round"/>
  <path d="M54 56 L80 70 L64 75 L59 91 Z" fill="#22D3EE"/>
  <text x="144" y="68" fill="#F8FAFC" font-family="sans-serif" font-weight="800" font-size="38" letter-spacing="1.5">DAUVERSE</text>
  <text x="146" y="106" fill="#38BDF8" font-family="sans-serif" font-weight="600" font-size="22" letter-spacing="4">REMOTE DESKTOP V1</text>
</svg>
"""


def encode_png(width: int, height: int, rgba_bytes: bytes) -> bytes:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    raw_rows = bytearray()
    stride = width * 4
    for y in range(height):
        raw_rows.append(0)
        raw_rows.extend(rgba_bytes[y * stride : (y + 1) * stride])

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    idat = zlib.compress(bytes(raw_rows), 9)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")


def encode_ico(png_entries: list[tuple[int, bytes]]) -> bytes:
    count = len(png_entries)
    header = struct.pack("<HHH", 0, 1, count)
    dir_entries = bytearray()
    payload = bytearray()
    offset = 6 + count * 16
    for size, png_data in png_entries:
        dim_byte = 0 if size >= 256 else size
        dir_entries.extend(
            struct.pack(
                "<BBBBHHII",
                dim_byte,
                dim_byte,
                0,
                0,
                1,
                32,
                len(png_data),
                offset,
            )
        )
        payload.extend(png_data)
        offset += len(png_data)
    return header + bytes(dir_entries) + bytes(payload)


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def brand_gradient(t: float) -> tuple[int, int, int]:
    t = max(0.0, min(1.0, t))
    if t < 0.5:
        u = t * 2.0
        return (
            int(lerp(6, 59, u)),
            int(lerp(182, 130, u)),
            int(lerp(212, 246, u)),
        )
    u = (t - 0.5) * 2.0
    return (
        int(lerp(59, 139, u)),
        int(lerp(130, 92, u)),
        int(lerp(246, 246, u)),
    )


def sd_rounded_box(px: float, py: float, bx: float, by: float, r: float) -> float:
    qx = abs(px) - bx + r
    qy = abs(py) - by + r
    return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - r


def sd_d_monogram(nx: float, ny: float) -> float:
    # Normalized space [-1, 1]: crisp D-portal ring
    # Left vertical spine from x=-0.42, y in [-0.48, 0.48] plus right semicircle centered at (-0.08, 0) radius 0.48
    if nx < -0.08:
        dx = max(abs(nx - (-0.25)) - 0.17, 0.0)
        dy = max(abs(ny) - 0.48, 0.0)
        outer = math.hypot(dx, dy) + min(max(abs(nx - (-0.25)) - 0.17, abs(ny) - 0.48), 0.0)
        idx = max(abs(nx - (-0.16)) - 0.10, 0.0)
        idy = max(abs(ny) - 0.30, 0.0)
        inner = math.hypot(idx, idy) + min(max(abs(nx - (-0.16)) - 0.10, abs(ny) - 0.30), 0.0)
        return max(outer, -inner)
    dist_c = math.hypot(nx - (-0.08), ny)
    return abs(dist_c - 0.39) - 0.09


def render_icon_rgba(size: int, tray_mode: bool = False) -> bytes:
    buf = bytearray(size * size * 4)
    aa = 2.0 / size
    for y in range(size):
        ny = (y + 0.5) / size * 2.0 - 1.0
        for x in range(size):
            nx = (x + 0.5) / size * 2.0 - 1.0
            t = ((nx + 1.0) * 0.5 * 0.6) + ((ny + 1.0) * 0.5 * 0.4)

            d_card = sd_rounded_box(nx, ny, 0.90, 0.90, 0.40)
            if d_card > aa:
                continue

            alpha = max(0.0, min(1.0, (aa - d_card) / (2.0 * aa) + 0.5))
            # Obsidian background
            bg_r = int(lerp(8, 22, t))
            bg_g = int(lerp(12, 27, t))
            bg_b = int(lerp(24, 58, t))

            r, g, b = bg_r, bg_g, bg_b

            # Outer border glow
            border_d = abs(d_card + 0.045) - (0.045 if tray_mode else 0.032)
            if border_d < aa:
                w = max(0.0, min(1.0, (aa - border_d) / (2.0 * aa) + 0.5))
                gr, gg, gb = brand_gradient(t)
                r = int(lerp(r, gr, w))
                g = int(lerp(g, gg, w))
                b = int(lerp(b, gb, w))

            # D monogram
            d_mono = sd_d_monogram(nx, ny)
            if d_mono < aa:
                w = max(0.0, min(1.0, (aa - d_mono) / (2.0 * aa) + 0.5))
                gr, gg, gb = brand_gradient(1.0 - t * 0.6)
                r = int(lerp(r, gr, w))
                g = int(lerp(g, gg, w))
                b = int(lerp(b, gb, w))

            # Inner AI pulse core dot
            dot_d = math.hypot(nx - (-0.03), ny) - (0.14 if tray_mode else 0.11)
            if dot_d < aa:
                w = max(0.0, min(1.0, (aa - dot_d) / (2.0 * aa) + 0.5))
                r = int(lerp(r, 34, w))
                g = int(lerp(g, 211, w))
                b = int(lerp(b, 238, w))

            idx = (y * size + x) * 4
            buf[idx] = r
            buf[idx + 1] = g
            buf[idx + 2] = b
            buf[idx + 3] = int(alpha * 255)
    return bytes(buf)


def downsample_2x(hi_size: int, hi_rgba: bytes) -> bytes:
    lo = hi_size // 2
    out = bytearray(lo * lo * 4)
    for y in range(lo):
        for x in range(lo):
            r = g = b = a = 0
            for dy in (0, 1):
                for dx in (0, 1):
                    si = ((y * 2 + dy) * hi_size + (x * 2 + dx)) * 4
                    r += hi_rgba[si]
                    g += hi_rgba[si + 1]
                    b += hi_rgba[si + 2]
                    a += hi_rgba[si + 3]
            di = (y * lo + x) * 4
            out[di] = r // 4
            out[di + 1] = g // 4
            out[di + 2] = b // 4
            out[di + 3] = a // 4
    return bytes(out)


def build_png_at_size(size: int, tray_mode: bool = False) -> bytes:
    if size <= 256:
        hi = render_icon_rgba(size * 2, tray_mode=tray_mode)
        rgba = downsample_2x(size * 2, hi)
    else:
        rgba = render_icon_rgba(size, tray_mode=tray_mode)
    return encode_png(size, size, rgba)


def main() -> None:
    res_dir = REPO_ROOT / "res"
    flutter_assets = REPO_ROOT / "flutter" / "assets"
    flutter_assets.mkdir(parents=True, exist_ok=True)

    (res_dir / "dauverse-logo.svg").write_text(APP_SVG, encoding="utf-8")
    (res_dir / "dauverse-tray.svg").write_text(TRAY_SVG, encoding="utf-8")
    (res_dir / "dauverse-banner.svg").write_text(HEADER_LOGO_SVG, encoding="utf-8")
    (res_dir / "scalable.svg").write_text(APP_SVG, encoding="utf-8")
    (res_dir / "logo.svg").write_text(APP_SVG, encoding="utf-8")
    (flutter_assets / "dauverse_logo.svg").write_text(APP_SVG, encoding="utf-8")
    (flutter_assets / "dauverse_banner.svg").write_text(HEADER_LOGO_SVG, encoding="utf-8")
    (flutter_assets / "icon.svg").write_text(APP_SVG, encoding="utf-8")

    png_cache: dict[int, bytes] = {}
    for sz in (512, 256, 128, 64, 48, 32, 16):
        png_cache[sz] = build_png_at_size(sz, tray_mode=False)

    (res_dir / "icon.png").write_bytes(png_cache[512])
    (res_dir / "mac-icon.png").write_bytes(png_cache[512])
    (res_dir / "128x128@2x.png").write_bytes(png_cache[256])
    (res_dir / "128x128.png").write_bytes(png_cache[128])
    (res_dir / "64x64.png").write_bytes(png_cache[64])
    (res_dir / "32x32.png").write_bytes(png_cache[32])
    (flutter_assets / "dauverse_logo.png").write_bytes(png_cache[256])

    app_ico = encode_ico([(sz, png_cache[sz]) for sz in (256, 128, 64, 48, 32, 16)])
    (res_dir / "icon.ico").write_bytes(app_ico)
    win_runner_ico = REPO_ROOT / "flutter" / "windows" / "runner" / "resources" / "app_icon.ico"
    if win_runner_ico.parent.exists():
        win_runner_ico.write_bytes(app_ico)

    tray_ico = encode_ico([(sz, build_png_at_size(sz, tray_mode=True)) for sz in (64, 48, 32, 16)])
    (res_dir / "tray-icon.ico").write_bytes(tray_ico)

    print("Pure-Python DAUVERSE branding SVG, PNG, App ICO, and Tray ICO generated cleanly.")


if __name__ == "__main__":
    main()
