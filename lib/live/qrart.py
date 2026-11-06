"""A QR code for the terminal, written out in Python's standard library (3.9 and newer): the text as bytes (ISO 8859-1
or UTF-8, as a phone expects them), version 1–10, error correction L or M, the best of the 8 masks – and the modules as
half blocks in black and white, two rows of modules to a row of the terminal, so that they come out square.

    encode("http://192.168.178.23:5500")  →  [[True, False, …], …]    (True is a dark module)
    render(rows)                          →  lines of text, one per two rows of modules, a quiet zone around

The scheme is the one of ISO/IEC 18004: finder, timing and alignment patterns, the format information with its BCH code,
the version information from version 7, the data in blocks with Reed–Solomon codes over GF(256), interleaved.
"""

# error correction codewords per block, and the number of blocks: [level][version]  (versions 1–10)
ECC = {
    "L": {"words": [7, 10, 15, 20, 26, 18, 20, 24, 30, 18], "blocks": [1, 1, 1, 1, 1, 2, 2, 2, 2, 4], "bits": 1},
    "M": {"words": [10, 16, 26, 18, 24, 16, 18, 22, 22, 26], "blocks": [1, 1, 1, 2, 2, 4, 4, 4, 5, 5], "bits": 0},
}
MAX_VERSION = 10


def _alignment(ver):
    if ver == 1:
        return []
    n = ver // 7 + 2
    step = (ver * 4 + n * 2 + 1) // (n * 2 - 2) * 2
    return [6] + [ver * 4 + 10 - i * step for i in range(n - 2, -1, -1)]


def _raw_modules(ver):
    """Modules that hold data and error correction: all but the patterns, the format and the version information."""
    n = (16 * ver + 128) * ver + 64
    if ver >= 2:
        a = ver // 7 + 2
        n -= (25 * a - 10) * a - 55
        if ver >= 7:
            n -= 36
    return n


def _data_codewords(ver, level):
    e = ECC[level]
    return _raw_modules(ver) // 8 - e["words"][ver - 1] * e["blocks"][ver - 1]


# Reed–Solomon over GF(256), x^8 + x^4 + x^3 + x^2 + 1
_EXP, _LOG = [0] * 512, [0] * 256
_x = 1
for _i in range(255):
    _EXP[_i] = _x
    _LOG[_x] = _i
    _x <<= 1
    if _x & 0x100:
        _x ^= 0x11D
for _i in range(255, 512):
    _EXP[_i] = _EXP[_i - 255]


def _mul(a, b):
    return 0 if a == 0 or b == 0 else _EXP[_LOG[a] + _LOG[b]]


def _generator(degree):
    g = [1]
    for i in range(degree):
        nxt = [0] * (len(g) + 1)
        for j, c in enumerate(g):
            nxt[j] ^= c
            nxt[j + 1] ^= _mul(c, _EXP[i])
        g = nxt
    return g[1:]


def _remainder(data, degree):
    gen = _generator(degree)
    rem = [0] * degree
    for b in data:
        factor = b ^ rem.pop(0)
        rem.append(0)
        for i, c in enumerate(gen):
            rem[i] ^= _mul(c, factor)
    return rem


def _text_bytes(text):
    try:
        return text.encode("iso-8859-1")        # what readers take for byte mode without a hint
    except UnicodeEncodeError:
        return text.encode("utf-8")


def _codewords(payload, ver, level):
    """The data of the text as codewords, with the error correction – blocks interleaved."""
    cap = _data_codewords(ver, level)
    bits = "0100" + format(len(payload), "08b" if ver < 10 else "016b") + "".join(format(b, "08b") for b in payload)
    bits += "0" * min(4, cap * 8 - len(bits))
    bits += "0" * (-len(bits) % 8)
    data = [int(bits[i:i + 8], 2) for i in range(0, len(bits), 8)]
    pad = (0xEC, 0x11)
    while len(data) < cap:
        data.append(pad[(len(data) - len(bits) // 8) % 2])
    e = ECC[level]
    nblocks, words = e["blocks"][ver - 1], e["words"][ver - 1]
    raw = _raw_modules(ver) // 8
    short = nblocks - raw % nblocks                      # blocks one codeword shorter
    blocks, ecc, pos = [], [], 0
    for i in range(nblocks):
        size = raw // nblocks - words + (0 if i < short else 1)
        block = data[pos:pos + size]
        pos += size
        blocks.append(block)
        ecc.append(_remainder(block, words))
    out = []
    for i in range(max(len(b) for b in blocks)):
        out += [b[i] for b in blocks if i < len(b)]
    for i in range(words):
        out += [b[i] for b in ecc]
    return out


class _Matrix:
    def __init__(self, ver):
        self.ver, self.size = ver, ver * 4 + 17
        self.m = [[False] * self.size for _ in range(self.size)]
        self.fn = [[False] * self.size for _ in range(self.size)]     # function modules: no data there
        self._patterns()

    def _set(self, x, y, dark, fn=True):
        self.m[y][x] = dark
        if fn:
            self.fn[y][x] = True

    def _patterns(self):
        n = self.size
        for i in range(n):
            self._set(6, i, i % 2 == 0)
            self._set(i, 6, i % 2 == 0)
        for cx, cy in ((3, 3), (n - 4, 3), (3, n - 4)):               # finder patterns with their separators
            for dy in range(-4, 5):
                for dx in range(-4, 5):
                    x, y = cx + dx, cy + dy
                    if 0 <= x < n and 0 <= y < n:
                        self._set(x, y, max(abs(dx), abs(dy)) not in (2, 4))
        pos = _alignment(self.ver)
        for cy in pos:
            for cx in pos:
                if (cx, cy) in ((6, 6), (6, pos[-1]), (pos[-1], 6)) or (cx < 8 and cy < 8) or (cx < 8 and cy > n - 9) or (cx > n - 9 and cy < 8):
                    continue
                for dy in range(-2, 3):
                    for dx in range(-2, 3):
                        self._set(cx + dx, cy + dy, max(abs(dx), abs(dy)) != 1)
        self._format(0, 0)                                            # reserves its modules
        self._set(8, n - 8, True)                                     # the one that is always dark
        if self.ver >= 7:
            rem = self.ver
            for _ in range(12):
                rem = (rem << 1) ^ ((rem >> 11) * 0x1F25)
            bits = self.ver << 12 | rem
            for i in range(18):
                dark = (bits >> i) & 1 == 1
                a, b = n - 11 + i % 3, i // 3
                self._set(a, b, dark)
                self._set(b, a, dark)

    def _format(self, level_bits, mask):
        data = level_bits << 3 | mask
        rem = data
        for _ in range(10):
            rem = (rem << 1) ^ ((rem >> 9) * 0x537)
        bits = (data << 10 | rem) ^ 0x5412
        n = self.size
        bit = lambda i: (bits >> i) & 1 == 1
        for i in range(6):
            self._set(8, i, bit(i))
        self._set(8, 7, bit(6))
        self._set(8, 8, bit(7))
        self._set(7, 8, bit(8))
        for i in range(9, 15):
            self._set(14 - i, 8, bit(i))
        for i in range(8):
            self._set(n - 1 - i, 8, bit(i))
        for i in range(8, 15):
            self._set(8, n - 15 + i, bit(i))

    def place(self, words):
        """The codewords in the free modules, in pairs of columns from the right, up and down."""
        n, i = self.size, 0
        total = len(words) * 8
        for right in range(n - 1, 0, -2):
            if right <= 6:                    # the timing column is no column for data
                right -= 1
            for vert in range(n):
                for j in range(2):
                    x = right - j
                    y = n - 1 - vert if (right + 1) & 2 == 0 else vert
                    if not self.fn[y][x] and i < total:
                        self.m[y][x] = (words[i >> 3] >> (7 - (i & 7))) & 1 == 1
                        i += 1

    def mask(self, k):
        out = [row[:] for row in self.m]
        test = (lambda x, y: (x + y) % 2 == 0, lambda x, y: y % 2 == 0, lambda x, y: x % 3 == 0, lambda x, y: (x + y) % 3 == 0,
                lambda x, y: (x // 3 + y // 2) % 2 == 0, lambda x, y: x * y % 2 + x * y % 3 == 0,
                lambda x, y: (x * y % 2 + x * y % 3) % 2 == 0, lambda x, y: ((x + y) % 2 + x * y % 3) % 2 == 0)[k]
        for y in range(self.size):
            for x in range(self.size):
                if not self.fn[y][x] and test(x, y):
                    out[y][x] = not out[y][x]
        return out


def _penalty(m):
    n = len(m)
    score = 0
    for grid in (m, [list(col) for col in zip(*m)]):
        for line in grid:
            run, prev = 1, line[0]
            for c in line[1:]:
                if c == prev:
                    run += 1
                else:
                    score += run - 2 if run >= 5 else 0
                    run, prev = 1, c
            score += run - 2 if run >= 5 else 0
            s = "".join("1" if c else "0" for c in line)
            for pat in ("10111010000", "00001011101"):
                i = s.find(pat)
                while i >= 0:
                    score += 40
                    i = s.find(pat, i + 1)
    for y in range(n - 1):
        for x in range(n - 1):
            if m[y][x] == m[y][x + 1] == m[y + 1][x] == m[y + 1][x + 1]:
                score += 3
    dark = sum(c for row in m for c in row)
    k = (abs(dark * 20 - n * n * 10) + n * n - 1) // (n * n) - 1       # steps of 5 % away from half dark
    return score + max(k, 0) * 10


def encode(text, level="M"):
    """The QR code of text → rows of modules (True = dark). Level M, or L when the text only fits that way."""
    payload = _text_bytes(text)
    for lvl in ([level] if level == "L" else [level, "L"]):
        for ver in range(1, MAX_VERSION + 1):
            if len(payload) + 2 + (ver >= 10) <= _data_codewords(ver, lvl):
                return _build(payload, ver, lvl)
    raise ValueError("too long for a QR code here")


def _build(payload, ver, level):
    mat = _Matrix(ver)
    mat.place(_codewords(payload, ver, level))
    best = None
    for k in range(8):
        masked = mat.mask(k)
        probe = _Matrix(ver)
        probe.m = masked
        probe._format(ECC[level]["bits"], k)
        score = _penalty(probe.m)
        if best is None or score < best[0]:
            best = (score, probe.m)
    return best[1]


# ── In the terminal ───────────────────────────────────────────

def render(rows, quiet=2, indent="    "):
    """Lines of text for the terminal: ▀ with a foreground (the upper module) and a background (the lower one), in black
    and white whatever the theme – a QR code needs a light ground. quiet: the light border, in modules."""
    n = len(rows) + 2 * quiet
    dark = lambda x, y: 0 <= x - quiet < len(rows) and 0 <= y - quiet < len(rows) and rows[y - quiet][x - quiet]
    lines = []
    for y in range(0, n, 2):
        line, last = [], None
        for x in range(n):
            style = (30 if dark(x, y) else 97, 40 if dark(x, y + 1) else 107)
            if style != last:
                line.append(f"\033[{style[0]};{style[1]}m")
                last = style
            line.append("▀")
        lines.append(indent + "".join(line) + "\033[0m")
    return lines


def plain(rows):
    """The same for a terminal without colors: ██ for a dark module, two spaces for a light one."""
    return ["".join("██" if c else "  " for c in row) for row in rows]
