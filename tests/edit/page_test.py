"""The image editor's pages (lib/edit/web: the editor, and the drop page of /img without a picture): their texts exist in every
language and fit their places, and they keep to the content policy the server sends (no inline script, no inline style, no handlers
in the markup). python3 tests/edit/page_test.py"""
import json
import os
import re

from kit import EDIT, finish, test

import engine as E

WEB = os.path.join(EDIT, "web")
read = lambda name: open(os.path.join(WEB, name), encoding="utf-8").read()
HTML, CSS = read("index.html"), read("editor.css")
JS = read("editor.js") + read("blur.js") + read("faces.js") + read("faces-worker.js")     # (everything that runs in the page)
DROP_HTML, DROP_JS = read("drop.html"), read("drop.js")                                  # the drop page
PAGES = (("the editor", HTML, read("editor.js")), ("the drop page", DROP_HTML, DROP_JS))
S = json.loads(read("strings.json"))
EN = S["en"]
QUALITIES, SIZES = (95, 85, 70, 50), (0, 3840, 2560, 1920, 1280, 640)


def keys_used():
    keys = {k for k in re.findall(r"""\bt\('([a-z0-9_]+)'""", JS + DROP_JS) if not k.endswith("_")}   # (t('fmt_' + …): below)
    keys |= set(re.findall(r'data-t="([a-z0-9_]+)"', HTML + DROP_HTML))
    keys |= {"drop_here", "drop_release"}                                          # t(on ? 'drop_release' : 'drop_here')
    keys |= {"t_" + k for k in re.findall(r'data-(?:title|label)="([a-z0-9_]+)"', HTML)}
    keys |= {"fmt_" + f[0] for f in E.FORMATS}                                    # t('fmt_' + format)
    keys |= {"q_%d" % q for q in QUALITIES} | {"q_%d_d" % q for q in QUALITIES}   # t('q_' + quality)
    keys |= {"size_%d" % s for s in SIZES}                                        # SIZE_NAMES
    keys |= {"ratio_portrait", "ratio_landscape"}                                  # t('ratio_' + …)
    keys |= {"fb_type_blur", "fb_type_pixel", "fb_type_solid"}                     # t('fb_type_' + type) – LotusBlur.TYPES
    return keys


@test("the languages of Lotus: English, German, French and Spanish – each with the same texts")
def _():
    assert set(S) == {"en", "de", "fr", "es"}, set(S)
    for lang in ("de", "fr", "es"):
        missing = set(EN) - set(S[lang])
        extra = set(S[lang]) - set(EN)
        assert not missing and not extra, "%s: missing %s, extra %s" % (lang, sorted(missing), sorted(extra))


@test("every text the page asks for is there")
def _():
    missing = keys_used() - set(EN)
    assert not missing, sorted(missing)


@test("no text is left over that nothing asks for")
def _():
    unused = set(EN) - keys_used()
    assert not unused, sorted(unused)


@test("a text keeps its %s places in every language (a name, a folder, a number)")
def _():
    for key, text in EN.items():
        for lang in ("de", "fr", "es"):
            assert S[lang][key].count("%s") == text.count("%s"), "%s %s: %r vs %r" % (lang, key, S[lang][key], text)
    assert EN["save_note"].count("%s") == 2, "the page puts the name first, the folder second"


@test("nothing is empty, nothing has a stray space at its ends, and no emoji")
def _():
    emoji = re.compile("[\U0001F000-\U0001FAFF☀-➿⭐✅]")
    for lang, table in S.items():
        for key, text in table.items():
            assert text and text == text.strip(), (lang, key)
            assert not emoji.search(text), (lang, key)


@test("both pages keep to their content policy: no inline script, no inline style, no handlers in the markup")
def _():
    for what, html, _js in PAGES:
        assert not re.search(r"\sstyle\s*=", html), (what, "style attribute")
        assert not re.search(r"<style", html, re.I), (what, "style block")
        assert not re.search(r"\son[a-z]+\s*=", html), (what, "event handler attribute")
        for m in re.finditer(r"<script([^>]*)>", html):
            assert "src=" in m.group(1) or 'type="application/json"' in m.group(1), (what, m.group(0))
    every = HTML + DROP_HTML + JS + DROP_JS + CSS
    assert "setAttribute('style'" not in JS + DROP_JS and ".innerHTML" not in JS + DROP_JS and "eval(" not in JS + DROP_JS, "JS the policy would stop (or that is unsafe)"
    assert "https://" not in every and "http://" not in re.sub(r"http://www\.w3\.org/2000/svg", "", every), "nothing is fetched from elsewhere"


@test("every id a script asks for is in its own page")
def _():
    for what, html, js in PAGES:
        ids = set(re.findall(r'\bid="([\w-]+)"', html))
        asked = set(re.findall(r"""\$\('([\w-]+)'\)""", js))
        assert not asked - ids, (what, sorted(asked - ids))


@test("the drop page sends the picture to the editor's own server only, and takes what the server says a picture is")
def _():
    assert re.findall(r"fetch\(([^,]+)", DROP_JS) == ["base + 'api/drop?name=' + encodeURIComponent(name) + '&count=' + count",
                                                      "base + path", "base + 'api/bye'"], re.findall(r"fetch\(([^,]+)", DROP_JS)
    assert "cfg.pictures" in DROP_JS and "cfg.max" in DROP_JS and "location.replace(base)" in DROP_JS
    assert "cfg.drop" in read("editor.js") and "'image?pic=' + cfg.pic" in read("editor.js") and "'&pic=' + cfg.pic" in read("editor.js")


@test("the drop page offers the pictures /img reads – IMG_EXT of lib/cmd/img.zsh, in the same order")
def _():
    import editor as ED
    with open(os.path.join(os.path.dirname(EDIT), "cmd", "img.zsh"), encoding="utf-8") as f:
        zsh = f.read().split("typeset -ga IMG_EXT=(")[1].split(")")[0].split()
    assert zsh == list(ED.PICTURES), "%r != %r" % (zsh, ED.PICTURES)


@test("the word 'gone' on the hint cannot clash with the overlay of the same name any more")
def _():
    assert "hint').classList.add('away')" in JS and ".hint.away" in CSS and ".hint.gone" not in CSS

@test("the Face Blur tab: its kinds of hiding are the ones blur.js knows, and every file the page loads is one the server sends")
def _():
    assert re.search(r"var TYPES = \['blur', 'pixel', 'solid'\]", read("blur.js"))
    import editor as ED
    for name in re.findall(r'src="web/([\w.-]+)"', HTML + DROP_HTML) + ["faces-worker.js", "faces.js", "faces.bin"]:
        assert name in ED.ASSETS, name
        assert os.path.isfile(os.path.join(WEB, name)), name
    assert "importScripts('faces.js')" in read("faces-worker.js") and "fetch('faces.bin')" in read("faces-worker.js")
    assert "new Worker(base + 'web/faces-worker.js')" in read("editor.js")

finish()
