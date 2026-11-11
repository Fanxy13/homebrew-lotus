"""What the image editor's Python tests share: a few test pictures made without any program (so they work wherever Python
does), a small runner that prints "  ✓ what" / "  ✗ what" like Lotus' other tests, and the path to lib/edit."""
import os
import struct
import sys
import tempfile
import traceback
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
EDIT = os.path.join(ROOT, "lib", "edit")
sys.path.insert(0, EDIT)

PASSED, FAILED, SKIPPED = [0], [0], [0]


def test(what):
    """@test("what it does") – runs the function now; an exception or a failed assert is a ✗."""
    def run(fn):
        try:
            fn()
            PASSED[0] += 1
            print("  ✓ " + what, flush=True)
        except Skip as s:
            SKIPPED[0] += 1
            print("  · skipped: %s (%s)" % (what, s), flush=True)
        except Exception:
            FAILED[0] += 1
            print("  ✗ " + what + "\n      " + traceback.format_exc().strip().replace("\n", "\n      "), flush=True)
        return fn
    return run


class Skip(Exception):
    pass


def finish():
    print("\n%d passed, %d failed%s" % (PASSED[0], FAILED[0], ", %d skipped" % SKIPPED[0] if SKIPPED[0] else ""), flush=True)
    sys.exit(1 if FAILED[0] else 0)


def tmpdir():
    return tempfile.mkdtemp(prefix="lotus-edit-test.")


def png(path, w, h, px, alpha=False):
    """A PNG: px(x, y) → a tuple of 3 (or 4 with alpha) bytes."""
    raw = b"".join(b"\x00" + b"".join(bytes(px(x, y)) for x in range(w)) for y in range(h))
    chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    hdr = struct.pack(">IIBBBBB", w, h, 8, 6 if alpha else 2, 0, 0, 0)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", hdr) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
    return path


def png_size(path):
    with open(path, "rb") as f:
        d = f.read(24)
    return struct.unpack(">II", d[16:24])


def with_exif(src_jpeg, dst, orientation=6, make="Lotus Test Camera"):
    """The JPEG with an Exif block in front: the camera's make and how it was held (6: the picture lies on its side)."""
    s = make.encode() + b"\x00"
    ifd_at, entries = 8, 2
    data_at = ifd_at + 2 + entries * 12 + 4
    ifd = struct.pack("<H", entries)
    ifd += struct.pack("<HHII", 0x010F, 2, len(s), data_at)                  # Make
    ifd += struct.pack("<HHIHH", 0x0112, 3, 1, orientation, 0)               # Orientation
    ifd += struct.pack("<I", 0)
    tiff = b"II*\x00" + struct.pack("<I", ifd_at) + ifd + s
    app1 = b"Exif\x00\x00" + tiff
    with open(src_jpeg, "rb") as f:
        jpeg = f.read()
    assert jpeg[:2] == b"\xff\xd8"
    with open(dst, "wb") as f:
        f.write(jpeg[:2] + b"\xff\xe1" + struct.pack(">H", len(app1) + 2) + app1 + jpeg[2:])
    return dst


def bmp_pixel(path, x, y):
    """(r, g, b) of a pixel of an uncompressed 24-bit BMP (the way the tests look into a picture)."""
    with open(path, "rb") as f:
        d = f.read()
    off, w = struct.unpack("<I", d[10:14])[0], struct.unpack("<i", d[18:22])[0]
    h, bpp = struct.unpack("<i", d[22:26])[0], struct.unpack("<H", d[28:30])[0]
    assert bpp == 24, "a 24-bit BMP, not %d" % bpp
    row = (w * 3 + 3) // 4 * 4
    yy = (h - 1 - y) if h > 0 else y
    b, g, r = d[off + yy * row + x * 3: off + yy * row + x * 3 + 3]
    return r, g, b
