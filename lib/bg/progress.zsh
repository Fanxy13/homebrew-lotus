# lotus – the progress screen for Remove BG: a lotus that blooms while the work gets done.
#
#   ◇ lotus / Remove BG                                       portrait.jpg
#
#                      (the flower, opening step by step)
#                              ~ ~~  ~ ~~ ~
#
#                         ◆ Finding the subject
#                      ━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
#              ✓ Model   ✓ Image   ◆ Subject   · Edges   · PNG
#
#                    BiRefNet · MPS · 1916 × 2608 · 2.1s
#                              ctrl-c cancels
#
# The flower opens with the steps that are really done (and with real download bytes); while
# a step runs it only drifts a little further and pollen rises – never a made-up percentage.
# The pixels come from data/bloom.txt (scripts/make-bloom.py) and take the theme's colors.
# One centered column, every line placed by cursor position and line wrap off, so nothing can
# run through the drawing. Without a terminal (pipes, scripts, -V) it prints one plain line per step.

zmodload zsh/zselect 2>/dev/null
zmodload zsh/mathfunc 2>/dev/null
zmodload zsh/system 2>/dev/null

typeset -ga BGU_KEYS=() BGU_LABELS=() BGU_SHORT=() BGU_TIMES=() BGU_INFO_KEYS=()
typeset -gA BGU_INFO=()
typeset -g BGU_TITLE= BGU_CUR= BGU_NOTE= BGU_SUB=
typeset -gi BGU_LIVE=0 BGU_ON=0 BGU_DIRTY=1 BGU_FRAME=0 BGU_DONE=0 BGU_TOTAL=0 BGU_IMG=0 BGU_IMGS=0 BGU_FINISHED=0
typeset -gF BGU_T0=0 BGU_TS=0 BGU_BLOOM=0

# Flower frames and their rendering (cached per frame), pollen
typeset -ga BGU_PIX=() BGU_PX=() BGU_PY=() BGU_PL=()
typeset -gA BGU_FG=() BGU_BG=() BGU_ROW=() BGU_MASK=()
typeset -gi BGU_ART_W=0 BGU_ART_H=0

# bg_ui_begin <title> "key|Label[|Short]" …   (Short is the word in the step line, default bg_ss_<key>)
bg_ui_begin() {
  BGU_TITLE=$1; shift
  BGU_KEYS=() BGU_LABELS=() BGU_SHORT=() BGU_TIMES=() BGU_INFO_KEYS=() BGU_INFO=() BGU_CUR= BGU_NOTE= BGU_SUB=
  BGU_DONE=0 BGU_TOTAL=0 BGU_IMG=0 BGU_IMGS=0 BGU_FINISHED=0 BGU_BLOOM=0 BGU_PX=() BGU_PY=() BGU_PL=() BGU_PV=()
  local s
  local -a f
  for s in "$@"; do
    f=("${(@s:|:)s}")
    BGU_KEYS+=($f[1]) BGU_LABELS+=("$f[2]") BGU_SHORT+=("${f[3]:-${LOTUS_L[bg_ss_$f[1]]:-$f[2]}}") BGU_TIMES+=("")
  done
  BGU_T0=$EPOCHREALTIME BGU_TS=$EPOCHREALTIME BGU_FRAME=0 BGU_DIRTY=1
  BGU_LIVE=0
  [[ -t 1 && -z $LOTUS_VERBOSE ]] && ui_has_tty && BGU_LIVE=1
  BGU_ON=1
  if (( BGU_LIVE )); then
    _bgu_load
    print -n $'\e[?1049h\e[?25l\e[?7l\e[2J'
    TRAPWINCH() { BGU_DIRTY=1 }
  else
    ui_header $BGU_TITLE >&2    # scripts: progress on stderr, the PNG paths alone on stdout
  fi
}

# Back to the normal terminal. Safe to call more than once; starts no other program.
bg_ui_end() {
  (( BGU_ON )) || return 0
  BGU_ON=0
  if (( BGU_LIVE )); then
    print -n $'\e[0m\e[?7h\e[?25h\e[?1049l'
    unfunction TRAPWINCH 2>/dev/null
  fi
  return 0
}

bg_ui_stage() {   # <key> – the stages before it count as done
  local key=$1
  local -i i
  [[ $key == $BGU_CUR ]] && return
  local -F now=$EPOCHREALTIME
  for (( i = 1; i <= ${#BGU_KEYS}; i++ )); do
    [[ $BGU_KEYS[i] == $BGU_CUR && -z $BGU_TIMES[i] ]] && BGU_TIMES[i]=$(( now - BGU_TS ))
  done
  BGU_CUR=$key BGU_TS=$now BGU_NOTE= BGU_DONE=0 BGU_TOTAL=0
  if (( ! BGU_LIVE )) && [[ $key != __end ]]; then
    i=${BGU_KEYS[(i)$key]}
    ui_step "${BGU_LABELS[i]:-$key}" >&2
  fi
  [[ $key == __end ]] || lotus_log DEBUG bg "Stage: $key"
}

bg_ui_info() {    # <key> <value>  (model, backend, resolution … in the line under the steps)
  (( ${BGU_INFO_KEYS[(Ie)$1]} )) || BGU_INFO_KEYS+=($1)
  BGU_INFO[$1]=$2
}

# Next image of a batch: the stages from <key> on start again
bg_ui_reset_from() {
  local -i i=${BGU_KEYS[(i)$1]}
  for (( ; i <= ${#BGU_KEYS}; i++ )); do BGU_TIMES[i]=; done
  BGU_CUR=
}

bg_ui_note() { BGU_NOTE=$1 }                   # small line under the bar (a package, a file)
bg_ui_sub() { BGU_SUB=$1 }                     # top right (e.g. "2 / 14 · photo.jpg")
bg_ui_batch() { BGU_IMG=$1 BGU_IMGS=$2 }       # image n of N – the flower opens over the whole batch
bg_ui_progress() { BGU_DONE=$1 BGU_TOTAL=$2 }  # real progress (bytes), 0 0 = none

# All stages done: the flower opens fully, a short moment, then back
bg_ui_complete() {
  bg_ui_stage __end
  BGU_CUR= BGU_FINISHED=1
  (( BGU_LIVE )) || return 0
  local -i i
  for (( i = 0; i < 14; i++ )); do bg_ui_frame; bg_ui_tick 6; done
}

_bgu_fmt_secs() { (( $1 < 60 )) && printf -v REPLY '%.1fs' $1 || printf -v REPLY '%dm %02ds' $(( int($1) / 60 )) $(( int($1) % 60 )) }

# ── The flower ────────────────────────────────────────────────

# Theme color → shade k (0 … 1): deep at the base, the theme color, almost white at the tip.
# Same formula as scripts/make-bloom.py.  _bgu_ramp "r;g;b" k → REPLY "r;g;b"
_bgu_ramp() {
  local -a c=(${(s:;:)1}) a b
  local -F k=$2 m f
  local -i i
  (( m = (c[1] + c[2] + c[3]) / 3.0 ))
  local -a deep=() tip=()
  local -F v
  for i in 1 2 3; do
    (( v = c[i] * 0.58 - (m - c[i]) * 0.7, v = v < 0 ? 0 : (v > 255 ? 255 : v) ))
    deep+=($v) tip+=($(( c[i] + (255 - c[i]) * 0.62 )))
  done
  if (( k < 0.6 )); then a=($deep) b=($c) f=$(( k / 0.6 ))
  else a=($c) b=($tip) f=$(( (k - 0.6) / 0.4 )); fi
  REPLY="$(( int(a[1] + (b[1] - a[1]) * f) ));$(( int(a[2] + (b[2] - a[2]) * f) ));$(( int(a[3] + (b[3] - a[3]) * f) ))"
}

_bgu_shade() {   # <code> <r;g;b> <k> – one pixel color as foreground and background
  _bgu_ramp $2 $3
  lotus_sgr $REPLY
  BGU_FG[$1]=$REPLY
  BGU_BG[$1]="48${REPLY#38}"
}

# Frames from data/bloom.txt and the theme palette (once per run)
_bgu_load() {
  (( ${#BGU_PIX} )) && return
  local line cur=
  for line in "${(@f)$(<$LOTUS_ROOT/data/bloom.txt)}"; do
    [[ $line == \#* ]] && continue
    if [[ $line == % ]]; then BGU_PIX+=("${cur%$'\n'}"); cur=
    else cur+="$line"$'\n'; fi
  done
  local -a px=("${(@f)BGU_PIX[1]}")
  BGU_ART_W=${#px[1]} BGU_ART_H=$(( ${#px} / 2 ))
  local -a th=(${=LOTUS_THEMES[$LOTUS_THEME]:-$LOTUS_THEMES[matcha]})   # logo key accent key2 …
  local -i n
  for n in {0..9}; do _bgu_shade $n $th[1] $(( n / 9.0 )); done
  _bgu_shade y $th[4] 0.45; _bgu_shade Y $th[4] 0.8
  _bgu_shade g $th[2] 0.25; _bgu_shade G $th[2] 0.55
  BGU_ROW=() BGU_MASK=()
}

# One frame as terminal rows: two pixels per cell (▀ ▄ █), colors change only when needed
_bgu_render() {   # <frame number>
  local -a px=("${(@f)BGU_PIX[$1]}")
  local top bot t b want cur out mask ch
  local -i r c
  for (( r = 1; r <= BGU_ART_H; r++ )); do
    top=${px[2*r-1]} bot=${px[2*r]} out= cur=x mask=
    for (( c = 1; c <= BGU_ART_W; c++ )); do
      t=${top[c]} b=${bot[c]}
      if [[ $t == . && $b == . ]]; then want=0 ch=' ' mask+=' '
      elif [[ $b == . ]]; then want=$BGU_FG[$t] ch=▀ mask+=x
      elif [[ $t == . ]]; then want=$BGU_FG[$b] ch=▄ mask+=x
      elif [[ $t == $b ]]; then want=$BGU_FG[$t] ch=█ mask+=x
      else want="$BGU_FG[$t];$BGU_BG[$b]" ch=▀ mask+=x; fi
      [[ $want != $cur ]] && { out+=$'\e[0;'"${want}m"; cur=$want }
      out+=$ch
    done
    BGU_ROW[$1,$r]="$out"$'\e[0m'
    BGU_MASK[$1,$r]=$mask
  done
}

# How far the flower should be open: the share of steps really done. While a step runs it may
# drift up to half a step further (slowing down), real download bytes count exactly.
_bgu_target() {
  local -i n=${#BGU_KEYS} done=0 i
  local -F within=0 frac
  (( BGU_FINISHED )) && { REPLY=1; return }
  for (( i = 1; i <= n; i++ )); do [[ -n ${BGU_TIMES[i]} ]] && (( done++ )); done
  if [[ -n $BGU_CUR ]]; then
    if (( BGU_TOTAL > 0 )); then (( within = 1.0 * BGU_DONE / BGU_TOTAL ))
    else (( within = 0.5 * (1 - exp(-(EPOCHREALTIME - BGU_TS) / 6.0)) )); fi
  fi
  (( frac = (done + within) / (n > 0 ? n : 1) ))
  (( BGU_IMGS > 1 )) && (( frac = (BGU_IMG - 1 + frac) / BGU_IMGS ))
  (( frac > 1 )) && frac=1
  REPLY=$frac
}

# Pollen: specks that leave the petal tips once the flower opens and drift up and outwards
typeset -ga BGU_PV=()
_bgu_pollen() {
  local -i i burst=$1
  local -F side
  local -a nx=() ny=() nl=() nv=()
  if (( burst || (BGU_BLOOM > 0.4 && RANDOM % 100 < 30) )); then
    repeat $(( burst ? 6 : 1 )); do
      (( side = RANDOM % 1000 / 1000.0 - 0.5 ))
      BGU_PX+=($(( BGU_ART_W / 2.0 + side * 18 * BGU_BLOOM )))
      BGU_PY+=($(( BGU_ART_H * (0.55 - 0.3 * BGU_BLOOM) + RANDOM % 100 / 100.0 )))
      BGU_PV+=($(( side * 0.35 )))
      BGU_PL+=(0)
    done
  fi
  for (( i = 1; i <= ${#BGU_PX}; i++ )); do
    (( BGU_PL[i] < 26 && BGU_PY[i] > 0 )) || continue
    nx+=($(( BGU_PX[i] + BGU_PV[i] + sin(BGU_FRAME * 0.4 + i) * 0.15 ))) ny+=($(( BGU_PY[i] - 0.14 )))
    nv+=($BGU_PV[i]) nl+=($(( BGU_PL[i] + 1 )))
  done
  BGU_PX=($nx) BGU_PY=($ny) BGU_PV=($nv) BGU_PL=($nl)
}

# ── One frame ─────────────────────────────────────────────────

# Adds one screen line to $out of the caller: clears the row, then writes at the column
_line() { out+=$'\e['"$1;1H"$'\e[2K'; (( $3 > 0 )) && out+=$'\e['"$1;$3H"; out+=$2 }   # <row> <text> <col>

bg_ui_frame() {
  bg_ui_check
  (( BGU_LIVE )) || return 0
  (( BGU_FRAME++ ))
  if (( BGU_DIRTY )); then
    local -a sz=(${=$(stty size < /dev/tty 2>/dev/null)})
    LINES=${sz[1]:-24} COLUMNS=${sz[2]:-80}
    print -n $'\e[2J'
    BGU_DIRTY=0
  fi
  local -i W=$COLUMNS H=$LINES i x y n
  local d=$'\e['"$LOTUS_C[dim]m" a=$'\e['"$LOTUS_C[accent]m" k=$'\e['"$LOTUS_C[key]m" B=$'\e[1m' R=$'\e[0m'
  local -F now=$EPOCHREALTIME
  # Layout: the title on top like every Lotus screen, the rest centered below it.
  # The flower (and its water) only when there is room for everything.
  local -i art=$(( W >= BGU_ART_W + 8 && H >= BGU_ART_H + 14 ))
  local -i y0=$(( H >= 14 ? 2 : 1 ))
  local -i block=$(( 9 + (art ? BGU_ART_H + 2 : 0) )) free
  (( free = H - y0 - 1 - block, free < 0 ? (free = 0) : 0 ))
  local out=

  # Title, and the image on the right
  local sub=${BGU_SUB:-$BGU_INFO[image]}
  _line $y0 "${a}◇${R} ${B}lotus${R}${d} / ${R}${B}${BGU_TITLE}${R}" 5
  local -i room=$(( W - ${#BGU_TITLE} - 20 ))
  if [[ -n $sub ]] && (( room > 8 )); then
    (( ${#sub} > room )) && sub="…${sub[-(room-1),-1]}"
    out+=$'\e['"$y0;$(( W - ${#sub} - 3 ))H${d}${sub}${R}"
  fi
  y=$(( y0 + 2 + free / 2 ))

  # The flower
  if (( art )); then
    _bgu_target
    local -F target=$REPLY
    (( target > BGU_BLOOM )) && (( BGU_BLOOM += (target - BGU_BLOOM) * (BGU_FINISHED ? 0.3 : 0.1) ))
    local -i f=$(( int(BGU_BLOOM * (${#BGU_PIX} - 1) + 0.5) + 1 ))
    [[ -n ${BGU_ROW[$f,1]} ]] || _bgu_render $f
    x=$(( (W - BGU_ART_W) / 2 + 1 ))
    for (( i = 1; i <= BGU_ART_H; i++ )); do _line $(( y + i - 1 )) "${BGU_ROW[$f,$i]}" $x; done
    # pollen over empty cells
    _bgu_pollen $(( BGU_FINISHED && BGU_FRAME % 5 == 0 ))
    local -i px py
    local mask glyph
    local y2=$'\e['"$LOTUS_C[key2]m"
    for (( i = 1; i <= ${#BGU_PX}; i++ )); do
      (( px = int(BGU_PX[i]) + 1, py = int(BGU_PY[i]) + 1 ))
      (( px >= 1 && px <= BGU_ART_W && py >= 1 && py <= BGU_ART_H )) || continue
      mask=${BGU_MASK[$f,$py]}
      [[ ${mask[px]} == ' ' ]] || continue
      (( BGU_PL[i] < 12 )) && glyph=• || glyph=·
      out+=$'\e['"$(( y + py - 1 ));$(( x + px - 1 ))H${y2}${glyph}${R}"
    done
    # water: ripples that drift, as wide as the leaves
    local water=
    local -i reach=$(( int(6 + 13 * BGU_BLOOM) )) c
    local -F v
    for (( c = 0; c < BGU_ART_W; c++ )); do
      (( v = sin(c * 0.55 - now * 2.6) + 0.6 * sin(c * 0.21 + now * 1.3) ))
      if (( abs(c - BGU_ART_W / 2) > reach + 2 )); then water+=' '
      elif (( v > 1.05 )); then water+="${a}~"
      elif (( v > 0.55 )); then water+="${d}~"
      else water+=' '; fi
    done
    _line $(( y + BGU_ART_H )) "$water$R" $x
    y=$(( y + BGU_ART_H + 2 ))
  fi

  # The current step, its bar, a note
  local -i idx=${BGU_KEYS[(i)$BGU_CUR]} bw=$(( W - 12 > 36 ? 36 : W - 12 ))
  local label glyph2
  local -a spin=(◇ ◈ ◆ ◈)
  if (( BGU_FINISHED )); then
    label="${k}✓${R} ${B}${LOTUS_L[bg_done]}${R}"; n=$(( ${#LOTUS_L[bg_done]} + 2 ))
  elif (( idx <= ${#BGU_KEYS} )); then
    glyph2=${spin[(BGU_FRAME / 3) % 4 + 1]}
    label="${a}${glyph2}${R} ${B}${BGU_LABELS[idx]}${R}"; n=$(( ${#BGU_LABELS[idx]} + 2 ))
  else
    label= n=0
  fi
  _line $y "$label" $(( (W - n) / 2 + 1 ))
  local bar=
  if (( BGU_FINISHED )); then
    bar="${k}${${(l:bw::x:)}//x/━}${R}"
  elif (( BGU_TOTAL > 0 )); then
    local -i fill=$(( BGU_DONE * bw / BGU_TOTAL ))
    (( fill > bw )) && fill=bw
    bar="${k}${${(l:fill::x:)}//x/━}${d}${${(l:bw-fill::x:)}//x/━}${R}"
  else
    # a light that glides back and forth – activity, not a percentage
    local -i span=$(( bw - 6 )) pos
    (( pos = BGU_FRAME % (2 * span), pos > span ? (pos = 2 * span - pos) : 0 ))
    for (( i = 0; i < bw; i++ )); do
      if (( i >= pos && i < pos + 6 )); then bar+="${k}━"
      elif (( i == pos - 1 || i == pos + 6 )); then bar+="${a}━"
      else bar+="${d}━"; fi
    done
    bar+=$R
  fi
  _line $(( y + 1 )) "$bar" $(( (W - bw) / 2 + 1 ))
  local note=$BGU_NOTE
  if (( BGU_TOTAL > 0 )); then
    note="$(( BGU_DONE * 100 / BGU_TOTAL ))% · $(( BGU_DONE / 1048576 )) / $(( BGU_TOTAL / 1048576 )) MB${note:+ · $note}"
  fi
  (( ${#note} > W - 8 )) && note="${note[1,W-9]}…"
  _line $(( y + 2 )) "${d}${note}${R}" $(( (W - ${#note}) / 2 + 1 ))

  # All steps in one line (or "3 / 5" when it does not fit)
  local strip= plain= s
  for (( i = 1; i <= ${#BGU_KEYS}; i++ )); do
    s=$BGU_SHORT[i]
    (( i > 1 )) && { strip+="   "; plain+="   " }
    if [[ -n ${BGU_TIMES[i]} ]] || (( BGU_FINISHED )); then strip+="${k}✓${R} $s"
    elif (( i == idx )); then strip+="${a}◆${R} ${B}$s${R}"
    else strip+="${d}· $s${R}"; fi
    plain+="x $s"
  done
  if (( ${#plain} > W - 6 )); then
    plain="$(( idx <= ${#BGU_KEYS} ? idx : ${#BGU_KEYS} )) / ${#BGU_KEYS}"
    strip="${d}${plain}${R}"
  fi
  _line $(( y + 4 )) "$strip" $(( (W - ${#plain}) / 2 + 1 ))

  # Model · backend · size · time, and how to stop
  local info= key
  for key in model backend resolution python; do [[ -n $BGU_INFO[$key] ]] && info+="${info:+ · }$BGU_INFO[$key]"; done
  _bgu_fmt_secs $(( now - BGU_T0 ))
  info+="${info:+ · }$REPLY"
  (( ${#info} > W - 8 )) && info="${info[1,W-9]}…"
  _line $(( y + 6 )) "${d}${info}${R}" $(( (W - ${#info}) / 2 + 1 ))
  _line $(( y + 8 )) "${d}${LOTUS_L[bg_ctrl_c]}${R}" $(( (W - ${#LOTUS_L[bg_ctrl_c]}) / 2 + 1 ))
  print -rn -- "$out"
}

# Lines from a pipe, waiting at most <seconds>:  bg_read_lines <fd> <seconds> → reply (complete lines)
# Status 1 at the end of the stream. sysread tells a timeout (4) from the end (5), read cannot.
typeset -g _BG_BUF=
bg_read_lines() {
  local chunk
  local -i st
  reply=()
  sysread -t $2 -i $1 chunk; st=$?
  if (( st == 0 )); then
    _BG_BUF+=$chunk
    if [[ $_BG_BUF == *$'\n'* ]]; then
      reply=("${(@f)${_BG_BUF%$'\n'*}}")
      _BG_BUF=${_BG_BUF##*$'\n'}
    fi
    return 0
  fi
  (( st == 4 )) && return 0                     # nothing new yet
  (( st == 2 && ERRNO == 4 )) && return 0       # interrupted (resize, ctrl-c): look again
  [[ -n $_BG_BUF ]] && reply=("${(@f)_BG_BUF}")
  _BG_BUF=
  return 1
}

# Short pause between frames that still notices a key or resize
bg_ui_tick() { zselect -t ${1:-8} 2>/dev/null || true; }

# ctrl-c only sets a flag (see _bg_interrupt); the loops call this to stop cleanly
bg_ui_check() { (( BG_CANCEL )) && _bg_cancel; return 0 }
