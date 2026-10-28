"""A web page as a document: what a visitor reads – headings, paragraphs, lists, tables, images, links and code –
without its scripts, styles and what is hidden. html.parser reads the page into a small tree (adding the end tags
HTML may leave out), then the tree becomes the blocks of model.py. Images come from the folder only (or are in the
page as data: URLs); nothing is loaded from the internet.
"""
import base64
import os
import re
import shutil
import struct
import subprocess
import tempfile
from html.parser import HTMLParser
from urllib.parse import unquote, urlsplit

from . import highlight
from .model import B, I, U, S, CODE, MARK, SUP, SUB, Run, Heading, Para, Item, Table, Image, Rule, Code, Document, merge, plain

VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr", "keygen"}
CLOSES_P = {"address", "article", "aside", "blockquote", "details", "dialog", "div", "dl", "fieldset", "figcaption", "figure",
            "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hgroup", "hr", "main", "menu", "nav", "ol", "p",
            "pre", "section", "table", "ul", "search"}
SCOPE = {"html", "table", "td", "th", "caption", "template", "button", "object", "marquee", "applet"}
HEADINGS = {"h1", "h2", "h3", "h4", "h5", "h6"}

# What a visitor does not read: left out with everything in it
SKIP = {"head", "script", "style", "template", "noscript", "svg", "math", "canvas", "iframe", "object", "embed", "video",
        "audio", "map", "select", "datalist", "input", "textarea", "meta", "link", "base", "title", "param", "source", "track"}
INLINE = {"b": B, "strong": B, "i": I, "em": I, "cite": I, "dfn": I, "var": I, "u": U, "ins": U, "s": S, "strike": S,
          "del": S, "code": CODE, "kbd": CODE, "samp": CODE, "tt": CODE, "mark": MARK, "sup": SUP, "sub": SUB}
BLOCKS = {"html", "body", "main", "article", "section", "div", "header", "footer", "nav", "aside", "address", "form",
          "fieldset", "details", "summary", "hgroup", "center", "search", "figure", "dialog", "legend", "p", "caption",
          "figcaption", "blockquote", "dl", "dt", "dd", "ul", "ol", "menu", "table", "pre", "hr", "li", "listing", "xmp",
          "h1", "h2", "h3", "h4", "h5", "h6", "img", "picture"}
BULLETS = ("•", "◦", "▪")
MAX_IMAGE = 20 * 1024 * 1024
SIPS = "/usr/bin/sips"


class Node:
    __slots__ = ("tag", "attrs", "children", "parent")

    def __init__(self, tag, attrs, parent):
        self.tag, self.attrs, self.children, self.parent = tag, attrs, [], parent


class _Tree(HTMLParser):
    """The page as a tree of Nodes, the way a browser closes what the page leaves open (<p>, <li>, <td> …)."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = Node("#root", {}, None)
        self.stack = [self.root]

    def _close_to(self, tags, stop):
        """Close the nearest open element named in tags – unless one of stop comes first."""
        for i in range(len(self.stack) - 1, 0, -1):
            tag = self.stack[i].tag
            if tag in tags:
                del self.stack[i:]
                return
            if tag in stop:
                return

    def handle_starttag(self, tag, attrs):
        if tag in CLOSES_P:
            self._close_to({"p"}, SCOPE)
        if tag == "li":
            self._close_to({"li"}, SCOPE | {"ul", "ol", "menu"})
        elif tag in ("dt", "dd"):
            self._close_to({"dt", "dd"}, SCOPE | {"dl"})
        elif tag == "tr":
            self._close_to({"tr"}, {"table", "html", "template"})
        elif tag in ("td", "th"):
            self._close_to({"td", "th"}, {"tr", "table", "html", "template"})
        elif tag in ("thead", "tbody", "tfoot"):
            self._close_to({"thead", "tbody", "tfoot"}, {"table", "html", "template"})
        elif tag in ("option", "optgroup"):
            self._close_to({"option"}, {"select", "datalist", "html"})
        elif tag in HEADINGS and self.stack[-1].tag in HEADINGS:
            self.stack.pop()
        node = Node(tag, {k: (v if v is not None else "") for k, v in attrs}, self.stack[-1])
        self.stack[-1].children.append(node)
        if tag not in VOID:
            self.stack.append(node)

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        if tag not in VOID and self.stack[-1].tag == tag:
            self.stack.pop()

    def handle_endtag(self, tag):
        if tag == "br":
            self.handle_starttag("br", [])
            return
        for i in range(len(self.stack) - 1, 0, -1):
            if self.stack[i].tag == tag:
                del self.stack[i:]
                return

    def handle_data(self, data):
        self.stack[-1].children.append(data)


def tree(source):
    t = _Tree()
    t.feed(source)
    t.close()
    return t.root


# ── Images ────────────────────────────────────────────────────

def image_size(data):
    """(kind, width, height) of a PNG, JPEG or GIF – (None, 0, 0) for anything else."""
    if data[:8] == b"\x89PNG\r\n\x1a\n" and len(data) >= 24:
        w, h = struct.unpack(">II", data[16:24])
        return "png", w, h
    if data[:6] in (b"GIF87a", b"GIF89a") and len(data) >= 10:
        w, h = struct.unpack("<HH", data[6:10])
        return "gif", w, h
    if data[:2] == b"\xff\xd8":
        i = 2
        while i + 9 < len(data):
            if data[i] != 0xFF:
                i += 1
                continue
            marker = data[i + 1]
            if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7 or marker == 0xFF:
                i += 1 if marker == 0xFF else 2
                continue
            length = struct.unpack(">H", data[i + 2:i + 4])[0]
            if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                h, w = struct.unpack(">HH", data[i + 5:i + 9])
                return "jpeg", w, h
            i += 2 + length
    return None, 0, 0


def as_png(data):
    """Other images (WebP, AVIF, HEIC, BMP, TIFF, SVG …) as PNG with macOS' sips – None where there is none."""
    if not os.path.exists(SIPS):
        return None
    folder = tempfile.mkdtemp(prefix="lotus-html-")
    try:
        src, out = os.path.join(folder, "in"), os.path.join(folder, "out.png")
        with open(src, "wb") as f:
            f.write(data)
        subprocess.run([SIPS, "-s", "format", "png", src, "--out", out], capture_output=True, timeout=30)
        if os.path.exists(out):
            with open(out, "rb") as f:
                return f.read()
    except (OSError, subprocess.SubprocessError):
        pass
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    return None


def _px(value):
    m = re.match(r"\s*(\d+(?:\.\d+)?)\s*(px)?\s*$", value or "")
    return float(m.group(1)) if m else 0


# ── The page as blocks ────────────────────────────────────────

_WS = re.compile(r"[ \t\n\r\f]+")


def collapse(runs):
    """Spaces the way a browser shows them: runs of white space are one space, none at the start or end of a line."""
    out, space = [], True
    for r in runs:
        if r.text == "\n":
            if out and out[-1].text.endswith(" "):
                out[-1] = out[-1]._replace(text=out[-1].text.rstrip(" "))
            out.append(r)
            space = True
            continue
        t = highlight.visible(_WS.sub(" ", r.text)).replace("\u00ad", "").replace("\u200b", "")
        if space:
            t = t.lstrip(" ")
        if not t:
            continue
        space = t.endswith(" ")
        out.append(r._replace(text=t))
    while out and (out[-1].text == "\n" or not out[-1].text.strip(" ")):
        out.pop()
    if out:
        out[-1] = out[-1]._replace(text=out[-1].text.rstrip(" "))
    return merge(out)


def _hidden(node):
    a = node.attrs
    if "hidden" in a or a.get("aria-hidden", "").lower() == "true" or a.get("type", "").lower() == "hidden":
        return True
    style = a.get("style", "").replace(" ", "").lower()
    return "display:none" in style or "visibility:hidden" in style


def _style_flags(node):
    style = node.attrs.get("style", "").replace(" ", "").lower()
    if not style:
        return 0
    flags = 0
    m = re.search(r"font-weight:(\w+)", style)
    if m and (m.group(1) in ("bold", "bolder") or (m.group(1).isdigit() and int(m.group(1)) >= 600)):
        flags |= B
    if "font-style:italic" in style or "font-style:oblique" in style:
        flags |= I
    if re.search(r"text-decoration(-line)?:[^;]*underline", style):
        flags |= U
    if re.search(r"text-decoration(-line)?:[^;]*line-through", style):
        flags |= S
    return flags


def _marker(n, kind):
    if kind in ("a", "A"):
        s = ""
        while n > 0:
            n, r = divmod(n - 1, 26)
            s = chr(97 + r) + s
        return (s.upper() if kind == "A" else s or "a") + "."
    if kind in ("i", "I") and 0 < n < 4000:
        s = ""
        for value, letters in ((1000, "m"), (900, "cm"), (500, "d"), (400, "cd"), (100, "c"), (90, "xc"), (50, "l"),
                               (40, "xl"), (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i")):
            while n >= value:
                s += letters
                n -= value
        return (s.upper() if kind == "I" else s) + "."
    return f"{n}."


def _text_of(node):
    """All the text in a node as it is written (for <pre>): <br> is a line break."""
    out = []
    for c in node.children:
        if isinstance(c, str):
            out.append(c)
        elif c.tag == "br":
            out.append("\n")
        elif c.tag not in ("script", "style", "template"):
            out.append(_text_of(c))
    return "".join(out)


def _code_lang(node):
    for n in [node] + [c for c in node.children if not isinstance(c, str)]:
        for cls in n.attrs.get("class", "").split():
            m = re.match(r"(?:language|lang)-(\w+)", cls)
            if m:
                name = m.group(1).lower()
                return {"javascript": "js", "typescript": "ts", "xml": "html", "svg": "html", "less": "scss",
                        "sass": "scss"}.get(name, name if name in highlight.NAMES else "text")
    return "text"


class Renderer:
    def __init__(self, root, page_dir, images=True):
        self.root, self.page_dir, self.images = root, page_dir, images
        self.blocks, self.runs = [], []
        self.style, self.indent = "normal", 0
        self.item = None                # (level, marker) while inside a list item; marker "" once it is used
        self.lists = 0
        self.title, self.lang = "", ""

    # the paragraph so far becomes a block
    def flush(self):
        runs = collapse(self.runs)
        self.runs = []
        if not plain(runs).strip():
            return
        if self.item is not None:
            level, marker = self.item
            self.blocks.append(Item(level, marker, runs))
            self.item = (level, "")
        else:
            self.blocks.append(Para(runs, self.style, self.indent))

    def inline(self, node, flags, link):
        """The runs of node's content (for headings and table cells), without touching the paragraph around it."""
        saved, self.runs = self.runs, []
        self.walk(node, flags, link)
        runs, self.runs = self.runs, saved
        return runs

    def walk(self, node, flags=0, link=None):
        for c in node.children:
            if isinstance(c, str):
                self.runs.append(Run(c, flags, link))
            else:
                self.element(c, flags, link)

    def element(self, node, flags, link):
        tag = node.tag
        if tag in SKIP or _hidden(node):
            if tag == "title" and not self.title:
                self.title = " ".join(_text_of(node).split())
            if tag == "head":
                for c in node.children:
                    if not isinstance(c, str) and c.tag == "title" and not self.title:
                        self.title = " ".join(_text_of(c).split())
            return
        if tag == "dialog" and "open" not in node.attrs:
            return
        if tag == "html" and node.attrs.get("lang") and not self.lang:
            self.lang = node.attrs["lang"]
        flags |= INLINE.get(tag, 0) | _style_flags(node)
        if tag == "br":
            self.runs.append(Run("\n", flags, link))
        elif tag == "a":
            href = node.attrs.get("href", "").strip()
            if re.match(r"(?i)(https?:|mailto:|tel:)", href):
                link = href
            self.walk(node, flags, link)
        elif tag == "q":
            self.runs.append(Run("“", flags, link))
            self.walk(node, flags, link)
            self.runs.append(Run("”", flags, link))
        elif tag in HEADINGS:
            self.flush()
            runs = collapse(self.inline(node, flags, link))
            if plain(runs).strip():
                self.blocks.append(Heading(int(tag[1]), runs))
        elif tag in ("ul", "ol", "menu"):
            self.list(node, tag == "ol")
        elif tag == "li":                       # an <li> outside of a list: a list of its own
            self.flush()
            saved, self.item = self.item, (self.lists, BULLETS[self.lists % 3])
            self.walk(node, flags, link)
            self.flush()
            self.item = saved
        elif tag == "table":
            self.table(node)
        elif tag in ("pre", "listing", "xmp"):
            self.flush()
            text = _text_of(node)
            if text.startswith("\n"):
                text = text[1:]
            if text.strip():
                lang = _code_lang(node)
                self.blocks.append(Code(highlight.lines(text, lang), False, lang))
        elif tag == "hr":
            self.flush()
            self.blocks.append(Rule())
        elif tag == "img":
            self.image(node, flags, link)
        elif tag in ("blockquote", "figcaption", "caption", "dt", "dd"):
            self.flush()
            saved = self.style, self.indent
            if tag == "blockquote":
                self.style = "quote"
            elif tag in ("figcaption", "caption"):
                self.style = "caption"
            elif tag == "dt":
                self.style = "term"
            else:
                self.indent += 1
            self.walk(node, flags, link)
            self.flush()
            self.style, self.indent = saved
        elif tag in BLOCKS:
            self.flush()
            self.walk(node, flags, link)
            self.flush()
        else:
            self.walk(node, flags, link)

    def list(self, node, ordered):
        self.flush()
        level = self.lists
        self.lists += 1
        saved = self.item
        kind = node.attrs.get("type", "1") if ordered else ""
        items = [c for c in node.children if not isinstance(c, str) and c.tag == "li" and not _hidden(c)]
        backwards = ordered and "reversed" in node.attrs
        try:
            n = int(node.attrs.get("start", "")) if ordered and node.attrs.get("start") else (len(items) if backwards else 1)
        except ValueError:
            n = 1
        for c in node.children:
            if isinstance(c, str):
                if c.strip():
                    self.runs.append(Run(c, 0, None))
                continue
            if c.tag != "li":
                self.element(c, 0, None)
                continue
            if _hidden(c):
                continue
            if ordered and c.attrs.get("value", "").strip().lstrip("-").isdigit():
                n = int(c.attrs["value"])
            self.flush()
            self.item = (level, _marker(n, kind) if ordered else BULLETS[level % 3])
            self.walk(c, _style_flags(c), None)
            self.flush()
            n += -1 if backwards else 1
        self.flush()
        self.item = saved
        self.lists -= 1

    def cell(self, node):
        """The runs of a table cell: its paragraphs one per line, a nested table row by row."""
        sub = Renderer(self.root, self.page_dir, images=False)
        sub.title = self.title
        sub.walk(node)
        sub.flush()
        runs = []
        for b in sub.blocks:
            if runs:
                runs.append(Run("\n", 0, None))
            if isinstance(b, Item):
                runs += [Run("    " * b.level + (b.marker + " " if b.marker else "  "), 0, None)] + list(b.runs)
            elif isinstance(b, (Para, Heading)):
                runs += list(b.runs)
            elif isinstance(b, Table):
                runs.append(Run("\n".join(" | ".join(plain(c) for c in row) for row in b.rows), 0, None))
            elif isinstance(b, Code):
                runs.append(Run("\n".join("".join(t for _, t in line) for line in b.lines), CODE, None))
            elif isinstance(b, Image):
                runs.append(Run(f"[{b.alt or 'Image'}]", I, None))
        return merge(runs)

    def table(self, node):
        self.flush()
        rows, head = [], []
        caption = None

        def take(section, is_head):
            for c in section.children:
                if isinstance(c, str) or _hidden(c):
                    continue
                if c.tag == "tr":
                    cells = [x for x in c.children if not isinstance(x, str) and x.tag in ("td", "th") and not _hidden(x)]
                    row = []
                    for x in cells:
                        row.append(self.cell(x))
                        try:
                            span = min(int(x.attrs.get("colspan", "1")), 50)
                        except ValueError:
                            span = 1
                        row += [[] for _ in range(span - 1)]
                    if row:
                        rows.append(row)
                        head.append(bool(is_head or all(x.tag == "th" for x in cells)))
                elif c.tag in ("thead", "tbody", "tfoot"):
                    take(c, c.tag == "thead")

        for c in node.children:
            if not isinstance(c, str) and c.tag == "caption":
                caption = c
        take(node, False)
        if caption is not None:
            saved = self.style
            self.style = "caption"
            self.walk(caption)
            self.flush()
            self.style = saved
        if not rows:
            return
        width = max(len(r) for r in rows)
        rows = [r + [[] for _ in range(width - len(r))] for r in rows]
        header = 0
        while header < len(head) and head[header] and header < len(rows) - 1:
            header += 1
        self.blocks.append(Table(rows, header))

    def file(self, src):
        """The file in the folder that src names – "" for data: URLs, the internet and what is outside the folder."""
        url = urlsplit(src.strip())
        if url.scheme or url.netloc or not url.path:
            return ""
        path = unquote(url.path)
        full = os.path.realpath(os.path.join(self.root, path.lstrip("/")) if path.startswith("/") else os.path.join(self.page_dir, path))
        return full if full == self.root or full.startswith(self.root + os.sep) else ""

    def load(self, src):
        """The bytes of an image the page shows – from the folder, or a data: URL – or None."""
        src = src.strip()
        if src.startswith("data:"):
            m = re.match(r"data:([\w/+.-]*)(;[^,]*)?,(.*)$", src, re.S)
            if not m:
                return None
            try:
                if m.group(2) and "base64" in m.group(2):
                    return base64.b64decode(re.sub(r"\s+", "", m.group(3)))
                return unquote(m.group(3)).encode("utf-8")
            except ValueError:
                return None
        full = self.file(src)
        if not full:
            return None                          # on the internet or outside the folder: never loaded
        try:
            if not os.path.isfile(full) or os.path.getsize(full) > MAX_IMAGE:
                return None
            with open(full, "rb") as f:
                return f.read()
        except OSError:
            return None

    def image(self, node, flags, link):
        src = node.attrs.get("src") or node.attrs.get("data-src") or ""
        alt = " ".join(node.attrs.get("alt", "").split())
        name = os.path.basename(unquote(urlsplit(src).path)) if not src.startswith("data:") else ""
        w_attr, h_attr = _px(node.attrs.get("width")), _px(node.attrs.get("height"))
        if (w_attr and w_attr <= 24) or (h_attr and h_attr <= 24):
            if alt:
                self.runs.append(Run(alt, flags, link))       # an icon in the text: its words
            return
        data = self.load(src) if self.images and src else None
        kind, w, h = image_size(data) if data else (None, 0, 0)
        if data and not kind:
            data = as_png(data)
            kind, w, h = image_size(data) if data else (None, 0, 0)
        if not kind or not w or not h:
            label = alt or name
            if label:
                self.runs.append(Run(f"[{label}]", flags | I, link))
            return
        if w_attr and h_attr:
            w, h = w_attr, h_attr
        elif w_attr:
            w, h = w_attr, h * w_attr / w
        elif h_attr:
            w, h = w * h_attr / h, h_attr
        self.flush()
        self.blocks.append(Image(data, kind, w, h, alt or name, self.file(src)))


def document(path, root, title=None):
    """The page at path (in the folder root) as a Document of what a visitor reads."""
    with open(path, "rb") as f:
        source = decode(f.read())
    r = Renderer(os.path.realpath(root), os.path.dirname(os.path.realpath(path)))
    r.walk(tree(source))
    r.flush()
    blocks = [b for b in r.blocks if not (isinstance(b, Para) and not plain(b.runs).strip())]
    return Document(title or os.path.basename(path), blocks, "page", r.title, r.lang or "en")


def decode(data):
    """Text of a file: UTF-8 (with or without BOM), else the encoding the page names, else Windows-1252."""
    if data[:3] == b"\xef\xbb\xbf":
        return data[3:].decode("utf-8", "replace")
    if data[:2] in (b"\xff\xfe", b"\xfe\xff"):
        return data.decode("utf-16", "replace")
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        pass
    m = re.search(rb"""charset\s*=\s*["']?([\w-]+)""", data[:4096], re.I)
    if m:
        try:
            return data.decode(m.group(1).decode("ascii"), "replace")
        except LookupError:
            pass
    return data.decode("cp1252", "replace")
