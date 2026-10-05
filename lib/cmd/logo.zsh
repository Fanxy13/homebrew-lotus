# lotus – logos: preview the built-in ones, paste your own ASCII art
#   lotus logo                 preview all logos and pick one
#   lotus logo import          paste ASCII art (or: lotus logo import --clipboard)
#   lotus logo reset           back to Lotus Classic

typeset -gi LOGO_MAX_W=80 LOGO_MAX_H=40

lotus_cmd_logo() {
  shift
  case $1 in
    import)  lotus_logo_import $2 ;;
    reset)   LOTUS_LOGO=lotus; lotus_save; ui_success "Logo: Lotus Classic" ;;
    preview) lotus_logo_preview ${2:-$LOTUS_LOGO} ;;
    *)       lotus_logo_pick ;;
  esac
}

lotus_logo_preview() {   # <logo name>
  lotus_logo_file $1
  [[ -z $REPLY ]] && { ui_dim "(no logo)"; return }
  local line c=$'\e[1;'"$LOTUS_C[logo]m"
  for line in "${(@f)$(<$REPLY)}"; do print -r -- "  $c${line//\$\$/\$}"$'\e[0m'; done
}

lotus_logo_pick() {
  local n
  local -a names=(lotus minimal large terminal) labels=()
  [[ -r $LOTUS_CONF/logo.txt ]] && names+=(custom)
  names+=(none)
  for n in $names; do labels+=("$LOTUS_LOGO_LABELS[$n]${${(M)n:#$LOTUS_LOGO}:+  (current)}"); done
  ui_header Logos
  lotus_logo_preview minimal
  ui_blank
  ui_choose "Preview a logo" $labels "Paste my own ASCII art" || return 0
  if (( REPLY > ${#names} )); then lotus_logo_import; return; fi
  local pick=$names[REPLY]
  print -n $'\e[H\e[2J'
  ui_header "Logo" $LOTUS_LOGO_LABELS[$pick]
  lotus_logo_preview $pick
  ui_blank
  ui_confirm "Use $LOTUS_LOGO_LABELS[$pick]?" y || return 0
  LOTUS_LOGO=$pick; lotus_save
  ui_success "Logo: $LOTUS_LOGO_LABELS[$pick]"
}

# Cleans pasted art: no colors or control characters, tabs → spaces, "$" kept literal for fastfetch
lotus_logo_clean() {
  setopt localoptions extendedglob
  local text=$1 line
  local -a out
  text=${text//$'\e'\[[0-9;?]#[a-zA-Z]/}
  text=${text//$'\t'/    }
  for line in "${(@f)text}"; do
    line=${line//[[:cntrl:]]/}
    out+=("${line%%[[:space:]]#}")
  done
  while (( ${#out} )) && [[ -z ${out[1]// } ]]; do out[1]=(); done
  while (( ${#out} )) && [[ -z ${out[-1]// } ]]; do out[-1]=(); done
  reply=("${out[@]}")
}

lotus_logo_import() {
  local text
  ui_header Logo "your own ASCII art"
  if [[ $1 == --clipboard ]]; then
    text=$(pbpaste 2>/dev/null)
  else
    ui_text "Paste your ASCII art, then type a single . on its own line (or press Ctrl-D)."
    ui_dim  "Tip: the Lotus website has an ASCII art page with a prompt for AI tools."
    ui_blank
    local line
    while IFS= read -r line < /dev/tty; do
      [[ $line == . ]] && break
      text+=$line$'\n'
    done
  fi
  lotus_logo_clean "$text"
  local -a art=("${reply[@]}")
  if (( ! ${#art} )); then ui_error "Nothing to import" "" "Copy ASCII art first or paste it here."; return 1; fi
  local -i w=0 l
  for line in $art; do (( ${#line} > w )) && w=${#line}; done
  if (( w > LOGO_MAX_W || ${#art} > LOGO_MAX_H )); then
    ui_error "That logo is too big" "${w} × ${#art} characters" "Lotus logos can be up to $LOGO_MAX_W wide and $LOGO_MAX_H lines tall."
    return 1
  fi
  ui_blank
  local c=$'\e[1;'"$LOTUS_C[logo]m"
  for line in $art; do print -r -- "  $c$line"$'\e[0m'; done
  ui_blank
  ui_confirm "Use this logo?" y || return 0
  zf_mkdir -p $LOTUS_CONF
  print -rl -- "${(@)art//\$/\$\$}" >| $LOTUS_CONF/logo.txt
  LOTUS_LOGO=custom; lotus_save
  ui_success "Saved as your logo (${w} × ${#art})"
}
