"""Reading photos and writing the transparent PNG.

Reading: everything Pillow knows (PNG, JPEG, WebP, TIFF, BMP, GIF …). HEIC, HEIF and AVIF go through
macOS' own `sips` first – a local conversion into the session folder, the original is only read. On Windows
Pillow tries them first, then Windows' own imaging component (WIC, the decoders Photos uses).
Writing: a new file next to nothing else – photo_no_bg.png, photo_no_bg_2.png, … – written to a
temporary name and moved into place, so there is never a half-written PNG and never an overwrite.
"""
import base64
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageOps, UnidentifiedImageError

from events import BgError, log

Image.MAX_IMAGE_PIXELS = 300_000_000
EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp", ".heic", ".heif", ".avif", ".tif", ".tiff", ".bmp", ".gif"}
NATIVE = {".heic", ".heif", ".avif"}
FIRST = NATIVE if sys.platform == "darwin" else set()    # converted by the system before Pillow tries them


def _sips(path, session):
    """Converts with macOS' own image tools (argument list, no shell)."""
    os.makedirs(session, exist_ok=True)
    out = os.path.join(session, "converted-%d.png" % (abs(hash(path)) % 10**8))
    r = subprocess.run(["/usr/bin/sips", "-s", "format", "png", path, "--out", out],
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=120)
    if r.returncode != 0 or not os.path.isfile(out):
        raise BgError("BG-005", "macOS could not read this image.", r.stderr.decode(errors="replace").strip())
    return out


# Windows PowerShell (always there) decodes with WIC and writes a PNG – the paths reach it through the
# environment, never inside the command.
_WIC = r"""
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationCore
$in = [IO.File]::OpenRead($env:LOTUS_WIC_IN)
try {
  $d = [Windows.Media.Imaging.BitmapDecoder]::Create($in, 'PreservePixelFormat', 'OnLoad')
  $e = New-Object Windows.Media.Imaging.PngBitmapEncoder
  $e.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($d.Frames[0]))
  $out = [IO.File]::Create($env:LOTUS_WIC_OUT)
  try { $e.Save($out) } finally { $out.Close() }
} finally { $in.Close() }
"""


def _wic(path, session):
    """Converts with Windows' own imaging component (HEIC needs the HEIF and HEVC extensions of the Store)."""
    os.makedirs(session, exist_ok=True)
    out = os.path.join(session, "converted-%d.png" % (abs(hash(path)) % 10**8))
    ps = os.path.join(os.environ.get("SystemRoot", r"C:\Windows"), "System32", "WindowsPowerShell", "v1.0", "powershell.exe")
    env = dict(os.environ, LOTUS_WIC_IN=os.path.abspath(path), LOTUS_WIC_OUT=out)
    code = base64.b64encode(_WIC.encode("utf-16-le")).decode("ascii")
    try:
        r = subprocess.run([ps, "-NoProfile", "-NonInteractive", "-EncodedCommand", code], env=env,
                           stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=120)
    except (OSError, subprocess.SubprocessError) as e:
        raise BgError("BG-005", "Windows could not read this image.", str(e))
    if r.returncode != 0 or not os.path.isfile(out):
        raise BgError("BG-005", "Windows could not read this image.", r.stderr.decode(errors="replace").strip()[-400:])
    return out


def _convert(path, session):
    """The system's own image tools for what Pillow cannot read: sips on macOS, WIC on Windows."""
    if sys.platform == "darwin":
        return _sips(path, session)
    if os.name == "nt":
        return _wic(path, session)
    raise BgError("BG-005", "This system has no tool for this image format.", path)


def load(path, session):
    """→ rgb (uint8 H×W×3, upright), its own alpha or None, ICC profile or None"""
    if not os.path.isfile(path):
        raise BgError("BG-005", "The file is not there (any more).", path)
    ext = os.path.splitext(path)[1].lower()
    source = path
    try:
        if ext in FIRST:
            source = _convert(path, session)
        im = Image.open(source)
        im.load()
    except BgError:
        raise
    except Image.DecompressionBombError as e:
        raise BgError("BG-005", "This image is too large (more than 300 megapixels).", str(e))
    except (UnidentifiedImageError, OSError, SyntaxError, ValueError) as e:
        if source == path and ext not in {".png", ".jpg", ".jpeg"}:
            try:
                im = Image.open(_convert(path, session))
                im.load()
            except BgError:
                raise BgError("BG-005", "This is not an image Lotus can read.", str(e))
        else:
            raise BgError("BG-005", "This is not an image Lotus can read.", str(e))
    if getattr(im, "n_frames", 1) > 1:
        log("info", "Animated image: only the first frame is used")
    icc = im.info.get("icc_profile")
    im = ImageOps.exif_transpose(im)
    alpha = None
    if im.mode in ("RGBA", "LA", "PA") or (im.mode == "P" and "transparency" in im.info):
        rgba = im.convert("RGBA")
        alpha = np.asarray(rgba.getchannel("A"))
        rgb = np.asarray(rgba.convert("RGB"))
        if alpha.min() == 255:
            alpha = None
    else:
        rgb = np.asarray(im.convert("RGB"))
    return np.ascontiguousarray(rgb), alpha, icc


def output_path(folder, source):
    """photo.jpg → folder/photo_no_bg.png, or _2, _3 … – the name is reserved right away."""
    stem = os.path.splitext(os.path.basename(source))[0]
    if not os.path.isdir(folder):
        try:
            os.makedirs(folder, exist_ok=True)
        except OSError as e:
            raise BgError("BG-006", "The output folder cannot be created.", f"{folder}: {e.strerror}")
    if not os.access(folder, os.W_OK):
        raise BgError("BG-006", "Lotus cannot write into the output folder.", folder)
    for n in range(1, 10000):
        name = f"{stem}_no_bg.png" if n == 1 else f"{stem}_no_bg_{n}.png"
        path = os.path.join(folder, name)
        try:
            fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
            os.close(fd)
            return path
        except FileExistsError:
            continue
        except OSError as e:
            raise BgError("BG-006", "Lotus cannot write into the output folder.", f"{folder}: {e.strerror}")
    raise BgError("BG-006", "Too many files with this name in the output folder.", folder)


def save_png(path, rgb, alpha, icc=None):
    """RGBA PNG, written next to the target and then moved over the (reserved or own) file."""
    a8 = (np.clip(alpha, 0, 1) * 255 + 0.5).astype(np.uint8)
    img = Image.fromarray(np.dstack([rgb, a8]), "RGBA")
    tmp = os.path.join(os.path.dirname(path), f".{os.path.basename(path)}.lotus-tmp")
    try:
        kwargs = {"compress_level": 6}
        if icc:
            kwargs["icc_profile"] = icc
        img.save(tmp, "PNG", **kwargs)
        os.replace(tmp, path)
    except OSError as e:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise BgError("BG-006", "The PNG could not be written.", f"{path}: {e.strerror or e}")


def save_gray(path, values, bits=8):
    """Small helper for the editor and the session cache (alpha maps)."""
    if bits == 16:
        Image.fromarray((np.clip(values, 0, 1) * 65535 + 0.5).astype(np.uint16)).save(path, "PNG", compress_level=1)
    else:
        Image.fromarray((np.clip(values, 0, 1) * 255 + 0.5).astype(np.uint8), "L").save(path, "PNG", compress_level=1)


def load_gray(path):
    im = Image.open(path)
    arr = np.asarray(im)
    if arr.dtype == np.uint16 or im.mode.startswith("I"):
        return arr.astype(np.float32) / 65535.0
    if arr.ndim == 3:
        arr = arr[..., 0]
    return arr.astype(np.float32) / 255.0
