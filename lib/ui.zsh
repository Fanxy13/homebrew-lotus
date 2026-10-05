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
ui_warn()    { print -r -- "  "$'\e[1;'"$LOTUS_C[key2]m!${_UI_R} $*" }
ui_info()    { print -r -- "  "$'\e['"$LOTUS_C[accent]m›${_UI_R} $*" }
ui_step()    { print -r -- "  "$'\e['"$LOTUS_C[dim]m…${_UI_R} $*" }

# Error screen: title, message, then optional hint lines
ui_error() {
  local title=$1 msg=$2; shift $(( $# < 2 ? $# : 2 ))
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
    $'\e[A'|k) REPLY=up ;;   $'\e[B'|j) REPLY=down ;;
    $'\e[C'|l) REPLY=right ;; $'\e[D'|h) REPLY=left ;;
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
