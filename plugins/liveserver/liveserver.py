"""Live Server – a plugin for Lotus (plugin.conf), in Python with nothing but its standard library.

    lotus liveserver                  the folder you are in: opens index.html, or a menu of all its pages
    lotus liveserver <folder>         another folder
    lotus liveserver <page.html>      opens that page
    lotus liveserver --port <n>       a port of your choice (otherwise 5500, or the next free one)
    lotus liveserver --no-open        does not open the browser
    lotus liveserver stop             stops the live servers that run in other windows

Like Live Server in VS Code: the page reloads when a file of the folder changes – only the style sheets when
nothing but CSS changed (a WebSocket, /__lotus/ws). Ctrl-C stops it. It listens on 127.0.0.1 and answers only
to 127.0.0.1 and localhost, and serves nothing outside the folder (no .., no links out of it) and no hidden
files (.git, .env). Full access: it reads the folder Lotus was called in ($LOTUS_PWD) and opens the browser.
"""
import base64
import hashlib
import html
import mimetypes
import os
import re
import select
import signal
import socket
import struct
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import quote, unquote, urlsplit

HERE = os.path.dirname(os.path.abspath(__file__))
PORTS = range(5500, 5600)                      # VS Code's Live Server starts at 5500 too
PAGES = (".html", ".htm")
SKIP = {"node_modules", "__pycache__", "venv", "bower_components"}
MAX_FILES = 50000                              # files the watcher looks at
TAG = b'<script src="/__lotus/reload.js"></script>'
WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
TYPES = {
    ".html": "text/html", ".htm": "text/html", ".css": "text/css", ".js": "text/javascript", ".mjs": "text/javascript",
    ".json": "application/json", ".map": "application/json", ".webmanifest": "application/manifest+json",
    ".xml": "application/xml", ".txt": "text/plain", ".md": "text/markdown", ".csv": "text/csv",
    ".svg": "image/svg+xml", ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".gif": "image/gif",
    ".webp": "image/webp", ".avif": "image/avif", ".ico": "image/x-icon", ".pdf": "application/pdf",
    ".woff": "font/woff", ".woff2": "font/woff2", ".ttf": "font/ttf", ".otf": "font/otf", ".wasm": "application/wasm",
    ".mp4": "video/mp4", ".webm": "video/webm", ".mov": "video/quicktime", ".mp3": "audio/mpeg", ".wav": "audio/wav",
    ".ogg": "audio/ogg", ".m4a": "audio/mp4", ".glb": "model/gltf-binary", ".gltf": "model/gltf+json",
}
TEXT = ("text/", "application/json", "application/manifest+json", "application/xml", "image/svg+xml")

TTY = sys.stdout.isatty()
HOME = os.path.realpath(os.path.expanduser("~"))


# ── Lotus' look in the terminal ────────────────────────────────

def color(name, fallback):
    code = os.environ.get("LOTUS_COLOR_" + name, "")
    return code if re.fullmatch(r"[0-9;]+", code) else fallback


KEY, ACCENT, DIM, LOGO = color("KEY", "38;5;150"), color("ACCENT", "38;5;149"), color("DIM", "38;5;245"), color("LOGO", "38;5;218")


def paint(code, text, bold=False):
    return f"\033[{'1;' if bold else ''}{code}m{text}\033[0m" if TTY else text


def bold(text):
    return f"\033[1m{text}\033[0m" if TTY else text


def say(text=""):
    print(text, flush=True)


def kv(key, value):
    say(f"    {paint(DIM, key.ljust(12))}{value}")


def fail(text, hint=""):
    say(f"  {paint('31', '✗', True)} {text}")
    if hint:
        say(f"    {paint(DIM, hint)}")
    return 1


def tilde(path):
    return "~" + path[len(HOME):] if path == HOME or path.startswith(HOME + os.sep) else path


def css_color(code, fallback):
    """An SGR color code of the theme (38;2;r;g;b or 38;5;n) → #rrggbb for the menu page."""
    p = code.split(";")
    try:
        if p[:2] == ["38", "2"] and len(p) == 5:
            r, g, b = (int(x) for x in p[2:])
        elif p[:2] == ["38", "5"] and len(p) == 3 and int(p[2]) >= 16:
            n = int(p[2])
            if n >= 232:
                r = g = b = 8 + (n - 232) * 10
            else:
                steps = (0, 95, 135, 175, 215, 255)
                n -= 16
                r, g, b = steps[n // 36], steps[n // 6 % 6], steps[n % 6]
        else:
            return fallback
    except ValueError:
        return fallback
    return f"#{r:02x}{g:02x}{b:02x}"


# ── The folder ─────────────────────────────────────────────────

def hidden(name):
    return name.startswith(".") or name.endswith("~")


def temporary(name):     # what editors write while they save: no reason to reload
    return hidden(name) or name.endswith((".swp", ".swx", ".tmp", ".crdownload")) or name == "4913"


class Site:
    def __init__(self, root):
        self.root = os.path.realpath(root)
        self.name = os.path.basename(self.root) or self.root

    def walk(self, top=None):
        """(folder, its files) from top down, without hidden folders, node_modules and the like."""
        for folder, dirs, files in os.walk(top or self.root):
            dirs[:] = sorted(d for d in dirs if not hidden(d) and d not in SKIP)
            yield folder, sorted(f for f in files if not hidden(f))

    def resolve(self, urlpath):
        """The file or folder for a path of a URL – None when it is outside the folder, hidden or not there."""
        parts = [p for p in unquote(urlpath).split("/") if p not in ("", ".")]
        if any(p == ".." or hidden(p) or "\0" in p or "\\" in p for p in parts):
            return None
        full = os.path.realpath(os.path.join(self.root, *parts))
        if full != self.root and not full.startswith(self.root + os.sep):
            return None                        # a link that points out of the folder
        return full if os.path.exists(full) else None

    def rel(self, full):
        return "" if full == self.root else os.path.relpath(full, self.root).replace(os.sep, "/")

    def pages(self, under=""):
        top = os.path.join(self.root, under) if under else self.root
        found = []
        for folder, files in self.walk(top):
            files = sorted((f for f in files if f.lower().endswith(PAGES)), key=lambda f: (f.lower() not in ("index.html", "index.htm"), f.lower()))
            found += [self.rel(os.path.join(folder, f)) for f in files]
            if len(found) >= 2000:
                break
        return found[:2000]

    def index(self, folder=None):
        for name in ("index.html", "index.htm"):
            path = os.path.join(folder or self.root, name)
            if os.path.isfile(path):
                return path
        return None


def page_title(path):
    try:
        with open(path, "rb") as f:
            head = f.read(65536).decode("utf-8", "replace")
    except OSError:
        return ""
    m = re.search(r"<title[^>]*>(.*?)</title", head, re.I | re.S)
    return " ".join(html.unescape(m.group(1)).split())[:120] if m else ""


# ── Pages of its own: the menu and "not here" ─────────────────

def theme():
    key = css_color(KEY, "#b5d371")
    return {"key": key, "accent": css_color(ACCENT, "#a6c47a"), "logo": css_color(LOGO, "#f8b8d0"), "icon": key.replace("#", "%23")}


def render(title, body):
    with open(os.path.join(HERE, "page.html"), encoding="utf-8") as f:
        out = f.read()
    for k, v in {**theme(), "title": html.escape(title), "body": body}.items():
        out = out.replace("{{" + k + "}}", v)
    return out.encode()


def href(rel):
    return quote("/" + rel)


def head(site, crumbs, count):
    e = html.escape
    where = [f"<span>{e(tilde(site.root))}</span>"]
    if crumbs:
        where += ['<span class="sep">·</span>', '<a href="/__lotus/">all pages</a>']
    where += ['<span class="sep">·</span>', f"<span>{count} {'page' if count == 1 else 'pages'}</span>",
              '<span class="live"><i></i><b class="on">live</b><b class="off">stopped – lotus liveserver starts it again</b></span>']
    name = e(site.name) + (f" / {e(crumbs)}" if crumbs else "")
    return f'<header>\n<p class="eyebrow">Live Server</p>\n<h1><span>{name}</span></h1>\n<p class="where">{"".join(where)}</p>\n</header>\n'


def menu(site, under=""):
    """All pages of the folder (or of one folder in it), by folder – with their titles."""
    e = html.escape
    pages = site.pages(under)
    body = head(site, under, len(pages))
    if not pages:
        body += ('<p class="empty"><strong>No pages here yet.</strong><br>Make an <code>index.html</code> – '
                 'this page shows it as soon as it is there.</p>\n')
        return render(f"{site.name} – Live Server", body)
    if len(pages) > 6:
        body += '<input class="filter" type="search" placeholder="Filter pages – Enter opens the first" aria-label="Filter pages">\n'
    groups = {}
    for rel in pages:
        groups.setdefault(rel.rpartition("/")[0], []).append(rel)
    titled = 0
    for folder, rels in groups.items():
        label = (folder + "/") if folder else "/"
        body += f'<section class="group">\n<h2><a href="{href(folder + "/") if folder else "/__lotus/"}">{e(label)}</a><small>{len(rels)}</small></h2>\n<div class="pages">\n'
        for rel in rels:
            file = rel.rpartition("/")[2]
            title = page_title(os.path.join(site.root, rel)) if titled < 400 else ""
            titled += 1
            home = " home" if file.lower() in ("index.html", "index.htm") else ""
            q = e(f"{rel} {title}".lower())
            body += (f'<a class="page{home}" href="{href(rel)}" data-q="{q}"><span class="name">{e(title or file)}</span>'
                     f'<span class="file">{e(rel)}</span></a>\n')
        body += "</div>\n</section>\n"
    body += '<p class="none">No page matches.</p>\n'
    return render(f"{site.name} – Live Server", body)


def not_here(site, path):
    body = head(site, "", len(site.pages()))
    body += (f'<p class="empty"><strong>Not here: {html.escape(unquote(path))}</strong><br>It is not in the folder – '
             'or it is hidden (a name that starts with a dot). This page reloads when it comes. '
             '<a href="/__lotus/">All pages</a></p>\n')
    return render(f"Not here – {site.name}", body)


def inject(data):
    """The reload script into a page: before </body>, or at its end."""
    at = data.lower().rfind(b"</body")
    return data[:at] + TAG + data[at:] if at >= 0 else data + TAG


# ── Who waits for a change ─────────────────────────────────────

class Hub:
    def __init__(self):
        self.version = 0            # +1 with every change
        self.reload_version = 0     # the last change that needs a whole reload (not only CSS)
        self.closing = False
        self.lock = threading.Lock()

    def changed(self, styles_only):
        with self.lock:
            self.version += 1
            if not styles_only:
                self.reload_version = self.version


class Watcher(threading.Thread):
    """Looks at the folder a few times a second; a change goes to every page that is open."""

    def __init__(self, site, hub):
        super().__init__(daemon=True)
        self.site, self.hub = site, hub

    def snapshot(self):
        snap = {}
        for folder, files in self.site.walk():
            for f in files:
                if temporary(f):
                    continue
                path = os.path.join(folder, f)
                try:
                    st = os.stat(path)
                except OSError:
                    continue
                snap[path] = (st.st_mtime_ns, st.st_size)
                if len(snap) >= MAX_FILES:
                    return snap
        return snap

    def run(self):
        old, pause = self.snapshot(), 0.3
        while not self.hub.closing:
            time.sleep(pause)
            started = time.monotonic()
            new = self.snapshot()
            pause = max(0.3, min(5.0, (time.monotonic() - started) * 8))    # a huge folder: look less often
            changed = [p for p in new if old.get(p) != new[p]] + [p for p in old if p not in new]
            old = new
            if not changed:
                continue
            styles_only = all(p.lower().endswith(".css") and p in new for p in changed)
            self.hub.changed(styles_only)
            first = self.site.rel(changed[0])
            what = first if len(changed) == 1 else f"{first} and {len(changed) - 1} more"
            log("↻", what + (paint(DIM, "  styles only") if styles_only else ""))


def log(mark, text, code=None):
    say(f"  {paint(DIM, time.strftime('%H:%M:%S'))}  {paint(code or KEY, mark)} {text}")


# ── The server ─────────────────────────────────────────────────

class Server(ThreadingHTTPServer):
    allow_reuse_address = True      # a port this server had a moment ago (TIME_WAIT); taken() keeps it off others' ports
    daemon_threads = True

    def handle_error(self, request, client_address):
        pass                        # a browser that went away in the middle of an answer


class Handler(BaseHTTPRequestHandler):
    server_version = "LotusLiveServer/1.0"
    protocol_version = "HTTP/1.1"      # keep-alive, and what a WebSocket needs
    timeout = 120                      # a connection the browser keeps open without asking anything

    def log_message(self, *args):
        pass

    def do_HEAD(self):
        self.do_GET(True)

    def do_GET(self, head_only=False):
        site = self.server.site
        if not self.host_ok():
            return self.answer(403, "text/plain; charset=utf-8", b"Lotus Live Server answers only to 127.0.0.1 and localhost.\n", head_only)
        url = urlsplit(self.path)
        path = url.path or "/"
        if path == "/__lotus/ws":
            return self.websocket()
        if path == "/__lotus/reload.js":
            with open(os.path.join(HERE, "reload.js"), "rb") as f:
                return self.answer(200, "text/javascript; charset=utf-8", f.read(), head_only)
        if path in ("/__lotus", "/__lotus/"):
            return self.answer(200, "text/html; charset=utf-8", menu(site), head_only)
        full = None if path.startswith("/__lotus/") else site.resolve(path)
        if full is None:
            if not path.endswith("/favicon.ico"):
                log("404", path, DIM)
            return self.answer(404, "text/html; charset=utf-8", not_here(site, path), head_only)
        if os.path.isdir(full):
            if not path.endswith("/"):
                return self.answer(301, "text/plain; charset=utf-8", b"", head_only, [("Location", path + "/" + (f"?{url.query}" if url.query else ""))])
            index = site.index(full)
            if index:
                return self.file(index, head_only)
            return self.answer(200, "text/html; charset=utf-8", menu(site, site.rel(full)), head_only)
        return self.file(full, head_only)

    def host_ok(self):
        """Only 127.0.0.1 and localhost: a web page cannot reach this server through a name of its own."""
        host = (self.headers.get("Host") or "").lower()
        name = host.rpartition(":")[0] if re.search(r":\d+$", host) else host
        return name in ("127.0.0.1", "localhost") or name.endswith(".localhost")

    def answer(self, code, ctype, data, head_only, extra=()):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        for k, v in extra:
            self.send_header(k, v)
        self.end_headers()
        if not head_only:
            self.wfile.write(data)

    def file(self, full, head_only):
        ext = os.path.splitext(full)[1].lower()
        ctype = TYPES.get(ext) or mimetypes.guess_type(full)[0] or "application/octet-stream"
        if ctype.startswith(TEXT):
            ctype += "; charset=utf-8"
        try:
            if ext in PAGES:
                with open(full, "rb") as f:
                    return self.answer(200, ctype, inject(f.read()), head_only)
            size = os.path.getsize(full)
            start, end, code = 0, size - 1, 200
            m = re.fullmatch(r"bytes=(\d*)-(\d*)", (self.headers.get("Range") or "").strip())
            if m and (m.group(1) or m.group(2)):          # one range: videos in Safari need it
                if m.group(1):
                    start = int(m.group(1))
                    end = min(int(m.group(2)), size - 1) if m.group(2) else size - 1
                else:
                    start = max(0, size - int(m.group(2)))
                if start > end:
                    return self.answer(416, "text/plain", b"", head_only, [("Content-Range", f"bytes */{size}")])
                code = 206
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(max(0, end - start + 1)))
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Cache-Control", "no-store")
            if code == 206:
                self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
            self.end_headers()
            if head_only:
                return
            with open(full, "rb") as f:
                f.seek(start)
                left = end - start + 1
                while left > 0:
                    chunk = f.read(min(65536, left))
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    left -= len(chunk)
        except (PermissionError, IsADirectoryError):
            self.answer(403, "text/plain; charset=utf-8", b"Not readable.\n", head_only)

    # A WebSocket that says "reload" or "css" when the folder changes (the browser's side: reload.js)
    def websocket(self):
        key = self.headers.get("Sec-WebSocket-Key", "")
        if "websocket" not in self.headers.get("Upgrade", "").lower() or not key:
            return self.answer(400, "text/plain", b"A WebSocket only.\n", False)
        accept = base64.b64encode(hashlib.sha1((key + WS_GUID).encode()).digest()).decode()
        self.send_response(101, "Switching Protocols")
        self.send_header("Upgrade", "websocket")
        self.send_header("Connection", "Upgrade")
        self.send_header("Sec-WebSocket-Accept", accept)
        self.end_headers()
        self.wfile.flush()
        self.close_connection = True
        hub, sock = self.server.hub, self.connection
        seen, pinged = hub.version, time.monotonic()
        try:
            while not hub.closing:
                readable, _, _ = select.select([sock], [], [], 0.25)
                if readable and not self.ws_read(sock):
                    return
                if hub.version != seen:
                    self.ws_send(sock, b"reload" if hub.reload_version > seen else b"css")
                    seen = hub.version
                if time.monotonic() - pinged > 20:
                    self.ws_send(sock, b"", 0x9)
                    pinged = time.monotonic()
        except OSError:
            pass

    @staticmethod
    def ws_send(sock, data, op=0x1):
        sock.sendall(bytes([0x80 | op, len(data)]) + data)

    @staticmethod
    def recv(sock, n):
        out = b""
        while len(out) < n:
            part = sock.recv(n - len(out))
            if not part:
                return None
            out += part
        return out

    def ws_read(self, sock):
        """One frame of the browser: False when it closes."""
        hdr = self.recv(sock, 2)
        if not hdr:
            return False
        op, n = hdr[0] & 0x0F, hdr[1] & 0x7F
        if n == 126:
            n = struct.unpack(">H", self.recv(sock, 2) or b"\0\0")[0]
        elif n > 126:
            return False
        mask = self.recv(sock, 4) if hdr[1] & 0x80 else b"\0\0\0\0"
        data = self.recv(sock, n) if n else b""
        if mask is None or data is None or op == 0x8:
            return False
        if op == 0x9:
            data = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
            self.ws_send(sock, data[:125], 0xA)
        return True


# ── Live servers that run (in other windows): one file per port in the plugin's data folder ──

def running_dir():
    path = os.path.join(os.environ.get("LOTUS_PLUGIN_DATA") or os.path.join(HOME, ".local/share/lotus/plugins/liveserver"), "running")
    os.makedirs(path, exist_ok=True)
    return path


def alive(pid):
    """Is pid a live server that still runs? (A number macOS gave to another program since is not.)"""
    try:
        out = subprocess.run(["/bin/ps", "-p", str(pid), "-o", "command="], capture_output=True, text=True, timeout=3).stdout
    except (OSError, subprocess.SubprocessError):
        return False
    return "liveserver.py" in out


def running():
    """[(port, pid, folder)] of the live servers that run – the ones that ended without a word are cleaned up."""
    found = []
    folder = running_dir()
    for name in sorted(os.listdir(folder)):
        path = os.path.join(folder, name)
        try:
            with open(path) as f:
                pid, root = f.read().split("\n", 1)
            pid, port = int(pid), int(name)
        except (OSError, ValueError):
            pid = port = 0
        if pid and alive(pid):
            found.append((port, pid, root.strip()))
        else:
            try:
                os.remove(path)
            except OSError:
                pass
    return found


def taken(port):
    with socket.socket() as s:
        s.settimeout(0.3)
        return s.connect_ex(("127.0.0.1", port)) == 0


def bind(ports):
    for port in ports:
        if taken(port):
            continue
        try:
            return Server(("127.0.0.1", port), Handler)
        except OSError:
            continue
    return None


def open_browser(url):
    try:
        subprocess.Popen(["/usr/bin/open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        pass


def header(sub=""):
    say()
    say(f"  {paint(ACCENT, 'lotus', True)}{paint(DIM, ' / ')}{bold('Live Server')}{paint(DIM, '  ' + sub) if sub else ''}")
    say()


def usage():
    header("like Live Server in VS Code")
    for cmd, what in (("lotus liveserver", "the folder you are in: index.html, or a menu of its pages"),
                      ("lotus liveserver <folder>", "another folder"),
                      ("lotus liveserver <page.html>", "opens that page"),
                      ("lotus liveserver --port 8080", "a port of your choice (otherwise 5500 or the next free one)"),
                      ("lotus liveserver --no-open", "without opening the browser"),
                      ("lotus liveserver stop", "stops the ones running in other windows")):
        say(f"    {paint(KEY, cmd.ljust(30))}{what}")
    say()
    say(f"  {paint(DIM, 'The page reloads when you save a file – only the styles when you change CSS. Ctrl-C stops it.')}")
    say(f"  {paint(DIM, 'Only this Mac can open it (127.0.0.1). Hidden files (.git, .env) and files outside the folder stay out.')}")
    say()


def stop():
    servers = running()
    if not servers:
        say(f"  {paint(DIM, 'No live server is running.')}")
        return 0
    for port, pid, root in servers:
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError:
            pass
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline and any(alive(pid) for _, pid, _ in servers):
        time.sleep(0.05)
    for port, pid, root in servers:
        say(f"  {paint(KEY, '✓', True)} Stopped http://127.0.0.1:{port}  {paint(DIM, tilde(root))}")
    return 0


def main(args):
    here = os.environ.get("LOTUS_PWD", "")
    if args[:1] in (["help"], ["-h"], ["--help"]):
        usage()
        return 0
    if args[:1] == ["stop"]:
        return stop()
    if not here:
        return fail("Live Server needs a newer Lotus – it does not know the folder you are in.", "lotus update")
    target, port, show = "", None, True
    i = 0
    while i < len(args):
        a = args[i]
        if a in ("--port", "-p") and i + 1 < len(args):
            port, i = args[i + 1], i + 1
        elif a.startswith("--port="):
            port = a.split("=", 1)[1]
        elif a == "--no-open":
            show = False
        elif a.startswith("-"):
            usage()
            return 2
        elif re.fullmatch(r"\d{2,5}", a) and not os.path.exists(os.path.join(here, a)):
            port = a
        elif not target:
            target = a
        else:
            return fail(f"One folder or page at a time – not {a} too.")
        i += 1
    if port is not None and not (port.isdigit() and 1024 <= int(port) <= 65535):
        return fail(f"Port {port}? A number from 1024 to 65535.", "lotus liveserver --port 8080")

    path = os.path.realpath(os.path.join(here, os.path.expanduser(target))) if target else os.path.realpath(here)
    start = "/"
    if os.path.isfile(path):
        if not path.lower().endswith(PAGES):
            return fail(f"{tilde(path)} is not a page.", "lotus liveserver <folder> or <page.html>")
        root = os.path.realpath(here)
        if not path.startswith(root + os.sep):      # a page somewhere else: its own folder
            root = os.path.dirname(path)
        start = href(os.path.relpath(path, root).replace(os.sep, "/"))
    elif os.path.isdir(path):
        root = path
    else:
        return fail(f"There is no {target}.", "lotus liveserver <folder> or <page.html>")
    if root in (HOME, "/") or root == os.path.dirname(HOME):
        return fail(f"That is your whole {'home folder' if root == HOME else 'disk'} – go to the folder of a project first.",
                    "cd ~/path/to/site  or  lotus liveserver ~/path/to/site")

    site = Site(root)
    for p, pid, other in running():
        if other == site.root:
            url = f"http://127.0.0.1:{p}{start}"
            header(tilde(site.root))
            say(f"  {paint(KEY, '✓', True)} Already running in another window: {paint(KEY, url)}")
            if show:
                open_browser(url)
            say(f"    {paint(DIM, 'lotus liveserver stop  stops it')}")
            say()
            return 0

    server = bind([int(port)] if port else PORTS)
    if server is None and not port:
        server = bind([0])                          # 5500–5599 all taken: any free one
    if server is None:
        return fail(f"Port {port} is taken.", "lotus liveserver  takes the next free one from 5500")
    server.site, server.hub = site, Hub()
    port = server.server_address[1]
    base = f"http://127.0.0.1:{port}"
    mark = os.path.join(running_dir(), str(port))
    with open(mark, "w") as f:
        f.write(f"{os.getpid()}\n{site.root}\n")

    def end(signum, frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, end)
    signal.signal(signal.SIGHUP, end)

    pages = site.pages()
    index = site.index()
    header(tilde(site.root))
    if start != "/":
        kv("Address", f"{paint(KEY, base + start)}")
        kv("All pages", f"{base}/__lotus/  {paint(DIM, f'{len(pages)} in the folder')}")
    elif index:
        kv("Address", f"{paint(KEY, base)}  {paint(DIM, '→ ' + os.path.basename(index))}")
        kv("All pages", f"{base}/__lotus/  {paint(DIM, f'{len(pages)} in the folder')}")
    else:
        n = len(pages)
        kv("Address", f"{paint(KEY, base)}  {paint(DIM, '→ a menu of ' + (f'{n} page' if n == 1 else f'{n} pages') if n else '→ no pages yet')}")
    say()
    say(f"  {paint(KEY, '✓', True)} Live – the page reloads when you save. {paint(DIM, 'Ctrl-C stops it.')}")
    say()

    Watcher(site, server.hub).start()
    if show:
        open_browser(base + start)
    try:
        server.serve_forever(poll_interval=0.25)
    except KeyboardInterrupt:
        pass
    finally:
        server.hub.closing = True
        server.server_close()
        try:
            os.remove(mark)
        except OSError:
            pass
    try:
        say(f"\r  {paint(KEY, '✓', True)} Stopped {paint(DIM, base)}")
    except OSError:
        pass                                    # the window was closed
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        sys.exit(130)
