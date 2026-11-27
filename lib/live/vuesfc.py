"""Vue 3 for the Live Server – part of lib/live/liveserver.py: a folder of .vue files (single-file components) opens in the browser
as it is, without npm or a build step – and on a Mac without Node, too.

What the Live Server does for it, and only where it is asked for:
  * a .vue file that a page imports (<script type="module"> … import App from './App.vue') is compiled here to the ES module the
    browser runs – by a program that carries Vue's own compiler (lib/live/vue/compiler-sfc.js, Vue 3.5): on a Mac in Apple's JavaScript
    engine, lotus-vue, built once from lib/live/Vue.swift (lotus liveserver --build-vue) – nothing to install; elsewhere (and on a Mac
    where that cannot be built) in Node, when it is installed (lib/live/vue/host.js). The browser, a phone in the Wi-Fi too, gets only
    the finished module; nothing is sent anywhere. What was compiled is kept until the file changes.
  * `import { createApp } from 'vue'` works: a page that has a module script gets an import map that says where Vue is
    (/__lotus/vue/vue.js – lib/live/vue/vue.js), unless the page names vue itself.
  * a stylesheet imported from a script (import './assets/main.css') becomes a <link> in the page, so a change in it is swapped in
    without a reload; a module that asks for './store' gets store.js or store/index.js.
  * a folder that is a Vue project (it has .vue files) answers a page that is not there – /about, a route of the router – with its
    index.html, as the router expects.
  * a file that cannot be compiled is shown in the page itself and in the terminal – the line, and what is wrong.

The compile program speaks lines: one JSON request on its stdin {"id", "file", "source"}, one JSON answer on its stdout
{"id", "code"} or {"id", "errors": [{"message", "line", "column"}]} – see lib/live/vue/sfc.js. Where there is neither a Mac's program
nor Node there is none (LOTUS_VUE_HOST names one – the tests do –, LOTUS_NODE a Node), and a .vue file says so in the page.
"""
import json
import os
import queue
import re
import shlex
import shutil
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
FILES = os.path.join(HERE, "vue")
SCRIPTS = ("compiler-sfc.js", "sfc.js")        # what the compile program loads, in this order
RUNTIME = "/__lotus/vue/vue.js"                # where a page finds Vue (lib/live/vue/vue.js)
TIMEOUT = 60                                   # seconds the compile program has for one file
KEEP = 400                                     # compiled files kept
NOT_HERE = "Vue files are compiled with Node.js here, and there is none – nodejs.org has it (a Mac needs nothing)"


# ── What a request is ──────────────────────────────────────────

def wants_module(headers):
    """Is this a script's `import` – the browser asking for a module – and not a link in a page, a fetch() or the browser opening
    the file? Sec-Fetch-Dest says so (script); where a browser does not send it, a request for anything (Accept: */*) is taken for
    one: a stylesheet, an image and a page all ask for their own types."""
    dest = (headers.get("Sec-Fetch-Dest") or "").strip().lower()
    if dest:
        return dest == "script"
    return (headers.get("Accept") or "*/*").strip() == "*/*"


def from_script(headers):
    """Sure to be a script's import: the browser said so."""
    return (headers.get("Sec-Fetch-Dest") or "").strip().lower() == "script"


def navigation(headers):
    """The browser opening a page (typing an address, a link, a reload)."""
    mode = (headers.get("Sec-Fetch-Mode") or "").strip().lower()
    if mode:
        return mode == "navigate"
    return "text/html" in (headers.get("Accept") or "")


def module_file(site, urlpath):
    """A module that asks for './store': store.js, store.mjs, store/index.js … → the file, or None."""
    base = urlpath.rstrip("/")
    for suffix in (".js", ".mjs", "/index.js", "/index.mjs"):
        full = site.resolve(base + suffix)
        if full and os.path.isfile(full):
            return full
    return None


# ── The page: Vue's address, and what a script gets in place of a stylesheet or an error ──

IMPORTMAP = re.compile(rb"""<script\b[^>]*\btype\s*=\s*["']?importmap["']?[^>]*>(.*?)</script\s*>""", re.I | re.S)
MODULE = re.compile(rb"""<script\b[^>]*\btype\s*=\s*["']?module["']?""", re.I)
SCRIPT = re.compile(rb"<script\b", re.I)


def with_vue(page):
    """A page with a module script knows where `vue` is: an import map in front of its first script – or `vue` put into the one it has.
    A page that names vue itself (a CDN, say) is left alone, and so is one without a module script (nothing there can ask)."""
    if not MODULE.search(page):
        return page
    have = IMPORTMAP.search(page)
    if have:
        try:
            found = json.loads(have.group(1).decode("utf-8"))
            imports = found.setdefault("imports", {})
            if not isinstance(imports, dict) or "vue" in imports:
                return page
            imports["vue"] = RUNTIME
            return page[:have.start(1)] + json.dumps(found).encode("utf-8") + page[have.end(1):]
        except (ValueError, AttributeError):
            return page                                          # an import map that is not JSON is the page's own business
    tag = b'<script type="importmap">{"imports":{"vue":"' + RUNTIME.encode() + b'"}}</script>'
    first = SCRIPT.search(page)
    return page[:first.start()] + tag + page[first.start():]


def js(data):
    """JSON that can stand in a script: nothing in it ends a block or starts a comment."""
    return json.dumps(data, ensure_ascii=False).replace("<", "\\u003c").replace(">", "\\u003e").replace("\u2028", "\\u2028").replace("\u2029", "\\u2029")


def error_module(file, errors):
    """What a .vue file that cannot be compiled is: a module that shows the error in the page (the overlay of reload.js) and fails.
    It has a default export, as a component has: a module that imports `Counter from './Counter.vue'` is not linked without one – the
    browser stops with "does not provide an export named 'default'" before a line of this module has run, and nothing is shown."""
    first = errors[0] if errors else {"message": "it could not be compiled"}
    where = ":%d" % first["line"] if first.get("line") else ""
    summary = "%s%s – %s" % (file, where, str(first.get("message", "")).strip().splitlines()[0] if str(first.get("message", "")).strip() else "?")
    return ("export default {};\nif (globalThis.__lotusError) globalThis.__lotusError(%s);\nthrow new Error(%s);\n" % (js({"file": file, "errors": errors}), js(summary)))


def css_module(url):
    """A stylesheet a script imports: a <link> in the page (its own address, so that its relative URLs and @imports work, and a
    change in it is swapped in without a reload)."""
    link = js(url)
    return ('if (typeof document !== "undefined" && !document.querySelector(\'link[data-lotus-css="\' + %s + \'"]\')) {\n'
            '  const link = document.createElement("link");\n  link.rel = "stylesheet";\n  link.href = %s;\n'
            '  link.setAttribute("data-lotus-css", %s);\n  document.head.appendChild(link);\n}\nexport default %s;\n' % (link, link, link, link))


# ── The compile program ────────────────────────────────────────

def pump(proc, lines):
    """Reads what the program writes, a line at a time, into a queue – so that waiting for an answer can time out (a pipe cannot be
    select()ed on Windows). None at the end: the program ended."""
    try:
        for raw in iter(proc.stdout.readline, b""):
            lines.put(raw)
    except (OSError, ValueError):
        pass
    lines.put(None)


def node_program():
    """The Node that compiles where a Mac's program does not: LOTUS_NODE (a path or a name), else `node` on the PATH → its path or None."""
    return shutil.which(os.environ.get("LOTUS_NODE") or "node")


class Compiler:
    def __init__(self, say, log):
        self.say, self.log = say, log                  # what the server writes in its terminal: a line, and a line with a time
        self.lock = threading.Lock()                   # one request to the program at a time – and its start
        self.proc = None
        self.lines = None                              # what the program writes, a line at a time (pump)
        self.unavailable = ""                          # why there is none, once it is known
        self.sent = 0
        self.cache = {}                                # full path → (its stamp, the answer)
        self.reported = set()                          # (file, stamp) of the errors that were written to the terminal
        self.vue, self.looked = False, -1e9

    # Is this folder a Vue project?
    def project(self, site):
        """It has .vue files, or a package.json that names vue – looked at again every few seconds."""
        if time.monotonic() - self.looked < 5:
            return self.vue
        self.looked = time.monotonic()
        found, seen = False, 0
        for _folder, files in site.walk():
            if any(f.lower().endswith(".vue") for f in files):
                found = True
                break
            seen += len(files)
            if seen > 20000:
                break
        if not found:
            try:
                with open(os.path.join(site.root, "package.json"), encoding="utf-8") as f:
                    package = json.load(f)
                found = any("vue" in (package.get(k) or {}) for k in ("dependencies", "devDependencies"))
            except (OSError, ValueError, AttributeError):
                pass
        self.vue = found
        return found

    def others(self, site):
        """The packages of package.json besides vue – the browser cannot get them without a build step (a page can name them in an
        import map of its own) → a short list, empty when the page has such a map."""
        try:
            with open(os.path.join(site.root, "package.json"), encoding="utf-8") as f:
                package = json.load(f)
            names = [n for n in (package.get("dependencies") or {}) if n != "vue"]
            index = site.index()
            if index:
                with open(index, "rb") as f:
                    if IMPORTMAP.search(f.read(262144)):
                        return []
            return names
        except (OSError, ValueError, AttributeError):
            return []

    # The program
    def engine(self):
        """What will compile the .vue files, without starting it: "host" (LOTUS_VUE_HOST names one), "mac" (lotus-vue, built once),
        "node", or "" – none."""
        if os.environ.get("LOTUS_VUE_HOST"):
            return "host"
        if sys.platform == "darwin":
            return "mac"
        return "node" if node_program() else ""

    def command(self):
        """The compile program and what it loads → a list; None (and `unavailable` says why) where there is none."""
        scripts = [os.path.join(FILES, name) for name in SCRIPTS]
        named = os.environ.get("LOTUS_VUE_HOST")            # (the tests bring their own)
        if named:
            return shlex.split(named) + scripts
        why = ""
        if sys.platform == "darwin":
            built, why = self.build()
            if built:
                return [built] + scripts
        node = node_program()
        if node:                                              # where there is no Mac – or the Mac's own could not be built
            return [node, os.path.join(FILES, "host.js")] + scripts
        self.unavailable = why or NOT_HERE
        return None

    def build(self):
        """On a Mac: the program that carries the compiler, built once from lib/live/Vue.swift → (its path, "") or (None, why not)."""
        lotus = os.environ.get("LOTUS_BIN")
        if not lotus or not os.access(lotus, os.X_OK):
            return None, "the compiler is built by lotus – start the Live Server with lotus liveserver"
        self.log("…", "Getting the Vue compiler ready – once, about half a minute", "38;5;245")
        try:
            out = subprocess.run([lotus, "liveserver", "--build-vue"], capture_output=True, text=True, timeout=900).stdout.strip().splitlines()
        except (OSError, subprocess.SubprocessError):
            out = []
        if not out or not os.access(out[-1], os.X_OK):
            return None, "the compiler needs Apple's Command Line Tools to be built once: xcode-select --install – or Node.js (nodejs.org)"
        return out[-1], ""

    def start(self):
        """Starts the program (the caller holds the lock) → True when it runs."""
        if self.proc and self.proc.poll() is None:
            return True
        self.proc = None
        if self.unavailable:
            return False
        cmd = self.command()
        if not cmd:
            return False
        try:
            self.proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        except OSError as e:
            self.unavailable = "the compiler did not start: %s" % e
            return False
        self.lines = queue.Queue()                      # (one for each program: what a program that was given up on says late is lost with it)
        threading.Thread(target=pump, args=(self.proc, self.lines), daemon=True).start()
        answer = self.ask({"op": "version"})
        if not answer or "vue" not in answer:
            self.stop()
            self.unavailable = (answer or {}).get("fatal") or "the compiler did not start"
            return False
        return True

    def ask(self, request):
        """One line to the program, one back → the answer (a dict), or None when it ended or took too long."""
        proc, lines = self.proc, self.lines
        self.sent += 1
        request = dict(request, id=self.sent)
        try:
            proc.stdin.write((json.dumps(request) + "\n").encode("ascii"))       # (json escapes everything that is not ASCII)
            proc.stdin.flush()
        except (OSError, ValueError, AttributeError):
            return None
        try:
            raw = lines.get(timeout=TIMEOUT)
        except (queue.Empty, AttributeError):
            return None
        if raw is None:                                                          # it ended
            return None
        try:
            answer = json.loads(raw.decode("utf-8"))
        except ValueError:
            return None
        return answer if isinstance(answer, dict) and (answer.get("id") in (request["id"], None)) else None

    def stop(self):
        proc, self.proc, self.lines = self.proc, None, None
        if proc:
            try:
                proc.stdin.close()
            except (OSError, ValueError):
                pass
            try:
                proc.terminate()
                proc.wait(timeout=3)
            except (OSError, subprocess.SubprocessError):
                try:
                    proc.kill()
                except OSError:
                    pass

    close = stop

    def warm(self):
        """Gets the program ready in the background – a Vue project's first page should not wait for it."""
        def work():
            with self.lock:
                ok = self.start()
            if ok:
                self.log("✓", "Vue compiler ready", None)
            elif self.unavailable:
                self.log("✗", "Vue files cannot be compiled: " + self.unavailable, "31")
        threading.Thread(target=work, daemon=True).start()

    # A .vue file
    def module(self, rel, full):
        """The module of a .vue file → (code, None), or (None, [errors])."""
        try:
            st = os.stat(full)
            stamp = (st.st_mtime_ns, st.st_size)
            with open(full, "rb") as f:
                source = f.read().decode("utf-8")
        except (OSError, UnicodeDecodeError) as e:
            return None, [{"message": "it cannot be read: %s" % e}]
        with self.lock:
            hit = self.cache.get(full)
            if hit and hit[0] == stamp:
                return hit[1]
            result = self.compile(rel, source)
            if result[0] is not None or not self.unavailable:       # (a program that is not there is not a result to keep)
                if len(self.cache) >= KEEP:
                    self.cache.clear()
                self.cache[full] = (stamp, result)
        if result[0] is None:
            self.report(rel, stamp, result[1])
        return result

    def compile(self, rel, source):
        answer = None
        for _try in range(2):                                          # a program that ended is started once more
            if not self.start():
                return None, [{"message": self.unavailable or NOT_HERE}]
            answer = self.ask({"file": rel, "source": source})
            if answer is not None:
                break
            self.stop()
        if answer is None:
            return None, [{"message": "the compiler did not answer – it ended, or took more than %d seconds" % TIMEOUT}]
        if "code" in answer:
            return answer["code"], None
        return None, answer.get("errors") or [{"message": answer.get("fatal") or "it could not be compiled"}]

    def report(self, rel, stamp, errors):
        """What is wrong, in the terminal – once for each state of the file."""
        if (rel, stamp) in self.reported or len(self.reported) > 2000:
            return
        self.reported.add((rel, stamp))
        for e in errors[:3]:
            text = str(e.get("message", "")).strip().splitlines()
            self.log("✗", "%s%s  %s" % (rel, (":%d" % e["line"]) if e.get("line") else "", text[0] if text else "?"), "31")
