# lotus ai server – Lotus AI in the browser: a web chat served by the AI program itself
# (lotus-ai --serve, lib/ai/Server.swift) – the same AI, tools, permissions and questions as /ai.
#   lotus ai server                    status, start or stop, port, start with the terminal, other devices
#   lotus ai server start|stop|restart|status|open
#   lotus ai server port <n>           the port (default 3000), kept in the settings
# It listens on 127.0.0.1 only. Other devices only when "Other devices" is turned on – they need the link
# with the access key. It never starts by itself unless "Start with the terminal" is turned on.
# State: $LOTUS_STATE/ai-server ("pid port started lan model-pid", then the folder) · the access key:
# $LOTUS_STATE/ai-server.key (only you can read it) · the conversations: $LOTUS_STATE/ai-chats

zmodload zsh/zselect 2>/dev/null

lotus_ai_server() {
  case ${1:-} in
    '')       _ais_menu ;;
    start)    shift; lotus_ai_server_start "$@" ;;
    stop)     lotus_ai_server_stop ;;
    restart)  lotus_ai_server_stop quiet; lotus_ai_server_start --no-open ;;
    status)   lotus_ai_server_status ;;
    open)     lotus_ai_server_open ;;
    port)     lotus_ai_server_port "${2:-}" ;;
    *)        ui_error "Unknown option: $1" "" "lotus ai server [start|stop|restart|status|open|port <n>]"; return 2 ;;
  esac
}

# The running web chat → AIS_PID AIS_PORT AIS_START AIS_LAN AIS_CHILD AIS_DIR; status 1 when it does not run.
# A state file whose process is gone, or now belongs to another program, is forgotten.
lotus_ai_server_state() {
  typeset -gi AIS_PID=0 AIS_PORT=0 AIS_START=0 AIS_LAN=0 AIS_CHILD=0
  typeset -g AIS_DIR=
  local f=$LOTUS_STATE/ai-server
  [[ -r $f ]] || return 1
  local -a lines=("${(@f)$(<$f)}")
  local -a v=(${=lines[1]})
  if [[ $v[1] != <-> || $v[2] != <-> || $v[3] != <-> || $v[4] != [01] || $v[5] != <-> ]] ||
     ! kill -0 $v[1] 2>/dev/null || [[ $(ps -p $v[1] -o comm= 2>/dev/null) != *lotus-ai* ]]; then
    rm -f -- "${f:?}"
    return 1
  fi
  AIS_PID=$v[1] AIS_PORT=$v[2] AIS_START=$v[3] AIS_LAN=$v[4] AIS_CHILD=$v[5] AIS_DIR=$lines[2]
}

# The access key → REPLY: made once, kept in a file only you can read
_ais_key() {
  local f=$LOTUS_STATE/ai-server.key
  if [[ -r $f ]]; then
    REPLY=$(<$f)
    [[ ${#REPLY} == 48 && $REPLY != *[^a-f0-9]* ]] && return 0
  fi
  zf_mkdir -p $LOTUS_STATE && chmod 700 $LOTUS_STATE
  REPLY=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
  [[ ${#REPLY} == 48 ]] || return 1
  ( umask 077; print -r -- $REPLY >| $f )
}

_ais_home() { REPLY=$1; [[ $REPLY == $HOME || $REPLY == $HOME/* ]] && REPLY="~${REPLY#$HOME}" }

# The link for other devices (with the key) → REPLY, empty without a network address
_ais_lan_link() {
  local ip=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)
  REPLY=
  [[ -n $ip ]] || return 1
  _ais_key || return 1
  REPLY="http://$ip:$1/?key=$REPLY"
}

# One start at a time (two terminals that open together)
_ais_lock() {
  local d=$LOTUS_STATE/ai-server.lock
  zf_mkdir -p $LOTUS_STATE
  zf_mkdir $d 2>/dev/null && return 0
  local -a st
  if zstat -A st +mtime $d 2>/dev/null && (( EPOCHSECONDS - st[1] > 120 )); then   # left over from a start that broke off
    rmdir $d 2>/dev/null
    zf_mkdir $d 2>/dev/null && return 0
  fi
  return 1
}
_ais_unlock() { rmdir $LOTUS_STATE/ai-server.lock 2>/dev/null; return 0 }

# Port <port> is taken: say by what and offer the next free one – kept only after a yes → REPLY
_ais_port_taken() {   # <port> <program> <lan> <quiet>
  local -i port=$1 next=0 p
  local who=$(lsof -nP -iTCP:$port -sTCP:LISTEN -Fc 2>/dev/null | sed -n 's/^c//p' | head -1)
  for (( p = port + 1; p <= port + 40 && p <= 65535; p++ )); do
    [[ $($2 --port-check $p $3) == free ]] && { next=p; break }
  done
  (( $4 )) && return 1
  local -a hints=("The web chat needs a port of its own. Lotus never changes it without asking.")
  (( next )) && hints+=("Another port: lotus ai server port $next")
  ui_error "Port $port is already in use${who:+ (by $who)}" "" $hints
  (( next )) && [[ -t 1 ]] && ui_has_tty || return 1
  ui_confirm "Use port $next instead? It is kept in the settings." y || return 1
  LOTUS_AI_SERVER_PORT=$next
  lotus_save
  REPLY=$next
}

lotus_ai_server_start() {
  local -i quiet=0 open=1
  local a
  for a; do
    case $a in
      --quiet)   quiet=1 open=0 ;;     # started with the terminal: no output, no browser
      --no-open) open=0 ;;
    esac
  done
  [[ -t 1 ]] || open=0
  if lotus_ai_server_state; then
    (( quiet )) || ui_info "The web chat is already running: http://127.0.0.1:$AIS_PORT  (lotus ai server open)"
    return 0
  fi
  if ! _ais_lock; then
    (( quiet )) || ui_info "The web chat is being started right now"
    return 0
  fi
  {
    _ais_start $quiet $open
  } always {
    _ais_unlock
  }
}

_ais_start() {   # <quiet> <open>
  local -i quiet=$1 open=$2 port=${LOTUS_AI_SERVER_PORT:-3000} lan=${LOTUS_AI_SERVER_LAN:-0}
  _ai_build || return 1
  lotus_ai_helper
  local bin=$REPLY
  if [[ $($bin --port-check $port $lan) != free ]]; then
    _ais_port_taken $port $bin $lan $quiet || return 1
    port=$REPLY
  fi
  _ais_key || { (( quiet )) || ui_error "Could not make the access key" "$LOTUS_STATE/ai-server.key"; return 1 }
  local key=$REPLY
  (( quiet )) || ui_step "Starting the web chat …"
  _ai_prepare --serve || return 1
  # a model on this Mac stays loaded while the web chat runs – the web chat stops it when it stops
  local -i child=$LLM_PID
  LLM_PID=0
  local out=$LOTUS_CACHE/ai/server.log
  zf_mkdir -p $LOTUS_STATE/ai-chats && chmod 700 $LOTUS_STATE/ai-chats
  (
    _ai_export
    export LOTUS_AI_SERVER_KEY=$key LOTUS_AI_SERVER_LAN=$lan LOTUS_AI_SERVER_CHILD=$child
    export LOTUS_AI_CHATS=$LOTUS_STATE/ai-chats LOTUS_AI_SETTINGS=$LOTUS_CONF/settings.zsh LOTUS_THEME
    exec nohup $bin --serve $port </dev/null >| $out 2>&1
  ) &
  local -i pid=$! i ok=0 rc
  for (( i = 0; i < 150; i++ )); do
    kill -0 $pid 2>/dev/null || break
    if [[ $(curl -fsS -m 1 --noproxy '*' http://127.0.0.1:$port/api/health 2>/dev/null) == *\"pid\":${pid}[,}]* ]]; then ok=1; break; fi
    zselect -t 10 2>/dev/null || sleep 0.1
  done
  if (( ! ok )); then
    if kill -0 $pid 2>/dev/null; then kill $pid 2>/dev/null; rc=1; else wait $pid 2>/dev/null; rc=$?; fi
    (( child )) && kill $child 2>/dev/null
    lotus_log ERROR ai "The web chat did not start (status $rc): $(tail -1 $out 2>/dev/null)"
    (( quiet )) && return 1
    case $rc in
      98) ui_error "Port $port is already in use" "Another program took it just now." "Another port: lotus ai server port $(( port + 1 ))" ;;
      3)  ui_error "The AI could not start" "$(tail -1 $out 2>/dev/null)" "Check it in the terminal first: /ai" ;;
      *)  ui_error "The web chat did not start" "${$(tail -1 $out 2>/dev/null):-no reason given}" "Details: $out" ;;
    esac
    return 1
  fi
  zf_mkdir -p $LOTUS_STATE
  print -r -- "$pid $port $EPOCHSECONDS $lan $child"$'\n'"$PWD" >| $LOTUS_STATE/ai-server
  lotus_log INFO ai "Web chat started on port $port (pid $pid, ${${lan:#0}:+other devices allowed}${${(M)lan:#0}:+only this Mac})"
  (( quiet )) && return 0
  local label
  case $AI_PROVIDER in
    claude) label="Claude${AI_MODEL:+ · $AI_MODEL}" ;;
    apple)  label="Apple Intelligence" ;;
    ollama) label="Ollama · $AI_MODEL" ;;
    *)      label=${AI_LABEL:-"${AI_MODEL:-gpt-4o-mini} · ${${AI_URL#*://}%%/*}"} ;;
  esac
  _ais_home $PWD
  ui_success "The web chat is running: http://127.0.0.1:$port"
  ui_kv Answers "$label"
  ui_kv Folder "$REPLY"
  if (( lan )); then
    _ais_lan_link $port && ui_kv "Other devices" "$REPLY"
    ui_dim "Devices in your network can open it with that link – not encrypted, only on networks you trust."
  else
    ui_dim "Only this Mac can open it. Every command it wants to run asks you first in the browser."
  fi
  if (( open )); then
    open "http://127.0.0.1:$port/?key=$key" 2>/dev/null && ui_dim "It opens in your browser now · later: lotus ai server open · stop: lotus ai server stop"
  else
    ui_dim "Open it: lotus ai server open · stop: lotus ai server stop"
  fi
}

lotus_ai_server_stop() {
  if ! lotus_ai_server_state; then
    [[ $1 == quiet ]] || ui_info "The web chat is not running"
    return 0
  fi
  kill $AIS_PID 2>/dev/null
  local -i i
  for (( i = 0; i < 40; i++ )); do
    kill -0 $AIS_PID 2>/dev/null || break
    zselect -t 10 2>/dev/null || sleep 0.1
  done
  kill -0 $AIS_PID 2>/dev/null && kill -9 $AIS_PID 2>/dev/null
  # the model on this Mac it started (the web chat stops it itself – this is in case it could not)
  if (( AIS_CHILD > 1 )) && [[ $(ps -p $AIS_CHILD -o command= 2>/dev/null) == *mlx_lm.server* ]]; then
    kill $AIS_CHILD 2>/dev/null
  fi
  rm -f -- "${LOTUS_STATE:?}/ai-server"
  lotus_log INFO ai "Web chat stopped (pid $AIS_PID)"
  [[ $1 == quiet ]] || ui_success "The web chat is stopped"
}

lotus_ai_server_status() {
  if ! lotus_ai_server_state; then
    print -r -- "Web chat: off (port $LOTUS_AI_SERVER_PORT) · start it: lotus ai server start"
    return 0
  fi
  local since
  strftime -s since '%H:%M' $AIS_START
  print -r -- "Web chat: running on http://127.0.0.1:$AIS_PORT (since $since)"
  _ais_home $AIS_DIR
  print -r -- "  Folder: $REPLY"
  if (( AIS_LAN )); then
    _ais_lan_link $AIS_PORT && print -r -- "  Other devices: $REPLY"
  else
    print -r -- "  Only this Mac can open it"
  fi
  (( AIS_PORT != LOTUS_AI_SERVER_PORT )) && print -r -- "  The settings say port $LOTUS_AI_SERVER_PORT – lotus ai server restart moves it"
  print -r -- "  Open it: lotus ai server open · stop it: lotus ai server stop"
}

lotus_ai_server_open() {
  if ! lotus_ai_server_state; then
    ui_error "The web chat is not running" "" "Start it: lotus ai server start"
    return 1
  fi
  _ais_key || return 1
  if open "http://127.0.0.1:$AIS_PORT/?key=$REPLY" 2>/dev/null; then
    ui_success "Opened in your browser: http://127.0.0.1:$AIS_PORT"
  else
    ui_error "Could not open the browser" "" "Open http://127.0.0.1:$AIS_PORT – the link with the key: lotus ai server status"
    return 1
  fi
}

lotus_ai_server_port() {
  local p=$1
  if [[ -z $p ]]; then
    print -r -- "The web chat uses port $LOTUS_AI_SERVER_PORT"
    return 0
  fi
  if [[ $p != <1024-65535> ]]; then
    ui_error "$p is not a port the web chat can use" "Ports from 1024 to 65535 work." "Example: lotus ai server port 3000"
    return 2
  fi
  p=$(( 10#$p ))
  LOTUS_AI_SERVER_PORT=$p
  lotus_save
  ui_success "The web chat uses port $p"
  lotus_ai_helper
  if lotus_ai_server_state; then
    (( AIS_PORT != p )) && ui_dim "It still runs on port $AIS_PORT – lotus ai server restart moves it"
  elif [[ -x $REPLY && $($REPLY --port-check $p $LOTUS_AI_SERVER_LAN) != free ]]; then
    ui_warn "Port $p is in use right now – the web chat can only start when it is free"
  fi
  return 0
}

# ── The menu ──────────────────────────────────────────────────

_ais_menu() {
  if ! { [[ -t 1 ]] && ui_has_tty }; then
    lotus_ai_server_status
    return
  fi
  local -i sel=1
  local -a acts opts
  local onoff
  while :; do
    print -n $'\e[H\e[2J'
    acts=() opts=()
    if lotus_ai_server_state; then
      ui_hero "AI web chat" "Lotus AI in your browser – the same AI, tools and questions as /ai"
      local since
      strftime -s since '%H:%M' $AIS_START
      ui_kv Address "http://127.0.0.1:$AIS_PORT  · running since $since"
      _ais_home $AIS_DIR
      ui_kv Folder "$REPLY"
      (( AIS_LAN )) && _ais_lan_link $AIS_PORT && ui_kv "Other devices" "$REPLY"
      ui_blank
      acts=(open stop restart)
      opts=("Open in the browser|signs you in with your key" "Stop|" "Restart|after you changed the AI, the port or other devices")
    else
      ui_hero "AI web chat" "Lotus AI in your browser – off. It only starts when you start it."
      acts=(start)
      opts=("Start|on port $LOTUS_AI_SERVER_PORT, then it opens in your browser")
    fi
    (( LOTUS_AI_SERVER_BOOT )) && onoff="on – it starts with the first terminal" || onoff="off – it starts only when you start it"
    acts+=(port boot lan)
    opts+=("Port|$LOTUS_AI_SERVER_PORT" "Start with the terminal|$onoff")
    if (( LOTUS_AI_SERVER_LAN )); then opts+=("Other devices|allowed – with the link that has your key")
    else opts+=("Other devices|off – only this Mac"); fi
    ui_select $sel "${opts[@]}" || break
    sel=$REPLY
    case $acts[sel] in
      start)   print; lotus_ai_server_start; _ais_back ;;
      open)    print; lotus_ai_server_open; _ais_back ;;
      stop)    print; lotus_ai_server_stop; _ais_back ;;
      restart) print; lotus_ai_server_stop quiet; lotus_ai_server_start --no-open; _ais_back ;;
      port)
        print
        ui_input "Port (1024–65535)" $LOTUS_AI_SERVER_PORT && [[ $REPLY != $LOTUS_AI_SERVER_PORT ]] && lotus_ai_server_port $REPLY
        _ais_back ;;
      boot)
        (( LOTUS_AI_SERVER_BOOT )) && LOTUS_AI_SERVER_BOOT=0 || LOTUS_AI_SERVER_BOOT=1
        lotus_save ;;
      lan)
        if (( LOTUS_AI_SERVER_LAN )); then
          LOTUS_AI_SERVER_LAN=0
        else
          print
          ui_text "Devices in your network (your phone, another Mac) can then open the web chat with the link"
          ui_text "that contains your key – anyone with that link can use the AI on this Mac. The connection is"
          ui_text "not encrypted (http): only turn this on in networks you trust."
          ui_blank
          ui_confirm "Allow other devices?" n && LOTUS_AI_SERVER_LAN=1
        fi
        lotus_save
        if lotus_ai_server_state && (( AIS_LAN != LOTUS_AI_SERVER_LAN )); then
          ui_confirm "Restart the web chat now, so this counts?" y && { lotus_ai_server_stop quiet; lotus_ai_server_start --no-open }
          _ais_back
        fi ;;
    esac
  done
  print -n $'\e[H\e[2J'
}

_ais_back() { ui_dim "  $LOTUS_L[back]"; ui_key }
