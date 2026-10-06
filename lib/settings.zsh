# lotus – settings menu (lotus settings or /settings)
# Returns 10 when lotus was uninstalled, so the shell can unload it.

lotus_settings_ui() {
  emulate -L zsh
  setopt extendedglob

  local hush=$HOME/.hushlogin hush_mark=$LOTUS_CONF/hushlogin-by-lotus
  local -i LOTUS_HUSH=0 sel=2 i rc=0 top=1
  [[ -e $hush ]] && LOTUS_HUSH=1
  local msg= key rest
  local -a items

  # type|variable|label|values (value=label;…) – rebuilt when the language changes
  _ls_items() {
    local n themes= logos=
    for n in $LOTUS_THEME_NAMES; do themes+="$n=$LOTUS_THEME_LABELS[$n];"; done
    for n in lotus minimal large terminal custom none; do logos+="$n=$LOTUS_LOGO_LABELS[$n];"; done
    items=(
      "head||$LOTUS_L[head_general]|"
      "text|LOTUS_NAME|$LOTUS_L[name]|"
      "choice|LOTUS_LANG|$LOTUS_L[lang]|en=English;de=Deutsch;fr=Français;es=Español"
      "bool|LOTUS_STARTUP|$LOTUS_L[startup]|"
      "choice|LOTUS_LOGO|$LOTUS_L[logo]|${logos%;}"
      "action|logos|$LOTUS_L[logos_action]|"
      "choice|LOTUS_THEME|$LOTUS_L[theme]|${themes%;}"
      "bool|LOTUS_PROMPT|$LOTUS_L[prompt]|"
      "bool|LOTUS_HUSH|$LOTUS_L[hush]|"
      "head||$LOTUS_L[head_greeting]|"
      "choice|LOTUS_GREETING|$LOTUS_L[greet_top]|rotate=$LOTUS_L[rotate];random=$LOTUS_L[random];off=$LOTUS_L[off]"
      "choice|LOTUS_SALUTE|$LOTUS_L[greet_bottom]|off=$LOTUS_L[off];fr=$LOTUS_L[sal_fr];de=$LOTUS_L[sal_de];en=$LOTUS_L[sal_en];es=$LOTUS_L[sal_es]"
      "head||$LOTUS_L[head_sections]|"
      "bool|LOTUS_SHOW_HARDWARE|$LOTUS_L[sec_hw]|"
      "bool|LOTUS_SHOW_SESSION|$LOTUS_L[sec_session]|"
      "bool|LOTUS_SHOW_TIME|$LOTUS_L[sec_time]|"
      "bool|LOTUS_SHOW_MUSIC|$LOTUS_L[sec_music]|"
      "head||$LOTUS_L[head_np]|"
      "bool|LOTUS_LIVE|$LOTUS_L[live]|"
      "choice|LOTUS_INTERVAL|$LOTUS_L[interval]|1=$LOTUS_L[sec1];2=2 $LOTUS_L[secs];3=3 $LOTUS_L[secs];5=5 $LOTUS_L[secs]"
      "choice|LOTUS_COLORS|$LOTUS_L[colors]|auto=$LOTUS_L[col_auto];truecolor=$LOTUS_L[col_tc];256=$LOTUS_L[col_256]"
      "choice|LOTUS_VISUAL_MODE|$LOTUS_L[visual_mode]|bars=Bars;wave=Wave;spectrum=Spectrum;particles=Particles;minimal=Minimal;circular=Circular;retro=Retro terminal;matrix=Matrix"
      "head||$LOTUS_L[head_weather]|"
      "text|LOTUS_WEATHER_LOCATION|$LOTUS_L[weather_city]|"
      "choice|LOTUS_WEATHER_UNITS|$LOTUS_L[units]|metric=°C, km/h;imperial=°F, mph"
      "choice|LOTUS_SEARCH_ENGINE|$LOTUS_L[search_engine]|google=Google;duckduckgo=DuckDuckGo;bing=Bing;ecosia=Ecosia;brave=Brave Search"
      "head||$LOTUS_L[head_ai]|"
      "choice|LOTUS_AI_PROVIDER|$LOTUS_L[ai_provider]|auto=$LOTUS_L[col_auto];claude=Claude;apple=Apple Intelligence;ollama=Ollama;openai=OpenAI-compatible"
      "choice|LOTUS_AI_EFFORT|$LOTUS_L[ai_effort]|low=$LOTUS_L[effort_low];medium=$LOTUS_L[effort_medium];high=$LOTUS_L[effort_high];max=$LOTUS_L[effort_max]"
      "text|LOTUS_AI_MODEL|$LOTUS_L[ai_model]|"
      "text|LOTUS_AI_URL|$LOTUS_L[ai_url]|"
      "action|aikey|$LOTUS_L[ai_key]|"
      "head||$LOTUS_L[head_lotus]|"
      "action|shortcuts|$LOTUS_L[shortcuts_action]|"
      "action|setup|$LOTUS_L[setup_again]|"
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

  # All rows of the menu; only the part around the selection fits on screen
  _ls_draw() {
    local acc=$LOTUS_C[accent] dim=$LOTUS_C[dim] t k label v shown
    local -a vals keys rows
    local -i selrow h
    for i in {1..${#items}}; do
      _ls_field $i
      t=$reply[1] k=$reply[2] label=$reply[3]
      if [[ $t == head ]]; then
        (( i > 1 )) && rows+=("")
        rows+=("  "$'\e['"${dim}m${label:u}"$'\e[0m')
        continue
      fi
      v=${(P)k}
      case $t in
        bool)   (( v )) && shown=$'\e['"${LOTUS_C[key]}m● $LOTUS_L[on]"$'\e[0m' \
                        || shown=$'\e['"${dim}m○ ${(L)LOTUS_L[off]}"$'\e[0m' ;;
        choice) vals=(${(s:;:)reply[4]}); keys=(${vals%%=*})
                shown=${${vals[${keys[(i)$v]}]}#*=}
                (( i == sel )) && shown="‹ $shown ›" ;;
        text)   shown=${v:-$'\e['"${dim}m–"$'\e[0m'}; (( i == sel )) && shown+=$'\e['"${dim}m  $LOTUS_L[edit]"$'\e[0m' ;;
        action) shown=; (( i == sel )) && shown=$'\e['"${dim}m$LOTUS_L[run]"$'\e[0m' ;;
      esac
      label=${(r:32:)label}
      [[ $k == uninstall ]] && label=$'\e[38;5;203m'"$label"$'\e[0m'
      if (( i == sel )); then
        selrow=$(( ${#rows} + 1 ))
        rows+=($'  \e['"${acc}m›"$'\e[0;1m '"$label"$'\e[0m'"$shown")
      else
        rows+=("    $label$shown")
      fi
    done
    (( h = ${LINES:-24} - 7, h = h < 6 ? 6 : h ))
    (( selrow < top + 1 )) && (( top = selrow > 2 ? selrow - 2 : 1 ))
    (( selrow > top + h - 2 )) && (( top = selrow - h + 2 ))
    (( top > ${#rows} - h + 1 )) && (( top = ${#rows} - h + 1 ))
    (( top < 1 )) && top=1
    local out=$'\e[H\e[K\n'
    out+="  "$'\e[1;'"${acc}mlotus"$'\e[0;'"${dim}m / $LOTUS_L[settings] · v$LOTUS_VERSION"$'\e[0m\e[K\n\e[K\n'
    for (( i = top; i < top + h && i <= ${#rows}; i++ )); do out+="${rows[i]}"$'\e[K\n'; done
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

  # Runs a bigger screen (logos, shortcuts, …), then comes back to the menu
  _ls_run() {
    print -n $'\e[H\e[2J\e[?25h'
    source $LOTUS_ROOT/lib/cmd/$1.zsh
    lotus_cmd_$1 "${@[2,-1]}"
    lotus_load; _ls_items
    print -n $'\e[?25l'
    ui_dim "$LOTUS_L[back]"; ui_key
    print -n $'\e[2J'
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
        [[ $k == LOTUS_NAME && -z ${new// } ]] && return
        typeset -g $k=${new## #} ;;
      action)
        case $k in
          uninstall) _ls_ask "$LOTUS_L[confirm_un]" && rc=10 ;;
          logos)     _ls_run logo logo ;;
          shortcuts) _ls_run shortcuts shortcuts ;;
          setup)     _ls_run setup setup ;;
          aikey)     _ls_run ai ai key ;;
        esac
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
      r)  if _ls_ask "Reset all settings (name, language and shortcuts stay)? [y/N] "; then
            local name=$LOTUS_NAME lang=$LOTUS_LANG
            local -A shortcuts=("${(@kv)LOTUS_SHORTCUTS}")
            lotus_defaults; LOTUS_NAME=$name LOTUS_LANG=$lang LOTUS_CONFIGURED=1 LOTUS_CONFIG_VERSION=2
            LOTUS_SHORTCUTS=("${(@kv)shortcuts}")
            lotus_save; lotus_lang; lotus_colors; _ls_items
            msg=$'\e['"${LOTUS_C[key]}m$LOTUS_L[reset_done]"$'\e[0m'
          fi ;;
      q|Q|$'\e')                  break ;;
    esac
  done

  unfunction _ls_items _ls_field _ls_move _ls_draw _ls_ask _ls_run _ls_change _ls_preview
  if (( rc == 10 )); then
    print -n $'\e[?1049l\e[?25h'
    source $LOTUS_ROOT/lib/cmd/system.zsh
    lotus_uninstall --yes
  fi
  return rc
}
