"""The image editor's page (lib/edit/web): its texts exist in every language and fit their places, and it keeps to the content policy
the server sends (no inline script, no inline style, no handlers in the markup). python3 tests/edit/page_test.py"""
import json
import os
import re

from kit import EDIT, finish, test

import engine as E

WEB = os.path.join(EDIT, "web")
read = lambda name: open(os.path.join(WEB, name), encoding="utf-8").read()
HTML, CSS = read("index.html"), read("editor.css")
JS = read("editor.js") + read("blur.js") + read("faces.js") + read("faces-worker.js")     # (everything that runs in the page)
S = json.loads(read("strings.json"))
EN = S["en"]
QUALITIES, SIZES = (95, 85, 70, 50), (0, 3840, 2560, 1920, 1280, 640)


def keys_used():
    keys = {k for k in re.findall(r"""\bt\('([a-z0-9_]+)'""", JS) if not k.endswith("_")}      # (t('fmt_' + …) is a prefix: below)
    keys |= set(re.findall(r'data-t="([a-z0-9_]+)"', HTML))
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


@test("the page keeps to its content policy: no inline script, no inline style, no handlers in the markup")
def _():
    assert not re.search(r"\sstyle\s*=", HTML), "style attribute"
    assert not re.search(r"<style", HTML, re.I), "style block"
    assert not re.search(r"\son[a-z]+\s*=", HTML), "event handler attribute"
    for m in re.finditer(r"<script([^>]*)>", HTML):
        assert "src=" in m.group(1) or 'type="application/json"' in m.group(1), m.group(0)
    assert "setAttribute('style'" not in JS and ".innerHTML" not in JS and "eval(" not in JS, "JS the policy would stop (or that is unsafe)"
    assert "https://" not in HTML + JS + CSS and "http://" not in re.sub(r"http://www\.w3\.org/2000/svg", "", HTML + JS + CSS), "nothing is fetched from elsewhere"


@test("every id the script asks for is in the page")
def _():
    ids = set(re.findall(r'\bid="([\w-]+)"', HTML))
    asked = set(re.findall(r"""\$\('([\w-]+)'\)""", JS))
    assert not asked - ids, sorted(asked - ids)


@test("the word 'gone' on the hint cannot clash with the overlay of the same name any more")
def _():
    assert "hint').classList.add('away')" in JS and ".hint.away" in CSS and ".hint.gone" not in CSS

@test("the Face Blur tab: its kinds of hiding are the ones blur.js knows, and every file the page loads is one the server sends")
def _():
    assert re.search(r"var TYPES = \['blur', 'pixel', 'solid'\]", read("blur.js"))
    import editor as ED
    for name in re.findall(r'src="web/([\w.-]+)"', HTML) + ["faces-worker.js", "faces.js", "faces.bin"]:
        assert name in ED.ASSETS, name
        assert os.path.isfile(os.path.join(WEB, name)), name
    assert "importScripts('faces.js')" in read("faces-worker.js") and "fetch('faces.bin')" in read("faces-worker.js")
    assert "new Worker(base + 'web/faces-worker.js')" in read("editor.js")

finish()
