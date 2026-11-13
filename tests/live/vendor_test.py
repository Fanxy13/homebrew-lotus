"""The Vue files of the Live Server (lib/live/vue/) are the ones THIRD_PARTY.md names, made by scripts/vendor-vue.py: their checksums,
their versions, and the one line that was changed. It only reads the files – nothing of Vue is run. python3 tests/live/vendor_test.py"""
import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
VUE = os.path.join(ROOT, "lib", "live", "vue")
PASSED, FAILED = [0], [0]


def test(what):
    def run(fn):
        try:
            fn()
            PASSED[0] += 1
            print("  ✓ " + what, flush=True)
        except Exception:
            FAILED[0] += 1
            import traceback
            print("  ✗ " + what + "\n      " + traceback.format_exc().strip().replace("\n", "\n      "), flush=True)
        return fn
    return run


def read(*path):
    with open(os.path.join(*path), "rb") as f:
        return f.read()


THIRD = read(ROOT, "THIRD_PARTY.md").decode("utf-8")
SCRIPT = read(ROOT, "scripts", "vendor-vue.py").decode("utf-8")
VERSION = re.search(r'^VERSION = "([\d.]+)"', SCRIPT, re.M).group(1)


@test("THIRD_PARTY.md names each vendored file with its SHA-256")
def _():
    for name in ("vue.js", "compiler-sfc.js", "LICENSE"):
        digest = hashlib.sha256(read(VUE, name)).hexdigest()
        assert digest in THIRD, "%s: %s is not in THIRD_PARTY.md" % (name, digest)
        assert "lib/live/vue/" + name in THIRD, name


@test("THIRD_PARTY.md has the licence text of the files, word for word")
def _():
    block = THIRD.split("### Vue 3 – .vue files")[1].split("```")[1].strip("\n")
    assert block == read(VUE, "LICENSE").decode("utf-8").strip("\n")
    assert "Evan) You" in block and "MIT License" in block


@test("the version of the script, of both files and of THIRD_PARTY.md is the same")
def _():
    assert re.search(r"^\* vue v%s$" % re.escape(VERSION), read(VUE, "vue.js").decode("utf-8")[:300], re.M)
    assert re.search(r"^\* @vue/compiler-sfc v%s$" % re.escape(VERSION), read(VUE, "compiler-sfc.js").decode("utf-8")[:300], re.M)
    assert "Vue %s" % VERSION in THIRD or "**Vue %s**" % VERSION in THIRD
    assert 'const version = "%s";' % VERSION in read(VUE, "compiler-sfc.js").decode("utf-8")


@test("the packages the script accepts are pinned by the registry's own sha512 – a package that changed is refused")
def _():
    pins = re.findall(r'"(sha512-[A-Za-z0-9+/]{86}==)"', SCRIPT)
    assert len(pins) == 2 and len(set(pins)) == 2, pins
    assert "https://registry.npmjs.org/vue/-/vue-%s.tgz" % VERSION in SCRIPT or '"https://registry.npmjs.org/vue/-/vue-%s.tgz" % VERSION' in SCRIPT


@test("the compiler is a script: its only change is the last line, which sets globalThis.VueCompilerSFC")
def _():
    text = read(VUE, "compiler-sfc.js").decode("utf-8")
    lines = text.rstrip("\n").split("\n")
    assert lines[-1].startswith("globalThis.VueCompilerSFC = { ") and lines[-1].endswith(" };"), lines[-1][:80]
    assert text.count("globalThis.VueCompilerSFC") == 1
    names = re.findall(r"(\w+)(?::| ?[,}])", lines[-1].split("{", 1)[1])
    for needed in ("compileScript", "compileTemplate", "compileStyle", "parse", "version", "rewriteDefault", "generateCodeFrame"):
        assert needed in lines[-1], needed
    assert not re.search(r"^(import|export) [{*\w]", "\n".join(lines[:-1]).split("`")[0], re.M), "no module statement before the first template literal"


@test("the runtime stays the ES module Vue published (a page imports it)")
def _():
    text = read(VUE, "vue.js").decode("utf-8").rstrip("\n").split("\n")
    assert text[-1].startswith("export { ") and "createApp" in text[-1] and "compile" in text[-1], "the full build: createApp and the template compiler"


@test("the glue is there and answers the two things the host asks of it")
def _():
    glue = read(VUE, "sfc.js").decode("utf-8")
    assert "root.lotusRequest = function" in glue and "VueCompilerSFC" in glue and "req.op === 'version'" in glue


@test("the vendored files are marked in .gitattributes: no diffs, not counted as a language")
def _():
    attrs = read(ROOT, ".gitattributes").decode("utf-8")
    for name in ("vue.js", "compiler-sfc.js"):
        assert re.search(r"^lib/live/vue/%s -diff linguist-vendored$" % re.escape(name), attrs, re.M), name


print("\n%d passed, %d failed" % (PASSED[0], FAILED[0]))
sys.exit(1 if FAILED[0] else 0)
