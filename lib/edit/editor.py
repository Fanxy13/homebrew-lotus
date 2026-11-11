"""Lotus image editor – crop, turn, straighten and convert a picture in a window like the iPhone's Photos app.

    python3 editor.py <picture> [--out-dir <folder>] [--no-open] [--port <n>]

Part of Lotus (lib/cmd/img.zsh starts it: /img, /img edit). Python's standard library, nothing to install.

How it works – the same on every system:
  * the page (web/: HTML, CSS, JavaScript – no framework, no download) is served to this computer only: 127.0.0.1, an
    address that holds a secret, only its own host names, no cross-site requests;
  * the picture is first made readable for any browser by the system's engine (engine.py: HEIC, RAW, WebP … into an upright
    PNG), the page crops it in a canvas and sends the result back;
  * the engine then writes the new file in the format, quality and size that were chosen – next to the original, which is
    never changed; a new name when there is one already ("photo edited (2).jpg").
Closing the tab, the Cancel button or Ctrl-C ends it. Nothing is uploaded anywhere.

Environment (all optional):  LOTUS_IMG_TOOL (macOS: the lotus-img program), LOTUS_CWEBP, LOTUS_LANG (en de fr es),
LOTUS_EDIT_DATA (a folder for the working files), LOTUS_IMG_LAST (the file where /img remembers the last quality),
LOTUS_DOWNLOADS (where pictures without a folder go), LOTUS_THIS and LOTUS_FILES_APP (what the texts call this computer and
its file manager), LOTUS_COLOR_KEY / _ACCENT / _DIM (the theme colors of the terminal).
"""
import argparse
import hmac
import json
import os
import re
import secrets
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import engine as engines  # noqa: E402

WEB = os.path.join(HERE, "web")
ASSETS = {"editor.css": "text/css; charset=utf-8", "editor.js": "text/javascript; charset=utf-8",
          "geometry.js": "text/javascript; charset=utf-8"}
LANGS = ("en", "de", "fr", "es")
QUALITIES = (95, 85, 70, 50)                       # Best, High, Medium, Small – the same as /img convert
SIZES = (0, 3840, 2560, 1920, 1280, 640)           # all, 4K, 2560, Full HD, 1280, 640 – the same as /img convert
WORK_MAX = 10000                                   # a picture bigger than this is worked on as a smaller copy (browsers' canvases)
UPLOAD_MAX = 1 << 30                               # the cropped picture the page sends back: at most 1 GiB
IDLE = 180                                         # seconds without a sign of the page (it pings every 2) – it is gone
GRACE = 4                                          # seconds the page has to come back after it said goodbye (a reload does)
FIRST = 900                                        # seconds the browser has to open the page
TTY = sys.stdout.isatty()
HOME = os.path.expanduser("~")


# ── Lotus' look in the terminal ────────────────────────────────

def color(name, fallback):
    code = os.environ.get("LOTUS_COLOR_" + name, "")
    return code if re.fullmatch(r"[0-9;]+", code) else fallback


KEY, ACCENT, DIM = color("KEY", "38;5;150"), color("ACCENT", "38;5;149"), color("DIM", "38;5;245")
OUT = threading.RLock()


def paint(code, text, bold=False):
    return "\033[%s%sm%s\033[0m" % ("1;" if bold else "", code, text) if TTY else text


def say(text=""):
    with OUT:
        print(text, flush=True)


def kv(key, value):
    say("    %s%s" % (paint(DIM, key.ljust(10)), value))


def fail(text, hint=""):
    say("  %s %s" % (paint("31", "✗", True), text))
    if hint:
        say("    " + paint(DIM, hint))
    return 1


def tilde(path):
    return "~" + path[len(HOME):] if path == HOME or path.startswith(HOME + os.sep) else path


def human(n):
    return "%d KB" % ((n + 512) // 1024) if n < 1048576 else "%.1f MB" % (n / 1048576.0)


# ── What differs from system to system (and is small enough to be here) ──

def open_url(url):
    try:
        if sys.platform == "win32":
            os.startfile(url)                                           # the default browser
        elif sys.platform == "darwin":
            subprocess.Popen(["/usr/bin/open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        else:
            opener = shutil.which("xdg-open") or shutil.which("gio")
            if not opener:
                import webbrowser
                return webbrowser.open(url)
            subprocess.Popen([opener] + (["open"] if opener.endswith("gio") else []) + [url],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True
    except OSError:
        return False


def show_file(path, reveal):
    """The picture in the file manager (reveal) or in the app that opens it. Only ever a file this editor wrote."""
    if os.environ.get("LOTUS_EDIT_NO_SHOW"):
        return True                                                     # (the tests)
    try:
        if sys.platform == "win32":
            if reveal:
                subprocess.Popen(["explorer", "/select," + path])
            else:
                os.startfile(path)
        elif sys.platform == "darwin":
            subprocess.Popen(["/usr/bin/open"] + (["-R"] if reveal else []) + ["--", path],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        else:
            opener = shutil.which("xdg-open") or shutil.which("gio")
            if not opener:
                return False
            subprocess.Popen([opener] + (["open"] if opener.endswith("gio") else []) + [os.path.dirname(path) if reveal else path],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True
    except OSError:
        return False


# ── The picture ────────────────────────────────────────────────

class Session(object):
    def __init__(self, image, eng, data_dir, out_dir=None, last_file=None, downloads=None):
        self.image = os.path.abspath(image)
        self.engine = eng
        self.last_file = last_file
        self.downloads = downloads or os.path.join(HOME, "Downloads", "Lotus")
        self.note = ""                                            # why the pictures do not go next to the original
        self.out_dir = self._out_dir(out_dir)
        os.makedirs(data_dir, mode=0o700, exist_ok=True)
        self.work_dir = tempfile.mkdtemp(prefix="edit-", dir=data_dir)
        self.work = os.path.join(self.work_dir, "work.png")
        self.formats = []
        self.size = (0, 0)                                        # as it is seen
        self.work_size = (0, 0)
        self.bytes = 0
        self.saved = []
        self.lock = threading.Lock()

    def _out_dir(self, out_dir):
        want = out_dir or os.path.dirname(self.image)
        if out_dir and not os.path.isdir(want):                  # (Downloads/Lotus, the first time)
            try:
                os.makedirs(want)
            except OSError:
                pass
        if os.path.isdir(want) and os.access(want, os.W_OK | os.X_OK):
            return want
        self.note = "folder"
        os.makedirs(self.downloads, exist_ok=True)
        return self.downloads

    def prepare(self):
        """The picture as a PNG any browser shows (upright, not bigger than WORK_MAX) – raises EngineError."""
        self.formats = self.engine.writable()
        res = self.engine.convert(self.image, self.work, "png", 0, WORK_MAX)
        self.size, self.work_size, self.bytes = res.size_in, res.size_out, res.in_bytes
        if min(self.work_size) < 1:
            raise engines.EngineError("it has no size")

    def source_format(self):
        ext = os.path.splitext(self.image)[1].lower().lstrip(".")
        return engines.EXTENSIONS.get(ext)

    def last(self):
        """(format, quality, max) of the last time /img was used: 'jpeg|85|1920' – or None."""
        try:
            with open(self.last_file, encoding="utf-8") as f:
                p = f.read().strip().split("|")
            return p[0], int(p[1]), int(p[2])
        except (OSError, TypeError, ValueError, IndexError):
            return None

    def defaults(self):
        """What the Convert tab starts with: the format of the picture (or one that it can be saved as), the last quality, all of it."""
        key = self.source_format()
        if key not in self.formats:
            key = "png" if os.path.splitext(self.image)[1].lower() in (".svg", ".psd", ".tga", ".exr", ".icns", ".ico") and "png" in self.formats \
                else ("jpeg" if "jpeg" in self.formats else (self.formats[0] if self.formats else "png"))
        last = self.last()
        quality = last[1] if last and 1 <= last[1] <= 100 else QUALITIES[1]
        return {"format": key, "quality": quality, "max": 0}

    def remember(self, key, quality, max_px):
        if not self.last_file:
            return
        try:
            os.makedirs(os.path.dirname(self.last_file), exist_ok=True)
            with open(self.last_file, "w", encoding="utf-8") as f:
                f.write("%s|%d|%d\n" % (key, quality, max_px))
        except OSError:
            pass

    def plan(self, key, edited):
        """The file a save would write: next to the original, never over a file that is there (name (2).ext)."""
        ext = engines.BY_KEY[key][2]
        base = os.path.splitext(os.path.basename(self.image))[0] + (" edited" if edited else "")
        n = 1
        while True:
            name = "%s.%s" % (base, ext) if n == 1 else "%s (%d).%s" % (base, n, ext)
            path = os.path.join(self.out_dir, name)
            if not os.path.lexists(path):
                return path
            n += 1

    def save(self, key, quality, max_px, edited, upload):
        """Writes the new file → a dict for the page. `upload`: the cropped picture as a PNG (when it was edited)."""
        if key not in self.formats:
            raise engines.EngineError("this computer cannot write that format")
        lossy = engines.BY_KEY[key][4]
        quality = min(100, max(1, quality)) if lossy else 0
        max_px = 256 if key == "ico" else max(0, max_px)
        with self.lock:
            out = self.plan(key, edited)
            if edited:
                res = self.engine.convert(upload, out, key, quality, max_px, self.image)
            else:
                res = self.engine.convert(self.image, out, key, quality, max_px, None)
            item = {"path": out, "name": os.path.basename(out), "folder": tilde(os.path.dirname(out)),
                    "bytes": res.out_bytes, "width": res.size_out[0], "height": res.size_out[1], "from_bytes": res.in_bytes}
            self.saved.append(item)
        self.remember(key, quality or (self.last() or (0, QUALITIES[1]))[1], max_px)
        return item

    def forget(self):
        shutil.rmtree(self.work_dir, ignore_errors=True)


# ── The page ───────────────────────────────────────────────────

def strings(lang):
    with open(os.path.join(HERE, "web", "strings.json"), encoding="utf-8") as f:
        every = json.load(f)
    table = dict(every["en"])
    table.update(every.get(lang, {}))
    return table


FILES_APP = {   # what the file manager is called, by language, where it is not the Finder (the texts say "Show in %s")
    "en": {}, "de": {"the file manager": "Dateimanager", "File Explorer": "Datei-Explorer"},
    "fr": {"the file manager": "le gestionnaire de fichiers", "File Explorer": "l’Explorateur de fichiers"},
    "es": {"the file manager": "el gestor de archivos", "File Explorer": "el Explorador de archivos"},
}


def files_app(lang, name):
    return FILES_APP.get(lang, {}).get(name, name)


def same_token(given, token):
    """Is `given` (a piece of the request path, which http.server decodes as Latin-1) the secret? Never raises on odd bytes."""
    return hmac.compare_digest(given.encode("latin-1", "replace"), token.encode("ascii"))


def js_json(data):
    # in a <script> block: nothing in the text may end the block or start a comment
    return json.dumps(data, ensure_ascii=False).replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026") \
        .replace("\u2028", "\\u2028").replace("\u2029", "\\u2029")


class Editor(object):
    def __init__(self, session, lang, this, files_app):
        self.session, self.lang, self.this, self.files_app = session, lang, this, files_app
        self.token = secrets.token_urlsafe(18)
        self.idle, self.grace, self.first = IDLE, GRACE, FIRST        # (LOTUS_EDIT_IDLE, _GRACE and _FIRST shorten them for the tests)
        self.started = time.monotonic()
        self.last_ping = self.started
        self.seen = False                       # has the page said anything yet?
        self.bye_at = None
        self.quit = False
        self.busy = 0
        self.port = 0

    def config(self):
        s = self.session
        return {
            "lang": self.lang, "strings": strings(self.lang), "this": self.this, "filesApp": files_app(self.lang, self.files_app),
            "image": {"name": os.path.basename(s.image), "width": s.size[0], "height": s.size[1], "bytes": s.bytes,
                      "kind": (os.path.splitext(s.image)[1].lstrip(".") or "?").upper()},
            "work": {"width": s.work_size[0], "height": s.work_size[1], "scale": s.work_size[0] / float(s.size[0] or 1)},
            "formats": [{"key": f[0], "label": f[1], "lossy": f[4]} for f in engines.FORMATS if f[0] in s.formats],
            "defaults": s.defaults(), "source": s.source_format() if s.source_format() in s.formats else None,
            "qualities": list(QUALITIES), "sizes": list(SIZES),
            "folder": tilde(s.out_dir), "folderNote": s.note, "engine": s.engine.kind,
        }

    def page(self):
        with open(os.path.join(WEB, "index.html"), encoding="utf-8") as f:
            html = f.read()
        return html.replace("{{config}}", js_json(self.config())).replace("{{lang}}", self.lang) \
            .replace("{{title}}", os.path.basename(self.session.image).replace("&", "&amp;").replace("<", "&lt;"))


CSP = ("default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' blob: data:; connect-src 'self'; "
       "base-uri 'none'; form-action 'none'; frame-ancestors 'none'")


class Handler(BaseHTTPRequestHandler):
    server_version = "LotusImageEditor/1.0"
    protocol_version = "HTTP/1.1"
    timeout = 300

    def log_message(self, *args):
        pass

    # who may ask
    def host_ok(self):
        host = (self.headers.get("Host") or "").lower()
        return host in ("127.0.0.1:%d" % self.server.editor.port, "localhost:%d" % self.server.editor.port)

    def same_site(self):
        """A POST comes from the page itself: its own origin, never another site (and it says so with its own header)."""
        port = self.server.editor.port
        origin = self.headers.get("Origin")
        if origin and origin not in ("http://127.0.0.1:%d" % port, "http://localhost:%d" % port):
            return False
        if self.headers.get("Sec-Fetch-Site") not in (None, "same-origin", "none"):
            return False
        return self.headers.get("X-Lotus-Edit") == "1"

    # answers
    def send(self, code, ctype, data, extra=()):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        for k, v in extra:
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    def text(self, code, text):
        self.send(code, "text/plain; charset=utf-8", (text + "\n").encode("utf-8"))

    def json(self, code, obj):
        self.send(code, "application/json; charset=utf-8", json.dumps(obj, ensure_ascii=False).encode("utf-8"))

    def refuse(self, code, text):
        self.close_connection = True                       # (a body that was not read must not be taken for the next request)
        self.send(code, "text/plain; charset=utf-8", (text + "\n").encode("utf-8"), [("Connection", "close")])

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        ed = self.server.editor
        if not self.host_ok():
            return self.text(403, "This editor answers only to 127.0.0.1.")
        url = urlsplit(self.path)
        parts = url.path.split("/")                         # ['', token, ...]
        if len(parts) < 2 or not same_token(parts[1], ed.token):
            return self.text(404, "Not found")
        rest = "/".join(parts[2:])
        if len(parts) == 2:
            return self.send(301, "text/plain; charset=utf-8", b"", [("Location", "/%s/" % ed.token)])
        if rest == "":
            return self.send(200, "text/html; charset=utf-8", ed.page().encode("utf-8"),
                             [("Content-Security-Policy", CSP)])
        if rest.startswith("web/") and rest[4:] in ASSETS:
            with open(os.path.join(WEB, rest[4:]), "rb") as f:
                return self.send(200, ASSETS[rest[4:]], f.read())
        if rest == "image":
            try:
                with open(ed.session.work, "rb") as f:
                    data = f.read()
            except OSError:
                return self.text(404, "Not found")
            return self.send(200, "image/png", data, [("Cache-Control", "private, max-age=3600")])
        if rest == "api/plan":
            q = parse_qs(url.query)
            key = (q.get("format") or [""])[0]
            if key not in ed.session.formats:
                return self.json(400, {"ok": False, "error": "format"})
            path = ed.session.plan(key, (q.get("edited") or ["0"])[0] == "1")
            return self.json(200, {"ok": True, "name": os.path.basename(path), "folder": tilde(os.path.dirname(path))})
        return self.text(404, "Not found")

    def do_POST(self):
        ed = self.server.editor
        if not self.host_ok():
            return self.refuse(403, "This editor answers only to 127.0.0.1.")
        url = urlsplit(self.path)
        parts = url.path.split("/")
        if len(parts) < 3 or not same_token(parts[1], ed.token):
            return self.refuse(404, "Not found")
        if not self.same_site():
            return self.refuse(403, "Not from this page.")
        rest = "/".join(parts[2:])
        if rest == "api/ping":
            ed.last_ping, ed.seen, ed.bye_at = time.monotonic(), True, None
            return self.json(200, {"ok": True})
        if rest == "api/bye":
            ed.bye_at = time.monotonic() + ed.grace
            return self.json(200, {"ok": True})
        if rest == "api/quit":
            ed.quit = True
            return self.json(200, {"ok": True})
        if rest in ("api/reveal", "api/open"):
            saved = ed.session.saved
            if not saved:
                return self.json(400, {"ok": False, "error": "nothing saved yet"})
            return self.json(200, {"ok": show_file(saved[-1]["path"], rest == "api/reveal")})
        if rest == "api/save":
            return self.save(ed, parse_qs(url.query))
        return self.refuse(404, "Not found")

    def save(self, ed, q):
        s = ed.session

        def num(name, default):
            try:
                return int((q.get(name) or [default])[0])
            except ValueError:
                return default
        key, edited = (q.get("format") or [""])[0], (q.get("edited") or ["0"])[0] == "1"
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            return self.refuse(400, "Content-Length is not a number.")
        if edited and not 0 < length <= UPLOAD_MAX:
            return self.refuse(413 if length else 411, "The picture is missing or too big.")
        upload = os.path.join(s.work_dir, "crop.png")
        ed.busy += 1
        try:
            if edited:
                left = length
                with open(upload, "wb") as f:
                    while left > 0:
                        chunk = self.rfile.read(min(1 << 20, left))
                        if not chunk:
                            break
                        f.write(chunk)
                        left -= len(chunk)
                with open(upload, "rb") as f:
                    if left or f.read(8) != b"\x89PNG\r\n\x1a\n":
                        return self.json(400, {"ok": False, "error": "The picture did not arrive whole."})
            elif length:
                self.rfile.read(length)
            try:
                item = s.save(key, num("quality", QUALITIES[1]), num("max", 0), edited, upload)
            except engines.EngineError as e:
                return self.json(200, {"ok": False, "error": e.reason})
            say("  %s Saved  %s  %s" % (paint(KEY, "✓", True), paint(KEY, tilde(item["path"])),
                                       paint(DIM, "%d × %d · %s" % (item["width"], item["height"], human(item["bytes"])))))
            return self.json(200, dict(item, ok=True, note=s.note))
        finally:
            ed.busy -= 1
            try:
                os.remove(upload)
            except OSError:
                pass


class Server(ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True

    def handle_error(self, request, client_address):
        pass                                    # a browser that went away in the middle of an answer


def watch(ed, server):
    """Ends the editor when it is done: Cancel was pressed, the tab was closed, or the browser is gone."""
    while True:
        time.sleep(0.4)
        now = time.monotonic()
        if ed.quit or (ed.bye_at and now >= ed.bye_at and not ed.busy) or \
           (ed.seen and not ed.busy and now - ed.last_ping > ed.idle) or (not ed.seen and now - ed.started > ed.first):
            threading.Thread(target=server.shutdown, daemon=True).start()
            return


# ── Start ──────────────────────────────────────────────────────

def clean_old(data_dir):
    """Working folders of editors that were killed (older than a day)."""
    try:
        for name in os.listdir(data_dir):
            path = os.path.join(data_dir, name)
            if name.startswith("edit-") and time.time() - os.path.getmtime(path) > 86400:
                shutil.rmtree(path, ignore_errors=True)
    except OSError:
        pass


def main(argv):
    ap = argparse.ArgumentParser(prog="editor.py", add_help=False)
    ap.add_argument("image", nargs="?")
    ap.add_argument("--out-dir")
    ap.add_argument("--no-open", action="store_true")
    ap.add_argument("--port", type=int, default=0)
    ap.add_argument("-h", "--help", action="store_true")
    try:
        args = ap.parse_args(argv)
    except SystemExit:
        return 2
    if args.help or not args.image:
        say(__doc__.strip().split("\n\n")[0])
        return 0 if args.help else 2
    if not os.path.isfile(args.image):
        return fail("There is no picture %s." % args.image, "/img edit <picture>")
    env = os.environ
    lang = env.get("LOTUS_LANG", "")
    if lang not in LANGS:
        lang = env.get("LANG", "en")[:2]
        lang = lang if lang in LANGS else "en"
    eng = engines.find_engine(env)
    if eng is None:
        return fail("The editor needs an image program: ImageMagick.",
                    "macOS ships its own; Linux: install imagemagick · Windows: winget install ImageMagick.ImageMagick")
    data_dir = env.get("LOTUS_EDIT_DATA") or os.path.join(tempfile.gettempdir(), "lotus-edit-%d" % os.getuid() if hasattr(os, "getuid") else "lotus-edit")
    clean_old(data_dir)
    session = Session(args.image, eng, data_dir, args.out_dir, env.get("LOTUS_IMG_LAST"), env.get("LOTUS_DOWNLOADS"))
    try:
        say("  %s Opening %s …" % (paint(DIM, "…"), os.path.basename(args.image)))
        session.prepare()
    except engines.EngineError as e:
        session.forget()
        return fail("%s – %s" % (os.path.basename(args.image), e.reason), "Pictures: JPEG, PNG, HEIC, WebP, AVIF, GIF, TIFF, BMP, RAW …")
    ed = Editor(session, lang, env.get("LOTUS_THIS", "this computer"), env.get("LOTUS_FILES_APP", "the file manager"))
    try:
        server = Server(("127.0.0.1", args.port), Handler)
    except OSError:
        session.forget()
        return fail("The port %d is taken." % args.port)
    for name in ("idle", "grace", "first"):
        try:
            setattr(ed, name, float(env.get("LOTUS_EDIT_" + name.upper(), getattr(ed, name))))
        except ValueError:
            pass
    server.editor = ed
    ed.port = server.server_address[1]
    url = "http://127.0.0.1:%d/%s/" % (ed.port, ed.token)
    w, h = session.size
    kv("Picture", "%s  %s" % (os.path.basename(args.image), paint(DIM, "%d × %d · %s" % (w, h, human(session.bytes)))))
    kv("Folder", "%s%s" % (tilde(session.out_dir), paint(DIM, "  (the folder of the picture is read-only)") if session.note else ""))
    kv("Address", paint(KEY, url))
    say()

    def end(signum, frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, end)
    if hasattr(signal, "SIGHUP"):
        signal.signal(signal.SIGHUP, end)
    threading.Thread(target=watch, args=(ed, server), daemon=True).start()
    if args.no_open or env.get("LOTUS_EDIT_NO_OPEN") or not open_url(url):
        say("  %s Open this address in your browser." % paint(KEY, "›", True))
    else:
        say("  %s Open in your browser. %s" % (paint(KEY, "✓", True), paint(DIM, "Ctrl-C closes it.")))
    code = 0
    try:
        server.serve_forever(poll_interval=0.25)
    except KeyboardInterrupt:
        code = 130 if not ed.quit else 0
    finally:
        server.server_close()
        saved = list(session.saved)
        session.forget()
    say()
    if saved:
        say("  %s %d picture%s saved." % (paint(KEY, "✓", True), len(saved), "" if len(saved) == 1 else "s"))
    else:
        say("  %s Closed – nothing was saved." % paint(DIM, "›"))
    return code


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        sys.exit(130)
