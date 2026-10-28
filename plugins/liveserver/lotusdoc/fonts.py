"""TrueType fonts for the PDFs: which glyph a character has (cmap), how wide it is (hmtx), and a subset with only the
glyphs a document uses, to embed – the Mac's own Arial and Menlo (Liberation and DejaVu elsewhere). A character
that the font lacks comes from a fallback font (Arial Unicode, Apple Symbols, DejaVu …), else it is a "?".
"""
import bisect
import os
import struct

SANS = {
    "regular": ["/System/Library/Fonts/Supplemental/Arial.ttf", "/Library/Fonts/Arial.ttf",
                "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"],
    "bold": ["/System/Library/Fonts/Supplemental/Arial Bold.ttf", "/Library/Fonts/Arial Bold.ttf",
             "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"],
    "italic": ["/System/Library/Fonts/Supplemental/Arial Italic.ttf", "/Library/Fonts/Arial Italic.ttf",
               "/usr/share/fonts/truetype/liberation/LiberationSans-Italic.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Oblique.ttf"],
    "bolditalic": ["/System/Library/Fonts/Supplemental/Arial Bold Italic.ttf", "/Library/Fonts/Arial Bold Italic.ttf",
                   "/usr/share/fonts/truetype/liberation/LiberationSans-BoldItalic.ttf",
                   "/usr/share/fonts/truetype/dejavu/DejaVuSans-BoldOblique.ttf"],
}
MONO = {
    "regular": ["/System/Library/Fonts/Menlo.ttc", "/System/Library/Fonts/Supplemental/Courier New.ttf",
                "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf"],
    "bold": ["/System/Library/Fonts/Menlo.ttc", "/System/Library/Fonts/Supplemental/Courier New Bold.ttf",
             "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf", "/usr/share/fonts/truetype/liberation/LiberationMono-Bold.ttf"],
}
FALLBACK = ["/System/Library/Fonts/Supplemental/Arial Unicode.ttf", "/Library/Fonts/Arial Unicode.ttf",
            "/System/Library/Fonts/Apple Symbols.ttf", "/System/Library/Fonts/Menlo.ttc",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
            "/usr/share/fonts/truetype/freefont/FreeSerif.ttf", "/usr/share/fonts/truetype/freefont/FreeSans.ttf"]


def _u16(d, o):
    return struct.unpack_from(">H", d, o)[0]


def _i16(d, o):
    return struct.unpack_from(">h", d, o)[0]


def _u32(d, o):
    return struct.unpack_from(">I", d, o)[0]


class Font:
    """One TrueType font (or one face of a .ttc collection)."""

    def __init__(self, path, data=None, offset=0):
        self.path = path
        d = self.data = data if data is not None else open(path, "rb").read()
        if d[offset:offset + 4] not in (b"\x00\x01\x00\x00", b"true"):
            raise ValueError("not a TrueType font")
        self.tables = {}
        for i in range(_u16(d, offset + 4)):
            tag, _, off, length = struct.unpack_from(">4sIII", d, offset + 12 + 16 * i)
            self.tables[tag.decode("latin-1")] = (off, length)
        for need in ("head", "hhea", "hmtx", "maxp", "cmap", "loca", "glyf"):
            if need not in self.tables:
                raise ValueError("a font without " + need)
        head = self.tables["head"][0]
        self.upem = _u16(d, head + 18)
        self.bbox = [_i16(d, head + 36 + 2 * i) for i in range(4)]
        self.style = _u16(d, head + 44)                  # bit 0 bold, bit 1 italic
        long_loca = _i16(d, head + 50) == 1
        hhea = self.tables["hhea"][0]
        self.ascent, self.descent = _i16(d, hhea + 4), _i16(d, hhea + 6)
        n_metrics = _u16(d, hhea + 34)
        self.n = _u16(d, self.tables["maxp"][0] + 4)
        hmtx = self.tables["hmtx"][0]
        metrics = struct.unpack_from(f">{2 * n_metrics}H", d, hmtx)
        self.advance = list(metrics[0::2]) + [metrics[-2]] * (self.n - n_metrics)
        self.lsb = [x - 65536 if x > 32767 else x for x in metrics[1::2]]
        rest = self.n - n_metrics
        if rest > 0:
            self.lsb += list(struct.unpack_from(f">{rest}h", d, hmtx + 4 * n_metrics))
        loca = self.tables["loca"][0]
        if long_loca:
            self.loca = list(struct.unpack_from(f">{self.n + 1}I", d, loca))
        else:
            self.loca = [x * 2 for x in struct.unpack_from(f">{self.n + 1}H", d, loca)]
        self.cap = self.ascent * 0.7
        self.embeddable, self.weight = True, 700 if self.style & 1 else 400
        if "OS/2" in self.tables:
            os2 = self.tables["OS/2"][0]
            fs_type = _u16(d, os2 + 8)
            self.embeddable = (fs_type & 0x000F) != 0x0002          # "restricted license": may not be embedded
            self.weight = _u16(d, os2 + 4)
            if _u16(d, os2) >= 2 and self.tables["OS/2"][1] >= 90:
                self.cap = _i16(d, os2 + 88)
        self.italic_angle, self.fixed = 0.0, False
        if "post" in self.tables:
            post = self.tables["post"][0]
            self.italic_angle = struct.unpack_from(">i", d, post + 4)[0] / 65536.0
            self.fixed = _u32(d, post + 12) != 0
        self.name = self._ps_name() or os.path.splitext(os.path.basename(path))[0].replace(" ", "")
        self._cmap()
        self._cache = {}

    def _ps_name(self):
        if "name" not in self.tables:
            return ""
        d, base = self.data, self.tables["name"][0]
        count, strings = _u16(d, base + 2), base + _u16(d, base + 4)
        for i in range(count):
            platform, encoding, _, name_id, length, off = struct.unpack_from(">6H", d, base + 6 + 12 * i)
            if name_id != 6:
                continue
            raw = d[strings + off:strings + off + length]
            text = raw.decode("utf-16-be", "replace") if platform in (0, 3) else raw.decode("latin-1")
            text = "".join(c for c in text if c.isalnum() or c in "-_")
            if text:
                return text
        return ""

    def _cmap(self):
        """The best Unicode table: format 12 (all of Unicode) or format 4 (the first 65536)."""
        d, base = self.data, self.tables["cmap"][0]
        best = None
        for i in range(_u16(d, base + 2)):
            platform, encoding, off = struct.unpack_from(">HHI", d, base + 4 + 8 * i)
            sub = base + off
            fmt = _u16(d, sub)
            rank = {(3, 10, 12): 0, (0, 4, 12): 1, (0, 6, 12): 1, (3, 1, 4): 2, (0, 3, 4): 3, (0, 1, 4): 4, (0, 0, 4): 5}.get((platform, encoding, fmt))
            if rank is not None and (best is None or rank < best[0]):
                best = (rank, sub, fmt)
        if best is None:
            raise ValueError("a font without a Unicode table")
        _, sub, fmt = best
        self.fmt = fmt
        if fmt == 12:
            groups = _u32(d, sub + 12)
            g = struct.unpack_from(f">{3 * groups}I", d, sub + 16)
            self.starts, self.ends, self.glyphs = list(g[0::3]), list(g[1::3]), list(g[2::3])
        else:
            seg = _u16(d, sub + 6) // 2
            self.ends = list(struct.unpack_from(f">{seg}H", d, sub + 14))
            self.starts = list(struct.unpack_from(f">{seg}H", d, sub + 16 + 2 * seg))
            self.deltas = list(struct.unpack_from(f">{seg}h", d, sub + 16 + 4 * seg))
            self.range_pos = sub + 16 + 6 * seg
            self.ranges = list(struct.unpack_from(f">{seg}H", d, self.range_pos))

    def gid(self, ch):
        """The glyph of a character, 0 when the font has none."""
        c = ord(ch)
        g = self._cache.get(c)
        if g is not None:
            return g
        g = 0
        i = bisect.bisect_left(self.ends, c)
        if i < len(self.ends) and self.starts[i] <= c:
            if self.fmt == 12:
                g = self.glyphs[i] + c - self.starts[i]
            elif self.ranges[i] == 0:
                g = (c + self.deltas[i]) & 0xFFFF
            else:
                at = self.range_pos + 2 * i + self.ranges[i] + 2 * (c - self.starts[i])
                if at + 2 <= len(self.data):
                    g = _u16(self.data, at)
                    if g:
                        g = (g + self.deltas[i]) & 0xFFFF
        if g >= self.n:
            g = 0
        self._cache[c] = g
        return g

    def glyph(self, g):
        start = self.tables["glyf"][0]
        return self.data[start + self.loca[g]:start + self.loca[g + 1]]

    @staticmethod
    def _components(data):
        """(position of the glyph index, glyph index) of each part of a composite glyph."""
        out = []
        if len(data) < 10 or _i16(data, 0) >= 0:
            return out
        pos = 10
        while pos + 4 <= len(data):
            flags = _u16(data, pos)
            out.append((pos + 2, _u16(data, pos + 2)))
            pos += 4 + (4 if flags & 0x0001 else 2)
            if flags & 0x0008:
                pos += 2
            elif flags & 0x0040:
                pos += 4
            elif flags & 0x0080:
                pos += 8
            if not flags & 0x0020:
                break
        return out

    def subset(self, used, chars):
        """A font with only the glyphs in used (and the parts of composite glyphs) – (sfnt bytes, {old glyph: new}).
        chars {character: old glyph} becomes its Unicode table."""
        keep, todo = {0} | set(used), list(used)
        while todo:
            for _, c in self._components(self.glyph(todo.pop())):
                if c < self.n and c not in keep:
                    keep.add(c)
                    todo.append(c)
        order = sorted(keep)
        new = {g: i for i, g in enumerate(order)}
        glyf, loca, hmtx = bytearray(), [], bytearray()
        for g in order:
            loca.append(len(glyf))
            data = bytearray(self.glyph(g))
            for pos, c in self._components(data):
                struct.pack_into(">H", data, pos, new.get(c, 0))
            glyf += data
            glyf += b"\0" * (-len(glyf) % 4)
            hmtx += struct.pack(">Hh", self.advance[g], self.lsb[g] if g < len(self.lsb) else 0)
        loca.append(len(glyf))
        d = self.data

        def table(tag):
            off, length = self.tables[tag]
            return bytearray(d[off:off + length])

        head = table("head")
        struct.pack_into(">I", head, 8, 0)                  # checkSumAdjustment
        struct.pack_into(">h", head, 50, 1)                 # long loca
        hhea = table("hhea")
        struct.pack_into(">H", hhea, 34, len(order))
        maxp = table("maxp")
        struct.pack_into(">H", maxp, 4, len(order))
        tables = {"head": head, "hhea": hhea, "maxp": maxp, "hmtx": hmtx, "glyf": glyf,
                  "loca": struct.pack(f">{len(loca)}I", *loca), "cmap": _cmap4({c: new[g] for c, g in chars.items() if g in new})}
        if "post" in self.tables:
            post = table("post")[:32]
            if len(post) == 32:
                struct.pack_into(">I", post, 0, 0x00030000)  # version 3: no glyph names
                tables["post"] = post
        for tag in ("cvt ", "fpgm", "prep"):
            if tag in self.tables:
                tables[tag] = table(tag)
        return _sfnt(tables), new


def _cmap4(chars):
    """A Unicode table (format 4) for the characters of the subset that are in the first 65536."""
    pairs = sorted((ord(c), g) for c, g in chars.items() if ord(c) < 0xFFFF)
    segs = []                              # (start, end, delta) – runs of characters whose glyphs follow each other
    for c, g in pairs:
        if segs and segs[-1][1] == c - 1 and (c + segs[-1][2]) & 0xFFFF == g:
            segs[-1][1] = c
        else:
            segs.append([c, c, (g - c) & 0xFFFF])
    segs.append([0xFFFF, 0xFFFF, 1])
    n = len(segs)
    search = 2 * (1 << (n.bit_length() - 1))
    body = struct.pack(">HHHH", 2 * n, search, (search // 2).bit_length() - 1, 2 * n - search)
    body += struct.pack(f">{n}H", *(s[1] for s in segs)) + b"\0\0"
    body += struct.pack(f">{n}H", *(s[0] for s in segs))
    body += struct.pack(f">{n}H", *(s[2] for s in segs))
    body += struct.pack(f">{n}H", *(0 for _ in segs))
    sub = struct.pack(">HHH", 4, 6 + len(body), 0) + body
    return struct.pack(">HHHHI", 0, 1, 3, 1, 12) + sub


def _checksum(data):
    data = bytes(data) + b"\0" * (-len(data) % 4)
    return sum(struct.unpack(f">{len(data) // 4}I", data)) & 0xFFFFFFFF


def _sfnt(tables):
    tags = sorted(tables)
    n = len(tags)
    search = 16 * (1 << (n.bit_length() - 1))
    out = bytearray(struct.pack(">IHHHH", 0x00010000, n, search, (search // 16).bit_length() - 1, 16 * n - search))
    offset = 12 + 16 * n
    body = bytearray()
    for tag in tags:
        data = bytes(tables[tag])
        out += struct.pack(">4sIII", tag.encode("latin-1"), _checksum(data), offset + len(body), len(data))
        body += data + b"\0" * (-len(data) % 4)
    return bytes(out + body)


def load(path, want_bold=False, want_italic=False):
    """The font at path – for a .ttc the face that is (not) bold and (not) italic. None when it cannot be used."""
    try:
        data = open(path, "rb").read()
    except OSError:
        return None
    offsets = [0]
    if data[:4] == b"ttcf":
        offsets = list(struct.unpack_from(f">{_u32(data, 8)}I", data, 12))
    found = []
    for off in offsets:
        try:
            f = Font(path, data, off)
        except (ValueError, struct.error, IndexError):
            continue
        if f.embeddable:
            found.append(f)
    for f in found:
        if bool(f.style & 1) == want_bold and bool(f.style & 2) == want_italic:
            return f
    for f in found:
        if bool(f.style & 1) == want_bold:
            return f
    return found[0] if found else None


class Fonts:
    """The fonts of a PDF: sans-serif in four styles, monospace in two, fallbacks for what they lack."""

    def __init__(self):
        self.sans = {k: self._first(v, "bold" in k, "italic" in k) for k, v in SANS.items()}
        self.mono = {k: self._first(v, k == "bold", False) for k, v in MONO.items()}
        self.sans = {k: v or self.sans["regular"] for k, v in self.sans.items()}
        self.mono = {k: v or self.mono["regular"] for k, v in self.mono.items()}
        self._fallbacks = None
        self.missing = 0

    @staticmethod
    def _first(paths, bold, italic):
        for p in paths:
            if os.path.exists(p):
                f = load(p, bold, italic)
                if f:
                    return f
        return None

    def ok(self):
        return self.sans["regular"] is not None and self.mono["regular"] is not None

    def get(self, mono=False, bold=False, italic=False):
        if mono:
            return self.mono["bold" if bold else "regular"]
        return self.sans[("bold" if bold else "") + ("italic" if italic else "") or "regular"]

    def fallbacks(self):
        if self._fallbacks is None:
            self._fallbacks = []
            for p in FALLBACK:
                if os.path.exists(p):
                    f = load(p)
                    if f:
                        self._fallbacks.append(f)
        return self._fallbacks

    def shape(self, text, font):
        """text in font → [(font, [(glyph, character), …]), …] – characters the font lacks from a fallback font,
        else as "?"."""
        out = []
        for ch in text:
            f, g = font, font.gid(ch)
            if not g and ch in "\u200b\u200c\u200d\u2060\ufeff\u00ad\ufe0f":
                continue                        # invisible characters the font does not have: left out
            if not g:
                for alt in self.fallbacks():
                    ag = alt.gid(ch)
                    if ag:
                        f, g = alt, ag
                        break
                else:
                    self.missing += 1
                    g = font.gid("?")
            if out and out[-1][0] is f:
                out[-1][1].append((g, ch))
            else:
                out.append((f, [(g, ch)]))
        return out
