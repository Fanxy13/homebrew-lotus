"""Image engines of the Lotus image editor – the one thing that differs from system to system.

The editor itself (editor.py and the page in web/) is the same everywhere. It asks an engine for exactly two things:

    engine.writable()                                     which formats the system can write (keys of FORMATS)
    engine.convert(src, dst, key, quality, max_px, meta)  one picture into another file: upright, smaller but never larger,
                                                          transparency white where the format has none; src is read as
                                                          it is (any picture the system reads), dst is written whole
                                                          or not at all. `meta`: a file whose camera data the new
                                                          picture gets (the engines that can do it do it, the others
                                                          leave it out)

There are two engines, both small:

    ImageIO   macOS: lotus-img, the Swift program of Lotus (lib/img/Convert.swift, built once by lib/cmd/img.zsh) – Apple's
              ImageIO, so it reads what Preview reads (HEIC, RAW, WebP, AVIF …). It speaks a line protocol, see below.
    Magick    Linux and Windows: ImageMagick (magick, or convert and identify of version 6), WebP with cwebp when
              ImageMagick cannot write it.

A third system needs a third class with these two methods – nothing else in the editor changes.

The protocol of lotus-img (the one /img convert uses too): jobs on stdin, one per line, tab-separated
    <input> <output> <type identifier> <quality 1–100, 0 = the format's own> <max pixels, 0 = keep> [<meta file>]
and one answer per job on stdout
    done <i> <input bytes> <output bytes> <w>x<h> <new w>x<new h>      or      fail <i> <reason>
"""
import glob
import os
import re
import shutil
import subprocess

# key, label, file extension, type identifier, lossy – the rows of IMG_FORMATS in lib/cmd/img.zsh (tests/test-edit.zsh
# compares the two lists, so that they cannot drift apart)
FORMATS = (
    ("jpeg", "JPEG", "jpg", "public.jpeg", True),
    ("png", "PNG", "png", "public.png", False),
    ("heic", "HEIC", "heic", "public.heic", True),
    ("avif", "AVIF", "avif", "public.avif", True),
    ("webp", "WebP", "webp", "org.webmproject.webp", True),
    ("tiff", "TIFF", "tiff", "public.tiff", False),
    ("gif", "GIF", "gif", "com.compuserve.gif", False),
    ("bmp", "BMP", "bmp", "com.microsoft.bmp", False),
    ("pdf", "PDF", "pdf", "com.adobe.pdf", False),
    ("ico", "ICO", "ico", "com.microsoft.ico", False),
)
BY_KEY = {f[0]: f for f in FORMATS}
# the names ImageMagick knows them by
MAGICK_NAME = {"jpeg": "JPEG", "png": "PNG", "heic": "HEIC", "avif": "AVIF", "webp": "WEBP", "tiff": "TIFF", "gif": "GIF",
               "bmp": "BMP", "pdf": "PDF", "ico": "ICO"}
# the extensions that name a format (jpg and tif are the usual short forms)
EXTENSIONS = {"jpg": "jpeg", "jpe": "jpeg", "jpeg": "jpeg", "tif": "tiff", "tiff": "tiff", "heif": "heic", "heic": "heic",
              "png": "png", "avif": "avif", "webp": "webp", "gif": "gif", "bmp": "bmp", "pdf": "pdf", "ico": "ico"}
UPRIGHT = ("LeftTop", "RightTop", "RightBottom", "LeftBottom")       # the orientations that turn a picture on its side


class EngineError(Exception):
    """A picture could not be read or written: `reason` says why, in a few words."""

    def __init__(self, reason):
        Exception.__init__(self, reason)
        self.reason = reason


class Result(object):
    def __init__(self, in_bytes, out_bytes, size_in, size_out):
        self.in_bytes, self.out_bytes, self.size_in, self.size_out = in_bytes, out_bytes, size_in, size_out


def _size(path):
    try:
        return os.path.getsize(path)
    except OSError:
        return 0


def _plain(path):
    # one job per line, fields apart by a tab: a name with either cannot be told to the program
    if any(c in path for c in "\t\r\n"):
        raise EngineError("a file name with a tab or a line break in it")
    return path


class ImageIO(object):
    """macOS: lotus-img (lib/img/Convert.swift)."""
    kind = "imageio"

    def __init__(self, tool, cwebp=None):
        self.tool = tool
        self.cwebp = cwebp or shutil.which("cwebp")

    def _run(self, args, stdin=None, timeout=900):
        env = dict(os.environ)
        if self.cwebp:
            env["LOTUS_CWEBP"] = self.cwebp
        try:
            return subprocess.run([self.tool] + args, input=stdin, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                  encoding="utf-8", errors="replace", timeout=timeout, env=env)
        except (OSError, subprocess.TimeoutExpired):
            raise EngineError("the converter did not run")

    def writable(self):
        types = set(self._run(["--formats"], timeout=60).stdout.split())
        keys = []
        for key, _label, _ext, tid, _lossy in FORMATS:
            if key == "webp":
                if not (self.cwebp or tid in types):       # ImageIO cannot write WebP: cwebp does
                    continue
            elif tid not in types:
                continue
            keys.append(key)
        return keys

    def convert(self, src, dst, key, quality=0, max_px=0, meta=None):
        tid = BY_KEY[key][3]
        job = "\t".join([_plain(src), _plain(dst), tid, str(int(quality)), str(int(max_px))] + ([_plain(meta)] if meta else []))
        out = self._run(["--jobs", "1"], stdin=job + "\n").stdout
        for line in out.splitlines():
            w = line.split()
            if len(w) >= 6 and w[0] == "done":
                size_in, size_out = w[4].split("x"), w[5].split("x")
                return Result(int(w[2]), int(w[3]), (int(size_in[0]), int(size_in[1])), (int(size_out[0]), int(size_out[1])))
            if w and w[0] == "fail":
                raise EngineError(" ".join(w[2:]) or "it could not be converted")
        raise EngineError("the converter stopped")


class Magick(object):
    """Linux and Windows: ImageMagick 7 (`magick`) or 6 (`convert` and `identify`)."""
    kind = "magick"

    def __init__(self, convert, identify, listing, cwebp=None):
        self.convert_cmd, self.identify_cmd, self.list_cmd = convert, identify, listing
        self.cwebp = cwebp or shutil.which("cwebp")
        self._can = None

    def _run(self, cmd, timeout=300):
        try:
            return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                  encoding="utf-8", errors="replace", timeout=timeout)
        except (OSError, subprocess.TimeoutExpired):
            raise EngineError("ImageMagick did not run")

    def _can_write(self):
        if self._can is None:
            self._can = set()
            for line in self._run(self.list_cmd, 60).stdout.splitlines():
                w = line.split()
                if len(w) >= 3 and re.match(r"^[r-][w-][+-]$", w[2]) and "w" in w[2]:
                    self._can.add(w[0].rstrip("*").upper())
        return self._can

    def writable(self):
        keys = []
        for key, _label, _ext, _tid, _lossy in FORMATS:
            if MAGICK_NAME[key] in self._can_write() or (key == "webp" and self.cwebp):
                keys.append(key)
        return keys

    def size(self, path):
        """The size of a picture as it is seen (a photo that lies on its side counts the other way round)."""
        out = self._run(self.identify_cmd + ["-format", "%w %h %[orientation]", _first(path)], 60).stdout.split()
        if len(out) < 2 or not (out[0].isdigit() and out[1].isdigit()):
            raise EngineError("not a picture this computer can read")
        w, h = int(out[0]), int(out[1])
        return (h, w) if len(out) > 2 and out[2] in UPRIGHT else (w, h)

    def convert(self, src, dst, key, quality=0, max_px=0, meta=None):
        w0, h0 = self.size(src)
        side = max(w0, h0)
        if max_px and max_px < side:
            side = max_px                                    # smaller, never larger
        if key == "ico" and side > 256:
            side = 256
        args = ["-auto-orient"]
        if side:
            args += ["-resize", "%dx%d>" % (side, side)]
        if quality:
            args += ["-quality", str(int(quality))]
        if key in ("jpeg", "bmp"):
            args += ["-background", "white", "-alpha", "remove", "-alpha", "off"]    # no transparency: white
        if key == "ico" and side:
            args += ["-background", "none", "-gravity", "center", "-extent", "%dx%d" % (side, side)]
        limits = ["-limit", "memory", "512MiB", "-limit", "map", "512MiB", "-limit", "disk", "2GiB"]
        tmp = dst + ".lotus-tmp"
        try:
            if key == "webp" and "WEBP" not in self._can_write():
                # no WebP writer in ImageMagick: a PNG first, then cwebp
                if not self.cwebp:
                    raise EngineError("cwebp is needed for WebP")
                ok = self._run(self.convert_cmd + limits + [_first(src)] + args + ["PNG:" + tmp + ".png"]).returncode == 0
                ok = ok and self._run([self.cwebp, "-quiet", "-q", str(int(quality) or 85), tmp + ".png", "-o", tmp]).returncode == 0
            else:
                ok = self._run(self.convert_cmd + limits + [_first(src)] + args + [MAGICK_NAME[key] + ":" + tmp]).returncode == 0
            if not ok or not os.path.isfile(tmp) or os.path.getsize(tmp) == 0:
                raise EngineError("it could not be converted")
            os.replace(tmp, dst)
        except OSError:
            raise EngineError("the new file could not be written")
        finally:
            for f in (tmp, tmp + ".png"):
                try:
                    os.remove(f)
                except OSError:
                    pass
        try:
            size_out = self.size(dst)
        except EngineError:
            size_out = (0, 0)
        return Result(_size(src), _size(dst), (w0, h0), size_out)


def _first(path):
    """The first picture of a file (a GIF has many); a name that starts with a dash is not an option."""
    return ("./" + path if path.startswith("-") else path) + "[0]"


def find_magick(cwebp=None):
    """ImageMagick if this system has it, else None."""
    exe = shutil.which("magick")
    if not exe and os.name == "nt":
        found = sorted(glob.glob(os.path.join(os.environ.get("ProgramFiles", r"C:\Program Files"), "ImageMagick-*", "magick.exe")), reverse=True)
        exe = found[0] if found else None
    if exe:
        return Magick([exe], [exe, "identify"], [exe, "-list", "format"], cwebp)
    if os.name != "nt":                                      # (on Windows convert.exe is a tool for disks)
        conv, ident = shutil.which("convert"), shutil.which("identify")
        if conv and ident:
            return Magick([conv], [ident], [conv, "-list", "format"], cwebp)
    return None


def find_engine(environ=None):
    """The engine of this system. LOTUS_IMG_TOOL: the program lotus-img (macOS); otherwise ImageMagick. None: there is none."""
    env = os.environ if environ is None else environ
    tool = env.get("LOTUS_IMG_TOOL", "")
    if tool and os.access(tool, os.X_OK):
        return ImageIO(tool, env.get("LOTUS_CWEBP") or None)
    return find_magick(env.get("LOTUS_CWEBP") or None)
