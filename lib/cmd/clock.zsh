# lotus clock – a clock for the terminal, in the colors of your theme
#   lotus clock [minimal|big|retro|matrix|analog|world]
# ←/→ or space switch the design, s seconds on/off, z a second time zone, q or esc leaves.
# One loop that wakes when the second changes (Matrix: a few times a second) – no background process.
# It uses the Mac's own clock; time zones come from the system's zone files.

typeset -ga CLK_DESIGNS=(minimal big retro matrix analog world)

# Big digits: 5 pixels wide, 7 high; the colon is 1 wide
typeset -gA CLK_FONT=(
  0 ".###. #...# #..## #.#.# ##..# #...# .###."
  1 "..#.. .##.. ..#.. ..#.. ..#.. ..#.. .###."
  2 ".###. #...# ....# ...#. ..#.. .#... #####"
  3 "##### ...#. ..#.. ...#. ....# #...# .###."
  4 "...#. ..##. .#.#. #..#. ##### ...#. ...#."
  5 "##### #.... ####. ....# ....# #...# .###."
  6 "..##. .#... #.... ####. #...# #...# .###."
  7 "##### ....# ...#. ..#.. .#... .#... .#..."
  8 ".###. #...# #...# .###. #...# #...# .###."
  9 ".###. #...# #...# .#### ....# ...#. .##.."
  : ". # . . # . ."
)

# Seven segments per digit: a top, b top right, c bottom right, d bottom, e bottom left, f top left, g middle
typeset -gA CLK_SEG=(0 abcdef 1 bc 2 abged 3 abgcd 4 fgbc 5 afgcd 6 afgedc 7 abc 8 abcdefg 9 abcdfg)

lotus_cmd_clock() {
  emulate -L zsh
  setopt extendedglob
  zmodload zsh/datetime
  [[ $1 == clock ]] && shift          # bin/lotus hands over the command name first
  local want=${1:-$LOTUS_CLOCK_DESIGN}
  [[ -n ${CLK_DESIGNS[(r)$want]} ]] || want=big
  if ! { [[ -t 1 ]] && ui_has_tty }; then
    # not a terminal: the time once
    strftime -s REPLY '%H:%M:%S' $EPOCHSECONDS
    print -r -- $REPLY
    return 0
  fi
  _clk_setup
  local -i d=${CLK_DESIGNS[(i)$want]} secs=${LOTUS_CLOCK_SECONDS:-1} zi=0 last=-1 rows cols changed=0
  local -a zones=(${=LOTUS_CLOCK_ZONES})
  zones=(${zones:#*[^A-Za-z0-9_/+-]*})
  [[ -n $LOTUS_CLOCK_ZONE ]] && zi=${zones[(i)$LOTUS_CLOCK_ZONE]} && (( zi > ${#zones} )) && zi=0
  local state=$(stty -g < /dev/tty 2>/dev/null)
  stty -echo -icanon < /dev/tty 2>/dev/null
  print -n $'\e[?1049h\e[?25l\e[2J'
  UI_INT=0
  TRAPINT() { UI_INT=1; return 0 }
  local -F now wait
  local -a sz
  while :; do
    now=$EPOCHREALTIME
    if (( ${now%.*} != last )) || [[ $CLK_DESIGNS[d] == matrix ]]; then
      if (( ${now%.*} != last )); then
        sz=(${=$(stty size < /dev/tty 2>/dev/null)})
        rows=${sz[1]:-24} cols=${sz[2]:-80}
        last=${now%.*}
      fi
      _clk_frame $CLK_DESIGNS[d] $rows $cols $secs "${zones[zi]:-}"
    fi
    if [[ $CLK_DESIGNS[d] == matrix ]]; then wait=0.12
    else (( wait = 1.0 - (now - ${now%.*}) + 0.01 )); fi
    ui_keyx $wait
    case $REPLY in
      timeout) ;;
      right|space|tab|l|n) (( d = d % ${#CLK_DESIGNS} + 1, last = -1, changed = 1 )) ;;
      left|h|p)            (( d = (d + ${#CLK_DESIGNS} - 2) % ${#CLK_DESIGNS} + 1, last = -1, changed = 1 )) ;;
      s|S)                 (( secs = !secs, last = -1, changed = 1 )) ;;
      z|Z)                 (( ${#zones} )) && (( zi = (zi + 1) % (${#zones} + 1), last = -1, changed = 1 )) ;;
      [1-6])               (( d = REPLY, last = -1, changed = 1 )) ;;
      q|Q|esc|enter|interrupt) break ;;
      *) ;;
    esac
    (( UI_INT )) && break
  done
  unfunction TRAPINT 2>/dev/null
  print -n $'\e[?2026l\e[2J\e[?1049l\e[?25h'
  [[ -n $state ]] && stty $state < /dev/tty 2>/dev/null
  [[ -t 1 ]] && trap 'exit 130' INT
  if (( changed )); then
    # the last design, seconds and time zone are what the clock opens with next time
    LOTUS_CLOCK_DESIGN=$CLK_DESIGNS[d] LOTUS_CLOCK_SECONDS=$secs LOTUS_CLOCK_ZONE=${zones[zi]:-}
    lotus_save
  fi
  return 0
}

# Colors of the theme, and the day and month names in the language of Lotus
typeset -gA CLK_C
typeset -gA CLK_ZOFF CLK_ZAT
_clk_setup() {
  local -a th=(${=LOTUS_THEMES[$LOTUS_THEME]:-$LOTUS_THEMES[matcha]})
  local k i
  local -a names=(logo key accent key2 salute border dim)
  for (( i = 1; i <= ${#names}; i++ )); do lotus_sgr $th[i]; CLK_C[$names[i]]=$'\e['"${REPLY}m"; done
  # dark versions for the unlit segments of the retro clock and the tail of the rain
  for k in key2 key logo; do
    local -a c=(${(s:;:)th[${names[(i)$k]}]})
    lotus_sgr "$(( c[1] * 22 / 100 ));$(( c[2] * 22 / 100 ));$(( c[3] * 22 / 100 ))"; CLK_C[${k}_off]=$'\e['"${REPLY}m"
    lotus_sgr "$(( c[1] * 55 / 100 ));$(( c[2] * 55 / 100 ));$(( c[3] * 55 / 100 ))"; CLK_C[${k}_mid]=$'\e['"${REPLY}m"
  done
  CLK_C[r]=$'\e[0m' CLK_C[b]=$'\e[1m' CLK_C[w]=$'\e[97m'
  case $LOTUS_LANG in
    de) export LC_TIME=de_DE.UTF-8 ;; fr) export LC_TIME=fr_FR.UTF-8 ;; es) export LC_TIME=es_ES.UTF-8 ;; *) export LC_TIME=en_US.UTF-8 ;;
  esac
}

# Seconds east of UTC for a zone, asked once an hour (DST changes are rare but real)
_clk_offset() {
  local z=$1
  if [[ -z ${CLK_ZOFF[$z]} ]] || (( EPOCHSECONDS - ${CLK_ZAT[$z]:-0} > 3600 )); then
    local o
    [[ -r /usr/share/zoneinfo/$z ]] && o=$(TZ=$z date +%z 2>/dev/null)
    if [[ $o == [+-][0-9][0-9][0-9][0-9] ]]; then
      CLK_ZOFF[$z]=$(( (${o[1]}1) * (10#${o[2,3]} * 3600 + 10#${o[4,5]} * 60) ))
    else
      CLK_ZOFF[$z]=x
    fi
    CLK_ZAT[$z]=$EPOCHSECONDS
  fi
  REPLY=$CLK_ZOFF[$z]
  [[ $REPLY != x ]]
}

# "Tokyo 22:07 · tomorrow" for a zone → REPLY
_clk_zone_line() {
  local z=$1 secs=$2
  _clk_offset $z || { REPLY="$z ?"; return }
  local -i off=$REPLY t h m s here dz
  strftime -s here '%z' $EPOCHSECONDS
  local -i hoff=$(( (${here[1]}1) * (10#${here[2,3]} * 3600 + 10#${here[4,5]} * 60) ))
  (( t = EPOCHSECONDS + off, h = t % 86400 / 3600, m = t % 3600 / 60, s = t % 60 ))
  (( dz = (EPOCHSECONDS + off) / 86400 - (EPOCHSECONDS + hoff) / 86400 ))
  local city=${${z:t}//_/ } day=
  (( dz > 0 )) && day=" · ${LOTUS_L[clk_tomorrow]:-tomorrow}"
  (( dz < 0 )) && day=" · ${LOTUS_L[clk_yesterday]:-yesterday}"
  if (( secs )); then printf -v REPLY '%s %02d:%02d:%02d%s' "$city" h m s "$day"
  else printf -v REPLY '%s %02d:%02d%s' "$city" h m "$day"; fi
}

# One frame of a design, centered, with its name on top and the keys at the bottom
_clk_frame() {
  local design=$1 zone=$5
  local -i H=$2 W=$3 secs=$4
  local -a out
  local -i w=0
  local hm hms date
  strftime -s hm '%H:%M' $EPOCHSECONDS
  strftime -s hms '%H:%M:%S' $EPOCHSECONDS
  strftime -s date '%A, %e %B %Y' $EPOCHSECONDS
  date=${date//  / }
  local t=$hm
  (( secs )) && t=$hms
  case $design in
    minimal) _clk_minimal $t "$date" ;;
    big)     _clk_big $t "$date" $W ;;
    retro)   _clk_retro $t "$date" $W ;;
    matrix)  _clk_matrix $t $H $W ;;
    analog)  _clk_analog $H $W $secs "$date" ;;
    world)   _clk_world $secs $W ;;
  esac
  out=("${reply[@]}") w=$CLK_W
  if [[ -n $zone && $design != world ]]; then
    _clk_zone_line $zone $secs
    out+=("" "$CLK_C[dim]${(l:(w + ${#REPLY}) / 2:)REPLY}$CLK_C[r]")
  fi
  local -i h=${#out} top left i
  local label=${LOTUS_L[clk_$design]:-$design}
  local keys=${LOTUS_L[clk_keys]:-←→ design · s seconds · z time zone · q quit}
  (( top = (H - h) / 2, top < 2 && (top = 2) ))
  (( left = (W - w) / 2, left < 0 && (left = 0) ))
  local buf=$'\e[?2026h\e[H'
  buf+="  $CLK_C[dim]lotus clock · $CLK_C[r]$CLK_C[key]$label$CLK_C[r]"$'\e[K\n'
  for (( i = 2; i < top; i++ )); do buf+=$'\e[K\n'; done
  local pad=${(l:left:: :)}
  for (( i = 1; i <= h && top + i < H; i++ )); do buf+="$pad${out[i]}$CLK_C[r]"$'\e[K\n'; done
  buf+=$'\e[J\e['"${H};3H$CLK_C[dim]$keys$CLK_C[r]"$'\e[?2026l'
  print -rn -- $buf
}

# ── The designs. Each one: reply = lines, CLK_W = their width ──

_clk_minimal() {
  local t=$1 date=$2 spaced=
  local ch
  for ch in ${(s::)t}; do spaced+="$ch "; done
  spaced=${spaced% }
  local -i w=$(( ${#spaced} > ${#date} ? ${#spaced} : ${#date} ))
  local line=${(l:(w + ${#spaced}) / 2:)spaced}
  # the seconds quieter than the hours and minutes
  local main=${line[1,-7]} tail=${line[-6,-1]}
  [[ ${#t} == 5 ]] && main=$line tail=
  reply=("$CLK_C[b]$CLK_C[key]$main$CLK_C[r]$CLK_C[dim]$tail" "" "$CLK_C[accent]${(l:(w + ${#date}) / 2:)date}")
  CLK_W=$w
}

# Big digits from the font; two columns per pixel when there is room
_clk_bigrows() {   # <text> <pixel width> → reply (7 rows of '#' and '.', already widened)
  local t=$1 ch g
  local -i pw=$2 r
  reply=("" "" "" "" "" "" "")
  for ch in ${(s::)t}; do
    local -a rows=(${=CLK_FONT[$ch]})
    for (( r = 1; r <= 7; r++ )); do
      g=${rows[r]//./ }
      (( pw == 2 )) && g=${${g//\#/██}// /  } || g=${g//\#/█}
      reply[r]+="$g${(l:pw:: :)}"
    done
  done
}

_clk_big() {
  local t=$1 date=$2
  local -i W=$3 pw=2
  (( ${#t} * 12 > W - 4 )) && pw=1
  _clk_bigrows $t $pw
  local -a rows=("${reply[@]}")
  local -i w=${#rows[1]} r
  reply=()
  # a soft gradient from the theme's lotus color to its key color
  local -a col=($CLK_C[logo] $CLK_C[logo] $CLK_C[accent] $CLK_C[accent] $CLK_C[key] $CLK_C[key] $CLK_C[key])
  for (( r = 1; r <= 7; r++ )); do reply+=("$col[r]$rows[r]"); done
  reply+=("" "$CLK_C[dim]${(l:(w + ${#date}) / 2:)date}")
  CLK_W=$w
}

# Seven segments, the unlit ones faintly visible like on a real display
_clk_retro() {
  local t=$1 date=$2 ch segs
  local -i r
  local on=$CLK_C[key2] off=$CLK_C[key2_off] sp="     "
  local -a rows=("" "" "" "" "" "" "")
  local a b c d e f g
  _clk_seg() { [[ $segs == *$1* ]] && REPLY=$on || REPLY=$off }
  for ch in ${(s::)t}; do
    if [[ $ch == : ]]; then
      rows[1]+="   " rows[2]+="   " rows[3]+=" $on●$off " rows[4]+="   " rows[5]+=" $on●$off " rows[6]+="   " rows[7]+="   "
      continue
    fi
    segs=$CLK_SEG[$ch]
    _clk_seg a; a=$REPLY; _clk_seg b; b=$REPLY; _clk_seg c; c=$REPLY; _clk_seg d; d=$REPLY
    _clk_seg e; e=$REPLY; _clk_seg f; f=$REPLY; _clk_seg g; g=$REPLY
    rows[1]+="$a ━━━━━  "
    rows[2]+="$f┃$sp$b┃ " rows[3]+="$f┃$sp$b┃ "
    rows[4]+="$g ━━━━━  "
    rows[5]+="$e┃$sp$c┃ " rows[6]+="$e┃$sp$c┃ "
    rows[7]+="$d ━━━━━  "
  done
  local -i w=$(( ${#${t//[^0-9]/}} * 8 + ${#${t//[0-9]/}} * 3 ))
  local frame=$CLK_C[border] bar=${(l:w + 2::─:)}
  reply=("$frame╭$bar╮")
  for (( r = 1; r <= 7; r++ )); do reply+=("$frame│ ${rows[r]} $frame│"); done
  reply+=("$frame╰$bar╯" "" "$CLK_C[key2_mid]${(l:(w + 4 + ${#date}) / 2:)date}")
  CLK_W=$(( w + 4 ))
}

# Digits made of falling characters: rain everywhere, brighter where a digit is
typeset -ga CLK_RAIN CLK_SPEED
typeset -gi CLK_RW=0
_clk_matrix() {
  local t=$1
  local -i H=$2 W=$3 x y pw=2 hgt
  local glyphs='01234567890ABCDEF:+*<>=#%$&ZXCVNMKLJH'
  (( hgt = H - 4 ))
  (( W > 2 )) || W=80
  (( W -= 2 ))
  if (( CLK_RW != W )); then
    CLK_RAIN=() CLK_SPEED=()
    for (( x = 1; x <= W; x++ )); do CLK_RAIN+=($(( RANDOM % (hgt + 20) - 20 ))); CLK_SPEED+=($(( RANDOM % 2 + 1 ))); done
    CLK_RW=W
  fi
  (( ${#t} * 12 > W - 4 )) && pw=1
  _clk_bigrows $t $pw
  local -a big=("${reply[@]}")
  local -i bw=${#big[1]} bx by
  (( bx = (W - bw) / 2, by = (hgt - 7) / 2 ))
  local -a lines
  local line g head=$CLK_C[w] hot=$CLK_C[key] tail=$CLK_C[key_mid] dark=$CLK_C[key_off] cur=
  for (( y = 0; y < hgt; y++ )); do
    line= cur=
    for (( x = 1; x <= W; x++ )); do
      local -i d=$(( CLK_RAIN[x] - y ))
      local inside=0
      if (( y >= by && y < by + 7 && x > bx && x <= bx + bw )); then
        [[ ${big[y - by + 1][x - bx]} == █ ]] && inside=1
      fi
      g=${glyphs[RANDOM % ${#glyphs} + 1]}
      if (( inside )); then
        [[ $cur == hot ]] || { line+=$hot; cur=hot }
        line+=$g
      elif (( d == 0 )); then
        [[ $cur == head ]] || { line+=$head; cur=head }
        line+=$g
      elif (( d > 0 && d < 7 )); then
        [[ $cur == tail ]] || { line+=$tail; cur=tail }
        line+=$g
      elif (( d >= 7 && d < 16 )); then
        [[ $cur == dark ]] || { line+=$dark; cur=dark }
        line+=$g
      else
        line+=" "
      fi
    done
    lines+=("$line")
  done
  for (( x = 1; x <= W; x++ )); do
    (( CLK_RAIN[x] += CLK_SPEED[x] ))
    (( CLK_RAIN[x] - 16 > hgt )) && { CLK_RAIN[x]=$(( - RANDOM % 15 )); CLK_SPEED[x]=$(( RANDOM % 2 + 1 )) }
  done
  reply=("${lines[@]}")
  CLK_W=$W
}

# A round face drawn with braille dots (2 × 4 per character, close to square)
typeset -gA CLK_DOT CLK_COL
_clk_plot() {   # <x> <y> <color name> – one dot on the canvas
  local -i x=$1 y=$2 cx=$(( $1 / 2 )) cy=$(( $2 / 4 ))
  (( x < 0 || y < 0 )) && return
  local -i bit
  case $(( x % 2 ))$(( y % 4 )) in
    00) bit=1 ;; 01) bit=2 ;; 02) bit=4 ;; 03) bit=64 ;;
    10) bit=8 ;; 11) bit=16 ;; 12) bit=32 ;; 13) bit=128 ;;
  esac
  CLK_DOT[$cx,$cy]=$(( ${CLK_DOT[$cx,$cy]:-0} | bit ))
  CLK_COL[$cx,$cy]=$3
}
_clk_line() {   # <x0> <y0> <angle in degrees, 0 = up> <from r> <to r> <color>
  local -F a=$(( ($3 - 90) * 3.14159265 / 180 )) r
  local -F step=0.5
  for (( r = $4; r <= $5; r += step )); do
    _clk_plot $(( int(rint($1 + cos(a) * r)) )) $(( int(rint($2 + sin(a) * r)) )) $6
  done
}
_clk_analog() {
  zmodload zsh/mathfunc
  local -i H=$1 W=$2 secs=$3 ch cw x y
  local date=$4
  (( ch = H - 7, ch > 26 && (ch = 26), ch < 8 && (ch = 8) ))
  (( cw = ch * 2, cw > W - 4 && (cw = W - 4) ))
  local -i R=$(( (cw * 2 < ch * 4 ? cw * 2 : ch * 4) / 2 - 2 ))
  local -i X=$(( cw )) Y=$(( ch * 2 ))
  CLK_DOT=() CLK_COL=()
  local -F a
  local -i k
  for (( k = 0; k < 120; k++ )); do
    (( a = k * 3 ))
    _clk_line $X $Y $a $(( R - 0.5 )) $R border
  done
  for (( k = 0; k < 12; k++ )); do
    _clk_line $X $Y $(( k * 30 )) $(( R * (k % 3 ? 0.86 : 0.76) )) $(( R - 2 )) ${${(M)k:#(0|3|6|9)}:+key}${${k:#(0|3|6|9)}:+dim}
  done
  local -i h m s
  strftime -s h '%H' $EPOCHSECONDS; strftime -s m '%M' $EPOCHSECONDS; strftime -s s '%S' $EPOCHSECONDS
  h=10#$h m=10#$m s=10#$s
  _clk_line $X $Y $(( (h % 12) * 30 + m * 0.5 )) 0 $(( R * 0.5 )) logo
  _clk_line $(( X + 1 )) $Y $(( (h % 12) * 30 + m * 0.5 )) 0 $(( R * 0.5 )) logo
  _clk_line $X $Y $(( m * 6 + s * 0.1 )) 0 $(( R * 0.78 )) key
  (( secs )) && _clk_line $X $Y $(( s * 6 )) 0 $(( R * 0.86 )) salute
  local line col cur
  reply=()
  for (( y = 0; y < ch; y++ )); do
    line= cur=
    for (( x = 0; x < cw; x++ )); do
      local -i bits=${CLK_DOT[$x,$y]:-0}
      if (( bits )); then
        col=${CLK_COL[$x,$y]}
        [[ $col == $cur ]] || { line+=$CLK_C[$col]; cur=$col }
        line+=${(#)$(( 0x2800 + bits ))}
      else
        line+=" "
      fi
    done
    reply+=("$line")
  done
  local t
  strftime -s t '%H:%M' $EPOCHSECONDS
  (( secs )) && strftime -s t '%H:%M:%S' $EPOCHSECONDS
  reply+=("$CLK_C[b]$CLK_C[key]${(l:(cw + ${#t}) / 2:)t}" "$CLK_C[dim]${(l:(cw + ${#date}) / 2:)date}")
  CLK_W=$cw
}

# Here and the zones of the settings: time, day, offset and where the day stands
_clk_world() {
  local -i secs=$1 W=$2 hr off t h m s dz
  local -a zones=(${=LOTUS_CLOCK_ZONES})
  zones=(${zones:#*[^A-Za-z0-9_/+-]*})
  local here z name tm sx gmt day bar color
  local -i now=$EPOCHSECONDS          # one moment for every row
  strftime -s here '%z' $now
  local -i hoff=$(( (${here[1]}1) * (10#${here[2,3]} * 3600 + 10#${here[4,5]} * 60) ))
  reply=()
  for z in here $zones; do
    if [[ $z == here ]]; then off=$hoff name=${LOTUS_L[clk_here]:-Here}
    else _clk_offset $z || continue; off=$REPLY name=${${z:t}//_/ }; fi
    (( t = now + off, h = t % 86400 / 3600, m = t % 3600 / 60, s = t % 60 ))
    (( dz = (now + off) / 86400 - (now + hoff) / 86400 ))
    printf -v tm '%02d:%02d' h m
    (( secs )) && { printf -v sx ':%02d' s; tm+=$sx }
    day=
    (( dz > 0 )) && day="+1"
    (( dz < 0 )) && day="−1"
    printf -v gmt 'UTC%+d' $(( off / 3600 ))
    (( off % 3600 )) && gmt+=":$(( (off < 0 ? -off : off) % 3600 / 60 ))"
    # 24 hours: the day bright, the night dark, now marked
    bar=
    for (( hr = 0; hr < 24; hr++ )); do
      if (( hr == h )); then bar+="$CLK_C[logo]●"
      elif (( hr >= 7 && hr < 19 )); then bar+="$CLK_C[key_mid]▬"
      else bar+="$CLK_C[key_off]▬"; fi
    done
    color=$CLK_C[w]
    [[ $z == here ]] && color=$CLK_C[key]
    reply+=("$CLK_C[b]$color${(r:16:)name[1,16]}$CLK_C[r]  $CLK_C[b]${(r:9:)tm}$CLK_C[r]$CLK_C[salute]${(r:3:)day}$CLK_C[dim]${(r:9:)gmt}$CLK_C[r] $bar")
    reply+=("")
  done
  reply[-1]=()
  CLK_W=64
}
