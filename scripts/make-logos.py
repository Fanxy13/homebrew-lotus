#!/usr/bin/env python3
"""Builds the logo variants from logos/lotus.txt (the original Lotus Classic).

Every character gets a density (space … #). The density grid is resampled
and turned back into characters, so all variants keep the same flower.
Run from the repository root: python3 scripts/make-logos.py
"""
RAMP = " .:-=+*#"
SHADES = " ░▒▓█"

def load(path):
    lines = [l.rstrip("\n") for l in open(path, encoding="utf-8")]
    while lines and not lines[-1].strip():
        lines.pop()
    w = max(len(l) for l in lines)
    return [[RAMP.index(c) / 7 if c in RAMP else 0.5 for c in l.ljust(w)] for l in lines]

def sample(grid, x, y):
    h, w = len(grid), len(grid[0])
    x0, y0 = int(x), int(y)
    fx, fy = x - x0, y - y0
    def g(xx, yy):
        return grid[min(max(yy, 0), h - 1)][min(max(xx, 0), w - 1)]
    top = g(x0, y0) * (1 - fx) + g(x0 + 1, y0) * fx
    bot = g(x0, y0 + 1) * (1 - fx) + g(x0 + 1, y0 + 1) * fx
    return top * (1 - fy) + bot * fy

def coverage_mix(path):
    """Mix of 'is there a character' and its density – keeps the outline when shrinking."""
    lines = [l.rstrip("\n") for l in open(path, encoding="utf-8")]
    while lines and not lines[-1].strip():
        lines.pop()
    w = max(len(l) for l in lines)
    return [[(0.6 if c != " " else 0) + 0.4 * (RAMP.index(c) / 7 if c in RAMP else 0.5) for c in l.ljust(w)]
            for l in lines]

def resize(grid, w, h, box=False):
    gh, gw = len(grid), len(grid[0])
    out = []
    for j in range(h):
        row = []
        for i in range(w):
            if box:   # average a block of source cells (for shrinking)
                xs = range(int(i * gw / w), max(int((i + 1) * gw / w), int(i * gw / w) + 1))
                ys = range(int(j * gh / h), max(int((j + 1) * gh / h), int(j * gh / h) + 1))
                vals = [grid[y][x] for y in ys for x in xs]
                row.append(sum(vals) / len(vals))
            else:
                row.append(sample(grid, (i + 0.5) * gw / w - 0.5, (j + 0.5) * gh / h - 0.5))
        out.append(row)
    return out

def render(grid, chars, gamma=1.0):
    n = len(chars) - 1
    lines = []
    for row in grid:
        line = ""
        for v in row:
            v = v ** gamma
            line += chars[min(n, int(round(v * n)))] if v > 0.06 else " "
        lines.append(line.rstrip())
    while lines and not lines[0].strip():
        lines.pop(0)
    while lines and not lines[-1].strip():
        lines.pop()
    w = max(len(l) for l in lines)
    return "\n".join(l.ljust(w) for l in lines) + "\n"

classic = load("logos/lotus.txt")
h, w = len(classic), len(classic[0])
open("logos/large.txt", "w", encoding="utf-8").write(render(resize(classic, int(w * 1.45), int(h * 1.45)), RAMP))
open("logos/minimal.txt", "w", encoding="utf-8").write(render(resize(coverage_mix("logos/lotus.txt"), 34, 14, box=True), RAMP, 1.3))
open("logos/terminal.txt", "w", encoding="utf-8").write(render(classic, SHADES))
