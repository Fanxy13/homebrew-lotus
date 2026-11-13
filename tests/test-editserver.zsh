# The image editor's server (lib/edit/editor.py) over HTTP, as a browser meets it – and the command that starts it (/img edit).
# Like the Live Server's tests it talks to 127.0.0.1, which a CI Mac does not let it do (the workflow leaves this file out there; it
# runs on a real Mac and in the Linux containers). With Playwright and a browser at hand it drives the page too.
source $LOTUS_ROOT/lib/core.zsh
source $LOTUS_ROOT/lib/ui.zsh
lotus_load
source $LOTUS_ROOT/lib/cmd/img.zsh
ui_has_tty() { false }
lotus() { $LOTUS_ROOT/bin/lotus "$@" }
plain() { sed $'s/\e\\[[0-9;?]*[a-zA-Z]//g' | tr -d '\r' }
suite() {   # <what> <command…> – a test program whose ✓ and ✗ lines are checks of this file
  local what=$1 out; shift
  local -i rc
  out=$("$@" 2>&1); rc=$?
  print -r -- "$out"
  local -a lines=(${(f)out})
  (( PASSED += ${#${(@M)lines:#*✓*}} ))
  (( FAILED += ${#${(@M)lines:#*✗*}} ))
  (( rc == 0 )) || { (( FAILED++ )); print -r -- "  ✗ $what: exit status $rc" }
}
if (( ! $+commands[python3] )); then print -r -- "  – no python3: skipped"; return 0; fi
if [[ $LOTUS_OS == macos ]]; then
  img_tool || lotus_swift_build lotus-img $LOTUS_ROOT/lib/img/Convert.swift > /dev/null 2>&1
  img_tool && export LOTUS_IMG_TOOL=$REPLY || { print -r -- "  – the converter could not be built here: skipped"; return 0 }
elif ! (( $+commands[magick] || ($+commands[convert] && $+commands[identify]) )); then
  print -r -- "  – the editor needs ImageMagick here: skipped"; return 0
fi

# ── the server, asked over HTTP ──
suite "server" python3 -B $LOTUS_ROOT/tests/edit/server_test.py

# ── the command: /img edit <picture> starts it, says where, and a quit from the page ends it ──
zf_mkdir -p $HOME/pics
python3 - $HOME/pics/shot.png <<'PY'
import struct, sys, zlib
w, h = 320, 240
raw = b"".join(b"\x00" + b"".join(bytes((x % 256, y % 256, 90)) for x in range(w)) for y in range(h))
chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
open(sys.argv[1], "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
PY
export LOTUS_EDIT_NO_OPEN=1 LOTUS_EDIT_NO_SHOW=1
(lotus img edit $HOME/pics/shot.png >| $HOME/edit.log 2>&1 &)
url=
for i in {1..100}; do
  url=$(plain < $HOME/edit.log | grep -o 'http://127.0.0.1:[0-9]*/[A-Za-z0-9_-]*/' | head -1)
  [[ -n $url ]] && break
  sleep 0.1
done
check "the command starts the editor and says its address" test -n "$url"
out=$(plain < $HOME/edit.log)
check_has "with a header of Lotus" "$out" "lotus / Image editor"
check_has "the picture and its size" "$out" "shot.png  320 × 240"
if [[ -n $url ]]; then
  check_eq "the page is served" "$(curl -s -m 5 -o /dev/null -w '%{http_code}' $url)" 200
  check_has "in the language of Lotus" "$(curl -s -m 5 $url)" "<html lang=\"$LOTUS_LANG\">"
  check_eq "a request that is not the page's own is refused" "$(curl -s -m 5 -o /dev/null -w '%{http_code}' -X POST ${url}api/quit)" 403
  curl -s -m 5 -X POST -H 'X-Lotus-Edit: 1' ${url}api/quit > /dev/null
  for i in {1..60}; do pgrep -f "lib/edit/editor.py $HOME/pics/shot.png" > /dev/null || break; sleep 0.1; done
  check "closing the page ends the editor" eval '! pgrep -f "lib/edit/editor.py $HOME/pics/shot.png"'
  check_has "and says that nothing was saved" "$(plain < $HOME/edit.log)" "Closed – nothing was saved."
else
  pkill -f "lib/edit/editor.py $HOME/pics/shot.png" 2>/dev/null
fi

# ── the command without a picture: /img starts it on its drop page, in the browser – not a drop zone in the terminal ──
( ui_has_tty() { true }; img_edit >| $HOME/drop.log 2>&1 < /dev/null & )
url=
for i in {1..100}; do
  url=$(plain < $HOME/drop.log | grep -o 'http://127.0.0.1:[0-9]*/[A-Za-z0-9_-]*/' | head -1)
  [[ -n $url ]] && break
  sleep 0.1
done
check "/img without a picture starts the editor and says its address" test -n "$url"
out=$(plain < $HOME/drop.log)
check_has "it asks for the picture on the page" "$out" "Drop a picture on the page"
check_has "and says where the pictures go: Downloads/Lotus" "$out" "Downloads/Lotus"
check "no drop zone in the terminal" eval '[[ $out != *"Drag a picture into this window"* && $out != *"Drop a picture here"* ]]'
if [[ -n $url ]]; then
  check_has "the page is the drop page" "$(curl -s -m 5 $url)" 'src="web/drop.js"'
  curl -s -m 5 -X POST -H 'X-Lotus-Edit: 1' ${url}api/quit > /dev/null
  for i in {1..60}; do pgrep -f "lib/edit/editor.py --drop" > /dev/null || break; sleep 0.1; done
  check "closing the page ends it" eval '! pgrep -f "lib/edit/editor.py --drop"'
  check_has "and it says that nothing was saved" "$(plain < $HOME/drop.log)" "Closed – nothing was saved."
else
  pkill -f "lib/edit/editor.py --drop" 2>/dev/null
fi

# ── the page in a browser, when there is one to drive ──
if (( $+commands[node] )) && node -e "require('playwright')" 2>/dev/null; then
  suite "page in a browser" node $LOTUS_ROOT/tests/edit/ui.test.js
else
  print -r -- "  · no Playwright for Node here: the page is not driven (node tests/edit/ui.test.js does it where there is)"
fi
