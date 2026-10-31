#!/usr/bin/env python3
"""Checks the website (docs/ plus the shared data/ and logos/ that the site workflow copies next to it):
every local link, script, stylesheet and image exists, every #anchor of a local page exists, the data files the pages
fetch are there, and no emoji appears anywhere (the Lotus mark is an SVG).  Run: python3 scripts/check-site.py"""
import re, sys, pathlib
from html.parser import HTMLParser

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
SITE = [DOCS, ROOT]          # a path is found in docs/ first, then at the top (data/, logos/, CHANGELOG.md are copied in)

EMOJI = re.compile("[\U0001F000-\U0001FAFF⭐⭕⌚⌛⏩-⏳⏸-⏺◽◾☔☕♈-♓"
                   "♿⚓⚡⚪⚫⚽⚾⛄⛅⛎⛔⛪⛲⛳⛵⛺⛽✅"
                   "✊✋✨❌❎❓-❕❗➕-➗➰➿⬛⬜〰〽㊗㊙️]")

class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.refs, self.ids = [], set()
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if "id" in a: self.ids.add(a["id"])
        if tag == "a" and "name" in a: self.ids.add(a["name"])
        for key in ("href", "src"):
            if a.get(key): self.refs.append((tag, a[key]))

def find(rel):
    for base in SITE:
        p = (base / rel).resolve()
        if p.exists(): return p
    return None

problems, pages = [], {}
slug = lambda t: re.sub(r"[^a-z0-9]+", "-", t.lower())
for f in sorted(DOCS.glob("*.html")):
    text = f.read_text(encoding="utf-8")
    p = Page(); p.feed(text); pages[f.name] = p
    for m in EMOJI.finditer(text):
        problems.append(f"{f.name}: emoji U+{ord(m.group()):04X}")
for f in sorted(list(DOCS.glob("*.html")) + list((DOCS / "js").glob("*.js")) + list((DOCS / "css").glob("*.css"))):
    for m in EMOJI.finditer(f.read_text(encoding="utf-8")):
        if f.suffix != ".html": problems.append(f"{f.relative_to(ROOT)}: emoji U+{ord(m.group()):04X}")

# the commands page makes one section per category of data/commands.tsv, with the category as id (js/commands.js)
if "commands.html" in pages:
    for line in (ROOT / "data" / "commands.tsv").read_text(encoding="utf-8").splitlines():
        if line and not line.startswith("#"):
            pages["commands.html"].ids.add(slug(line.split("\t")[0]))

for name, p in pages.items():
    for tag, ref in p.refs:
        if re.match(r"^(https?:|mailto:|data:|javascript:|//)", ref): continue
        path, _, frag = ref.partition("#")
        path = path.split("?")[0]
        if path == "":
            target = pages[name]
        else:
            if find(path) is None: problems.append(f"{name}: <{tag}> {ref} does not exist"); continue
            target = pages.get(path)
        if frag and target is not None and frag not in target.ids and not re.match(r"^(top|)$", frag):
            problems.append(f"{name}: {ref} – no element with that id")

# the data files the scripts fetch
for js in (DOCS / "js").glob("*.js"):
    for m in re.finditer(r"tsv\('([a-z-]+)'\)", js.read_text(encoding="utf-8")):
        if find(f"data/{m.group(1)}.tsv") is None: problems.append(f"{js.name}: data/{m.group(1)}.tsv is missing")

if problems:
    print("\n".join(sorted(set(problems))))
    print(f"\n{len(set(problems))} problem(s)")
    sys.exit(1)
print(f"site ok: {len(pages)} pages, no broken local link, no emoji")
