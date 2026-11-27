# /icons: the icons of the folders on your Desktop – one, a few or all of them (lib/cmd/icons.zsh, the folder icon functions of
# lib/platform/macos.zsh and linux.zsh, lib/icons/seticon.js). No network. Every test runs in an empty home.
#   · the registries and the platform contract
#   · what it finds on a Desktop and how it reads what is dropped
#   · each system's part – macOS with a stand-in for osascript (and the JavaScript itself under Node), Linux with real files
#     (.directory) and a stand-in for gio – and the real thing where this machine can do it
#   · the commands without questions, and the guided one in a pseudo terminal (tests/icons/flow.py waits for each question)
source $LOTUS_ROOT/lib/core.zsh
source $LOTUS_ROOT/lib/ui.zsh
lotus_load
source $LOTUS_ROOT/lib/cmd/icons.zsh
ui_has_tty() { false }
lotus() { $LOTUS_ROOT/bin/lotus "$@" }
plain() { sed $'s/\e\\[[0-9;?]*[a-zA-Z]//g' | tr -d '\r' }

# a test program: its ✓ and ✗ lines are checks of this file
suite() {   # <what> <command…>
  local what=$1 out; shift
  local -i rc
  out=$("$@" 2>&1); rc=$?
  print -r -- "$out"
  local -a lines=(${(f)out})
  (( PASSED += ${#${(@M)lines:#*✓*}} ))
  (( FAILED += ${#${(@M)lines:#*✗*}} ))
  (( rc == 0 )) || { (( FAILED++ )); print -r -- "  ✗ $what: exit status $rc" }
}

mkpng() {   # <file> [r g b] – a 32 × 32 PNG, with Python's standard library
  python3 - "$1" ${2:-200} ${3:-60} ${4:-60} <<'PY'
import struct, sys, zlib
path, r, g, b = sys.argv[1], *map(int, sys.argv[2:5])
raw = b"".join(b"\x00" + bytes((r, g, b)) * 32 for _ in range(32))
chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 32, 32, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
PY
}
# does the folder have a picture of its own – looked at in the file, not through the code that is tested
if [[ $LOTUS_OS == macos ]]; then has_icon() { [[ -e $1/Icon$'\r' ]] }
else has_icon() { [[ -r $1/.directory ]] && grep -q '^Icon=' $1/.directory }; fi

# ── the registries ──
check "/icons is in the table of commands (category Desktop)" grep -q $'^Desktop\t/icons\ticons\t/icons\t' $LOTUS_ROOT/data/commands.tsv
rows_there() { local w; for w in "$@"; do grep -q "^Desktop"$'\t'"-"$'\t'"icons $w"$'\t' $LOTUS_ROOT/data/commands.tsv || return 1; done }
check "and so are set, reset, list and check" rows_there set reset list check
check "every row of the table has seven columns" eval '! awk -F"\t" "!/^#/ && NF != 7 { bad = 1 } END { exit !bad }" $LOTUS_ROOT/data/commands.tsv'
check "bin/lotus knows icons, and icon as a short name" grep -q 'icons icons  icon icons' $LOTUS_ROOT/bin/lotus
lotus_features
check_eq "icons belongs to the core feature – it cannot be switched off by a feature that is off" "${LOTUS_FEATURE_OF[icons]}:${LOTUS_FEATURE_OF[icon]}" "core:core"
for os in macos linux; do
  missing=$( ( source $LOTUS_ROOT/lib/platform/$os.zsh; for f in $LOTUS_OS_CONTRACT; do (( $+functions[$f] )) || print -n "$f "; done ) )
  check_eq "the $os platform file has every function of the contract (the folder icon ones too)" "$missing" ""
done
check "the folder icon functions are in the contract" eval '(( ${LOTUS_OS_CONTRACT[(Ie)lotus_os_folder_icon_set]} && ${LOTUS_OS_CONTRACT[(Ie)lotus_os_desktop]} ))'
check "the install hints know gio and gvfs" eval "grep -q '^gio'\$'\\t' \$LOTUS_ROOT/data/packages.tsv && grep -q '^gvfs'\$'\\t' \$LOTUS_ROOT/data/packages.tsv"

# ── the Desktop of the test ──
D=$HOME/Desktop
zf_mkdir -p $D/Projects $D/Photos "$D/My Games" $D/.hidden $D/Tool.app $D/Notes.rtfd $HOME/Pictures "$HOME/Elsewhere/Deep Folder" $HOME/Elsewhere/Other
print -r -- "a file" >| $D/notes.txt
print -r -- x >| $D/Projects/one; print -r -- x >| $D/Projects/two
ln -s $D/Projects $D/Link
mkpng $HOME/Pictures/red.png 200 60 60
mkpng "$HOME/Pictures/my red.png" 200 60 60
mkpng $HOME/Pictures/green.png 60 200 60
print -r -- "not a picture" >| $HOME/Pictures/notes.txt
: >| $HOME/Pictures/empty.png
H=${HOME:a}

# ── what it finds on a Desktop ──
icons_desktop_folders
check_eq "the folders on the Desktop: no hidden one, no package, no link, no file – by name, upper and lower case alike" "${(j:|:)${(@)reply:t}}" "My Games|Photos|Projects"
zf_mkdir -p $D/apple $D/Banana $D/cherry
icons_desktop_folders
check_eq "…sorted without regard to case" "${(j:|:)${(@)reply:t}}" "apple|Banana|cherry|My Games|Photos|Projects"
rmdir $D/apple $D/Banana $D/cherry
icons_folder_note $D/Projects; check_eq "a folder says what it holds" "$REPLY" "2 items"
icons_folder_note $D/Photos;   check_eq "an empty one says so" "$REPLY" "empty"
print -r -- x >| "$D/Photos/Icon"$'\r'
icons_folder_note $D/Photos;   check_eq "the hidden file Icon of a Mac is not one of the folder's items" "${REPLY%% · *}" "empty"
[[ $LOTUS_OS == macos ]] && check_has "…on a Mac it is the folder's picture, and the note says so" "$REPLY" "empty · has a picture of its own"
rm -f "$D/Photos/Icon"$'\r'

# ── how it reads what is dropped or typed ──
icons_paths $D Projects "My" "Games" nowhere $HOME/Elsewhere/Other
check_eq "a bare name is a folder of the Desktop; a name with a space that was not quoted is put together again" "${(j:|:)${(@)reply/#$H/~}}" "~/Desktop/Projects|~/Desktop/My Games|~/Elsewhere/Other"
check_eq "what is not there is named" "$ICONS_MISSING" "nowhere"
icons_paths "" "$HOME/Elsewhere/Deep\\ Folder"
check_eq "a path with a backslash is not looked for as it is" "${#reply}" "0"
typed="$HOME/Elsewhere/Deep\\ Folder $HOME/Elsewhere/Other"
icons_paths "" ${(Q)${(z)typed}}
check_eq "what a window types for a dragged folder (a space with a backslash) is read like the shell reads it" "${(j:|:)${(@)reply/#$H/~}}" "~/Elsewhere/Deep Folder|~/Elsewhere/Other"
icons_paths "" "file://$H/Elsewhere/Deep%20Folder"
check_eq "a file:// address works too" "${reply/#$H/~}" "~/Elsewhere/Deep Folder"
icons_paths "" "~/Elsewhere/Other"
check_eq "~ is the home folder" "${reply/#$H/~}" "~/Elsewhere/Other"
icons_folders_from Projects Projects "$HOME/Pictures/red.png" nowhere
check_eq "folders: each once, a file is not a folder, what is not there is named" "${(j:|:)${(@)ICONS_FOLDERS/#$H/~}} / ${(j:|:)${(@)ICONS_NOTDIR:t}} / ${(j:|:)ICONS_MISSING}" "~/Desktop/Projects / red.png / nowhere"

icons_picture_ok $HOME/Pictures/red.png; check_eq "a PNG can be an icon" "$?" "0"
icons_picture_ok $HOME/Pictures/notes.txt; check_has "a text file cannot" "$ICONS_WHY" "not a picture file"
icons_picture_ok $HOME/Pictures/empty.png; check_has "an empty file cannot" "$ICONS_WHY" "empty"
icons_picture_ok $HOME/Pictures; check_has "a folder cannot" "$ICONS_WHY" "a picture is a file"
icons_picture_ok $HOME/Pictures/nope.png; check_has "a picture that is not there cannot" "$ICONS_WHY" "not there"
mkpng $HOME/Pictures/UPPER.PNG; icons_picture_ok $HOME/Pictures/UPPER.PNG; check_eq "…an upper case ending is fine" "$?" "0"

wrapped=("${(@f)$(icons_wrap "    " "one two three four five six seven eight nine ten" | plain)}")
check_eq "the wrap helper puts a short text on one line, with its indent" "${#wrapped}:${wrapped[1]}" "1:    one two three four five six seven eight nine ten"
wrapped=("${(@f)$(COLUMNS=40 icons_wrap "    " "one two three four five six seven eight nine ten" | plain)}")
longest=0; for line in $wrapped; do (( ${#line} > longest )) && longest=${#line}; done
check "…and breaks a long one into lines that fit the window, each with the indent" eval '(( ${#wrapped} > 1 && longest <= 38 )) && (( ${#${(@M)wrapped:#    *}} == ${#wrapped} ))'

# ── the help and the check ──
out=$(lotus icons help 2>&1 | plain)
check_has "the help says what it needs" "$out" "WHAT IT NEEDS"
check_has "…and how to use it" "$out" "/icons set <picture> <folders>"
check_has "…and that nothing inside a folder is changed" "$out" "What is inside your folders stays as it is"
check_has "/icons without a keyboard is the help" "$(lotus icons 2>&1 < /dev/null | plain)" "/icons reset"
check_has "icon is the same command" "$(lotus icon help 2>&1 | plain)" "WHAT IT NEEDS"
out=$(lotus icons frobnicate 2>&1 | plain)
check_has "an unknown word is named, with what exists" "$out" "Unknown: /icons frobnicate"

# ── the JavaScript of macOS, under Node ──
if (( $+commands[node] )); then suite "seticon.js" node $LOTUS_ROOT/tests/icons/seticon.test.js
else print -r -- "  - the JavaScript of macOS is checked with Node – not installed here, skipped"; fi

# ── macOS: the functions, with a stand-in for osascript (this runs on every system: the file is only sourced in a subshell) ──
zf_mkdir -p $HOME/osa-bin $HOME/ls-bin $HOME/emptybin
cat >| $HOME/osa-bin/osascript <<'OSA'
#!/bin/sh
# a stand-in for macOS' osascript: it writes down what it was asked and answers as FAKE_OSA says
echo "$*" >> "$HOME/osa.log"
case $FAKE_OSA in
  boom) printf 'execution error: seticon.js: ObjC.import is not defined (-2700)\nsecond line\n' >&2; exit 1 ;;
  *)    echo "${FAKE_OSA:-ok}" ;;
esac
OSA
cat >| $HOME/ls-bin/ls <<'LS'
#!/bin/sh
# a Desktop that macOS keeps locked until the terminal is allowed to use it
echo "ls: $2: Operation not permitted" >&2; exit 1
LS
chmod +x $HOME/osa-bin/osascript $HOME/ls-bin/ls
mac() { ( source $LOTUS_ROOT/lib/platform/macos.zsh; "$@" ) }           # a function of macos.zsh, whatever this system is
_mac_run() { "$@"; print -r -- "$?|${(j:|:)LOTUS_OS_MSG}" }
_mac_needs() { rehash; lotus_os_folder_icon_needs; print -r -- "status $?"; print -rl -- "${(@)reply}" }
macset()   { mac _mac_run lotus_os_folder_icon_set "$@" }
macreset() { mac _mac_run lotus_os_folder_icon_reset "$@" }
needs()    { mac _mac_needs }
: >| $HOME/osa.log
r=$(FAKE_OSA=ok PATH=$HOME/osa-bin:$PATH macset "$D/Projects" "$HOME/Pictures/red.png")
check_eq "macOS: set – osascript says ok, the status is 0" "$r" "0|"
check_eq "macOS: …it was asked for the helper, the folder and the picture, in this order" "$(<$HOME/osa.log)" "-l JavaScript $LOTUS_ROOT/lib/icons/seticon.js set $D/Projects $HOME/Pictures/red.png"
r=$(FAKE_OSA=unreadable PATH=$HOME/osa-bin:$PATH macset "$D/Projects" "$HOME/Pictures/red.png")
check_has "macOS: a picture it cannot read says so" "$r" "1|macOS cannot read this picture|red.png is not a picture that Preview can open."
r=$(FAKE_OSA=failed PATH=$HOME/osa-bin:$PATH macset "$D/Projects" "$HOME/Pictures/red.png")
check_has "macOS: a no without a reason says so, and where to look" "$r" "1|macOS did not change the icon|macOS said no without saying why.|Is the folder locked?"
r=$(FAKE_OSA=boom PATH=$HOME/osa-bin:$PATH macset "$D/Projects" "$HOME/Pictures/red.png")
check_has "macOS: an error of osascript is shown (its first line)" "$r" "execution error: seticon.js: ObjC.import is not defined (-2700)"
check "macOS: …and only its first line" eval '[[ $r != *"second line"* ]]'
r=$(PATH=$HOME/emptybin mac eval 'rehash; lotus_os_folder_icon_set /x /y; print -r -- $?')
check_eq "macOS: without osascript it is not possible here (status 2)" "$r" "2"
: >| $HOME/osa.log
r=$(FAKE_OSA=ok PATH=$HOME/osa-bin:$PATH macreset "$D/Projects")
check_eq "macOS: reset – ok is 0" "$r" "0|"
check_eq "macOS: …it asks the helper to reset the folder" "$(<$HOME/osa.log)" "-l JavaScript $LOTUS_ROOT/lib/icons/seticon.js reset $D/Projects"
r=$(FAKE_OSA=failed PATH=$HOME/osa-bin:$PATH macreset "$D/Projects")
check_has "macOS: a reset that fails says so" "$r" "1|macOS did not give the folder its normal icon back|macOS said no without saying why."
r=$(FAKE_OSA=boom PATH=$HOME/osa-bin:$PATH macreset "$D/Projects")
check_has "macOS: …and shows the error of osascript" "$r" "ObjC.import is not defined"
print -r -- x >| "$D/Photos/Icon"$'\r'
check "macOS: a folder with the hidden file Icon has a picture of its own" mac lotus_os_folder_icon_has $D/Photos
check "macOS: …a folder without it has not" eval '! mac lotus_os_folder_icon_has $D/Projects'
rm -f "$D/Photos/Icon"$'\r'
r=$(mac eval 'lotus_os_desktop; print -r -- "$?|${REPLY/#$HOME/~}"')
check_eq "macOS: the Desktop is ~/Desktop" "$r" "0|~/Desktop"
check_eq "macOS: the drop zone names what a Mac reads" "$(mac eval 'lotus_os_folder_icon_types; print -r -- $REPLY')" "PNG · JPEG · HEIC · ICNS · GIF · TIFF"

r=$(LOTUS_OS_VERSION=15.1 PATH=$HOME/osa-bin:$PATH needs)
check_has "macOS needs: a Mac that can do it – nothing is missing" "$r" "status 0"
check_has "macOS needs: …it names the version" "$r" "ok|macOS 11 or newer|this Mac has macOS 15.1|"
check_has "macOS needs: …and that nothing has to be installed" "$r" "ok|Nothing to install|"
r=$(LOTUS_OS_VERSION=10.15 PATH=$HOME/osa-bin:$PATH needs)
check_has "macOS needs: macOS 10.15 is too old, and it says what to do" "$r" "fail|macOS 11 or newer|this Mac has macOS 10.15|Update macOS"
check_has "macOS needs: …so the status is 1" "$r" "status 1"
r=$(LOTUS_OS_VERSION=15.1 TERM_PROGRAM=Apple_Terminal PATH=$HOME/ls-bin:$HOME/osa-bin:$PATH needs)
check_has "macOS needs: a locked Desktop names Terminal and the setting" "$r" "fail|Your Desktop is locked|macOS does not let Terminal use ~/Desktop yet|Open System Settings → Privacy & Security → Files & Folders, turn on Desktop Folder for Terminal"
check_has "macOS needs: …the status is 1" "$r" "status 1"
r=$(LOTUS_OS_VERSION=15.1 TERM_PROGRAM=iTerm.app PATH=$HOME/ls-bin:$HOME/osa-bin:$PATH needs)
check_has "macOS needs: …iTerm by its name" "$r" "turn on Desktop Folder for iTerm"
r=$(LOTUS_OS_VERSION=15.1 TERM_PROGRAM= PATH=$HOME/ls-bin:$HOME/osa-bin:$PATH needs)
check_has "macOS needs: …and any other terminal as your terminal app" "$r" "turn on Desktop Folder for your terminal app"
zf_mkdir -p $HOME/ls-only; ln -sf ${commands[ls]} $HOME/ls-only/ls      # (a Mac has osascript in /usr/bin: the only program on this PATH is ls)
r=$(LOTUS_OS_VERSION=15.1 PATH=$HOME/ls-only needs)
check_has "macOS needs: without osascript it fails and says why" "$r" "fail|osascript is missing"
fakes=$HOME/osa-bin; nohome=$HOME/nohome
r=$(LOTUS_OS_VERSION=15.1 HOME=$nohome PATH=$fakes:$PATH needs)
check_has "macOS needs: no Desktop folder is a hint, not a failure" "$r" "warn|No Desktop folder|~/Desktop is not there|You can still drop other folders into the window."
check_has "macOS needs: …the status stays 0" "$r" "status 0"

# ── Linux: the Desktop, the pictures, the two ways to keep an icon ──
if onlyon linux "the Linux part of the platform layer"; then
  im() { if (( $+commands[magick] )); then magick "$@"; else convert "$@"; fi }
  (( $+commands[magick] || $+commands[convert] )) && have_im=1 || have_im=0

  # where the Desktop is
  lotus_os_desktop; check_eq "the Desktop is ~/Desktop when nothing says otherwise" "$?:${REPLY/#$H/~}" "0:~/Desktop"
  zf_mkdir -p $HOME/.config $HOME/Schreibtisch
  print -r -- $'# a comment\nXDG_MUSIC_DIR="$HOME/Musik"\nXDG_DESKTOP_DIR="$HOME/Schreibtisch"' >| $HOME/.config/user-dirs.dirs
  lotus_os_desktop; check_eq "…the folder that xdg-user-dirs names, in your language" "$?:${REPLY/#$H/~}" "0:~/Schreibtisch"
  XDG_DESKTOP_DIR=$HOME/Elsewhere lotus_os_desktop; check_eq "…and XDG_DESKTOP_DIR wins" "$?:${REPLY/#$H/~}" "0:~/Elsewhere"
  print -r -- 'XDG_DESKTOP_DIR="$HOME/"' >| $HOME/.config/user-dirs.dirs
  lotus_os_desktop; check_eq "…\"\$HOME/\" is how xdg-user-dirs says there is no Desktop" "$?:$REPLY" "1:"
  print -r -- 'XDG_DESKTOP_DIR="$HOME/Nowhere"' >| $HOME/.config/user-dirs.dirs
  lotus_os_desktop; check_eq "…a folder that is not there is named" "$?:${REPLY/#$H/~}" "1:~/Nowhere"
  rm -f $HOME/.config/user-dirs.dirs

  # what kind of picture a file is – by its first bytes, not by its name
  python3 - $HOME/magic <<'PY'
import os, sys
d = sys.argv[1]; os.makedirs(d, exist_ok=True)
files = {
  "a.jpg": b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01",
  "a.gif": b"GIF89a\x01\x00\x01\x00\x00\x00\x00;",
  "a.bmp": b"BM" + b"\x00" * 24,
  "a.webp": b"RIFF\x24\x00\x00\x00WEBPVP8 " + b"\x00" * 8,
  "a.tif": b"II*\x00\x08\x00\x00\x00" + b"\x00" * 8,
  "b.tif": b"MM\x00*\x00\x00\x00\x08" + b"\x00" * 8,
  "a.ico": b"\x00\x00\x01\x00\x01\x00" + b"\x00" * 10,
  "empty.ico": b"\x00\x00\x01\x00\x00\x00" + b"\x00" * 10,
  "a.icns": b"icns\x00\x00\x00\x10" + b"\x00" * 8,
  "a.heic": b"\x00\x00\x00\x18ftypheic\x00\x00\x00\x00mif1heic",
  "a.avif": b"\x00\x00\x00\x1cftypavif\x00\x00\x00\x00avifmif1",
  "a.svg": b'<?xml version="1.0"?>\n<!-- a picture -->\n<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8"/>',
  "a.txt": b"hello",
  "a.mov": b"\x00\x00\x00\x14ftypqt  \x00\x00\x00\x00qt  ",
}
for name, data in files.items(): open(os.path.join(d, name), "wb").write(data)
PY
  mkpng $HOME/magic/a.png
  for pair in a.png:png a.jpg:jpeg a.gif:gif a.bmp:bmp a.webp:webp a.tif:tiff b.tif:tiff a.ico:ico a.icns:icns a.heic:heic a.avif:avif a.svg:svg; do
    _lotus_os_icon_kind $HOME/magic/${pair%%:*}
    check_eq "the kind of ${pair%%:*} is ${pair#*:}" "$REPLY" "${pair#*:}"
  done
  for name in a.txt empty.ico a.mov; do
    _lotus_os_icon_kind $HOME/magic/$name
    check_eq "$name is no picture" "$?:$REPLY" "1:"
  done
  cp $HOME/magic/a.gif $HOME/magic/looks-like.png
  _lotus_os_icon_kind $HOME/magic/looks-like.png; check_eq "a GIF called .png is still a GIF" "$REPLY" "gif"

  _lotus_os_file_uri "$HOME/x/ä b#1.png"
  check_eq "an address for GIO: a space, an umlaut and a # are written as %XX" "$REPLY" "file://$H/x/%C3%A4%20b%231.png"

  # the copy of the picture that Lotus keeps
  _lotus_os_icon_store $HOME/Pictures/red.png; stored=$REPLY
  check_eq "a PNG is kept as it is, in Lotus' folder, under a name made from what is in it" "$?:${stored/#$H/~}" "0:~/.local/share/lotus/icons/${stored:t}"
  check "…the copy is the same picture" eval '[[ $(cksum < $stored) == $(cksum < $HOME/Pictures/red.png) ]]'
  _lotus_os_icon_store "$HOME/Pictures/my red.png"; check_eq "…the same picture again is the same copy" "$REPLY" "$stored"
  _lotus_os_icon_store $HOME/Pictures/green.png; check "…another picture is another copy" eval '[[ $REPLY != $stored ]]'
  rm -f $HOME/Pictures/UPPER.PNG.gone; mv $HOME/Pictures/UPPER.PNG $HOME/Pictures/UPPER.PNG.gone
  check "…the original can be moved: the copy stays" test -s $stored
  mv $HOME/Pictures/UPPER.PNG.gone $HOME/Pictures/UPPER.PNG
  _lotus_os_icon_store $HOME/magic/a.svg; check_eq "an SVG is kept as an SVG" "${REPLY:e}" "svg"
  _lotus_os_icon_store $HOME/magic/a.jpg; check_eq "…a JPEG as a .jpg" "${REPLY:e}" "jpg"
  _lotus_os_icon_store $HOME/Pictures/notes.txt
  check_eq "a text file is refused, with the title and the reason" "$?|${LOTUS_OS_MSG[1]}|${LOTUS_OS_MSG[2]}" "1|Lotus cannot use this picture|notes.txt is not a PNG, JPEG, SVG, GIF, BMP, WebP, TIFF, ICO, ICNS or HEIC picture."
  if (( have_im )); then
    im -size 40x40 xc:red $HOME/Pictures/x.tif
    _lotus_os_icon_store $HOME/Pictures/x.tif; check_eq "with ImageMagick a TIFF becomes a PNG" "$?:${REPLY:e}" "0:png"
    lotus_os_png_size $REPLY; check_eq "…of the same size" "$REPLY" "40x40"
    python3 - $HOME/Pictures/big.png <<'PY'
import os, struct, sys, zlib
w = h = 1500
raw = b"".join(b"\x00" + os.urandom(w * 3) for _ in range(h))
chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
open(sys.argv[1], "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 1)) + chunk(b"IEND", b""))
PY
    _lotus_os_icon_store $HOME/Pictures/big.png; lotus_os_png_size $REPLY
    check_eq "…and a big picture (over 2 MB) is made small: at most 512 pixels" "$REPLY" "512x512"
    rm -f $HOME/Pictures/big.png
  else print -r -- "  - ImageMagick is not here: the TIFF and big-picture checks are skipped"; fi
  r=$( ( unset "commands[magick]" "commands[convert]"; _lotus_os_icon_store $HOME/magic/a.tif; print -r -- "$?|${LOTUS_OS_MSG[1]}|${LOTUS_OS_MSG[2]}" ) )
  check_has "without ImageMagick a TIFF is refused and the way out is named" "$r" "1|This picture needs ImageMagick|A TIFF picture is turned into a PNG first"

  # KDE and LXQt: a .directory file in the folder, the rest of the file left alone
  export LOTUS_ICON_METHOD=file
  lotus_os_folder_icon_set $D/Projects $HOME/Pictures/red.png
  check_eq "KDE: set – the status" "$?" "0"
  check_eq "KDE: …a .directory file with the picture's copy" "$(<$D/Projects/.directory)" $'[Desktop Entry]\nIcon='$stored
  check "KDE: …the folder has a picture of its own" lotus_os_folder_icon_has $D/Projects
  check "KDE: …another folder has not" eval '! lotus_os_folder_icon_has $D/Photos'
  print -r -- $'[Dolphin]\nTimestamp=2026,11,27,10,0,0.0\nViewMode=1\n\n[Settings]\nHiddenFilesShown=true' >| $D/Photos/.directory
  lotus_os_folder_icon_set $D/Photos $HOME/Pictures/red.png
  check_eq "KDE: an existing .directory gets the Icon first, everything else stays – blank lines too" "$(<$D/Photos/.directory)" $'[Desktop Entry]\nIcon='$stored$'\n[Dolphin]\nTimestamp=2026,11,27,10,0,0.0\nViewMode=1\n\n[Settings]\nHiddenFilesShown=true'
  lotus_os_folder_icon_set $D/Photos $HOME/Pictures/green.png
  check_eq "KDE: another picture replaces the Icon – there is only one" "$(grep -c '^Icon=' $D/Photos/.directory)" "1"
  lotus_os_folder_icon_reset $D/Photos
  check_eq "KDE: reset takes only the Icon and its heading away" "$(<$D/Photos/.directory)" $'[Dolphin]\nTimestamp=2026,11,27,10,0,0.0\nViewMode=1\n\n[Settings]\nHiddenFilesShown=true'
  lotus_os_folder_icon_reset $D/Projects
  check "KDE: …a file that was only for the icon goes" eval '[[ ! -e $D/Projects/.directory ]]'
  lotus_os_folder_icon_reset $D/Projects; check_eq "KDE: …resetting a folder that has nothing is fine" "$?" "0"
  print -r -- $'[Desktop Entry]\nName=Mine\nIcon=folder-red\nComment=kept' >| $D/Projects/.directory
  lotus_os_folder_icon_reset $D/Projects
  check_eq "KDE: other keys of the same group stay" "$(<$D/Projects/.directory)" $'[Desktop Entry]\nName=Mine\nComment=kept'
  rm -f $D/Projects/.directory $D/Photos/.directory
  if (( EUID != 0 )); then
    chmod 555 $D/Projects
    lotus_os_folder_icon_set $D/Projects $HOME/Pictures/red.png
    check_eq "KDE: a folder that is locked says so" "$?|${LOTUS_OS_MSG[1]}" "1|Lotus cannot write into this folder"
    chmod 755 $D/Projects
  else print -r -- "  - a locked folder cannot be tested as root – skipped"; fi
  unset LOTUS_ICON_METHOD

  # GNOME, Cinnamon, MATE, XFCE: gio – here a stand-in that keeps the attributes in a file, and a broken one
  zf_mkdir -p $HOME/gio-bin
  cat >| $HOME/gio-bin/gio <<'GIO'
#!/bin/sh
# a stand-in for gio: "set" and "info" as the real one takes them; FAKE_GIO_BROKEN=1 is a system without GVfs
db=$HOME/.fake-gio-db; echo "gio $*" >> $HOME/.fake-gio-log
if [ "$FAKE_GIO_BROKEN" = 1 ]; then echo "gio: Setting attribute $6 not supported" >&2; exit 1; fi
case $1 in
  set) shift; type=; while [ "$1" != "--" ]; do [ "$1" = -t ] && { type=$2; shift; }; shift; done; shift
       loc=$1; attr=$2; val=$3
       { grep -v "^$loc	$attr	" $db 2>/dev/null; [ "$type" = unset ] || printf '%s\t%s\t%s\n' "$loc" "$attr" "$val"; } > $db.new; mv $db.new $db ;;
  info) shift; attr=$2; loc=$4
       echo "uri: file://$loc"; echo "attributes:"; grep "^$loc	$attr	" $db 2>/dev/null | awk -F'\t' '{ print "  " $2 ": " $3 }' ;;
esac
GIO
  chmod +x $HOME/gio-bin/gio
  gio_test() ( export LOTUS_ICON_METHOD=gio PATH=$HOME/gio-bin:$PATH; rehash; "$@" )
  _gio_set() { lotus_os_folder_icon_set "$1" "$2"; print -r -- "$?|${(j:|:)LOTUS_OS_MSG}" }
  rm -f $HOME/.fake-gio-log $HOME/.fake-gio-db
  r=$(gio_test _gio_set "$D/My Games" $HOME/Pictures/red.png)
  check_eq "gio: set – the status" "$r" "0|"
  _lotus_os_file_uri $stored
  check_has "gio: …the folder gets metadata::custom-icon: the address of Lotus' copy" "$(<$HOME/.fake-gio-log)" "gio set -t string -- $D/My Games metadata::custom-icon $REPLY"
  check_has "gio: …after one try-out on a folder of its own, to see that GVfs keeps what it is given" "$(<$HOME/.fake-gio-log)" "gio set -t string -- /"
  check_has "gio: …that try-out is taken away again" "$(<$HOME/.fake-gio-log)" "metadata::lotus-probe"
  check "gio: the folder has a picture of its own" gio_test lotus_os_folder_icon_has "$D/My Games"
  check "gio: …another has not" eval '! gio_test lotus_os_folder_icon_has $D/Photos'
  r=$(gio_test eval 'lotus_os_folder_icon_reset "$D/My Games"; print -r -- $?')
  check_eq "gio: reset – the status" "$r" "0"
  check_has "gio: …the attribute is unset" "$(<$HOME/.fake-gio-log)" "gio set -t unset -- $D/My Games metadata::custom-icon"
  check "gio: …and the folder has no picture of its own again" eval '! gio_test lotus_os_folder_icon_has "$D/My Games"'
  rm -f $HOME/.fake-gio-log
  r=$(FAKE_GIO_BROKEN=1 gio_test _gio_set "$D/My Games" $HOME/Pictures/red.png)
  check_has "gio without GVfs: set says the icon service is not running" "$r" "1|The icon service of your desktop is not running|gio is installed, but GVfs does not keep what it is given"
  check "gio without GVfs: …and nothing was copied or set for the folder" eval '! grep -q custom-icon $HOME/.fake-gio-log'
  r=$(FAKE_GIO_BROKEN=1 gio_test eval 'lotus_os_folder_icon_reset "$D/My Games"; print -r -- "$?|${(j:|:)LOTUS_OS_MSG}"')
  check_has "gio without GVfs: reset shows what gio said, its first line" "$r" "1|Your desktop did not take the icon away|gio: Setting attribute metadata::custom-icon not supported"
  r=$( ( export LOTUS_ICON_METHOD=gio; unset "commands[gio]"; lotus_os_folder_icon_set $D/Projects $HOME/Pictures/red.png; print -r -- $? ) )
  check_eq "gio missing: not possible here (status 2)" "$r" "2"

  # what it needs
  _needs() { lotus_os_folder_icon_needs; print -r -- "status $?"; print -rl -- "${(@)reply}" }
  r=$( ( export LOTUS_ICON_METHOD=file; _needs ) )
  check_has "Linux needs, KDE: nothing to install" "$r" "ok|Nothing to install|a small .directory file is written in each folder"
  check_has "Linux needs, KDE: …the status is 0" "$r" "status 0"
  r=$(gio_test eval 'export LOTUS_DESKTOP=gnome; _needs')
  check_has "Linux needs, GNOME with GVfs: the desktop is named with its file manager" "$r" "ok|A desktop that shows folder icons|GNOME – GNOME Files"
  check_has "Linux needs, GNOME with GVfs: gio and GVfs are fine" "$r" "ok|gio and GVfs|"
  check_has "Linux needs, GNOME with GVfs: the status is 0" "$r" "status 0"
  r=$(FAKE_GIO_BROKEN=1 gio_test eval 'export LOTUS_DESKTOP=xfce; _needs')
  check_has "Linux needs, GNOME without GVfs: the status is 1" "$r" "status 1"
  check_has "Linux needs, without GVfs: it says what is wrong and how to fix it" "$r" "fail|GVfs|its icon service is not running – a desktop session has it|In a desktop window, or install it:"
  r=$( ( export LOTUS_ICON_METHOD=gio; unset "commands[gio]"; _needs ) )
  check_has "Linux needs, without gio: it names the missing program" "$r" "fail|gio|the program that keeps folder icons is missing|"
  r=$( ( export LOTUS_ICON_METHOD=file LOTUS_DESKTOP=none; _needs ) )
  check_has "Linux needs: no desktop at all is a hint, not a failure" "$r" "warn|A desktop that shows folder icons|no desktop is running here"
  r=$( ( export LOTUS_ICON_METHOD=file LOTUS_DESKTOP=enlightenment; _needs ) )
  check_has "Linux needs: a desktop it does not know is a hint too" "$r" "warn|A desktop that shows folder icons|enlightenment is not one Lotus knows"
  r=$( ( export LOTUS_ICON_METHOD=file LOTUS_DESKTOP=kde; _needs ) )
  check_has "Linux needs: KDE is named with Dolphin" "$r" "ok|A desktop that shows folder icons|KDE Plasma – Dolphin"
  r=$( ( export LOTUS_ICON_METHOD=file XDG_DESKTOP_DIR=$HOME/Nowhere; _needs ) )
  check_has "Linux needs: a Desktop folder that is not there is a hint" "$r" "warn|No Desktop folder|~/Nowhere is not there"
  r=$( ( export LOTUS_ICON_METHOD=file; unset "commands[magick]" "commands[convert]"; _needs ) )
  check_has "Linux needs: ImageMagick is optional, and says for what" "$r" "warn|ImageMagick (optional)|only for WebP, HEIC and TIFF pictures"
  r=$( ( export LOTUS_ICON_METHOD=file; unset "commands[magick]" "commands[convert]"; lotus_os_folder_icon_types; print -r -- $REPLY ) )
  check_eq "Linux: the drop zone names what works without ImageMagick" "$r" "PNG · JPEG · SVG · GIF"
fi

# ── the commands, without questions ──
# macOS: a stand-in for osascript that does what the real one does to the folder (the hidden file Icon); Linux: real .directory files
REAL_PATH=$PATH
zf_mkdir -p $HOME/mac-bin
cat >| $HOME/mac-bin/osascript <<'OSA'
#!/bin/sh
# -l JavaScript <seticon.js> set|reset <folder> [<picture>] – the hidden file Icon, whose name ends in a carriage return
action=$4; folder=$5; pic=$6; icon="$folder/Icon$(printf '\r')"
case $action in
  set)   [ -r "$pic" ] || { echo unreadable; exit 0; }; cp "$pic" "$icon"; echo ok ;;
  reset) rm -f "$icon"; echo ok ;;
esac
OSA
chmod +x $HOME/mac-bin/osascript
export LOTUS_ICON_METHOD=file PATH=$HOME/mac-bin:$PATH
unset LOTUS_DESKTOP
cd $HOME/Pictures
# a command of Lotus without a keyboard → OUT (its output, plain) and RC (its status)
run() { local o; o=$(lotus "$@" 2>&1 < /dev/null; print -r -- "·rc=$?"); RC=${o##*·rc=}; OUT=$(print -r -- "${o%·rc=*}" | plain) }

run icons set red.png Projects "My Games"; out=$OUT
check_has "set: names of folders on the Desktop, the picture in this folder" "$out" "2 folders have a new icon"
check_eq "set: …the status is 0" "$RC" "0"
check "set: …Projects has a picture of its own" has_icon $D/Projects
check "set: …My Games too" has_icon "$D/My Games"
check "set: …Photos has not – it was not named" eval '! has_icon $D/Photos'
check_has "set: …each folder is named when it is done" "$out" "✓ My Games"
check_has "set: …and how to get the normal icons back" "$out" "/icons reset"
out=$(lotus icons list 2>&1 | plain)
check_has "list: the folder that has one says so" "$out" "Projects                   2 items · has a picture of its own"
check_has "list: …and the one that has none does not" "$out" "Photos                     empty"$'\n'
check_has "list: …it names the Desktop" "$out" "~/Desktop"
check "list: …a package, a hidden folder, a link and a file are not listed" eval '[[ $out != *Tool.app* && $out != *.hidden* && $out != *Link* && $out != *notes.txt* ]]'

out=$(lotus icons set green.png --all 2>&1 < /dev/null | plain)
check_has "set --all: every folder on the Desktop" "$out" "3 folders have a new icon"
check "set --all: …Photos too now" has_icon $D/Photos
check "set --all: …not a package, not a hidden folder" eval '! has_icon $D/Tool.app && ! has_icon $D/.hidden && ! has_icon $D/Notes.rtfd'
check "set --all: …and not the folders it was not asked for" eval '! has_icon "$HOME/Elsewhere/Other"'
out=$(lotus icons set red.png Photos Photos Projects --all 2>&1 < /dev/null | plain)
check_has "a folder named twice, and with --all, is done once" "$out" "3 folders have a new icon"

out=$(lotus icons reset Photos 2>&1 < /dev/null | plain)
check_has "reset: a folder by name" "$out" "1 folder has the normal icon again"
check "reset: …it is back to normal" eval '! has_icon $D/Photos'
check "reset: …the others are not touched" eval 'has_icon $D/Projects && has_icon "$D/My Games"'
out=$(lotus icons reset --all 2>&1 < /dev/null | plain)
check_has "reset --all: only the folders that have a picture of their own" "$out" "2 folders have the normal icon again"
check "reset --all: …all are normal" eval '! has_icon $D/Projects && ! has_icon "$D/My Games"'
out=$(lotus icons reset --all 2>&1 < /dev/null | plain)
check_has "reset --all when there is nothing to do says so" "$out" "None of the folders on your Desktop has a picture of its own"

# a path with spaces that was not quoted (the shell hands over its pieces), a folder from outside the Desktop
out=$(lotus icons set $HOME/Pictures/my red.png $HOME/Elsewhere/Deep Folder $HOME/Elsewhere/Other 2>&1 < /dev/null | plain)
check_has "set: a picture and a folder with spaces in their names, not quoted" "$out" "2 folders have a new icon"
check "set: …the folder outside the Desktop" has_icon "$HOME/Elsewhere/Deep Folder"
check "set: …and the other one" has_icon "$HOME/Elsewhere/Other"
lotus icons reset "$HOME/Elsewhere/Deep Folder" $HOME/Elsewhere/Other >/dev/null 2>&1 < /dev/null
check "reset: folders outside the Desktop by their path" eval '! has_icon "$HOME/Elsewhere/Deep Folder" && ! has_icon $HOME/Elsewhere/Other'
out=$(lotus icons red.png Projects 2>&1 < /dev/null | plain)
check_has "a picture as the first word is the same as set" "$out" "1 folder has a new icon"
lotus icons reset Projects >/dev/null 2>&1
out=$(lotus icons $HOME/Pictures/my red.png Projects 2>&1 < /dev/null | plain)
check_has "a picture whose path has a space that was not quoted is found too" "$out" "1 folder has a new icon"
check "…and it is the picture that was meant" has_icon $D/Projects
lotus icons reset Projects >/dev/null 2>&1

# what is wrong is said
run icons set notes.txt Projects; out=$OUT
check_has "not a picture: named, with the reason and what a picture is" "$out" "notes.txt cannot be an icon"$'\n'"    it is not a picture file"
check_eq "not a picture: the status is 1" "$RC" "1"
check "not a picture: …nothing was changed" eval '! has_icon $D/Projects'
check_has "an empty file is no picture" "$(lotus icons set empty.png Projects 2>&1 < /dev/null | plain)" "the file is empty"
check_has "a picture that is not there" "$(lotus icons set nope.png Projects 2>&1 < /dev/null | plain)" "Not found: nope.png"
run icons set red.png; out=$OUT
check_has "no folders and no keyboard: it asks which, and how to say it" "$out" "Which folders?"$'\n'"    /icons set red.png <folders>   ·   /icons set red.png --all"
check_eq "…the status is 1" "$RC" "1"
check_has "a picture on its own without a keyboard asks which folders too" "$(lotus icons red.png 2>&1 < /dev/null | plain)" "Which folders?"
check_has "set without anything asks which picture" "$(lotus icons set 2>&1 < /dev/null | plain)" "Which picture?"
out=$(lotus icons set red.png Nowhere 2>&1 < /dev/null | plain)
check_has "a folder that is not there is named, and then it asks which folders" "$out" "Not found: Nowhere"
check_has "a file is not a folder" "$(lotus icons set red.png $HOME/Pictures/green.png 2>&1 < /dev/null | plain)" "Not a folder: green.png"
run icons reset Nowhere; out=$OUT
check_has "reset: a folder that is not there is named" "$out" "Not found: Nowhere"
check_eq "reset: …the status is 1" "$RC" "1"
check_has "reset without folders and without a keyboard asks which" "$(lotus icons reset 2>&1 < /dev/null | plain)" "Which folders?"

# when the system says no for one folder – and when it cannot at all (the platform functions are stood in for)
failing() {
  lotus_os_folder_icon_set() {
    case ${1:t} in
      Photos)   LOTUS_OS_MSG=("The system said no" "It is locked." "Unlock it."); return 1 ;;
      Projects) LOTUS_OS_MSG=("The system said no" "It is locked." "Unlock it."); return 1 ;;
      *)        return 0 ;;
    esac
  }
  ICONS_FOLDERS=($D/Photos "$D/My Games" $D/Projects) ICONS_PICS=(a b c)
  icons_apply set; print -r -- "status $?"
}
out=$(failing 2>&1 | plain)
check_has "a folder that fails is named with the reason; the others are done" "$out" "✓ My Games"
check_has "…the two that failed are named with the reason" "$out" "✗ Photos – The system said no"$'\n'"      It is locked."
check_eq "…the reason is given once, not for each folder" "$(print -r -- "$out" | grep -c 'It is locked.')" "1"
check_has "…and counted" "$out" "1 folder has a new icon"
check_has "…the failures too" "$out" "2 folders could not be changed"
check_has "…the status is 1" "$out" "status 1"
nothere() {
  lotus_os_folder_icon_set() { return 2 }
  ICONS_FOLDERS=($D/Photos); ICONS_PICS=(a)
  icons_apply set; print -r -- "status $?"
}
out=$(nothere 2>&1 | plain)
check_has "when the system cannot at all it says so, and shows what it needs" "$out" "Folder icons do not work here yet"
check_has "…the list of what it needs follows" "$out" "WHAT IT NEEDS"
check_has "…and the status is 1" "$out" "status 1"
skipped() {
  lotus_os_folder_icon_set() { return 0 }
  ICONS_FOLDERS=($D/Photos $D/Projects); ICONS_PICS=(a "")
  icons_apply set
}
check_has "a folder without a picture is left out, and that is said" "$(skipped 2>&1 | plain)" "1 folder has a new icon (1 left as they were)"

# ── the guided command, in a pseudo terminal: each answer is typed when its question has been asked (tests/icons/flow.py) ──
flow() {   # <the conversation as JSON: [[text to wait for, keys to type]…]> <arguments of lotus icons…> → FLOW (plain text), RC
  local o
  print -r -- "$1" >| $HOME/steps.json; shift
  o=$(python3 $LOTUS_ROOT/tests/icons/flow.py $HOME/steps.json $LOTUS_ROOT/bin/lotus icons "$@" 2>&1; print -r -- "·rc=$?")
  RC=${o##*·rc=}; FLOW=$(print -r -- "${o%·rc=*}" | plain)
}
# what is the picture of a folder? (its checksum – the picture that was set, not the name of a copy)
icon_sum() {
  local f
  if [[ $LOTUS_OS == macos ]]; then f="$1/Icon"$'\r'
  else f=${${(M)${(f)"$(<$1/.directory)"}:#Icon=*}#Icon=}; fi
  [[ -r $f ]] && print -r -- ${$(cksum < $f)%% *}
}
sum_of() { print -r -- ${$(cksum < $1)%% *} }
RED=$H/Pictures/red.png GREEN=$H/Pictures/green.png
cd $HOME

flow '[["esc back","\r"],["or a different one for each?",""],["esc back","\r"],["q goes back.","'$RED'\r"],["Change the icon of 3 folders?","y"],["have a new icon",""]]'
check_has "guided: it says what it needs, and how it works" "$FLOW" "WHAT IT NEEDS"$'\n'
check_has "guided: …the three steps are named" "$FLOW" "1  Choose the folders – one, a few or all of them"
check_has "guided: step 1 – which folders" "$FLOW" "Step 1 of 3 · Which folders?"
check_has "guided: …All 3 folders on the Desktop is the first choice" "$FLOW" "● All 3 folders on the Desktop"
check_has "guided: step 2 – the picture, with the drop zone" "$FLOW" "Drop the picture here"
check_has "guided: …it tells what to do" "$FLOW" "Drag the picture from"
check_has "guided: step 3 – what will happen, folder by folder" "$FLOW" "My Games                 → red.png"
check_has "guided: …and asks" "$FLOW" "Change the icon of 3 folders?"
check_eq "guided: all folders, the same picture – the status" "$RC" "0"
check_eq "guided: …Projects got the picture" "$(icon_sum $D/Projects)" "$(sum_of $RED)"
check_eq "guided: …Photos too" "$(icon_sum $D/Photos)" "$(sum_of $RED)"
check_eq "guided: …and My Games" "$(icon_sum "$D/My Games")" "$(sum_of $RED)"
lotus icons reset --all >/dev/null 2>&1 < /dev/null

flow '[["esc back","\u001b[B\r"],["Tick the folders with Space",""],["esc back"," \u001b[B\u001b[B \r"],["or a different one for each?",""],["esc back","\u001b[B\r"],["q goes back.","'$RED'\r"],["q goes back.","'$GREEN'\r"],["Change the icon of 2 folders?","y"],["have a new icon",""]]'
check_has "guided: choose which ones – a list to tick" "$FLOW" "Tick the folders with Space"
check_has "guided: …the folders with what they hold" "$FLOW" "Projects             2 items"$'\n'
check_has "guided: a different picture for each – the first one asks for My Games" "$FLOW" "Drop the picture for “My Games”"
check_has "guided: …the second for Projects" "$FLOW" "Drop the picture for “Projects”"
check_has "guided: …and the check lists the two with their pictures" "$FLOW" "Projects                 → green.png"
check_eq "guided: ticked ones, each its own picture – the status" "$RC" "0"
check_eq "guided: …My Games got the red one" "$(icon_sum "$D/My Games")" "$(sum_of $RED)"
check_eq "guided: …Projects the green one" "$(icon_sum $D/Projects)" "$(sum_of $GREEN)"
check "guided: …Photos was not ticked: no picture" eval '! has_icon $D/Photos'
lotus icons reset --all >/dev/null 2>&1 < /dev/null

flow '[["esc back","\r"],["or a different one for each?",""],["esc back","\r"],["q goes back.","q\r"],["Nothing was changed.",""]]'
check_has "guided: q goes back from the drop zone – nothing was changed" "$FLOW" "Nothing was changed."
check_eq "guided: …the status is 0" "$RC" "0"
check "guided: …and no folder has a picture" eval '! has_icon $D/Projects && ! has_icon $D/Photos && ! has_icon "$D/My Games"'
flow '[["esc back","\u001b"],["Nothing was changed.",""]]'
check_has "guided: Esc in the list of choices goes back too" "$FLOW" "Nothing was changed."

lotus icons set $RED --all >/dev/null 2>&1 < /dev/null
flow '[["esc back","\r"],["Give 3 folders the normal icon back?","y"],["have the normal icon again",""]]' reset
check_has "guided reset: the folders that have a picture are offered" "$FLOW" "● All 3 folders that have a picture of their own"
check_has "guided reset: …it says what it does" "$FLOW" "Give the folders on your Desktop their normal icon back"
check_eq "guided reset: the status" "$RC" "0"
check "guided reset: …all three are normal again" eval '! has_icon $D/Projects && ! has_icon $D/Photos && ! has_icon "$D/My Games"'

flow '[["esc back","\u001b[B\u001b[B\r"],["q goes back.","'$H'/Elsewhere/Deep\\ Folder '$H'/nowhere\r"],["q goes back.","'$RED'\r"],["Change the icon of 1 folder?","y"],["has a new icon",""]]'
check_has "guided: other folders – a drop zone for folders" "$FLOW" "Drop folders here"
check_has "guided: …a folder that is not there is named" "$FLOW" "Not found: $H/nowhere"
check_eq "guided: …a dragged path with a backslash for the space is the folder" "$(icon_sum "$H/Elsewhere/Deep Folder")" "$(sum_of $RED)"
check_eq "guided: …the status is 0" "$RC" "0"
lotus icons reset "$H/Elsewhere/Deep Folder" >/dev/null 2>&1 < /dev/null

flow '[["esc back","\r"],["Change the icon of 3 folders?","y"],["have a new icon",""]]' $GREEN
check_has "guided with the picture given: it is step 2 already" "$FLOW" "2  The picture: green.png"
check_eq "guided with the picture given: all three get it" "$(icon_sum $D/Photos)|$(icon_sum $D/Projects)|$(icon_sum "$D/My Games")" "$(sum_of $GREEN)|$(sum_of $GREEN)|$(sum_of $GREEN)"
lotus icons reset --all >/dev/null 2>&1 < /dev/null

# ── the real thing, where this machine can do it ──
zf_mkdir -p $H/real/Folder
if [[ $LOTUS_OS == macos ]]; then
  out=$(PATH=$REAL_PATH LOTUS_ICON_METHOD= $LOTUS_ROOT/bin/lotus icons set $RED $H/real/Folder 2>&1 < /dev/null | plain)
  if [[ -e $H/real/Folder/Icon$'\r' ]]; then
    # (a Mac keeps the picture in the resource fork of that file – the file itself is empty, as for every folder icon)
    rsrc_ok() { [[ -s $1/Icon$'\r'/..namedfork/rsrc ]] || xattr -p com.apple.ResourceFork $1/Icon$'\r' >/dev/null 2>&1 }
    check "this Mac, for real: the hidden file Icon is in the folder, and its resource fork holds the picture" rsrc_ok $H/real/Folder
    rsrc_ok $H/real/Folder || print -r -- "      what is there: $(ls -la@ $H/real/Folder 2>&1 | tr '\r\n' '~|' | cut -c1-500)"
    print -r -- "  · the Finder flags of the folder (the custom icon is bit 4 of the ninth byte): $(xattr -px com.apple.FinderInfo $H/real/Folder 2>&1 | tr -d '\n' | cut -c1-120)"
    PATH=$REAL_PATH LOTUS_ICON_METHOD= $LOTUS_ROOT/bin/lotus icons reset $H/real/Folder >/dev/null 2>&1 < /dev/null
    check "this Mac, for real: reset takes the hidden file away" test ! -e "$H/real/Folder/Icon"$'\r'
  else
    print -r -- "  - this Mac did not set an icon from a script here – the real thing is skipped (${out//$'\n'/ })"
  fi
else
  if ( PATH=$REAL_PATH; rehash; LOTUS_DESKTOP=gnome; _lotus_os_gio_ready ) 2>/dev/null; then
    out=$(PATH=$REAL_PATH LOTUS_ICON_METHOD=gio $LOTUS_ROOT/bin/lotus icons set $RED $H/real/Folder 2>&1 < /dev/null | plain)
    check_has "this system, for real (gio and GVfs): the folder has the attribute" "$(PATH=$REAL_PATH gio info -a metadata::custom-icon -- $H/real/Folder)" "metadata::custom-icon: file://"
    PATH=$REAL_PATH LOTUS_ICON_METHOD=gio $LOTUS_ROOT/bin/lotus icons reset $H/real/Folder >/dev/null 2>&1 < /dev/null
    check "this system, for real: reset takes it away" eval '[[ $(PATH=$REAL_PATH gio info -a metadata::custom-icon -- $H/real/Folder) != *"metadata::custom-icon: "* ]]'
  else
    print -r -- "  - gio cannot keep an icon here (GVfs runs in a desktop session) – the real gio is skipped"
  fi
fi
