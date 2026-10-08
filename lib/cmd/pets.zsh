# lotus – pets: little pixel friends that live in your terminal (feature "pets", up to 3).
#
#   /pets                     adopt, talk, feed, rename, personality, settings
#   <name> [message]          type a pet's name in the shell to talk to it (→ lotus pet <name> …)
#   /feed [name]              feed a pet – pets get hungry after half a day (they never get ill)
#   /help                     your pet asks where you need help and shows the commands
#   lotus pets add [file]     add your own kind of pet from the prompt on the website (default: clipboard)
#
# Kinds of pets are plain text files: data/pets/*.pet (cat, dog) and your own in ~/.config/lotus/pets/.
# They are read as data, never run; their drawings are ASCII and block pixels (▀ … ▟) only. Adopted pets live in
# ~/.config/lotus/pets.tsv, hunger and what they remember in ~/.local/state/lotus/.
# Pets think with Apple Intelligence on this Mac (or the AI of /ai, or not at all).

lotus_cmd_pets() {
  local cmd=$1; shift
  lotus_lang_group pets
  case $cmd in
    pet)  lotus_pet_talk "$@" ;;
    feed) lotus_pet_feed "$@" ;;
    *)
      case $1 in
        add)        shift; lotus_pets_add "$@" ;;
        adopt)      shift; lotus_pets_adopt "$@" ;;
        greet)      lotus_pet_greet ;;
        ''|list)    lotus_pets_screen ;;
        *)          lotus_pet_talk "$@" ;;
      esac ;;
  esac
}

zmodload zsh/zselect 2>/dev/null

# ── Kinds of pets (.pet files) ────────────────────────────────

typeset -ga PET_KINDS=()
typeset -gA PET_INFO=() PET_ART=() PET_AW=() PET_AH=()

_pet_species() {
  (( ${#PET_KINDS} )) && return 0
  local f
  for f in $LOTUS_ROOT/data/pets/*.pet(N) $LOTUS_CONF/pets/*.pet(N); do _pet_parse $f || lotus_log WARN pets "Not a pet: $f ($REPLY)"; done
  return 0
}

# Reads one .pet file – as data, nothing in it is run. Drawings keep plain ASCII and the block
# characters ▀ … ▟ (pixel sprites, two by two pixels each) only; other values lose control characters. → REPLY = the kind (status 1: REPLY = what is wrong)
_pet_parse() {
  setopt localoptions extendedglob
  local file=$1 line frame= key val sp
  local -A info=() art=()
  [[ -f $file && -r $file ]] || { REPLY="cannot read the file"; return 1 }
  local -a st
  zstat -A st +size -- $file 2>/dev/null
  (( ${st[1]:-0} < 16000 )) || { REPLY="the file is too big"; return 1 }
  for line in "${(@f)$(<$file)}"; do
    line=${${line%$'\r'}//$'\t'/  }
    if [[ $line == \[[a-z]##\] ]]; then
      frame=${${line#\[}%\]} art[$frame]=
      continue
    fi
    if [[ -z $frame ]]; then
      line=${line##[[:space:]-]#}
      [[ $line == [a-z_]##:* ]] || continue                 # comments, empty lines
      key=${line%%:*} val=${line#*:}
      info[$key]=${${${val//[[:cntrl:]]/}##[[:space:]]#}%%[[:space:]]#}
    else
      art[$frame]+=${${line//[^ -~▀-▟]/}%%[[:space:]]#}$'\n'
    fi
  done
  sp=${(L)info[species]}
  [[ $sp == [a-z][a-z0-9-]# ]] && (( ${#sp} <= 16 )) || { REPLY="species: is missing"; return 1 }
  [[ -n ${art[idle]//[[:space:]]/} ]] || { REPLY="the drawing [idle] is missing"; return 1 }
  local -i w=0 h=0
  local -a rows
  for frame in ${(k)art}; do
    art[$frame]=${art[$frame]%%$'\n'#}
    rows=("${(@f)art[$frame]}")
    (( ${#rows} > 8 )) && { REPLY="[$frame] is higher than 8 lines"; return 1 }
    for line in $rows; do
      (( ${#line} > 24 )) && { REPLY="[$frame] is wider than 24 characters"; return 1 }
      (( ${#line} > w )) && w=${#line}
    done
    (( ${#rows} > h )) && h=${#rows}
  done
  (( ${PET_KINDS[(Ie)$sp]} )) || PET_KINDS+=($sp)
  for key in ${(k)info}; do PET_INFO[$sp,$key]=${info[$key][1,300]}; done
  for frame in ${(k)art}; do PET_ART[$sp,$frame]=$art[$frame]; done
  PET_AW[$sp]=$w PET_AH[$sp]=$h PET_INFO[$sp,file]=$file
  REPLY=$sp
}

# The name of a kind in the interface language → REPLY
_pet_kind_label() { REPLY=${PET_INFO[$1,label_$LOTUS_LANG]:-${PET_INFO[$1,label]:-${(C)1}}} }

# A few words about a kind, in the interface language → REPLY
_pet_kind_about() {
  REPLY=${PET_INFO[$1,about_$LOTUS_LANG]:-${PET_INFO[$1,about]}}
  [[ -n $REPLY ]] || REPLY=${${PET_INFO[$1,personality]}[1,48]}
}

# ── Your pets ─────────────────────────────────────────────────

_pet_name_ok() { [[ $1 == [[:alpha:]][[:alnum:]_-]# ]] && (( ${#1} <= 16 )) }

_pet_load() {
  (( ${+PET_N} )) && return 0
  typeset -ga PET_N=() PET_K=() PET_P=() PET_T=()
  typeset -gA PET_FED=() PET_COUNT=()
  local line
  local -a f
  if [[ -r $LOTUS_CONF/pets.tsv ]]; then
    for line in "${(@f)$(<$LOTUS_CONF/pets.tsv)}"; do
      [[ $line == \#* || -z $line ]] && continue
      f=("${(@ps:\t:)line}")
      _pet_name_ok "$f[1]" || continue
      (( ${#PET_N} >= 3 )) && break
      PET_N+=("$f[1]") PET_K+=("${f[2]:-cat}") PET_P+=("$f[3]") PET_T+=("${f[4]:-$EPOCHSECONDS}")
    done
  fi
  if [[ -r $LOTUS_STATE/pets.tsv ]]; then
    for line in "${(@f)$(<$LOTUS_STATE/pets.tsv)}"; do
      f=("${(@ps:\t:)line}")
      [[ $f[2] == <-> ]] || continue
      PET_FED[${(L)f[1]}]=$f[2] PET_COUNT[${(L)f[1]}]=${f[3]:-0}
    done
  fi
}

_pet_save() {
  zf_mkdir -p $LOTUS_CONF
  local out="# Lotus pets: name, kind, personality (empty: the usual one of the kind), adopted (epoch). Edit with /pets."$'\n'
  local -i i
  for (( i = 1; i <= ${#PET_N}; i++ )); do
    out+="$PET_N[i]"$'\t'"$PET_K[i]"$'\t'"${PET_P[i]//[[:cntrl:]]/ }"$'\t'"$PET_T[i]"$'\n'
  done
  print -rn -- $out >| $LOTUS_CONF/pets.tsv
  _pet_save_state
  lotus_log INFO pets "Pets: ${(j:, :)PET_N:-none}"
}

_pet_save_state() {
  { zf_mkdir -p $LOTUS_STATE && chmod 700 $LOTUS_STATE } 2>/dev/null || return 0
  local out= n
  local -a now=(${(L)PET_N})
  for n in ${(k)PET_FED}; do
    (( ${now[(Ie)$n]} )) && out+="$n"$'\t'"$PET_FED[$n]"$'\t'"${PET_COUNT[$n]:-0}"$'\n'
  done
  print -rn -- $out >| $LOTUS_STATE/pets.tsv
}

_pet_find() {   # <name> → REPLY = index (case does not matter), status 1 when there is none
  local -i i
  for (( i = 1; i <= ${#PET_N}; i++ )); do [[ ${(L)PET_N[i]} == ${(L)1} ]] && { REPLY=$i; return 0 }; done
  REPLY=0
  return 1
}

# The kind of a pet; one whose file is gone becomes a cat again
_pet_kind() { REPLY=$PET_K[$1]; [[ -n ${PET_ART[$REPLY,idle]} ]] || REPLY=cat }

# Hours since the last meal → REPLY
_pet_hours() {
  local fed=${PET_FED[${(L)PET_N[$1]}]:-$PET_T[$1]}
  [[ $fed == <-> ]] || fed=$EPOCHSECONDS
  REPLY=$(( (EPOCHSECONDS - fed) / 3600 ))
}

# asleep (11 pm – 6 am) · starving · hungry · happy → REPLY
_pet_mood() {
  local -i hour
  strftime -s hour %H $EPOCHSECONDS
  _pet_hours $1
  if (( hour >= 23 || hour < 6 )) && [[ $2 != awake ]]; then REPLY=asleep
  elif (( REPLY >= 24 )); then REPLY=starving
  elif (( REPLY >= 12 )); then REPLY=hungry
  else REPLY=happy; fi
}

_pet_status() {   # one short line about a pet → REPLY
  local mood
  _pet_mood $1; mood=$REPLY
  _pet_hours $1
  case $mood in
    starving) REPLY=$LOTUS_L[pt_starving] ;;
    hungry)   REPLY=$LOTUS_L[pt_hungry] ;;
    *)        (( REPLY < 1 )) && REPLY=$LOTUS_L[pt_fed_now] || REPLY=${LOTUS_L[pt_fed_h]//\%s/$REPLY}
              [[ $mood == asleep ]] && REPLY+=" · $LOTUS_L[pt_asleep]" ;;
  esac
}

# Each pet keeps its own color: the theme's logo, greeting and key colors
_pet_color() { local -a roles=(logo salute key); REPLY=$LOTUS_C[${roles[$1]:-logo}] }

# ── Drawing ───────────────────────────────────────────────────

# The drawing of a pet, every line as wide as the widest drawing of its kind and the feet on the
# ground (shorter drawings get empty lines on top) → reply
_pet_art() {
  _pet_kind $1
  local kind=$REPLY line
  local -a rows=("${(@f)${PET_ART[$kind,$2]:-$PET_ART[$kind,idle]}}")
  local -i w=$PET_AW[$kind] h=$PET_AH[$kind] i
  reply=()
  for (( i = ${#rows}; i < h; i++ )); do reply+=("${(l:w:: :)}"); done
  for line in "${rows[@]}"; do reply+=("${(r:w:: :)line}"); done
}

# Word wrap; very long words are cut into pieces → reply
_pet_wrap() {
  local word line=
  local -i w=$2
  reply=()
  for word in ${=1}; do
    while (( ${#word} > w )); do
      [[ -n $line ]] && { reply+=("$line"); line= }
      reply+=("${word[1,w]}"); word=${word[w+1,-1]}
    done
    [[ -z $word ]] && continue
    if (( ${#line} && ${#line} + ${#word} + 1 > w )); then reply+=("$line"); line=$word
    else line+=${line:+ }$word; fi
  done
  [[ -n $line ]] && reply+=("$line")
}

# Width for the speech bubble next to a pet → REPLY
_pet_bubble_width() {
  _pet_kind $1
  local -i aw=$PET_AW[$REPLY] cols=${COLUMNS:-80}
  (( cols > 0 )) || cols=80
  (( aw < ${#PET_N[$1]} )) && aw=${#PET_N[$1]}
  REPLY=$(( cols - aw - 12 ))
  (( REPLY > 54 )) && REPLY=54
  (( REPLY < 12 )) && REPLY=12
}

# A pet with a speech bubble → reply (lines)
#   _pet_block <pet> <drawing> <characters shown, -1 = all> <style> <line>…
#   style: bubble · plain (the lines without a bubble, e.g. a snack flying in) · none
_pet_block() {
  local -i idx=$1 shown=$3 i k iw=0 rows colw
  local frame=$2 style=$4 name=$PET_N[$1] line
  shift 4
  local -a text=("$@") art bub
  _pet_art $idx $frame; art=("${reply[@]}")
  _pet_kind $idx
  local -i aw=$PET_AW[$REPLY] ah=${#art}
  (( colw = aw > ${#name} ? aw : ${#name} ))
  _pet_color $idx
  local c=$'\e['"${REPLY}m" b=$'\e['"$LOTUS_C[border]m" d=$'\e['"$LOTUS_C[dim]m" r=$'\e[0m' y=$'\e['"$LOTUS_C[key2]m"
  # the bubble
  local t
  if [[ $style == bubble ]] && (( ${#text} )); then
    for t in $text; do (( ${#t} > iw )) && iw=${#t}; done
    local -i left=$shown
    (( shown < 0 )) && left=999999
    lotus_line $(( iw + 2 )); local bar=$REPLY
    bub=("  ${b}╭${bar}╮${r}")
    for (( k = 1; k <= ${#text}; k++ )); do
      local part=${text[k][1,left > 0 ? left : 0]}
      (( left -= ${#text[k]} ))
      if (( k == 1 )); then bub+=(" ${b}─┤${r} ${(r:iw:)part} ${b}│${r}")
      else bub+=("  ${b}│${r} ${(r:iw:)part} ${b}│${r}"); fi
    done
    bub+=("  ${b}╰${bar}╯${r}")
  elif [[ $style == plain ]]; then
    for t in $text; do bub+=("  $y$t$r"); done
    # next to the middle of the drawing
    for (( k = 0; k < (ah - 1) / 2; k++ )); do bub=("" "${bub[@]}"); done
  fi
  (( rows = ah + 1 > ${#bub} ? ah + 1 : ${#bub} ))
  local pad=${(l:colw:: :)}
  reply=()
  for (( i = 1; i <= rows; i++ )); do
    if (( i <= ah )); then line="$c${(r:colw:)art[i]}$r"
    elif (( i == ah + 1 )); then line="$d${(r:colw:)${(l:(colw + ${#name}) / 2:)name}}$r"
    else line=$pad; fi
    reply+=("$line${bub[i]}")
  done
}

typeset -gi PET_DRAWN=0

# Draws reply where the last block was (the cursor stays below it). Blocks only grow, so the
# lines above never move – that works at the bottom of the window too.
_pet_paint() {
  local line
  local -i n=${#reply} i
  print -n $'\e[?2026h'
  (( PET_DRAWN )) && print -n "\e[${PET_DRAWN}A"
  for line in "${reply[@]}"; do print -r -- $'\r'"  $line"$'\e[0m\e[K'; done
  for (( i = n; i < PET_DRAWN; i++ )); do print -r -- $'\r\e[K'; done
  (( n > PET_DRAWN )) && PET_DRAWN=n
  print -n $'\e[?2026l'
}

# Prints a block once (no animation, no terminal needed)
_pet_print() { local line; for line in "${reply[@]}"; do print -r -- "  $line"$'\e[0m'; done }

# While a pet is on screen: keys are not echoed, line wrap is off, Ctrl-C only sets a flag.
# Everything comes back in _pet_end – never from a trap, traps here start no programs.
typeset -g PET_TTY=
_pet_begin() {
  [[ -t 1 ]] && ui_has_tty || return 1
  PET_TTY=$(stty -g < /dev/tty 2>/dev/null)
  stty -echo < /dev/tty 2>/dev/null
  UI_INT=0
  TRAPINT() { UI_INT=1; return 0 }
  print -n $'\e[?7l\e[?25l'
  return 0
}
_pet_end() {
  [[ -n $PET_TTY ]] || return 0
  unfunction TRAPINT 2>/dev/null
  [[ -t 1 ]] && trap 'exit 130' INT
  print -n $'\e[0m\e[?7h\e[?25h'
  [[ -n $PET_TTY ]] && stty $PET_TTY < /dev/tty 2>/dev/null
  PET_TTY=
}

# A pet says something: the words appear one after another while its mouth moves
#   _pet_speak <pet> <text> [last drawing]
_pet_speak() {
  local -i idx=$1 bw total shown=0 step tick=0
  local text=$2 last=${3:-idle} fr
  _pet_bubble_width $idx; bw=$REPLY
  _pet_wrap "$text" $bw
  local -a lines=("${reply[@]}")
  if [[ -z $PET_TTY ]]; then _pet_block $idx $last -1 bubble "${lines[@]}"; _pet_print; return; fi
  total=${#${(j::)lines}}
  (( step = total / 80 + 1 ))
  while (( shown < total )); do
    (( shown += step, shown > total && (shown = total) ))
    (( tick / 2 % 2 )) && fr=idle || fr=talk
    _pet_block $idx $fr $shown bubble "${lines[@]}"
    _pet_paint
    (( tick++ ))
    ui_keyx 0.025
    [[ $REPLY == timeout ]] || shown=total
    (( UI_INT )) && break
  done
  _pet_block $idx $last -1 bubble "${lines[@]}"
  _pet_paint
}

# ── Thinking ──────────────────────────────────────────────────

# Who answers for the pets → REPLY (apple|ai), status 1 when nothing can (REPLY: off|none)
typeset -g PET_BRAIN=
_pet_brain() {
  [[ -n $PET_BRAIN ]] && { REPLY=$PET_BRAIN; [[ $REPLY == (apple|ai) ]]; return }
  local want=${LOTUS_PET_BRAIN:-apple}
  PET_BRAIN=none
  [[ $want == off ]] && { PET_BRAIN=off; REPLY=off; return 1 }
  (( ${+functions[lotus_ai_run]} )) || source $LOTUS_ROOT/lib/cmd/ai.zsh
  LOTUS_LOG_COMP=pets
  if [[ $want == apple ]]; then
    [[ -d /System/Library/Frameworks/FoundationModels.framework ]] || { REPLY=none; return 1 }
    lotus_ai_helper
    if [[ ! -x $REPLY ]]; then
      _ai_can_build || { REPLY=none; return 1 }
      local -i n=1
      _pet_load
      ui_dim "  ${LOTUS_L[pt_waking]//\%s/${PET_N[1]:-Lotus}}"
      _ai_build >/dev/null 2>&1 || { REPLY=none; return 1 }
      lotus_ai_helper
    fi
    [[ $($REPLY --check 2>/dev/null) == available ]] || { REPLY=none; return 1 }
    PET_BRAIN=apple
  else
    lotus_ai_helper
    [[ -x $REPLY ]] || { _ai_can_build && _ai_build >/dev/null 2>&1 } || { REPLY=none; return 1 }
    lotus_ai_provider >/dev/null 2>&1 || { REPLY=none; return 1 }
    PET_BRAIN=ai
  fi
  REPLY=$PET_BRAIN
}

# Starts the answer in the background (PET_PID, the text goes to PET_OUT)
typeset -gi PET_PID=0
typeset -g PET_OUT=
_pet_think_start() {   # <instructions> <prompt>
  zf_mkdir -p $LOTUS_CACHE/pets && chmod 700 $LOTUS_CACHE/pets
  PET_OUT=$LOTUS_CACHE/pets/answer.$$
  : >| $PET_OUT
  (
    [[ $PET_BRAIN == apple ]] && LOTUS_AI_PROVIDER=apple
    LOTUS_AI_INSTRUCTIONS=$1 lotus_ai_run --plain "$2" >| $PET_OUT 2>/dev/null
  ) &
  PET_PID=$!
}

# Waits for the answer while the pet thinks ("· · ·") → REPLY; status 1 when it was stopped or empty
_pet_think_wait() {
  local -i idx=$1 t=0
  local -a dots=('·' '· ·' '· · ·')
  local fr
  while kill -0 $PET_PID 2>/dev/null; do
    case $(( t % 14 )) in 6) fr=blink ;; 10|11) fr=wag ;; *) fr=idle ;; esac
    if [[ -n $PET_TTY ]]; then
      _pet_block $idx $fr -1 bubble "$dots[t % 3 + 1]"
      _pet_paint
      ui_keyx 0.15
      [[ $REPLY == (esc|interrupt) ]] && { kill $PET_PID 2>/dev/null; REPLY=; return 1 }
    else
      zselect -t 15 2>/dev/null
    fi
    (( ++t > 600 )) && { kill $PET_PID 2>/dev/null; break }
  done
  wait $PET_PID 2>/dev/null
  REPLY=$(<$PET_OUT)
  rm -f $PET_OUT
  _pet_clean "$REPLY" "$PET_N[idx]"
  [[ -n $REPLY ]]
}

# Only plain words get on screen: no escape sequences, no control characters, no markdown
_pet_clean() {
  setopt localoptions extendedglob
  local t=$1
  t=${t//$'\e'\[[0-9;?]#[@-~]/}
  t=${t//[[:cntrl:]]/ }
  t=${t//(\*\*|\`|\#\#)/}
  t=${t//  ##/ }
  t=${${t##[[:space:]]#}%%[[:space:]]#}
  t=${t#(#i)$2:[[:space:]]#}
  [[ $t == \"*\" ]] && t=${${t#\"}%\"}
  (( ${#t} > 320 )) && t="${t[1,317]}…"
  REPLY=$t
}

# How a pet is: personality, mood, time, language → REPLY (instructions for the AI)
_pet_instructions() {
  local -i idx=$1 hour
  _pet_kind $idx
  local kind=$REPLY name=$PET_N[idx] owner=${LOTUS_NAME:-my human} part lang
  local label=${PET_INFO[$kind,label]:-$kind} persona=${PET_P[idx]:-$PET_INFO[$kind,personality]}
  local sound=${PET_INFO[$kind,sound]:-hello} food=${PET_INFO[$kind,food]:-treats}
  strftime -s hour %H $EPOCHSECONDS
  if (( hour < 12 )); then part=morning; elif (( hour < 18 )); then part=afternoon; elif (( hour < 23 )); then part=evening; else part=night; fi
  case $LOTUS_LANG in de) lang=German ;; fr) lang=French ;; es) lang=Spanish ;; *) lang=English ;; esac
  _pet_mood $idx awake
  local mood=$REPLY
  REPLY="You are $name, a little ${(L)label} who lives in Lotus, a start screen in the macOS terminal. You belong to $owner and you like $owner a lot.
Your personality: $persona.
Talk like a ${(L)label} would: short, warm, playful sentences, and now and then you say \"$sound\". It is $part."
  case $mood in
    starving|hungry) REPLY+=" You are hungry and would love some $food – you may say so, or that $owner can type /feed ${(L)name}." ;;
  esac
  REPLY+="
Rules: reply directly to what $owner just said – answer the question if there is one. Use 1 or 2 short sentences, at most 35 words. Plain text only: no emojis, no lists, no markdown. You cannot run commands or change files and never say you did. If $owner asks how to do something in the terminal or with Lotus, suggest typing /help. Always answer in $lang.${3:+
$3}"
}

# What a pet remembers: the last three exchanges
_pet_memory() {   # <pet> → REPLY
  local f=$LOTUS_STATE/pets/${(L)PET_N[$1]}.mem
  REPLY=
  [[ -r $f ]] || return 0
  local -a l=("${(@f)$(<$f)}")
  REPLY=${(F)l[-6,-1]}
}
_pet_remember() {   # <pet> <what you said> <what the pet said>
  local f=$LOTUS_STATE/pets/${(L)PET_N[$1]}.mem
  { zf_mkdir -p $LOTUS_STATE/pets && chmod 700 $LOTUS_STATE/pets } 2>/dev/null || return 0
  local -a l=()
  [[ -r $f ]] && l=("${(@f)$(<$f)}")
  l+=("${LOTUS_NAME:-Human}: ${2//[[:cntrl:]]/ }" "$PET_N[$1]: ${3//[[:cntrl:]]/ }")
  print -rl -- "${(@)l[-6,-1]}" >| $f
}

# Short phrases, for pets without an AI
_pet_phrase() {   # <pet> <kind: hi|reply> → REPLY
  local -i idx=$1 hour n
  local owner=${LOTUS_NAME:-you} key
  _pet_kind $idx
  local sound=${PET_INFO[$REPLY,sound_$LOTUS_LANG]:-${PET_INFO[$REPLY,sound]:-hi}}
  _pet_mood $idx awake
  case $2 in
    hi)
      if [[ $REPLY == (hungry|starving) ]]; then key=pt_hi_hungry_$(( RANDOM % 2 + 1 )); REPLY=${LOTUS_L[$key]//\%s/${(L)PET_N[idx]}}; return; fi
      strftime -s hour %H $EPOCHSECONDS
      if (( hour < 11 )); then key=pt_hi_morning; elif (( hour < 18 )); then key=pt_hi_day; else key=pt_hi_evening; fi
      key+=_$(( RANDOM % 2 + 1 ))
      REPLY=${LOTUS_L[$key]//\%s/$owner} ;;
    *)
      REPLY="${(C)sound}! ${LOTUS_L[pt_noai]//\%s/$sound}" ;;
  esac
}

# A pet answers <message>: it thinks (with the AI), then speaks. Status 1 = stopped.
_pet_answer() {   # <pet> <message> [extra instructions]
  local -i idx=$1
  local msg=$2 answer
  if _pet_brain; then
    _pet_instructions $idx "" "$3"
    local sys=$REPLY
    _pet_memory $idx
    local prompt="${REPLY:+Earlier:
$REPLY

}${LOTUS_NAME:-Your human}: $msg"
    lotus_log INFO pets "${PET_N[idx]} thinks ($PET_BRAIN)"
    _pet_think_start "$sys" "$prompt"
    PET_DRAWN=0
    if ! _pet_think_wait $idx; then
      (( UI_INT )) && return 1
      REPLY=$LOTUS_L[pt_confused]
    fi
    answer=$REPLY
    _pet_remember $idx "$msg" "$answer"
  else
    _pet_phrase $idx reply; answer=$REPLY
    PET_DRAWN=0
  fi
  _pet_speak $idx "$answer"
  (( UI_INT )) && return 1
  return 0
}

# ── Talking: <name> [message] ─────────────────────────────────

lotus_pet_talk() {
  _pet_load; _pet_species
  local want=$1; shift
  local msg="$*"
  if (( ! ${#PET_N} )); then ui_error "$LOTUS_L[pt_nopets]" "" "$LOTUS_L[pt_nopets_hint]"; return 1; fi
  if ! _pet_find "$want"; then
    ui_error "${LOTUS_L[pt_unknown]//\%s/$want}" "" "${LOTUS_L[pt_unknown_hint]//\%s/${(j:, :)PET_N}}"
    return 1
  fi
  local -i idx=$REPLY
  _pet_begin
  print
  if [[ -n ${msg// } ]]; then
    _pet_answer $idx "$msg"
  else
    # just the name: the pet comes, says hi, and you can chat until an empty line
    _pet_mood $idx
    if [[ $REPLY == asleep ]]; then PET_DRAWN=0; _pet_speak $idx "$LOTUS_L[pt_wake]" sleep
    else _pet_phrase $idx hi; PET_DRAWN=0; _pet_speak $idx "$REPLY"; fi
    while [[ -n $PET_TTY ]] && (( ! UI_INT )); do
      print
      ui_dim "  $LOTUS_L[pt_chat_hint]"
      print -n $'\e[?25h'
      ui_line "$LOTUS_L[pt_you]" "" || break
      print -n $'\e[?25l'
      [[ -z ${REPLY// } ]] && break
      print
      _pet_answer $idx "$REPLY" || break
    done
  fi
  _pet_end
  print
  lotus_log INFO pets "Talked with ${PET_N[idx]}"
}

# ── Feeding: /feed [name] ─────────────────────────────────────

lotus_pet_feed() {
  _pet_load; _pet_species
  if (( ! ${#PET_N} )); then ui_error "$LOTUS_L[pt_nopets]" "" "$LOTUS_L[pt_nopets_hint]"; return 1; fi
  local -i idx=1
  if [[ -n $1 ]]; then
    _pet_find "$1" || { ui_error "${LOTUS_L[pt_unknown]//\%s/$1}" "" "${LOTUS_L[pt_unknown_hint]//\%s/${(j:, :)PET_N}}"; return 1 }
    idx=$REPLY
  elif (( ${#PET_N} > 1 )); then
    ui_has_tty || { ui_error "$LOTUS_L[pt_which]" "" "/feed ${(L)PET_N[1]}"; return 1 }
    ui_choose "$LOTUS_L[pt_which]" "${PET_N[@]}" || return 0
    idx=$REPLY
  fi
  _pet_kind $idx
  local kind=$REPLY name=$PET_N[idx] key
  local food=${PET_INFO[$kind,food_$LOTUS_LANG]:-${PET_INFO[$kind,food]:-food}} snack=${PET_INFO[$kind,snack]:-o}
  snack=${${snack//[^ -~]/}[1,6]}
  _pet_hours $idx
  local -i hours=$REPLY
  _pet_begin
  print
  PET_DRAWN=0
  if (( hours < 1 && ${PET_COUNT[${(L)name}]:-0} > 0 )); then
    _pet_speak $idx "${${LOTUS_L[pt_full_now]/\%s/$name}/\%s/$food}" idle
  else
    if [[ -n $PET_TTY ]]; then
      local -i i
      for (( i = 14; i >= 0; i -= 2 )); do
        _pet_block $idx idle -1 plain "${(l:i:)}$snack"; _pet_paint
        ui_keyx 0.05; (( UI_INT )) && break
      done
      for (( i = 0; i < 6 && ! UI_INT; i++ )); do
        (( i % 2 )) && key=happy || key=eat
        _pet_block $idx $key -1 plain "${${(M)key:#eat}:+nom}"; _pet_paint
        ui_keyx 0.16
      done
    fi
    PET_FED[${(L)name}]=$EPOCHSECONDS
    PET_COUNT[${(L)name}]=$(( ${PET_COUNT[${(L)name}]:-0} + 1 ))
    _pet_save_state
    lotus_log INFO pets "$name was fed"
    key=pt_thanks_$(( RANDOM % 3 + 1 ))
    _pet_speak $idx "${LOTUS_L[$key]//\%s/$food}" happy
  fi
  _pet_end
  print
}

# ── Greeting on the start screen ──────────────────────────────

# One pet (a different one every day) says hi below the start screen – only when it fits
# without scrolling, so the now playing lines keep their place. No AI here: it has to be quick.
lotus_pet_greet() {
  emulate -L zsh
  setopt extendedglob
  [[ -t 1 ]] || return 0
  lotus_lang_group pets
  _pet_load
  local -i free=99
  if lotus_cursor_row; then (( free = ${LINES:-24} - REPLY )); fi
  if (( ! ${#PET_N} )); then
    # once in a while (three times) a hint for people who updated
    local seen=$LOTUS_STATE/pets-hint
    local -i n=0
    [[ -r $seen ]] && n=$(<$seen)
    (( n >= 3 || free < 2 )) && return 0
    print -r -- "  "$'\e['"$LOTUS_C[dim]m$LOTUS_L[pt_new]"$'\e[0m'
    { zf_mkdir -p $LOTUS_STATE && print $(( n + 1 )) >| $seen } 2>/dev/null
    return 0
  fi
  _pet_species
  local -i idx day
  strftime -s day %j $EPOCHSECONDS
  (( idx = day % ${#PET_N} + 1 ))
  _pet_mood $idx
  local mood=$REPLY text frame=idle
  case $mood in
    asleep) frame=sleep; text=${LOTUS_L[pt_hi_night]//\%s/$PET_N[idx]} ;;
    *)      _pet_phrase $idx hi; text=$REPLY ;;
  esac
  # a tip every few days, and how to call the pet in its first days
  if [[ $mood == happy ]]; then
    if (( EPOCHSECONDS - ${PET_T[idx]:-0} < 3 * 86400 )); then text+=" $LOTUS_L[pt_call_tip]"
    elif (( day % 3 == 0 )); then
      _pet_tip && text+=" $LOTUS_L[pt_tip] $REPLY"
    fi
  fi
  _pet_bubble_width $idx
  if [[ $mood == asleep ]]; then _pet_block $idx sleep -1 none
  else _pet_wrap "$text" $REPLY; _pet_block $idx $frame -1 bubble "${reply[@]}"; fi
  (( ${#reply} + 1 <= free )) || return 0
  _pet_print
  [[ $mood == asleep ]] && print -r -- "  "$'\e['"$LOTUS_C[dim]m$text"$'\e[0m'
  return 0
}

# A random command of a feature that is on → REPLY ("/bg paste – …")
_pet_tip() {
  local line
  local -a f all=()
  lotus_features
  for line in "${(@f)$(<$LOTUS_ROOT/data/commands.tsv)}"; do
    [[ $line == \#* ]] && continue
    f=("${(@ps:\t:)line}")
    [[ $f[7] == 1 || $f[4] == lotus* || $f[3] == pet ]] && continue
    lotus_feature_on ${LOTUS_FEATURE_OF[${f[3]%% *}]:-core} || continue
    all+=("$f[6] – ${(L)f[5][1]}${f[5][2,-1]}")
  done
  (( ${#all} )) || return 1
  REPLY=$all[RANDOM % ${#all} + 1]
}

# ── Reactions (typos, finished work) ──────────────────────────

lotus_pet_react_now() {   # <typo|done>
  emulate -L zsh
  setopt extendedglob
  lotus_lang_group pets
  _pet_load
  (( ${#PET_N} )) || return 0
  _pet_species
  local -i idx=$(( RANDOM % ${#PET_N} + 1 ))
  _pet_kind $idx
  local kind=$REPLY face text
  _pet_color $idx
  local c=$'\e['"${REPLY}m" r=$'\e[0m'
  case $1 in
    typo) face=${PET_INFO[$kind,face]:-(o.o)}; text=${LOTUS_L[pt_typo]//\%s/$PET_N[idx]} ;;
    done) face=${PET_INFO[$kind,face_happy]:-${PET_INFO[$kind,face]:-(^.^)}}
          local key=pt_done_$(( RANDOM % 3 + 1 ))
          text="$PET_N[idx]: $LOTUS_L[$key]" ;;
    *)    return 0 ;;
  esac
  face=${face//[^ -~▀-▟]/}
  print -r -- "  $c${face[1,12]}$r $text"
}

# ── /help with a pet ──────────────────────────────────────────

# Commands of the features that are on → PET_CMDS (lines of data/commands.tsv)
_pet_commands() {
  (( ${+PET_CMDS} )) && return
  typeset -ga PET_CMDS=()
  local line
  local -a f
  lotus_features
  for line in "${(@f)$(<$LOTUS_ROOT/data/commands.tsv)}"; do
    [[ $line == \#* ]] && continue
    f=("${(@ps:\t:)line}")
    [[ $f[7] == 1 ]] && continue
    lotus_feature_on ${LOTUS_FEATURE_OF[${f[3]%% *}]:-core} || continue
    PET_CMDS+=("$line")
  done
}

# The commands that fit a question best, without an AI → reply (indexes in PET_CMDS)
_pet_rank() {
  setopt localoptions extendedglob
  _pet_commands
  local q=${(L)1} w hay
  # a few words in other languages that lead to the English descriptions
  local -A alias=(wetter weather météo weather tiempo weather clima weather hintergrund background fond background fondo background
    bild image foto image photo image imagen image musik music musique music música music lied song chanson song canción song
    öffnen open ouvrir open abrir open suchen search chercher search buscar search herunterladen download télécharger download
    descargar download installieren install installer install instalar install einstellungen settings réglages settings ajustes settings
    farbe theme couleur theme color theme haustier pet animal pet mascota pet füttern feed nourrir feed alimentar feed
    zwischenablage clipboard presse-papiers clipboard portapapeles clipboard ki ai ia ai abkürzung shortcut raccourci shortcut atajo shortcut)
  local -a words=() scores=()
  for w in ${(s: :)${q//[^[:alnum:]-]/ }}; do
    (( ${#w} >= 3 )) || continue
    [[ $w == (the|and|how|can|what|with|for|ich|wie|kann|was|mit|und|der|die|das|ein|eine|einen|mein|meine|comment|que|pour|avec|les|des|une|cómo|como|qué|que|para|con|los|las|una) ]] && continue
    words+=($w ${alias[$w]})
  done
  local -i i s
  local -a f
  for (( i = 1; i <= ${#PET_CMDS}; i++ )); do
    f=("${(@ps:\t:)PET_CMDS[i]}")
    hay=${(L):-"$f[1] $f[4] $f[5] $f[6]"}
    s=0
    for w in $words; do
      if [[ $hay == *$w* ]]; then (( s += 3 ))
      elif (( ${#w} >= 5 )) && [[ $hay == *${w[1,5]}* ]]; then (( s += 1 )); fi
    done
    (( s )) && scores+=("$(( 100 - s )):$i")
  done
  reply=()
  for w in ${${(on)scores}[1,3]}; do reply+=(${w#*:}); done
}

# Asks the pet's AI which commands help (by number) and how → reply (indexes), REPLY (what it says)
_pet_help_think() {   # <pet> <question>
  local -i idx=$1 i
  local list= line
  local -a f picks=()
  for (( i = 1; i <= ${#PET_CMDS}; i++ )); do
    f=("${(@ps:\t:)PET_CMDS[i]}")
    list+="$i. $f[4] – $f[5]"$'\n'
  done
  _pet_instructions $idx "" "You help ${LOTUS_NAME:-your human} use Lotus. These are the Lotus commands, numbered:
$list
Answer in exactly this form. First line: the numbers of the 1 to 3 commands that help most, separated by commas, or 0 when none fits. Then one or two short sentences in your voice that say what to do."
  local sys=${REPLY//at most 35 words/at most 40 words}
  _pet_think_start "$sys" "${LOTUS_NAME:-Your human} asks: $2"
  PET_DRAWN=0
  _pet_think_wait $idx || return 1
  local all=$REPLY first rest
  # the numbers come first; anything else is what the pet says
  first=${(M)all##[0-9 ,.;:–-]##}
  rest=${all#$first}
  for i in ${(s: :)${first//[^0-9]/ }}; do
    (( i >= 1 && i <= ${#PET_CMDS} )) && (( ! ${picks[(Ie)$i]} )) && picks+=($i)
  done
  reply=(${picks[1,3]})
  REPLY=${${rest##[[:space:][:punct:]]#}%%[[:space:]]#}
  return 0
}

# /help: the pet asks, you say what you need, it shows the right commands
lotus_pet_help() {
  _pet_load; _pet_species; _pet_commands
  (( ${#PET_N} )) || return 1
  local -i idx=$(( RANDOM % ${#PET_N} + 1 )) n i thought
  local q first= text
  local -a picks f
  _pet_begin || return 1
  print
  PET_DRAWN=0
  _pet_speak $idx "${LOTUS_L[pt_help_ask]//\%s/${LOTUS_NAME:-}}"
  while (( ! UI_INT )); do
    print
    ui_dim "  $LOTUS_L[pt_help_hint]"
    print -n $'\e[?25h'
    ui_line "$LOTUS_L[pt_ask]" "$first" || break
    print -n $'\e[?25l'
    q=$REPLY first=
    if [[ -z ${q// } ]]; then
      _pet_end
      lotus_cheatsheet
      return 0
    fi
    print
    lotus_log INFO pets "Help asked"
    picks=() text= thought=0
    if _pet_brain; then
      thought=1
      _pet_help_think $idx "$q" && picks=($reply) text=$REPLY
    fi
    (( UI_INT )) && break
    (( ${#picks} )) || { _pet_rank "$q"; picks=($reply) }
    (( thought )) || PET_DRAWN=0
    if (( ! ${#picks} )); then
      _pet_speak $idx "${text:-$LOTUS_L[pt_help_none]}"
      continue
    fi
    _pet_speak $idx "${text:-$LOTUS_L[pt_help_found]}"
    # the commands, ready to be put on the command line
    print
    n=0
    local k=$'\e[1;'"$LOTUS_C[key]m" d=$'\e['"$LOTUS_C[dim]m" r=$'\e[0m'
    local -i dw=$(( ${COLUMNS:-80} - 10 ))
    (( dw > 70 )) && dw=70
    for i in $picks; do
      f=("${(@ps:\t:)PET_CMDS[i]}")
      (( n++ ))
      print -r -- "    $k$n  ${f[4]}$r"
      _pet_wrap "$f[5]" $dw
      local l
      for l in $reply; do print -r -- "       $l"; done
      [[ $f[6] != $f[4] ]] && print -r -- "       ${d}${f[6]}$r"
    done
    print
    ui_dim "  ${LOTUS_L[pt_help_pick]//\%s/$n}"
    _pet_key
    if [[ $REPLY == <1-9> ]] && (( REPLY <= n )); then
      f=("${(@ps:\t:)PET_CMDS[$picks[REPLY]]}")
      zf_mkdir -p $LOTUS_CACHE
      print -r -- "${f[6]}" >| $LOTUS_CACHE/ai-prompt
      ui_success "$LOTUS_L[pt_help_ready]"
      break
    fi
    [[ $REPLY == (esc|interrupt) ]] && break
    [[ $REPLY == ? && $REPLY == [[:print:]] ]] && first=$REPLY
  done
  _pet_end
  print
  return 0
}

# ── /pets ─────────────────────────────────────────────────────

# Your pets side by side, with name and how they are
_pet_lineup() {
  local -i i j h=0 w
  local -a cols=() widths=() hs=()
  for (( i = 1; i <= ${#PET_N}; i++ )); do
    _pet_block $i idle -1 none
    cols+=("${(pj:\n:)reply}")
    _pet_kind $i
    (( w = PET_AW[$REPLY] > ${#PET_N[i]} ? PET_AW[$REPLY] : ${#PET_N[i]} ))
    widths+=($(( w + 6 )))
    (( ${#reply} > h )) && h=${#reply}
  done
  local line
  local -a rows
  for (( j = 1; j <= h; j++ )); do
    line="  "
    for (( i = 1; i <= ${#cols}; i++ )); do
      rows=("${(@f)cols[i]}")
      local -i pad=$(( h - ${#rows} ))
      if (( j > pad )); then line+="${rows[j - pad]}"$'\e[0m'"${(l:6:)}"
      else line+="${(l:widths[i]:)}"; fi
    done
    print -r -- $line
  done
}

lotus_pets_screen() {
  _pet_load; _pet_species
  if ! { [[ -t 1 ]] && ui_has_tty }; then
    local -i i
    for (( i = 1; i <= ${#PET_N}; i++ )); do _pet_status $i; print -r -- "${(r:16:)PET_N[i]} ${(r:10:)PET_K[i]} $REPLY"; done
    return 0
  fi
  local -i i sel=1
  local -a opts
  while :; do
    print -n $'\e[H\e[2J'
    ui_hero "$LOTUS_L[pt_title]" "$LOTUS_L[pt_sub]"
    if (( ${#PET_N} )); then _pet_lineup; ui_blank; fi
    opts=()
    for (( i = 1; i <= ${#PET_N}; i++ )); do
      _pet_kind_label $PET_K[i]; local lbl=$REPLY
      _pet_status $i
      opts+=("$PET_N[i]|$lbl · $REPLY")
    done
    (( ${#PET_N} < 3 )) && opts+=("$LOTUS_L[pt_adopt]|${LOTUS_L[pt_adopt_d]//\%s/${#PET_N}}")
    opts+=("$LOTUS_L[pt_settings]|$LOTUS_L[pt_settings_d]")
    ui_select $sel "${opts[@]}" || break
    sel=$REPLY
    if (( sel <= ${#PET_N} )); then _pets_one $sel
    elif (( sel == ${#PET_N} + 1 && ${#PET_N} < 3 )); then _pets_adopt_flow
    else _pets_settings; fi
  done
  print -n $'\e[H\e[2J'
  return 0
}

# One pet: talk, feed, rename, personality, say goodbye
_pets_one() {
  local -i idx=$1
  local name=$PET_N[idx] new
  _pet_kind_label $PET_K[idx]; local lbl=$REPLY
  print -n $'\e[H\e[2J'
  ui_hero "$LOTUS_L[pt_title] · $name"
  _pet_block $idx happy -1 none; _pet_print
  ui_blank
  ui_select 1 "$LOTUS_L[pt_talk]|${LOTUS_L[pt_talk_d]//\%s/${(L)name}}" "$LOTUS_L[pt_feed]|/feed ${(L)name}" \
    "$LOTUS_L[pt_rename]|" "$LOTUS_L[pt_persona]|${LOTUS_L[pt_persona_d]//\%s/$name}" "$LOTUS_L[pt_remove]|" "$LOTUS_L[pt_back]|" || return 0
  case $REPLY in
    1) print -n $'\e[H\e[2J'; lotus_pet_talk $name; _pets_wait ;;
    2) print -n $'\e[H\e[2J'; lotus_pet_feed $name; _pets_wait ;;
    3) ui_blank
       ui_line "$LOTUS_L[pt_name]" "$name" || return 0
       new=${${REPLY## #}%% #}
       [[ $new == $name || -z $new ]] && return 0
       _pets_name_check "$new" $idx || { _pets_wait; return 0 }
       [[ -n ${PET_FED[${(L)name}]} ]] && { PET_FED[${(L)new}]=$PET_FED[${(L)name}]; PET_COUNT[${(L)new}]=$PET_COUNT[${(L)name}] }
       [[ -r $LOTUS_STATE/pets/${(L)name}.mem ]] && zf_mv $LOTUS_STATE/pets/${(L)name}.mem $LOTUS_STATE/pets/${(L)new}.mem 2>/dev/null
       PET_N[idx]=$new
       _pet_save
       ui_success "${LOTUS_L[pt_renamed]//\%s/$new}"; _pets_wait ;;
    4) ui_blank
       ui_dim "  ${PET_INFO[$PET_K[idx],personality]}"
       ui_line "${LOTUS_L[pt_persona_q]//\%s/$lbl}" "$PET_P[idx]" || return 0
       PET_P[idx]=${${REPLY//[[:cntrl:]]/ }[1,240]}
       _pet_save
       rm -f $LOTUS_STATE/pets/${(L)name}.mem
       ui_success "$LOTUS_L[pt_saved]"; _pets_wait ;;
    5) ui_blank
       ui_confirm "${LOTUS_L[pt_remove_q]//\%s/$name}" n || return 0
       PET_N[idx]=() PET_K[idx]=() PET_P[idx]=() PET_T[idx]=()
       unset "PET_FED[${(L)name}]" "PET_COUNT[${(L)name}]"
       rm -f $LOTUS_STATE/pets/${(L)name}.mem
       _pet_save
       ui_info "${LOTUS_L[pt_removed]//\%s/$name}"; _pets_wait ;;
  esac
}

_pets_wait() { ui_dim "$LOTUS_L[back]"; ui_key }

# One key while a pet is on screen (Ctrl-C counts as esc) → REPLY
_pet_key() { while :; do ui_keyx 0.3; [[ $REPLY == timeout ]] || return 0; done }

# Is a name free and usable? (a pet you call by typing its name must not be a command)
_pets_name_check() {   # <name> [index of the pet that is renamed]
  _pet_name_ok "$1" || { ui_warn "$LOTUS_L[pt_name_bad]"; return 1 }
  local -i i
  for (( i = 1; i <= ${#PET_N}; i++ )); do
    (( i == ${2:-0} )) && continue
    [[ ${(L)PET_N[i]} == ${(L)1} ]] && { ui_warn "${LOTUS_L[pt_name_taken]//\%s/$1}"; return 1 }
  done
  if (( $+commands[$1] || $+commands[${(L)1}] || $+builtins[${(L)1}] || $+reswords[(r)${(L)1}] )) || [[ ${(L)1} == (lotus|pet|pets|feed|help|ai|bg) ]]; then
    ui_warn "${LOTUS_L[pt_name_cmd]//\%s/$1}"; return 1
  fi
  return 0
}

# Adopt: which kind, which name
_pets_adopt_flow() {
  local -a kinds=() opts=()
  local k
  for k in $PET_KINDS; do
    _pet_kind_label $k
    local lbl=$REPLY
    _pet_kind_about $k
    kinds+=($k) opts+=("$lbl|$REPLY")
  done
  opts+=("$LOTUS_L[pt_own]|$LOTUS_L[pt_own_d]")
  print -n $'\e[H\e[2J'
  ui_hero "$LOTUS_L[pt_adopt]" "$LOTUS_L[pt_species_q]"
  ui_select 1 "${opts[@]}" || return 0
  if (( REPLY > ${#kinds} )); then
    ui_blank
    ui_text "$LOTUS_L[pt_add_how]"
    ui_dim "  $LOTUS_P[website]pets.html"
    ui_blank
    ui_confirm "$LOTUS_L[pt_add_q]" n && { lotus_pets_add; return 0 }
    return 0
  fi
  _pets_adopt_named $kinds[REPLY] || _pets_wait
}

# Asks for a name and adopts a <kind> (the pet says hi right away)
_pets_adopt_named() {
  local kind=$1 name
  local -a ideas=(${(s:, :)PET_INFO[$kind,names]})
  local idea=${ideas[RANDOM % (${#ideas} > 0 ? ${#ideas} : 1) + 1]:-Mochi}
  ui_blank
  ui_line "$LOTUS_L[pt_name]" "$idea" || return 0
  name=${${REPLY## #}%% #}
  _pets_name_check "$name" || return 1
  lotus_pets_adopt $kind "$name" quiet || return 1
  print -n $'\e[H\e[2J'
  lotus_pet_intro $name
  _pets_wait
  return 0
}

# lotus pets adopt <kind> <name> [quiet]
lotus_pets_adopt() {
  _pet_load; _pet_species
  local kind=${(L)1} name=$2
  [[ -n ${PET_ART[$kind,idle]} ]] || { ui_error "$LOTUS_L[pt_kind_bad]" "$1" "${(j:, :)PET_KINDS}"; return 1 }
  (( ${#PET_N} < 3 )) || { ui_error "$LOTUS_L[pt_full]"; return 1 }
  _pets_name_check "$name" || return 1
  PET_N+=("$name") PET_K+=($kind) PET_P+=("") PET_T+=($EPOCHSECONDS)
  PET_FED[${(L)name}]=$EPOCHSECONDS PET_COUNT[${(L)name}]=0
  _pet_save
  lotus_log INFO pets "Adopted $name ($kind)"
  [[ $3 == quiet ]] || ui_success "${${LOTUS_L[pt_adopted]/\%s/$name}/\%s/${(L)name}}"
  return 0
}

# A new pet introduces itself
lotus_pet_intro() {
  lotus_lang_group pets
  _pet_load; _pet_species
  _pet_find "$1" || return 0
  local -i idx=$REPLY
  local text=${LOTUS_L[pt_intro]/\%s/${LOTUS_NAME:-}}
  text=${text/\%s/$PET_N[idx]}
  _pet_begin
  print
  PET_DRAWN=0
  _pet_speak $idx "$text" happy
  _pet_end
  print
}

_pets_settings() {
  local -i sel=1
  local -A brain=(apple "$LOTUS_L[pt_brain_apple]" ai "$LOTUS_L[pt_brain_ai]" off "$LOTUS_L[pt_brain_off]")
  _onoff() { (( $1 )) && REPLY=$LOTUS_L[pt_on] || REPLY=$LOTUS_L[pt_off] }
  while :; do
    print -n $'\e[H\e[2J'
    ui_hero "$LOTUS_L[pt_title] · $LOTUS_L[pt_settings]"
    local -a o=()
    _onoff $LOTUS_PET_START; o+=("$LOTUS_L[pt_s_start]|$REPLY")
    _onoff $LOTUS_PET_HELP;  o+=("$LOTUS_L[pt_s_help]|$REPLY")
    _onoff $LOTUS_PET_REACT; o+=("$LOTUS_L[pt_s_react]|$REPLY")
    o+=("$LOTUS_L[pt_on_brain]|${brain[${LOTUS_PET_BRAIN:-apple}]}")
    ui_select $sel "${o[@]}" || break
    sel=$REPLY
    case $sel in
      1) (( LOTUS_PET_START = ! LOTUS_PET_START )) ;;
      2) (( LOTUS_PET_HELP = ! LOTUS_PET_HELP )) ;;
      3) (( LOTUS_PET_REACT = ! LOTUS_PET_REACT )) ;;
      4) case ${LOTUS_PET_BRAIN:-apple} in apple) LOTUS_PET_BRAIN=ai ;; ai) LOTUS_PET_BRAIN=off ;; *) LOTUS_PET_BRAIN=apple ;; esac
         PET_BRAIN= ;;
    esac
    lotus_save
  done
}

# ── Your own kind of pet: lotus pets add [file] ───────────────

lotus_pets_add() {
  _pet_species
  local src=$1 text tmp=$LOTUS_CACHE/pets/new.pet
  ui_header "$LOTUS_L[pt_add_title]"
  if [[ -n $src ]]; then
    [[ -f $src && -r $src ]] || { ui_error "File not found" "$src"; return 1 }
    text=$(<$src)
  else
    text=$(pbpaste 2>/dev/null)
  fi
  # what an AI answers often sits in a code block
  text=${text//\`\`\`[a-z]#/}
  zf_mkdir -p ${tmp:h} && chmod 700 ${tmp:h}
  print -r -- $text >| $tmp
  local -a before=($PET_KINDS)
  if ! _pet_parse $tmp; then
    ui_error "$LOTUS_L[pt_add_bad]" "$REPLY" "$LOTUS_L[pt_add_bad_hint]" "$LOTUS_L[pt_add_how]"
    rm -f $tmp
    return 1
  fi
  local kind=$REPLY
  if [[ ${PET_INFO[$kind,file]} == $LOTUS_ROOT/* ]] || [[ -e $LOTUS_ROOT/data/pets/$kind.pet ]]; then
    ui_error "${LOTUS_L[pt_add_builtin]//\%s/$kind}"
    rm -f $tmp
    return 1
  fi
  # a preview, then saved as clean text (what Lotus read, not what was pasted)
  local lbl
  _pet_kind_label $kind; lbl=$REPLY
  local -a art=("${(@f)PET_ART[$kind,idle]}")
  local line
  for line in $art; do print -r -- "    "$'\e['"$LOTUS_C[logo]m$line"$'\e[0m'; done
  ui_blank
  ui_kv "$lbl" "${PET_INFO[$kind,personality]}"
  ui_blank
  ui_has_tty && { ui_confirm "$LOTUS_L[pt_add_q]" y || { rm -f $tmp; return 0 } }
  local out="# Lotus pet, added with lotus pets add"$'\n' key fr
  for key in species label label_de label_fr label_es about about_de about_fr about_es sound sound_de sound_fr sound_es \
      food food_de food_fr food_es snack face face_happy names personality; do
    [[ -n ${PET_INFO[$kind,$key]} ]] && out+="$key: ${PET_INFO[$kind,$key]}"$'\n'
  done
  for fr in idle blink wag talk happy eat sleep; do
    [[ -n ${PET_ART[$kind,$fr]} ]] && out+="[$fr]"$'\n'"${PET_ART[$kind,$fr]}"$'\n'
  done
  zf_mkdir -p $LOTUS_CONF/pets
  print -rn -- $out >| $LOTUS_CONF/pets/$kind.pet
  rm -f $tmp
  lotus_log INFO pets "New kind of pet: $kind"
  ui_success "${LOTUS_L[pt_add_ok]//\%s/$lbl}"
  _pet_load
  if (( ${#PET_N} < 3 )) && ui_has_tty && [[ -t 1 ]]; then
    ui_blank
    ui_confirm "$LOTUS_L[pt_adopt]?" y && _pets_adopt_named $kind
  fi
  return 0
}
