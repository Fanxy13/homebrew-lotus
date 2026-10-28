"""Live Server – a plugin for Lotus (plugin.conf), in Python with nothing but its standard library.

    lotus liveserver                  the folder you are in: opens index.html, or a menu of all its pages
    lotus liveserver <folder>         another folder
    lotus liveserver <page.html>      opens that page
    lotus liveserver --port <n>       a port of your choice (otherwise 5500, or the next free one)
    lotus liveserver --no-open        does not open the browser
    lotus liveserver --local          only this Mac, not the phones and computers in the same Wi-Fi
    lotus liveserver stop             stops the live servers that run in other windows

Like Live Server in VS Code: the page reloads when a file of the folder changes – only the style sheets when
nothing but CSS changed (a WebSocket, /__lotus/ws). Ctrl-C stops it. Phones and computers in the same Wi-Fi
(or Ethernet) open it too, at the Mac's address in that network – nobody else: a device from another network
is turned away, and so is any name for the Mac but its own (127.0.0.1, localhost, its address, its .local
name). With --local it listens on 127.0.0.1 only. It serves nothing outside the folder (no .., no links out of
it) and no hidden files (.git, .env). Full access: it reads the folder Lotus was called in ($LOTUS_PWD) and
opens the browser.
"""
import base64
import hashlib
import html
import ipaddress
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
        """(folder, its files) from top down, without hidden folders, node_modules and the like – and without the
        folders of documents /html made (Word/, PDF/ …): a conversion is no reason to reload the page."""
        for folder, dirs, files in os.walk(top or self.root):
            dirs[:] = sorted(d for d in dirs if not hidden(d) and d not in SKIP
                             and not os.path.exists(os.path.join(folder, d, ".lotus-html")))
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
        self.pages = {}             # each open page → (its file, when it was looked at last)
        self.page_file = ""         # running/<port>.page: the page in front right now – for /html

    def changed(self, styles_only):
        with self.lock:
            self.version += 1
            if not styles_only:
                self.reload_version = self.version

    def looking(self, who, rel):
        """A page in the browser opened or came to the front (rel: its file, "" for the menu) – or closed (None)."""
        with self.lock:
            if rel is None:
                self.pages.pop(who, None)
            else:
                self.pages[who] = (rel, time.time())
            if not self.page_file:
                return
            newest = max(self.pages.values(), key=lambda v: v[1], default=None)
            try:
                if newest and newest[0]:
                    with open(self.page_file + ".tmp", "w") as f:
                        f.write(f"{newest[0]}\n{newest[1]}\n")
                    os.replace(self.page_file + ".tmp", self.page_file)
                elif os.path.exists(self.page_file):
                    os.remove(self.page_file)
            except OSError:
                pass


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


# ── The Wi-Fi: who may open it besides this Mac ───────────────

WIFI = re.compile(r"(en|eth|wl|bridge)")     # Wi-Fi and Ethernet (en0, en1, …) and Internet Sharing – no VPN (utun), no AirDrop
HOTSPOT = ipaddress.IPv4Network("172.20.10.0/28")      # what an iPhone's Personal Hotspot hands out, over Wi-Fi or USB


def networks(ifconfig):
    """[(interface, IPv4Interface)] of the local networks in ifconfig's output – private addresses only, so a
    Mac with an address of the internet never lets the whole internet in."""
    found, name = [], ""
    for line in ifconfig.splitlines():
        m = re.match(r"(\S+?):? ", line)
        if m and not line[:1].isspace():
            name = m.group(1)
        m = re.search(r"\binet (?:addr:)?(\d+\.\d+\.\d+\.\d+)\s+netmask\s+(0x[0-9a-fA-F]{8}|\d+\.\d+\.\d+\.\d+)", line)
        if not m or not WIFI.match(name):
            continue
        mask = m.group(2)
        if mask.lower().startswith("0x"):
            mask = str(ipaddress.IPv4Address(int(mask, 16)))
        try:
            net = ipaddress.IPv4Interface(f"{m.group(1)}/{mask}")
        except ValueError:
            continue
        if net.ip.is_private and not net.ip.is_loopback and net.network.prefixlen >= 8:
            found.append((name, net))
    return found


def hardware_ports(text):
    """{device: its name in macOS} from networksetup -listallhardwareports: en0 → Wi-Fi, en7 → iPhone USB."""
    return {dev: name.strip() for name, dev in re.findall(r"Hardware Port: (.+)\nDevice: (\S+)", text)}


def where(iface, net, ports):
    """Who opens the page at this address of the Mac."""
    port = ports.get(iface, "")
    if net.ip in HOTSPOT:
        return "your iPhone, whose hotspot the Mac uses"
    if iface.startswith("bridge"):
        return "devices the Mac shares its internet with"
    if port == "Wi-Fi" or iface.startswith("wl") or (not port and iface == "en0"):
        return "phones and computers in this Wi-Fi"
    return "devices in this network" + (f" ({port})" if port else "")


def allowed(ip, nets):
    """May a device with this address open it? This Mac, and devices in one of its networks."""
    try:
        ip = ipaddress.ip_address(ip.split("%")[0])
    except ValueError:
        return False
    if ip.version == 6 and ip.ipv4_mapped:
        ip = ip.ipv4_mapped
    return ip.is_loopback or any(ip in net.network for _, net in nets)


class Lan:
    """The Mac's networks now – looked up again every few seconds: the Mac may join another Wi-Fi meanwhile."""

    def __init__(self, on):
        self.on = on
        self.at, self.nets, self.names = -1e9, [], set()
        self.local, self.ports, self.asked = None, {}, set()
        self.lock = threading.Lock()
        self.refused = set()

    def get(self):
        with self.lock:
            if self.on and time.monotonic() - self.at > 5:
                self.at = time.monotonic()
                self.nets = networks(run(["/sbin/ifconfig"]))
                if self.local is None:
                    self.local = local_names()
                new = {iface for iface, _ in self.nets} - self.asked
                if new:                             # a network the Mac was not in: what kind is it?
                    self.asked |= new
                    self.ports = hardware_ports(run(["/usr/sbin/networksetup", "-listallhardwareports"]))
                self.names = {str(net.ip) for _, net in self.nets} | self.local
            return self.nets, self.names

    def entries(self):
        """[(address, who opens the page there)] of the Mac in its networks – the Wi-Fi first, internet sharing last."""
        nets, _ = self.get()
        return [(str(net.ip), where(iface, net, self.ports))
                for iface, net in sorted(nets, key=lambda n: (n[0].startswith("bridge"), n[0]))]

    def addresses(self):
        return [ip for ip, _ in self.entries()]


def run(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=3).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def show_wifi(lan, port, page):
    """The addresses for phones and other devices, one per network, each with whom it is for."""
    rows = [(f"http://{ip}:{port}{page}", what) for ip, what in lan.entries()]
    width = max((len(url) for url, _ in rows), default=0)
    for i, (url, what) in enumerate(rows):
        kv("" if i else "Wi-Fi", f"{paint(KEY, url)}{' ' * (width - len(url))}  {paint(DIM, 'for ' + what)}")
    return bool(rows)


class NetWatcher(threading.Thread):
    """The Mac joins another Wi-Fi or hotspot while it runs: the terminal says the new address."""

    def __init__(self, lan, hub, port, page):
        super().__init__(daemon=True)
        self.lan, self.hub, self.port, self.page = lan, hub, port, page

    def run(self):
        old = self.lan.entries()
        while not self.hub.closing:
            time.sleep(1)
            new = self.lan.entries()                # looks again every 5 seconds
            if new == old:
                continue
            if not new:
                log("⇄", "No Wi-Fi now – only this Mac opens it", DIM)
            for ip, what in new:
                if (ip, what) not in old:
                    log("⇄", f"For {what}: {paint(KEY, f'http://{ip}:{self.port}{self.page}')}")
            old = new


def local_names():
    """The Mac's own names in the network: Name-MacBook.local."""
    names = set()
    out = run(["/usr/sbin/scutil", "--get", "LocalHostName"]).strip()
    if out:
        names.add(out.lower() + ".local")
    host = socket.gethostname().lower()
    if host.endswith(".local"):
        names.add(host)
    return names


def firewall_on():
    out = run(["/usr/libexec/ApplicationFirewall/socketfilterfw", "--getglobalstate"]).lower()
    return "enabled" in out or "state = 1" in out


# ── The server ─────────────────────────────────────────────────

class Server(ThreadingHTTPServer):
    allow_reuse_address = True      # a port this server had a moment ago (TIME_WAIT); taken() keeps it off others' ports
    daemon_threads = True

    def handle_error(self, request, client_address):
        pass                        # a browser that went away in the middle of an answer

    def verify_request(self, request, client_address):
        """Only this Mac and devices in its Wi-Fi: anyone else gets no answer at all."""
        ip = client_address[0]
        if allowed(ip, self.lan.get()[0]):
            return True
        if ip not in self.lan.refused and len(self.lan.refused) < 100:
            self.lan.refused.add(ip)
            log("✗", f"{ip} is not in this Wi-Fi – turned away", "31")
        return False


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
            return self.answer(403, "text/plain; charset=utf-8", b"Lotus Live Server answers only to its own addresses: 127.0.0.1, localhost and the Mac's address in the Wi-Fi.\n", head_only)
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
        """Only the Mac's own names – 127.0.0.1, localhost, its address in the Wi-Fi and its .local name: a web
        page cannot reach this server through a name of its own (DNS rebinding)."""
        host = (self.headers.get("Host") or "").lower()
        name = host.rpartition(":")[0] if re.search(r":\d+$", host) else host
        name = name.rstrip(".")
        return name in ("127.0.0.1", "localhost") or name.endswith(".localhost") or name in self.server.lan.get()[1]

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
        hub, sock, me = self.server.hub, self.connection, object()
        seen, pinged = hub.version, time.monotonic()
        try:
            while not hub.closing:
                readable, _, _ = select.select([sock], [], [], 0.25)
                if readable:
                    data = self.ws_read(sock)
                    if data is None:
                        return
                    if data.startswith(b"open "):           # reload.js: this page is in front now
                        hub.looking(me, self.page_of(data[5:].decode("utf-8", "replace")))
                if hub.version != seen:
                    self.ws_send(sock, b"reload" if hub.reload_version > seen else b"css")
                    seen = hub.version
                if time.monotonic() - pinged > 20:
                    self.ws_send(sock, b"", 0x9)
                    pinged = time.monotonic()
        except OSError:
            pass
        finally:
            hub.looking(me, None)

    def page_of(self, path):
        """The file of the page at a path of a URL – "" for the menu and what is not there."""
        site = self.server.site
        path = urlsplit(path).path
        full = None if path.startswith("/__lotus") else site.resolve(path)
        if full and os.path.isdir(full):
            full = site.index(full)
        return site.rel(full) if full and os.path.isfile(full) else ""

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
        """One frame of the browser → the text it sent (b"" for other frames), None when it closes."""
        hdr = self.recv(sock, 2)
        if not hdr:
            return None
        op, n = hdr[0] & 0x0F, hdr[1] & 0x7F
        if n == 126:
            n = struct.unpack(">H", self.recv(sock, 2) or b"\0\0")[0]
        elif n > 126:
            return None
        mask = self.recv(sock, 4) if hdr[1] & 0x80 else b"\0\0\0\0"
        data = self.recv(sock, n) if n else b""
        if mask is None or data is None or op == 0x8:
            return None
        data = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
        if op == 0x9:
            self.ws_send(sock, data[:125], 0xA)
        return data if op == 0x1 else b""


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
    """[(port, pid, folder, wifi)] of the live servers that run – the ones that ended without a word are cleaned up."""
    found = []
    folder = running_dir()
    for name in sorted(os.listdir(folder)):
        if not name.isdigit():                 # <port>.page: the page in front (Hub.looking)
            continue
        path = os.path.join(folder, name)
        try:
            with open(path) as f:
                pid, root, *more = f.read().split("\n")
            pid, port = int(pid), int(name)
        except (OSError, ValueError):
            pid = port = 0
        if pid and alive(pid):
            found.append((port, pid, root.strip(), "local" not in more))
        else:
            for stale in (path, path + ".page"):
                try:
                    os.remove(stale)
                except OSError:
                    pass
    return found


def taken(port):
    with socket.socket() as s:
        s.settimeout(0.3)
        return s.connect_ex(("127.0.0.1", port)) == 0


def bind(ports, host):
    for port in ports:
        if taken(port):
            continue
        try:
            return Server((host, port), Handler)
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
                      ("lotus liveserver --local", "only this Mac, not the devices in your Wi-Fi"),
                      ("lotus liveserver stop", "stops the ones running in other windows")):
        say(f"    {paint(KEY, cmd.ljust(30))}{what}")
    say()
    say(f"  {paint(DIM, 'The page reloads when you save a file – only the styles when you change CSS. Ctrl-C stops it.')}")
    say(f"  {paint(DIM, 'This Mac and the phones and computers in the same Wi-Fi can open it – nobody else.')}")
    say(f"  {paint(DIM, 'Hidden files (.git, .env) and files outside the folder stay out.')}")
    say()


def stop():
    servers = running()
    if not servers:
        say(f"  {paint(DIM, 'No live server is running.')}")
        return 0
    for port, pid, root, _ in servers:
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError:
            pass
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline and any(alive(pid) for _, pid, _, _ in servers):
        time.sleep(0.05)
    for port, pid, root, _ in servers:
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
    target, port, show, wifi = "", None, True, True
    i = 0
    while i < len(args):
        a = args[i]
        if a in ("--port", "-p") and i + 1 < len(args):
            port, i = args[i + 1], i + 1
        elif a.startswith("--port="):
            port = a.split("=", 1)[1]
        elif a == "--no-open":
            show = False
        elif a in ("--local", "--no-wifi"):
            wifi = False
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
    for p, pid, other, shared in running():
        if other == site.root:
            url = f"http://127.0.0.1:{p}{start}"
            header(tilde(site.root))
            say(f"  {paint(KEY, '✓', True)} Already running in another window: {paint(KEY, url)}")
            show_wifi(Lan(shared), p, "" if start == "/" else start)
            if show:
                open_browser(url)
            say(f"    {paint(DIM, 'lotus liveserver stop  stops it')}")
            say()
            return 0

    host = "0.0.0.0" if wifi else "127.0.0.1"       # 0.0.0.0: the Wi-Fi too – verify_request lets in only its devices
    server = bind([int(port)] if port else PORTS, host)
    if server is None and not port:
        server = bind([0], host)                    # 5500–5599 all taken: any free one
    if server is None:
        return fail(f"Port {port} is taken.", "lotus liveserver  takes the next free one from 5500")
    server.site, server.hub, server.lan = site, Hub(), Lan(wifi)
    port = server.server_address[1]
    base = f"http://127.0.0.1:{port}"
    mark = os.path.join(running_dir(), str(port))
    server.hub.page_file = mark + ".page"
    with open(mark, "w") as f:
        f.write(f"{os.getpid()}\n{site.root}\n{'wifi' if wifi else 'local'}\n")

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
    page = "" if start == "/" else start
    if not wifi:
        kv("Wi-Fi", paint(DIM, "off – only this Mac (--local)"))
    elif show_wifi(server.lan, port, page):
        if firewall_on():
            kv("", paint(DIM, "The macOS firewall is on: allow python3 when macOS asks."))
    else:
        kv("Wi-Fi", paint(DIM, "not in a Wi-Fi now – the address shows here as soon as the Mac joins one"))
    say()
    say(f"  {paint(KEY, '✓', True)} Live – the page reloads when you save. {paint(DIM, 'Ctrl-C stops it.')}")
    say()

    Watcher(site, server.hub).start()
    if wifi:
        NetWatcher(server.lan, server.hub, port, page).start()
    if show:
        open_browser(base + start)
    try:
        server.serve_forever(poll_interval=0.25)
    except KeyboardInterrupt:
        pass
    finally:
        server.hub.closing = True
        server.server_close()
        for path in (mark, mark + ".page"):
            try:
                os.remove(path)
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
