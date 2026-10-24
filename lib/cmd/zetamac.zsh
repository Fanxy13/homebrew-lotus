# lotus – the math game of the pets: /zetamac [seconds] [easy|normal|hard] (sourced by lib/cmd/pets.zsh)
#
# Like the Arithmetic Game on arithmetic.zetamac.com: as many problems as you can in 120 seconds, and an answer
# counts as soon as it is right – no Enter. "normal" has Zetamac's default ranges: (2–100) + (2–100) and
# (2–12) × (2–100), subtraction and division are these in reverse, so every answer is a whole number above 1.
# Every right answer is a bite for each of your pets: it keeps them full longer, up to two days.
# The best score per level and time is kept in ~/.local/state/lotus/zetamac.tsv.

# addition: left min max, right min max · multiplication: left min max, right min max
typeset -gA ZM_RANGE=(
  easy   '2 20 2 20 2 10 2 10'
  normal '2 100 2 100 2 12 2 100'
  hard   '10 500 10 500 2 20 10 100'
)
typeset -gA ZM_MINUTES=(easy 10 normal 15 hard 20)   # how long one right answer keeps a pet full
typeset -gi ZM_FULL_MAX=48                          # hours – fuller than that a pet does not get
typeset -g ZM_Q= ZM_A=

# A random number from $1 to $2 → REPLY
_zm_rand() { REPLY=$(( $1 + RANDOM % ($2 - $1 + 1) )) }

# A new problem → ZM_Q (what is shown), ZM_A (the answer); never the same one twice in a row
_zm_problem() {
  local spec=${ZM_RANGE[$1]:-$ZM_RANGE[normal]} q last=$ZM_Q
  local -a r=(${=spec})
  local -i a b op try
  for (( try = 0; try < 5; try++ )); do
    (( op = RANDOM % 4 ))
    if (( op < 2 )); then
      _zm_rand $r[1] $r[2]; a=$REPLY; _zm_rand $r[3] $r[4]; b=$REPLY
      if (( op == 0 )); then q="$a + $b" ZM_A=$(( a + b ))
      else q="$(( a + b )) – $a" ZM_A=$b; fi
    else
      _zm_rand $r[5] $r[6]; a=$REPLY; _zm_rand $r[7] $r[8]; b=$REPLY
      if (( op == 2 )); then q="$a × $b" ZM_A=$(( a * b ))
      else q="$(( a * b )) ÷ $a" ZM_A=$b; fi
    fi
    [[ $q != $last ]] && break
  done
  ZM_Q=$q
}

# The pets eat what was earned: <right answers> <level> → reply = minutes each pet is full now, status 1: nothing to eat
# A pet is hungry 12 hours after its last meal (_pet_mood) – a big meal moves that meal into the future.
_zm_feed() {
  local -i score=$1 i fed full max=$(( ZM_FULL_MAX * 3600 ))
  local -i gain=$(( score * ${ZM_MINUTES[$2]:-15} * 60 ))
  local n
  reply=()
  (( score > 0 && ${#PET_N} )) || return 1
  for (( i = 1; i <= ${#PET_N}; i++ )); do
    n=${(L)PET_N[i]}
    fed=${PET_FED[$n]:-$PET_T[i]}
    (( full = fed + 43200 - EPOCHSECONDS ))
    (( full < 0 )) && full=0
    (( full += gain, full > max && (full = max) ))
    PET_FED[$n]=$(( EPOCHSECONDS + full - 43200 ))
    PET_COUNT[$n]=$(( ${PET_COUNT[$n]:-0} + 1 ))
    reply+=($(( (full + 30) / 60 )))
  done
  _pet_save_state
  lotus_log INFO pets "Math game: $score right ($2) – the pets ate"
}

# Keeps the best score: <level> <seconds> <score> → REPLY = the best before (0: none yet)
_zm_record() {
  local file=$LOTUS_STATE/zetamac.tsv line out=
  local -a f
  local -i games=0
  REPLY=0
  if [[ -r $file ]]; then
    for line in "${(@f)$(<$file)}"; do
      f=("${(@ps:\t:)line}")
      [[ $f[3] == <-> ]] || continue
      if [[ $f[1] == $1 && $f[2] == $2 ]]; then REPLY=$f[3] games=${f[4]:-0}
      else out+=$line$'\n'; fi
    done
  fi
  local -i best=$(( $3 > REPLY ? $3 : REPLY ))
  out+="$1"$'\t'"$2"$'\t'"$best"$'\t'"$(( games + 1 ))"$'\n'
  { zf_mkdir -p $LOTUS_STATE && print -rn -- $out >| $file } 2>/dev/null
  return 0
}

# How long, in words: <minutes> → REPLY
_zm_duration() {
  local -i m=$1
  if (( m < 60 )); then REPLY=${LOTUS_L[zm_minutes]//\%s/$m}
  elif (( m < 120 )); then REPLY=$LOTUS_L[zm_hour]
  else REPLY=${LOTUS_L[zm_hours]//\%s/$(( m / 60 ))}; fi
}

lotus_zetamac() {
  setopt localoptions extendedglob
  local level=normal arg
  local -i secs=120
  for arg in "$@"; do
    case ${(L)arg} in
      <10-600>) secs=$arg ;;
      easy|leicht|facile|facil|fácil) level=easy ;;
      normal) level=normal ;;
      hard|schwer|difficile|dificil|difícil) level=hard ;;
      *) ui_error "${LOTUS_L[zm_bad]//\%s/$arg}" "" "$LOTUS_L[zm_usage]"; return 1 ;;
    esac
  done
  [[ -t 1 ]] && ui_has_tty || { ui_error "$LOTUS_L[zm_tty]" "" "$LOTUS_L[zm_usage]"; return 1 }
  _pet_load; _pet_species
  local -i rc
  while :; do
    _zm_play $level $secs; rc=$?
    (( rc == 130 )) && break
    _zm_after $level $secs $ZM_SCORE $rc || break
  done
  print -n $'\e[H\e[2J'
  return 0
}

typeset -gi ZM_SCORE=0

# One game → ZM_SCORE; status 0: the time is up, 1: ended with Esc, 130: Ctrl-C
_zm_play() {
  local level=$1 input= label=$LOTUS_L[zm_$1] line
  local -i secs=$2 left shown=-1 eating=0 ended=0 i pos=0   # pos: the digits left of the cursor
  local -F end now eat_until=0
  local -a idle eat top
  _pet_begin || return 130
  # the pets watch and eat along – when the window is tall enough
  if (( ${#PET_N} && ${LINES:-24} >= 24 )); then
    idle=("${(@f)$(_pet_lineup idle)}") eat=("${(@f)$(_pet_lineup eat)}")
  fi
  top=("${(@f)$(ui_hero "$LOTUS_L[zm_title]" "${${LOTUS_L[zm_sub]/\%s/$secs}/\%s/$label}")}")
  local a=$'\e[1;'"$LOTUS_C[accent]m" k=$'\e[1;'"$LOTUS_C[key]m" d=$'\e['"$LOTUS_C[dim]m" b=$'\e['"$LOTUS_C[border]m" r=$'\e[0m'
  local task bar
  local -i boxw=30 full
  lotus_line $boxw; bar=$REPLY
  ZM_SCORE=0 ZM_Q=
  _zm_problem $level
  (( end = EPOCHREALTIME + secs ))
  print -n $'\e[H\e[2J'
  while :; do
    now=$EPOCHREALTIME
    (( left = end - now + 0.999 ))
    (( left <= 0 )) && break
    (( eating = now < eat_until ))
    # draw everything again – synchronized, so nothing flickers
    {
      print -n $'\e[?2026h\e[H'
      for line in "${top[@]}"; do print -r -- "$line"$'\e[K'; done
      print -r -- $'\e[K'
      if (( ${#idle} )); then
        if (( eating )); then for line in "${eat[@]}"; do print -r -- "$line"$'\e[0m\e[K'; done
        else for line in "${idle[@]}"; do print -r -- "$line"$'\e[0m\e[K'; done; fi
        print -r -- $'\e[K'
      fi
      # the time as a bar that runs out, the score next to it
      (( full = (end - now) * 30 / secs + 0.5 ))
      print -r -- "    $d${LOTUS_L[zm_left]}$r $k${(l:3:)left} s$r  $a${${(l:full::x:)}//x/━}$b${${(l:30 - full::x:)}//x/─}$r   $d${LOTUS_L[zm_score]}$r $k$ZM_SCORE$r"$'\e[K'
      print -r -- $'\e[K'
      # the problem in a box
      task="$ZM_Q = $input"
      print -r -- "    $b╭${bar}╮$r"$'\e[K'
      print -r -- "    $b│$r    $a$ZM_Q = $r${_UI_B}${input[1,pos]}$r$a▏$r${_UI_B}${input[pos+1,-1]}$r${(l:boxw - ${#task} - 5:)}$b│$r"$'\e[K'
      print -r -- "    $b╰${bar}╯$r"$'\e[K'
      print -r -- $'\e[K'
      print -r -- "    $d$LOTUS_L[zm_hint]$r"$'\e[K'
      print -r -- "    $d$LOTUS_L[zm_keys]$r"$'\e[K'
      print -n $'\e[J\e[?2026l'
    }
    ui_keyx 0.05
    (( UI_INT )) && { _pet_end; return 130 }
    # a digit goes where the cursor is: the last digit first, then ← and the ones before it
    case $REPLY in
      [0-9]) (( ${#input} < 7 )) && { input="${input[1,pos]}$REPLY${input[pos+1,-1]}"; (( pos++ )) } ;;
      back)  (( pos > 0 )) && { input="${input[1,pos-1]}${input[pos+1,-1]}"; (( pos-- )) } ;;
      left)  (( pos > 0 )) && (( pos-- )) ;;
      right) (( pos < ${#input} )) && (( pos++ )) ;;
      home)  pos=0 ;;
      end)   pos=${#input} ;;
      esc)   ended=1; break ;;
    esac
    if [[ -n $input ]] && (( 10#$input == ZM_A )); then
      (( ZM_SCORE++ ))
      input= pos=0
      _zm_problem $level
      (( eat_until = EPOCHREALTIME + 0.3 ))
    fi
  done
  _pet_end
  return $ended
}

# After a game: the score, the record, the pets eat. Enter plays again → status 0, Esc → status 1
_zm_after() {
  local level=$1 label=$LOTUS_L[zm_$1] text key
  local -i secs=$2 score=$3 ended=$4 best idx=1 i
  _zm_record $level $secs $score; best=$REPLY
  print -n $'\e[H\e[2J'
  ui_hero "$LOTUS_L[zm_title]" "${${LOTUS_L[zm_sub]/\%s/$secs}/\%s/$label}"
  local k=$'\e[1;'"$LOTUS_C[key]m" d=$'\e['"$LOTUS_C[dim]m" r=$'\e[0m'
  (( ended )) && text=$LOTUS_L[zm_stopped] || text=$LOTUS_L[zm_over]
  text+="  $k${LOTUS_L[zm_result]//\%s/$score}$r"
  if (( score > best && best > 0 )); then text+="  $k$LOTUS_L[zm_new_best]$r"
  elif (( best > 0 )); then text+="  $d${LOTUS_L[zm_best]//\%s/$best}$r"; fi
  print -r -- "    $text"
  print
  if (( ${#PET_N} )); then
    (( idx = RANDOM % ${#PET_N} + 1 ))
    _pet_kind $idx
    local snack=${${${PET_INFO[$REPLY,snack]:-o}//[^ -~]/}[1,6]}
    _pet_begin
    PET_DRAWN=0
    if _zm_feed $score $level; then
      _zm_duration $reply[idx]
      (( ${#PET_N} > 1 )) && key=zm_fed_n || key=zm_fed_1
      local bites=${LOTUS_L[zm_bites]//\%s/$score}
      (( score == 1 )) && bites=$LOTUS_L[zm_bite]
      text=${${LOTUS_L[$key]/\%s/$bites}/\%s/$REPLY}
      if [[ -n $PET_TTY ]]; then
        for (( i = 14; i >= 0 && ! UI_INT; i -= 2 )); do
          _pet_block $idx idle -1 plain "${(l:i:)}$snack"; _pet_paint
          ui_keyx 0.05
        done
        for (( i = 0; i < 6 && ! UI_INT; i++ )); do
          (( i % 2 )) && key=happy || key=eat
          _pet_block $idx $key -1 plain "${${(M)key:#eat}:+nom}"; _pet_paint
          ui_keyx 0.16
        done
      fi
      _pet_speak $idx "$text" happy
    else
      _pet_speak $idx "$LOTUS_L[zm_none]" idle
    fi
    _pet_end
  else
    ui_dim "  $LOTUS_L[zm_nopets]"
  fi
  print
  ui_dim "  $LOTUS_L[zm_again]"
  while :; do
    ui_key
    case $REPLY in
      enter) return 0 ;;
      quit)  return 1 ;;
    esac
  done
}
