"""Vue's compiler through the program that carries it – lotus-vue on a Mac (JavaScriptCore), tests/live/vue-host.js (Node) where there is no
Mac: what a .vue file becomes, line by line, as the Live Server sends it to the program (LOTUS_VUE_HOST names the program; the two scripts
it loads are added here, as the server does).

    LOTUS_VUE_HOST="node tests/live/vue-host.js" python3 tests/live/vue_compile_test.py
"""
import json
import os
import re
import shlex
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
VUE = os.path.join(ROOT, "lib", "live", "vue")
HOST = os.environ.get("LOTUS_VUE_HOST")
if not HOST:
    print("  – LOTUS_VUE_HOST names no program: skipped")
    sys.exit(0)
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


class Host(object):
    def __init__(self):
        self.proc = subprocess.Popen(shlex.split(HOST) + [os.path.join(VUE, "compiler-sfc.js"), os.path.join(VUE, "sfc.js")],
                                     stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        self.n = 0

    def raw(self, line):
        self.proc.stdin.write(line.encode("utf-8") + b"\n")
        self.proc.stdin.flush()
        out = self.proc.stdout.readline()
        assert out, "the program ended without an answer"
        return json.loads(out.decode("utf-8"))

    def ask(self, request):
        self.n += 1
        answer = self.raw(json.dumps(dict(request, id=self.n)))
        assert answer.get("id") == self.n, answer
        return answer

    def compile(self, file, source):
        return self.ask({"file": file, "source": source})

    def close(self):
        self.proc.stdin.close()
        self.proc.wait(timeout=10)


host = Host()

COUNTER = """<script setup>
import { ref } from 'vue'
import Child from './Child.vue'
const props = defineProps({ start: { type: Number, default: 1 } })
const emit = defineEmits(['bump'])
const n = ref(props.start)
const color = ref('red')
function inc() { n.value++; emit('bump', n.value) }
</script>

<template>
  <div class="box" @click="inc">
    <img src="./logo.png" alt="x">
    <span>{{ n }}</span>
    <Child v-for="i in 2" :key="i" :label="'#' + i" />
  </div>
</template>

<style scoped>
.box { color: v-bind(color); border: 1px solid blue }
.box :deep(.inner) { margin: 0 }
</style>
"""


def errors_of(answer):
    assert "code" not in answer and answer.get("errors"), answer
    return answer["errors"]


@test("the program knows which Vue it carries")
def _():
    assert host.ask({"op": "version"})["vue"] == "3.5.45"


@test("a <script setup> with a template and a scoped style becomes a module: script, render function, scope, style, export")
def _():
    a = host.compile("src/components/Counter.vue", COUNTER)
    assert "code" in a and "errors" not in a, a
    code = a["code"]
    assert "import Child from './Child.vue'" in code and re.search(r"import \{[^}]*\bref\b[^}]*\} from ['\"]vue['\"]", code), "the script's own imports stay"
    assert len(re.findall(r"\bconst _sfc_main = ", code)) == 1 and "props:" in code and "emits:" in code, "defineProps and defineEmits are options now"
    assert "export function render(" in code and "_sfc_main.render = render;" in code
    assert '_sfc_main.__file = "src/components/Counter.vue";' in code
    scope = re.search(r'_sfc_main\.__scopeId = "(data-v-[0-9a-f]{8})";', code)
    assert scope, "scoped: the component has a scope id"
    assert "$setup" in code, "the template reads what setup() returns"
    assert code.rstrip().endswith("export default _sfc_main;")
    assert re.search(r'document\.createElement\("style"\)', code) and 'data-lotus-vue", "src/components/Counter.vue"' in code
    css = json.loads(re.search(r"el\.textContent = (\".*?\"); document\.head", code, re.S).group(1))
    assert ".box[%s]" % scope.group(1) in css and "[%s] .inner" % scope.group(1) in css, css
    assert "var(--" in css and "color: var(--" in css, "v-bind() in CSS is a custom property"
    assert "_useCssVars" in code, "and the component sets it"


@test("a relative URL in a template is the URL the server has the file at – no import of an image")
def _():
    code = host.compile("src/components/Counter.vue", COUNTER)["code"]
    assert "/src/components/logo.png" in code and "./logo.png" not in code, "the page's address is not the file's"
    assert not re.search(r"import\s+\w+\s+from\s+['\"][^'\"]*\.png", code)
    code = host.compile("Top.vue", '<template><img src="./a/b.svg"><img src="../x.png"><img src="https://x.example/y.png"><a href="#top">t</a></template>')["code"]
    assert "/a/b.svg" in code and "https://x.example/y.png" in code and "#top" in code, code


@test("the same file gives the same module – the scope id depends on the name of the file only – and another file another scope")
def _():
    a, b = host.compile("src/A.vue", COUNTER), host.compile("src/A.vue", COUNTER)
    assert a["code"] == b["code"] and "ok" not in a
    other = host.compile("src/B.vue", COUNTER)["code"]
    scope = lambda c: re.search(r'__scopeId = "(data-v-[0-9a-f]{8})"', c).group(1)
    assert scope(a["code"]) != scope(other)


@test("a <script> with an options API component, and a template next to it")
def _():
    code = host.compile("Options.vue", """<template><p>{{ n }}</p></template>
<script>
export default { name: 'Options', data() { return { n: 1 } } }
</script>""")["code"]
    assert re.search(r"\bconst _sfc_main = ", code) and "name: 'Options'" in code and "_sfc_main.render = render;" in code, code
    assert "__scopeId" not in code and "createElement(\"style\")" not in code, "not scoped, no style: none of either"


@test("only a template, only a script, only a style")
def _():
    t = host.compile("T.vue", "<template><b>bold</b></template>")["code"]
    assert "const _sfc_main = {};" in t and "_sfc_main.render = render;" in t
    s = host.compile("S.vue", "<script>\nexport default { render() { return null } }\n</script>")["code"]
    assert "_sfc_main.render" not in s and "export default _sfc_main;" in s
    c = host.compile("C.vue", "<style>\np { color: green }\n</style>")["code"]
    assert "const _sfc_main = {};" in c and "p { color: green }" in c and "data-v-" not in c.split("textContent =")[1], "a plain style has no scope"
    e = host.compile("E.vue", "")
    assert "const _sfc_main = {};" in e["code"] and e["code"].rstrip().endswith("export default _sfc_main;"), e


@test("text that is not ASCII goes through the lines, in the template and the script")
def _():
    code = host.compile("src/Über uns – 日本語.vue", """<script setup>
const t = 'Grüezi – 日本語 \U0001F338'
</script>
<template><p title="Ünï">{{ t }} Grüezi – 日本語 \U0001F338</p></template>""")["code"]
    assert "Grüezi – 日本語 \U0001F338" in code and "Ünï" in code
    assert '_sfc_main.__file = "src/Über uns – 日本語.vue";' in code


@test("what is wrong is said, with the line where there is one: a template that is not closed, a script that is not JavaScript")
def _():
    e = errors_of(host.compile("Bad.vue", "<template>\n  <div>\n</template>\n"))
    assert re.search(r"end tag|missing|unexpected|closing", e[0]["message"], re.I), e
    e = errors_of(host.compile("Bad2.vue", "<script setup>\nconst = 1\n</script>\n<template><p/></template>"))
    assert e[0]["message"].strip(), e
    e = errors_of(host.compile("Bad3.vue", "<template><p>{{ a b }}</p></template>"))
    assert e[0]["message"].strip(), "an expression that is not one: " + repr(e)
    e = errors_of(host.compile("Bad4.vue", "<template><p></template><template><q></template>"))
    assert e, "two template blocks"
    assert host.compile("Good.vue", "<template><p>fine</p></template>").get("code"), "the program goes on after errors"


@test("what is not there yet is said instead of being left out: TypeScript, SCSS, Pug, CSS modules, src blocks")
def _():
    cases = (("<script setup lang=\"ts\">\nconst a: number = 1\n</script>", "lang=\"ts\""),
             ("<script lang=\"tsx\">\nexport default {}\n</script>", "lang=\"tsx\""),
             ("<template><p/></template>\n<style lang=\"scss\">\n$a: 1;\n</style>", "scss"),
             ("<template><p/></template>\n<style lang=\"less\">\n@a: 1;\n</style>", "less"),
             ("<template lang=\"pug\">\np hi\n</template>", "pug"),
             ("<template><p/></template>\n<style module>\n.a { color: red }\n</style>", "CSS modules"),
             ("<template src=\"./t.html\"></template>", "<template src"),
             ("<script src=\"./s.js\"></script>", "<script src"),
             ("<style src=\"./s.css\"></style>", "<style src"))
    for source, word in cases:
        e = errors_of(host.compile("X.vue", source))
        assert word in e[0]["message"] and "not supported" in e[0]["message"], (source, e)
    both = errors_of(host.compile("Y.vue", "<script lang=\"ts\">export default {}</script>\n<style lang=\"scss\"></style>"))
    assert len(both) == 2, both
    assert both[0]["line"] == 1 and both[1]["line"] == 2, "the line of the block"


@test("a style that is not CSS is an error of the style, with its line")
def _():
    e = errors_of(host.compile("Z.vue", "<template><p/></template>\n<style scoped>\n.a { color: red\n</style>"))
    assert e[0]["message"].strip(), e


@test("a template of a few thousand lines is compiled in a few seconds – and the program answers the next file")
def _():
    items = "\n".join('  <li v-for="n in 3" :key="n" class="row-%d">{{ n }} item %d</li>' % (i, i) for i in range(4000))
    began = time.time()
    a = host.compile("Big.vue", "<template><ul>\n%s\n</ul></template>\n" % items)
    took = time.time() - began
    assert "code" in a and len(a["code"]) > 100000, (list(a), took)
    assert took < 30, "took %.1f s" % took
    assert host.compile("After.vue", "<template><p>x</p></template>").get("code")


@test("a line that is not a request is an error, not the end of the program")
def _():
    for line in ("not json at all", "{}", '{"id": 7}', '{"id": 8, "file": 5, "source": null}'):
        answer = host.raw(line)
        assert "code" not in answer or answer.get("code") is not None
    answer = host.raw("not json at all")
    assert answer.get("errors") and answer["errors"][0]["message"], answer
    assert host.compile("Alive.vue", "<template><i>still here</i></template>").get("code")


@test("many files in a row through one program – it does not slow down")
def _():
    began = time.time()
    for i in range(60):
        assert host.compile("src/f%d.vue" % i, COUNTER).get("code")
    assert time.time() - began < 60


host.close()
print("\n%d passed, %d failed" % (PASSED[0], FAILED[0]))
sys.exit(1 if FAILED[0] else 0)
