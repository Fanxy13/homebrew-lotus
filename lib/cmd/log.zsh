# lotus – /lotus log: what Lotus did, for finding out why something went wrong.
#   lotus log              interactive viewer (plain list when there is no terminal)
#   lotus log live         the viewer, following new lines
#   lotus log clear        empty the log
#   lotus log level [lvl]  show or set how much is written: off, warn, info, debug, trace
#   lotus log path         where the file is

typeset -gA _LOG_ALIAS=(off off quiet off error warn errors warn warn warn warnings warn
  info info normal info debug debug detailed debug trace trace everything trace all trace)

lotus_cmd_log() {
  shift   # "log"
  lotus_lang_group log
  case $1 in
    ''|show|view)      if [[ -t 1 ]] && ui_has_tty; then lotus_log_view; else lotus_log_print ${2:-100}; fi ;;
    live|follow|-f)    lotus_log_view live ;;
    tail|print|cat)    lotus_log_print ${2:-100} ;;
    clear|reset)       lotus_log_clear ;;
    level)             shift; lotus_log_level "$@" ;;
    path|where)        print -r -- $LOTUS_LOG ;;
    help|-h|--help)    lotus_log_help ;;
    *)                 ui_error "$LOTUS_L[log_unknown]" "$1" "lotus log · lotus log clear · lotus log level debug"; return 1 ;;
  esac
}

lotus_log_help() {
  ui_hero $LOTUS_L[log_title]
  local -a rows=(
    "/lotus log|$LOTUS_L[log_h_view]"
    "/lotus log live|$LOTUS_L[log_h_live]"
    "/lotus log level <level>|$LOTUS_L[log_h_level]"
    "/lotus log clear|$LOTUS_L[log_h_clear]"
    "/lotus log path|$LOTUS_L[log_h_path]")
  local r k=$'\e['"$LOTUS_C[key]m"
  for r in $rows; do print -r -- "    ${k}${(r:28:)${r%%|*}}${_UI_R}${r#*|}"; done
  ui_blank
  ui_dim "  ${LOTUS_L[log_h_file]} $LOTUS_LOG"
  ui_blank
}

lotus_log_level() {
  local -A label=(off $LOTUS_L[log_off] warn $LOTUS_L[log_warn] info $LOTUS_L[log_info] debug $LOTUS_L[log_debug] trace $LOTUS_L[log_trace])
  if [[ -z $1 ]]; then
    ui_info "$LOTUS_L[log_level]: ${label[$LOTUS_LOG_LEVEL]} ($LOTUS_LOG_LEVEL)"
    ui_dim "  lotus log level off|warn|info|debug|trace"
    return 0
  fi
  local want=${_LOG_ALIAS[${(L)1}]}
  [[ -z $want ]] && { ui_error "$LOTUS_L[log_bad_level]" "$1" "off · warn · info · debug · trace"; return 1 }
  LOTUS_LOG_LEVEL=$want
  lotus_save
  _lotus_log_max=-1
  lotus_log INFO log "Log level set to $want"
  ui_success "$LOTUS_L[log_level]: ${label[$want]} ($want)"
}

lotus_log_clear() {
  local -a files=($LOTUS_LOG(N) $LOTUS_LOG.<1-9>(N))
  if (( ! ${#files} )); then ui_info $LOTUS_L[log_empty_short]; return 0; fi
  ui_confirm "$LOTUS_L[log_clear_q]" n || return 0
  rm -f $files
  lotus_log INFO log "Log cleared"
  ui_success $LOTUS_L[log_cleared]
}

# Every entry, oldest first → reply (raw lines). Rotated files come first. At most the last 5000.
_log_lines() {
  local f
  local -a all=()
  for f in $LOTUS_LOG.<1-9>(NOn) $LOTUS_LOG(N); do all+=("${(@f)$(<$f)}"); done
  all=(${all:#})
  (( ${#all} > 5000 )) && all=(${all[-5000,-1]})
  reply=("${all[@]}")
}

typeset -gA _LOG_SEV=(ERROR 1 WARN 2 INFO 3 DEBUG 4 TRACE 5)

# Plain list for pipes and scripts:  lotus log tail 50
lotus_log_print() {
  local -i n=${1:-100}
  _log_lines
  local -a lines=("${reply[@]}") f
  (( ${#lines} > n )) && lines=(${lines[-n,-1]})
  if (( ! ${#lines} )); then print -r -- $LOTUS_L[log_empty_short]; return 0; fi
  local l
  for l in $lines; do
    f=("${(@ps:\t:)l}")
    print -r -- "${f[1]%.*}  ${(r:5:)f[2]}  ${(r:9:)f[3]} ${f[4]//\\n/ ⏎ }"
  done
}

# Day heading: Today, Yesterday or the date → REPLY
_log_day() {
  local today yesterday
  strftime -s today %Y-%m-%d $EPOCHSECONDS
  strftime -s yesterday %Y-%m-%d $(( EPOCHSECONDS - 86400 ))
  case $1 in
    $today)     REPLY=$LOTUS_L[log_today] ;;
    $yesterday) REPLY=$LOTUS_L[log_yesterday] ;;
    *)          REPLY=$1 ;;
  esac
}

lotus_log_view() {
  emulate -L zsh
  setopt extendedglob
  local -i live=0 sel=0 top=1 dirty=1 H W i lev=5 n
  [[ $1 == live ]] && live=1
  local query= note= stty_saved key
  local -a raw=() E_TS=() E_LV=() E_CP=() E_MSG=() rows=() rowidx=()
  local -a filters=(trace error warn info debug)
  local -A flabel=(trace $LOTUS_L[log_f_all] error ERROR warn "WARN+" info "INFO+" debug "DEBUG+")
  local -i fi=1
  local c_dim=$'\e['"$LOTUS_C[dim]m" c_acc=$'\e['"$LOTUS_C[accent]m" c_k2=$'\e[1;'"$LOTUS_C[key2]m" c_key=$'\e['"$LOTUS_C[key]m"
  local c_err=$'\e[1;38;5;203m' R=$'\e[0m' B=$'\e[1m' INV=$'\e[7m'
  local -F last_check=0
  local last_sig=

  _lv_load() {
    _log_lines
    raw=("${reply[@]}")
    E_TS=() E_LV=() E_CP=() E_MSG=()
    local l
    local -a f
    for l in $raw; do
      f=("${(@ps:\t:)l}")
      if (( ${#f} >= 4 )) && [[ $f[1] == <->-<->-<->* ]]; then
        E_TS+=($f[1]) E_LV+=($f[2]) E_CP+=($f[3]) E_MSG+=("${(j:	:)f[4,-1]}")
      else
        E_TS+=("") E_LV+=(INFO) E_CP+=("") E_MSG+=("$l")
      fi
    done
  }

  # Visible rows: day headings plus the entries that pass the filter and the search
  _lv_rows() {
    rows=() rowidx=()
    local day= d m
    local -i j max=${_LOG_SEV[${(U)filters[fi]}]:-5}
    for (( j = 1; j <= ${#E_MSG}; j++ )); do
      (( ${_LOG_SEV[$E_LV[j]]:-3} <= max )) || continue
      [[ -n $query && ${(L)E_MSG[j]} != *${(L)query}* && ${(L)E_CP[j]} != *${(L)query}* ]] && continue
      d=${E_TS[j][1,10]}
      if [[ -n $d && $d != $day ]]; then
        day=$d; _log_day $d
        rows+=("day|$REPLY"); rowidx+=(0)
      fi
      rows+=("e|$j"); rowidx+=($j)
    done
  }

  _lv_size() {
    local -a sz=(${=$(stty size < /dev/tty 2>/dev/null)})
    H=${sz[1]:-24} W=${sz[2]:-80}
  }

  # Line of one entry, cut to the window width
  _lv_entry() {
    local -i j=$1 cur=$2 room
    local lv=$E_LV[j] col msg=${E_MSG[j]//\\n/ ⏎ } t=${${E_TS[j]#* }%.*}
    case $lv in
      ERROR) col=$c_err ;; WARN) col=$c_k2 ;; INFO) col=$c_acc ;; *) col=$c_dim ;;
    esac
    local comp=
    (( W >= 70 )) && comp="${c_dim}${(r:10:)${E_CP[j][1,10]}}${R}"
    (( room = W - 8 - 2 - 7 - (W >= 70 ? 10 : 0) - 6 ))
    (( room < 10 )) && room=10
    (( ${#msg} > room )) && msg="${msg[1,room-1]}…"
    [[ $lv == (DEBUG|TRACE) ]] && msg="${c_dim}${msg}${R}"
    local pre="    "
    (( cur )) && pre="  ${c_acc}›${R} "
    REPLY="${pre}${c_dim}${(r:8:)t}${R}  ${col}${(r:6:)lv}${R} ${comp}${msg}"
  }

  _lv_header() {
    local first=${E_TS[1]} lastt=${E_TS[-1]} span=
    if (( ${#E_TS} )) && [[ -n $first ]]; then
      _log_day ${lastt[1,10]}
      span="$REPLY · ${${first#* }[1,5]} – ${${lastt#* }[1,5]}"
      [[ ${first[1,10]} != ${lastt[1,10]} ]] && span="${first[1,10]} – ${lastt[1,10]}"
    fi
    local -A lvl=(off $LOTUS_L[log_off] warn $LOTUS_L[log_warn] info $LOTUS_L[log_info] debug $LOTUS_L[log_debug] trace $LOTUS_L[log_trace])
    local info="${span:+$span · }${#E_MSG} ${LOTUS_L[log_entries]} · ${LOTUS_L[log_level]}: ${lvl[$LOTUS_LOG_LEVEL]}"
    REPLY=$'\e[K\n'"    ${c_acc}◇${R} ${B}lotus${R}${c_dim} / ${R}${B}${LOTUS_L[log_title]}${R}"
    (( live )) && REPLY+="   ${c_key}● ${LOTUS_L[log_live]}${R}"
    REPLY+=$'\e[K\n\e[K\n'"    ${c_dim}${info[1,W-6]}${R}"$'\e[K\n'
    local f="    ${c_dim}${LOTUS_L[log_filter]}: ${R}${flabel[$filters[fi]]}"
    [[ -n $query ]] && f+="${c_dim}   ${LOTUS_L[log_search]}: ${R}$query"
    REPLY+="$f"$'\e[K\n\e[K\n'
  }

  _lv_draw() {
    local out
    _lv_header; out=$REPLY
    local -i body=$(( H - 9 ))
    (( body < 3 )) && body=3
    if (( ! ${#rows} )); then
      if (( ${#E_MSG} )); then out+="    ${c_dim}${LOTUS_L[log_nomatch]}${R}"$'\e[K\n'
      else
        out+="    ${LOTUS_L[log_empty]}"$'\e[K\n\e[K\n'
        out+="    ${c_dim}${LOTUS_L[log_empty_hint]}${R}"$'\e[K\n'
      fi
      out+=$'\e[J'
    else
      (( sel < 1 )) && sel=${#rows}
      (( sel > ${#rows} )) && sel=${#rows}
      (( sel < top )) && top=sel
      (( sel > top + body - 1 )) && (( top = sel - body + 1 ))
      local -i maxtop=$(( ${#rows} - body + 1 ))
      (( maxtop < 1 )) && maxtop=1
      (( top > maxtop )) && top=maxtop
      (( top < 1 )) && top=1
      for (( i = top; i < top + body && i <= ${#rows}; i++ )); do
        if [[ ${rows[i]} == day\|* ]]; then
          out+="    ${c_dim}── ${rows[i]#day|} ──${R}"$'\e[K\n'
        else
          _lv_entry ${rows[i]#e|} $(( i == sel ))
          out+="$REPLY"$'\e[K\n'
        fi
      done
      for (( ; i < top + body; i++ )); do out+=$'\e[K\n'; done
    fi
    out+=$'\e[K\n'"    ${c_dim}${note:-${LOTUS_L[log_keys]}}${R}"$'\e[K\e[J'
    note=
    print -rn -- $'\e[H'"$out"
  }

  # Moves the selection to the next entry row (skipping day headings)
  _lv_step() {
    local -i d=$1 j=$sel
    repeat ${#rows}; do
      (( j += d ))
      (( j < 1 || j > ${#rows} )) && return
      [[ ${rows[j]} == e\|* ]] && { sel=j; return }
    done
  }

  _lv_detail() {
    [[ ${rows[sel]} == e\|* ]] || return
    local -i j=${rows[sel]#e|}
    local msg=${E_MSG[j]//\\n/$'\n'} l
    print -n $'\e[H\e[2J'
    ui_hero "${LOTUS_L[log_title]} · ${E_LV[j]}"
    ui_kv "${LOTUS_L[log_time]}" "${E_TS[j]}"
    ui_kv "${LOTUS_L[log_comp]}" "${E_CP[j]}"
    ui_blank
    for l in "${(@f)msg}"; do
      while (( ${#l} > W - 8 )); do print -r -- "    ${l[1,W-8]}"; l=${l[W-7,-1]}; done
      print -r -- "    $l"
    done
    ui_blank
    ui_dim "  ${LOTUS_L[back]}"
    read -rsk1 < /dev/tty
    print -n $'\e[2J'
  }

  _lv_reload() {
    local -i at_end=$(( sel >= ${#rows} ))
    _lv_load; _lv_rows
    (( at_end || sel == 0 )) && sel=${#rows}
  }

  # File signature: size and time of the current log (cheap check for live mode)
  _lv_sig() {
    local -a st
    zstat -A st +size +mtime $LOTUS_LOG 2>/dev/null && REPLY="${st[1]}:${st[2]}" || REPLY=none
  }

  _lv_load; _lv_rows; sel=${#rows}
  _lv_sig; last_sig=$REPLY
  stty_saved=$(stty -g < /dev/tty)
  stty -echo -icanon < /dev/tty
  print -n $'\e[?1049h\e[?25l\e[2J'
  trap 'print -n "\e[?25h\e[?1049l"; stty $stty_saved < /dev/tty' EXIT
  trap 'return 0' INT
  TRAPWINCH() { dirty=1 }
  _lv_size

  while :; do
    if (( dirty )); then _lv_size; print -n $'\e[2J'; dirty=0; fi
    _lv_draw
    if (( live )); then
      if ! read -rsk1 -t 0.5 key < /dev/tty; then
        _lv_sig
        [[ $REPLY != $last_sig ]] && { last_sig=$REPLY; _lv_reload }
        continue
      fi
      [[ $key == $'\e' ]] && { local rest c; rest=; while read -rsk1 -t 0.02 c < /dev/tty; do rest+=$c; [[ $c == [A-Za-z~] ]] && break; done; key+=$rest }
      case $key in
        $'\e[A') REPLY=up ;; $'\e[B') REPLY=down ;; $'\e[5~') REPLY=pgup ;; $'\e[6~') REPLY=pgdn ;;
        $'\n'|$'\r') REPLY=enter ;; $'\e') REPLY=esc ;; *) REPLY=$key ;;
      esac
    else
      ui_keyx
    fi
    case $REPLY in
      up|k)     _lv_step -1 ;;
      down|j)   _lv_step 1 ;;
      pgup)     repeat $(( H - 10 )); do _lv_step -1; done ;;
      pgdn|space) repeat $(( H - 10 )); do _lv_step 1; done ;;
      home|g)   sel=1; _lv_step 1; [[ ${rows[1]} == e\|* ]] && sel=1 ;;
      end|G)    sel=${#rows} ;;
      enter)    _lv_detail ;;
      f)        (( fi = fi % ${#filters} + 1 )); _lv_rows; sel=${#rows} ;;
      /)        print -n $'\e['"${H};1H"$'\e[K\e[?25h    '"${LOTUS_L[log_search]}: "
                stty $stty_saved < /dev/tty
                read -r query < /dev/tty
                stty -echo -icanon < /dev/tty
                print -n $'\e[?25l'
                _lv_rows; sel=${#rows} ;;
      l)        (( live = ! live )); _lv_reload ;;
      r)        _lv_reload ;;
      y)        local -a out=() ; local -i j2
                for (( j2 = 1; j2 <= ${#rows}; j2++ )); do
                  [[ ${rows[j2]} == e\|* ]] || continue
                  i=${rows[j2]#e|}; out+=("${E_TS[i]}  ${E_LV[i]}  ${E_CP[i]}  ${E_MSG[i]}")
                done
                print -rl -- $out | pbcopy && note="${LOTUS_L[log_copied]//\%d/${#out}}" ;;
      c)        print -n $'\e['"${H};1H"$'\e[K\e[?25h    '
                if read -q "?${LOTUS_L[log_clear_q]} [y/N] " < /dev/tty; then
                  rm -f $LOTUS_LOG(N) $LOTUS_LOG.<1-9>(N)
                  lotus_log INFO log "Log cleared"
                  note=$LOTUS_L[log_cleared]
                fi
                print -n $'\e[?25l'
                _lv_reload ;;
      esc)      if [[ -n $query ]]; then query=; _lv_rows; sel=${#rows}; else break; fi ;;
      q|Q)      break ;;
    esac
  done
  unfunction _lv_load _lv_rows _lv_size _lv_entry _lv_header _lv_draw _lv_step _lv_detail _lv_reload _lv_sig TRAPWINCH 2>/dev/null
  return 0
}
