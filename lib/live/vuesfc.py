"""Vue 3 for the Live Server (macOS) – part of lib/live/liveserver.py: a folder of .vue files (single-file components) opens in the
browser as it is, without Node, npm or a build step.

What the Live Server does for it, and only where it is asked for:
  * a .vue file that a page imports (<script type="module"> … import App from './App.vue') is compiled on this Mac to the ES module
    the browser runs – by a program that carries Vue's own compiler (lib/live/vue/compiler-sfc.js, Vue 3.5) in Apple's JavaScript
    engine: lotus-vue, built once from lib/live/Vue.swift (lotus liveserver --build-vue). The browser, a phone in the Wi-Fi too, gets
    only the finished module; nothing is sent anywhere. What was compiled is kept until the file changes.
  * `import { createApp } from 'vue'` works: a page that has a module script gets an import map that says where Vue is
    (/__lotus/vue/vue.js – lib/live/vue/vue.js), unless the page names vue itself.
  * a stylesheet imported from a script (import './assets/main.css') becomes a <link> in the page, so a change in it is swapped in
    without a reload; a module that asks for './store' gets store.js or store/index.js.
  * a folder that is a Vue project (it has .vue files) answers a page that is not there – /about, a route of the router – with its
    index.html, as the router expects.
  * a file that cannot be compiled is shown in the page itself and in the terminal – the line, and what is wrong.

The compile program speaks lines: one JSON request on its stdin {"id", "file", "source"}, one JSON answer on its stdout
{"id", "code"} or {"id", "errors": [{"message", "line", "column"}]} – see lib/live/vue/sfc.js. On a system that is not a Mac there is
none (the tests name one, LOTUS_VUE_HOST), and a .vue file says so in the page.
"""
import json
import os
import re
import select
import shlex
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
NOT_HERE = "Vue files are compiled on a Mac only – not here yet"


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
    """What a .vue file that cannot be compiled is: a module that shows the error in the page (the overlay of reload.js) and fails."""
    first = errors[0] if errors else {"message": "it could not be compiled"}
    where = ":%d" % first["line"] if first.get("line") else ""
    summary = "%s%s – %s" % (file, where, str(first.get("message", "")).strip().splitlines()[0] if str(first.get("message", "")).strip() else "?")
    return ("if (globalThis.__lotusError) globalThis.__lotusError(%s);\nthrow new Error(%s);\n" % (js({"file": file, "errors": errors}), js(summary)))


def css_module(url):
    """A stylesheet a script imports: a <link> in the page (its own address, so that its relative URLs and @imports work, and a
    change in it is swapped in without a reload)."""
    link = js(url)
    return ('if (typeof document !== "undefined" && !document.querySelector(\'link[data-lotus-css="\' + %s + \'"]\')) {\n'
            '  const link = document.createElement("link");\n  link.rel = "stylesheet";\n  link.href = %s;\n'
            '  link.setAttribute("data-lotus-css", %s);\n  document.head.appendChild(link);\n}\nexport default %s;\n' % (link, link, link, link))


# ── The compile program ────────────────────────────────────────

class Compiler:
    def __init__(self, say, log):
        self.say, self.log = say, log                  # what the server writes in its terminal: a line, and a line with a time
        self.lock = threading.Lock()                   # one request to the program at a time – and its start
        self.proc = None
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
    def command(self):
        """The compile program and what it loads → a list; None (and `unavailable` says why) where there is none."""
        scripts = [os.path.join(FILES, name) for name in SCRIPTS]
        named = os.environ.get("LOTUS_VUE_HOST")            # (the tests bring their own)
        if named:
            return shlex.split(named) + scripts
        if sys.platform != "darwin":
            self.unavailable = NOT_HERE
            return None
        lotus = os.environ.get("LOTUS_BIN")
        if not lotus or not os.access(lotus, os.X_OK):
            self.unavailable = "the compiler is built by lotus – start the Live Server with lotus liveserver"
            return None
        self.log("…", "Getting the Vue compiler ready – once, about half a minute", "38;5;245")
        try:
            out = subprocess.run([lotus, "liveserver", "--build-vue"], capture_output=True, text=True, timeout=900).stdout.strip().splitlines()
        except (OSError, subprocess.SubprocessError):
            out = []
        if not out or not os.access(out[-1], os.X_OK):
            self.unavailable = "the compiler needs Apple's Command Line Tools to be built once: xcode-select --install"
            return None
        return [out[-1]] + scripts

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
        answer = self.ask({"op": "version"})
        if not answer or "vue" not in answer:
            self.stop()
            self.unavailable = (answer or {}).get("fatal") or "the compiler did not start"
            return False
        return True

    def ask(self, request):
        """One line to the program, one back → the answer (a dict), or None when it ended or took too long."""
        proc = self.proc
        self.sent += 1
        request = dict(request, id=self.sent)
        try:
            proc.stdin.write((json.dumps(request) + "\n").encode("ascii"))       # (json escapes everything that is not ASCII)
            proc.stdin.flush()
        except (OSError, ValueError, AttributeError):
            return None
        fd, buf, end = proc.stdout.fileno(), b"", time.monotonic() + TIMEOUT
        while b"\n" not in buf:
            left = end - time.monotonic()
            if left <= 0 or proc.poll() is not None and not select.select([fd], [], [], 0)[0]:
                return None
            if select.select([fd], [], [], min(left, 0.5))[0]:
                part = os.read(fd, 1 << 16)
                if not part:
                    return None
                buf += part
        try:
            answer = json.loads(buf.split(b"\n", 1)[0].decode("utf-8"))
        except ValueError:
            return None
        return answer if isinstance(answer, dict) and (answer.get("id") in (request["id"], None)) else None

    def stop(self):
        proc, self.proc = self.proc, None
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
