# The art of the start screen: logos in theme or own colors, the album cover (lib/cover.pl),
# the choice of art for the window, live swaps between cover and logo
source $LOTUS_ROOT/lib/core.zsh
lotus_load
setopt extendedglob
strip() { REPLY=${1//$'\e'\[[0-9;]#m/} }
colors() {   # <text> → reply = the different front colors in it (38;…)
  local p
  reply=()
  for p in ${(ps:\e[:)1}; do
    [[ "${p%%m*};" == (#b)*(38\;(2\;<->\;<->\;<->|5\;<->))\;* ]] && reply+=($match[1])
  done
  reply=(${(u)reply})
}
widths_ok() {   # <file> <width> – every line exactly as wide
  local l
  for l in "${(@f)$(<$1)}"; do strip "$l"; (( ${#REPLY} == $2 )) || return 1; done
}
# A BMP as sips writes it (24-bit, top-down): bmp <file> <width> <height> <r;g;b per pixel, row by row …>
bmp() {
  local f=$1 px
  local -i w=$2 h=$3 stride=$(( ($2 * 3 + 3) / 4 * 4 )) x y
  shift 3
  local -a c
  le() { printf "\\\\x%02x\\\\x%02x\\\\x%02x\\\\x%02x" $(( $1 & 255 )) $(( $1 >> 8 & 255 )) $(( $1 >> 16 & 255 )) $(( $1 >> 24 & 255 )) }
  local out="BM$(le $(( 54 + stride * h )))$(le 0)$(le 54)$(le 40)$(le $w)$(le $(( 4294967296 - h )))\\x01\\x00\\x18\\x00$(le 0)$(le $(( stride * h )))$(le 2835)$(le 2835)$(le 0)$(le 0)"
  for (( y = 0; y < h; y++ )); do
    for (( x = 0; x < w; x++ )); do
      c=(${(s:;:)1}); shift
      out+=$(printf '\\x%02x\\x%02x\\x%02x' $c[3] $c[2] $c[1])
    done
    repeat $(( stride - w * 3 )) out+='\x00'
  done
  print -n -- $out >| $f
}

# ── Logos ─────────────────────────────────────────────────────

LOTUS_COLORS=truecolor LOTUS_THEME=ocean; lotus_colors
LOTUS_LOGO_THEME=1
lotus_logo_paint apple; file=$REPLY
check "Apple: painted" test -s $file
check_eq "Apple: 36 × 22" "$reply" "36 22"
check "Apple: every line as wide (the info starts right after it)" widths_ok $file 36
apple=("${(@f)$(<$file)}")
check_has "theme colors: the theme's logo color" "$apple[1]" "1;$LOTUS_C[logo]m"
colors "$(<$file)"
check_eq "theme colors: one color for all lines" "$reply" "$LOTUS_C[logo]"
check_has "a lit top half is drawn as background (no gaps in Terminal.app)" "$apple[-2]" $'\e[0;1;7;'"$LOTUS_C[logo]m▄      "
check_has "a dark top half stays a character" "$apple[6]" "m       ▗▄▄▄▄▄▄▖"

LOTUS_LOGO_THEME=0
lotus_logo_paint apple
apple=("${(@f)$(<$REPLY)}")
check_has "own colors: the Apple's leaf is green" "$apple[1]" '1;38;2;97;187;70m'
check_has "own colors: the Apple's bottom is blue" "$apple[-1]" '1;38;2;0;157;220m'
colors "$(<$REPLY)"
check_eq "own colors: six stripes" ${#reply} 6
lotus_logo_paint earth; file=$REPLY
earth=("${(@f)$(<$file)}")
check_eq "Flag of Earth: 52 × 24" "$reply" "52 24"
check "Flag of Earth: every line as wide" widths_ok $file 52
check_has "own colors: white rings on blue" "$earth[1]" $'\e[0;1;38;2;255;255;255;48;2;1;58;167m'
check_has "own colors: a lit top half is white behind blue" "$earth[2]" $'\e[0;1;38;2;1;58;167;48;2;255;255;255m'
check "own colors: the blue reaches the right edge" eval '[[ ${earth[1]} == *" "$'"'"'\e[0m'"'"' ]]'
lotus_logo_paint lotus
lotus=("${(@f)$(<$REPLY)}")
check_has "own colors: the lotus is light pink at the tip" "$lotus[1]" '1;38;2;255;222;234m'
check_has "own colors: deep pink at the base" "$lotus[-1]" '1;38;2;226;96;150m'
LOTUS_COLORS=256; lotus_colors
lotus_logo_paint earth
check_has "256 colors: own colors as the nearest of 256" "$(<$REPLY)" $'\e[0;1;38;5;231;48;5;25m'
LOTUS_COLORS=truecolor; lotus_colors

zf_mkdir -p $LOTUS_CONF
print -r -- 'a $$ b' >| $LOTUS_CONF/logo.txt
lotus_logo_paint custom
check_has "your own logo: \$\$ is a \$" "$(<$REPLY)" 'a $ b'
check_has "your own logo: always the theme's color" "$(<$REPLY)" "1;$LOTUS_C[logo]m"
check "no logo: nothing painted" eval '! lotus_logo_paint none'

lotus_logo_paint minimal; first=$REPLY
zstat -A t1 +mtime $first
sleep 1.1
lotus_logo_paint minimal
zstat -A t2 +mtime $first
check_eq "painted once, then taken from the cache" "$t2" "$t1"
LOTUS_LOGO_THEME=1; lotus_logo_paint minimal
check "another color setting paints again" eval '[[ $(<$REPLY) != *"255;222;234"* ]]'

# ── Album cover: lib/cover.pl ─────────────────────────────────

bmp $HOME/sq.bmp 2 2 '255;0;0' '0;255;0' '0;0;255' '255;255;255'
out=$(/usr/bin/perl $LOTUS_ROOT/lib/cover.pl $HOME/sq.bmp 2 1 tc)
check_eq "cover: two pixels per character, the top one behind, the bottom one in front" "$out" \
  $'\e[38;2;0;0;255;48;2;255;0;0m▄\e[38;2;255;255;255;48;2;0;255;0m▄\e[0m'
out=$(/usr/bin/perl $LOTUS_ROOT/lib/cover.pl $HOME/sq.bmp 2 1 256)
check_eq "cover: 256 colors" "$out" $'\e[38;5;21;48;5;196m▄\e[38;5;231;48;5;46m▄\e[0m'
bmp $HOME/wide.bmp 4 2 '10;10;10' '10;10;10' '10;10;10' '10;10;10' '200;200;200' '200;200;200' '200;200;200' '200;200;200'
lines=("${(@f)$(/usr/bin/perl $LOTUS_ROOT/lib/cover.pl $HOME/wide.bmp 40 40 tc)}")
strip "$lines[1]"
check_eq "cover: keeps the picture's shape (as big as fits)" "${#REPLY} × ${#lines}" "40 × 10"
check "cover: no picture, no art" eval '! /usr/bin/perl $LOTUS_ROOT/lib/cover.pl $HOME/missing.bmp 4 4 tc'

# ── Album cover: from the player to the art ───────────────────

sips -s format jpeg $HOME/sq.bmp --out $HOME/cover.jpeg >/dev/null 2>&1
STATE=Playing
lotus_cover_query() {   # instead of macOS: a song with the test cover
  local t=${TMPDIR%/}/ff_LOTUSTEST-$$.jpeg
  cp $HOME/cover.jpeg $t
  reply=($STATE "Song" "Artist" "Album" $t)
}
lotus_cover 48 24
check "a song plays: its cover as art" test -s "$REPLY"
check_eq "a square cover fills the room" "$reply" "48 24"
check "the cover from macOS is removed again" test ! -e ${TMPDIR%/}/ff_LOTUSTEST-$$.jpeg
check_has "the art keeps the cover's colors, not the theme's" "$(<$REPLY)" '38;2;'
STATE=Paused
check "paused: no cover" eval '! lotus_cover 48 24'
check "paused: the cover from macOS is removed too" test ! -e ${TMPDIR%/}/ff_LOTUSTEST-$$.jpeg

# ── The start screen: which art, how big ──────────────────────

LOTUS_LOGO=lotus LOTUS_LOGO_THEME=1 LOTUS_NP_ON=1 LOTUS_COVER=1 STATE=Paused
COLUMNS=140; lotus_art_pick 22
check_has "wide window: the logo" "$reply" "--logo $LOTUS_CACHE/art/lotus.txt --logo-type file-raw --logo-width 48 --logo-height 22"
check_eq "the logo's room: 48 × 24" "$LOTUS_ART_W × $LOTUS_ART_H" "48 × 24"
COLUMNS=100; lotus_art_pick 22
check_has "narrower: the minimal lotus" "$reply" "--logo-width 34"
COLUMNS=70; lotus_art_pick 22
check_eq "narrow: no logo" "$reply" "--logo none"
STATE=Playing
COLUMNS=140; lotus_art_pick 22
check_has "a song plays: its cover in the logo's place" "$reply" "--logo $LOTUS_CACHE/covers/"
check_has "as tall as the logo's room" "$reply" "--logo-width 48 --logo-height 24 --logo-padding-top 0"
COLUMNS=100; lotus_art_pick 22
check_has "narrower: a smaller cover – the info keeps 64 columns" "$reply" "--logo-width 36 --logo-height 18"
check_has "the room stays wide enough for the logo" "$reply" "--logo-padding-right 6"
LOTUS_COVER=0; COLUMNS=140; lotus_art_pick 22
check_has "covers turned off: the logo" "$reply" "--logo $LOTUS_CACHE/art/lotus.txt"
LOTUS_COVER=1 LOTUS_NP_ON=0; lotus_art_pick 22
check_has "now playing off: the logo" "$reply" "--logo $LOTUS_CACHE/art/lotus.txt"
LOTUS_NP_ON=1

# ── Live: a song starts and stops ─────────────────────────────

LOTUS_ART_TTY=$HOME/tty.out
STATE=Paused; COLUMNS=140; lotus_art_pick 22
LOTUS_ART_KEY= LOTUS_NP_ROW=21 LOTUS_NP_IDX=21
STATE=Playing
lotus_art_live "♫ Song — Artist" "  [··········] 00:01 / 03:00  ▶ playing"
check "a song starts: its cover is drawn" eval '[[ $LOTUS_ART_SHOWN == $LOTUS_CACHE/covers/* ]]'
out=$(<$LOTUS_ART_TTY)
check_has "drawn from the first row of the start screen, in the logo's place" "$out" $'\e[1;3H\e[38;2;'
check_has "with line wrap off" "$out" $'\e[?7l'
: >| $LOTUS_ART_TTY
lotus_art_live "♫ Song — Artist" "  [■·········] 00:20 / 03:00  ▶ playing"
check_eq "the same song: nothing drawn again" "$(<$LOTUS_ART_TTY)" ""
STATE=Paused
lotus_art_live "♫ Song — Artist" "  [■·········] 00:20 / 03:00  ‖ paused"
check_eq "stopped: the logo again" "$LOTUS_ART_SHOWN" "$LOTUS_CACHE/art/lotus.txt"
check_has "the logo in its place" "$(<$LOTUS_ART_TTY)" $'\e[3;3H\e[0;1;'"$LOTUS_C[logo]m"
LOTUS_NP_ROW=0; : >| $LOTUS_ART_TTY
STATE=Playing; lotus_art_live "♫ Other — Artist" "  [··········] 00:01 / 03:00  ▶ playing"
check_eq "start screen no longer on screen: nothing drawn" "$(<$LOTUS_ART_TTY)" ""
