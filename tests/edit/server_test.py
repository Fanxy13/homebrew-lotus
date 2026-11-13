"""The image editor's server (lib/edit/editor.py) as a browser meets it: the page and its files, who is let in, saving, and how it
ends – the real program on a port of its own, asked over HTTP. python3 tests/edit/server_test.py"""
import glob
import http.client
import json
import os
import re
import subprocess
import sys
import threading
import time
from urllib.parse import quote

from kit import EDIT, bmp_pixel, finish, png, png_size, test, tmpdir

import engine as E

if E.find_engine() is None:
    print("  – no image program here (ImageMagick, or lotus-img on a Mac): skipped")
    sys.exit(0)

D = tmpdir()
os.makedirs(D + "/pics")
IMAGE = png(D + "/pics/shot.png", 400, 300, lambda x, y: (x % 256, y % 256, 120))
ENV = dict(os.environ, LOTUS_EDIT_DATA=D + "/data", LOTUS_EDIT_NO_SHOW="1", LOTUS_IMG_LAST=D + "/img-last", LOTUS_LANG="de",
           LOTUS_DOWNLOADS=D + "/Downloads", PYTHONDONTWRITEBYTECODE="1")


class Editor(object):
    """An editor process: its output lines, its address."""

    def __init__(self, image, extra_env=None, args=()):
        self.lines = []
        self.proc = subprocess.Popen([sys.executable, "-B", EDIT + "/editor.py"] + ([image] if image else []) + ["--no-open"] + list(args), stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT, universal_newlines=True, env=dict(ENV, **(extra_env or {})))
        threading.Thread(target=self._read, daemon=True).start()
        self.url = None
        end = time.time() + 20
        while time.time() < end and self.proc.poll() is None:
            m = re.search(r"http://127\.0\.0\.1:(\d+)/([\w-]+)/", "\n".join(self.lines))
            if m:
                self.port, self.token, self.url = int(m.group(1)), m.group(2), m.group(0)
                break
            time.sleep(0.05)

    def _read(self):
        for line in self.proc.stdout:
            self.lines.append(re.sub(r"\x1b\[[0-9;]*m", "", line.rstrip("\n")))

    def request(self, method, path, body=None, headers=None, host=None, token=True):
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=30)
        c.putrequest(method, ("/%s/" % self.token if token is True else "/") + path if token else path, skip_host=True)
        c.putheader("Host", host or "127.0.0.1:%d" % self.port)
        for k, v in (headers or {}).items():
            c.putheader(k, v)
        data = body if body is not None else b""
        if method == "POST":
            c.putheader("Content-Length", str(len(data)))
        c.endheaders(data if method == "POST" else None)
        r = c.getresponse()
        out = r.read()
        c.close()
        return r.status, dict((k.lower(), v) for k, v in r.getheaders()), out

    def post(self, path, body=None, extra=None, **kw):
        return self.request("POST", path, body, dict({"X-Lotus-Edit": "1"}, **(extra or {})), **kw)

    def wait(self, seconds):
        end = time.time() + seconds
        while time.time() < end and self.proc.poll() is None:
            time.sleep(0.05)
        return self.proc.poll()

    def output(self):
        time.sleep(0.2)
        return "\n".join(self.lines)

    def kill(self):
        if self.proc.poll() is None:
            self.proc.kill()
        self.proc.wait()


ed = Editor(IMAGE)
assert ed.url, "the editor did not start: " + ed.output()


@test("it says what it opened and where, and that it listens on this computer only")
def _():
    out = ed.output()
    assert "shot.png  400 × 300" in out and "Address" in out and "127.0.0.1" in out, out


@test("the page: HTML for this picture, a strict content policy, nothing cached")
def _():
    status, h, body = ed.request("GET", "")
    page = body.decode("utf-8")
    assert status == 200 and h["content-type"].startswith("text/html")
    assert "default-src 'none'" in h["content-security-policy"] and "script-src 'self'" in h["content-security-policy"]
    assert "worker-src 'self'" in h["content-security-policy"], "the face detector's worker (a browser without CSP 3's fallback)"
    assert h["cache-control"] == "no-store" and h["x-content-type-options"] == "nosniff"
    assert '<html lang="de">' in page and "<title>shot.png – Lotus</title>" in page
    cfg = json.loads(re.search(r'<script type="application/json" id="config">(.*?)</script>', page, re.S).group(1))
    assert cfg["image"]["name"] == "shot.png" and cfg["image"]["width"] == 400 and cfg["lang"] == "de"
    assert cfg["strings"]["cancel"] == "Abbrechen" and cfg["strings"]["q_85"] == "Hoch"
    assert cfg["defaults"] == {"format": "png", "quality": 85, "max": 0}, cfg["defaults"]
    assert [f["key"] for f in cfg["formats"]][:2] == ["jpeg", "png"]


@test("the page's files, and only those")
def _():
    for name, kind in (("editor.js", "javascript"), ("geometry.js", "javascript"), ("editor.css", "css"), ("blur.js", "javascript"),
                       ("faces.js", "javascript"), ("faces-worker.js", "javascript"), ("faces.bin", "application/octet-stream")):
        status, h, body = ed.request("GET", "web/" + name)
        assert status == 200 and kind in h["content-type"] and len(body) > 1000, name
    status, _, body = ed.request("GET", "web/faces.bin")
    assert body[:8] == b"LFACE1\n\0", "the face detector of the Face Blur tab"
    for name in ("strings.json", "index.html", "../editor.py", "..%2Feditor.py", "editor.js/../../editor.py", ".", ""):
        status, _, body = ed.request("GET", "web/" + name)
        assert status == 404 and b"def main" not in body, (name, status)


@test("the picture for the browser: a PNG as big as the picture")
def _():
    status, h, body = ed.request("GET", "image")
    assert status == 200 and h["content-type"] == "image/png" and body[:8] == b"\x89PNG\r\n\x1a\n"
    with open(D + "/got.png", "wb") as f:
        f.write(body)
    assert png_size(D + "/got.png") == (400, 300)


@test("without the secret in the address there is nothing: 404, for everything")
def _():
    for path in ("", "image", "web/editor.js", "api/plan?format=png", "x/"):
        status, _, _ = ed.request("GET", "/" + path, token=False)
        assert status == 404, (path, status)
        status, _, _ = ed.request("GET", "/wrong-secret/" + path, token=False)
        assert status == 404, (path, status)
    status, _, _ = ed.post("/wrong-secret/api/quit", token=False)
    assert status == 404 and ed.proc.poll() is None
    status, _, _ = ed.request("GET", "/%C3%A9%FF%00/image", token=False)                    # odd bytes in the address
    assert status == 404, status
    c = http.client.HTTPConnection("127.0.0.1", ed.port, timeout=10)                         # a length that is no number
    c.putrequest("POST", "/%s/api/save?format=jpeg&edited=1" % ed.token, skip_host=True)
    c.putheader("Host", "127.0.0.1:%d" % ed.port)
    c.putheader("X-Lotus-Edit", "1")
    c.putheader("Content-Length", "many")
    c.endheaders()
    assert c.getresponse().status == 400
    c.close()


@test("a web page cannot reach it under a name of its own (DNS rebinding): only 127.0.0.1 and localhost")
def _():
    for host in ("evil.example", "evil.example:%d" % ed.port, "127.0.0.1.evil.example:%d" % ed.port, "127.0.0.1", "localhost"):
        status, _, _ = ed.request("GET", "", host=host)
        assert status == 403, (host, status)
    status, _, _ = ed.request("GET", "", host="localhost:%d" % ed.port)
    assert status == 200


@test("a request that changes something must come from the page itself")
def _():
    status, _, _ = ed.request("POST", "api/quit", b"")                                        # no header of the page
    assert status == 403 and ed.proc.poll() is None
    status, _, _ = ed.post("api/quit", extra={"Origin": "http://evil.example"})
    assert status == 403
    status, _, _ = ed.post("api/quit", extra={"Sec-Fetch-Site": "cross-site"})
    assert status == 403
    status, _, _ = ed.post("api/quit", host="evil.example")
    assert status == 403
    assert ed.proc.poll() is None, "none of them may have ended it"
    status, _, _ = ed.post("api/ping", extra={"Origin": "http://127.0.0.1:%d" % ed.port, "Sec-Fetch-Site": "same-origin"})
    assert status == 200


@test("what a save would be called, per format")
def _():
    status, _, body = ed.request("GET", "api/plan?format=jpeg&edited=1")
    j = json.loads(body)
    assert status == 200 and j["name"] == "shot edited.jpg", j
    status, _, body = ed.request("GET", "api/plan?format=png&edited=0")
    assert json.loads(body)["name"] == "shot (2).png"                                          # shot.png is the original
    status, _, _ = ed.request("GET", "api/plan?format=nothing&edited=0")
    assert status == 400


@test("a save: the cropped picture arrives, the new file is written next to the original, the original stays")
def _():
    crop = png(D + "/crop.png", 200, 100, lambda x, y: (x, y, 50))
    with open(crop, "rb") as f:
        body = f.read()
    status, _, out = ed.post("api/save?format=jpeg&quality=80&max=100&edited=1", body, {"Content-Type": "image/png"})
    j = json.loads(out)
    assert status == 200 and j["ok"] and j["name"] == "shot edited.jpg", j
    assert (j["width"], j["height"]) == (100, 50) and os.path.isfile(D + "/pics/shot edited.jpg"), j
    assert j["folder"] == D + "/pics" or j["folder"].endswith("pics")
    assert png_size(IMAGE) == (400, 300)
    status, _, out = ed.post("api/save?format=jpeg&quality=80&max=0&edited=1", body)
    assert json.loads(out)["name"] == "shot edited (2).jpg", out
    leftovers = [f for f in os.listdir(D + "/data") for g in os.listdir(D + "/data/" + f) if g.startswith("crop")]
    assert not leftovers, "the upload is deleted after the save: %r" % leftovers
    assert "Saved" in ed.output() and "shot edited.jpg" in ed.output()


@test("a save without editing: the original in another format")
def _():
    status, _, out = ed.post("api/save?format=bmp&quality=0&max=200&edited=0")
    j = json.loads(out)
    assert j["ok"] and j["name"] == "shot.bmp" and (j["width"], j["height"]) == (200, 150), j
    assert bmp_pixel(D + "/pics/shot.bmp", 0, 0) is not None


@test("what cannot be saved is said, and the editor goes on")
def _():
    status, _, out = ed.post("api/save?format=nothing&edited=0")
    j = json.loads(out)
    assert status == 200 and not j["ok"] and j["error"], j
    status, _, _ = ed.post("api/save?format=jpeg&edited=1", b"")                                # an edit without a picture
    assert status == 411
    status, _, out = ed.post("api/save?format=jpeg&edited=1", b"this is not a PNG")
    assert status == 400 and not json.loads(out)["ok"]
    c = http.client.HTTPConnection("127.0.0.1", ed.port, timeout=10)                           # a picture far too big is not even read
    c.putrequest("POST", "/%s/api/save?format=jpeg&edited=1" % ed.token, skip_host=True)
    c.putheader("Host", "127.0.0.1:%d" % ed.port)
    c.putheader("X-Lotus-Edit", "1")
    c.putheader("Content-Length", str(5 * 1024 ** 3))
    c.endheaders()
    assert c.getresponse().status == 413
    c.close()
    assert ed.request("GET", "api/plan?format=png&edited=0")[0] == 200, "still alive"


@test("showing the saved file: only what it saved itself")
def _():
    status, _, out = ed.post("api/reveal")
    assert status == 200 and json.loads(out)["ok"]
    status, _, out = ed.post("api/open")
    assert status == 200 and json.loads(out)["ok"]


@test("the last choice is kept for /img convert too: format|quality|max")
def _():
    with open(D + "/img-last") as f:
        assert f.read().strip() == "bmp|80|200", open(D + "/img-last").read()


@test("a reload (goodbye, then the page again) does not end it; closing the tab does")
def _():
    ed2 = Editor(IMAGE, {"LOTUS_EDIT_GRACE": "1.5"})
    try:
        assert ed2.post("api/ping")[0] == 200
        assert ed2.post("api/bye")[0] == 200
        time.sleep(0.4)
        assert ed2.post("api/ping")[0] == 200                      # the reloaded page
        assert ed2.wait(2.5) is None, "the reload must not end it"
        assert ed2.post("api/bye")[0] == 200                       # the tab was closed
        assert ed2.wait(6) == 0, "it should end by itself"
        assert "Closed – nothing was saved." in ed2.output(), ed2.output()
    finally:
        ed2.kill()


@test("a browser that went away (no sign of it) ends it; a browser that never came ends it too")
def _():
    ed3 = Editor(IMAGE, {"LOTUS_EDIT_IDLE": "1.5"})
    try:
        assert ed3.post("api/ping")[0] == 200
        assert ed3.wait(8) == 0, "no sign of the page for a while"
    finally:
        ed3.kill()
    ed4 = Editor(IMAGE, {"LOTUS_EDIT_FIRST": "1.5"})
    try:
        assert ed4.wait(8) == 0, "no browser came"
    finally:
        ed4.kill()


@test("Cancel / Close: the page says so and it ends; it reports what was saved, and the working folder is gone")
def _():
    status, _, out = ed.post("api/quit")
    assert status == 200 and json.loads(out)["ok"]
    assert ed.wait(8) == 0
    out = ed.output()
    assert "3 pictures saved." in out, out


@test("with an unreadable file it says so and does not open anything")
def _():
    with open(D + "/pics/not.png", "w") as f:
        f.write("not an image\n")
    bad = Editor(D + "/pics/not.png")
    try:
        assert bad.wait(15) == 1 and bad.url is None, bad.output()
        assert "not.png" in bad.output() and "Pictures:" in bad.output()
    finally:
        bad.kill()


@test("a picture that is not there")
def _():
    out = subprocess.run([sys.executable, "-B", EDIT + "/editor.py", D + "/nothing.png", "--no-open"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                         universal_newlines=True, env=ENV).stdout
    assert "There is no picture" in out, out


# ── --drop: /img without a picture – the page sends it ──
def config_of(page):
    return json.loads(re.search(r'<script type="application/json" id="config">(.*?)</script>', page, re.S).group(1))


PICTURE = open(IMAGE, "rb").read()
dr = Editor(None, args=("--drop", "--out-dir", D + "/Dropped"))
assert dr.url, "the editor did not start without a picture: " + dr.output()


@test("--drop: without a picture the page is the drop page – in the language of Lotus, with the folder the pictures go to")
def _():
    out = dr.output()
    assert "Dropped" in out and "Drop a picture on the page" in out and "Picture" not in out, out
    status, h, body = dr.request("GET", "")
    page = body.decode("utf-8")
    assert status == 200 and "default-src 'none'" in h["content-security-policy"] and h["cache-control"] == "no-store"
    assert "<title>Bildeditor – Lotus</title>" in page and 'src="web/drop.js"' in page and '<html lang="de">' in page
    cfg = config_of(page)
    assert cfg["folder"].endswith("Dropped") and "heic" in cfg["pictures"] and "cr3" in cfg["pictures"] and cfg["max"] == 1 << 30, cfg
    assert cfg["strings"]["drop_here"] == "Bild hierher ziehen" and cfg["lang"] == "de"
    status, h, body = dr.request("GET", "web/drop.js")
    assert status == 200 and "javascript" in h["content-type"] and b"api/drop" in body


@test("--drop: before a picture there is no picture to show, to plan, to save or to show in the Finder")
def _():
    assert dr.request("GET", "image")[0] == 404
    assert dr.request("GET", "api/plan?format=png&edited=0")[0] == 409
    assert dr.post("api/save?format=png&edited=0")[0] == 409
    assert dr.post("api/reveal")[0] == 400
    assert ed.proc.poll() is not None and dr.proc.poll() is None


@test("--drop: a picture must come from the page itself, whole and not too big – and only in --drop")
def _():
    assert dr.request("POST", "api/drop?name=a.png", PICTURE)[0] == 403                          # no header of the page
    assert dr.post("api/drop?name=a.png", PICTURE, {"Origin": "http://evil.example"})[0] == 403
    assert dr.post("api/drop?name=a.png", PICTURE, {"Sec-Fetch-Site": "cross-site"})[0] == 403
    assert dr.post("/wrong-secret/api/drop?name=a.png", PICTURE, token=False)[0] == 404
    assert dr.post("api/drop?name=a.png", b"")[0] == 411
    c = http.client.HTTPConnection("127.0.0.1", dr.port, timeout=10)                              # far too big: not even read
    c.putrequest("POST", "/%s/api/drop?name=big.png" % dr.token, skip_host=True)
    c.putheader("Host", "127.0.0.1:%d" % dr.port)
    c.putheader("X-Lotus-Edit", "1")
    c.putheader("Content-Length", str(5 * 1024 ** 3))
    c.endheaders()
    assert c.getresponse().status == 413
    c.close()
    assert dr.request("GET", "image")[0] == 404, "still no picture"
    e2 = Editor(IMAGE)                                                                            # an editor of a picture has no drop
    try:
        assert e2.post("api/drop?name=a.png", PICTURE)[0] == 404 and e2.post("api/another")[0] == 404
        assert e2.post("api/quit")[0] == 200 and e2.wait(8) == 0
    finally:
        e2.kill()


@test("--drop: what is not a picture is said, and the page stays the drop page")
def _():
    status, _, out = dr.post("api/drop?name=notes.txt", b"just some text\n")
    j = json.loads(out)
    assert status == 200 and not j["ok"] and j["error"], j
    assert "<title>Bildeditor – Lotus</title>" in dr.request("GET", "")[2].decode("utf-8")
    assert "notes.txt" in dr.output()
    assert not glob.glob(D + "/data/edit-*/picture/notes.txt"), "its copy is gone"


@test("--drop: a dropped picture is made ready, then the address is the editor with it – named as a file, nothing outside its folder")
def _():
    status, _, out = dr.post("api/drop?name=" + quote("../../Ferien: Tag 1.png") + "&count=3", PICTURE)
    j = json.loads(out)
    assert status == 200 and j["ok"] and j["pic"] == 1 and j["name"] == "Ferien Tag 1.png", j
    status, _, body = dr.request("GET", "")
    page = body.decode("utf-8")
    cfg = config_of(page)
    assert "<title>Ferien Tag 1.png – Lotus</title>" in page and 'src="web/editor.js"' in page
    assert cfg["image"]["name"] == "Ferien Tag 1.png" and cfg["image"]["width"] == 400 and cfg["drop"] is True and cfg["pic"] == 1, cfg
    assert cfg["folder"].endswith("Dropped") and cfg["defaults"]["format"] == "png", cfg
    status, h, img = dr.request("GET", "image?pic=1")
    assert status == 200 and h["content-type"] == "image/png" and img[:8] == b"\x89PNG\r\n\x1a\n"
    out = dr.output()
    assert "Ferien Tag 1.png  400 × 300" in out and "3 pictures – the editor opens the first" in out, out
    assert len(glob.glob(D + "/data/edit-*/picture/Ferien Tag 1.png")) == 1, "the copy is in a working folder of its own"
    assert not glob.glob(D + "/Ferien*") and not glob.glob(D + "/data/Ferien*") and not glob.glob(D + "/data/edit-*/Ferien*")


@test("--drop: one picture at a time – a second drop while one is open is refused, the open one stays")
def _():
    status, _, out = dr.post("api/drop?name=other.png", PICTURE)
    assert status == 409 and json.loads(out)["error"] == "open", out
    assert config_of(dr.request("GET", "")[2].decode("utf-8"))["image"]["name"] == "Ferien Tag 1.png"


@test("--drop: it is saved in the folder given (for /img: Downloads/Lotus); a page of another picture cannot save")
def _():
    status, _, out = dr.post("api/save?format=jpeg&quality=80&max=0&edited=0&pic=1")
    j = json.loads(out)
    assert status == 200 and j["ok"] and j["name"] == "Ferien Tag 1.jpg" and os.path.isfile(D + "/Dropped/Ferien Tag 1.jpg"), j
    status, _, out = dr.post("api/save?format=jpeg&quality=80&max=0&edited=0&pic=2")
    assert status == 409 and not json.loads(out)["ok"], out
    assert dr.post("api/reveal")[0] == 200


@test("--drop: Another picture puts it away – the drop page again, its working folder gone; the next one is number 2")
def _():
    status, _, out = dr.post("api/another")
    assert status == 200 and json.loads(out)["ok"]
    assert "<title>Bildeditor – Lotus</title>" in dr.request("GET", "")[2].decode("utf-8")
    assert dr.request("GET", "image")[0] == 404 and not glob.glob(D + "/data/edit-*/picture/Ferien*")
    assert os.path.isfile(D + "/Dropped/Ferien Tag 1.jpg"), "what was saved stays"
    status, _, out = dr.post("api/drop?name=" + quote("Clipboard 2026-11-12 21.40.00.png"), PICTURE)
    assert json.loads(out)["pic"] == 2, out
    cfg = config_of(dr.request("GET", "")[2].decode("utf-8"))
    assert cfg["pic"] == 2 and cfg["image"]["name"] == "Clipboard 2026-11-12 21.40.00.png", cfg
    crop = png(D + "/crop2.png", 120, 80, lambda x, y: (x, y, 9))
    status, _, out = dr.post("api/save?format=png&quality=0&max=0&edited=1&pic=2", open(crop, "rb").read(), {"Content-Type": "image/png"})
    j = json.loads(out)
    assert j["ok"] and j["name"] == "Clipboard 2026-11-12 21.40.00 edited.png" and (j["width"], j["height"]) == (120, 80), j


@test("--drop: closing it says how many pictures were saved – of every picture – and leaves no working folder")
def _():
    assert dr.post("api/quit")[0] == 200
    assert dr.wait(8) == 0
    assert "2 pictures saved." in dr.output(), dr.output()


@test("a picture and --drop at once is a mistake: it shows how it is used")
def _():
    r = subprocess.run([sys.executable, "-B", EDIT + "/editor.py", IMAGE, "--drop", "--no-open"], stdout=subprocess.PIPE,
                       stderr=subprocess.STDOUT, universal_newlines=True, env=ENV)
    assert r.returncode == 2 and "editor.py --drop" in r.stdout, r.stdout


@test("no working folder is left behind when the editors have ended")
def _():
    left = [f for f in os.listdir(D + "/data") if f.startswith("edit-")]
    assert not left, left

finish()
