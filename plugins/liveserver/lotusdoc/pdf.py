"""PDF, written by hand (PDF 1.7) – A4 pages with the code, its colors and the number of each line, or a page's
headings, text, lists, tables and images. The fonts are embedded as subsets (fonts.py), links can be clicked, and
every page has a footer with the file and the page. Without any font file it falls back to PDF's own Courier.
"""
import datetime
import hashlib
import re
import struct
import zlib
from collections import namedtuple
from urllib.parse import quote

from . import fonts as fontlib
from .highlight import COLORS, TEXT_COLOR
from .model import B, I, U, S, CODE, MARK, SUP, SUB, Run, Heading, Para, Item, Table, Image, Rule, Code
from .page import as_png

W, H = 595.28, 841.89                   # A4 in points
GRAY, LINK, RULE, HEAD_FILL = "6E6E6E", "0563C1", "BFBFBF", "F2F2F2"
CODE_FILL, INLINE_FILL, MARK_FILL, NUMBER = "F6F8FA", "EDEDED", "FFF176", "A0A0A0"
HEADING_SIZE = {1: 19, 2: 15.5, 3: 13, 4: 11.5, 5: 10.5, 6: 10.5}
_WORDS = re.compile(r" +|[^ ]+")

Style = namedtuple("Style", "size color flags link rise")


def _rgb(c):
    return " ".join(_n(int(c[i:i + 2], 16) / 255) for i in (0, 2, 4))


def _n(x):
    s = f"{x:.3f}".rstrip("0").rstrip(".")
    return s if s not in ("-0", "") else "0"


class Base14:
    """PDF's own Courier, for a Mac without font files: Windows-1252 characters only."""
    upem, fixed, simple, italic_angle, style = 1000, True, True, 0, 0
    name, ascent, descent, cap, bbox = "Courier", 629, -157, 562, [-23, -250, 715, 805]

    def __init__(self):
        self.advance = [600] * 256

    def gid(self, ch):
        try:
            b = ch.encode("cp1252")
        except UnicodeEncodeError:
            return 0
        return b[0] if len(b) == 1 and b[0] >= 32 else 0


class Courier(fontlib.Fonts):
    def __init__(self):
        c = Base14()
        self.sans = {k: c for k in ("regular", "bold", "italic", "bolditalic")}
        self.mono = {"regular": c, "bold": c}
        self._fallbacks, self.missing = [], 0


class Page:
    def __init__(self):
        self.ops, self.links = [], []


# ── Images: JPEG as it is, PNG with its transparency ──────────

def _png(data):
    """The parts of a PNG → dict, None when it is not one."""
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    pos, info, idat = 8, {"palette": b"", "trns": b""}, []
    while pos + 8 <= len(data):
        length, kind = struct.unpack_from(">I4s", data, pos)
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            info["w"], info["h"], info["depth"], info["type"], _, _, info["interlace"] = struct.unpack(">IIBBBBB", body[:13])
        elif kind == b"PLTE":
            info["palette"] = body
        elif kind == b"tRNS":
            info["trns"] = body
        elif kind == b"IDAT":
            idat.append(body)
        elif kind == b"IEND":
            break
        pos += 12 + length
    info["idat"] = b"".join(idat)
    return info if "w" in info and info["idat"] else None


def _unfilter(raw, w, h, bpp):
    stride = w * bpp
    out = bytearray(stride * h)
    prev = bytearray(stride)
    pos = 0
    for y in range(h):
        kind = raw[pos]
        line = bytearray(raw[pos + 1:pos + 1 + stride])
        pos += 1 + stride
        if kind == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 255
        elif kind == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif kind == 3:
            for i in range(stride):
                line[i] = (line[i] + (((line[i - bpp] if i >= bpp else 0) + prev[i]) >> 1)) & 255
        elif kind == 4:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return out


PdfImage = namedtuple("PdfImage", "w h space bits filter data parms smask")


def pdf_image(data, kind):
    """An image as the PDF needs it, or None (GIF, interlaced or very large transparent PNGs …)."""
    if kind == "gif":
        data = as_png(data)
        kind = "png" if data else None
    if kind == "jpeg":
        i = 2
        while i + 9 < len(data):
            if data[i] != 0xFF:
                i += 1
                continue
            marker = data[i + 1]
            if marker in (0xD8, 0x01, 0xFF) or 0xD0 <= marker <= 0xD7:
                i += 1 if marker == 0xFF else 2
                continue
            if marker in (0xC0, 0xC1, 0xC2):
                h, w = struct.unpack(">HH", data[i + 5:i + 9])
                comps = data[i + 9]
                space = {1: "/DeviceGray", 3: "/DeviceRGB", 4: "/DeviceCMYK"}.get(comps)
                return PdfImage(w, h, space, 8, "/DCTDecode", data, None, None) if space else None
            i += 2 + struct.unpack(">H", data[i + 2:i + 4])[0]
        return None
    if kind != "png":
        return None
    p = _png(data)
    if not p or p["interlace"]:
        return None
    w, h, depth, ctype = p["w"], p["h"], p["depth"], p["type"]
    palette = p["palette"]
    indexed = f"[/Indexed /DeviceRGB {len(palette) // 3 - 1} <{palette.hex()}>]" if palette else ""
    alpha = ctype in (4, 6) or (ctype == 3 and p["trns"] and depth == 8)
    if not alpha:
        if ctype not in (0, 2, 3) or (ctype == 3 and not palette):
            return None
        colors = 3 if ctype == 2 else 1
        space = {0: "/DeviceGray", 2: "/DeviceRGB", 3: indexed}[ctype]
        parms = f"<< /Predictor 15 /Colors {colors} /BitsPerComponent {depth} /Columns {w} >>"
        return PdfImage(w, h, space, depth, "/FlateDecode", p["idat"], parms, None)
    if depth not in (8, 16):
        return None
    channels = {4: 2, 6: 4, 3: 1}[ctype]
    bpp = channels * depth // 8
    if w * h * bpp > 12_000_000:
        return None                       # too large to unpack here
    try:
        pixels = _unfilter(zlib.decompress(p["idat"]), w, h, bpp)
    except (zlib.error, IndexError):
        return None
    if depth == 16:
        pixels = pixels[0::2]
    if ctype == 3:
        trns = p["trns"]
        table = bytes(trns[i] if i < len(trns) else 255 for i in range(256))
        return PdfImage(w, h, indexed, 8, "/FlateDecode", zlib.compress(bytes(pixels)), None, zlib.compress(bytes(pixels).translate(table)))
    if ctype == 4:
        return PdfImage(w, h, "/DeviceGray", 8, "/FlateDecode", zlib.compress(bytes(pixels[0::2])), None, zlib.compress(bytes(pixels[1::2])))
    rgb = bytearray(w * h * 3)
    rgb[0::3], rgb[1::3], rgb[2::3] = pixels[0::4], pixels[1::4], pixels[2::4]
    return PdfImage(w, h, "/DeviceRGB", 8, "/FlateDecode", zlib.compress(bytes(rgb)), None, zlib.compress(bytes(pixels[3::4])))


def fit(w, h, max_w, max_h):
    k = min(1.0, max_w / w if w else 1, max_h / h if h else 1)
    return w * k, h * k


# ── Laying out the pages ──────────────────────────────────────

class Layout:
    def __init__(self, fonts, doc):
        self.fonts, self.doc = fonts, doc
        if doc.kind == "code":
            self.left, self.right, self.top, self.bottom = 42.5, 42.5, 48, 56
        else:
            self.left, self.right, self.top, self.bottom = 70.9, 56.7, 56.7, 60
        self.width = W - self.left - self.right
        self.pages, self.images = [], {}
        self.styles = {}
        self.new_page()

    def new_page(self):
        self.page = Page()
        self.pages.append(self.page)
        self.y = H - self.top

    def at_top(self):
        return self.y >= H - self.top - 0.5

    def room(self, h):
        """Make sure there are h points left on the page – else go on on the next one."""
        if self.y - h < self.bottom and not self.at_top():
            self.new_page()
            return True
        return False

    def style(self, size, color, flags, link=None):
        key = (size, color, flags, link)
        st = self.styles.get(key)
        if st is None:
            small = flags & (SUP | SUB)
            st = Style(size * 0.72 if small else size, LINK if link else color, flags, link,
                       size * 0.34 if flags & SUP else -size * 0.12 if flags & SUB else 0)
            self.styles[key] = st
        return st

    def items(self, text, font, st):
        """Glyphs of text: [(font, glyph, character, width, style)]."""
        out = []
        for f, glyphs in self.fonts.shape(text, font):
            k = st.size / f.upem
            out += [(f, g, ch, f.advance[g] * k, st) for g, ch in glyphs]
        return out

    def font(self, flags):
        return self.fonts.get(mono=bool(flags & CODE), bold=bool(flags & B), italic=bool(flags & I))

    # one line of glyphs: backgrounds, the text, lines under and through it, links
    def draw(self, line, x, base):
        pos, cx = [], x
        for it in line:
            pos.append(cx)
            cx += it[3]
        spans = []
        for it, px in zip(line, pos):
            if spans and spans[-1][0] is it[4]:
                spans[-1][2] = px + it[3]
            else:
                spans.append([it[4], px, px + it[3]])
        for st, x0, x1 in spans:
            if st.flags & MARK:
                self.page.ops.append(("rect", x0, base - st.size * 0.24, x1 - x0, st.size * 1.08, MARK_FILL))
            elif st.flags & CODE and self.doc.kind == "page":
                self.page.ops.append(("rect", x0 - 1, base - st.size * 0.24, x1 - x0 + 2, st.size * 1.08, INLINE_FILL))
        i = 0
        while i < len(line):
            j = i
            while j < len(line) and line[j][0] is line[i][0] and line[j][4] is line[i][4]:
                j += 1
            st = line[i][4]
            self.page.ops.append(("text", pos[i], base + st.rise, line[i][0], st.size, st.color, [(g, ch) for _, g, ch, _, _ in line[i:j]]))
            i = j
        for st, x0, x1 in spans:
            if st.flags & U or st.link:
                self.page.ops.append(("line", x0, base - st.size * 0.12, x1, base - st.size * 0.12, st.size * 0.06, st.color))
            if st.flags & S:
                self.page.ops.append(("line", x0, base + st.size * 0.28, x1, base + st.size * 0.28, st.size * 0.06, st.color))
            if st.link:
                self.page.links.append((x0, base - st.size * 0.25, x1, base + st.size * 0.85, st.link))
        return cx

    # text that flows: words, spaces and <br> into lines of a width
    def lines(self, runs, width, size, color=TEXT_COLOR, flags=0):
        words = []
        for r in runs:
            if r.text == "\n":
                words.append(("br", None))
                continue
            f = flags | r.flags
            st = self.style(size, color, f, r.link)
            font = self.font(f)
            for m in _WORDS.finditer(r.text):
                t = m.group()
                kind = "sp" if t[0] == " " else "w"
                its = self.items(" " if kind == "sp" else t, font, st)
                if kind == "w" and words and words[-1][0] == "w":
                    words[-1] = ("w", words[-1][1] + its)
                else:
                    words.append((kind, its))
        out, cur, cw, space = [], [], 0.0, None
        for kind, its in words:
            if kind == "br":
                out.append(cur)
                cur, cw, space = [], 0.0, None
                continue
            if kind == "sp":
                if cur:
                    space = its
                continue
            ww = sum(it[3] for it in its)
            sw = sum(it[3] for it in space) if space and cur else 0
            if cur and cw + sw + ww > width:
                out.append(cur)
                cur, cw, sw = [], 0.0, 0
            if sw:
                cur += space
                cw += sw
            space = None
            if ww > width:
                for it in its:
                    if cur and cw + it[3] > width:
                        out.append(cur)
                        cur, cw = [], 0.0
                    cur.append(it)
                    cw += it[3]
            else:
                cur += its
                cw += ww
        if cur or not out:
            out.append(cur)
        return out

    def flow(self, runs, x, width, size, color=TEXT_COLOR, flags=0, lead=1.38, after=6.0, marker="", bar=None):
        for n, line in enumerate(self.lines(runs, width, size, color, flags)):
            lh = max([it[4].size for it in line] + [size]) * lead
            self.room(lh)
            base = self.y - (lh - size) / 2 - size * 0.8
            if n == 0 and marker:
                mk = self.items(marker, self.font(flags), self.style(size, color, flags))
                self.draw(mk, x - 5 - sum(it[3] for it in mk), base)
            self.draw(line, x, base)
            if bar is not None:
                self.page.ops.append(("line", bar, self.y, bar, self.y - lh, 1.5, "D0D0D0"))
            self.y -= lh
        self.y -= after

    @staticmethod
    def rows(items, avail):
        """A line of code into rows that fit avail – after a space when there is one close by, else anywhere."""
        if sum(it[3] for it in items) <= avail:
            return [items]
        rows, start, x, space, i = [], 0, 0.0, -1, 0
        while i < len(items):
            w = items[i][3]
            if x + w > avail and i > start:
                cut = space + 1 if start <= space < i - 1 and i - space < 30 else i
                rows.append(items[start:cut])
                start, space = cut, -1
                x = sum(it[3] for it in items[start:i])
                continue
            if items[i][2] == " ":
                space = i
            x += w
            i += 1
        rows.append(items[start:])
        return rows

    def code_line(self, line, font, size):
        out = []
        for kind, text in line:
            st = self.style(size, COLORS.get(kind, TEXT_COLOR), 0)
            out += self.items(text, font, st)
        return out

    # ── the two kinds of document

    def code(self):
        doc = self.doc
        bold, regular, mono = self.fonts.get(bold=True), self.fonts.get(), self.fonts.get(mono=True)
        self.y -= 4
        self.draw(self.items(doc.title, bold, self.style(15, TEXT_COLOR, B)), self.left, self.y - 12)
        self.y -= 22
        if doc.meta:
            self.draw(self.items(doc.meta, regular, self.style(8.5, GRAY, 0)), self.left, self.y - 7)
            self.y -= 15
        self.page.ops.append(("line", self.left, self.y, W - self.right, self.y, 0.5, "D9D9D9"))
        self.y -= 12
        size, lead, nsize = 8.5, 11.4, 7.2
        code_x = self.left + 32
        avail = W - self.right - code_x
        nstyle = self.style(nsize, NUMBER, 0)
        for block in doc.blocks:
            if not isinstance(block, Code):
                continue
            for n, line in enumerate(block.lines, 1):
                for r, row in enumerate(self.rows(self.code_line(line, mono, size), avail)):
                    self.room(lead)
                    base = self.y - lead + (lead - size) / 2 + size * 0.22
                    if r == 0:
                        num = self.items(str(n), mono, nstyle)
                        self.draw(num, code_x - 7 - sum(it[3] for it in num), base)
                    self.draw(row, code_x, base)
                    self.y -= lead

    def page_doc(self):
        for b in self.doc.blocks:
            if isinstance(b, Heading):
                size = HEADING_SIZE[b.level]
                if not self.at_top():
                    self.y -= 14 if b.level < 3 else 9
                self.room(size * 1.3 + 34)           # a heading stays with what follows it
                self.flow(b.runs, self.left, self.width, size, "1F1F1F", B | (I if b.level == 6 else 0), lead=1.25, after=5)
            elif isinstance(b, Para):
                if b.style == "quote":
                    self.flow(b.runs, self.left + 16, self.width - 16, 10.5, "404040", I, after=7, bar=self.left + 4)
                elif b.style == "caption":
                    self.flow(b.runs, self.left, self.width, 8.5, GRAY, I, after=9)
                elif b.style == "term":
                    self.room(30)
                    self.flow(b.runs, self.left, self.width, 10.5, TEXT_COLOR, B, after=2)
                else:
                    indent = 24 * b.indent
                    self.flow(b.runs, self.left + indent, self.width - indent, 10.5, GRAY if b.style == "meta" else TEXT_COLOR, after=7)
            elif isinstance(b, Item):
                x = self.left + 18 * (b.level + 1)
                self.flow(b.runs, x, self.left + self.width - x, 10.5, after=3, marker=b.marker)
            elif isinstance(b, Table):
                self.table(b)
            elif isinstance(b, Image):
                self.image(b)
            elif isinstance(b, Rule):
                self.room(16)
                self.y -= 6
                self.page.ops.append(("line", self.left, self.y, W - self.right, self.y, 0.75, RULE))
                self.y -= 10
            elif isinstance(b, Code):
                self.code_block(b)

    def code_block(self, block):
        mono = self.fonts.get(mono=True)
        size, lead, pad = 8.5, 11, 5
        avail = self.width - 2 * pad
        self.room(lead + pad)
        self.page.ops.append(("rect", self.left, self.y - pad, self.width, pad, CODE_FILL))
        self.y -= pad
        for line in block.lines:
            for row in self.rows(self.code_line(line, mono, size), avail):
                self.room(lead)
                self.page.ops.append(("rect", self.left, self.y - lead, self.width, lead, CODE_FILL))
                self.draw(row, self.left + pad, self.y - lead + (lead - size) / 2 + size * 0.22)
                self.y -= lead
        self.page.ops.append(("rect", self.left, self.y - pad, self.width, pad, CODE_FILL))
        self.y -= pad + 8

    def measure(self, runs, size, flags):
        """(the widest word, all of it in one line) of runs, in points."""
        missing = self.fonts.missing
        widest = total = word = 0.0
        for r in runs:
            if r.text == "\n":
                widest, word = max(widest, word), 0.0
                continue
            f = flags | r.flags
            st, font = self.style(size, TEXT_COLOR, f, r.link), self.font(f)
            for m in _WORDS.finditer(r.text):
                t = m.group()
                w = sum(it[3] for it in self.items(" " if t[0] == " " else t, font, st))
                total += w
                if t[0] == " ":
                    widest, word = max(widest, word), 0.0
                else:
                    word += w
        self.fonts.missing = missing        # measuring is not drawing: what is missing is counted once
        return max(widest, word), total

    def table(self, t):
        """Columns as wide as their content wants (like a browser): never narrower than their widest word – and
        when even that does not fit, a smaller font, down to 6 points."""
        cols = len(t.rows[0])
        size, lead, pad = 9.5, 1.3, 4
        while True:
            mins, maxs = [2 * pad] * cols, [2 * pad] * cols
            for r, row in enumerate(t.rows):
                for c, cell in enumerate(row):
                    least, most = self.measure(cell, size, B if r < t.header else 0)
                    mins[c] = max(mins[c], least + 2 * pad + 0.5)
                    maxs[c] = max(maxs[c], most + 2 * pad + 0.5)
            if sum(mins) <= self.width or size <= 6:
                break
            size = max(6.0, size * self.width / sum(mins) * 0.98)
            pad = max(2.0, 4 * size / 9.5)
        if sum(maxs) <= self.width:
            widths = [m * self.width / sum(maxs) for m in maxs]
        elif sum(mins) <= self.width:
            flex = [b - a for a, b in zip(mins, maxs)]
            extra = self.width - sum(mins)
            widths = [a + (extra * f / sum(flex) if sum(flex) else extra / cols) for a, f in zip(mins, flex)]
        else:
            widths = [m * self.width / sum(mins) for m in mins]
        rows = []
        for r, row in enumerate(t.rows):
            head = r < t.header
            cells = [self.lines(cell, widths[c] - 2 * pad, size, TEXT_COLOR, B if head else 0) for c, cell in enumerate(row)]
            height = max(len(lines) for lines in cells) * size * lead + 2 * pad
            rows.append((cells, height, head))
        self.y -= 2
        for cells, height, head in rows:
            if self.room(height) and not head:
                for hc, hh, _ in rows[:t.header]:
                    self.row(hc, hh, widths, True, size, lead, pad)
            self.row(cells, height, widths, head, size, lead, pad)
        self.y -= 10

    def row(self, cells, height, widths, head, size, lead, pad):
        top, x = self.y, self.left
        for c, lines in enumerate(cells):
            if head:
                self.page.ops.append(("rect", x, top - height, widths[c], height, HEAD_FILL))
            ly = top - pad
            for line in lines:
                lh = size * lead
                self.draw(line, x + pad, ly - (lh - size) / 2 - size * 0.8)
                ly -= lh
            x += widths[c]
        right = self.left + sum(widths)
        for y in (top, top - height):
            self.page.ops.append(("line", self.left, y, right, y, 0.5, RULE))
        x = self.left
        for w in [0] + widths:
            x += w
            self.page.ops.append(("line", x, top, x, top - height, 0.5, RULE))
        self.y -= height

    def image(self, img):
        key = id(img.data)
        if key not in self.images:
            self.images[key] = pdf_image(img.data, img.kind)
        pi = self.images[key]
        if pi is None:
            self.flow([Run(f"[Image: {img.alt}]" if img.alt else "[Image]", I, None)], self.left, self.width, 10.5, GRAY)
            return
        w, h = fit(img.width * 0.75, img.height * 0.75, self.width, (H - self.top - self.bottom) * 0.85)
        self.room(h + 10)
        self.y -= 4
        self.page.ops.append(("image", self.left, self.y - h, w, h, key))
        self.y -= h + 6

    def footers(self, title):
        regular = self.fonts.get()
        st = self.style(7.5, GRAY, 0)
        total = len(self.pages)
        for n, page in enumerate(self.pages, 1):
            self.page = page
            self.draw(self.items(title, regular, st), self.left, 30)
            num = self.items(f"{n} / {total}", regular, st)
            self.draw(num, W - self.right - sum(it[3] for it in num), 30)


# ── Writing the file ──────────────────────────────────────────

def _pdf_text(s):
    """A string for the document's info: UTF-16 with its byte order mark, in hex."""
    return "<FEFF" + s.encode("utf-16-be").hex().upper() + ">"


def _literal(s):
    return "(" + s.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)") + ")"


class _Objects:
    def __init__(self):
        self.objs = [None]

    def reserve(self):
        self.objs.append(None)
        return len(self.objs) - 1

    def add(self, body, n=None):
        if n is None:
            n = self.reserve()
        self.objs[n] = body if isinstance(body, bytes) else body.encode("latin-1")
        return n

    def stream(self, entries, data, compress=True, n=None):
        if compress:
            data = zlib.compress(data, 9)
            entries += " /Filter /FlateDecode"
        return self.add(f"<< {entries} /Length {len(data)} >>\nstream\n".encode("latin-1") + data + b"\nendstream", n)

    def bytes(self, root, info, ident):
        out = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
        offsets = []
        for i in range(1, len(self.objs)):
            offsets.append(len(out))
            out += f"{i} 0 obj\n".encode("latin-1") + self.objs[i] + b"\nendobj\n"
        xref = len(out)
        out += f"xref\n0 {len(self.objs)}\n0000000000 65535 f \n".encode("latin-1")
        out += "".join(f"{o:010d} 00000 n \n" for o in offsets).encode("latin-1")
        out += (f"trailer\n<< /Size {len(self.objs)} /Root {root} 0 R /Info {info} 0 R /ID [<{ident}> <{ident}>] >>\n"
                f"startxref\n{xref}\n%%EOF\n").encode("latin-1")
        return bytes(out)


def _tounicode(pairs):
    lines = ["/CIDInit /ProcSet findresource begin", "12 dict begin", "begincmap",
             "/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def",
             "/CMapName /Adobe-Identity-UCS def", "/CMapType 2 def", "1 begincodespacerange", "<0000> <FFFF>", "endcodespacerange"]
    pairs = sorted(pairs)
    for i in range(0, len(pairs), 100):
        chunk = pairs[i:i + 100]
        lines.append(f"{len(chunk)} beginbfchar")
        lines += [f"<{cid:04X}> <{ch.encode('utf-16-be').hex().upper()}>" for cid, ch in chunk]
        lines.append("endbfchar")
    lines += ["endcmap", "CMapName currentdict /CMap defineresource pop", "end", "end"]
    return "\n".join(lines).encode("latin-1")


def _font(objs, font, used):
    """The PDF objects of a font: a subset with the glyphs used (CIDFontType2), or PDF's own Courier."""
    if getattr(font, "simple", False):
        return objs.add("<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>"), {g: g for g in used}
    chars = {}
    for g, ch in used.items():
        chars.setdefault(ch, g)
    sfnt, new = font.subset(set(used), chars)
    tag = "".join(chr(65 + b % 26) for b in hashlib.md5(sfnt).digest()[:6])
    base = f"{tag}+{font.name}"
    k = 1000.0 / font.upem
    file = objs.stream(f"/Length1 {len(sfnt)}", sfnt)
    flags = 32 | (1 if font.fixed else 0) | (64 if font.italic_angle or font.style & 2 else 0)
    bbox = " ".join(str(round(v * k)) for v in font.bbox)
    desc = objs.add(f"<< /Type /FontDescriptor /FontName /{base} /Flags {flags} /FontBBox [{bbox}] "
                    f"/ItalicAngle {_n(font.italic_angle)} /Ascent {round(font.ascent * k)} /Descent {round(font.descent * k)} "
                    f"/CapHeight {round(font.cap * k)} /StemV {120 if font.weight >= 600 else 80} /FontFile2 {file} 0 R >>")
    order = sorted(new, key=new.get)
    widths = " ".join(str(round(font.advance[g] * k)) for g in order)
    cid = objs.add(f"<< /Type /Font /Subtype /CIDFontType2 /BaseFont /{base} "
                   "/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> "
                   f"/FontDescriptor {desc} 0 R /DW 1000 /W [0 [{widths}]] /CIDToGIDMap /Identity >>")
    to_unicode = objs.stream("", _tounicode([(new[g], ch) for g, ch in used.items() if g in new and g]))
    return objs.add(f"<< /Type /Font /Subtype /Type0 /BaseFont /{base} /Encoding /Identity-H "
                    f"/DescendantFonts [{cid} 0 R] /ToUnicode {to_unicode} 0 R >>"), new


_FONTS = []


def write_pdf(doc, path, author=""):
    """The document as a PDF → how many characters no font had (shown as ?)."""
    if not _FONTS:                      # loaded once for all the documents of a run
        fonts = fontlib.Fonts()
        _FONTS.append(fonts if fonts.ok() else Courier())
    fonts = _FONTS[0]
    fonts.missing = 0
    lay = Layout(fonts, doc)
    if doc.kind == "code":
        lay.code()
    else:
        lay.page_doc()
    lay.footers(doc.title)

    # which glyphs of which font are used
    used = {}
    for page in lay.pages:
        for op in page.ops:
            if op[0] == "text":
                d = used.setdefault(id(op[3]), (op[3], {}))[1]
                for g, ch in op[6]:
                    d.setdefault(g, ch)
    objs = _Objects()
    catalog, pages_obj = objs.reserve(), objs.reserve()
    font_names, maps, resources_fonts = {}, {}, []
    for i, (key, (font, glyphs)) in enumerate(used.items(), 1):
        n, new = _font(objs, font, glyphs)
        font_names[key], maps[key] = f"F{i}", new
        resources_fonts.append(f"/F{i} {n} 0 R")
    image_names, resources_images = {}, []
    for key, pi in lay.images.items():
        if pi is None:
            continue
        smask = ""
        if pi.smask:
            m = objs.stream(f"/Type /XObject /Subtype /Image /Width {pi.w} /Height {pi.h} /ColorSpace /DeviceGray "
                            "/BitsPerComponent 8 /Filter /FlateDecode", pi.smask, compress=False)
            smask = f" /SMask {m} 0 R"
        parms = f" /DecodeParms {pi.parms}" if pi.parms else ""
        n = objs.stream(f"/Type /XObject /Subtype /Image /Width {pi.w} /Height {pi.h} /ColorSpace {pi.space} "
                        f"/BitsPerComponent {pi.bits} /Filter {pi.filter}{parms}{smask}", pi.data, compress=False)
        image_names[key] = f"Im{len(image_names) + 1}"
        resources_images.append(f"/{image_names[key]} {n} 0 R")
    resources = objs.add(f"<< /Font << {' '.join(resources_fonts)} >> /XObject << {' '.join(resources_images)} >> "
                         "/ProcSet [/PDF /Text /ImageB /ImageC /ImageI] >>")
    kids = []
    for page in lay.pages:
        out = []
        for op in page.ops:
            if op[0] == "text":
                _, x, y, font, size, color, glyphs = op
                key = id(font)
                if getattr(font, "simple", False):
                    hexed = "".join(f"{g:02X}" for g, _ in glyphs)
                else:
                    hexed = "".join(f"{maps[key].get(g, 0):04X}" for g, _ in glyphs)
                out.append(f"BT /{font_names[key]} {_n(size)} Tf {_rgb(color)} rg 1 0 0 1 {_n(x)} {_n(y)} Tm <{hexed}> Tj ET")
            elif op[0] == "rect":
                _, x, y, w, h, color = op
                out.append(f"{_rgb(color)} rg {_n(x)} {_n(y)} {_n(w)} {_n(h)} re f")
            elif op[0] == "line":
                _, x1, y1, x2, y2, width, color = op
                out.append(f"{_rgb(color)} RG {_n(width)} w {_n(x1)} {_n(y1)} m {_n(x2)} {_n(y2)} l S")
            elif op[0] == "image" and op[5] in image_names:
                _, x, y, w, h, key = op
                out.append(f"q {_n(w)} 0 0 {_n(h)} {_n(x)} {_n(y)} cm /{image_names[key]} Do Q")
        content = objs.stream("", "\n".join(out).encode("latin-1"))
        annots = []
        for x1, y1, x2, y2, url in page.links:
            target = quote(url, safe=":/?#[]@!$&'()*+,;=%~-._")
            annots.append(objs.add(f"<< /Type /Annot /Subtype /Link /Rect [{_n(x1)} {_n(y1)} {_n(x2)} {_n(y2)}] /Border [0 0 0] "
                                   f"/A << /S /URI /URI {_literal(target)} >> >>"))
        links = f" /Annots [{' '.join(f'{a} 0 R' for a in annots)}]" if annots else ""
        kids.append(objs.add(f"<< /Type /Page /Parent {pages_obj} 0 R /MediaBox [0 0 {_n(W)} {_n(H)}] "
                             f"/Resources {resources} 0 R /Contents {content} 0 R{links} >>"))
    objs.add(f"<< /Type /Pages /Kids [{' '.join(f'{k} 0 R' for k in kids)}] /Count {len(kids)} >>", pages_obj)
    lang = (doc.lang or "en").replace("_", "-")
    objs.add(f"<< /Type /Catalog /Pages {pages_obj} 0 R /Lang {_literal(lang)} /ViewerPreferences << /DisplayDocTitle true >> >>", catalog)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("D:%Y%m%d%H%M%SZ")
    title = doc.meta if doc.kind == "page" and doc.meta else doc.title
    who = f" /Author {_pdf_text(author)}" if author else ""
    info = objs.add(f"<< /Title {_pdf_text(title)}{who} /Producer (Lotus) /Creator (Lotus /html) /CreationDate ({stamp}) >>")
    ident = hashlib.md5((path + stamp + title).encode("utf-8", "replace")).hexdigest()
    with open(path, "wb") as f:
        f.write(objs.bytes(catalog, info, ident))
    return fonts.missing
