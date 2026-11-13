"""What lib/live/vuesfc.py does around the compiler – no network, no compiler (a stand-in host speaks the same lines): the import map in a
page, which request is a script's import, the module that shows an error, the stylesheet a script imports, the program that carries the
compiler (its lines, its start, a crash, too long an answer, no program at all). python3 tests/live/vuesfc_test.py"""
import json
import os
import re
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "lib", "live"))
import vuesfc as V                                                    # noqa: E402

PASSED, FAILED = [0], [0]


def test(what):
    def run(fn):
        try:
            fn()
            PASSED[0] += 1
            print("  ✓ " + what, flush=True)
        except Exception as e:
            FAILED[0] += 1
            import traceback
            print("  ✗ " + what + "\n      " + traceback.format_exc().strip().replace("\n", "\n      "), flush=True)
        return fn
    return run


MAP = b'<script type="importmap">{"imports":{"vue":"/__lotus/vue/vue.js"}}</script>'


@test("a page with a module script gets an import map for vue, in front of its first script")
def _():
    page = b'<!doctype html><html><head><title>x</title></head><body><div id="app"></div><script type="module" src="/src/main.js"></script></body></html>'
    got = V.with_vue(page)
    assert got == page.replace(b'<script type="module"', MAP + b'<script type="module"'), got
    classic_first = b'<html><body><script src="a.js"></script><script type=module>import "x"</script></body></html>'
    got = V.with_vue(classic_first)
    assert got.index(MAP) < got.index(b'<script src="a.js">'), "an import map must come before every module is loaded"
    assert V.with_vue(b"<SCRIPT TYPE='module'>1</SCRIPT>").startswith(MAP), "upper case, single quotes"


@test("a page without a module script is left as it is – nothing in it can ask for vue")
def _():
    for page in (b"<p>plain</p>", b'<script src="a.js"></script>', b"<script type=text/javascript>1</script>", b'<script type="importmap">{}</script>'):
        assert V.with_vue(page) == page, page


@test("a page that has an import map gets vue put into it – and keeps its own entries; one that names vue is left alone")
def _():
    page = b'<script type="importmap">{"imports": {"lodash": "https://cdn.example/lodash.js"}, "scopes": {}}</script><script type="module">1</script>'
    got = V.with_vue(page)
    found = json.loads(re.search(rb"<script type=\"importmap\">(.*?)</script>", got).group(1))
    assert found == {"imports": {"lodash": "https://cdn.example/lodash.js", "vue": "/__lotus/vue/vue.js"}, "scopes": {}}, found
    assert got.count(b"importmap") == 1, "one import map: browsers use only the first"
    mine = b'<script type="importmap">{"imports":{"vue":"https://unpkg.com/vue@3/dist/vue.esm-browser.js"}}</script><script type="module">1</script>'
    assert V.with_vue(mine) == mine
    no_imports = b'<script type="importmap">{"scopes":{}}</script><script type="module">1</script>'
    assert b'"imports": {"vue"' in V.with_vue(no_imports)
    for broken in (b'<script type="importmap">{not json</script><script type="module">1</script>',
                   b'<script type="importmap">{"imports": []}</script><script type="module">1</script>'):
        assert V.with_vue(broken) == broken, "an import map that is not one is the page's business"


@test("which request is a script's import: Sec-Fetch-Dest says; where it is not sent, a request for anything is")
def _():
    h = lambda **kw: {k.replace("_", "-"): v for k, v in kw.items()}
    assert V.wants_module(h(Sec_Fetch_Dest="script")) and V.from_script(h(Sec_Fetch_Dest="script"))
    for dest in ("empty", "style", "document", "image", "iframe"):
        assert not V.wants_module(h(Sec_Fetch_Dest=dest, Accept="*/*")), dest
    assert V.wants_module({}) and V.wants_module({"Accept": "*/*"}) and not V.from_script({"Accept": "*/*"})
    assert not V.wants_module({"Accept": "text/css,*/*;q=0.1"}) and not V.wants_module({"Accept": "text/html,application/xhtml+xml,*/*;q=0.8"})
    assert V.navigation(h(Sec_Fetch_Mode="navigate")) and not V.navigation(h(Sec_Fetch_Mode="cors", Accept="text/html"))
    assert V.navigation({"Accept": "text/html,application/xhtml+xml"}) and not V.navigation({"Accept": "*/*"}) and not V.navigation({})


@test("a file that cannot be compiled becomes a module that shows it in the page and fails – the text cannot end the script")
def _():
    errors = [{"message": "Unexpected </script> token", "line": 4, "column": 2}, {"message": "second"}]
    code = V.error_module("src/A.vue", errors)
    assert "globalThis.__lotusError" in code and "throw new Error(" in code
    assert "</script" not in code and "<" not in code.replace("\\u003c", ""), "a '<' in a message is escaped"
    assert 'src/A.vue:4 – Unexpected \\u003c/script\\u003e token' in code, code
    node = subprocess.run(["node", "-e", "const c = require('fs').readFileSync(0,'utf8'); globalThis.seen = []; globalThis.__lotusError = (i) => seen.push(i);"
                           "try { new Function(c)(); } catch (e) { console.log(JSON.stringify([e.message, seen])); }"], input=code,
                          capture_output=True, text=True) if subprocess.run(["which", "node"], capture_output=True).returncode == 0 else None
    if node:
        message, seen = json.loads(node.stdout)
        assert message == "src/A.vue:4 – Unexpected </script> token" and seen[0]["file"] == "src/A.vue" and seen[0]["errors"] == errors, node.stdout
    assert V.error_module("x.vue", []).count("throw new Error") == 1, "no errors in the list is no reason to fail without a word"


@test("a stylesheet a script imports becomes a <link> to its own address – once")
def _():
    code = V.css_module("/src/assets/main.css")
    assert 'link.rel = "stylesheet"' in code and 'link.href = "/src/assets/main.css"' in code and "export default" in code
    assert code.count("document.createElement") == 1 and "querySelector" in code, "there is one link for it, however often it is imported"


# ── the program that carries the compiler ──
STUB = [sys.executable, "-B", os.path.join(HERE, "stub-host.py")]
D = tempfile.mkdtemp(prefix="lotus-vuesfc-test.")
LINES = []
say, log = (lambda text="": LINES.append(text)), (lambda mark, text, code=None: LINES.append("%s %s" % (mark, text)))


def compiler(host, **env):
    os.environ.pop("LOTUS_VUE_HOST", None)
    os.environ.update(env)
    if host:
        os.environ["LOTUS_VUE_HOST"] = " ".join(host) if isinstance(host, list) else host
    return V.Compiler(say, log)


def vue_file(name, text):
    path = os.path.join(D, name)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    return path


@test("the compile program gets a request and gives the module – its lines are JSON, whatever the file says")
def _():
    c = compiler(STUB)
    try:
        text = '<template><p>Grüezi – 日本語 \U0001F338 "quotes" \\ backslash\nline two</p></template>\n'
        code, errors = c.module("src/A.vue", vue_file("a.vue", text))
        assert errors is None and code.startswith('export default { stub: "src/A.vue"'), (code, errors)
        assert json.loads(re.search(r"source: (\".*\") \};", code).group(1)) == text, "the source arrived as it was"
        big = "<template>" + "x" * 3_000_000 + "</template>\n"
        code, errors = c.module("src/Big.vue", vue_file("big.vue", big))
        assert errors is None and ("size: %d," % len(big.encode())) in code, "a file of three megabytes goes through the pipe"
    finally:
        c.close()


@test("what was compiled is kept until the file changes: the program is asked once")
def _():
    count = os.path.join(D, "count")
    c = compiler(STUB, LOTUS_STUB_COUNT=count)
    try:
        path = vue_file("b.vue", "<template>1</template>")
        first = c.module("b.vue", path)
        assert c.module("b.vue", path) == first and c.module("b.vue", path) == first
        asked = open(count).read().split()
        assert asked.count("b.vue") == 1 and asked.count("version") == 1, asked
        time.sleep(0.02)
        vue_file("b.vue", "<template>22</template>")
        os.utime(path, ns=(time.time_ns(), time.time_ns() + 5_000_000))
        second = c.module("b.vue", path)
        assert second != first and open(count).read().split().count("b.vue") == 2
    finally:
        c.close()
        os.environ.pop("LOTUS_STUB_COUNT", None)


@test("an error goes to the page and to the terminal – once for each state of the file")
def _():
    del LINES[:]
    c = compiler(STUB)
    try:
        path = vue_file("c.vue", "<template>BREAK</template>")
        for _ in range(3):
            code, errors = c.module("src/c.vue", path)
        assert code is None and errors == [{"message": "BREAK in src/c.vue", "line": 2, "column": 3}], errors
        shown = [l for l in LINES if "BREAK" in l]
        assert shown == ["✗ src/c.vue:2  BREAK in src/c.vue"], LINES
    finally:
        c.close()


@test("a program that ends in the middle of a request is started again once – and a file that always ends it is an error, not a hang")
def _():
    c = compiler(STUB)
    try:
        code, errors = c.module("d.vue", vue_file("d.vue", "<template>CRASH</template>"))
        assert code is None and "did not answer" in errors[0]["message"], errors
        code, errors = c.module("e.vue", vue_file("e.vue", "<template>fine</template>"))
        assert errors is None and "e.vue" in code, "and the next file is compiled by a program that was started again"
    finally:
        c.close()


@test("no program, or one that does not start, says so – as an error of the file, with the reason")
def _():
    c = compiler("/nonexistent/lotus-vue-host")
    code, errors = c.module("f.vue", vue_file("f.vue", "<template>1</template>"))
    assert code is None and "did not start" in errors[0]["message"], errors
    c = compiler(None)
    saved = sys.platform
    try:
        V.sys.platform = "linux"
        c = compiler(None)
        code, errors = c.module("f.vue", vue_file("f.vue", "<template>1</template>"))
        assert code is None and errors[0]["message"] == V.NOT_HERE, errors
        V.sys.platform = "darwin"
        os.environ.pop("LOTUS_BIN", None)
        c = compiler(None)
        code, errors = c.module("f.vue", vue_file("f.vue", "<template>1</template>"))
        assert code is None and "lotus liveserver" in errors[0]["message"], errors
    finally:
        V.sys.platform = saved


@test("a program that says it cannot load the compiler is believed")
def _():
    bad = vue_file("fatal-host.py", 'import sys\nprint(\'{"fatal": "compiler-sfc.js: SyntaxError"}\', flush=True)\nsys.exit(1)\n')
    c = compiler([sys.executable, "-B", bad])
    code, errors = c.module("g.vue", vue_file("g.vue", "<template>1</template>"))
    assert code is None and "compiler-sfc.js: SyntaxError" in errors[0]["message"], errors


@test("a folder is a Vue project when it has .vue files or a package.json that names vue")
def _():
    sys.path.insert(0, os.path.join(ROOT, "lib", "live"))
    import liveserver as L
    plain, comp, pkg, deep, dep = (os.path.join(D, n) for n in ("plain", "comp", "pkg", "deep", "dep"))
    for d in (plain, comp, pkg, os.path.join(deep, "a", "b"), os.path.join(dep, "node_modules", "x")):
        os.makedirs(d)
    open(os.path.join(plain, "index.html"), "w").close()
    open(os.path.join(comp, "App.vue"), "w").close()
    open(os.path.join(deep, "a", "b", "C.VUE"), "w").close()
    open(os.path.join(dep, "node_modules", "x", "Dep.vue"), "w").close()
    json.dump({"dependencies": {"vue": "^3.5.0", "vue-router": "^4.0.0", "pinia": "^3.0.0"}}, open(os.path.join(pkg, "package.json"), "w"))
    got = {}
    for name, d in (("plain", plain), ("comp", comp), ("pkg", pkg), ("deep", deep), ("dep", dep)):
        c = V.Compiler(say, log)
        got[name] = c.project(L.Site(d))
    assert got == {"plain": False, "comp": True, "pkg": True, "deep": True, "dep": False}, got
    c = V.Compiler(say, log)
    assert c.others(L.Site(pkg)) == ["vue-router", "pinia"] and c.others(L.Site(plain)) == []
    open(os.path.join(pkg, "index.html"), "w").write('<script type="importmap">{"imports":{}}</script>')
    assert c.others(L.Site(pkg)) == [], "a page that has an import map of its own may name them there"


print("\n%d passed, %d failed" % (PASSED[0], FAILED[0]))
sys.exit(1 if FAILED[0] else 0)
