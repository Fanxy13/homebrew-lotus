#!/usr/bin/env python3
"""Draws Lotus' own pets – the cat and the dog – as tiny pixel sprites: data/pets/cat.pet, dog.pet.

Each sprite is a grid of pixels ('#' set, '.' empty) that becomes quadrant block characters
(two by two pixels per character: ▘ ▝ ▀ ▖ ▌ ▞ ▛ ▗ ▚ ▐ ▜ ▄ ▙ ▟ █). Eyes are one-pixel gaps. Every
drawing (idle, blink, wag, talk, happy, eat, sleep) is made from the same body, so they can be
swapped like frames. "mini" is the line with the eyes: the pet's face in one line (the spinner of
/ai, reactions). Everything in a .pet file before the first [frame] is kept as it is.

Run from the repository root: python3 scripts/make-pets.py
"""

QUAD = {(0, 0, 0, 0): ' ', (1, 0, 0, 0): '▘', (0, 1, 0, 0): '▝', (1, 1, 0, 0): '▀', (0, 0, 1, 0): '▖',
        (1, 0, 1, 0): '▌', (0, 1, 1, 0): '▞', (1, 1, 1, 0): '▛', (0, 0, 0, 1): '▗', (1, 0, 0, 1): '▚',
        (0, 1, 0, 1): '▐', (1, 1, 0, 1): '▜', (0, 0, 1, 1): '▄', (1, 0, 1, 1): '▙', (0, 1, 1, 1): '▟',
        (1, 1, 1, 1): '█'}


def grid(text):
    rows = text.split()
    w = max(len(r) for r in rows)
    return [list(r.ljust(w, '.')) for r in rows]


def quad(g):
    h, w = len(g), len(g[0])
    out = []
    for y in range(0, h, 2):
        line = ''
        for x in range(0, w, 2):
            px = lambda yy, xx: int(yy < h and xx < w and g[yy][xx] == '#')
            line += QUAD[(px(y, x), px(y, x + 1), px(y + 1, x), px(y + 1, x + 1))]
        out.append(line.rstrip())
    return out


def edit(g, changes):
    """changes: (row, x, '#' or '.') or (row, 'whole row text')"""
    g = [r[:] for r in g]
    for c in changes:
        if len(c) == 2:
            g[c[0]] = list(c[1].ljust(len(g[0]), '.'))
        else:
            g[c[0]][c[1]] = c[2]
    return g


def frames(base, eyes, talk, eat, tail_wag, tail_happy, legs_row):
    """eyes, talk, eat: [(row, x)…] pixels · tail_*: replacement rows (row, text)"""
    shut = [(r, x, '#') for r, x in eyes]
    f = {'idle': base,
         'blink': edit(base, shut),
         'wag': edit(base, tail_wag),
         'talk': edit(base, [(r, x, '.') for r, x in talk]),
         'eat': edit(base, [(r, x, '.') for r, x in eat]),
         'happy': edit(edit(base, shut), tail_happy),
         'sleep': edit(edit(base, shut), [(legs_row, '')])}
    art = {k: quad(v) for k, v in f.items()}
    art['sleep'][0] += '  z'
    art['sleep'][1] = art['sleep'][1].ljust(len(art['sleep'][0]) - 1) + 'Z'
    return art


CAT = grid("""
....#........#......
...###......###.....
...############.....
...##.######.##.....
...############..#..
...############.##..
...############.#...
....#.#....#.#......
""")

# the dog stands sideways: ear and snout on the left, the tail up on the right
DOG = grid("""
....................
..###...........#...
.####...........#...
##.###############..
##################..
..################..
...##############...
....#.#.......#.#...
""")

PETS = {
    'cat': frames(CAT, eyes=[(3, 5), (3, 12)], talk=[(4, 8), (4, 9)], eat=[(4, 7), (4, 8), (4, 9), (4, 10)],
                  tail_wag=[(4, '...############.#...'), (5, '...############.#...'), (6, '...############.##..')],
                  tail_happy=[(4, '...############.##..'), (5, '...############..#..'), (6, '...############..#..')],
                  legs_row=7),
    'dog': frames(DOG, eyes=[(3, 2)], talk=[(4, 1)], eat=[(4, 0), (4, 1)],
                  tail_wag=[(1, '..###............#..'), (2, '.####...........#...')],
                  tail_happy=[(1, '..###............#..'), (2, '.####...........#...')],
                  legs_row=7),
}

# the face in one line: the character row with the eyes, and how wide it is (without the tail)
MINI = {'cat': (CAT, 2, 16), 'dog': (DOG, 2, 18)}


def mini(g, top, width, eyes_open=True, eyes=()):
    rows = [r[:width] for r in g[top:top + 2]]
    if not eyes_open:
        for r, x in eyes:
            rows[r - top][x] = '#'
    return quad(rows)[0].strip()


def main():
    eyes = {'cat': [(3, 5), (3, 12)], 'dog': [(3, 2)]}
    for kind, art in PETS.items():
        path = f'data/pets/{kind}.pet'
        head = open(path, encoding='utf-8').read().split('\n[', 1)[0].rstrip('\n').split('\n')
        g, top, width = MINI[kind]
        keep = [l for l in head if not l.startswith(('mini:', 'mini_blink:', 'face:', 'face_happy:'))]
        keep += [f'mini: {mini(g, top, width)}', f'mini_blink: {mini(g, top, width, False, eyes[kind])}',
                 f'face: {mini(g, top, width)}', f'face_happy: {mini(g, top, width, False, eyes[kind])}']
        body = []
        for name in ('idle', 'blink', 'wag', 'talk', 'happy', 'eat', 'sleep'):
            body.append(f'[{name}]')
            body += art[name]
        with open(path, 'w', encoding='utf-8') as out:
            out.write('\n'.join(keep) + '\n' + '\n'.join(body) + '\n')
        print(f'{path}: {len(art)} drawings')
        print('\n'.join(art['idle']))


if __name__ == '__main__':
    main()
