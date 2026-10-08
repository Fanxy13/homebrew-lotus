# lotus – reusable terminal UI components (themed, no emojis).
# Every Lotus command builds its screens from these functions.

typeset -g _UI_R=$'\e[0m' _UI_B=$'\e[1m'

ui_c() { REPLY=$'\e['"${LOTUS_C[$1]:-0}m" }          # theme color by role → REPLY

# Header:  lotus / Weather   (optional dim subtitle on the right)
ui_header() {
  local a=$'\e[1;'"$LOTUS_C[accent]m" d=$'\e['"$LOTUS_C[dim]m"
  print -r -- ""
  print -r -- "  ${a}lotus${_UI_R}${d} / ${_UI_R}${_UI_B}$1${_UI_R}${2:+${d}  $2${_UI_R}}"
  print -r -- ""
}

ui_text()  { print -r -- "  $*" }
ui_dim()   { print -r -- "  "$'\e['"$LOTUS_C[dim]m$*"$_UI_R }
ui_blank() { print -r -- "" }

ui_success() { print -r -- "  "$'\e[1;'"$LOTUS_C[key]m✓${_UI_R} $*" }
ui_warn()    { print -r -- "  "$'\e[1;'"$LOTUS_C[key2]m!${_UI_R} $*"; lotus_log WARN ${LOTUS_LOG_COMP:-ui} "$*" }
ui_info()    { print -r -- "  "$'\e['"$LOTUS_C[accent]m›${_UI_R} $*" }
ui_step()    { print -r -- "  "$'\e['"$LOTUS_C[dim]m…${_UI_R} $*" }

# Error screen: title, message, then optional hint lines (also written to the log)
ui_error() {
  local title=$1 msg=$2; shift $(( $# < 2 ? $# : 2 ))
  lotus_log ERROR ${LOTUS_LOG_COMP:-ui} "$title${msg:+ – $msg}"
  print -r -- ""
  print -r -- "  "$'\e[1;38;5;203m'"✗ $title$_UI_R"
  [[ -n $msg ]] && print -r -- "    $msg"
  local h
  for h in "$@"; do print -r -- "    "$'\e['"$LOTUS_C[dim]m$h$_UI_R"; done
  print -r -- ""
}

# Box in the start screen style:  ui_card "Title" "KEY|value" "KEY|value" …
ui_card() {
  local title=$1 row k v b=$'\e['"$LOTUS_C[border]m" key=$'\e[1;'"$LOTUS_C[key]m"
  shift
  lotus_box_parts $title
  print -r -- "  ${b}${reply[1]}"$'\e['"$LOTUS_C[accent]m $title ${b}${reply[2]}${_UI_R}"
  for row in "$@"; do
    k=${row%%|*} v=${row#*|}
    if [[ $row == '|' || -z $row ]]; then
      print -r -- "  ${b}│${_UI_R}"
    else
      print -r -- "  ${b}├─${_UI_R} ${key}${(r:10:)k}${_UI_R} $v"
    fi
  done
  lotus_line 42
  print -r -- "  ${b}└${REPLY}┘${_UI_R}"
}

# Category line:  ui_category "Browsers" 9
ui_category() {
  print -r -- "  "$'\e[1;'"$LOTUS_C[accent]m${1:u}${_UI_R}"$'\e['"$LOTUS_C[dim]m  $2${_UI_R}"
}

# Search result row:  ui_result <index> <name> <meta> <description> [installed]
ui_result() {
  local idx=$1 name=$2 meta=$3 desc=$4 inst=$5
  local d=$'\e['"$LOTUS_C[dim]m" k=$'\e['"$LOTUS_C[key]m"
  local mark=" "
  [[ -n $inst ]] && mark="${k}●${_UI_R}"
  print -r -- "  ${d}${(l:2:)idx}${_UI_R} ${mark} ${_UI_B}${(r:24:)${name[1,24]}}${_UI_R} ${d}${(r:12:)meta}${_UI_R} ${desc[1,${COLUMNS:-100}-46]}"
}

# Progress bar:  ui_progress <label> <percent>   (redraws the same line)
ui_progress() {
  local -i pct=$2 n
  (( pct < 0 )) && pct=0; (( pct > 100 )) && pct=100
  n=$(( pct * 24 / 100 ))
  print -rn -- $'\r\e[K'"  $1 [""${${(l:n::x:)}//x/■}""${${(l:24-n::x:)}//x/·}""] ${pct}%"
  (( pct == 100 )) && print
}

# Yes/no question, single key.  ui_confirm "Install Firefox?" [y|n default]
ui_confirm() {
  local def=${2:-n} key hint="[y/N]"
  [[ $def == y ]] && hint="[Y/n]"
  print -rn -- "  $1 "$'\e['"$LOTUS_C[dim]m$hint$_UI_R "
  if ! ui_has_tty; then print -r -- "(no keyboard: $def)"; [[ $def == y ]]; return; fi
  read -rsk1 key < /dev/tty
  [[ $key == $'\n' || $key == $'\r' ]] && key=$def
  if [[ $key == [yYjJ] ]]; then print -r -- "yes"; return 0; fi
  print -r -- "no"; return 1
}

# Free text input with optional default:  ui_input "City" "Zurich"  → REPLY
ui_input() {
  local ans hint=
  [[ -n $2 ]] && hint=" "$'\e['"$LOTUS_C[dim]m($2)$_UI_R"
  print -rn -- "  $1$hint: "
  if ! ui_has_tty; then print; REPLY=$2; return 1; fi
  read -r ans < /dev/tty || { REPLY=; return 1 }
  REPLY=${ans:-$2}
}

# Is there a keyboard to ask? (false in scripts, pipes and Homebrew install steps)
ui_has_tty() { [[ -t 0 ]] || { true < /dev/tty } 2>/dev/null }

# Read one key (arrows become up/down/left/right) → REPLY
ui_key() {
  local k rest
  read -rsk1 k < /dev/tty || { REPLY=quit; return }
  if [[ $k == $'\e' ]]; then
    read -rsk2 -t 0.05 rest < /dev/tty && k+=$rest
  fi
  case $k in
    $'\e[A'|$'\eOA'|k) REPLY=up ;;   $'\e[B'|$'\eOB'|j) REPLY=down ;;
    $'\e[C'|$'\eOC'|l) REPLY=right ;; $'\e[D'|$'\eOD'|h) REPLY=left ;;
    $'\n'|$'\r'|' ') REPLY=enter ;;
    $'\e'|q|Q) REPLY=quit ;;
    *) REPLY=$k ;;
  esac
}

# Pick one entry with arrows, Enter or its number; q/Esc cancels. Long lists scroll.
#   ui_choose "Title" "Label one" "Label two" …   → REPLY = index (1-based), status 1 on cancel
ui_choose() {
  local title=$1; shift
  local -a opts=("$@")
  local -i sel=1 n=${#opts} i top=1 h
  (( n )) || return 1
  (( h = ${LINES:-24} - 7, h = h < 5 ? 5 : h, h = h > n ? n : h ))
  local a=$'\e['"$LOTUS_C[accent]m" d=$'\e['"$LOTUS_C[dim]m"
  [[ -n $title ]] && print -r -- "  ${_UI_B}$title${_UI_R}"
  if ! ui_has_tty; then ui_dim "(no keyboard – cancelled)"; return 1; fi
  print -n $'\e[?25l'
  while :; do
    (( sel < top )) && top=sel
    (( sel > top + h - 1 )) && (( top = sel - h + 1 ))
    for (( i = top; i < top + h; i++ )); do
      if (( i == sel )); then
        print -r -- $'\e[K'"  ${a}›${_UI_R} ${d}${(l:2:)i}${_UI_R}  ${_UI_B}${opts[i]}${_UI_R}"
      else
        print -r -- $'\e[K'"    ${d}${(l:2:)i}${_UI_R}  ${opts[i]}"
      fi
    done
    print -rn -- $'\e[K'"  ${d}↑↓ select   ⏎ choose   q cancel${${(M)n:#<$((h+1))->}:+   $sel/$n}${_UI_R}"
    ui_key
    case $REPLY in
      up)    (( sel = sel > 1 ? sel - 1 : n )) ;;
      down)  (( sel = sel < n ? sel + 1 : 1 )) ;;
      enter) break ;;
      quit)  print -n $'\r\e[K\e[?25h\n'; return 1 ;;
      <1-9>) (( REPLY <= n )) && { sel=$REPLY; break } ;;
    esac
    print -n $'\r'"\e[${h}A"
  done
  print -n $'\r\e[K\e[?25h\n'
  REPLY=$sel
}

# ── Larger screens: setup, features, Remove BG, the log ──────

# A page title:   ◇ lotus / Remove BG     (optional dim line below)
ui_hero() {
  local a=$'\e['"$LOTUS_C[accent]m" d=$'\e['"$LOTUS_C[dim]m"
  print -r -- ""
  print -r -- "    ${a}◇${_UI_R} ${_UI_B}lotus${_UI_R}${d} / ${_UI_R}${_UI_B}$1${_UI_R}"
  [[ -n $2 ]] && { print -r -- ""; print -r -- "    ${d}$2${_UI_R}" }
  print -r -- ""
}

# Section label inside a page (small caps style, dim)
ui_section() { print -r -- "    "$'\e['"$LOTUS_C[dim]m${(U)1}"$_UI_R }

# Key/value row:  ui_kv Model BiRefNet
ui_kv() {
  local -i w=$(( ${#1} >= 12 ? ${#1} + 2 : 12 ))
  print -r -- "    "$'\e['"$LOTUS_C[dim]m${(r:w:)1}"$_UI_R"$2"
}

# Path for display: ~ for the home folder, shortened in the middle when too long → REPLY
ui_path() {
  local p=$1
  local -i cols=${COLUMNS:-80}
  (( cols > 0 )) || cols=100     # no terminal (pipes): COLUMNS is 0
  local -i max=${2:-$(( cols - 18 ))}
  [[ -n $HOME && $p == $HOME(/*|) ]] && p="~${p#$HOME}"
  (( max < 20 )) && max=20
  if (( ${#p} > max )); then
    local -i keep=$(( (max - 1) / 2 ))
    p="${p[1,keep]}…${p[-(max - keep - 1),-1]}"
  fi
  REPLY=$p
}

# One key, with more names than ui_key → REPLY:
#   up down left right home end pgup pgdn enter space tab back esc, or the character
# With a timeout in seconds it also returns "timeout" (screens that keep moving or watch the
# window size), and "interrupt" after a Ctrl-C that a TRAPINT turned into UI_INT=1.
# A keyboard that is gone counts as esc.
typeset -gi UI_FAILS=0 UI_INT=0
ui_keyx() {
  local k c rest=
  if [[ -n $1 ]]; then
    local -F t0=$EPOCHREALTIME
    if ! read -rsk1 -t $1 k < /dev/tty; then
      if (( UI_INT )); then REPLY=interrupt
      elif (( EPOCHREALTIME - t0 < $1 / 3.0 )); then (( ++UI_FAILS > 5 )) && REPLY=esc || REPLY=timeout
      else REPLY=timeout UI_FAILS=0; fi
      return
    fi
    UI_FAILS=0
    (( UI_INT )) && { REPLY=interrupt; return }
  else
    read -rsk1 k < /dev/tty || { REPLY=esc; return }
  fi
  if [[ $k == $'\e' ]]; then
    # ESC [ … letter, or ESC O letter (arrow keys in application mode)
    while read -rsk1 -t 0.02 c < /dev/tty; do rest+=$c; [[ $c == [A-Za-z~] && $rest != O ]] && break; done
    k+=$rest
  fi
  case $k in
    $'\e[A'|$'\eOA') REPLY=up ;;      $'\e[B'|$'\eOB') REPLY=down ;;
    $'\e[C'|$'\eOC') REPLY=right ;;   $'\e[D'|$'\eOD') REPLY=left ;;
    $'\e[H'|$'\e[1~') REPLY=home ;;   $'\e[F'|$'\e[4~') REPLY=end ;;
    $'\e[5~') REPLY=pgup ;;           $'\e[6~') REPLY=pgdn ;;
    $'\n'|$'\r') REPLY=enter ;;       ' ') REPLY=space ;;
    $'\t') REPLY=tab ;;               $'\x7f'|$'\b') REPLY=back ;;
    $'\e') REPLY=esc ;;
    $'\e'*) REPLY=ignore ;;
    *) REPLY=$k ;;
  esac
}

# Radio list with a short description per entry. Enter picks, Esc goes back.
#   ui_select <default index> "Label|Description" …   → REPLY = index; status 1 = back/cancel
ui_select() {
  [[ -n $UI_SELECT_HOOK ]] && { $UI_SELECT_HOOK "$@"; return }   # the setup wizard draws its own
  local -i sel=${1:-1} n i; shift
  local -a opts=("$@")
  n=${#opts}
  (( sel < 1 || sel > n )) && sel=1
  if ! ui_has_tty; then REPLY=$sel; return 0; fi
  local a=$'\e['"$LOTUS_C[accent]m" k=$'\e[1;'"$LOTUS_C[key]m" d=$'\e['"$LOTUS_C[dim]m" lbl desc
  local -i rows=0 W=${COLUMNS:-80}
  print -n $'\e[?25l'
  while :; do
    (( rows )) && print -n "\e[${rows}A"
    rows=0
    for (( i = 1; i <= n; i++ )); do
      lbl=${opts[i]%%|*} desc=${opts[i]#*|}
      [[ $desc == $opts[i] ]] && desc=
      if (( i == sel )); then
        print -r -- $'\r\e[K'"    ${k}●${_UI_R} ${_UI_B}$lbl${_UI_R}${desc:+${d}  ${desc[1,W-${#lbl}-12]}${_UI_R}}"
      else
        print -r -- $'\r\e[K'"    ${d}○${_UI_R} $lbl${desc:+${d}  ${desc[1,W-${#lbl}-12]}${_UI_R}}"
      fi
      (( rows++ ))
    done
    print -r -- $'\r\e[K'
    print -rn -- $'\r\e[K'"    ${d}${LOTUS_L[ui_select_hint]:-↑↓ choose   ⏎ continue   esc back}${_UI_R}"
    (( rows++ ))
    ui_keyx
    case $REPLY in
      up)    (( sel = sel > 1 ? sel - 1 : n )) ;;
      down|tab) (( sel = sel < n ? sel + 1 : 1 )) ;;
      enter|space|right) break ;;
      esc|left|q) print -n $'\r\e[K\e[?25h\n'; return 1 ;;
      <1-9>) (( REPLY <= n )) && sel=$REPLY ;;
    esac
    print -n $'\r'
  done
  print -n $'\r\e[K\e[?25h\n'
  REPLY=$sel
}

# Checklist: Space turns entries on and off, Enter continues, Esc goes back.
#   ui_toggles "Label|Description|locked" …   with the states in the array LOTUS_TOGGLES (1/0, changed in place)
ui_toggles() {
  local -a opts=("$@")
  local -i n=${#opts} sel=1 i rows=0 top=1 h W=${COLUMNS:-80}
  (( h = ${LINES:-24} - 12, h = h < 4 ? 4 : h, h = h > n ? n : h ))
  if ! ui_has_tty; then return 0; fi
  local k=$'\e[1;'"$LOTUS_C[key]m" a=$'\e['"$LOTUS_C[accent]m" d=$'\e['"$LOTUS_C[dim]m" lbl desc mark lock
  local -a f
  print -n $'\e[?25l'
  while :; do
    (( sel < top )) && top=sel
    (( sel > top + h - 1 )) && (( top = sel - h + 1 ))
    (( rows )) && print -n "\e[${rows}A"
    rows=0
    for (( i = top; i < top + h; i++ )); do
      f=("${(@s:|:)opts[i]}")
      lbl=$f[1] desc=$f[2] lock=$f[3]
      if [[ -n $lock ]]; then mark="${d}◉${_UI_R}"
      elif (( LOTUS_TOGGLES[i] )); then mark="${k}◉${_UI_R}"
      else mark="${d}○${_UI_R}"; fi
      if (( i == sel )); then
        print -r -- $'\r\e[K'"  ${a}›${_UI_R} $mark ${_UI_B}${(r:20:)lbl}${_UI_R} ${d}${desc[1,W-30]}${_UI_R}"
      else
        print -r -- $'\r\e[K'"    $mark ${(r:20:)lbl} ${d}${desc[1,W-30]}${_UI_R}"
      fi
      (( rows++ ))
    done
    print -r -- $'\r\e[K'
    print -rn -- $'\r\e[K'"    ${d}${LOTUS_L[ui_toggle_hint]:-↑↓ move   space on/off   ⏎ continue   esc back}${${(M)n:#<$((h+1))->}:+   $sel/$n}${_UI_R}"
    (( rows++ ))
    ui_keyx
    case $REPLY in
      up)    (( sel = sel > 1 ? sel - 1 : n )) ;;
      down|tab) (( sel = sel < n ? sel + 1 : 1 )) ;;
      space|right|left|x)
        f=("${(@s:|:)opts[sel]}")
        [[ -z $f[3] ]] && (( LOTUS_TOGGLES[sel] = ! LOTUS_TOGGLES[sel] )) ;;
      a) for (( i = 1; i <= n; i++ )); do LOTUS_TOGGLES[i]=1; done ;;
      enter) break ;;
      esc|q) print -n $'\r\e[K\e[?25h\n'; return 1 ;;
    esac
    print -n $'\r'
  done
  print -n $'\r\e[K\e[?25h\n'
  return 0
}

# Shown when a command belongs to a feature that is turned off. Status 0 = turned on just now.
lotus_feature_off_screen() {
  local id=$1
  lotus_feature_label $id
  local name=$REPLY
  ui_hero $name
  ui_text "${LOTUS_L[feat_is_off]//\%s/$name}"
  ui_blank
  ui_dim "${LOTUS_L[feat_turn_on]:-Turn it on in /settings → Features, or with: lotus features}"
  ui_blank
  [[ -t 1 ]] && ui_has_tty || return 1
  ui_confirm "${LOTUS_L[feat_on_now]:-Turn it on now?}" n || { ui_blank; return 1 }
  lotus_feature_set $id 1
  lotus_save
  ui_success "${LOTUS_L[feat_now_on]//\%s/$name}"
  ui_blank
  return 0
}

# One line of text with a default; Enter accepts, Esc goes back (status 1).  ui_line "Name" "Gabriel" → REPLY
ui_line() {
  [[ -n $UI_LINE_HOOK ]] && { $UI_LINE_HOOK "$@"; return }
  local label=$1 text=$2 d=$'\e['"$LOTUS_C[dim]m" a=$'\e['"$LOTUS_C[accent]m"
  if ! ui_has_tty; then REPLY=$text; return 0; fi
  print -n $'\e[?25h'
  local shown=
  local -i drawn=0
  while :; do
    if (( ! drawn )) || [[ $shown != $text ]]; then
      print -rn -- $'\r\e[K'"    ${d}${label}${_UI_R}  ${a}›${_UI_R} $text"
      shown=$text drawn=1
    fi
    ui_keyx 0.3
    case $REPLY in
      timeout) continue ;;
      enter) break ;;
      esc|interrupt) print; return 1 ;;
      back)  text=${text[1,-2]} ;;
      up|down|left|right|home|end|pgup|pgdn|tab|ignore|space)
             [[ $REPLY == space ]] && text+=' ' ;;
      *)     [[ $REPLY == [[:print:]] ]] && (( ${#text} < 200 )) && text+=$REPLY ;;
    esac
  done
  print
  REPLY=$text
}
