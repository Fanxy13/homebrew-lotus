"""The documents: Text, Markdown, Word (.docx), OpenDocument (.odt) and RTF – written by hand, nothing to install.
(PDF is pdf.py.) Each takes a Document of model.py: code with its colors and line numbers, or a page's blocks.
Word, OpenDocument and RTF get A4 pages and a footer with the file and the page number. Code gets the number of
its line in the file in front of each line – a long line that wraps keeps one number, so line 18 is line 18.
"""
import base64
import datetime
import os
import re
import zipfile

from .highlight import COLORS, TEXT_COLOR
from .model import B, I, U, S, CODE, MARK, SUP, SUB, Run, Heading, Para, Item, Table, Image, Rule, Code, plain

LINK_COLOR = "0563C1"
GRAY = "6E6E6E"
EMU_PER_PX = 9525                      # 96 pixels an inch


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def attr(s):
    return esc(s).replace('"', "&quot;")


def lang_tag(lang):
    lang = (lang or "en").strip().replace("_", "-")
    if "-" in lang:
        return lang
    return {"en": "en-US", "de": "de-DE", "fr": "fr-FR", "es": "es-ES", "it": "it-IT", "nl": "nl-NL", "pt": "pt-PT",
            "sv": "sv-SE", "da": "da-DK", "pl": "pl-PL", "cs": "cs-CZ", "ja": "ja-JP", "zh": "zh-CN"}.get(lang.lower(), lang.lower())


def now_iso():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def label(doc):
    """What the document is called inside: the page's title, else the file."""
    return doc.meta if doc.kind == "page" and doc.meta else doc.title


def image_label(img):
    return f"[Image: {img.alt}]" if img.alt else "[Image]"


def fit(width, height, max_w, max_h):
    """A size that fits into max_w × max_h, never larger than it is."""
    k = min(1.0, max_w / width if width else 1, max_h / height if height else 1)
    return width * k, height * k


# ── Text ──────────────────────────────────────────────────────

def _text_runs(runs):
    out = []
    for r in runs:
        out.append(r.text)
        if r.link and r.link not in r.text and r.text != "\n" and not r.link.startswith("mailto:" + r.text):
            out.append(f" ({r.link})")
    return "".join(out)


def _text_table(rows):
    cells = [[_text_runs(c).replace("\n", " ") for c in row] for row in rows]
    widths = [max(len(row[i]) for row in cells) for i in range(len(cells[0]))]
    if sum(widths) + 3 * len(widths) > 110:
        return [" | ".join(row) for row in cells]
    lines = [" | ".join(c.ljust(w) for c, w in zip(row, widths)).rstrip() for row in cells]
    return lines


def write_txt(doc, path):
    out = []
    if doc.kind == "code":
        out = ["".join(t for _, t in line) for b in doc.blocks if isinstance(b, Code) for line in b.lines]
        text = "\n".join(out) + "\n"
    else:
        prev = None
        for b in doc.blocks:
            if out and not (isinstance(b, Item) and isinstance(prev, Item)):
                out.append("")
            if isinstance(b, Heading):
                t = _text_runs(b.runs).replace("\n", " ")
                out.append(t)
                if b.level <= 2:
                    out.append(("=" if b.level == 1 else "-") * len(t))
            elif isinstance(b, Para):
                pad = "    " * b.indent + ("    " if b.style == "quote" else "")
                out += [pad + line for line in _text_runs(b.runs).split("\n")]
            elif isinstance(b, Item):
                pad = "    " * b.level
                lines = _text_runs(b.runs).split("\n")
                first = (b.marker + " ") if b.marker else "  "
                out.append(pad + first + lines[0])
                out += [pad + " " * len(first) + line for line in lines[1:]]
            elif isinstance(b, Table):
                out += _text_table(b.rows)
            elif isinstance(b, Image):
                out.append(image_label(b))
            elif isinstance(b, Rule):
                out.append("-" * 40)
            elif isinstance(b, Code):
                out += ["    " + "".join(t for _, t in line) for line in b.lines]
            prev = b
        text = "\n".join(out).rstrip("\n") + "\n"
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


# ── Markdown ──────────────────────────────────────────────────

_MD_SPECIAL = re.compile(r"([\\`*_\[\]<>|])")


def _md_inline(runs, table=False):
    out = []
    for r in runs:
        if r.text == "\n":
            out.append("<br>" if table else "\\\n")
            continue
        text = r.text
        lead = text[:len(text) - len(text.lstrip(" "))]
        trail = text[len(text.rstrip(" ")):]
        core = text.strip(" ")
        if not core:
            out.append(text)
            continue
        if r.flags & CODE:
            ticks = max((len(m) for m in re.findall(r"`+", core)), default=0) + 1
            pad = " " if core.startswith("`") or core.endswith("`") else ""
            core = "`" * ticks + pad + core + pad + "`" * ticks
        else:
            core = _MD_SPECIAL.sub(r"\\\1", core)
            if r.flags & B:
                core = f"**{core}**"
            if r.flags & I:
                core = f"*{core}*"
            if r.flags & S:
                core = f"~~{core}~~"
            if r.flags & U:
                core = f"<u>{core}</u>"
            if r.flags & MARK:
                core = f"<mark>{core}</mark>"
            if r.flags & SUP:
                core = f"<sup>{core}</sup>"
            if r.flags & SUB:
                core = f"<sub>{core}</sub>"
        if r.link:
            core = f"[{core}]({r.link.replace(' ', '%20').replace(')', '%29')})"
        out.append(lead + core + trail)
    text = "".join(out)
    if not table:
        text = re.sub(r"(?m)^(\s*)([#+-]|\d+\.)(?=\s)", r"\1\\\2", text)     # a line that would start a heading or list
    return text


def _fence(lines):
    longest = max((len(m) for line in lines for _, t in line for m in re.findall(r"`+", t)), default=0)
    return "`" * max(3, longest + 1)


def write_md(doc, path):
    out = []
    here = os.path.dirname(os.path.abspath(path))
    if doc.kind == "code":
        out += ["# " + doc.title, ""]
        if doc.meta:
            out += [f"*{_md_inline([Run(doc.meta, 0, None)])}*", ""]
    prev = None
    for b in doc.blocks:
        if out and out[-1] != "" and not (isinstance(b, Item) and isinstance(prev, Item) and b.marker):
            out.append("")
        if isinstance(b, Heading):
            out.append("#" * b.level + " " + _md_inline(b.runs).replace("\\\n", " "))
        elif isinstance(b, Para):
            text = _md_inline(b.runs)
            if b.style == "quote":
                text = "\n".join("> " + line for line in text.split("\n"))
            elif b.style == "caption":
                text = f"*{text}*"
            elif b.style == "term":
                text = f"**{text}**"
            out.append(text)
        elif isinstance(b, Item):
            pad = "    " * b.level
            text = _md_inline(b.runs).replace("\n", "\n" + pad + "    ")
            if not b.marker:
                out.append(pad + "    " + text)
            else:
                marker = b.marker if re.fullmatch(r"\d+\.", b.marker) else "-"
                out.append(f"{pad}{marker} {text}")
        elif isinstance(b, Table):
            rows = [[_md_inline(c, table=True) or " " for c in row] for row in b.rows]
            out.append("| " + " | ".join(rows[0]) + " |")
            out.append("|" + "|".join(" --- " for _ in rows[0]) + "|")
            out += ["| " + " | ".join(row) + " |" for row in rows[1:]]
        elif isinstance(b, Image):
            if b.src:
                target = os.path.relpath(b.src, here).replace(os.sep, "/")
            else:
                target = f"data:image/{b.kind};base64," + base64.b64encode(b.data).decode("ascii")
            alt = _MD_SPECIAL.sub(r"\\\1", b.alt)
            out.append(f"![{alt}]({target.replace(' ', '%20')})")
        elif isinstance(b, Rule):
            out.append("---")
        elif isinstance(b, Code):
            fence = _fence(b.lines)
            body = ["".join(t for _, t in line) for line in b.lines]
            out += [fence + (b.lang if b.lang != "text" else "")] + body + [fence]
        prev = b
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out).rstrip("\n") + "\n")


# ── Word (.docx) ──────────────────────────────────────────────

W_NS = ('xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"')
DRAW_NS = ('xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
           'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
           'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"')
REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
PAGE_W, PAGE_H, MARGIN_L, MARGIN_R, MARGIN_TB = 11906, 16838, 1418, 1134, 1134     # A4 in twips
CODE_MARGIN = 850                      # code: 1.5 cm left and right – the line numbers take the first 1.4 cm
NUMBER_W, NUMBER_GAP = 794, 227        # where the code starts, and the gap between number and code
TEXT_W = PAGE_W - MARGIN_L - MARGIN_R
MONO = '<w:rFonts w:ascii="Consolas" w:hAnsi="Consolas" w:eastAsia="Consolas" w:cs="Consolas"/>'
SANS = "Calibri"


def _docx_rpr(flags=0, color=None, link=False, code_para=False):
    p = []
    if link:
        p.append('<w:rStyle w:val="Hyperlink"/>')
    if flags & CODE and not code_para:
        p.append(MONO)
    if flags & B:
        p.append("<w:b/><w:bCs/>")
    if flags & I:
        p.append("<w:i/><w:iCs/>")
    if flags & S:
        p.append("<w:strike/>")
    if flags & CODE and not code_para:
        p.append("<w:noProof/>")
    if color:
        p.append(f'<w:color w:val="{color}"/>')
    if flags & MARK:
        p.append('<w:highlight w:val="yellow"/>')
    if flags & U and not link:
        p.append('<w:u w:val="single"/>')
    if flags & CODE and not code_para:
        p.append('<w:shd w:val="clear" w:color="auto" w:fill="F0F0F0"/>')
    if flags & SUP:
        p.append('<w:vertAlign w:val="superscript"/>')
    elif flags & SUB:
        p.append('<w:vertAlign w:val="subscript"/>')
    return f"<w:rPr>{''.join(p)}</w:rPr>" if p else ""


def _docx_text(text):
    parts = text.split("\n")
    out = []
    for i, part in enumerate(parts):
        if i:
            out.append("<w:br/>")
        if part:
            out.append(f'<w:t xml:space="preserve">{esc(part)}</w:t>')
    return "".join(out)


class _Docx:
    def __init__(self, doc, author=""):
        self.doc, self.author = doc, author
        self.rels, self.media = [], []
        self.drawing = 0

    def rel(self, kind, target, external=False):
        rid = f"rId{len(self.rels) + 10}"
        self.rels.append((rid, kind, target, external))
        return rid

    def runs(self, runs):
        out = []
        for r in runs:
            if not r.text:
                continue
            body = f"<w:r>{_docx_rpr(r.flags, None, bool(r.link))}{_docx_text(r.text)}</w:r>"
            if r.link:
                rid = self.rel("hyperlink", r.link, external=True)
                body = f'<w:hyperlink r:id="{rid}" w:history="1">{body}</w:hyperlink>'
            out.append(body)
        return "".join(out)

    @staticmethod
    def para(content, style=None, ppr=""):
        p = (f'<w:pStyle w:val="{style}"/>' if style else "") + ppr
        return f"<w:p>{'<w:pPr>' + p + '</w:pPr>' if p else ''}{content}</w:p>"

    def code(self, block, style):
        out = []
        for line in block.lines:
            rs = "".join(f"<w:r>{_docx_rpr(0, COLORS.get(k), code_para=True)}<w:t xml:space=\"preserve\">{esc(t)}</w:t></w:r>"
                         for k, t in line)
            out.append(self.para(rs, style))
        return "".join(out)

    def image(self, img):
        self.drawing += 1
        n = self.drawing
        name = f"image{n}.{'jpeg' if img.kind == 'jpeg' else img.kind}"
        self.media.append((name, img.data))
        rid = self.rel("image", f"media/{name}")
        w, h = fit(img.width * EMU_PER_PX, img.height * EMU_PER_PX, TEXT_W * 635, (PAGE_H - 2 * MARGIN_TB - 1400) * 635)
        w, h = int(w), int(h)
        alt = attr(img.alt)
        return self.para(
            f'<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="{w}" cy="{h}"/>'
            f'<wp:effectExtent l="0" t="0" r="0" b="0"/><wp:docPr id="{n}" name="Picture {n}" descr="{alt}"/>'
            '<wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>'
            '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
            f'<pic:pic><pic:nvPicPr><pic:cNvPr id="{n}" name="{name}" descr="{alt}"/><pic:cNvPicPr/></pic:nvPicPr>'
            f'<pic:blipFill><a:blip r:embed="{rid}"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
            f'<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="{w}" cy="{h}"/></a:xfrm>'
            '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic>'
            "</wp:inline></w:drawing></w:r>", "Picture")

    def table(self, t):
        cols = len(t.rows[0])
        weight = [max(4, min(40, max(len(plain(row[i])) for row in t.rows))) for i in range(cols)]
        widths = [TEXT_W * w // sum(weight) for w in weight]
        grid = "".join(f'<w:gridCol w:w="{w}"/>' for w in widths)
        border = 'w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"'
        out = [f'<w:tbl><w:tblPr><w:tblW w:w="{sum(widths)}" w:type="dxa"/><w:tblBorders><w:top {border}/><w:left {border}/>'
               f'<w:bottom {border}/><w:right {border}/><w:insideH {border}/><w:insideV {border}/></w:tblBorders>'
               '<w:tblLayout w:type="fixed"/><w:tblCellMar><w:top w:w="40" w:type="dxa"/><w:left w:w="100" w:type="dxa"/>'
               '<w:bottom w:w="40" w:type="dxa"/><w:right w:w="100" w:type="dxa"/></w:tblCellMar></w:tblPr>'
               f"<w:tblGrid>{grid}</w:tblGrid>"]
        for r, row in enumerate(t.rows):
            head = r < t.header
            out.append("<w:tr>" + ("<w:trPr><w:tblHeader/></w:trPr>" if head else ""))
            for c, cell in enumerate(row):
                runs = [x._replace(flags=x.flags | B) for x in cell] if head else cell
                shade = '<w:shd w:val="clear" w:color="auto" w:fill="F2F2F2"/>' if head else ""
                out.append(f'<w:tc><w:tcPr><w:tcW w:w="{widths[c]}" w:type="dxa"/>{shade}</w:tcPr>'
                           f'{self.para(self.runs(runs), "TableText")}</w:tc>')
            out.append("</w:tr>")
        out.append("</w:tbl>")
        out.append(self.para("", "TableAfter"))
        return "".join(out)

    def body(self):
        doc, out = self.doc, []
        if doc.kind == "code":
            out.append(self.para(f"<w:r><w:t xml:space=\"preserve\">{esc(doc.title)}</w:t></w:r>", "FileName"))
            if doc.meta:
                out.append(self.para(f"<w:r><w:t xml:space=\"preserve\">{esc(doc.meta)}</w:t></w:r>", "Meta"))
        for b in doc.blocks:
            if isinstance(b, Heading):
                out.append(self.para(self.runs(b.runs), f"Heading{b.level}"))
            elif isinstance(b, Para):
                style = {"quote": "Quote", "caption": "Caption", "term": "Term", "meta": "Meta"}.get(b.style)
                out.append(self.para(self.runs(b.runs), style, f'<w:ind w:left="{567 * b.indent}"/>' if b.indent else ""))
            elif isinstance(b, Item):
                left = 360 * (b.level + 1)
                if b.marker:
                    content = f'<w:r><w:t xml:space="preserve">{esc(b.marker)}</w:t></w:r><w:r><w:tab/></w:r>' + self.runs(b.runs)
                    ppr = f'<w:tabs><w:tab w:val="left" w:pos="{left}"/></w:tabs><w:ind w:left="{left}" w:hanging="360"/>'
                else:
                    content, ppr = self.runs(b.runs), f'<w:ind w:left="{left}"/>'
                out.append(self.para(content, "ListText", ppr))
            elif isinstance(b, Table):
                out.append(self.table(b))
            elif isinstance(b, Image):
                if b.kind in ("png", "jpeg", "gif"):
                    out.append(self.image(b))
                else:
                    out.append(self.para(f"<w:r>{_docx_rpr(I)}<w:t>{esc(image_label(b))}</w:t></w:r>"))
            elif isinstance(b, Rule):
                out.append(self.para("", None, '<w:pBdr><w:bottom w:val="single" w:sz="6" w:space="1" w:color="BFBFBF"/></w:pBdr>'))
            elif isinstance(b, Code):
                out.append(self.code(b, "Code" if doc.kind == "code" else "CodeBlock"))
        left, right = (CODE_MARGIN, CODE_MARGIN) if doc.kind == "code" else (MARGIN_L, MARGIN_R)
        footer = self.rel("footer", "footer1.xml")
        out.append(f'<w:sectPr><w:footerReference w:type="default" r:id="{footer}"/><w:pgSz w:w="{PAGE_W}" w:h="{PAGE_H}"/>'
                   f'<w:pgMar w:top="{MARGIN_TB}" w:right="{right}" w:bottom="{MARGIN_TB}" w:left="{left}" '
                   'w:header="567" w:footer="567" w:gutter="0"/></w:sectPr>')
        return "".join(out)


def _docx_styles(doc):
    lang = lang_tag(doc.lang)
    no_numbers = ""
    text_w = PAGE_W - 2 * CODE_MARGIN if doc.kind == "code" else TEXT_W
    sizes = {1: 36, 2: 30, 3: 26, 4: 24, 5: 22, 6: 22}
    headings = "".join(
        f'<w:style w:type="paragraph" w:styleId="Heading{n}"><w:name w:val="heading {n}"/><w:basedOn w:val="Normal"/>'
        f'<w:next w:val="Normal"/><w:uiPriority w:val="9"/><w:qFormat/><w:pPr><w:keepNext/><w:keepLines/>{no_numbers}'
        f'<w:spacing w:before="{280 if n < 3 else 200}" w:after="100"/><w:outlineLvl w:val="{n - 1}"/></w:pPr>'
        f'<w:rPr><w:b/><w:bCs/>{"<w:i/><w:iCs/>" if n == 6 else ""}<w:color w:val="1F1F1F"/><w:sz w:val="{sizes[n]}"/>'
        f'<w:szCs w:val="{sizes[n]}"/></w:rPr></w:style>' for n in range(1, 7))
    return (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<w:styles {W_NS}>'
            f'<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="{SANS}" w:hAnsi="{SANS}" w:eastAsia="{SANS}" w:cs="{SANS}"/>'
            f'<w:sz w:val="22"/><w:szCs w:val="22"/><w:lang w:val="{lang}" w:eastAsia="{lang}" w:bidi="ar-SA"/></w:rPr></w:rPrDefault>'
            '<w:pPrDefault><w:pPr><w:spacing w:after="120" w:line="264" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>'
            '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>'
            '<w:style w:type="character" w:default="1" w:styleId="DefaultParagraphFont"><w:name w:val="Default Paragraph Font"/>'
            '<w:uiPriority w:val="1"/><w:semiHidden/><w:unhideWhenUsed/></w:style>'
            + headings +
            '<w:style w:type="paragraph" w:styleId="FileName"><w:name w:val="File Name"/><w:basedOn w:val="Normal"/>'
            f'<w:next w:val="Meta"/><w:qFormat/><w:pPr><w:keepNext/>{no_numbers}<w:spacing w:before="0" w:after="40"/>'
            f'<w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:bCs/><w:color w:val="1F1F1F"/><w:sz w:val="32"/><w:szCs w:val="32"/></w:rPr></w:style>'
            '<w:style w:type="paragraph" w:styleId="Meta"><w:name w:val="Meta"/><w:basedOn w:val="Normal"/><w:next w:val="Code"/>'
            f'<w:pPr><w:keepNext/>{no_numbers}<w:pBdr><w:bottom w:val="single" w:sz="4" w:space="6" w:color="D9D9D9"/></w:pBdr>'
            f'<w:spacing w:after="240"/></w:pPr><w:rPr><w:color w:val="{GRAY}"/><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr></w:style>'
            '<w:style w:type="paragraph" w:styleId="Code"><w:name w:val="Code"/><w:basedOn w:val="Normal"/><w:qFormat/>'
            '<w:pPr><w:numPr><w:numId w:val="1"/></w:numPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/>'
            f'<w:ind w:left="{NUMBER_W}" w:hanging="{NUMBER_GAP}"/></w:pPr>'
            f'<w:rPr>{MONO}<w:noProof/><w:color w:val="{TEXT_COLOR}"/><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr></w:style>'
            '<w:style w:type="paragraph" w:styleId="CodeBlock"><w:name w:val="Code Block"/><w:basedOn w:val="Normal"/>'
            '<w:pPr><w:shd w:val="clear" w:color="auto" w:fill="F6F8FA"/><w:spacing w:after="0" w:line="240" w:lineRule="auto"/>'
            '<w:ind w:left="113" w:right="113"/></w:pPr>'
            f'<w:rPr>{MONO}<w:noProof/><w:color w:val="{TEXT_COLOR}"/><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr></w:style>'
            '<w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:basedOn w:val="Normal"/><w:qFormat/>'
            f'<w:pPr>{no_numbers}<w:pBdr><w:left w:val="single" w:sz="18" w:space="8" w:color="D0D0D0"/></w:pBdr><w:ind w:left="340"/></w:pPr>'
            f'<w:rPr><w:i/><w:iCs/><w:color w:val="404040"/></w:rPr></w:style>'
            '<w:style w:type="paragraph" w:styleId="Caption"><w:name w:val="caption"/><w:basedOn w:val="Normal"/><w:qFormat/>'
            f'<w:pPr>{no_numbers}<w:spacing w:after="200"/></w:pPr><w:rPr><w:i/><w:iCs/><w:color w:val="{GRAY}"/><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr></w:style>'
            '<w:style w:type="paragraph" w:styleId="Term"><w:name w:val="Term"/><w:basedOn w:val="Normal"/>'
            f'<w:pPr><w:keepNext/>{no_numbers}<w:spacing w:after="40"/></w:pPr><w:rPr><w:b/><w:bCs/></w:rPr></w:style>'
            '<w:style w:type="paragraph" w:styleId="ListText"><w:name w:val="List Text"/><w:basedOn w:val="Normal"/>'
            f'<w:pPr>{no_numbers}<w:spacing w:after="60"/></w:pPr></w:style>'
            '<w:style w:type="paragraph" w:styleId="Picture"><w:name w:val="Picture"/><w:basedOn w:val="Normal"/>'
            f'<w:pPr><w:keepNext/>{no_numbers}<w:spacing w:before="120" w:after="120"/></w:pPr></w:style>'
            '<w:style w:type="paragraph" w:styleId="TableText"><w:name w:val="Table Text"/><w:basedOn w:val="Normal"/>'
            f'<w:pPr>{no_numbers}<w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:rPr><w:sz w:val="20"/><w:szCs w:val="20"/></w:rPr></w:style>'
            '<w:style w:type="paragraph" w:styleId="TableAfter"><w:name w:val="Table After"/><w:basedOn w:val="Normal"/>'
            f'<w:pPr>{no_numbers}<w:spacing w:after="0" w:line="120" w:lineRule="exact"/></w:pPr></w:style>'
            '<w:style w:type="paragraph" w:styleId="Footer"><w:name w:val="footer"/><w:basedOn w:val="Normal"/>'
            f'<w:pPr>{no_numbers}<w:tabs><w:tab w:val="right" w:pos="{text_w}"/></w:tabs><w:spacing w:after="0"/></w:pPr>'
            f'<w:rPr><w:color w:val="{GRAY}"/><w:sz w:val="16"/><w:szCs w:val="16"/></w:rPr></w:style>'
            f'<w:style w:type="character" w:styleId="Hyperlink"><w:name w:val="Hyperlink"/><w:rPr><w:color w:val="{LINK_COLOR}"/>'
            '<w:u w:val="single"/></w:rPr></w:style>'
            '</w:styles>')


def write_docx(doc, path, author=""):
    d = _Docx(doc, author)
    body = d.body()
    document = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<w:document {W_NS} {DRAW_NS}>'
                f"<w:body>{body}</w:body></w:document>")
    footer = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<w:ftr {W_NS}><w:p><w:pPr><w:pStyle w:val="Footer"/></w:pPr>'
              f'<w:r><w:t xml:space="preserve">{esc(doc.title)}</w:t></w:r><w:r><w:tab/></w:r>'
              '<w:fldSimple w:instr=" PAGE "><w:r><w:t>1</w:t></w:r></w:fldSimple><w:r><w:t xml:space="preserve"> / </w:t></w:r>'
              '<w:fldSimple w:instr=" NUMPAGES "><w:r><w:t>1</w:t></w:r></w:fldSimple></w:p></w:ftr>')
    external = ' TargetMode="External"'
    rels = "".join(f'<Relationship Id="{rid}" Type="{REL}/{kind}" Target="{attr(target)}"{external if ext else ""}/>'
                   for rid, kind, target, ext in d.rels)
    doc_rels = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
                '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                f'<Relationship Id="rId1" Type="{REL}/styles" Target="styles.xml"/>'
                f'<Relationship Id="rId2" Type="{REL}/settings" Target="settings.xml"/>'
                f'<Relationship Id="rId3" Type="{REL}/fontTable" Target="fontTable.xml"/>'
                f'<Relationship Id="rId4" Type="{REL}/numbering" Target="numbering.xml"/>{rels}</Relationships>')
    settings = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<w:settings {W_NS}><w:zoom w:percent="100"/>'
                '<w:defaultTabStop w:val="709"/><w:characterSpacingControl w:val="doNotCompress"/>'
                '<w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/>'
                '</w:compat></w:settings>')
    numbering = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<w:numbering {W_NS}>'
                 '<w:abstractNum w:abstractNumId="0"><w:multiLevelType w:val="singleLevel"/><w:lvl w:ilvl="0">'
                 '<w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1"/><w:lvlJc w:val="right"/>'
                 f'<w:pPr><w:ind w:left="{NUMBER_W}" w:hanging="{NUMBER_GAP}"/></w:pPr>'
                 f'<w:rPr>{MONO}<w:color w:val="A0A0A0"/><w:sz w:val="16"/><w:szCs w:val="16"/></w:rPr></w:lvl></w:abstractNum>'
                 '<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num></w:numbering>')
    fonts = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<w:fonts {W_NS}>'
             f'<w:font w:name="{SANS}"><w:panose1 w:val="020F0502020204030204"/><w:charset w:val="00"/><w:family w:val="swiss"/>'
             '<w:pitch w:val="variable"/></w:font><w:font w:name="Consolas"><w:panose1 w:val="020B0609020204030204"/>'
             '<w:charset w:val="00"/><w:family w:val="modern"/><w:pitch w:val="fixed"/></w:font></w:fonts>')
    creator = f"<dc:creator>{esc(author)}</dc:creator>" if author else ""
    core = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
            '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
            'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" '
            'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
            f'<dc:title>{esc(label(doc))}</dc:title>{creator}<dc:language>{lang_tag(doc.lang)}</dc:language>'
            f'<dcterms:created xsi:type="dcterms:W3CDTF">{now_iso()}</dcterms:created></cp:coreProperties>')
    app = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
           '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
           '<Application>Lotus</Application></Properties>')
    main = "application/vnd.openxmlformats-officedocument.wordprocessingml"
    types = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
             '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
             '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
             '<Default Extension="xml" ContentType="application/xml"/>'
             '<Default Extension="png" ContentType="image/png"/><Default Extension="jpeg" ContentType="image/jpeg"/>'
             '<Default Extension="gif" ContentType="image/gif"/>'
             f'<Override PartName="/word/document.xml" ContentType="{main}.document.main+xml"/>'
             f'<Override PartName="/word/styles.xml" ContentType="{main}.styles+xml"/>'
             f'<Override PartName="/word/settings.xml" ContentType="{main}.settings+xml"/>'
             f'<Override PartName="/word/fontTable.xml" ContentType="{main}.fontTable+xml"/>'
             f'<Override PartName="/word/numbering.xml" ContentType="{main}.numbering+xml"/>'
             f'<Override PartName="/word/footer1.xml" ContentType="{main}.footer+xml"/>'
             '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
             '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
             '</Types>')
    package_rels = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
                    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                    f'<Relationship Id="rId1" Type="{REL}/officeDocument" Target="word/document.xml"/>'
                    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
                    f'<Relationship Id="rId3" Type="{REL}/extended-properties" Target="docProps/app.xml"/></Relationships>')
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", types)
        z.writestr("_rels/.rels", package_rels)
        z.writestr("docProps/core.xml", core)
        z.writestr("docProps/app.xml", app)
        z.writestr("word/document.xml", document)
        z.writestr("word/styles.xml", _docx_styles(doc))
        z.writestr("word/settings.xml", settings)
        z.writestr("word/fontTable.xml", fonts)
        z.writestr("word/numbering.xml", numbering)
        z.writestr("word/footer1.xml", footer)
        z.writestr("word/_rels/document.xml.rels", doc_rels)
        for name, data in d.media:
            z.writestr(f"word/media/{name}", data)


# ── OpenDocument (.odt) ───────────────────────────────────────

ODF_NS = ('xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
          'xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" '
          'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" '
          'xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" '
          'xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" '
          'xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" '
          'xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:dc="http://purl.org/dc/elements/1.1/" '
          'xmlns:meta="urn:oasis:names:tc:opendocument:xmlns:meta:1.0" '
          'xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0" office:version="1.3"')
ODT_TEXT_W = 16.5                      # cm: A4, 2.5 cm left, 2 cm right
_ODT_SPACES = re.compile(r"( {2,}|\n|\t|^ )")


def _odt_text(text, start):
    """Text as ODF keeps it: more than one space, a space at the start of a line, tabs and line breaks are
    elements of their own (ODF would collapse them)."""
    out = []
    for i, part in enumerate(_ODT_SPACES.split(text)):
        if not part:
            continue
        if i % 2 == 0:
            if start and part.startswith(" "):
                out.append('<text:s/>')
                part = part[1:]
            out.append(esc(part))
            start = False
        elif part == "\n":
            out.append("<text:line-break/>")
            start = True
        elif part == "\t":
            out.append("<text:tab/>")
            start = False
        else:
            n = len(part)
            if start:
                out.append(f'<text:s text:c="{n}"/>' if n > 1 else "<text:s/>")
            elif n == 1:
                out.append(" ")
            else:
                out.append(" " + (f'<text:s text:c="{n - 1}"/>' if n > 2 else "<text:s/>"))
            start = False
    return "".join(out), start


class _Odt:
    def __init__(self, doc):
        self.doc = doc
        self.text_styles = {}           # (flags, color) → style name
        self.auto = []                  # automatic styles of content.xml
        self.pictures = []
        self.tables = 0

    def tstyle(self, flags, color=None, link=False):
        key = (flags, color, link)
        if key not in self.text_styles:
            name = f"T{len(self.text_styles) + 1}"
            self.text_styles[key] = name
            p = []
            if link:
                p.append(f'fo:color="#{LINK_COLOR}" style:text-underline-style="solid" style:text-underline-width="auto" '
                         'style:text-underline-color="font-color"')
            elif color:
                p.append(f'fo:color="#{color}"')
            if flags & B:
                p.append('fo:font-weight="bold" style:font-weight-asian="bold" style:font-weight-complex="bold"')
            if flags & I:
                p.append('fo:font-style="italic" style:font-style-asian="italic" style:font-style-complex="italic"')
            if flags & U and not link:
                p.append('style:text-underline-style="solid" style:text-underline-width="auto" style:text-underline-color="font-color"')
            if flags & S:
                p.append('style:text-line-through-style="solid" style:text-line-through-type="single"')
            if flags & CODE:
                p.append('style:font-name="Mono" fo:background-color="#f0f0f0" fo:language="zxx" fo:country="none"')
            if flags & MARK:
                p.append('fo:background-color="#ffff00"')
            if flags & SUP:
                p.append('style:text-position="super 58%"')
            elif flags & SUB:
                p.append('style:text-position="sub 58%"')
            self.auto.append(f'<style:style style:name="{name}" style:family="text"><style:text-properties {" ".join(p)}/></style:style>')
        return self.text_styles[key]

    def runs(self, runs):
        out, start = [], True
        for r in runs:
            if not r.text:
                continue
            body, start = _odt_text(r.text, start)
            if r.flags or r.link:
                body = f'<text:span text:style-name="{self.tstyle(r.flags, None, bool(r.link))}">{body}</text:span>'
            if r.link:
                body = f'<text:a xlink:type="simple" xlink:href="{attr(r.link)}">{body}</text:a>'
            out.append(body)
        return "".join(out)

    def code(self, block, style):
        out = []
        for line in block.lines:
            parts, start = [], True
            for kind, t in line:
                body, start = _odt_text(t, start)
                color = COLORS.get(kind)
                parts.append(f'<text:span text:style-name="{self.tstyle(0, color)}">{body}</text:span>' if color else body)
            p = f'<text:p text:style-name="{style}">{"".join(parts)}</text:p>'
            out.append(f"<text:list-item>{p}</text:list-item>" if block.numbers else p)
        if block.numbers:
            return f'<text:list text:style-name="CodeNumbers">{"".join(out)}</text:list>'
        return "".join(out)

    def image(self, img):
        n = len(self.pictures) + 1
        name = f"Pictures/image{n}.{'jpg' if img.kind == 'jpeg' else img.kind}"
        self.pictures.append((name, img.data, f"image/{img.kind}"))
        w, h = fit(img.width * 2.54 / 96, img.height * 2.54 / 96, ODT_TEXT_W, 22)
        return (f'<text:p text:style-name="Picture"><draw:frame draw:style-name="Frame" draw:name="Image{n}" '
                f'text:anchor-type="as-char" svg:width="{w:.3f}cm" svg:height="{h:.3f}cm" draw:z-index="0">'
                f'<draw:image xlink:href="{name}" xlink:type="simple" xlink:show="embed" xlink:actuate="onLoad"/>'
                f'<svg:desc>{esc(img.alt)}</svg:desc></draw:frame></text:p>')

    def table(self, t):
        self.tables += 1
        n = self.tables
        cols = len(t.rows[0])
        weight = [max(4, min(40, max(len(plain(row[i])) for row in t.rows))) for i in range(cols)]
        widths = [ODT_TEXT_W * w / sum(weight) for w in weight]
        self.auto.append(f'<style:style style:name="Tbl{n}" style:family="table"><style:table-properties '
                         f'style:width="{sum(widths):.3f}cm" table:align="left" fo:margin-top="0.1cm" fo:margin-bottom="0.3cm"/></style:style>')
        for i, w in enumerate(widths):
            self.auto.append(f'<style:style style:name="Tbl{n}.C{i + 1}" style:family="table-column">'
                             f'<style:table-column-properties style:column-width="{w:.3f}cm"/></style:style>')
        out = [f'<table:table table:name="Table{n}" table:style-name="Tbl{n}">']
        out += [f'<table:table-column table:style-name="Tbl{n}.C{i + 1}"/>' for i in range(cols)]
        for r, row in enumerate(t.rows):
            head = r < t.header
            if r == 0 and head:
                out.append("<table:table-header-rows>")
            out.append("<table:table-row>")
            for cell in row:
                runs = [x._replace(flags=x.flags | B) for x in cell] if head else cell
                out.append(f'<table:table-cell table:style-name="{"CellHead" if head else "Cell"}" office:value-type="string">'
                           f'<text:p text:style-name="TableText">{self.runs(runs)}</text:p></table:table-cell>')
            out.append("</table:table-row>")
            if head and r + 1 == t.header:
                out.append("</table:table-header-rows>")
        out.append("</table:table>")
        return "".join(out)

    def body(self):
        doc, out = self.doc, []
        if doc.kind == "code":
            out.append(f'<text:h text:style-name="FileName" text:outline-level="1">{esc(doc.title)}</text:h>')
            if doc.meta:
                out.append(f'<text:p text:style-name="Meta">{_odt_text(doc.meta, True)[0]}</text:p>')
        for b in doc.blocks:
            if isinstance(b, Heading):
                out.append(f'<text:h text:style-name="Heading_20_{b.level}" text:outline-level="{b.level}">{self.runs(b.runs)}</text:h>')
            elif isinstance(b, Para):
                style = {"quote": "Quote", "caption": "Caption", "term": "Term", "meta": "Meta"}.get(b.style, "Text_20_body")
                if b.indent:
                    style = f"Indent{min(b.indent, 6)}"
                out.append(f'<text:p text:style-name="{style}">{self.runs(b.runs)}</text:p>')
            elif isinstance(b, Item):
                level = min(b.level, 8)
                if b.marker:
                    out.append(f'<text:p text:style-name="List{level}">{esc(b.marker)}<text:tab/>{self.runs(b.runs)}</text:p>')
                else:
                    out.append(f'<text:p text:style-name="ListMore{level}">{self.runs(b.runs)}</text:p>')
            elif isinstance(b, Table):
                out.append(self.table(b))
            elif isinstance(b, Image):
                out.append(self.image(b) if b.kind in ("png", "jpeg", "gif") else
                           f'<text:p text:style-name="Caption">{esc(image_label(b))}</text:p>')
            elif isinstance(b, Rule):
                out.append('<text:p text:style-name="Rule"/>')
            elif isinstance(b, Code):
                out.append(self.code(b, "Code" if doc.kind == "code" else "CodeBlock"))
        return "".join(out)


def _odt_styles(doc):
    off = '<style:paragraph-properties text:number-lines="false"/>'
    italic = ' fo:font-style="italic"'
    sizes = {1: "18pt", 2: "15pt", 3: "13pt", 4: "12pt", 5: "11pt", 6: "11pt"}
    headings = "".join(
        f'<style:style style:name="Heading_20_{n}" style:display-name="Heading {n}" style:family="paragraph" '
        f'style:parent-style-name="Standard" style:next-style-name="Text_20_body" style:default-outline-level="{n}" style:class="text">'
        f'<style:paragraph-properties fo:margin-top="{0.5 if n < 3 else 0.35}cm" fo:margin-bottom="0.18cm" fo:keep-with-next="always" '
        f'text:number-lines="false"/><style:text-properties fo:font-size="{sizes[n]}" fo:font-weight="bold" '
        f'style:font-weight-asian="bold" style:font-weight-complex="bold" fo:color="#1f1f1f"{italic if n == 6 else ""}/>'
        "</style:style>" for n in range(1, 7))
    lists = "".join(
        f'<style:style style:name="List{n}" style:family="paragraph" style:parent-style-name="Standard">'
        f'<style:paragraph-properties fo:margin-left="{0.63 * (n + 1):.2f}cm" fo:text-indent="-0.63cm" fo:margin-bottom="0.1cm" '
        'text:number-lines="false"><style:tab-stops><style:tab-stop style:position="0cm"/></style:tab-stops></style:paragraph-properties></style:style>'
        f'<style:style style:name="ListMore{n}" style:family="paragraph" style:parent-style-name="Standard">'
        f'<style:paragraph-properties fo:margin-left="{0.63 * (n + 1):.2f}cm" fo:margin-bottom="0.1cm" text:number-lines="false"/></style:style>'
        for n in range(9))
    indents = "".join(
        f'<style:style style:name="Indent{n}" style:family="paragraph" style:parent-style-name="Text_20_body">'
        f'<style:paragraph-properties fo:margin-left="{n}cm" text:number-lines="false"/></style:style>' for n in range(1, 7))
    lang, _, country = lang_tag(doc.lang).partition("-")
    left, right = ("1.5cm", "1.5cm") if doc.kind == "code" else ("2.5cm", "2cm")
    text_w = 18 if doc.kind == "code" else ODT_TEXT_W
    return (f'<?xml version="1.0" encoding="UTF-8"?>\n<office:document-styles {ODF_NS}>'
            '<office:font-face-decls><style:font-face style:name="Body" svg:font-family="Helvetica" '
            'style:font-family-generic="swiss" style:font-pitch="variable"/><style:font-face style:name="Mono" '
            'svg:font-family="Menlo" style:font-family-generic="modern" style:font-pitch="fixed"/></office:font-face-decls>'
            '<office:styles>'
            '<style:default-style style:family="paragraph"><style:paragraph-properties style:tab-stop-distance="1.25cm"/>'
            f'<style:text-properties style:font-name="Body" fo:font-size="11pt" fo:language="{lang}" fo:country="{country or "none"}"/>'
            '</style:default-style>'
            '<style:style style:name="Standard" style:family="paragraph" style:class="text">'
            '<style:paragraph-properties fo:margin-bottom="0.2cm" fo:line-height="115%"/></style:style>'
            '<style:style style:name="Text_20_body" style:display-name="Text body" style:family="paragraph" '
            f'style:parent-style-name="Standard" style:class="text">{off}</style:style>'
            + headings + lists + indents +
            '<style:style style:name="FileName" style:display-name="File Name" style:family="paragraph" '
            'style:parent-style-name="Standard" style:next-style-name="Meta" style:default-outline-level="1">'
            '<style:paragraph-properties fo:margin-bottom="0.1cm" fo:keep-with-next="always" text:number-lines="false"/>'
            '<style:text-properties fo:font-size="16pt" fo:font-weight="bold" style:font-weight-complex="bold" fo:color="#1f1f1f"/></style:style>'
            '<style:style style:name="Meta" style:family="paragraph" style:parent-style-name="Standard">'
            '<style:paragraph-properties fo:margin-bottom="0.45cm" fo:padding-bottom="0.15cm" fo:border-bottom="0.5pt solid #d9d9d9" '
            f'fo:keep-with-next="always" text:number-lines="false"/><style:text-properties fo:font-size="9pt" fo:color="#{GRAY}"/></style:style>'
            '<style:style style:name="Code" style:family="paragraph" style:parent-style-name="Standard">'
            '<style:paragraph-properties fo:margin-top="0cm" fo:margin-bottom="0cm" fo:line-height="100%"/>'
            f'<style:text-properties style:font-name="Mono" fo:font-size="9pt" fo:color="#{TEXT_COLOR}" fo:language="zxx" fo:country="none"/></style:style>'
            '<style:style style:name="CodeBlock" style:display-name="Code Block" style:family="paragraph" style:parent-style-name="Code">'
            '<style:paragraph-properties fo:background-color="#f6f8fa" fo:padding-left="0.1cm" text:number-lines="false"/></style:style>'
            '<style:style style:name="Quote" style:family="paragraph" style:parent-style-name="Standard">'
            '<style:paragraph-properties fo:margin-left="0.6cm" fo:padding-left="0.3cm" fo:border-left="1.5pt solid #d0d0d0" '
            'text:number-lines="false"/><style:text-properties fo:font-style="italic" fo:color="#404040"/></style:style>'
            '<style:style style:name="Caption" style:family="paragraph" style:parent-style-name="Standard">'
            '<style:paragraph-properties text:number-lines="false" fo:margin-bottom="0.35cm"/>'
            f'<style:text-properties fo:font-style="italic" fo:font-size="9pt" fo:color="#{GRAY}"/></style:style>'
            '<style:style style:name="Term" style:family="paragraph" style:parent-style-name="Standard">'
            '<style:paragraph-properties fo:margin-bottom="0.05cm" fo:keep-with-next="always" text:number-lines="false"/>'
            '<style:text-properties fo:font-weight="bold"/></style:style>'
            '<style:style style:name="Picture" style:family="paragraph" style:parent-style-name="Standard">'
            '<style:paragraph-properties fo:margin-top="0.2cm" fo:margin-bottom="0.2cm" fo:keep-with-next="always" text:number-lines="false"/></style:style>'
            '<style:style style:name="Rule" style:family="paragraph" style:parent-style-name="Standard">'
            '<style:paragraph-properties fo:margin-bottom="0.3cm" fo:border-bottom="0.75pt solid #bfbfbf" text:number-lines="false"/>'
            '<style:text-properties fo:font-size="4pt"/></style:style>'
            '<style:style style:name="TableText" style:family="paragraph" style:parent-style-name="Standard">'
            '<style:paragraph-properties fo:margin-bottom="0cm" text:number-lines="false"/><style:text-properties fo:font-size="10pt"/></style:style>'
            '<style:style style:name="Footer" style:family="paragraph" style:parent-style-name="Standard" style:class="extra">'
            '<style:paragraph-properties fo:margin-bottom="0cm" text:number-lines="false"><style:tab-stops>'
            f'<style:tab-stop style:position="{text_w}cm" style:type="right"/></style:tab-stops></style:paragraph-properties>'
            f'<style:text-properties fo:font-size="8pt" fo:color="#{GRAY}"/></style:style>'
            '<style:style style:name="Frame" style:family="graphic"><style:graphic-properties style:wrap="none" '
            'style:vertical-pos="top" style:vertical-rel="baseline" style:horizontal-pos="left" style:horizontal-rel="paragraph"/></style:style>'
            '<style:style style:name="LineNumbers" style:display-name="Line Numbers" style:family="text">'
            '<style:text-properties style:font-name="Mono" fo:font-size="8pt" fo:color="#a0a0a0"/></style:style>'
            '<text:list-style style:name="CodeNumbers" style:display-name="Code Line Numbers">'
            '<text:list-level-style-number text:level="1" text:style-name="LineNumbers" style:num-format="1">'
            '<style:list-level-properties text:list-level-position-and-space-mode="label-alignment" fo:text-align="end">'
            '<style:list-level-label-alignment text:label-followed-by="listtab" text:list-tab-stop-position="1.4cm" '
            'fo:text-indent="-0.4cm" fo:margin-left="1.4cm"/></style:list-level-properties></text:list-level-style-number>'
            '</text:list-style>'
            '<text:linenumbering-configuration text:number-lines="false" text:offset="0.35cm" style:num-format="1" '
            'text:number-position="left" text:increment="5"/>'
            '</office:styles>'
            '<office:automatic-styles><style:page-layout style:name="Page"><style:page-layout-properties fo:page-width="21cm" '
            f'fo:page-height="29.7cm" fo:margin-top="2cm" fo:margin-bottom="1.4cm" fo:margin-left="{left}" fo:margin-right="{right}" '
            'style:print-orientation="portrait"/><style:footer-style><style:header-footer-properties fo:min-height="0cm" '
            'fo:margin-top="0.5cm"/></style:footer-style></style:page-layout></office:automatic-styles>'
            '<office:master-styles><style:master-page style:name="Standard" style:page-layout-name="Page"><style:footer>'
            f'<text:p text:style-name="Footer">{esc(doc.title)}<text:tab/><text:page-number text:select-page="current">1</text:page-number>'
            ' / <text:page-count>1</text:page-count></text:p></style:footer></style:master-page></office:master-styles>'
            '</office:document-styles>')


def write_odt(doc, path, author=""):
    o = _Odt(doc)
    body = o.body()
    auto = "".join(o.auto)
    content = (f'<?xml version="1.0" encoding="UTF-8"?>\n<office:document-content {ODF_NS}>'
               '<office:font-face-decls><style:font-face style:name="Body" svg:font-family="Helvetica" '
               'style:font-family-generic="swiss" style:font-pitch="variable"/><style:font-face style:name="Mono" '
               'svg:font-family="Menlo" style:font-family-generic="modern" style:font-pitch="fixed"/></office:font-face-decls>'
               '<office:automatic-styles><style:style style:name="Cell" style:family="table-cell"><style:table-cell-properties '
               'fo:padding="0.1cm" fo:border="0.5pt solid #bfbfbf"/></style:style><style:style style:name="CellHead" '
               'style:family="table-cell"><style:table-cell-properties fo:padding="0.1cm" fo:border="0.5pt solid #bfbfbf" '
               f'fo:background-color="#f2f2f2"/></style:style>{auto}</office:automatic-styles>'
               f"<office:body><office:text>{body}</office:text></office:body></office:document-content>")
    creator = f"<meta:initial-creator>{esc(author)}</meta:initial-creator><dc:creator>{esc(author)}</dc:creator>" if author else ""
    meta = (f'<?xml version="1.0" encoding="UTF-8"?>\n<office:document-meta {ODF_NS}><office:meta>'
            f"<meta:generator>Lotus</meta:generator><dc:title>{esc(label(doc))}</dc:title><dc:language>{lang_tag(doc.lang)}</dc:language>"
            f"<meta:creation-date>{now_iso()[:-1]}</meta:creation-date>{creator}</office:meta></office:document-meta>")
    pictures = "".join(f'<manifest:file-entry manifest:full-path="{name}" manifest:media-type="{kind}"/>' for name, _, kind in o.pictures)
    manifest = ('<?xml version="1.0" encoding="UTF-8"?>\n<manifest:manifest '
                'xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.3">'
                '<manifest:file-entry manifest:full-path="/" manifest:version="1.3" manifest:media-type="application/vnd.oasis.opendocument.text"/>'
                '<manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>'
                '<manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/>'
                f'<manifest:file-entry manifest:full-path="meta.xml" manifest:media-type="text/xml"/>{pictures}</manifest:manifest>')
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr(zipfile.ZipInfo("mimetype"), "application/vnd.oasis.opendocument.text", zipfile.ZIP_STORED)
        z.writestr("META-INF/manifest.xml", manifest)
        z.writestr("content.xml", content)
        z.writestr("styles.xml", _odt_styles(doc))
        z.writestr("meta.xml", meta)
        for name, data, _ in o.pictures:
            z.writestr(name, data)


# ── RTF ───────────────────────────────────────────────────────

def _rtf_text(text):
    out = []
    for ch in text:
        o = ord(ch)
        if ch in "\\{}":
            out.append("\\" + ch)
        elif ch == "\n":
            out.append("\\line ")
        elif ch == "\t":
            out.append("\\tab ")
        elif o < 128:
            out.append(ch)
        elif o < 0x10000:
            out.append(f"\\u{o if o < 32768 else o - 65536}?")
        else:
            o -= 0x10000
            hi, lo = 0xD800 + (o >> 10), 0xDC00 + (o & 0x3FF)
            out.append(f"\\u{hi - 65536}?\\u{lo - 65536}?")
    return "".join(out)


class _Rtf:
    def __init__(self, doc):
        self.doc = doc
        self.colors = ["000000", TEXT_COLOR, GRAY, LINK_COLOR, "F2F2F2", "BFBFBF", "F6F8FA"] + sorted(set(COLORS.values()))

    def color(self, hexcolor):
        if hexcolor not in self.colors:
            self.colors.append(hexcolor)
        return self.colors.index(hexcolor) + 1

    def runs(self, runs):
        out = []
        for r in runs:
            if not r.text:
                continue
            f = ""
            if r.flags & B:
                f += "\\b"
            if r.flags & I:
                f += "\\i"
            if r.flags & U or r.link:
                f += "\\ul"
            if r.flags & S:
                f += "\\strike"
            if r.flags & CODE:
                f += "\\f1\\fs18"
            if r.flags & MARK:
                f += "\\highlight7"
            if r.flags & SUP:
                f += "\\super"
            elif r.flags & SUB:
                f += "\\sub"
            if r.link:
                f += f"\\cf{self.color(LINK_COLOR)}"
            body = "{" + f + (" " if f else "") + _rtf_text(r.text) + "}"
            if r.link:
                body = '{\\field{\\*\\fldinst{HYPERLINK "' + r.link.replace("\\", "\\\\").replace('"', "%22") + '"}}{\\fldrslt' + body + "}}"
            out.append(body)
        return "".join(out)

    def code(self, block, numbered):
        out = []
        gray = self.color("A0A0A0")
        if numbered:                     # the number right-aligned at 1 cm, the code from 1.4 cm – wrapped lines too
            start = f"\\pard\\plain\\li{NUMBER_W}\\fi-{NUMBER_W}\\tqr\\tx{NUMBER_W - NUMBER_GAP}\\tx{NUMBER_W}"
        else:
            start = "\\pard\\plain\\cbpat" + str(self.color("F6F8FA"))
        for n, line in enumerate(block.lines, 1):
            parts = "".join("{" + ("\\cf" + str(self.color(COLORS[k])) + " " if k in COLORS else "") + _rtf_text(t) + "}" for k, t in line)
            number = f"\\tab{{\\fs16\\cf{gray} {n}}}\\tab " if numbered else ""
            out.append(f"{start}\\sa0\\sl240\\slmult1\\f1\\fs18\\cf{self.color(TEXT_COLOR)} {number}{parts}\\par\n")
        return "".join(out)

    def image(self, img):
        w, h = fit(img.width * 15, img.height * 15, TEXT_W, PAGE_H - 2 * MARGIN_TB - 1400)
        kind = "\\pngblip" if img.kind == "png" else "\\jpegblip"
        data = img.data.hex()
        lines = "\n".join(data[i:i + 128] for i in range(0, len(data), 128))
        return (f"\\pard\\plain\\sb120\\sa120\\keepn{{\\pict{kind}\\picw{int(img.width)}\\pich{int(img.height)}"
                f"\\picwgoal{int(w)}\\pichgoal{int(h)}\n{lines}}}\\par\n")

    def table(self, t):
        cols = len(t.rows[0])
        weight = [max(4, min(40, max(len(plain(row[i])) for row in t.rows))) for i in range(cols)]
        edges, x = [], 0
        for w in weight:
            x += TEXT_W * w // sum(weight)
            edges.append(x)
        border = "\\brdrs\\brdrw10\\brdrcf" + str(self.color("BFBFBF"))
        out = []
        for r, row in enumerate(t.rows):
            head = r < t.header
            cells = "".join(f"\\clbrdrt{border}\\clbrdrl{border}\\clbrdrb{border}\\clbrdrr{border}"
                            + (f"\\clcbpat{self.color('F2F2F2')}" if head else "") + f"\\cellx{e}" for e in edges)
            out.append("\\trowd\\trgaph100\\trleft0" + ("\\trhdr" if head else "") + cells + "\n")
            for cell in row:
                runs = [x._replace(flags=x.flags | B) for x in cell] if head else cell
                out.append(f"\\pard\\plain\\intbl\\f0\\fs20 {self.runs(runs)}\\cell\n")
            out.append("\\row\n")
        out.append("\\pard\\plain\\sa120\\par\n")
        return "".join(out)

    def body(self):
        doc, out = self.doc, []
        base = f"\\pard\\plain\\f0\\fs22\\sa120\\sl276\\slmult1\\cf{self.color(TEXT_COLOR)}"
        if doc.kind == "code":
            out.append(f"\\pard\\plain\\keepn\\outlinelevel0\\f0\\fs32\\b\\sa40\\cf{self.color(TEXT_COLOR)} {_rtf_text(doc.title)}\\par\n")
            if doc.meta:
                out.append(f"\\pard\\plain\\keepn\\f0\\fs18\\sa240\\brdrb\\brdrs\\brdrw10\\brsp100\\brdrcf{self.color('BFBFBF')}"
                           f"\\cf{self.color(GRAY)} {_rtf_text(doc.meta)}\\par\n")
        sizes = {1: 36, 2: 30, 3: 26, 4: 24, 5: 22, 6: 22}
        for b in doc.blocks:
            if isinstance(b, Heading):
                out.append(f"\\pard\\plain\\keepn\\outlinelevel{b.level - 1}\\f0\\b\\fs{sizes[b.level]}\\sb{280 if b.level < 3 else 200}"
                           f"\\sa100\\cf{self.color(TEXT_COLOR)} {self.runs(b.runs)}\\par\n")
            elif isinstance(b, Para):
                extra = {"quote": f"\\li340\\i\\cf{self.color('404040')}", "caption": f"\\i\\fs18\\cf{self.color(GRAY)}",
                         "term": "\\b\\keepn\\sa40", "meta": f"\\fs18\\cf{self.color(GRAY)}"}.get(b.style, "")
                indent = f"\\li{567 * b.indent}" if b.indent else ""
                out.append(f"{base}{extra}{indent} {self.runs(b.runs)}\\par\n")
            elif isinstance(b, Item):
                left = 360 * (b.level + 1)
                if b.marker:
                    out.append(f"{base}\\sa60\\fi-360\\li{left}\\tx{left} {_rtf_text(b.marker)}\\tab {self.runs(b.runs)}\\par\n")
                else:
                    out.append(f"{base}\\sa60\\li{left} {self.runs(b.runs)}\\par\n")
            elif isinstance(b, Table):
                out.append(self.table(b))
            elif isinstance(b, Image):
                out.append(self.image(b) if b.kind in ("png", "jpeg") else f"{base}\\i {_rtf_text(image_label(b))}\\par\n")
            elif isinstance(b, Rule):
                out.append(f"\\pard\\plain\\sa120\\brdrb\\brdrs\\brdrw10\\brsp20\\brdrcf{self.color('BFBFBF')}\\fs8 \\par\n")
            elif isinstance(b, Code):
                out.append(self.code(b, doc.kind == "code"))
        return "".join(out)


def write_rtf(doc, path, author=""):
    r = _Rtf(doc)
    body = r.body()
    colors = "".join("\\red{}\\green{}\\blue{};".format(int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16)) for c in r.colors)
    left, right = (CODE_MARGIN, CODE_MARGIN) if doc.kind == "code" else (MARGIN_L, MARGIN_R)
    info = "{\\info{\\title " + _rtf_text(label(doc)) + "}" + ("{\\author " + _rtf_text(author) + "}" if author else "") + "}"
    footer = (f"{{\\footer\\pard\\plain\\f0\\fs16\\cf{r.color(GRAY)}\\tqr\\tx{PAGE_W - left - right} {_rtf_text(doc.title)}\\tab "
              "{\\field{\\*\\fldinst PAGE}{\\fldrslt 1}} / {\\field{\\*\\fldinst NUMPAGES}{\\fldrslt 1}}\\par}")
    text = ("{\\rtf1\\ansi\\ansicpg1252\\deff0\\uc1"
            "{\\fonttbl{\\f0\\fswiss\\fprq2\\fcharset0 Helvetica{\\*\\falt Arial};}{\\f1\\fmodern\\fprq1\\fcharset0 Menlo{\\*\\falt Consolas};}}"
            f"{{\\colortbl;{colors}}}{info}\n"
            f"\\paperw{PAGE_W}\\paperh{PAGE_H}\\margl{left}\\margr{right}\\margt{MARGIN_TB}\\margb{MARGIN_TB}\\widowctrl\n"
            f"\\sectd\n{footer}\n{body}}}\n")
    with open(path, "w", encoding="ascii", newline="\n") as f:
        f.write(text)
