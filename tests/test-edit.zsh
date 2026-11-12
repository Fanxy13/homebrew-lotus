# /img and the image editor (lib/edit): the table of commands and the help, the glue in zsh, and – each a program of its own that
# prints ✓ and ✗ – the geometry of the crop (Node), the engine and the session of one picture, and the page's texts and policy.
# No network, no browser: the server over HTTP is tests/test-editserver.zsh.
source $LOTUS_ROOT/lib/core.zsh
source $LOTUS_ROOT/lib/ui.zsh
lotus_load
source $LOTUS_ROOT/lib/cmd/img.zsh
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

# ── the commands of Lotus ──
check "/img is still an alias for lotus img" grep -q $'^Images\t/img\timg\t/img\t' $LOTUS_ROOT/data/commands.tsv
check "and the cheatsheet lists the editor" grep -q $'^Images\t-\timg edit\t/img edit <image>\t' $LOTUS_ROOT/data/commands.tsv
check_has "the help names the editor first" "$(lotus img help 2>&1 | plain)" "/img edit <image>"
check_has "and still the converter" "$(lotus img help 2>&1 | plain)" "/img convert <image or folder>"
check_has "/img without a keyboard is the help" "$(lotus img 2>&1 < /dev/null | plain)" "crop, turn, straighten, hide faces and convert this picture"

# ── the glue ──
out=$(lotus img edit 2>&1 < /dev/null | plain)
check_has "/img edit without a picture and without a keyboard asks which" "$out" "Which picture?"
out=$(lotus img edit $HOME/nothing.png 2>&1 < /dev/null | plain)
check_has "a picture that is not there" "$out" "Not found: $HOME/nothing.png"
zf_mkdir -p $HOME/pics/folder
print -r -- "not an image" >| $HOME/pics/not.png
print -r -- "not an image either" >| $HOME/pics/folder/one.png
out=$(lotus img edit $HOME/pics/folder 2>&1 < /dev/null | plain)
check_has "a folder is for /img convert" "$out" "The editor opens one picture at a time"
check_has "and the way to it is shown" "$out" "/img convert <folder>"
out=$(lotus img edit $HOME/pics/not.png 2>&1 < /dev/null | plain)
if (( $+commands[python3] )) && { [[ $LOTUS_OS == macos ]] || (( $+commands[magick] || ($+commands[convert] && $+commands[identify]) )) }; then
  check_has "what is not a picture is said" "$out" "not.png"
else
  print -r -- "  · no Python 3 or no image program here: the rest of the glue is skipped"
fi

# ── the test programs: Python and, for the geometry, Node ──
if (( $+commands[node] )); then
  suite "geometry" node $LOTUS_ROOT/tests/edit/geometry.test.js
  suite "faces (Face Blur's detector)" node $LOTUS_ROOT/tests/edit/faces.test.js
  suite "hiding faces (Face Blur)" node $LOTUS_ROOT/tests/edit/blur.test.js
else print -r -- "  · no Node here: the geometry of the crop, the face detector and the hiding of faces are not tested"; fi
if (( ! $+commands[python3] )); then
  print -r -- "  · no Python 3: the editor's tests are skipped"
else
  suite "page" python3 -B $LOTUS_ROOT/tests/edit/page_test.py
  # the engine: on a Mac lotus-img (built once – half a minute), elsewhere ImageMagick
  if [[ $LOTUS_OS == macos ]]; then
    img_tool || lotus_swift_build lotus-img $LOTUS_ROOT/lib/img/Convert.swift > /dev/null 2>&1
    img_tool && export LOTUS_IMG_TOOL=$REPLY
  fi
  if [[ $LOTUS_OS == macos && -z $LOTUS_IMG_TOOL ]]; then print -r -- "  · the converter could not be built here: the engine tests are skipped"
  else suite "engine" python3 -B $LOTUS_ROOT/tests/edit/engine_test.py; fi
fi
