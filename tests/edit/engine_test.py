"""The image editor's engine and its session (lib/edit/engine.py, the Session of editor.py) – no network, no browser.
On a Mac the engine is lotus-img (LOTUS_IMG_TOOL, which tests/test-edit.zsh builds), elsewhere ImageMagick.
python3 tests/edit/engine_test.py"""
import ast
import io
import os
import stat
import sys

from kit import EDIT, Skip, bmp_pixel, finish, png, png_size, test, tmpdir, with_exif

import engine as E
import editor as ED

eng = E.find_engine()
if eng is None:
    print("  – no image program here (ImageMagick, or lotus-img on a Mac): skipped")
    sys.exit(0)
print("  (engine: %s)" % eng.kind)
D = tmpdir()
GRAD = lambda x, y: (x % 256, y % 256, 120)


def same(a, b):
    """The same path, whatever the separators (Windows writes a backslash where these tests write a slash)."""
    return os.path.normcase(os.path.normpath(a)) == os.path.normcase(os.path.normpath(b))


@test("the code is written for Python 3.9 (the oldest one a Mac's Command Line Tools bring)")
def _():
    for name in ("editor.py", "engine.py"):
        with open(os.path.join(EDIT, name), encoding="utf-8") as f:
            ast.parse(f.read(), feature_version=(3, 9))


@test("the formats of the editor are the ones of /img convert, in the same order")
def _():
    with open(os.path.join(os.path.dirname(EDIT), "cmd", "img.zsh"), encoding="utf-8") as f:
        text = f.read()
    rows = [l.strip().strip('"') for l in text.split("typeset -ga IMG_FORMATS=(")[1].split("\n)")[0].splitlines() if l.strip().startswith('"')]
    zsh = [(r.split("|")[0], r.split("|")[1], r.split("|")[2], r.split("|")[3], r.split("|")[4] == "1") for r in rows]
    assert zsh == list(E.FORMATS), "%r != %r" % (zsh, E.FORMATS)


@test("the engine can write PNG and JPEG")
def _():
    can = eng.writable()
    assert "png" in can and "jpeg" in can, can


@test("LOTUS_MAGICK names the ImageMagick a shell has tried out – it comes before the one in the PATH")
def _():
    fake = os.path.join(D, "my-magick.exe" if os.name == "nt" else "my-magick")
    with open(fake, "wb") as f:
        f.write(b"x")
    m = E.find_magick(magick=fake)
    assert m.convert_cmd == [fake] and m.identify_cmd == [fake, "identify"] and m.list_cmd == [fake, "-list", "format"], (m.convert_cmd, m.identify_cmd)
    m = E.find_engine({"LOTUS_MAGICK": fake})
    assert m.kind == "magick" and m.convert_cmd == [fake], (m.kind, m.convert_cmd)
    nothing = os.path.join(D, "nothing-here")
    other = E.find_magick(magick=nothing)                  # (a name that is no file is passed over: the PATH is asked)
    assert other is None or other.convert_cmd != [nothing]


@test("a picture becomes a JPEG, smaller when asked, never larger")
def _():
    a = png(D + "/a.png", 400, 300, GRAD)
    r = eng.convert(a, D + "/a.jpg", "jpeg", 80, 200)
    assert r.size_in == (400, 300) and r.size_out == (200, 150), (r.size_in, r.size_out)
    assert r.in_bytes > 0 and r.out_bytes > 0 and os.path.getsize(D + "/a.jpg") == r.out_bytes
    r = eng.convert(a, D + "/b.jpg", "jpeg", 80, 4000)
    assert r.size_out == (400, 300), r.size_out


@test("no half file is left behind")
def _():
    left = [f for f in os.listdir(D) if "lotus-tmp" in f]
    assert not left, left


@test("transparency becomes white in a JPEG, not black")
def _():
    t = png(D + "/t.png", 64, 32, lambda x, y: (0, 0, 255, 0 if x < 8 else 255), alpha=True)
    eng.convert(t, D + "/t.jpg", "jpeg", 90, 0)
    eng.convert(D + "/t.jpg", D + "/t.bmp", "bmp", 0, 0)
    r, g, b = bmp_pixel(D + "/t.bmp", 1, 1)
    assert r + g + b > 700, (r, g, b)
    r, g, b = bmp_pixel(D + "/t.bmp", 40, 10)
    assert b > 200 and r < 90, (r, g, b)


@test("a photo that lies on its side is turned upright")
def _():
    eng.convert(D + "/a.png", D + "/plain.jpg", "jpeg", 95, 0)
    with_exif(D + "/plain.jpg", D + "/side.jpg", 6)
    r = eng.convert(D + "/side.jpg", D + "/up.png", "png", 0, 0)
    assert r.size_in == (300, 400) and r.size_out == (300, 400), (r.size_in, r.size_out)
    assert png_size(D + "/up.png") == (300, 400)


@test("a name with spaces, brackets and a dash in front")
def _():
    os.makedirs(D + "/my photos")
    a = png(D + "/my photos/Fotó (1) -x.png", 40, 30, GRAD)
    r = eng.convert(a, D + "/my photos/out (2).png", "png", 0, 0)
    assert r.size_out == (40, 30)
    cwd = os.getcwd()
    try:
        os.chdir(D)
        png("-dash.png", 20, 10, GRAD)
        assert eng.convert("-dash.png", "dash-out.png", "png", 0, 0).size_out == (20, 10)
    finally:
        os.chdir(cwd)


@test("what is not a picture is said, and nothing is written")
def _():
    with open(D + "/not.png", "w") as f:
        f.write("not an image\n")
    try:
        eng.convert(D + "/not.png", D + "/not-out.jpg", "jpeg", 80, 0)
    except E.EngineError as e:
        assert e.reason
    else:
        raise AssertionError("it should have refused")
    assert not os.path.exists(D + "/not-out.jpg")


@test("a name with a line break cannot be told to the converter")
def _():
    if eng.kind != "imageio":
        raise Skip("only the protocol of lotus-img has lines")
    try:
        eng.convert(D + "/a.png", D + "/x\ny.jpg", "jpeg", 80, 0)
    except E.EngineError:
        pass
    else:
        raise AssertionError("it should have refused")


@test("an icon is square and at most 256")
def _():
    if "ico" not in eng.writable():
        raise Skip("no ICO writer here")
    t = png(D + "/ico-in.png", 64, 32, lambda x, y: (0, 0, 255, 255), alpha=True)
    r = eng.convert(t, D + "/i.ico", "ico", 0, 0)
    assert r.size_out == (64, 64), r.size_out


@test("the camera data of the original goes to the cropped copy (lotus-img)")
def _():
    if eng.kind != "imageio":
        raise Skip("ImageMagick does not copy it yet")
    crop = png(D + "/crop.png", 120, 90, GRAD)
    r = eng.convert(crop, D + "/cropped.jpg", "jpeg", 90, 0, D + "/side.jpg")
    assert r.size_out == (120, 90), "upright: not turned again by the original's orientation, %r" % (r.size_out,)
    with open(D + "/cropped.jpg", "rb") as f:
        assert b"Lotus Test Camera" in f.read()


@test("a picture with hidden faces gets no camera data – the place would tell where it was taken (lotus-img)")
def _():
    if eng.kind != "imageio":
        raise Skip("ImageMagick does not copy camera data at all")
    s = ED.Session(D + "/side.jpg", eng, D + "/data", D + "/blurred", None, D + "/Downloads")
    s.prepare()
    crop = png(D + "/crop2.png", 120, 90, GRAD)
    with_camera = s.save("jpeg", 90, 0, True, crop)
    without = s.save("jpeg", 90, 0, True, crop, camera=False)
    with open(with_camera["path"], "rb") as f:
        assert b"Lotus Test Camera" in f.read(), "as before: a cropped copy has the original's camera data"
    with open(without["path"], "rb") as f:
        assert b"Lotus Test Camera" not in f.read()
    s.forget()


# ── The session of one picture ──
def session(name="a.png", out=None, last=None, **kw):
    s = ED.Session(D + "/" + name, eng, D + "/data", out, last, D + "/Downloads")
    s.prepare()
    return s


@test("a session makes the picture ready for a browser: upright PNG, its size, what the system can write")
def _():
    s = session()
    assert s.size == (400, 300) and s.work_size == (400, 300), (s.size, s.work_size)
    assert png_size(s.work) == (400, 300)
    assert "png" in s.formats and "jpeg" in s.formats
    s.forget()
    assert not os.path.exists(s.work_dir)
    s = session("side.jpg")
    assert s.size == (300, 400) and png_size(s.work) == (300, 400)
    s.forget()


@test("what the Convert tab starts with: the format of the picture, the last quality, all of it")
def _():
    last = D + "/img-last"
    s = session("a.png", last=last)
    assert s.defaults() == {"format": "png", "quality": 85, "max": 0}, s.defaults()
    with open(last, "w") as f:
        f.write("webp|70|1920\n")
    assert s.defaults() == {"format": "png", "quality": 70, "max": 0}, s.defaults()
    s.forget()
    s = session("side.jpg", last=last)
    assert s.defaults()["format"] == "jpeg"
    s.forget()


@test("the new file goes next to the original, never over a file that is there")
def _():
    s = session()
    assert same(s.plan("jpeg", True), D + "/a edited.jpg")
    assert same(s.plan("jpeg", False), D + "/a (2).jpg"), s.plan("jpeg", False)      # a.jpg is there already
    assert same(s.plan("png", False), D + "/a (2).png"), s.plan("png", False)        # a.png is the original
    open(D + "/a edited.jpg", "w").close()
    assert same(s.plan("jpeg", True), D + "/a edited (2).jpg")
    os.remove(D + "/a edited.jpg")
    s.forget()


@test("a save: the cropped picture, in the chosen format, size and quality – and the last choice is remembered")
def _():
    last = D + "/img-last-2"
    s = session("a.png", last=last)
    up = png(D + "/up-crop.png", 200, 100, GRAD)
    item = s.save("jpeg", 80, 100, True, up)
    assert item["name"] == "a edited.jpg" and os.path.isfile(item["path"]), item
    assert (item["width"], item["height"]) == (100, 50), item
    with open(last) as f:
        assert f.read().strip() == "jpeg|80|100", open(last).read()
    item2 = s.save("jpeg", 80, 0, True, up)
    assert item2["name"] == "a edited (2).jpg", item2["name"]
    assert (item2["width"], item2["height"]) == (200, 100)
    assert len(s.saved) == 2
    s.forget()


@test("converting without editing writes the original in the new format")
def _():
    s = session("a.png")
    item = s.save("bmp", 0, 0, False, None)
    assert item["name"] == "a.bmp" and (item["width"], item["height"]) == (400, 300), item
    s.forget()


@test("a format the system cannot write is refused; lossless formats have no quality")
def _():
    s = session("a.png")
    try:
        s.save("nothing", 80, 0, False, None)
    except E.EngineError:
        pass
    else:
        raise AssertionError("it should have refused")
    item = s.save("png", 50, 0, False, None)
    assert os.path.isfile(item["path"])
    s.forget()


@test("a picture from the clipboard goes to the folder that was named – made when it is not there yet")
def _():
    s = session("a.png", out=D + "/clip/Lotus")
    assert same(s.out_dir, D + "/clip/Lotus") and s.note == "", (s.out_dir, s.note)
    item = s.save("png", 0, 0, False, None)
    assert same(os.path.dirname(item["path"]), D + "/clip/Lotus") and os.path.isfile(item["path"])
    s.forget()


@test("a folder that cannot be written to: the new file goes to Downloads/Lotus, and it says so")
def _():
    if hasattr(os, "geteuid") and os.geteuid() == 0:
        raise Skip("root can write everywhere")
    if os.name == "nt":
        raise Skip("Windows does not stop a program from writing into a folder that is marked read-only")
    ro = D + "/readonly"
    os.makedirs(ro)
    png(ro + "/r.png", 20, 20, GRAD)
    os.chmod(ro, stat.S_IRUSR | stat.S_IXUSR)
    try:
        s = ED.Session(ro + "/r.png", eng, D + "/data", None, None, D + "/Downloads")
        assert same(s.out_dir, D + "/Downloads") and s.note == "folder", (s.out_dir, s.note)
        s.forget()
    finally:
        os.chmod(ro, stat.S_IRWXU)


# ── A picture from the drop page (/img without a picture: the browser sends its bytes) ──
@test("a picture from the drop page becomes a copy in a working folder of its own, made ready like a picture of a path")
def _():
    with open(D + "/side.jpg", "rb") as f:
        data = f.read()
    s = ED.Session.dropped("Ferien 1.jpg", io.BytesIO(data).read, len(data), eng, D + "/data", D + "/dropped/Lotus")
    assert s is not None and same(os.path.dirname(s.image), os.path.join(s.work_dir, "picture")), s.image
    s.prepare()
    assert s.size == (300, 400), "upright, as from a path: %r" % (s.size,)
    item = s.save("jpeg", 90, 0, False, None)
    assert same(os.path.dirname(item["path"]), D + "/dropped/Lotus") and item["name"] == "Ferien 1.jpg", item
    if eng.kind == "imageio":
        edited = s.save("jpeg", 90, 0, True, png(D + "/crop3.png", 120, 90, GRAD))
        with open(edited["path"], "rb") as f:
            assert b"Lotus Test Camera" in f.read(), "the camera data of a dropped photo comes along, as from a path"
    s.forget()
    assert not os.path.exists(s.work_dir), "the copy goes with the working folder"


@test("a picture from the drop page that did not arrive whole is none – and nothing is left of it")
def _():
    before = set(os.listdir(D + "/data"))
    s = ED.Session.dropped("half.jpg", io.BytesIO(b"\xff\xd8 only the start").read, 5000, eng, D + "/data", D + "/dropped/Lotus")
    assert s is None and set(os.listdir(D + "/data")) == before


@test("the name a page sends becomes a file name: its last part, nothing a file name should not have, never empty")
def _():
    N = ED.picture_name
    assert N("../../etc/passwd") == "passwd" and N("C:\\Users\\me\\Bild 1.HEIC") == "Bild 1.HEIC"
    assert N("a\tb\nc.png") == "abc.png" and N('wh?at*:"<>|.jpg') == "what.jpg"
    assert N("") == "Picture" and N("...") == "Picture" and N(".hidden.png") == "hidden.png"
    assert N("x" * 300 + ".jpg") == "x" * 100 + ".jpg"
    assert N("Clipboard 2026-11-12 21.40.00.png") == "Clipboard 2026-11-12 21.40.00.png"

finish()
