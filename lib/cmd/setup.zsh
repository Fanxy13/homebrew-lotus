# lotus – first-time setup wizard (lotus setup) and the features page (lotus features)
#
#                       (a lotus that opens a little with every step)
#                   ━━━━━  ━━━━━  ━━━━━  ─────  ─────
#
#         What should Lotus call you?
#         Used in the greeting. Enter keeps the name shown.
#
#         ╭─ Name ─────────────────────────────────────────╮
#         │ Gabriel                                        │
#         ╰────────────────────────────────────────────────╯
#
#                          ⏎ continue   esc back
#
# Welcome (language) → You (name, theme, start) → Features → setup of the chosen features → Review.
# Always in the Matcha colors; on the theme page the flower takes the colors of the theme you point
# at, on the welcome page the texts switch to the language you point at. Every line is placed by
# cursor position, so nothing can run through the drawing. Esc goes back a page; nothing is saved
# before Finish. The flower comes from data/lotus-setup.txt (scripts/make-setup-lotus.py).

lotus_cmd_setup() {
  case $1 in
    features) shift; lotus_features_page "$@" ;;
    *)        lotus_cmd_setup_wizard ;;
  esac
}

# Colored sample of a theme
_lotus_swatch() {
  local -a rgb=(${=LOTUS_THEMES[$1]}) out=()
  local i
  for i in 1 2 3 4; do lotus_sgr $rgb[i]; out+=($'\e['"${REPLY}m"'■■'); done
  REPLY="${(j: :)out}"$'\e[0m'
}

# ── The page ──────────────────────────────────────────────────

typeset -gA SW_C=() SW_PF=() SW_ROW=()
typeset -ga SW_ART=()
typeset -gi SW_STEP=1 SW_STAGE=1 SW_Y=0 SW_X=0 SW_CW=0 SW_FOOT=0 SW_AY=0 SW_PY=0 SW_QY=0 SW_ART_ON=0
typeset -g SW_Q= SW_SUB= SW_HINT= SW_DETAIL= SW_ART_THEME=matcha SW_ON_MOVE= SW_PAINT= SW_ART_FN=

_sw_put() { print -rn -- $'\e['"$1;$2H$3" }

_sw_colors() {
  local -a th=(${=LOTUS_THEMES[matcha]})
  lotus_sgr $th[1]; SW_C[pink]=$REPLY
  lotus_sgr $th[2]; SW_C[green]=$REPLY
  lotus_sgr $th[4]; SW_C[yellow]=$REPLY
  lotus_sgr $th[7]; SW_C[dim]=$REPLY
}

_sw_size() {
  local -a sz=(${=$(stty size < /dev/tty 2>/dev/null)})
  (( ${#sz} == 2 && sz[1] > 0 )) && { LINES=$sz[1]; COLUMNS=$sz[2] }
}

# Was the window resized? Asked about once a second while no key comes – zsh runs a TRAPWINCH
# only after a loop has ended, so the wizard cannot wait for the signal.  Status 0 = new size.
# (zsh may already have updated LINES and COLUMNS, so the size of the last layout is compared.)
typeset -gi SW_TICK=0 SW_LH=0 SW_LW=0
_sw_resized() {
  (( ++SW_TICK % 3 )) && return 1
  local -a sz=(${=$(stty size < /dev/tty 2>/dev/null)})
  (( ${#sz} == 2 && sz[1] > 0 )) || return 1
  (( sz[1] == SW_LH && sz[2] == SW_LW )) && return 1
  LINES=$sz[1] COLUMNS=$sz[2]
}

# Where everything goes, for the current window size
_sw_layout() {
  local -i W=${COLUMNS:-80} H=${LINES:-24} top=1
  SW_LH=$H SW_LW=$W
  (( W < 20 )) && W=80; (( H < 12 )) && H=24
  SW_CW=$(( W - 8 > 72 ? 72 : W - 8 ))
  (( SW_CW < 30 )) && SW_CW=$(( W - 2 ))
  SW_X=$(( (W - SW_CW) / 2 + 1 ))
  SW_ART_ON=$(( H >= 22 && W >= 34 ))
  # Designed for 80 x 24; bigger windows get the same picture, a little above the middle
  (( H > 24 )) && top=$(( (H - 24) * 2 / 5 + 1 ))
  SW_FOOT=$(( top + 23 < H ? top + 23 : H ))
  if (( SW_ART_ON )); then SW_AY=$top SW_PY=$(( top + 8 )); else SW_PY=$(( top + 1 )); fi
  SW_QY=$(( SW_PY + 2 ))
}

# Word wrap → reply (lines)
_sw_wrap() {
  local word line=
  reply=()
  for word in ${=1}; do
    if (( ${#line} && ${#line} + ${#word} + 1 > $2 )); then reply+=("$line"); line=$word
    else line+=${line:+ }$word; fi
  done
  [[ -n $line ]] && reply+=("$line")
}

# ── The flower ────────────────────────────────────────────────

_sw_art_load() {
  (( ${#SW_ART} )) && return
  local line cur=
  for line in "${(@f)$(<$LOTUS_ROOT/data/lotus-setup.txt)}"; do
    [[ $line == \#* ]] && continue
    if [[ $line == % ]]; then SW_ART+=("${cur%$'\n'}"); cur=
    else cur+="$line"$'\n'; fi
  done
}

# Pixel codes → colors of a theme (petals from its logo color, the pad from its key color)
_sw_palette() {
  [[ -n ${SW_PF[$1,0]} ]] && return
  local -a th=(${=LOTUS_THEMES[$1]:-$LOTUS_THEMES[matcha]})
  local -i n
  for n in {0..9}; do _bgu_ramp $th[1] $(( n / 9.0 )); lotus_sgr $REPLY; SW_PF[$1,$n]=$REPLY; done
  _bgu_ramp $th[2] 0.25; lotus_sgr $REPLY; SW_PF[$1,g]=$REPLY
  _bgu_ramp $th[2] 0.55; lotus_sgr $REPLY; SW_PF[$1,G]=$REPLY
}

# One row of a stage as half blocks (two pixels per cell) → REPLY
_sw_art_row() {   # <stage> <row> <theme>
  local key=$3,$1,$2
  if [[ -z ${SW_ROW[$key]} ]]; then
    _sw_palette $3
    local -a px=("${(@f)SW_ART[$1]}")
    local top=${px[2*$2-1]} bot=${px[2*$2]} t b want cur=x out= ch
    local -i c
    for (( c = 1; c <= ${#top}; c++ )); do
      t=${top[c]} b=${bot[c]}
      if [[ $t == . && $b == . ]]; then want=0 ch=' '
      elif [[ $b == . ]]; then want=$SW_PF[$3,$t] ch=▀
      elif [[ $t == . ]]; then want=$SW_PF[$3,$b] ch=▄
      elif [[ $t == $b ]]; then want=$SW_PF[$3,$t] ch=█
      else want="$SW_PF[$3,$t];48${SW_PF[$3,$b]#38}" ch=▀; fi
      [[ $want != $cur ]] && { out+=$'\e[0;'"${want}m"; cur=$want }
      out+=$ch
    done
    SW_ROW[$key]="$out"$'\e[0m'
  fi
  REPLY=$SW_ROW[$key]
}

_sw_art_at() {   # <top row> <stage> <theme>
  (( ${#SW_ART} )) || return 0
  local -i r x=$(( (${COLUMNS:-80} - 25) / 2 + 1 ))
  for (( r = 1; r <= 7; r++ )); do _sw_art_row $2 $r $3; _sw_put $(( $1 + r - 1 )) $x $REPLY; done
}

_sw_art() {
  (( SW_ART_ON )) || return 0
  [[ -n $SW_ART_FN ]] && { $SW_ART_FN; return 0 }
  _sw_art_at $SW_AY $SW_STAGE $SW_ART_THEME
}

# The five steps: done in green, the current one in pink, the rest thin and dim
_sw_progress() {
  local out=
  local -i i
  for (( i = 1; i <= 5; i++ )); do
    if (( i < SW_STEP )); then out+=$'\e['"$SW_C[green]m━━━━━"
    elif (( i == SW_STEP )); then out+=$'\e['"$SW_C[pink]m━━━━━"
    else out+=$'\e['"$SW_C[dim]m─────"; fi
    (( i < 5 )) && out+='  '
  done
  _sw_put $SW_PY $(( (${COLUMNS:-80} - 33) / 2 + 1 )) "$out"$'\e[0m'
}

_sw_hint() {
  local h=$SW_HINT
  _sw_put $SW_FOOT 1 $'\e[2K'
  _sw_put $SW_FOOT $(( (${COLUMNS:-80} - ${#h}) / 2 + 1 )) $'\e['"$SW_C[dim]m$h"$'\e[0m'
}

# The description of what is highlighted, above the hints (two lines when it needs them)
typeset -gi SW_DL=1
_sw_detail() {
  SW_DETAIL=$1
  local -a l=()
  local -i i
  [[ -n $1 ]] && { _sw_wrap "$1" $SW_CW; l=("${(@)reply[1,2]}") }
  (( SW_DL > 1 || ${#l} > 1 )) && _sw_put $(( SW_FOOT - 2 )) 1 $'\e[2K'
  _sw_put $(( SW_FOOT - 1 )) 1 $'\e[2K'
  for (( i = 1; i <= ${#l}; i++ )); do
    _sw_put $(( SW_FOOT - ${#l} + i - 1 )) $SW_X $'\e['"$SW_C[dim]m${l[i]}"$'\e[0m'
  done
  SW_DL=${#l}
}

# The whole page: flower, steps, question and explanation; SW_Y = first row for the answer
_sw_frame() {
  _sw_layout
  print -n $'\e[?2026h\e[0m\e[2J'
  _sw_art
  _sw_progress
  _sw_put $SW_QY $SW_X $'\e[1m'"${SW_Q[1,SW_CW]}"$'\e[0m'
  local -i y=$(( SW_QY + 1 )) n=0
  local l
  if [[ -n $SW_SUB ]]; then
    _sw_wrap "$SW_SUB" $SW_CW
    for l in $reply; do _sw_put $y $SW_X $'\e['"$SW_C[dim]m$l"$'\e[0m'; (( y++, n++ )); done
  fi
  # The answer starts on the same row on every page and in every language (two lines are kept
  # for the explanation – all of them fit in two at 80 columns); small windows use what is there
  (( SW_ART_ON && n < 2 )) && n=2
  SW_Y=$(( SW_QY + n + 2 ))
  _sw_hint
  _sw_detail "$SW_DETAIL"
  [[ -n $SW_PAINT ]] && $SW_PAINT
  print -n $'\e[?2026l'
}

# Rows free for the answer
_sw_room() { REPLY=$(( SW_FOOT - 2 - SW_Y + 1 )) }

# ── Answers ───────────────────────────────────────────────────

# A list, "Label|Description" per entry: the labels in one column, the descriptions wrapped in the
# next. ⏎ picks, esc goes back.  → REPLY = index, status 1 = back
# SW_ON_MOVE (a function) hears about the highlighted entry; it may change the page texts.
_sw_select() {
  local -i sel=${1:-1} n i j redraw=1 gap lw dw total y was room; shift
  local -a opts=("$@") descs=() cnt=() dl
  n=${#opts}
  (( sel < 1 || sel > n )) && sel=1
  local p=$'\e['"$SW_C[pink]m" g=$'\e[1;'"$SW_C[green]m" d=$'\e['"$SW_C[dim]m" r=$'\e[0m' lbl desc pad
  print -n $'\e[?25l'
  while :; do
    if (( redraw )); then
      SW_HINT=${LOTUS_L[ui_select_hint]:-↑↓ choose   ⏎ continue   esc back} SW_DETAIL=
      _sw_frame; redraw=0
      lw=0
      for (( i = 1; i <= n; i++ )); do lbl=${opts[i]%%|*}; (( ${#lbl} > lw )) && lw=${#lbl}; done
      (( dw = SW_CW - 4 - lw, total = 0 ))
      descs=() cnt=()
      for (( i = 1; i <= n; i++ )); do
        desc=${opts[i]#*|}
        [[ $desc == $opts[i] ]] && desc=
        if [[ -n $desc ]] && (( dw >= 16 )); then _sw_wrap "$desc" $dw; else reply=("$desc"); fi
        descs+=("${(pj:\n:)reply}") cnt+=(${#reply})
        (( total += ${#reply} ))
      done
      _sw_room; room=$REPLY
      (( gap = total + n - 1 <= room ? 1 : 0 ))
      if (( total + gap * (n - 1) > room )); then
        # no room for whole descriptions: one line each, cut
        for (( i = 1; i <= n; i++ )); do
          dl=("${(@f)descs[i]}")
          (( cnt[i] > 1 )) && descs[i]="${dl[1][1,dw-1]}…"
          cnt[i]=1
        done
        (( gap = 2 * n - 1 <= room ? 1 : 0 ))
      fi
      pad=${(l:lw+4:)}
    fi
    y=$SW_Y
    for (( i = 1; i <= n; i++ )); do
      lbl=${opts[i]%%|*} dl=("${(@f)descs[i]}")
      if (( i == sel )); then _sw_put $y $SW_X $'\e[K'"${p}❯${r} ${g}${(r:lw:)lbl}${r}  ${d}${dl[1]}${r}"
      else _sw_put $y $SW_X $'\e[K'"  ${(r:lw:)lbl}  ${d}${dl[1]}${r}"; fi
      for (( j = 2; j <= cnt[i]; j++ )); do _sw_put $(( y + j - 1 )) $SW_X $'\e[K'"${pad}${d}${dl[j]}${r}"; done
      (( y += cnt[i] + gap ))
    done
    was=$sel
    ui_keyx 0.3
    case $REPLY in
      timeout) _sw_resized && redraw=1; continue ;;
      up)     (( sel = sel > 1 ? sel - 1 : n )) ;;
      down|tab) (( sel = sel < n ? sel + 1 : 1 )) ;;
      enter|space|right) break ;;
      esc|left|q|interrupt) return 1 ;;
      <1-9>)  (( REPLY <= n )) && sel=$REPLY ;;
    esac
    (( sel != was )) && [[ -n $SW_ON_MOVE ]] && { $SW_ON_MOVE $sel; redraw=1 }
  done
  REPLY=$sel
}

# A grid of short entries, filled column by column; the line at the bottom describes the
# highlighted one.  _sw_grid radio|check <columns> <default> "Label|Description|Extra" …
#   radio: ⏎ picks → REPLY = index.  check: space turns on and off (LOTUS_TOGGLES), ⏎ continues.
_sw_grid() {
  local mode=$1
  local -i cols=$2 sel=$3 n rows i redraw=1 cw lw x y was; shift 3
  local -a items=("$@") f
  n=${#items}
  (( sel < 1 || sel > n )) && sel=1
  local p=$'\e['"$SW_C[pink]m" g=$'\e[1;'"$SW_C[green]m" k=$'\e['"$SW_C[green]m" d=$'\e['"$SW_C[dim]m" r=$'\e[0m' mark cell
  print -n $'\e[?25l'
  while :; do
    if (( redraw )); then
      (( rows = (n + cols - 1) / cols, cw = SW_CW / cols ))
      SW_HINT=${LOTUS_L[ui_select_hint]:-↑↓ choose   ⏎ continue   esc back}
      [[ $mode == check ]] && SW_HINT=${LOTUS_L[ui_toggle_hint]:-↑↓ move   space on/off   ⏎ continue   esc back}
      SW_HINT=${SW_HINT/↑↓/←↑↓→}
      _sw_frame; redraw=0
      lw=0; for (( i = 1; i <= n; i++ )); do f=("${(@s:|:)items[i]}"); (( ${#f[1]} > lw )) && lw=${#f[1]}; done
    fi
    for (( i = 1; i <= n; i++ )); do
      f=("${(@s:|:)items[i]}")
      (( x = SW_X + (i - 1) / rows * cw, y = SW_Y + (i - 1) % rows ))
      if [[ $mode == check ]]; then
        (( LOTUS_TOGGLES[i] )) && mark="${k}◉${r}" || mark="${d}○${r}"
        if (( i == sel )); then cell="${p}❯${r} $mark ${g}${(r:lw:)f[1]}${r}"
        else cell="  $mark ${(r:lw:)f[1]}"; fi
      else
        if (( i == sel )); then cell="${p}❯${r} ${g}${(r:lw:)f[1]}${r} $f[3]"
        else cell="  ${(r:lw:)f[1]} $f[3]"; fi
      fi
      _sw_put $y $x "$cell"
    done
    f=("${(@s:|:)items[sel]}")
    _sw_detail "$f[2]"
    was=$sel
    ui_keyx 0.3
    case $REPLY in
      timeout) _sw_resized && redraw=1; continue ;;
      up)     (( sel = sel > 1 ? sel - 1 : n )) ;;
      down|tab) (( sel = sel < n ? sel + 1 : 1 )) ;;
      left)   (( sel > rows )) && (( sel -= rows )) ;;
      right)  (( sel + rows <= n )) && (( sel += rows )) ;;
      space|x) [[ $mode == check ]] && (( LOTUS_TOGGLES[sel] = ! LOTUS_TOGGLES[sel] )) ;;
      a)      [[ $mode == check ]] && for (( i = 1; i <= n; i++ )); do LOTUS_TOGGLES[i]=1; done ;;
      enter)  break ;;
      esc|q|interrupt) return 1 ;;
    esac
    (( sel != was )) && [[ -n $SW_ON_MOVE ]] && $SW_ON_MOVE $sel
  done
  REPLY=$sel
}

# One line of text in a rounded box; ⏎ accepts, esc goes back.  _sw_input <label> <text> → REPLY
# The text shown at first is a suggestion (dim): ⏎ keeps it, typing replaces it, ⌫ edits it.
_sw_input() {
  local label=$1 text=$2 shown
  local -i bw inner redraw=1 fresh=${#2}
  local k=$'\e['"$SW_C[green]m" b=$'\e[1m' r=$'\e[0m'
  while :; do
    if (( redraw )); then
      print -n $'\e[?25l'
      SW_HINT=${${LOTUS_L[ui_select_hint]:-↑↓ choose   ⏎ continue   esc back}#*   } SW_DETAIL=
      _sw_frame; redraw=0
      (( bw = SW_CW > 52 ? 52 : SW_CW, inner = bw - 4 ))
      lotus_line $(( bw - 5 - ${#label} > 0 ? bw - 5 - ${#label} : 1 )); _sw_put $SW_Y $SW_X "${k}╭─ ${r}${b}${label}${r} ${k}${REPLY}╮${r}"
      _sw_put $(( SW_Y + 1 )) $SW_X "${k}│${r}"; _sw_put $(( SW_Y + 1 )) $(( SW_X + bw - 1 )) "${k}│${r}"
      lotus_line $(( bw - 2 )); _sw_put $(( SW_Y + 2 )) $SW_X "${k}╰${REPLY}╯${r}"
    fi
    shown=$text
    (( ${#shown} > inner - 1 )) && shown="…${shown[-(inner-2),-1]}"
    if (( fresh )); then _sw_put $(( SW_Y + 1 )) $(( SW_X + 2 )) $'\e['"$SW_C[dim]m${(r:inner:)shown}$r"
    else _sw_put $(( SW_Y + 1 )) $(( SW_X + 2 )) "${(r:inner:)shown}"; fi
    print -n $'\e['"$(( SW_Y + 1 ));$(( SW_X + 2 + ${#shown} ))H"$'\e[?25h'
    ui_keyx 0.3
    case $REPLY in
      timeout) _sw_resized && redraw=1 ;;
      enter)  break ;;
      esc|interrupt) print -n $'\e[?25l'; return 1 ;;
      back)   text=${text[1,-2]} fresh=0 ;;
      space)  (( fresh )) && text= fresh=0; text+=' ' ;;
      up|down|left|right|home|end|pgup|pgdn|tab|ignore) ;;
      *)      if [[ $REPLY == [[:print:]] ]]; then
                (( fresh )) && text= fresh=0
                (( ${#text} < 200 )) && text+=$REPLY
              fi ;;
    esac
  done
  print -n $'\e[?25l'
  REPLY=$text
}

# Buttons on the line above the hints, the chosen one filled.  _sw_buttons <default> <label>… → REPLY
_sw_buttons() {
  local -i sel=${1:-1} n i redraw=1 x w; shift
  local -a b=("$@")
  n=${#b}
  local on=$'\e[1;'"$SW_C[green];7m" off=$'\e['"$SW_C[dim]m" r=$'\e[0m' out
  print -n $'\e[?25l'
  while :; do
    if (( redraw )); then
      SW_HINT=${${LOTUS_L[ui_select_hint]:-↑↓ choose   ⏎ continue   esc back}/↑↓/←→} SW_DETAIL=
      _sw_frame; redraw=0
    fi
    out= w=0
    for (( i = 1; i <= n; i++ )); do
      (( i == sel )) && out+="${on}  ${b[i]}  ${r}" || out+="${off}  ${b[i]}  ${r}"
      (( w += ${#b[i]} + 4 ))
      (( i < n )) && { out+='    '; (( w += 4 )) }
    done
    _sw_put $(( SW_FOOT - 1 )) 1 $'\e[2K'
    _sw_put $(( SW_FOOT - 1 )) $(( (${COLUMNS:-80} - w) / 2 + 1 )) "$out"
    ui_keyx 0.3
    case $REPLY in
      timeout) _sw_resized && redraw=1 ;;
      left|up)  (( sel = sel > 1 ? sel - 1 : n )) ;;
      right|down|tab) (( sel = sel < n ? sel + 1 : 1 )) ;;
      enter|space) break ;;
      esc|q|interrupt) return 1 ;;
    esac
  done
  REPLY=$sel
}

# ── The pages ─────────────────────────────────────────────────

_sw_set_lang() { LOTUS_LANG=$1; lotus_lang; lotus_lang_group setup; lotus_lang_group bg; return 0 }

_sw_lang() {
  SW_STEP=1 SW_STAGE=1
  local -a langs=(en de fr es)
  _sw_lang_move() { _sw_set_lang $langs[$1]; SW_Q=$LOTUS_L[sw_welcome] SW_SUB=$LOTUS_L[sw_welcome_sub] }
  SW_Q=$LOTUS_L[sw_welcome] SW_SUB=$LOTUS_L[sw_welcome_sub] SW_ON_MOVE=_sw_lang_move
  _sw_select ${langs[(i)$LOTUS_LANG]} 'English|Lotus speaks English' 'Deutsch|Lotus spricht Deutsch' \
    'Français|Lotus parle français' 'Español|Lotus habla español'
  local -i rc=$?
  SW_ON_MOVE=
  return rc
}

_sw_name() {
  SW_STEP=2 SW_STAGE=2 SW_Q=$LOTUS_L[sw_name_q] SW_SUB=$LOTUS_L[sw_name_sub]
  _sw_input $LOTUS_L[name] $LOTUS_NAME || return 1
  [[ -n ${REPLY// } ]] && LOTUS_NAME=${${REPLY## #}%% #}
  return 0
}

_sw_theme() {
  SW_STEP=2 SW_STAGE=2 SW_Q=$LOTUS_L[sw_theme_q] SW_SUB=$LOTUS_L[sw_theme_sub]
  local -a names=($LOTUS_THEME_NAMES) items=() rgb
  local n sw i
  for n in $names; do
    rgb=(${=LOTUS_THEMES[$n]}) sw=
    for i in 1 2 4; do lotus_sgr $rgb[i]; sw+=$'\e['"${REPLY}m■"; done
    items+=("${LOTUS_THEME_LABELS[$n]}||$sw"$'\e[0m')
  done
  _sw_theme_move() { SW_ART_THEME=$names[$1]; _sw_art }
  SW_ART_THEME=$LOTUS_THEME SW_ON_MOVE=_sw_theme_move
  _sw_grid radio $(( SW_CW >= 54 ? 3 : 2 )) ${names[(i)$LOTUS_THEME]} "${items[@]}"
  local -i rc=$?
  SW_ON_MOVE= SW_ART_THEME=matcha
  (( rc )) && return 1
  LOTUS_THEME=$names[REPLY]
  return 0
}

_sw_start() {
  SW_STEP=2 SW_STAGE=2 SW_Q=$LOTUS_L[sw_start_q] SW_SUB=
  _sw_select $(( LOTUS_STARTUP ? 1 : 2 )) "$LOTUS_L[sw_start_yes]|$LOTUS_L[sw_start_yes_d]" "$LOTUS_L[sw_start_no]|$LOTUS_L[sw_start_no_d]" || return 1
  (( REPLY == 1 )) && LOTUS_STARTUP=1 || LOTUS_STARTUP=0
  return 0
}

_sw_features() {
  SW_STEP=3 SW_STAGE=3 SW_Q=$LOTUS_L[sw_feat_q] SW_SUB=$LOTUS_L[sw_feat_wsub]
  lotus_features
  local id
  local -a ids=(${LOTUS_FEATURE_IDS:#core}) items=() f
  typeset -ga LOTUS_TOGGLES=()
  for id in $ids; do
    f=("${(@ps:\t:)LOTUS_FEATURE_ROW[$id]}")
    lotus_feature_label $id
    items+=("$REPLY|${LOTUS_L[featd_$id]:-$f[4]}")
    lotus_feature_on $id && LOTUS_TOGGLES+=(1) || LOTUS_TOGGLES+=(0)
  done
  _sw_grid check $(( SW_CW >= 44 ? 2 : 1 )) 1 "${items[@]}" || return 1
  local -i i
  for (( i = 1; i <= ${#ids}; i++ )); do
    lotus_feature_on $ids[i] && (( ! LOTUS_TOGGLES[i] )) && lotus_feature_set $ids[i] 0
    ! lotus_feature_on $ids[i] && (( LOTUS_TOGGLES[i] )) && lotus_feature_set $ids[i] 1
  done
  return 0
}

# The checklist of `lotus features` (outside the wizard): reads and sets LOTUS_FEATURES_OFF
_lotus_feature_toggles() {
  lotus_features
  local id
  local -a opts=() f
  typeset -ga LOTUS_TOGGLES=()
  for id in $LOTUS_FEATURE_IDS; do
    f=("${(@ps:\t:)LOTUS_FEATURE_ROW[$id]}")
    lotus_feature_label $id
    opts+=("$REPLY|${LOTUS_L[featd_$id]:-$f[4]}|${${(M)id:#core}:+locked}")
    lotus_feature_on $id && LOTUS_TOGGLES+=(1) || LOTUS_TOGGLES+=(0)
  done
  ui_toggles "${opts[@]}" || return 1
  local -i i
  for (( i = 1; i <= ${#LOTUS_FEATURE_IDS}; i++ )); do
    [[ $LOTUS_FEATURE_IDS[i] == core ]] && continue
    lotus_feature_on $LOTUS_FEATURE_IDS[i] && (( ! LOTUS_TOGGLES[i] )) && lotus_feature_set $LOTUS_FEATURE_IDS[i] 0
    ! lotus_feature_on $LOTUS_FEATURE_IDS[i] && (( LOTUS_TOGGLES[i] )) && lotus_feature_set $LOTUS_FEATURE_IDS[i] 1
  done
  return 0
}

_sw_weather() {
  SW_STEP=4 SW_STAGE=4 SW_Q=$LOTUS_L[sw_weather_q] SW_SUB=$LOTUS_L[sw_weather_sub]
  _sw_input $LOTUS_L[sw_city] $LOTUS_WEATHER_LOCATION || return 1
  LOTUS_WEATHER_LOCATION=${${REPLY## #}%% #}
  return 0
}

_sw_ai() {
  SW_STEP=4 SW_STAGE=4 SW_Q=$LOTUS_L[sw_ai_q] SW_SUB=$LOTUS_L[sw_ai_sub]
  _sw_select $(( sw_claude ? 2 : 1 )) "$LOTUS_L[sw_ai_later]|$LOTUS_L[sw_ai_later_d]" "$LOTUS_L[sw_ai_claude]|$LOTUS_L[sw_ai_claude_d]" || return 1
  (( REPLY == 2 )) && sw_claude=1 || sw_claude=0
  return 0
}

# The Remove BG pickers ask with ui_select and ui_line, which show up here as _sw_select and _sw_input
_sw_bgmodel() { SW_STEP=4 SW_STAGE=4 SW_Q=$LOTUS_L[bg_q_model] SW_SUB=$LOTUS_L[bg_q_model_sub]; lotus_bg_pick_model }
_sw_bgout()   { SW_STEP=4 SW_STAGE=4 SW_Q=$LOTUS_L[bg_q_output] SW_SUB=$LOTUS_L[bg_q_output_sub]; lotus_bg_pick_output }
_sw_bgwhen()  {
  (( LOTUS_BG_READY )) && return 0
  SW_STEP=4 SW_STAGE=4 SW_Q=$LOTUS_L[bg_q_when] SW_SUB=$LOTUS_L[bg_q_when_sub]
  lotus_bg_pick_when $sw_bg_now || return 1
  sw_bg_now=$REPLY
  return 0
}

# A pet moves in (when Pets is on and there is none yet): which kind, then its name.
# The lotus makes room for the pet you point at.
_sw_pet_draw() {
  local kind=$SW_PET_SHOW
  if [[ -z $kind ]]; then _sw_art_at $SW_AY $SW_STAGE matcha; return; fi
  local -a rows=("${(@f)PET_ART[$kind,idle]}")
  local -i w=$PET_AW[$kind] h=${#rows} r x=$(( (${COLUMNS:-80} - PET_AW[$kind]) / 2 + 1 )) y
  for (( r = 0; r < 7; r++ )); do _sw_put $(( SW_AY + r )) 1 $'\e[2K'; done
  (( y = SW_AY + (7 - h) / 2 ))
  for (( r = 1; r <= h; r++ )); do _sw_put $(( y + r - 1 )) $x $'\e['"$SW_C[pink]m${rows[r]}"$'\e[0m'; done
}

_sw_pet() {
  SW_STEP=4 SW_STAGE=4 SW_Q=$LOTUS_L[sw_pet_q] SW_SUB=$LOTUS_L[sw_pet_sub]
  local -a kinds=(${PET_KINDS[1,4]}) opts=()
  local k
  for k in $kinds; do
    _pet_kind_label $k
    local lbl=$REPLY
    _pet_kind_about $k
    opts+=("$lbl|$REPLY")
  done
  opts+=("$LOTUS_L[sw_pet_none]|$LOTUS_L[sw_pet_none_d]")
  local -i def=$(( ${kinds[(i)$sw_pet_kind]} ))
  (( def > ${#kinds} )) && def=$(( ${#kinds} + 1 ))
  [[ -z $sw_pet_kind && -z $sw_pet_seen ]] && def=1
  _sw_pet_move() { SW_PET_SHOW=${kinds[$1]}; _sw_art }
  SW_PET_SHOW=${kinds[def]} SW_ART_FN=_sw_pet_draw SW_ON_MOVE=_sw_pet_move
  _sw_select $def "${opts[@]}"
  local -i rc=$?
  SW_ON_MOVE= SW_ART_FN=
  (( rc )) && return 1
  sw_pet_seen=1
  if (( REPLY > ${#kinds} )); then sw_pet_kind=; else sw_pet_kind=$kinds[REPLY]; fi
  return 0
}

_sw_petname() {
  [[ -n $sw_pet_kind ]] || return 0
  _pet_kind_label $sw_pet_kind
  SW_STEP=4 SW_STAGE=4 SW_Q=${LOTUS_L[sw_petname_q]//\%s/${(L)REPLY}} SW_SUB=$LOTUS_L[sw_petname_sub]
  local -a ideas=(${(s:, :)PET_INFO[$sw_pet_kind,names]})
  local name=${sw_pet_name:-${ideas[1]:-Mochi}}
  SW_PET_SHOW=$sw_pet_kind SW_ART_FN=_sw_pet_draw
  while :; do
    _sw_input "$LOTUS_L[pt_name]" "$name" || { SW_ART_FN= SW_DETAIL=; return 1 }
    name=${${REPLY## #}%% #}
    [[ -z $name ]] && name=${ideas[1]:-Mochi}
    if ! _pet_name_ok "$name"; then SW_DETAIL=$LOTUS_L[pt_name_bad]
    elif (( $+commands[$name] || $+commands[${(L)name}] || $+builtins[${(L)name}] )) || [[ ${(L)name} == (lotus|pet|pets|feed|help|ai|bg) ]]; then
      SW_DETAIL=${LOTUS_L[pt_name_cmd]//\%s/$name}
    else break; fi
  done
  SW_ART_FN= SW_DETAIL=
  sw_pet_name=$name
  return 0
}

# Review: everything at a glance, then Back or Finish
_sw_review_paint() {
  local d=$'\e['"$SW_C[dim]m" r=$'\e[0m' id row
  local -a rows=() on=() off=() rgb
  local -i i lw=0 total=0 room
  for id in ${LOTUS_FEATURE_IDS:#core}; do
    lotus_feature_label $id; (( total++ ))
    lotus_feature_on $id && on+=($REPLY) || off+=($REPLY)
  done
  local sw= lang
  rgb=(${=LOTUS_THEMES[$LOTUS_THEME]})
  for i in 1 2 4; do lotus_sgr $rgb[i]; sw+=$'\e['"${REPLY}m■"; done
  case $LOTUS_LANG in de) lang=Deutsch ;; fr) lang=Français ;; es) lang=Español ;; *) lang=English ;; esac
  rows+=("$LOTUS_L[name]|${LOTUS_NAME:-–}")
  rows+=("$LOTUS_L[lang]|$lang")
  rows+=("$LOTUS_L[theme]|${LOTUS_THEME_LABELS[$LOTUS_THEME]}  $sw$r")
  rows+=("$LOTUS_L[sw_start]|${${LOTUS_STARTUP:#0}:+$LOTUS_L[sw_start_auto]}${${(M)LOTUS_STARTUP:#0}:+$LOTUS_L[sw_start_manual]}")
  local feat=${${LOTUS_L[sw_feat_sum]//\%s/${#on}}/\%t/$total}
  (( ${#off} )) && feat+=" · $LOTUS_L[sw_disabled]: ${(j:, :)off}"
  rows+=("$LOTUS_L[sw_s3]|$feat")
  if [[ -n $sw_pet_kind && -n $sw_pet_name ]] && lotus_feature_on pets; then
    _pet_kind_label $sw_pet_kind
    rows+=("$LOTUS_L[pt_title]|$sw_pet_name · $REPLY")
  fi
  lotus_feature_on weather && [[ -n $LOTUS_WEATHER_LOCATION ]] && rows+=("$LOTUS_L[sw_city]|$LOTUS_WEATHER_LOCATION")
  if lotus_feature_on ai && (( sw_claude )); then lotus_feature_label ai; rows+=("$REPLY|$LOTUS_L[sw_ai_claude]"); fi
  lotus_feature_on bg && rows[6,5]=("$LOTUS_L[head_bg]|")       # filled in below, when the width is known
  _sw_room; room=$(( REPLY - 1 ))
  for row in "${(@)rows[1,room]}"; do (( ${#row%%|*} > lw )) && lw=${#row%%|*}; done
  if lotus_feature_on bg; then
    lotus_bg_model_label $LOTUS_BG_MODEL; local model=$REPLY
    ui_path "${LOTUS_BG_OUTPUT/#\~/$HOME}" $(( SW_CW - lw - 3 - ${#model} - 3 ))
    [[ $LOTUS_BG_OUTPUT == @source ]] && REPLY=$LOTUS_L[bg_out_source]
    rows[6]="$LOTUS_L[head_bg]|$model · $REPLY"
  fi
  i=0
  for row in "${(@)rows[1,room]}"; do
    local v=${row#*|}
    [[ $v != *$'\e'* ]] && (( ${#v} > SW_CW - lw - 3 )) && v="${v[1,SW_CW-lw-4]}…"
    _sw_put $(( SW_Y + i )) $SW_X "${d}${(r:lw+3:)row%%|*}${r}$v"
    (( i++ ))
  done
}

_sw_review() {
  SW_STEP=5 SW_STAGE=5 SW_Q=$LOTUS_L[sw_ready] SW_SUB= SW_PAINT=_sw_review_paint
  _sw_buttons 2 $LOTUS_L[sw_back] $LOTUS_L[sw_finish]
  local -i rc=$?
  SW_PAINT=
  (( rc == 0 && REPLY == 2 ))
}

# Esc on the first page: stay or leave (status 0 = leave)
_sw_quit() {
  SW_Q=$LOTUS_L[sw_quit_t] SW_SUB=$LOTUS_L[sw_quit_new]
  (( LOTUS_CONFIGURED )) && SW_SUB=$LOTUS_L[sw_quit_cfg]
  _sw_buttons 1 $LOTUS_L[sw_quit_stay] $LOTUS_L[sw_quit_leave] || return 1
  (( REPLY == 2 ))
}

# ── The end: pollen from the lotus writes "Hello" and your name ─────

typeset -gA SW_FONT=()
typeset -ga SW_DX=() SW_DY=() SW_BR=()
# Accented letters the dot font does not have are drawn without the accent
typeset -gA SW_PLAIN=(â a ã a å a ë e î i ì i ï i ô o ò o õ o û u ù u ý y ÿ y
  À A Á A Â A Ã A Ä A Å A Ç C È E É E Ê E Ë E Ì I Í I Î I Ï I Ñ N Ò O Ó O Ô O Õ O Ö O Ù U Ú U Û U Ü U Ý Y)

# data/dotfont.txt → SW_FONT (char → 8 rows), SW_BR (braille characters for the dot masks 1-255)
_sw_font_load() {
  (( ${#SW_FONT} )) && return
  local line ch= rows=
  for line in "${(@f)$(<$LOTUS_ROOT/data/dotfont.txt)}"; do
    [[ $line == '# '* ]] && continue      # comments; a row of a letter is only . and #
    if [[ $line == '= '* ]]; then
      [[ -n $ch ]] && SW_FONT[$ch]=$rows
      ch=${line#= } rows=
    else rows+="${rows:+ }$line"; fi
  done
  [[ -n $ch ]] && SW_FONT[$ch]=$rows
  local -i m
  for (( m = 1; m < 256; m++ )); do SW_BR+=(${(#)$(( 0x2800 + m ))}); done
}

# The dots of a text: SW_DX/SW_DY (relative), REPLY = width in dots. Status 1: a letter is missing.
#   _sw_dots <text> 1   dense, 8 dots high (2 rows)      _sw_dots <text> 2   every second dot, 4 rows
_sw_dots() {
  local text=$1 ch g row
  local -i step=$2 x=0 i j c c0 c1
  local -a rows
  SW_DX=() SW_DY=()
  for (( i = 1; i <= ${#text}; i++ )); do
    ch=${text[i]}
    [[ -n ${SW_PLAIN[$ch]} ]] && ch=${SW_PLAIN[$ch]}
    if [[ $ch == ' ' ]]; then (( x += 3 * step )); continue; fi
    g=${SW_FONT[$ch]}
    [[ -z $g ]] && return 1
    rows=(${=g}) c0=6 c1=0
    for row in $rows; do
      for (( j = 1; j <= 5; j++ )); do [[ ${row[j]} == '#' ]] && { (( j < c0 )) && c0=j; (( j > c1 )) && c1=j }; done
    done
    for (( j = 1; j <= 8; j++ )); do
      row=${rows[j]}
      for (( c = c0; c <= c1; c++ )); do
        [[ ${row[c]} == '#' ]] && { SW_DX+=($(( x + (c - c0) * step ))); SW_DY+=($(( (j - 1) * step ))) }
      done
    done
    (( x += (c1 - c0 + 2) * step ))
  done
  REPLY=$(( x - 2 * step + 1 ))
  (( REPLY > 0 ))
}

# Finish: the lotus opens all the way, its pollen flies up and writes "Hello" (in big dots) and,
# a little smaller, your name – then the dots twinkle for a moment. Any key skips it.
# The dots are braille characters: two by four per cell, so they sit on a square grid.
_sw_finale() {
  _sw_layout
  local -i W=${COLUMNS:-80} H=${LINES:-24} art=$SW_ART_ON words=1 hw=0 nw=0
  local hello=${LOTUS_L[sw_hello]:-Hello} name=${${LOTUS_NAME## #}%% #} tip=$LOTUS_L[sw_done_hint]
  local -a hx hy nx ny
  _sw_font_load
  [[ ${SW_BR[1]} == ⠁ ]] || words=0                      # no UTF-8 here: plain text
  if (( words )) && _sw_dots "$hello" 2 && (( (REPLY + 1) / 2 + 4 <= W && H >= 14 )); then
    hx=($SW_DX) hy=($SW_DY) hw=$REPLY
  else words=0; fi
  local plainname=
  if [[ -n $name ]] && (( words )); then
    if _sw_dots "$name" 1 && (( (REPLY + 1) / 2 + 4 <= W )); then nx=($SW_DX) ny=($SW_DY) nw=$REPLY
    else plainname=$name; fi
  fi
  # Rows: Hello (4) · the name (2) · the lotus (7) · the tip. Centered as one block.
  local -i hr nr below ar tr top
  (( hr = 1, nr = hr + 5, below = ${#name} ? nr + 2 : hr + 4, ar = below + 2, tr = art ? ar + 8 : below + 1 ))
  (( top = (H - tr) / 2, top = top < 0 ? 0 : top ))
  (( hr += top, nr += top, ar += top, tr += top ))
  print -n $'\e[?25l\e[0m\e[2J'
  local pink=$SW_C[pink] green=$'\e[1;'"$SW_C[green]m" dim=$'\e['"$SW_C[dim]m" r0=$'\e[0m'
  if (( ! words )); then
    local msg="$hello${name:+, $name}"
    (( art )) && _sw_art_at $ar 5 matcha
    _sw_put $hr $(( (W - ${#msg}) / 2 + 1 )) "$green$msg$r0"
    _sw_put $tr $(( (W - ${#tip}) / 2 + 1 )) "$dim$tip$r0"
    ui_keyx 2
    return 0
  fi

  # Every dot of the words is one grain of pollen: it starts just above the flower and flies to
  # its place. Hello fills in from left to right, then the name.
  local -a PX PY PDX PDY PW PD PG HG
  local -i n=0 i lx ly sx sy sy0 cx=$W cmin cmax rmin rmax
  local -F maxd=0 d
  (( sy0 = art ? (ar - 1) * 4 - 2 : (tr - 1) * 4 - 6 ))
  (( lx = (W - (hw + 1) / 2) / 2 * 2, ly = (hr - 1) * 4, cmin = lx < cx - 10 ? lx : cx - 10, cmax = lx + hw > cx + 10 ? lx + hw : cx + 10 ))
  for (( i = 1; i <= ${#hx}; i++ )); do
    (( sx = cx + RANDOM % 21 - 10, sy = sy0 - RANDOM % 3, d = 0.3 + 0.55 * hx[i] / hw + (RANDOM % 15) / 100.0 ))
    PX+=($sx) PY+=($sy) PDX+=($(( lx + hx[i] - sx ))) PDY+=($(( ly + hy[i] - sy ))) PW+=($(( RANDOM % 13 - 6 ))) PD+=($d) PG+=(2)
    (( d > maxd )) && maxd=$d
  done
  # Hello in a soft gradient from the petal pink to peach
  local -a c1=(${(s:;:)${=LOTUS_THEMES[matcha]}[1]}) c2=(${(s:;:)${=LOTUS_THEMES[matcha]}[5]})
  local -i hc0=$(( lx / 2 )) hcs=$(( (hw + 1) / 2 )) c
  for (( c = 0; c < hcs; c++ )); do
    lotus_sgr "$(( c1[1] + (c2[1] - c1[1]) * c / (hcs > 1 ? hcs - 1 : 1) ));$(( c1[2] + (c2[2] - c1[2]) * c / (hcs > 1 ? hcs - 1 : 1) ));$(( c1[3] + (c2[3] - c1[3]) * c / (hcs > 1 ? hcs - 1 : 1) ))"
    HG[hc0+c+1]=$REPLY
  done
  if (( nw )); then
    (( lx = (W - (nw + 1) / 2) / 2 * 2, ly = (nr - 1) * 4 ))
    (( lx < cmin )) && cmin=lx; (( lx + nw > cmax )) && cmax=lx+nw
    for (( i = 1; i <= ${#nx}; i++ )); do
      (( sx = cx + RANDOM % 21 - 10, sy = sy0 - RANDOM % 3, d = 0.8 + 0.45 * nx[i] / nw + (RANDOM % 15) / 100.0 ))
      PX+=($sx) PY+=($sy) PDX+=($(( lx + nx[i] - sx ))) PDY+=($(( ly + ny[i] - sy ))) PW+=($(( RANDOM % 13 - 6 ))) PD+=($d) PG+=(3)
      (( d > maxd )) && maxd=$d
    done
  fi
  n=${#PX}
  (( cmin = (cmin - 7) / 2, cmin = cmin < 0 ? 0 : cmin, cmax = (cmax + 7) / 2, cmax = cmax > W - 1 ? W - 1 : cmax ))
  (( rmin = hr - 1, rmax = sy0 / 4 ))
  [[ -n $plainname ]] && _sw_put $nr $(( (W - ${#plainname}) / 2 + 1 )) "$green$plainname$r0"

  local -F t0=$EPOCHREALTIME t p e dur=0.8 tset tend
  (( tset = maxd + dur, tend = tset + 1.6 ))
  local -i x y k m row stage=2 hint=0
  local -a M C BIT=(1 2 4 64 8 16 32 128)
  local line cur sgr ycol=$SW_C[yellow] gcol="1;$SW_C[green]"
  while :; do
    (( t = EPOCHREALTIME - t0 ))
    if (( art && stage < 5 && t >= (stage - 2) * 0.1 )); then (( stage++ )); _sw_art_at $ar $stage matcha; fi
    M=() C=()
    for (( i = 1; i <= n; i++ )); do
      (( p = (t - PD[i]) / dur ))
      (( p <= 0 )) && continue
      if (( p >= 1 )); then
        (( t > tset - 0.3 && RANDOM % 40 == 0 )) && continue          # landed dots twinkle
        (( x = PX[i] + PDX[i], y = PY[i] + PDY[i] ))
      else
        (( e = 1 - (1 - p) * (1 - p) * (1 - p) ))
        (( x = PX[i] + PDX[i] * e + PW[i] * sin(p * 3.14159), y = PY[i] + PDY[i] * e ))
        (( x < 0 )) && x=0
      fi
      (( k = (y >> 2) * W + (x >> 1) + 1 ))
      (( M[k] |= BIT[((x & 1) << 2) + (y & 3) + 1], C[k] = p < 0.8 ? 1 : PG[i] ))
    done
    print -n $'\e[?2026h'
    for (( row = rmin; row <= rmax; row++ )); do
      line= cur=
      for (( c = cmin; c <= cmax; c++ )); do
        (( k = row * W + c + 1, m = M[k] ))
        if (( m )); then
          case $C[k] in 1) sgr=$ycol ;; 2) sgr=${HG[c+1]:-$pink} ;; *) sgr=$gcol ;; esac
          [[ $sgr != $cur ]] && { line+=$'\e[0;'"${sgr}m"; cur=$sgr }
          line+=$SW_BR[m]
        else line+=' '; fi
      done
      _sw_put $(( row + 1 )) $(( cmin + 1 )) "$line$r0"
    done
    if (( ! hint && t > tset )); then hint=1; _sw_put $tr $(( (W - ${#tip}) / 2 + 1 )) "$dim$tip$r0"; fi
    print -n $'\e[?2026l'
    (( t > tend )) && break
    ui_keyx 0.03
    [[ $REPLY == timeout ]] || return 0
  done
  return 0
}

# The pages, one after the other. Status 0 = Finish, 1 = left (or Ctrl-C: UI_INT is set)
_sw_pages() {
  local -i p=1
  local -a pages
  while :; do
    # The pages after "features" depend on what is turned on
    pages=(lang name theme start features)
    lotus_feature_on weather && pages+=(weather)
    lotus_feature_on ai && pages+=(ai)
    lotus_feature_on bg && pages+=(bgmodel bgout bgwhen)
    lotus_feature_on pets && (( ! ${#PET_N} )) && pages+=(pet petname)
    pages+=(review)
    (( p > ${#pages} )) && return 0
    if (( p < 1 )); then
      _sw_quit && return 1
      (( UI_INT )) && return 1
      p=1; continue
    fi
    if _sw_$pages[p]; then (( p++ )); else (( p-- )); fi
    (( UI_INT )) && return 1
  done
}

lotus_cmd_setup_wizard() {
  lotus_lang_group setup
  if ! ui_has_tty; then return 1; fi
  source $LOTUS_ROOT/lib/cmd/bg.zsh
  lotus_lang_group bg
  lotus_features
  lotus_log INFO setup "Setup wizard started"
  local -i sw_claude=0 sw_bg_now=0 rc
  local sw_pet_kind= sw_pet_name= sw_pet_seen= SW_PET_SHOW=
  source $LOTUS_ROOT/lib/cmd/pets.zsh
  lotus_lang_group pets
  _pet_load; _pet_species
  # The Remove BG pickers draw in the wizard's style
  local UI_SELECT_HOOK=_sw_select UI_LINE_HOOK=_sw_input
  # Keys pressed while the page draws are not echoed (no ^[[B on the screen); the terminal
  # settings come back below – not from a trap, traps here never start a program.
  local tty_saved
  tty_saved=$(stty -g < /dev/tty 2>/dev/null)
  stty -echo < /dev/tty 2>/dev/null
  _sw_colors; _sw_art_load; _sw_size
  SW_STEP=1 SW_STAGE=1 SW_ART_THEME=matcha SW_ON_MOVE= SW_PAINT= SW_DETAIL= UI_INT=0
  print -n $'\e[?1049h\e[?7l\e[?25l'
  trap 'print -n "\e[0m\e[?7h\e[?25h\e[?1049l"' EXIT
  TRAPINT() { UI_INT=1; return 0 }
  _sw_pages; rc=$?
  (( rc == 0 )) && _sw_finale
  unfunction TRAPINT 2>/dev/null
  [[ -t 1 ]] && trap 'exit 130' INT
  trap - EXIT
  print -n $'\e[0m\e[?7h\e[?25h\e[?1049l'
  [[ -n $tty_saved ]] && stty $tty_saved < /dev/tty 2>/dev/null
  UI_SELECT_HOOK= UI_LINE_HOOK=      # what follows (Claude, Remove BG) asks in the normal style
  if (( rc )); then
    if (( UI_INT )); then lotus_log INFO setup "Setup wizard interrupted"; return 130; fi
    lotus_log INFO setup "Setup wizard cancelled"
    return 1
  fi

  LOTUS_CONFIGURED=1 LOTUS_CONFIG_VERSION=3
  lotus_colors
  lotus_save
  lotus_build force
  lotus_log INFO setup "Setup finished (features off: ${LOTUS_FEATURES_OFF:-none})"
  local msg=$LOTUS_L[sw_done]
  if [[ -n $LOTUS_NAME ]]; then msg=${msg//\%s/$LOTUS_NAME}; else msg=${msg//, \%s/}; msg=${msg//\%s/}; fi
  ui_blank
  ui_success $msg
  ui_dim "  $LOTUS_L[sw_done_hint]"
  ui_blank
  if [[ -n $sw_pet_kind && -n $sw_pet_name ]] && lotus_feature_on pets && lotus_pets_adopt $sw_pet_kind "$sw_pet_name" quiet; then
    lotus_pet_intro "$sw_pet_name"
  fi
  if (( sw_claude )); then source $LOTUS_ROOT/lib/cmd/ai.zsh; lotus_ai_login; fi
  if (( sw_bg_now )) && lotus_feature_on bg; then lotus_bg_install || true; fi
  return 0
}

# lotus features                 the checklist
# lotus features <id> on|off     switch one feature (for scripts)
lotus_features_page() {
  lotus_lang_group setup
  lotus_features
  local id
  if [[ -n $1 ]]; then
    id=$1
    if [[ -z ${LOTUS_FEATURE_ROW[$id]} || $id == core ]]; then
      ui_error "$LOTUS_L[sw_feat_unknown]" "$id" "${(j:, :)${LOTUS_FEATURE_IDS:#core}}"; return 1
    fi
    case $2 in
      on|1|yes)  lotus_feature_set $id 1 ;;
      off|0|no)  lotus_feature_set $id 0 ;;
      *)         ui_error "$LOTUS_L[sw_feat_onoff]" "$2" "lotus features $id on   ·   lotus features $id off"; return 1 ;;
    esac
    lotus_save
    lotus_feature_label $id
    lotus_feature_on $id && ui_success "${LOTUS_L[feat_now_on]//\%s/$REPLY}" || ui_info "${LOTUS_L[feat_is_off]//\%s/$REPLY}"
    return 0
  fi
  if ! { [[ -t 1 ]] && ui_has_tty }; then
    local state
    for id in $LOTUS_FEATURE_IDS; do
      lotus_feature_label $id
      lotus_feature_on $id && state=on || state=off       # no subshell per feature
      print -r -- "${(r:12:)id} ${(r:22:)REPLY} $state"
    done
    return 0
  fi
  local before=$LOTUS_FEATURES_OFF
  ui_hero $LOTUS_L[sw_feat_title] $LOTUS_L[sw_feat_sub]
  _lotus_feature_toggles || { ui_info $LOTUS_L[cancelled]; return 0 }
  if [[ $LOTUS_FEATURES_OFF == $before ]]; then ui_info $LOTUS_L[sw_feat_same]; return 0; fi
  lotus_save
  ui_success $LOTUS_L[sw_feat_saved]
  if lotus_feature_on bg && (( ! LOTUS_BG_READY )) && [[ " $before " == *" bg "* ]]; then
    lotus_lang_group bg
    ui_dim "  $LOTUS_L[bg_on_hint]"
  fi
  ui_blank
}
