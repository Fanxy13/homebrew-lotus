# lotus caffeine – keep the Mac awake for a while, with macOS' own caffeinate
#   lotus caffeine                 status, and on or off from a short menu
#   lotus caffeine on [minutes]    awake for that long (default 60; 0 = until you turn it off)
#   lotus caffeine off             let it sleep again
#   lotus caffeine status          on or off, and how long it has left
# caffeinate runs on its own (closing the terminal does not stop it) and ends by itself when the
# time is up. Lotus keeps its process id and end time in $LOTUS_STATE/caffeine and only ever stops
# a caffeinate that it started itself.

lotus_cmd_caffeine() {
  [[ $1 == (caffeine|awake) ]] && shift
  case ${1:-} in
    on|start)   lotus_caffeine_on "${2:-}" ;;
    off|stop)   lotus_caffeine_off ;;
    status)     lotus_caffeine_status ;;
    '')         lotus_caffeine_menu ;;
    <->)        lotus_caffeine_on $1 ;;
    *)          ui_error "Unknown option: $1" "" "lotus caffeine on [minutes] · off · status"; return 2 ;;
  esac
}

# The running caffeinate of Lotus → CAF_PID, CAF_END (0 = until stopped); status 1 when there is none
lotus_caffeine_state() {
  typeset -gi CAF_PID=0 CAF_END=0 CAF_START=0
  local f=$LOTUS_STATE/caffeine
  [[ -r $f ]] || return 1
  local -a v=(${=$(<$f)})
  [[ $v[1] == <-> && $v[2] == <-> && $v[3] == <-> ]] || { rm -f -- "${f:?}"; return 1 }
  # gone, or the number now belongs to another program: forget it
  if ! kill -0 $v[1] 2>/dev/null || [[ $(ps -p $v[1] -o comm= 2>/dev/null) != *caffeinate ]]; then
    rm -f -- "${f:?}"
    return 1
  fi
  CAF_PID=$v[1] CAF_START=$v[2] CAF_END=$v[3]
}

# "42 min", "1 h 05 min" → REPLY
_caf_left() {
  local -i s=$1 m
  (( m = (s + 59) / 60 ))
  if (( m >= 60 )); then REPLY="$(( m / 60 )) h $(( m % 60 )) min"; else REPLY="$m min"; fi
}

lotus_caffeine_on() {
  local arg=${1:-60}
  [[ $arg == <-> ]] || { ui_error "Minutes must be a number" "$arg" "Example: lotus caffeine on 90"; return 2 }
  local -i min=$arg
  (( min > 1440 )) && { ui_error "At most 24 hours (1440 minutes)" "" "For longer: lotus caffeine on 0 – until you turn it off"; return 2 }
  command -v caffeinate >/dev/null || { ui_error "caffeinate is missing" "It comes with macOS." ""; return 1 }
  lotus_caffeine_state && lotus_caffeine_off quiet
  zf_mkdir -p $LOTUS_STATE
  local -a args=(-d -i -m)            # display, idle sleep and disk stay awake
  (( min )) && args+=(-t $(( min * 60 )))
  nohup caffeinate $args >/dev/null 2>&1 &!
  local -i pid=$!
  sleep 0.1
  if ! kill -0 $pid 2>/dev/null; then
    ui_error "caffeinate did not start" "" ""
    return 1
  fi
  print -r -- "$pid $EPOCHSECONDS $(( min ? EPOCHSECONDS + min * 60 : 0 ))" >| $LOTUS_STATE/caffeine
  lotus_log INFO caffeine "Keeping the Mac awake${min:+ for $min min} (caffeinate $pid)"
  if (( min )); then
    local until
    strftime -s until '%H:%M' $(( EPOCHSECONDS + min * 60 ))
    _caf_left $(( min * 60 ))
    ui_success "${LOTUS_L[caf_on]:-Your Mac stays awake} – $REPLY (${LOTUS_L[caf_until]:-until} $until)"
  else
    ui_success "${LOTUS_L[caf_on]:-Your Mac stays awake} – ${LOTUS_L[caf_forever]:-until you turn it off}: lotus caffeine off"
  fi
}

lotus_caffeine_off() {
  if ! lotus_caffeine_state; then
    [[ $1 == quiet ]] || ui_info "${LOTUS_L[caf_was_off]:-Keep awake is not on}"
    return 0
  fi
  kill $CAF_PID 2>/dev/null
  rm -f -- "${LOTUS_STATE:?}/caffeine"
  lotus_log INFO caffeine "Stopped keeping the Mac awake (caffeinate $CAF_PID)"
  [[ $1 == quiet ]] || ui_success "${LOTUS_L[caf_off]:-Your Mac may sleep again}"
}

lotus_caffeine_status() {
  if ! lotus_caffeine_state; then
    print -r -- "${LOTUS_L[caf_status_off]:-Keep awake: off}"
    return 0
  fi
  if (( CAF_END )); then
    local until
    strftime -s until '%H:%M' $CAF_END
    _caf_left $(( CAF_END - EPOCHSECONDS ))
    print -r -- "${LOTUS_L[caf_status_on]:-Keep awake: on} – $REPLY ${LOTUS_L[caf_left]:-left} (${LOTUS_L[caf_until]:-until} $until)"
  else
    print -r -- "${LOTUS_L[caf_status_on]:-Keep awake: on} – ${LOTUS_L[caf_forever]:-until you turn it off}"
  fi
}

lotus_caffeine_menu() {
  ui_has_tty || { lotus_caffeine_status; return }
  ui_header "${LOTUS_L[caf_title]:-Keep awake}" "${LOTUS_L[caf_sub]:-Your Mac does not sleep while this is on – for downloads, renders or a Minecraft server}"
  if lotus_caffeine_state; then
    lotus_caffeine_status
    print
    ui_confirm "${LOTUS_L[caf_stop_q]:-Let your Mac sleep again?}" y && lotus_caffeine_off
    return 0
  fi
  local -a mins=(30 60 120 240 0)
  ui_choose "${LOTUS_L[caf_how_long]:-For how long?}" "30 min" "1 h" "2 h" "4 h" "${LOTUS_L[caf_forever]:-until you turn it off}" || return 0
  lotus_caffeine_on $mins[REPLY]
}
