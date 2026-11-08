#!/usr/bin/env python3
"""A take, read back: the scene markers and the moments the screen comes to rest, with their times – to choose the cuts
(cut.json). With --at, the whole screen at those seconds.

    python3 timeline.py takes/take-1.cast.gz
    python3 timeline.py takes/take-1.cast.gz --at 312.5 330
    python3 timeline.py takes/take-1.cast.gz --find 'Pick a theme' 'Lotus is ready'   (when each first shows)
"""
import gzip
import json
import sys

import pyte

from record import Screen                              # (with the alternate screen, as the recording reads it)


def load(path):
    with (gzip.open(path, 'rt', encoding='utf-8') if path.endswith('.gz') else open(path, encoding='utf-8')) as f:
        lines = [line for line in f.read().split('\n') if line]
    return json.loads(lines[0]), [json.loads(line) for line in lines[1:]]


def main(argv):
    head, events = load(argv[0])
    at = [float(x) for x in argv[2:]] if argv[1:2] == ['--at'] else []
    screen = Screen(head['width'], head['height'])
    stream = pyte.Stream(screen)
    rows = lambda: [line.rstrip() for line in screen.display]
    if argv[1:2] == ['--find']:
        import re
        wanted = [(w, re.compile(w)) for w in argv[2:]]
        found = {}
        for t, kind, data in events:
            if kind == 'o':
                stream.feed(data)
            elif data == 'window':
                screen.reset()
            if kind != 'o' or len(found) == len(wanted):
                continue
            text = '\n'.join(rows())
            for w, rx in wanted:
                if w not in found and rx.search(text):
                    found[w] = t
        for w, _ in wanted:
            print(f'{found[w]:8.2f}  {w}' if w in found else f'{"–":>8}  {w}')
        return 0
    if at:
        k = 0
        for want in sorted(at):
            while k < len(events) and events[k][0] <= want:
                t, kind, data = events[k]
                if kind == 'o':
                    stream.feed(data)
                elif data == 'window':
                    screen.reset()
                k += 1
            print(f'── {want:.2f} s ' + '─' * 60)
            print('\n'.join(rows()).rstrip())
        return 0
    for i, (t, kind, data) in enumerate(events):
        if kind == 'm':
            print(f'\n{t:8.2f}  ▶ {data}')
            if data == 'window':
                screen.reset()
            continue
        stream.feed(data)
        nxt = next((e[0] for e in events[i + 1:] if e[1] == 'o'), None)
        if nxt is None or nxt - t >= 0.6:            # the screen rests here
            shown = [r.strip() for r in rows() if r.strip()]
            last = shown[-1] if shown else ''
            print(f'{t:8.2f}  {"(rest %.1f s)" % (nxt - t) if nxt else "(end)":>14}  {last[:90]}')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
