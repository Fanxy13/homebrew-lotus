#!/usr/bin/env python3
"""Builds the lotus of the setup wizard: data/lotus-setup.txt.

Five hand-drawn stages, one per setup step – a closed bud on Welcome, the full flower on Review.
Each stage is drawn as its left half (the middle column included) and mirrored. Letters mark the
petals, the shading is worked out here, so every petal gets its own darker outline:

  C    the middle petal (front)     I    the inner pair     O    the outer pair (back)
  G g  the lily pad, light and dark

The output uses the same codes as data/bloom.txt (0-9 petal shades, g/G leaf), and Lotus maps them to
the colors of a theme. Run from the repository root: python3 scripts/make-setup-lotus.py
"""

STAGES = ["""
.............
.............
.............
.............
.............
............C
...........CC
...........CC
..........CCC
..........CCC
..........CCC
...........CC
.....GGGGGGGG
.......gggggg
""", """
.............
.............
.............
............C
...........CC
...........CC
..........CCC
.........ICCC
........IICCC
........IICCC
.........IICC
..........IIC
...GGGGGGGGGG
.....gggggggg
""", """
.............
.............
............C
...........CC
...........CC
......I...CCC
......II..CCC
......III.CCC
.......III.CC
.......IIIICC
........IIICC
.........IIIC
..GGGGGGGGGGG
....ggggggggg
""", """
.............
............C
...........CC
...........CC
....I.....CCC
....II....CCC
....III..CCCC
.....III.CCCC
..O..IIII.CCC
..OO..IIIICCC
...OOO.IIIICC
....OOO.IIIIC
GGGGGGOOOOIIC
.gggggggggggg
""", """
.............
............C
...........CC
..........CCC
..I.......CCC
..II.....CCCC
..III....CCCC
..IIII..CCCCC
O..IIII.CCCCC
OO..IIIICCCCC
.OOO.IIIICCCC
..OOOO.IIIICC
GGGGOOOOOOIIC
.gggggggggggg
"""]

LAYER = {"C": 1, "I": 0, "O": -1}     # front petals a little lighter than the ones behind


def shade(half):
    rows = half.strip("\n").split("\n")
    full = [r + r[:-1][::-1] for r in rows]
    h, w = len(full), len(full[0])

    def petal(y, x):     # one petal = one letter on one side
        ch = full[y][x]
        if ch not in LAYER:
            return None
        return ch, 0 if ch == "C" else (-1 if x < w // 2 else 1)

    span = {}
    for y in range(h):
        for x in range(w):
            p = petal(y, x)
            if p:
                top, bottom = span.get(p, (y, y))
                span[p] = (min(top, y), max(bottom, y))

    def same(p, y, x):
        return 0 <= y < h and 0 <= x < w and petal(y, x) == p

    out = []
    for y in range(h):
        row = ""
        for x in range(w):
            p = petal(y, x)
            if not p:
                row += full[y][x]
                continue
            top, bottom = span[p]
            t = 1 - (y - top) / max(1, bottom - top)          # 0 at the base, 1 at the tip
            s = 3 + 5.5 * t + LAYER[p[0]]
            if not same(p, y, x - 1) or not same(p, y, x + 1):
                s -= 2                                        # outline at the sides
            elif not same(p, y - 1, x):
                s -= 1
            row += str(max(0, min(9, round(s))))
        out.append(row)
    return out


def main():
    frames = [shade(s) for s in STAGES]
    h, w = len(frames[0]), len(frames[0][0])
    with open("data/lotus-setup.txt", "w", encoding="utf-8") as out:
        out.write(f"# Lotus setup: {len(frames)} stages of {w}x{h} pixels (half blocks), made by scripts/make-setup-lotus.py\n")
        for f in frames:
            out.write("\n".join(f) + "\n%\n")
    print(f"data/lotus-setup.txt: {len(frames)} stages")


if __name__ == "__main__":
    main()
