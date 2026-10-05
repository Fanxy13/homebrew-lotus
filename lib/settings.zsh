# lotus – settings menu (lotus settings or /settings)
# Returns 10 when lotus was uninstalled, so the shell can unload it.

lotus_settings_ui() {
  emulate -L zsh
  setopt extendedglob

  local hush=$HOME/.hushlogin hush_mark=$LOTUS_CONF/hushlogin-by-lotus
  local -i LOTUS_HUSH=0 sel=2 i rc=0
  [[ -e $hush ]] && LOTUS_HUSH=1
  local msg= key rest
  local -a items

  # type|variable|label|values (value=label;…) – rebuilt when the language changes
  _ls_items() {
    items=(
      "head||$LOTUS_L[head_general]|"
      "text|LOTUS_NAME|$LOTUS_L[name]|"
      "choice|LOTUS_LANG|$LOTUS_L[lang]|en=English;de=Deutsch;fr=Français;es=Español"
      "bool|LOTUS_STARTUP|$LOTUS_L[startup]|"
      "choice|LOTUS_LOGO|$LOTUS_L[logo]|lotus=$LOTUS_L[logo_lotus];none=$LOTUS_L[logo_none]"
      "choice|LOTUS_THEME|$LOTUS_L[theme]|matcha=Matcha;sakura=Sakura;ocean=$LOTUS_L[theme_ocean];sunset=Sunset;mono=Mono"
      "bool|LOTUS_PROMPT|$LOTUS_L[prompt]|"
      "bool|LOTUS_HUSH|$LOTUS_L[hush]|"
      "head||$LOTUS_L[head_greeting]|"
      "choice|LOTUS_GREETING|$LOTUS_L[greet_top]|rotate=$LOTUS_L[rotate];random=$LOTUS_L[random];off=$LOTUS_L[off]"
      "choice|LOTUS_SALUTE|$LOTUS_L[greet_bottom]|fr=$LOTUS_L[sal_fr];de=$LOTUS_L[sal_de];en=$LOTUS_L[sal_en];es=$LOTUS_L[sal_es];off=$LOTUS_L[off]"
      "head||$LOTUS_L[head_sections]|"
      "bool|LOTUS_SHOW_HARDWARE|$LOTUS_L[sec_hw]|"
      "bool|LOTUS_SHOW_SESSION|$LOTUS_L[sec_session]|"
      "bool|LOTUS_SHOW_TIME|$LOTUS_L[sec_time]|"
      "bool|LOTUS_SHOW_MUSIC|$LOTUS_L[sec_music]|"
      "head||$LOTUS_L[head_np]|"
      "bool|LOTUS_LIVE|$LOTUS_L[live]|"
      "choice|LOTUS_INTERVAL|$LOTUS_L[interval]|1=$LOTUS_L[sec1];2=2 $LOTUS_L[secs];3=3 $LOTUS_L[secs];5=5 $LOTUS_L[secs]"
      "choice|LOTUS_COLORS|$LOTUS_L[colors]|auto=$LOTUS_L[col_auto];truecolor=$LOTUS_L[col_tc];256=$LOTUS_L[col_256]"
      "head||$LOTUS_L[head_lotus]|"
      "action|uninstall|$LOTUS_L[uninstall]|"
    )
  }

  _ls_field() { reply=("${(@s:|:)items[$1]}") }

  _ls_move() {
    local -i n=${#items} j=$sel
    repeat $n; do
      (( j = (j - 1 + $1 + n) % n + 1 ))
      _ls_field $j
      [[ $reply[1] != head ]] && { sel=$j; return }
    done
  }

  _ls_draw() {
    local acc=$LOTUS_C[accent] dim=$LOTUS_C[dim] out=$'\e[H\e[K\n'
    local t k label v shown
    local -a vals keys
    out+="  "$'\e[1;'"${acc}m🪷 lotus"$'\e[0;'"${dim}m  $LOTUS_L[settings] · v$LOTUS_VERSION"$'\e[0m\e[K\n\e[K\n'
    for i in {1..${#items}}; do
      _ls_field $i
      t=$reply[1] k=$reply[2] label=$reply[3]
      if [[ $t == head ]]; then
        (( i > 1 )) && out+=$'\e[K\n'
        out+="  "$'\e['"${dim}m${label:u}"$'\e[0m\e[K\n'
        continue
      fi
      v=${(P)k}
      case $t in
        bool)   (( v )) && shown=$'\e['"${LOTUS_C[key]}m● $LOTUS_L[on]"$'\e[0m' \
                        || shown=$'\e['"${dim}m○ ${(L)LOTUS_L[off]}"$'\e[0m' ;;
        choice) vals=(${(s:;:)reply[4]}); keys=(${vals%%=*})
                shown=${${vals[${keys[(i)$v]}]}#*=}
                (( i == sel )) && shown="‹ $shown ›" ;;
        text)   shown=$v; (( i == sel )) && shown+=$'\e['"${dim}m  $LOTUS_L[edit]"$'\e[0m' ;;
        action) shown=; (( i == sel )) && shown=$'\e['"${dim}m$LOTUS_L[run]"$'\e[0m' ;;
      esac
      label=${(r:32:)label}
      [[ $t == action ]] && label=$'\e[38;5;203m'"$label"$'\e[0m'
      if (( i == sel )); then
        out+=$'  \e['"${acc}m›"$'\e[0;1m '"$label"$'\e[0m'"$shown"$'\e[K\n'
      else
        out+="    $label$shown"$'\e[K\n'
      fi
    done
    out+=$'\e[K\n  \e['"${dim}m$LOTUS_L[footer]"$'\e[0m\e[K\n'
    out+="  ${msg}"$'\e[K\e[J'
    print -rn -- $out
    msg=
  }

  # Asks at the bottom of the screen; returns 0 for yes
  _ls_ask() {
    print -n $'\e['"${LINES:-24};1H"$'\e[K\e[?25h  '
    read -q "?$1"
    local -i yes=$?
    print -n $'\e[?25l'
    return yes
  }

  _ls_change() {
    _ls_field $sel
    local t=$reply[1] k=$reply[2]
    local -a vals keys
    local -i j
    case $t in
      bool)
        (( ${(P)k} )) && typeset -g $k=0 || typeset -g $k=1 ;;
      choice)
        vals=(${(s:;:)reply[4]}); keys=(${vals%%=*})
        j=${keys[(i)${(P)k}]}
        (( j = (j - 1 + $1 + ${#keys}) % ${#keys} + 1 ))
        typeset -g $k=$keys[j] ;;
      text)
        local new
        print -n $'\e['"${LINES:-24};1H"$'\e[K\e[?25h  '"$reply[3]: "
        read -r new
        print -n $'\e[?25l'
        [[ -n ${new// } ]] && typeset -g $k=${new## #} ;;
      action)
        if [[ $k == uninstall ]] && _ls_ask $LOTUS_L[confirm_un]; then
          rc=10
        fi
        return ;;
    esac
    if [[ $k == LOTUS_HUSH ]]; then
      if (( LOTUS_HUSH )); then
        [[ -e $hush ]] || { : >| $hush; zf_mkdir -p $LOTUS_CONF; : >| $hush_mark }
      else
        rm -f $hush $hush_mark
      fi
    else
      lotus_save
      lotus_lang
      lotus_colors
      [[ $k == LOTUS_LANG ]] && _ls_items
    fi
    msg=$'\e['"${LOTUS_C[key]}m$LOTUS_L[saved]"$'\e[0m'
  }

  _ls_preview() {
    print -n $'\e[H\e[2J'
    lotus_render
    print -n $'\n  \e['"${LOTUS_C[dim]}m$LOTUS_L[back]"$'\e[0m'
    read -rsk1
    print -n $'\e[2J'
  }

  _ls_items
  print -n $'\e[?1049h\e[?25l\e[2J'
  trap 'print -n "\e[?1049l\e[?25h"' EXIT
  trap 'return 130' INT

  while (( rc == 0 )); do
    _ls_draw
    read -rsk1 key || break
    if [[ $key == $'\e' ]]; then
      read -rsk2 -t 0.05 rest && key+=$rest
    fi
    case $key in
      $'\e[A'|k)                  _ls_move -1 ;;
      $'\e[B'|j)                  _ls_move 1 ;;
      $'\e[C'|l|' '|$'\n'|$'\r')  _ls_change 1 ;;
      $'\e[D'|h)                  _ls_field $sel; [[ $reply[1] == (text|action) ]] || _ls_change -1 ;;
      v|p)                        _ls_preview ;;
      r)  local name=$LOTUS_NAME lang=$LOTUS_LANG
          lotus_defaults; LOTUS_NAME=$name LOTUS_LANG=$lang
          lotus_save; lotus_lang; lotus_colors; _ls_items
          msg=$'\e['"${LOTUS_C[key]}m$LOTUS_L[reset_done]"$'\e[0m' ;;
      q|Q|$'\e')                  break ;;
    esac
  done

  unfunction _ls_items _ls_field _ls_move _ls_draw _ls_ask _ls_change _ls_preview
  if (( rc == 10 )); then
    print -n $'\e[?1049l\e[?25h'
    cmd_uninstall --yes
  fi
  return rc
}
