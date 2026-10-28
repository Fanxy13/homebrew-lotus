# /img convert: images and folders into other formats – with ImageIO (lib/img/Convert.swift), the originals untouched
source $LOTUS_ROOT/lib/core.zsh
source $LOTUS_ROOT/lib/ui.zsh
lotus_load
source $LOTUS_ROOT/lib/cmd/img.zsh
ui_has_tty() { false }
zf_mkdir -p $HOME/pics/shoot "$HOME/pics/my photos"
# test images: an opaque PNG and one with a transparent corner (written by Python, no other tools)
python3 - $HOME/pics <<'PY'
import struct, sys, zlib
def png(path, w, h, px, alpha):
    raw = b"".join(b"\x00" + b"".join(px(x, y) for x in range(w)) for y in range(h))
    chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    hdr = struct.pack(">IIBBBBB", w, h, 8, 6 if alpha else 2, 0, 0, 0)
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", hdr) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
d = sys.argv[1]
for name in ("a", "b", "c"):
    png(f"{d}/shoot/{name}.png", 400, 300, lambda x, y: bytes((x % 256, y % 256, 120)), False)
png(f"{d}/my photos/logo.png", 64, 32, lambda x, y: bytes((0, 0, 255, 0 if x < 8 else 255)), True)
PY
print -r -- "not an image" >| $HOME/pics/shoot/broken.png

# ── what comes in, where it goes ──
img_collect $HOME/pics/shoot $HOME/pics/my photos/logo.png nothere.png
check_eq "a folder: its images" "${#IMG_IN}" 5
H=${HOME:a}      # the paths as Lotus writes them
check_eq "a path with spaces, not quoted: found" "$IMG_IN[-1]" "$H/pics/my photos/logo.png"
check_eq "a folder's images remember the folder" "$IMG_FROM[1]" "$H/pics/shoot"
check_eq "what is not there is named" "$IMG_MISSING" "nothere.png"
: >| $HOME/pics/my\ photos/logo.jpg
img_plan jpg JPEG
check_eq "a folder: a folder for the format inside it" "$IMG_OUT[1]" "$H/pics/shoot/JPEG/a.jpg"
check_eq "an image on its own: next to it, never over another file" "$IMG_OUT[-1]" "$H/pics/my photos/logo (2).jpg"
rm -f $HOME/pics/my\ photos/logo.jpg

# ── a real conversion, without questions ──
out=$($LOTUS_ROOT/bin/lotus img convert $HOME/pics/shoot "$HOME/pics/my photos/logo.png" --to jpeg --quality 80 --max 200 2>&1 < /dev/null)
check_has "four images converted" "$out" "4 images → JPEG"
check_has "the broken one is named, with why" "$out" "broken.png – not an image this Mac can read"
check "the folder's images in their own folder" test -s $HOME/pics/shoot/JPEG/b.jpg
check "the image on its own next to it" test -s "$HOME/pics/my photos/logo.jpg"
check "the originals are still there" test -s $HOME/pics/shoot/a.png
check_has "smaller, as asked (400 → 200)" "$(sips -g pixelWidth $HOME/pics/shoot/JPEG/a.jpg)" "pixelWidth: 200"
check_has "never larger (64 stays 64)" "$(sips -g pixelWidth "$HOME/pics/my photos/logo.jpg")" "pixelWidth: 64"
check_has "a JPEG is a JPEG" "$(sips -g format $HOME/pics/shoot/JPEG/c.jpg)" "format: jpeg"
# transparency becomes white in a JPEG – not black
px=$(sips -s format bmp "$HOME/pics/my photos/logo.jpg" --out $HOME/px.bmp >/dev/null 2>&1; python3 -c "
import sys; d=open(sys.argv[1],'rb').read(); off=int.from_bytes(d[10:14],'little'); h=int.from_bytes(d[22:26],'little',signed=True)
w=int.from_bytes(d[18:22],'little'); row=(w*3+3)//4*4; y=(h-1) if h>0 else 0; print(d[off+y*row]+d[off+y*row+1]+d[off+y*row+2])" $HOME/px.bmp)
check "a transparent corner turns white in JPEG" test ${px:-0} -gt 700
check_has "the last choice is remembered" "$(<$LOTUS_STATE/img-last)" "jpeg|80|200"

# an icon: square, at most 256
out=$($LOTUS_ROOT/bin/lotus img convert "$HOME/pics/my photos/logo.png" --to ico 2>&1 < /dev/null)
check_has "ICO: made" "$out" "1 image → ICO"
check_has "ICO: square" "$(sips -g pixelHeight "$HOME/pics/my photos/logo.ico")" "pixelHeight: 64"

# WebP through cwebp, when it is there
if (( $+commands[cwebp] )); then
  out=$($LOTUS_ROOT/bin/lotus img convert $HOME/pics/shoot/a.png --to webp 2>&1 < /dev/null)
  check_has "WebP: made" "$out" "1 image → WebP"
  check_eq "WebP: a WebP file" "$(head -c 12 $HOME/pics/shoot/a.webp | tail -c 4)" "WEBP"
fi

# ── what is wrong is said ──
out=$($LOTUS_ROOT/bin/lotus img convert $HOME/pics/shoot/a.png --to xyz 2>&1 < /dev/null)
check_has "an unknown format" "$out" "Unknown format: xyz"
out=$($LOTUS_ROOT/bin/lotus img convert $HOME/pics/shoot/a.png --to jpeg --quality 300 2>&1 < /dev/null)
check_has "a quality out of range" "$out" "a number from 1 to 100"
out=$($LOTUS_ROOT/bin/lotus img convert $HOME/pics/shoot/a.png 2>&1 < /dev/null)
check_has "without a keyboard and without --to: asks for it" "$out" "Into which format?"
out=$($LOTUS_ROOT/bin/lotus img convert $HOME/nothing 2>&1 < /dev/null)
check_has "nothing to convert" "$out" "No images to convert"
check_has "/img formats lists what this Mac writes" "$($LOTUS_ROOT/bin/lotus img formats 2>&1 < /dev/null | sed "s/\x1b\[[0-9;]*m//g")" "✓ HEIC"
