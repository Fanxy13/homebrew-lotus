# lotus – the progress screen for Remove BG: a small lotus that shimmers, the stages with their
# times, live details. Bars only show real numbers (download sizes); while the model works the bar
# is a moving light, never a made-up percentage.
# Without a terminal (pipes, scripts, -V) it prints one plain line per stage instead.
# Ctrl-C, errors and resizing always leave the terminal as it was: cursor back, echo back, main screen.

zmodload zsh/zselect 2>/dev/null
zmodload zsh/mathfunc 2>/dev/null
zmodload zsh/system 2>/dev/null

typeset -ga BGU_KEYS=() BGU_LABELS=() BGU_TIMES=() BGU_INFO_KEYS=()
typeset -gA BGU_INFO=()
typeset -g BGU_TITLE= BGU_CUR= BGU_NOTE= BGU_STTY= BGU_SUB=
typeset -gi BGU_LIVE=0 BGU_ON=0 BGU_DIRTY=1 BGU_FRAME=0 BGU_DONE=0 BGU_TOTAL=0
typeset -gF BGU_T0=0 BGU_TS=0

# Lotus drawing (5 rows, 19 columns); the shimmer runs over it from left to right
typeset -ga BGU_ART=(
  "         .         "
  "       .' '.       "
  " .'.  '  :  '  .'. "
  " '. '.   :   .' .' "
  "   '-.._ : _..-'   "
)

# bg_ui_begin <title> "key|Label" …
bg_ui_begin() {
  BGU_TITLE=$1; shift
  BGU_KEYS=() BGU_LABELS=() BGU_TIMES=() BGU_INFO_KEYS=() BGU_INFO=() BGU_CUR= BGU_NOTE= BGU_SUB= BGU_DONE=0 BGU_TOTAL=0
  local s
  for s in "$@"; do BGU_KEYS+=(${s%%|*}); BGU_LABELS+=("${s#*|}"); BGU_TIMES+=(""); done
  BGU_T0=$EPOCHREALTIME BGU_TS=$EPOCHREALTIME BGU_FRAME=0 BGU_DIRTY=1
  BGU_LIVE=0
  [[ -t 1 && -z $LOTUS_VERBOSE ]] && ui_has_tty && BGU_LIVE=1
  BGU_ON=1
  if (( BGU_LIVE )); then
    print -n $'\e[?1049h\e[?25l\e[2J'
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
    print -n $'\e[?25h\e[?1049l'
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
  lotus_log DEBUG bg "Stage: $key"
}

bg_ui_info() {    # <key> <value>  (shown under the stages, in the order they arrive)
  (( ${BGU_INFO_KEYS[(Ie)$1]} )) || BGU_INFO_KEYS+=($1)
  BGU_INFO[$1]=$2
}

# Next image of a batch: the stages from <key> on start again
bg_ui_reset_from() {
  local -i i=${BGU_KEYS[(i)$1]}
  for (( ; i <= ${#BGU_KEYS}; i++ )); do BGU_TIMES[i]=; done
  BGU_CUR=
}

bg_ui_note() { BGU_NOTE=$1 }                   # small line under the current stage
bg_ui_sub() { BGU_SUB=$1 }                     # second title line (e.g. "2 of 14 · photo.jpg")
bg_ui_progress() { BGU_DONE=$1 BGU_TOTAL=$2 }  # real progress (bytes), 0 0 = none

# All stages done (marks the current one as finished)
bg_ui_complete() {
  bg_ui_stage __end
  BGU_CUR=
  (( BGU_LIVE )) && bg_ui_frame
}

_bgu_fmt_secs() { (( $1 < 60 )) && printf -v REPLY '%.1fs' $1 || printf -v REPLY '%dm %02ds' $(( int($1) / 60 )) $(( int($1) % 60 )) }

_bgu_bar() {   # <width> → REPLY: a real bar when BGU_TOTAL is known, a moving light otherwise
  local -i w=$1 i fill
  local k=$'\e['"$LOTUS_C[key]m" d=$'\e['"$LOTUS_C[dim]m" a=$'\e['"$LOTUS_C[accent]m" R=$'\e[0m' out=
  if (( BGU_TOTAL > 0 )); then
    (( fill = BGU_DONE * w / BGU_TOTAL, fill > w ? (fill = w) : 0 ))
    out="${k}${${(l:fill::x:)}//x/█}${R}${d}${${(l:w-fill::x:)}//x/░}${R}"
    local pct=$(( BGU_DONE * 100 / BGU_TOTAL ))
    REPLY="$out ${a}${(l:3:)pct}%${R} ${d}$(( BGU_DONE / 1048576 )) / $(( BGU_TOTAL / 1048576 )) MB${R}"
    return
  fi
  # ping-pong light, 6 cells wide
  local -i span=$(( w > 8 ? w - 6 : 2 ))
  local -i pos=$(( BGU_FRAME % (2 * span) ))
  (( pos > span )) && pos=$(( 2 * span - pos ))
  for (( i = 0; i < w; i++ )); do
    if (( i >= pos && i < pos + 6 )); then out+="${k}━"
    elif (( i == pos - 1 || i == pos + 6 )); then out+="${a}━"
    else out+="${d}━"; fi
  done
  REPLY="$out$R"
}

# The art row <n>, with the shimmer at the current frame
_bgu_art() {
  local line=${BGU_ART[$1]} out= c
  local -i i n=${#line}
  local -i phase=$(( (BGU_FRAME * 2) % (n + 30) - 10 ))
  local k=$'\e[1;'"$LOTUS_C[key]m" a=$'\e['"$LOTUS_C[logo]m" d=$'\e['"$LOTUS_C[accent]m"
  for (( i = 1; i <= n; i++ )); do
    c=${line[i]}
    if [[ $c == ' ' ]]; then out+=' '; continue; fi
    if (( i >= phase - 1 && i <= phase + 1 )); then out+="${k}$c"
    elif (( i >= phase - 4 && i <= phase + 4 )); then out+="${a}$c"
    else out+="${d}$c"; fi
  done
  # the heart of the flower breathes
  if (( $1 == 1 )); then
    local -a beat=(· • ◇ ◈ ◆ ◈ ◇ •)
    out="${out/./${k}${beat[(BGU_FRAME / 3) % 8 + 1]}}"
  fi
  REPLY="$out"$'\e[0m'
}

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
  local -i W=$COLUMNS H=$LINES i bw
  local d=$'\e['"$LOTUS_C[dim]m" a=$'\e['"$LOTUS_C[accent]m" k=$'\e[1;'"$LOTUS_C[key]m" B=$'\e[1m' R=$'\e[0m'
  local -F now=$EPOCHREALTIME
  local -a left=() right=()
  local -i art=$(( W >= 74 && H >= 18 ))
  local out=$'\e[H\e[K\n'"    ${a}◇${R} ${B}lotus${R}${d} / ${R}${B}${BGU_TITLE}${R}"$'\e[K\n'
  [[ -n $BGU_SUB ]] && out+="    ${d}${BGU_SUB[1,W-6]}${R}"$'\e[K\n' || out+=$'\e[K\n'
  out+=$'\e[K\n'
  (( bw = W >= 74 ? 22 : (W >= 50 ? 16 : 10) ))

  # Stages
  local glyph lbl t
  local -a spin=(◇ ◈ ◆ ◈)
  for (( i = 1; i <= ${#BGU_KEYS}; i++ )); do
    lbl=${BGU_LABELS[i]}
    if [[ -n ${BGU_TIMES[i]} ]]; then
      _bgu_fmt_secs ${BGU_TIMES[i]}
      right+=("${k}✓${R} ${(r:24:)lbl[1,24]} ${d}${REPLY}${R}")
    elif [[ ${BGU_KEYS[i]} == $BGU_CUR ]]; then
      glyph=${spin[(BGU_FRAME / 2) % 4 + 1]}
      _bgu_bar $bw
      right+=("${a}${glyph}${R} ${B}${(r:24:)lbl[1,24]}${R} $REPLY")
      [[ -n $BGU_NOTE ]] && right+=("  ${d}${BGU_NOTE[1,W-12]}${R}")
    else
      right+=("${d}·${R} ${d}${lbl}${R}")
    fi
  done

  if (( art )); then
    for (( i = 1; i <= ${#BGU_ART}; i++ )); do _bgu_art $i; left+=("$REPLY"); done
    local -i rows=$(( ${#left} > ${#right} ? ${#left} : ${#right} ))
    for (( i = 1; i <= rows; i++ )); do
      out+="    ${left[i]:-${(l:19:)}}      ${right[i]}"$'\e[K\n'
    done
  else
    for (( i = 1; i <= ${#right}; i++ )); do out+="    ${right[i]}"$'\e[K\n'; done
  fi

  # Details
  out+=$'\e[K\n'
  local key
  for key in $BGU_INFO_KEYS; do
    out+="    ${d}${(r:12:)${LOTUS_L[bg_i_$key]:-$key}}${R}${BGU_INFO[$key][1,W-18]}"$'\e[K\n'
  done
  _bgu_fmt_secs $(( now - BGU_T0 ))
  out+="    ${d}${(r:12:)LOTUS_L[bg_i_elapsed]}${R}$REPLY"$'\e[K\n'
  out+=$'\e[K\n'"    ${d}${LOTUS_L[bg_ctrl_c]}${R}"$'\e[K\e[J'
  print -rn -- $out
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
