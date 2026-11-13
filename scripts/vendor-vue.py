#!/usr/bin/env python3
"""Makes lib/live/vue/ – Vue 3 for the Live Server (/liveserver) – from the npm registry.

    python3 scripts/vendor-vue.py            download, check, write (or say that the files are what they should be)

What it takes from two packages, each checked against the sha512 the registry itself publishes for it (pinned below – a package
that changed is refused):

    vue 3.5.45                 dist/vue.esm-browser.js           → lib/live/vue/vue.js          as it is
        Vue with its template compiler, as an ES module for the browser: the page's `import { createApp } from 'vue'` gets it
        (through an import map the Live Server puts into the page), so that pages without a build step – `template: '…'`
        strings, a template in the HTML itself – work as well as the compiled .vue files do.
    @vue/compiler-sfc 3.5.45   dist/compiler-sfc.esm-browser.js  → lib/live/vue/compiler-sfc.js  last line changed
        The compiler of .vue files, with everything it needs inside (Babel's parser, PostCSS …), no Node. Its only `export`
        (the last line) becomes `globalThis.VueCompilerSFC = { … }`: the program that runs it – JavaScriptCore on a Mac, in the
        tests Node – takes a script, not a module. Nothing else is changed.
    LICENSE                                                      → lib/live/vue/LICENSE         (the same in both packages)

Python's standard library only. The SHA-256 of the files it writes are in THIRD_PARTY.md (tests/live/vue_test.js checks them).
To move to another Vue 3 version: change VERSION and the two sha512 values (the registry's `dist.integrity` of
https://registry.npmjs.org/vue/<version> and https://registry.npmjs.org/@vue%2fcompiler-sfc/<version>), run it, read the diff of
the compile glue's tests, and put the new SHA-256 into THIRD_PARTY.md.
"""
import base64
import hashlib
import io
import os
import re
import sys
import tarfile
import urllib.request

VERSION = "3.5.45"
PACKAGES = (
    ("vue", "https://registry.npmjs.org/vue/-/vue-%s.tgz" % VERSION,
     "sha512-3cvsib8m9c0vB24+MDKsgcW4+Da4xaBl9Z/5Tbm2pmSIsRPxcil4cdXjXlVsmJ2g64XJo5h+IRd7rsdGT9pZaw==",
     "package/dist/vue.esm-browser.js", "vue.js"),
    ("@vue/compiler-sfc", "https://registry.npmjs.org/@vue/compiler-sfc/-/compiler-sfc-%s.tgz" % VERSION,
     "sha512-MKFjb2UX0M/l/jhfzqMLrI8VM4pfvFKG3pqFZkSZFHRLtNld/O4RtUPZFWSwhro/14qP88UQEkWzHxAZAQ0tsw==",
     "package/dist/compiler-sfc.esm-browser.js", "compiler-sfc.js"),
)
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "lib", "live", "vue")


def fetch(url):
    with urllib.request.urlopen(url, timeout=120) as r:
        return r.read()


def integrity(data):
    return "sha512-" + base64.b64encode(hashlib.sha512(data).digest()).decode()


def member(tgz, name):
    """One file of a package – read, never extracted to disk."""
    with tarfile.open(fileobj=io.BytesIO(tgz), mode="r:gz") as tar:
        f = tar.extractfile(name)
        if f is None:
            raise SystemExit("%s is not in the package" % name)
        return f.read()


def as_script(source):
    """The compiler's ES module as a script: its last line, `export { a, b as c };`, becomes `globalThis.VueCompilerSFC = { a, c: b };`.
    (Other `export` words in the file are text inside the compiler's own template literals, not statements.)"""
    lines = source.decode("utf-8").rstrip("\n").split("\n")
    m = re.fullmatch(r"export \{ (.+) \};", lines[-1])
    if not m:
        raise SystemExit("the last line of the compiler is not an export list any more – this script has to learn the new form")
    pairs = []
    for item in m.group(1).split(", "):
        a, _, b = item.partition(" as ")
        pairs.append("%s: %s" % (b, a) if b else a)
    lines[-1] = "globalThis.VueCompilerSFC = { %s };" % ", ".join(pairs)
    return ("\n".join(lines) + "\n").encode("utf-8")


def main():
    files, license_text = {}, None
    for name, url, want, inside, target in PACKAGES:
        print("%s %s …" % (name, VERSION), flush=True)
        tgz = fetch(url)
        got = integrity(tgz)
        if got != want:
            raise SystemExit("%s: the package is not the one this script knows (%s)" % (name, got))
        data = member(tgz, inside)
        files[target] = as_script(data) if target == "compiler-sfc.js" else data
        lic = member(tgz, "package/LICENSE")
        if license_text not in (None, lic):
            raise SystemExit("the two packages do not have the same LICENSE any more")
        license_text = lic
    files["LICENSE"] = license_text
    os.makedirs(OUT, exist_ok=True)
    for target, data in files.items():
        path = os.path.join(OUT, target)
        same = os.path.exists(path) and open(path, "rb").read() == data
        if not same:
            with open(path, "wb") as f:
                f.write(data)
        print("  %-17s %9d bytes  SHA-256 %s  %s" % (os.path.relpath(path, ROOT), len(data), hashlib.sha256(data).hexdigest(),
                                                 "as it was" if same else "written"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
