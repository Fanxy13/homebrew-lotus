# lotus – Einstellungs-Menü (lotus settings bzw. /settings)

lotus_settings_ui() {
  emulate -L zsh
  setopt extendedglob
  lotus_load

  # Typ|Variable|Bezeichnung|Werte (wert=Anzeige;…)
  local -a items=(
    'head||Allgemein|'
    'text|LOTUS_NAME|Name|'
    'bool|LOTUS_STARTUP|Beim Öffnen anzeigen|'
    'choice|LOTUS_LOGO|Logo|lotus=Lotus;heart=Herz;none=Keins'
    'choice|LOTUS_THEME|Farbschema|matcha=Matcha;sakura=Sakura;ocean=Ozean;sunset=Sunset;mono=Mono'
    'bool|LOTUS_PROMPT|Farbiger Prompt|'
    'bool|LOTUS_HUSH|„Last login“-Zeile ausblenden|'
    'head||Begrüssung|'
    'choice|LOTUS_GREETING|Oben|rotate=15 Sprachen der Reihe nach;random=15 Sprachen zufällig;off=Aus'
    'choice|LOTUS_SALUTE|Unten, je nach Tageszeit|fr=Französisch;de=Deutsch;en=Englisch;off=Aus'
    'head||Bereiche|'
    'bool|LOTUS_SHOW_HARDWARE|Hardware|'
    'bool|LOTUS_SHOW_SESSION|Session|'
    'bool|LOTUS_SHOW_TIME|Uptime & Datum|'
    'bool|LOTUS_SHOW_MUSIC|Läuft gerade|'
    'head||Läuft gerade|'
    'bool|LOTUS_LIVE|Live aktualisieren|'
    'choice|LOTUS_INTERVAL|Aktualisieren alle|1=1 Sekunde;2=2 Sekunden;3=3 Sekunden;5=5 Sekunden'
    'choice|LOTUS_COLORS|Farbmodus|auto=Automatisch;truecolor=16 Mio. Farben;256=256 Farben'
  )
  local hush=$HOME/.hushlogin
  local -i LOTUS_HUSH=0
  [[ -e $hush ]] && LOTUS_HUSH=1

  local -i sel=2 i
  local msg= key rest

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
    out+="  "$'\e[1;'"${acc}m🪷 lotus"$'\e[0;'"${dim}m  Einstellungen · v$LOTUS_VERSION"$'\e[0m\e[K\n\e[K\n'
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
        bool)   (( v )) && shown=$'\e['"${LOTUS_C[key]}m● an"$'\e[0m' || shown=$'\e['"${dim}m○ aus"$'\e[0m' ;;
        choice) vals=(${(s:;:)reply[4]}); keys=(${vals%%=*})
                shown=${${vals[${keys[(i)$v]}]}#*=}
                (( i == sel )) && shown="‹ $shown ›" ;;
        text)   shown=$v; (( i == sel )) && shown+=$'\e['"${dim}m  ⏎ ändern"$'\e[0m' ;;
      esac
      if (( i == sel )); then
        out+=$'  \e['"${acc}m›"$'\e[0;1m '"${(r:32:)label}"$'\e[0m'"$shown"$'\e[K\n'
      else
        out+="    ${(r:32:)label}$shown"$'\e[K\n'
      fi
    done
    out+=$'\e[K\n  \e['"${dim}m↑↓ auswählen   ←→ ⏎ ändern   v Vorschau   r Standard   q fertig"$'\e[0m\e[K\n'
    out+="  ${msg}"$'\e[K\e[J'
    print -rn -- $out
    msg=
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
        [[ -n ${new// } ]] && typeset -g $k=${new## #}
        ;;
    esac
    if [[ $k == LOTUS_HUSH ]]; then
      if (( LOTUS_HUSH )); then : >| $hush; else rm -f $hush; fi
    else
      lotus_save
      lotus_colors
    fi
    msg=$'\e['"${LOTUS_C[key]}m✓ gespeichert"$'\e[0m'
  }

  _ls_preview() {
    print -n $'\e[H\e[2J'
    lotus_render
    print -n $'\n  \e['"${LOTUS_C[dim]}m(Taste drücken, um zurückzukehren)"$'\e[0m'
    read -rsk1
    print -n $'\e[2J'
  }

  print -n $'\e[?1049h\e[?25l\e[2J'
  trap 'print -n "\e[?1049l\e[?25h"' EXIT
  trap 'return 130' INT

  while :; do
    _ls_draw
    read -rsk1 key || break
    if [[ $key == $'\e' ]]; then
      read -rsk2 -t 0.05 rest && key+=$rest
    fi
    case $key in
      $'\e[A'|k)                  _ls_move -1 ;;
      $'\e[B'|j)                  _ls_move 1 ;;
      $'\e[C'|l|' '|$'\n'|$'\r')  _ls_change 1 ;;
      $'\e[D'|h)                  _ls_field $sel; [[ $reply[1] == text ]] || _ls_change -1 ;;
      v|p)                        _ls_preview ;;
      r)  local name=$LOTUS_NAME
          lotus_defaults; LOTUS_NAME=$name
          lotus_save; lotus_colors
          msg=$'\e['"${LOTUS_C[key]}m✓ Standard wiederhergestellt"$'\e[0m' ;;
      q|Q|$'\e')                  break ;;
    esac
  done
  unfunction _ls_field _ls_move _ls_draw _ls_change _ls_preview
}
