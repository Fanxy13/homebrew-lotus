"""What a converted file is before it becomes a format: a document of blocks.

A file as code is a title, a line about it and one Code block. A page (--page) is what a visitor reads: headings,
paragraphs, list items, tables, images, rules and code. Text in them is a list of Runs – a piece of text with its
formatting (the flags below) and maybe a link. Every writer (txt, md, docx, odt, rtf, pdf) knows all of them.
"""
from collections import namedtuple

# Formatting of a run, as bits
B, I, U, S, CODE, MARK, SUP, SUB = 1, 2, 4, 8, 16, 32, 64, 128

Run = namedtuple("Run", "text flags link")          # a "\n" in text is a line break (<br>)

Heading = namedtuple("Heading", "level runs")        # level 1–6
Para = namedtuple("Para", "runs style indent")      # style: normal, quote, caption, term, meta
Item = namedtuple("Item", "level marker runs")      # a list item: marker "•", "1.", "a." – "" continues the item
Table = namedtuple("Table", "rows header")          # rows: [[runs of a cell, …], …]; header: how many rows are head
Image = namedtuple("Image", "data kind width height alt src")    # kind png, jpeg or gif; width, height in pixels;
                                                                  # src: its file, "" when it was in the page
Rule = namedtuple("Rule", "")
Code = namedtuple("Code", "lines numbers lang")     # lines: [[(kind, text), …], …] – kind is a color of highlight.py;
                                                     # lang: html, css, scss, js, ts, json or text


class Document:
    def __init__(self, title, blocks, kind="code", meta="", lang="en"):
        self.title = title          # the file, as it is called in the folder: css/style.css
        self.blocks = blocks
        self.kind = kind            # code or page
        self.meta = meta            # one line under the title: the folder, lines, size, when it changed
        self.lang = lang            # the page's language (<html lang>), for the documents' metadata


def plain(runs):
    """The text of runs, without formatting."""
    return "".join(r.text for r in runs)


def merge(runs):
    """Runs next to each other with the same formatting become one."""
    out = []
    for r in runs:
        if not r.text:
            continue
        if out and out[-1].flags == r.flags and out[-1].link == r.link and "\n" not in (r.text, out[-1].text):
            out[-1] = Run(out[-1].text + r.text, r.flags, r.link)
        else:
            out.append(r)
    return out
