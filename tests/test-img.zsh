# /img convert: images and folders into other formats – with ImageIO (lib/img/Convert.swift), the originals untouched
source $LOTUS_ROOT/lib/core.zsh
source $LOTUS_ROOT/lib/ui.zsh
lotus_load
source $LOTUS_ROOT/lib/cmd/img.zsh
ui_has_tty() { false }
# what the converted files look like: sips on a Mac, the image info of the platform layer elsewhere
imgw() { if (( $+commands[sips] )); then sips -g pixelWidth "$1" | awk '/pixelWidth/ { print $2 }'; else lotus_os_image_info "$1"; print -r -- ${REPLY%x*}; fi }
imgh() { if (( $+commands[sips] )); then sips -g pixelHeight "$1" | awk '/pixelHeight/ { print $2 }'; else lotus_os_image_info "$1"; print -r -- ${REPLY#*x}; fi }
imgkind() { if (( $+commands[sips] )); then sips -g format "$1" | awk '/format:/ { print $2 }'; else _lotus_os_image_kind "$1"; print -r -- $REPLY; fi }
tobmp() {   # <image> <out.bmp>
  if (( $+commands[sips] )); then sips -s format bmp "$1" --out "$2" >/dev/null 2>&1
  else magick "$1" BMP3:"$2" >/dev/null 2>&1 || convert "$1" BMP3:"$2" >/dev/null 2>&1; fi
}
# Linux: the converter is ImageMagick
if [[ $LOTUS_OS != macos ]] && ! (( $+commands[magick] || $+commands[convert] )); then
  print -r -- "  - the converter needs ImageMagick here – skipped"
  return 0
fi
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
check_has "the broken one is named, with why" "$out" "broken.png – not an image $LOTUS_THIS can read"
check "the folder's images in their own folder" test -s $HOME/pics/shoot/JPEG/b.jpg
check "the image on its own next to it" test -s "$HOME/pics/my photos/logo.jpg"
check "the originals are still there" test -s $HOME/pics/shoot/a.png
check_eq "smaller, as asked (400 → 200)" "$(imgw $HOME/pics/shoot/JPEG/a.jpg)" 200
check_eq "never larger (64 stays 64)" "$(imgw "$HOME/pics/my photos/logo.jpg")" 64
check_eq "a JPEG is a JPEG" "$(imgkind $HOME/pics/shoot/JPEG/c.jpg)" jpeg
# transparency becomes white in a JPEG – not black
px=$(tobmp "$HOME/pics/my photos/logo.jpg" $HOME/px.bmp; python3 -c "
import sys; d=open(sys.argv[1],'rb').read(); off=int.from_bytes(d[10:14],'little'); h=int.from_bytes(d[22:26],'little',signed=True)
w=int.from_bytes(d[18:22],'little'); row=(w*3+3)//4*4; y=(h-1) if h>0 else 0; print(d[off+y*row]+d[off+y*row+1]+d[off+y*row+2])" $HOME/px.bmp)
check "a transparent corner turns white in JPEG" test ${px:-0} -gt 700
check_has "the last choice is remembered" "$(<$LOTUS_STATE/img-last)" "jpeg|80|200"

# an icon: square, at most 256
out=$($LOTUS_ROOT/bin/lotus img convert "$HOME/pics/my photos/logo.png" --to ico 2>&1 < /dev/null)
check_has "ICO: made" "$out" "1 image → ICO"
check_eq "ICO: square" "$(imgw "$HOME/pics/my photos/logo.ico")x$(imgh "$HOME/pics/my photos/logo.ico")" "64x64"

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
[[ $LOTUS_OS == macos ]] && want_fmt="✓ HEIC" || want_fmt="✓ PNG"       # a Mac writes HEIC; ImageMagick may not
check_has "/img formats lists what $LOTUS_THIS writes" "$($LOTUS_ROOT/bin/lotus img formats 2>&1 < /dev/null | sed "s/\x1b\[[0-9;]*m//g")" "$want_fmt"
