#!/usr/bin/env python3
"""Builds the blooming lotus of the Remove BG progress screen: data/bloom.txt.

The flower is drawn as small pixel art for half-block characters (two pixels per terminal cell),
from a closed bud to full bloom. Pixels store shades, not colors – Lotus maps them to the colors
of the current theme, so the lotus is pink in Matcha and blue in Ocean, like the logo.

  .      empty          0-9    petal, dark at the base … light at the tip
  y Y    heart          g G    leaf, dark … light

Run from the repository root: python3 scripts/make-bloom.py   (--png <file> draws a preview sheet)
"""
import math
import sys

W, H = 41, 20            # pixels; 41 x 10 terminal cells
FRAMES = 16
BX, BY = 20, 15.2        # base of the flower

# layer: petals, opening in degrees, length, width, shade offset.
# Outer petals open wide and stay short, the inner ones stay a cup and get taller towards the
# middle – so the open flower has a pointed, rounded outline instead of a flat top.
LAYERS = [
    (6, 176, 9.6, 5.0, -3),
    (4, 104, 11.0, 5.4, -1),
    (3, 52, 11.8, 5.6, 1),
    (1, 0, 13.6, 5.2, 2),
]


def ease(t):
    return t * t * (3 - 2 * t)      # smoothstep: the flower opens evenly


def petal_pixels(grid, ang, length, width, offset, bud):
    s, c = math.sin(ang), math.cos(ang)
    for py in range(H):
        for px in range(W):
            x, y = px + 0.5 - BX, BY - (py + 0.5)
            u = x * s + y * c
            v = x * c - y * s
            if u <= 0 or u >= length:
                continue
            t = u / length
            half = width * 0.5 * math.sin(math.pi * t ** 0.68) ** 1.0     # widest early, long pointed tip
            if abs(v) >= half:
                continue
            edge = abs(v) / half
            shade = 2 + 6 * t + offset - (2.5 if edge > 0.72 else 0) + bud
            grid[py][px] = str(max(0, min(9, round(shade))))


def frame(b):
    grid = [["."] * W for _ in range(H)]
    o = ease(b)
    # leaves: a pad that unfolds sideways
    reach = 7 + 12 * o
    for py in range(H):
        for px in range(W):
            x, y = px + 0.5 - BX, (py + 0.5) - (BY + 1.6)
            if (x / reach) ** 2 + (y / 2.4) ** 2 < 1:
                grid[py][px] = "G" if y < -0.6 else "g"
    for count, spread, length, width, offset in LAYERS:
        L = length * (0.62 + 0.38 * o)
        Wd = width * (0.62 + 0.38 * o)
        for i in range(count):
            pos = i / (count - 1) - 0.5 if count > 1 else 0
            ang = math.radians(pos * spread * (0.04 + 0.96 * o))
            petal_pixels(grid, ang, L, Wd, offset, round(-1.5 * (1 - o)))
    # lone pixels at the petal tips look like dust: a petal pixel needs two petal neighbours
    lone = []
    for py in range(H):
        for px in range(W):
            if not grid[py][px].isdigit():
                continue
            n = sum(1 for dy in (-1, 0, 1) for dx in (-1, 0, 1)
                    if (dy or dx) and 0 <= py + dy < H and 0 <= px + dx < W and grid[py + dy][px + dx].isdigit())
            if n < 2:
                lone.append((py, px))
    for py, px in lone:
        grid[py][px] = "."
    if o > 0.55:
        for px in range(BX - 2, BX + 3):
            grid[int(BY - 3)][px] = "Y" if abs(px - BX) < 2 else "y"
        grid[int(BY - 4)][BX] = "Y"
    return ["".join(r) for r in grid]


def ramp(rgb, k):
    """Same shading as lib/bg/progress.zsh: deep, saturated base → theme color → almost white tip."""
    m = sum(rgb) / 3
    deep = [max(0, min(255, c * 0.58 - (m - c) * 0.7)) for c in rgb]
    tip = [c + (255 - c) * 0.62 for c in rgb]
    if k < 0.6:
        a, b, f = deep, rgb, k / 0.6
    else:
        a, b, f = rgb, tip, (k - 0.6) / 0.4
    return tuple(int(a[i] + (b[i] - a[i]) * f) for i in range(3))


def png(path, frames):
    from PIL import Image
    pink, green, yellow = (248, 184, 208), (181, 211, 113), (236, 236, 140)
    def petal(n):
        return ramp(pink, int(n) / 9)
    colors = {"y": ramp(yellow, 0.45), "Y": ramp(yellow, 0.8), "g": ramp(green, 0.25), "G": ramp(green, 0.55)}
    cell = 6
    sheet = Image.new("RGB", (W * cell * 4 + 30, H * cell * ((len(frames) + 3) // 4) + 30), (11, 15, 18))
    for i, f in enumerate(frames):
        ox, oy = (i % 4) * (W * cell + 10), (i // 4) * (H * cell + 10)
        for y, row in enumerate(f):
            for x, ch in enumerate(row):
                if ch == ".":
                    continue
                col = petal(ch) if ch.isdigit() else colors[ch]
                for dy in range(cell):
                    for dx in range(cell):
                        sheet.putpixel((ox + x * cell + dx, oy + y * cell + dy), col)
    sheet.save(path)


def main():
    frames = [frame(i / (FRAMES - 1)) for i in range(FRAMES)]
    if "--png" in sys.argv:
        png(sys.argv[sys.argv.index("--png") + 1], frames)
        return
    with open("data/bloom.txt", "w", encoding="utf-8") as out:
        out.write(f"# Lotus bloom: {FRAMES} frames of {W}x{H} pixels (half blocks), made by scripts/make-bloom.py\n")
        for f in frames:
            out.write("\n".join(f) + "\n%\n")
    print(f"data/bloom.txt: {FRAMES} frames")


if __name__ == "__main__":
    main()
