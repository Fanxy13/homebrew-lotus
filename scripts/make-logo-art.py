#!/usr/bin/env python3
"""Builds the picture logos: logos/apple.txt and logos/earth.txt.

Both are drawn with quadrant block characters (two by two pixels per character: ▘ ▝ ▀ ▖ ▌ ▞ ▛ ▗ ▚
▐ ▜ ▄ ▙ ▟ █), like the pets. The files hold shapes only – Lotus paints them: in the theme's logo
color, or in their own colors (lib/art.zsh): the Apple in the six stripes of 1977, the flag as
white rings on blue. That is why the flag keeps a margin around its rings – it becomes the blue.

  apple   the Apple glyph of the system font (San Francisco)
  earth   the International Flag of Planet Earth (Oskar Pernefeldt): seven interlocking rings.
          Drawn from a picture of the flag, so the rings keep their over-and-under weave.

Needs Pillow (pip install pillow). Run from the repository root:
  python3 scripts/make-logo-art.py <picture of the flag of Earth>
"""
import sys
from PIL import Image, ImageDraw, ImageFont

QUAD = ' ▘▝▀▖▌▞▛▗▚▐▜▄▙▟█'   # index: top-left 1, top-right 2, bottom-left 4, bottom-right 8


def quadrants(img, cols, rows, threshold=0.5):
    """Grayscale picture → lines of quadrant characters (cols × rows), lit where it is bright."""
    small = img.resize((cols * 2, rows * 2), Image.BOX)
    px = small.load()
    on = lambda x, y: px[x, y] / 255 > threshold
    lines = []
    for r in range(rows):
        line = ''
        for c in range(cols):
            x, y = 2 * c, 2 * r
            line += QUAD[on(x, y) + 2 * on(x + 1, y) + 4 * on(x, y + 1) + 8 * on(x + 1, y + 1)]
        lines.append(line)
    return lines


def apple():
    font = ImageFont.truetype('/System/Library/Fonts/SFNS.ttf', 1600)
    img = Image.new('L', (2200, 2200), 0)
    ImageDraw.Draw(img).text((200, 0), '', font=font, fill=255)
    lines = quadrants(img.crop(img.getbbox()), 36, 22)
    return [l.rstrip() for l in lines]


def earth(path):
    img = Image.open(path).convert('L')
    w, h = img.size
    # the flower of rings: 1004 × 941 of a 2000 × 1333 flag, centered
    box = (round(w * 0.249), round(h * 0.147), round(w * 0.751), round(h * 0.853))
    rings = quadrants(img.crop(box), 46, 22)
    pad = ' ' * 3
    blank = ' ' * (46 + 2 * len(pad))
    return [blank] + [pad + l + pad for l in rings] + [blank]


def write(name, lines):
    with open(f'logos/{name}.txt', 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')


if len(sys.argv) != 2:
    sys.exit(__doc__)
write('apple', apple())
write('earth', earth(sys.argv[1]))
