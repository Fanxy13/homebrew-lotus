"""Colors for code, like Visual Studio Code's light theme: HTML with the CSS and JavaScript in it, CSS (SCSS, Less),
JavaScript (TypeScript, JSX) and JSON. A tokenizer turns a whole file into (kind, text) pieces – kind is a key of
COLORS, or None for plain text – and lines() splits them into the lines of a document. It never fails: what it does
not know stays plain text.
"""
import os
import re

# VS Code's "Light+" theme: what people see in their editor, and it reads well on white paper
COLORS = {
    "tag": "800000", "attr": "E50000", "value": "0000FF", "comment": "008000", "entity": "E50000",
    "selector": "800000", "property": "E50000", "cssvalue": "0451A5", "number": "098658", "string": "A31515",
    "at": "AF00DB", "keyword": "0000FF", "control": "AF00DB", "function": "795E26", "variable": "001080",
    "type": "267F99", "regex": "811F3F", "key": "0451A5",
}
TEXT_COLOR = "1F1F1F"

LANGS = {
    ".html": "html", ".htm": "html", ".xhtml": "html", ".vue": "html", ".svelte": "html", ".php": "html",
    ".xml": "html", ".svg": "html",
    ".css": "css", ".scss": "scss", ".sass": "scss", ".less": "scss",
    ".js": "js", ".mjs": "js", ".cjs": "js", ".jsx": "js", ".ts": "ts", ".tsx": "ts", ".mts": "ts",
    ".json": "json", ".webmanifest": "json", ".map": "json",
}
NAMES = {"html": "HTML", "css": "CSS", "scss": "SCSS", "js": "JavaScript", "ts": "TypeScript", "json": "JSON", "text": "text"}


def language(path):
    return LANGS.get(os.path.splitext(path)[1].lower(), "text")


def tokens(text, lang):
    out = []
    if lang == "html":
        _html(text, out)
    elif lang in ("css", "scss"):
        _css(text, out, lang == "scss")
    elif lang in ("js", "ts", "json"):
        _js(text, out, lang)
    else:
        out.append((None, text))
    return out


# Characters a document cannot hold (XML forbids most control characters): shown as their symbols ␀ ␁ …
_CONTROL = re.compile("[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")


def visible(text):
    return _CONTROL.sub(lambda m: chr(0x2400 + ord(m.group())) if m.group() != "\x7f" else "␡", text)


def lines(text, lang, tab=4):
    """[[(kind, text), …] for each line] – tabs become spaces (to the next multiple of tab), pieces of one kind
    next to each other are one."""
    text = visible(text.replace("\r\n", "\n").replace("\r", "\n"))
    out, cur, col = [], [], 0
    for kind, piece in tokens(text, lang):
        for i, part in enumerate(piece.split("\n")):
            if i:
                out.append(cur)
                cur, col = [], 0
            if not part:
                continue
            if "\t" in part:
                spaced = []
                for ch in part:
                    if ch == "\t":
                        n = tab - (col % tab)
                        spaced.append(" " * n)
                        col += n
                    else:
                        spaced.append(ch)
                        col += 1
                part = "".join(spaced)
            else:
                col += len(part)
            if cur and cur[-1][0] == kind:
                cur[-1] = (kind, cur[-1][1] + part)
            else:
                cur.append((kind, part))
    out.append(cur)
    if len(out) > 1 and not out[-1]:            # the newline at the end of the file is not one more line
        out.pop()
    return out


# ── HTML (and XML, SVG) ───────────────────────────────────────

_HTML = re.compile(r"""
    (?P<comment><!--.*?(?:-->|\Z))
  | (?P<cdata><!\[CDATA\[.*?(?:\]\]>|\Z))
  | (?P<decl><![^>]*>?)
  | (?P<pi><\?.*?(?:\?>|\Z))
  | (?P<tag></?[A-Za-z][\w:.-]*)
  | (?P<entity>&(?:[A-Za-z][A-Za-z0-9]{1,31}|\#\d{1,7}|\#[xX][0-9A-Fa-f]{1,6});)
  | (?P<text>[^<&]+|[<&])
""", re.S | re.X)

_IN_TAG = re.compile(r"""
    (?P<ws>\s+)
  | (?P<end>/?>)
  | (?P<eq>=)
  | (?P<quoted>"[^"]*(?:"|\Z)|'[^']*(?:'|\Z))
  | (?P<word>[^\s"'=<>/`]+)
  | (?P<other>\S)
""", re.S | re.X)

_HTML_KIND = {"comment": "comment", "cdata": "comment", "decl": "tag", "pi": "tag", "entity": "entity", "text": None}


def _script_lang(attrs):
    t = attrs.get("type", "").strip().lower()
    if t in ("", "module", "text/javascript", "application/javascript", "text/ecmascript", "application/ecmascript", "text/babel", "text/jsx"):
        return "js"
    if "json" in t or t == "importmap":
        return "json"
    if "template" in t or t == "text/html":
        return "html"
    return "text"


def _html(text, out):
    pos, n = 0, len(text)
    while pos < n:
        m = _HTML.match(text, pos)
        g = m.lastgroup
        if g != "tag":
            out.append((_HTML_KIND[g], m.group()))
            pos = m.end()
            continue
        out.append(("tag", m.group()))
        name = m.group().lstrip("</").lower()
        closing = m.group().startswith("</")
        pos = m.end()
        attrs, last, after_eq, end = {}, "", False, ""
        while pos < n:
            a = _IN_TAG.match(text, pos)
            k, s = a.lastgroup, a.group()
            if k == "other" and s == "<":           # a tag that was never closed: the next one starts here
                break
            if k == "end":
                out.append(("tag", s))
                pos, end = a.end(), s
                break
            if k == "eq":
                out.append((None, s))
                after_eq = True
            elif k == "quoted":
                out.append(("value", s))
                if last:
                    attrs[last] = s[1:-1] if len(s) > 1 and s[-1] == s[0] else s[1:]
                after_eq = False
            elif k == "word":
                if after_eq:
                    out.append(("value", s))
                    if last:
                        attrs[last] = s
                else:
                    out.append(("attr", s))
                    last = s.lower()
                    attrs.setdefault(last, "")
                after_eq = False
            else:
                out.append((None, s))
            pos = a.end()
        if end == ">" and not closing and name in ("script", "style"):
            close = re.compile(r"</" + name + r"\b", re.I).search(text, pos)
            end = close.start() if close else n
            out.extend(tokens(text[pos:end], "css" if name == "style" else _script_lang(attrs)))
            pos = end


# ── CSS, SCSS, Less ───────────────────────────────────────────

_CSS_PARTS = r"""
    (?P<comment>/\*.*?(?:\*/|\Z))
  {line}
  | (?P<string>"(?:\\.|[^"\\\n])*"?|'(?:\\.|[^'\\\n])*'?)
  | (?P<ws>\s+)
  | (?P<at>@[\w-]+)
  | (?P<open>\{{)
  | (?P<close>\}})
  | (?P<semi>;)
  | (?P<colon>:)
  | (?P<important>!\s*important\b)
  | (?P<hash>\#[\w-]+)
  | (?P<number>[-+]?(?:\d+(?:\.\d+)?|\.\d+)(?:%|[a-zA-Z]+)?)
  | (?P<word>[\w$-]+)
  | (?P<other>.)
"""
_CSS = re.compile(_CSS_PARTS.format(line=""), re.S | re.X)
_SCSS = re.compile(_CSS_PARTS.format(line=r"| (?P<line>//[^\n]*)"), re.S | re.X)
_STATEMENT_END = re.compile(r""""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|/\*.*?\*/|([;{}])""", re.S)
_NESTING_AT = {"media", "supports", "container", "layer", "document", "scope", "starting-style", "keyframes",
               "-webkit-keyframes", "-moz-keyframes", "include", "mixin", "each", "for", "if", "else", "while"}


def _nested(text, pos):
    """Does the statement at pos open a block (a nested rule) before it ends – or is it a property?"""
    for m in _STATEMENT_END.finditer(text, pos):
        if m.group(1):
            return m.group(1) == "{"
    return False


def _css(text, out, scss):
    stack, phase, at = ["rules"], "start", ""
    for m in (_SCSS if scss else _CSS).finditer(text):
        g, s = m.lastgroup, m.group()
        ctx = stack[-1]
        kind = None
        if g in ("comment", "line"):
            kind = "comment"
        elif g == "string":
            kind = "string"
        elif g == "ws":
            pass
        elif g == "open":
            stack.append("rules" if ctx == "rules" and phase == "at" and at in _NESTING_AT else "decls")
            phase = "start"
        elif g == "close":
            if len(stack) > 1:
                stack.pop()
            phase = "start"
        elif g == "semi":
            phase = "start"
        elif g == "at":
            at, phase, kind = s[1:].lower(), "at", "at"
        elif phase == "at":
            kind = "cssvalue" if g in ("word", "number", "hash") else None
        elif ctx == "rules":
            phase = "selector"
            kind = "selector" if g in ("word", "hash", "colon") or s == "." else None
        else:
            if phase == "start":
                phase = "nested" if _nested(text, m.start()) else "prop"
            if phase == "nested":
                kind = "selector" if g in ("word", "hash", "colon") or s in ".&" else None
            elif phase == "prop":
                if g == "colon":
                    phase = "value"
                elif g == "word":
                    kind = "property"
            else:
                kind = {"number": "number", "hash": "number", "important": "keyword", "word": "cssvalue"}.get(g)
        out.append((kind, s))


# ── JavaScript, TypeScript, JSON ──────────────────────────────

_JS = re.compile(r"""
    (?P<comment>//[^\n]*|/\*.*?(?:\*/|\Z))
  | (?P<string>"(?:\\.|[^"\\\n])*"?|'(?:\\.|[^'\\\n])*'?)
  | (?P<template>`(?:\\.|[^`\\])*`?)
  | (?P<ws>\s+)
  | (?P<number>(?:0[xX][\da-fA-F_]+|0[bB][01_]+|0[oO][0-7_]+|(?:\d[\d_]*(?:\.[\d_]*)?|\.\d[\d_]*)(?:[eE][+-]?\d+)?)n?)
  | (?P<word>[^\W\d][\w$]*|\$[\w$]*)
  | (?P<punct>.)
""", re.S | re.X)
_REGEX = re.compile(r"/(?![*/])(?:\\.|\[(?:\\.|[^\]\\\n])*\]|[^/\\\n\[])+/[a-z]*")
_STORAGE = set("var let const function class extends new this super typeof instanceof in of void delete async static get set".split())
_CONTROL_WORDS = set("if else for while do switch case default break continue return throw try catch finally import export from as await yield with debugger".split())
_CONSTANTS = set("true false null undefined NaN Infinity".split())
_TS_STORAGE = set("interface type enum implements private public protected readonly declare namespace abstract keyof infer is asserts module satisfies override".split())
_TS_TYPES = set("string number boolean any unknown never object symbol bigint".split())
_BEFORE_REGEX = set("return typeof case do else in of new delete void throw yield await instanceof".split())
_BEFORE_TYPE = {"new", "class", "extends", "implements", "interface", "instanceof"}


def _js(text, out, lang):
    pos, n = 0, len(text)
    prev = None                     # the last piece that was not a space or comment: (group, text)
    storage = _STORAGE | _TS_STORAGE if lang == "ts" else _STORAGE
    while pos < n:
        if text[pos] == "/" and lang != "json" and (prev is None or (prev[0] == "punct" and prev[1] not in ")]}")
                                                    or (prev[0] == "word" and prev[1] in _BEFORE_REGEX)):
            r = _REGEX.match(text, pos)
            if r:
                out.append(("regex", r.group()))
                prev, pos = ("regex", r.group()), r.end()
                continue
        m = _JS.match(text, pos)
        g, s = m.lastgroup, m.group()
        kind = None
        if g == "comment":
            kind = "comment"
        elif g in ("string", "template"):
            kind = "string"
            if lang == "json" and _next_char(text, m.end()) == ":":
                kind = "key"
        elif g == "number":
            kind = "number"
        elif g == "word":
            after_dot = prev is not None and prev == ("punct", ".")
            if lang == "json":
                kind = "keyword" if s in ("true", "false", "null") else None
            elif not after_dot and s in _CONTROL_WORDS:
                kind = "control"
            elif not after_dot and (s in storage or s in _CONSTANTS):
                kind = "keyword"
            elif _next_char(text, m.end()) == "(":
                kind = "function"
            elif lang == "ts" and s in _TS_TYPES and not after_dot:
                kind = "type"
            elif prev is not None and prev[0] == "word" and prev[1] in _BEFORE_TYPE:
                kind = "type"
            else:
                kind = "variable"
        out.append((kind, s))
        if g not in ("ws", "comment"):
            prev = (g, s)
        pos = m.end()


_NEXT = re.compile(r"\s*(\S)")


def _next_char(text, pos):
    m = _NEXT.match(text, pos)
    return m.group(1) if m else ""
