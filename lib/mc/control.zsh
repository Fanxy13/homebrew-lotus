# lotus – the Minecraft control center (/minecraft → open a server, /mc <name>).
# One full-screen window with three pages, Tab switches between them:
#   Stats     the server's state, players online with their ping, TPS, memory, CPU, the world's size,
#             the newest events – and a little Minecraft world drifting by (lib/mc/world.zsh)
#   Settings  the server icon, the description (MOTD), the folder, plugins: search Modrinth for the
#             server's version, install with one key, or drag your own .jar in (lib/mc/plugins.zsh)
#   Log       the console, filtered and colored, with a command line (/ like in Minecraft, t to chat)
# The server runs in the background (lib/mc/run.zsh): leaving the control center can keep it
# running, and opening it again later finds it. A server started some other way (start.command)
# is shown too, from its logs/latest.log – without the command line.
# Ping, TPS and tick time come from LotusBridge, a tiny plugin Lotus builds for Paper servers.

zmodload zsh/datetime zsh/system zsh/mathfunc
zmodload -F zsh/stat b:zstat
source $LOTUS_ROOT/lib/mc/world.zsh
source $LOTUS_ROOT/lib/mc/plugins.zsh

typeset -ga MCC_LOG MCC_EVENTS MCC_PORDER MCC_HIST MCC_RES MCC_INST MCC_ICON
typeset -gA MCC_PLAYERS MCC_BR MCC_PROP MCC_C
typeset -g MCC_DIR= MCC_S= MCC_NAME= MCC_TYPE= MCC_VER= MCC_MODE= MCC_STATE=stopped MCC_PROBLEM=
typeset -g MCC_LOGF= MCC_PART= MCC_FILTER=all MCC_IN= MCC_INTEXT= MCC_INLABEL= MCC_ASK= MCC_TOAST= MCC_TOASTK=ok
typeset -g MCC_SUB= MCC_Q= MCC_QSENT=- MCC_QFILE= MCC_RSTATE=idle MCC_LAN= MCC_PROPSTAMP= MCC_ICONKEY= MCC_TPS=- MCC_MSPT=-
typeset -gi MCC_FD=0 MCC_OFF=0 MCC_PID=0 MCC_XPID=0 MCC_WRAP=0 MCC_READY=0 MCC_PROGRESS=0 MCC_LOGSTOP=0 MCC_EXIT=-1
typeset -gi MCC_PAGE=1 MCC_SEL=1 MCC_SSEL=1 MCC_PSEL=1 MCC_BACK=0 MCC_HISTI=0 MCC_TOAST_AT=0
typeset -gi MCC_RSS=0 MCC_CPU=0 MCC_UP=0 MCC_XMX=0 MCC_WORLDKB=-1 MCC_BRIDGE=0 MCC_BR_AT=0 MCC_RTOTAL=0 MCC_RLOADING=0
typeset -gi MCC_STOP_AT=0 MCC_RESTART=0 MCC_LEAVE=0 MCC_WANTSTOP=0 MCC_CHANGED=0 MCC_H=24 MCC_W=80
typeset -gF MCC_QAT=0 MCC_T1=0 MCC_T2=0 MCC_T30=0 MCC_T5=0

# ── Entry ─────────────────────────────────────────────────────

lotus_mcc() {
  emulate -L zsh
  setopt extendedglob
  local dir=${1:A}
  [[ -x $dir/start.command ]] || { ui_error "$LOTUS_L[mc_noserver]" "$dir"; return 1 }
  lotus_lang_group mc
  _mcc_init $dir
  if ! { [[ -t 1 ]] && ui_has_tty }; then
    # no terminal: one line about the server
    _mcc_probe
    print -r -- "$MCC_NAME: $MCC_STATE"
    return 0
  fi
  _mcc_probe
  # a stopped server starts when its control center opens
  if [[ $MCC_STATE == (stopped|crashed) ]]; then _mcc_start; fi
  local state=$(stty -g < /dev/tty 2>/dev/null)
  # -isig: Ctrl-C arrives as a key and asks before leaving
  stty -echo -icanon -isig < /dev/tty 2>/dev/null
  print -n $'\e[?1049h\e[?25l\e[2J'
  UI_INT=0
  TRAPINT() { UI_INT=1; return 0 }
  {
    _mcc_loop
  } always {
    # also after an error: the terminal comes back as it was
    unfunction TRAPINT 2>/dev/null
    print -n $'\e[?2026l\e[2J\e[?1049l\e[?25h'
    [[ -n $state ]] && stty $state < /dev/tty 2>/dev/null
  }
  (( MCC_FD )) && exec {MCC_FD}<&-
  MCC_FD=0
  if [[ $MCC_STATE == (running|starting|preparing) ]]; then
    ui_blank
    ui_info "${LOTUS_L[mc_bg_running]//\%s/$MCC_NAME}"
    ui_dim "  ${LOTUS_L[mc_bg_back]//\%s/$MCC_NAME}"
    ui_blank
  fi
  return 0
}

_mcc_init() {
  MCC_DIR=$1 MCC_S=$1/.lotus MCC_NAME=${1:t}
  zf_mkdir -p $MCC_S
  MCC_PAGE=1 MCC_SUB= MCC_IN= MCC_ASK= MCC_TOAST= MCC_BACK=0 MCC_FILTER=all MCC_LEAVE=0 MCC_RESTART=0
  MCC_LAN=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)
  _mcc_colors
  _mcc_detect
  _mcc_xmx
  _mcc_props
  _mcc_hist_load
}

# Theme colors as escape codes, by short name
_mcc_colors() {
  local k
  MCC_C=()
  for k in logo key accent key2 salute border dim; do MCC_C[$k]=$'\e['"${LOTUS_C[$k]}m"; done
  MCC_C[r]=$'\e[0m' MCC_C[B]=$'\e[1m' MCC_C[red]=$'\e[38;5;203m'
  MCC_C[tab]=$'\e[1;30;48'"${LOTUS_C[key]#38}m"
}

# ── The server: what it is, whether it runs ──────────────────

# Type and version: from .lotus/server.conf (written when Lotus made the server), otherwise worked out once
_mcc_detect() {
  local conf=$MCC_S/server.conf line
  MCC_TYPE= MCC_VER=
  if [[ -r $conf ]]; then
    for line in "${(@f)$(<$conf)}"; do
      [[ $line == type=* ]] && MCC_TYPE=${line#type=}
      [[ $line == version=* ]] && MCC_VER=${line#version=}
    done
  fi
  if [[ -z $MCC_TYPE ]]; then
    if [[ $MCC_NAME == (#b)(vanilla|paper)-([0-9.]##)* ]]; then MCC_TYPE=$match[1] MCC_VER=$match[2]
    elif [[ -d $MCC_DIR/libraries/io/papermc || -r $MCC_DIR/config/paper-global.yml || -r $MCC_DIR/paper.yml ]]; then MCC_TYPE=paper
    elif [[ $(unzip -l -- $MCC_DIR/server.jar 2>/dev/null) == *paperclip* ]]; then MCC_TYPE=paper
    else MCC_TYPE=vanilla; fi
    if [[ -z $MCC_VER ]]; then
      MCC_VER=$(unzip -p -- $MCC_DIR/server.jar version.json 2>/dev/null | lotus_jq -r '.id // empty' 2>/dev/null)
    fi
    _mcc_conf_save
  fi
}
_mcc_conf_save() { print -r -- "type=$MCC_TYPE"$'\n'"version=$MCC_VER" >| $MCC_S/server.conf }

# The memory the server may use, from start.command (-Xmx4G) → MCC_XMX in MB
_mcc_xmx() {
  local sc=$(<$MCC_DIR/start.command)
  MCC_XMX=0
  if [[ $sc == (#b)*-Xmx([0-9]##)([GgMm])* ]]; then
    [[ $match[2] == [Gg] ]] && MCC_XMX=$(( match[1] * 1024 )) || MCC_XMX=$match[1]
  fi
}

# server.properties → MCC_PROP (read again when the file changed)
_mcc_props() {
  local f=$MCC_DIR/server.properties line
  local -A st
  zstat -H st $f 2>/dev/null || { MCC_PROP=(); MCC_PROPSTAMP=; return }
  [[ $MCC_PROPSTAMP == "$st[mtime] $st[size]" ]] && return
  MCC_PROPSTAMP="$st[mtime] $st[size]"
  MCC_PROP=()
  for line in "${(@f)$(<$f)}"; do
    [[ $line == [[:space:]]#[\#!]* || $line != *=* ]] && continue
    MCC_PROP[${line%%=*}]=${line#*=}
  done
}

# A value for server.properties: \ and everything outside ASCII as Java writes it (\uXXXX) → REPLY
_mcc_prop_escape() {
  local s=$1 out= c
  local -i i cp hi lo
  for (( i = 1; i <= ${#s}; i++ )); do
    c=${s[i]}
    if [[ $c == '\' ]]; then out+='\\'; continue; fi
    cp=$(( #c ))
    if (( cp < 32 )); then continue
    elif (( cp < 127 )); then out+=$c
    elif (( cp > 0xFFFF )); then
      (( hi = 0xD800 + ((cp - 0x10000) >> 10), lo = 0xDC00 + ((cp - 0x10000) & 0x3FF) ))
      out+='\u'${(l:4::0:)$(( [##16] hi ))}'\u'${(l:4::0:)$(( [##16] lo ))}
    else out+='\u'${(l:4::0:)$(( [##16] cp ))}; fi
  done
  REPLY=$out
}

# …and back: \uXXXX (pairs too), \\ and \: → REPLY
_mcc_prop_unescape() {
  local s=$1 out=
  local -i i n cp lo
  for (( i = 1; i <= ${#s}; i++ )); do
    if [[ ${s[i]} == '\' && $i -lt ${#s} ]]; then
      if [[ ${s[i+1]} == u && ${s[i+2,i+5]} == [0-9A-Fa-f](#c4) ]]; then
        cp=$(( 16#${s[i+2,i+5]} ))
        (( i += 5 ))
        if (( cp >= 0xD800 && cp < 0xDC00 )) && [[ ${s[i+1,i+2]} == '\u' && ${s[i+3,i+6]} == [0-9A-Fa-f](#c4) ]]; then
          lo=$(( 16#${s[i+3,i+6]} ))
          (( cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00), i += 6 ))
        fi
        out+=${(#)cp}
      else
        (( i++ ))
        out+=${s[i]}
      fi
    else
      out+=${s[i]}
    fi
  done
  REPLY=$out
}

# Changes one setting in server.properties (or adds it), the rest stays as it is
_mcc_prop_set() {   # <key> <value>
  local f=$MCC_DIR/server.properties line out= done=0
  _mcc_prop_escape "$2"; local v=$REPLY
  if [[ -r $f ]]; then
    for line in "${(@f)$(<$f)}"; do
      if [[ $line == $1=* ]]; then out+="$1=$v"$'\n'; done=1
      else out+=$line$'\n'; fi
    done
  fi
  (( done )) || out+="$1=$v"$'\n'
  print -rn -- $out >| $f
  MCC_PROPSTAMP=
  _mcc_props
}

# The description as Minecraft shows it: escapes undone, § color codes left out → REPLY
_mcc_motd() {
  _mcc_prop_unescape "${MCC_PROP[motd]-A Minecraft Server}"
  REPLY=${REPLY//§?/}
}

# Is a process there? (kill -0 asks without doing anything)
_mcc_alive() { (( $1 > 0 )) && kill -0 $1 2>/dev/null }

# What runs, once a second: our server (pid files of run.zsh), or one started elsewhere
_mcc_probe() {
  local -i pid=0 wrap=0
  [[ -r $MCC_S/pid ]] && pid=$(<$MCC_S/pid)
  [[ -r $MCC_S/wrapper ]] && wrap=$(<$MCC_S/wrapper)
  if (( pid != MCC_PID && pid )); then
    # a pid file from before a restart of the Mac can name another program
    [[ $(ps -o comm= -p $pid 2>/dev/null) == *(java|start.command|zsh)* ]] || pid=0
  fi
  if (( wrap != MCC_WRAP && wrap )); then
    [[ $(ps -o comm= -p $wrap 2>/dev/null) == *zsh* ]] || wrap=0
  fi
  _mcc_alive $pid || pid=0
  _mcc_alive $wrap || wrap=0
  MCC_PID=$pid MCC_WRAP=$wrap
  if (( pid || wrap )); then
    [[ $MCC_MODE == ours ]] || { MCC_MODE=ours; _mcc_log_open $MCC_S/console.log }
    if (( MCC_WANTSTOP || MCC_LOGSTOP )); then MCC_STATE=stopping
    elif (( ! pid )); then MCC_STATE=preparing
    elif (( MCC_READY )); then MCC_STATE=running
    else MCC_STATE=starting; fi
    return
  fi
  # started some other way: a java whose folder is this one (lsof takes a moment – every 10 s,
  # and once found, the process alone is watched)
  if [[ $MCC_MODE == external ]] && _mcc_alive $MCC_XPID; then
    MCC_PID=$MCC_XPID
    (( MCC_WANTSTOP )) && MCC_STATE=stopping || MCC_STATE=running
    return
  fi
  if [[ $MCC_MODE != (ours|external) ]] && (( EPOCHREALTIME - MCC_T5 > 10 )); then
    MCC_T5=$EPOCHREALTIME
    local line cur=
    pid=0
    for line in "${(@f)$(lsof -a -d cwd -c java -Fpn 2>/dev/null)}"; do
      [[ $line == p* ]] && cur=${line#p}
      [[ $line == n* && ${line#n} == $MCC_DIR ]] && pid=$cur
    done
    if (( pid )); then
      MCC_PID=$pid MCC_XPID=$pid
      [[ $MCC_MODE == external ]] || { MCC_MODE=external; _mcc_log_open $MCC_DIR/logs/latest.log }
      (( MCC_WANTSTOP )) && MCC_STATE=stopping || MCC_STATE=running
      return
    fi
  fi
  # nothing runs
  if [[ $MCC_STATE != (stopped|crashed) || -z $MCC_MODE ]]; then
    MCC_EXIT=-1
    [[ -r $MCC_S/exit ]] && MCC_EXIT=$(<$MCC_S/exit)
    if (( MCC_WANTSTOP || MCC_EXIT <= 0 || MCC_EXIT == 130 || MCC_EXIT == 143 )); then MCC_STATE=stopped
    else MCC_STATE=crashed; fi
    [[ -z $MCC_MODE && ! -r $MCC_S/exit ]] && MCC_STATE=stopped
    MCC_PLAYERS=() MCC_PORDER=() MCC_BR=() MCC_BRIDGE=0 MCC_RSS=0 MCC_CPU=0
    MCC_WANTSTOP=0
    [[ -z $MCC_MODE || $MCC_MODE == external ]] && _mcc_log_open $MCC_S/console.log
    MCC_MODE=stopped
  fi
}

# Starts the server in the background (in its own session: Ctrl-C and a closed window do not reach it)
_mcc_start() {
  _mcc_props
  # without the EULA the server would stop at once – ask first
  if [[ $(<$MCC_DIR/eula.txt 2>/dev/null) != *eula=true* ]]; then
    MCC_PROBLEM=eula MCC_ASK=eula
    return 1
  fi
  MCC_PROBLEM= MCC_READY=0 MCC_LOGSTOP=0 MCC_PROGRESS=0 MCC_WANTSTOP=0 MCC_EXIT=-1
  rm -f -- $MCC_S/console $MCC_S/exit
  mkfifo $MCC_S/console 2>/dev/null || { _mcc_toast err "$LOTUS_L[mc_err_fifo]"; return 1 }
  : >| $MCC_S/console.log
  _mcc_log_open $MCC_S/console.log
  perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' nohup /bin/zsh $LOTUS_ROOT/lib/mc/run.zsh $MCC_DIR >/dev/null 2>&1 < /dev/null &!
  MCC_MODE=ours MCC_STATE=preparing MCC_UP=0
  lotus_log INFO minecraft "Server started: $MCC_NAME"
  # the pid files take a moment
  local -i i
  for (( i = 0; i < 20; i++ )); do [[ -r $MCC_S/wrapper ]] && break; sleep 0.05; done
  MCC_T1=0
}

# stop: in the console for our server, SIGTERM for one started elsewhere (Minecraft saves and stops on it)
_mcc_stop() {
  MCC_WANTSTOP=1 MCC_STOP_AT=$EPOCHSECONDS MCC_STATE=stopping
  if [[ $MCC_MODE == ours ]] && (( MCC_PID )); then _mcc_send stop
  elif (( MCC_PID )); then kill -TERM $MCC_PID 2>/dev/null
  elif (( MCC_WRAP )); then kill -TERM $MCC_WRAP 2>/dev/null; fi
  lotus_log INFO minecraft "Server stopped: $MCC_NAME"
}

# A command into the server's console. Opened for reading and writing, so it never waits
_mcc_send() {
  [[ $MCC_MODE == ours && -p $MCC_S/console ]] && (( MCC_PID )) || return 1
  local -i fd
  exec {fd}<>$MCC_S/console || return 1
  print -r -u $fd -- "$1"
  exec {fd}>&-
  [[ $1 == stop ]] || print -r -- "[Lotus] > $1" >> $MCC_S/console.log
  return 0
}

# Memory and CPU (every 2 s), the world's size (every 30 s, measured in the background)
_mcc_sample() {
  if (( MCC_PID )); then
    local -a f=(${=$(ps -o rss=,%cpu=,etime= -p $MCC_PID 2>/dev/null)})
    if (( ${#f} >= 3 )); then
      MCC_RSS=$(( f[1] / 1024 )) MCC_CPU=${f[2]%%[.,]*}
      local e=$f[3]
      local -i d=0 h=0 m=0 s=0
      [[ $e == *-* ]] && { d=${e%%-*}; e=${e#*-} }
      local -a p=(${(s.:.)e})
      if (( ${#p} == 3 )); then h=10#$p[1] m=10#$p[2] s=10#$p[3]; else m=10#$p[1] s=10#$p[2]; fi
      MCC_UP=$(( d * 86400 + h * 3600 + m * 60 + s ))
    fi
  fi
  [[ -r $MCC_S/size ]] && MCC_WORLDKB=$(<$MCC_S/size)
  if (( EPOCHREALTIME - MCC_T30 > 30 )); then
    MCC_T30=$EPOCHREALTIME
    local lvl=${MCC_PROP[level-name]:-world}
    lvl=${lvl//[^A-Za-z0-9._ -]/}
    ( local -a dirs=($MCC_DIR/$lvl(N/) $MCC_DIR/${lvl}_nether(N/) $MCC_DIR/${lvl}_the_end(N/)) kb
      local -i sum=-2
      local x
      if (( ${#dirs} )); then
        sum=0
        kb=(${(f)"$(du -sk -- $dirs 2>/dev/null)"})
        for x in $kb; do (( sum += ${x%%[[:space:]]*} )); done
      fi
      print -r -- $sum >| $MCC_S/size.part && zf_mv -f $MCC_S/size.part $MCC_S/size ) &!
  fi
}

# What LotusBridge wrote (plugins/LotusBridge/status.tsv): fresh means less than 8 seconds old
_mcc_bridge() {
  local f=$MCC_DIR/plugins/LotusBridge/status.tsv line
  local -A st
  if ! zstat -H st $f 2>/dev/null || (( EPOCHSECONDS - st[mtime] > 8 )) || (( ! MCC_PID )); then
    MCC_BRIDGE=0 MCC_TPS=- MCC_MSPT=-
    return
  fi
  (( st[mtime] == MCC_BR_AT )) && return
  MCC_BR_AT=$st[mtime] MCC_BRIDGE=1
  MCC_BR=()
  local -a f2 names=()
  for line in "${(@f)$(<$f)}"; do
    f2=("${(@ps:\t:)line}")
    case $f2[1] in
      tps)    MCC_TPS=$f2[2] MCC_MSPT=$f2[3] ;;
      player) MCC_BR[$f2[2]]="${(j:	:)f2[3,-1]}"; names+=($f2[2]) ;;
    esac
  done
  # the plugin knows who is online, also those who joined before the log we read
  local n hms
  strftime -s hms '%H:%M:%S' $EPOCHSECONDS
  for n in $names; do [[ -n ${MCC_PLAYERS[$n]} ]] || { MCC_PLAYERS[$n]=$hms; MCC_PORDER+=($n) }; done
  for n in $MCC_PORDER; do (( ${names[(Ie)$n]} )) || _mcc_gone $n; done
}

# ── The console log ──────────────────────────────────────────

# Reads a log file from its start (the last 400 kB of a long one); what was parsed before is forgotten
_mcc_log_open() {
  (( MCC_FD )) && exec {MCC_FD}<&-
  MCC_FD=0 MCC_OFF=0 MCC_PART= MCC_LOGF=$1
  MCC_LOG=() MCC_EVENTS=() MCC_PLAYERS=() MCC_PORDER=() MCC_READY=0 MCC_LOGSTOP=0 MCC_PROGRESS=0 MCC_BACK=0
  [[ -r $1 ]] || return 0
  exec {MCC_FD}<$1 || { MCC_FD=0; return 1 }
  local -A st
  zstat -H st $1 2>/dev/null
  if (( st[size] > 400000 )); then
    sysseek -u $MCC_FD $(( st[size] - 400000 ))
    local skip
    read -r -u $MCC_FD skip     # the rest of a cut line
  fi
  (( MCC_OFF = systell(MCC_FD) ))
}

# New lines since last time (a file that became shorter was started again)
_mcc_log_poll() {
  [[ -n $MCC_LOGF ]] || return
  local -A st
  zstat -H st $MCC_LOGF 2>/dev/null || return
  if (( ! MCC_FD || st[size] < MCC_OFF )); then _mcc_log_open $MCC_LOGF || return; fi
  (( st[size] > MCC_OFF )) || return
  local chunk buf=$MCC_PART
  local -i n=0
  while sysread -i $MCC_FD -s 65536 chunk; do
    buf+=$chunk
    (( ++n > 64 )) && break
  done
  (( MCC_OFF = systell(MCC_FD) ))
  local -a lines=("${(@f)buf}")
  if [[ $buf == *$'\n' ]]; then MCC_PART=; else MCC_PART=$lines[-1]; lines[-1]=(); fi
  local l
  for l in $lines; do _mcc_line "$l"; done
}

# One line of the console: kept for the Log page, and what it says about players and the server
_mcc_line() {
  local l=${1//$'\r'/} hms= msg
  l=${l//$'\e'\[[0-9;?]#[A-Za-z]/}
  l=${l//$'\t'/    }
  MCC_LOG+=("$l")
  (( ${#MCC_LOG} > 5000 )) && MCC_LOG[1,1000]=()
  msg=$l
  if [[ $l == (#b)\[([0-2][0-9]:[0-5][0-9]:[0-5][0-9])[^\]]#\][^:]#:\ (*) ]]; then hms=$match[1] msg=$match[2]; fi
  [[ -z $hms ]] && strftime -s hms '%H:%M:%S' $EPOCHSECONDS
  case $msg in
    (#b)([A-Za-z0-9_.*-]##)\ joined\ the\ game)
      [[ -n ${MCC_PLAYERS[$match[1]]} ]] || MCC_PORDER+=($match[1])
      MCC_PLAYERS[$match[1]]=$hms
      _mcc_event $hms join "${LOTUS_L[mc_ev_join]//\%s/$match[1]}" ;;
    (#b)([A-Za-z0-9_.*-]##)\ (left\ the\ game|lost\ connection:*))
      if [[ -n ${MCC_PLAYERS[$match[1]]} ]]; then
        _mcc_gone $match[1]
        _mcc_event $hms leave "${LOTUS_L[mc_ev_leave]//\%s/$match[1]}"
      fi ;;
    (#b)(\[Not\ Secure\]\ |)\<([^\>]##)\>\ (*))
      _mcc_event $hms chat "<$match[2]> $match[3]" ;;
    (#b)([A-Za-z0-9_.*-]##)\ has\ (made\ the\ advancement|completed\ the\ challenge|reached\ the\ goal)\ \[(*)\])
      _mcc_event $hms goal "${${LOTUS_L[mc_ev_goal]//\%s/$match[1]}//\%a/$match[3]}" ;;
    Done\ \(*|*For\ help,\ type*)
      (( MCC_READY )) || _mcc_event $hms ready "$LOTUS_L[mc_ev_ready]"
      MCC_READY=1 MCC_PROGRESS=100 ;;
    (#b)Starting\ minecraft\ server\ version\ ([^ ]##)*)
      if [[ $MCC_VER != $match[1] ]]; then MCC_VER=$match[1]; _mcc_conf_save; fi ;;
    (#b)*Preparing\ spawn\ area:\ ([0-9]##)%*)
      MCC_PROGRESS=$match[1] ;;
    Stopping\ server*|Stopping\ the\ server*)
      MCC_LOGSTOP=1
      _mcc_event $hms stop "$LOTUS_L[mc_ev_stop]" ;;
    *You\ need\ to\ agree\ to\ the\ EULA*)
      MCC_PROBLEM=eula ;;
    *FAILED\ TO\ BIND\ TO\ PORT*)
      MCC_PROBLEM=port ;;
  esac
}

_mcc_gone() {
  unset "MCC_PLAYERS[$1]" "MCC_BR[$1]"
  MCC_PORDER=(${MCC_PORDER:#$1})
}

_mcc_event() {   # <hh:mm:ss> <kind> <text>
  MCC_EVENTS+=("${1[1,5]}"$'\t'"$2"$'\t'"$3")
  (( ${#MCC_EVENTS} > 60 )) && MCC_EVENTS[1,20]=()
}

# Commands typed before, for ↑ on the command line
_mcc_hist_load() {
  MCC_HIST=()
  [[ -r $MCC_S/history ]] && MCC_HIST=("${(@f)$(<$MCC_S/history)}")
  MCC_HIST=(${MCC_HIST:#})
}
_mcc_hist_add() {
  MCC_HIST=(${MCC_HIST:#$1} $1)
  (( ${#MCC_HIST} > 100 )) && MCC_HIST[1,-101]=()
  print -rl -- $MCC_HIST >| $MCC_S/history
}

# ── Small helpers for drawing ────────────────────────────────

# Plain text cut to a width, with … when it was longer → REPLY
_mcc_cut() {
  local -i n=$2
  (( n < 1 )) && { REPLY=; return }
  if (( ${#1} > n )); then REPLY="${1[1,n-1]}…"; else REPLY=$1; fi
}
# Plain text padded (and cut) to exactly a width → REPLY
_mcc_pad() { _mcc_cut "$1" $2; REPLY=${(r:$2:)REPLY} }

# A line with color codes cut to a width, with … at the end → REPLY
_mcc_clip() {
  local s=$1 o= pat=$'\e''\[[0-9;?]#[A-Za-z]'
  local -i w=$2 n=0 i=1 len=${#1}
  while (( i <= len && n < w - 1 )); do
    if [[ ${s[i]} == $'\e' && ${s[i,i+31]} == (#b)(${~pat})* ]]; then
      o+=$match[1]; (( i += ${#match[1]} )); continue
    fi
    o+=${s[i]}; (( i++, n++ ))
  done
  REPLY="$o…"$'\e[0m'
}

# Visible width of a line with color codes
_mcc_vw() { local s=${1//$'\e'\[[0-9;?]#[A-Za-z]/}; REPLY=${#s} }

# A bar of ■ and ·:  <percent> <width> <color>
_mcc_bar() {
  local -i p=$1 w=$2 n
  (( p < 0 )) && p=0; (( p > 100 )) && p=100
  (( n = (p * w + 50) / 100 ))
  REPLY="$3${(pl:n::■:)}$MCC_C[dim]${(pl:w-n::·:)}$MCC_C[r]"
}

# Ping as four bars in a color for how good it is → REPLY (plain width 4)
_mcc_ping_bars() {
  local -i p=$1 n c
  if (( p < 0 )); then REPLY="$MCC_C[dim]····$MCC_C[r]"; return; fi
  if (( p < 60 )); then n=4; elif (( p < 150 )); then n=3; elif (( p < 300 )); then n=2; else n=1; fi
  local col=$MCC_C[key]
  (( n == 2 )) && col=$MCC_C[key2]
  (( n == 1 )) && col=$MCC_C[red]
  local bars=▂▄▆█
  REPLY="$col${bars[1,n]}$MCC_C[dim]${(pl:4-n::·:)}$MCC_C[r]"
}

# Seconds as 3h 12m, 12m, 40s → REPLY
_mcc_dur() {
  local -i s=$1
  if (( s >= 86400 )); then REPLY="$(( s / 86400 ))d $(( s % 86400 / 3600 ))h"
  elif (( s >= 3600 )); then REPLY="$(( s / 3600 ))h $(( s % 3600 / 60 ))m"
  elif (( s >= 60 )); then REPLY="$(( s / 60 ))m"
  else REPLY="${s}s"; fi
}

# MB as "812 MB" or "1.4 GB" → REPLY
_mcc_mb() {
  local -i m=$1
  if (( m >= 1024 )); then printf -v REPLY '%.1f GB' $(( m / 1024.0 )); REPLY=${REPLY/.0 / }
  else REPLY="$m MB"; fi
}

# How long someone is online, from the time of their join → REPLY
_mcc_online_for() {
  local now
  strftime -s now '%H:%M:%S' $EPOCHSECONDS
  local -i a=$(( 10#${1[1,2]} * 3600 + 10#${1[4,5]} * 60 + 10#${1[7,8]} ))
  local -i b=$(( 10#${now[1,2]} * 3600 + 10#${now[4,5]} * 60 + 10#${now[7,8]} ))
  _mcc_dur $(( (b - a + 86400) % 86400 ))
}

_mcc_toast() {   # <ok|err|info> <text>
  MCC_TOASTK=$1 MCC_TOAST=$2 MCC_TOAST_AT=$EPOCHSECONDS
}

# The server's address for friends → REPLY
_mcc_addr() {
  local port=${MCC_PROP[server-port]:-25565}
  REPLY="${MCC_LAN:-localhost}:$port"
  [[ $port == 25565 && -n $MCC_LAN ]] && REPLY=$MCC_LAN
}

# ── The window ───────────────────────────────────────────────

_mcc_loop() {
  local -F now wait
  local -a sz
  while :; do
    now=$EPOCHREALTIME
    _mcc_log_poll
    if (( now - MCC_T1 >= 1 )); then
      MCC_T1=$now
      sz=(${=$(stty size < /dev/tty 2>/dev/null)})
      MCC_H=${sz[1]:-24} MCC_W=${sz[2]:-80}
      _mcc_probe
      _mcc_bridge
      _mcc_props
      # after a stop: leave, or start again for a restart
      if [[ $MCC_STATE == (stopped|crashed) ]]; then
        (( MCC_LEAVE )) && break
        (( MCC_RESTART )) && { MCC_RESTART=0; _mcc_start }
      fi
      if [[ $MCC_STATE == stopping ]] && (( MCC_STOP_AT && EPOCHSECONDS - MCC_STOP_AT == 60 )); then
        _mcc_toast info "$LOTUS_L[mc_still_stopping]"
      fi
    fi
    if (( now - MCC_T2 >= 2 )); then MCC_T2=$now; _mcc_sample; fi
    _mcc_search_poll
    (( MCC_TOAST_AT && EPOCHSECONDS - MCC_TOAST_AT > 6 )) && MCC_TOAST= MCC_TOAST_AT=0
    _mcc_draw
    # the world moves on the stats page; elsewhere the window only changes with the server
    if (( MCC_PAGE == 1 )) && [[ -z $MCC_ASK$MCC_IN ]]; then wait=0.12
    elif [[ -n $MCC_IN ]] || (( MCC_RLOADING )); then wait=0.2
    else wait=0.5; fi
    _mcc_key $wait
    [[ $REPLY == timeout ]] && continue
    _mcc_handle $REPLY
    (( $? == 9 )) && break
  done
}

# One key → REPLY: up down left right home end pgup pgdn enter space tab btab back del esc ctrlc,
# timeout, or the character
typeset -gi MCC_FAILS=0
_mcc_key() {
  local k c rest=
  local -F t0=$EPOCHREALTIME
  if ! read -rsk1 -t $1 k < /dev/tty; then
    if (( UI_INT )); then UI_INT=0; REPLY=ctrlc; return; fi
    # a keyboard that is gone answers at once, every time
    if (( EPOCHREALTIME - t0 < $1 / 3.0 )); then (( ++MCC_FAILS > 40 )) && { REPLY=ctrlc; return }
    else MCC_FAILS=0; fi
    REPLY=timeout
    return
  fi
  MCC_FAILS=0
  if [[ $k == $'\e' ]]; then
    while read -rsk1 -t 0.02 c < /dev/tty; do rest+=$c; [[ $c == [A-Za-z~] && $rest != O ]] && break; done
    k+=$rest
  fi
  case $k in
    $'\e[A'|$'\eOA') REPLY=up ;;      $'\e[B'|$'\eOB') REPLY=down ;;
    $'\e[C'|$'\eOC') REPLY=right ;;   $'\e[D'|$'\eOD') REPLY=left ;;
    $'\e[H'|$'\e[1~'|$'\eOH') REPLY=home ;; $'\e[F'|$'\e[4~'|$'\eOF') REPLY=end ;;
    $'\e[5~') REPLY=pgup ;;           $'\e[6~') REPLY=pgdn ;;
    $'\e[3~') REPLY=del ;;            $'\e[Z') REPLY=btab ;;
    $'\n'|$'\r') REPLY=enter ;;       ' ') REPLY=space ;;
    $'\t') REPLY=tab ;;               $'\x7f'|$'\b') REPLY=back ;;
    $'\x03') REPLY=ctrlc ;;           $'\e') REPLY=esc ;;
    $'\e'*|[[:cntrl:]]) REPLY=ignore ;;
    *) REPLY=$k ;;
  esac
}

# A key. Status 9 = leave the control center
_mcc_handle() {
  local key=$1
  [[ -n $MCC_IN ]] && { _mcc_input_key $key; return 0 }
  [[ -n $MCC_ASK ]] && { _mcc_ask_key $key; return }
  case $key in
    ctrlc) _mcc_quit; return ;;
    q|Q)
      if (( MCC_PAGE == 2 )) && [[ -n $MCC_SUB ]]; then MCC_SUB=; return 0; fi
      _mcc_quit; return ;;
    tab)  (( MCC_PAGE = MCC_PAGE % 3 + 1 )); return 0 ;;
    btab) (( MCC_PAGE = (MCC_PAGE + 1) % 3 + 1 )); return 0 ;;
    1|2|3) [[ -z $MCC_SUB || $MCC_PAGE != 2 ]] && { MCC_PAGE=$key; return 0 } ;;
  esac
  case $MCC_PAGE in
    1) _mcc_stats_key $key ;;
    2) if [[ $MCC_SUB == plugins ]]; then _mcc_plugins_key $key; else _mcc_settings_key $key; fi ;;
    3) _mcc_log_key $key ;;
  esac
  case $key in
    s|S) [[ $MCC_PAGE == 2 && $MCC_SUB == plugins ]] && return 0
         if [[ $MCC_STATE == (stopped|crashed) ]]; then _mcc_start
         elif [[ $MCC_STATE == stopping ]]; then
           # still stopping after a while: s ends it (the server saves on SIGTERM)
           (( MCC_PID && EPOCHSECONDS - MCC_STOP_AT > 20 )) && { kill -TERM $MCC_PID 2>/dev/null; _mcc_toast info "$LOTUS_L[mc_forced]" }
         elif (( ${#MCC_PORDER} )); then MCC_ASK=stop
         else _mcc_stop; fi ;;
    r|R) [[ $MCC_PAGE == 2 && $MCC_SUB == plugins ]] && return 0
         if [[ $MCC_STATE == (stopped|crashed) ]]; then _mcc_start
         elif [[ $MCC_STATE == (running|starting|preparing) ]]; then
           (( ${#MCC_PORDER} )) && MCC_ASK=restart || { MCC_RESTART=1; _mcc_stop }
         fi ;;
    o|O) [[ $MCC_PAGE == 2 && $MCC_SUB == plugins ]] && return 0
         _mcc_open_folder ;;
    e|E) [[ $MCC_PROBLEM == eula ]] && MCC_ASK=eula ;;
  esac
  return 0
}

_mcc_quit() {
  if [[ $MCC_MODE == ours && $MCC_STATE == (running|starting|preparing) ]]; then MCC_ASK=quit; return 0; fi
  if [[ $MCC_STATE == stopping ]]; then MCC_LEAVE=1; return 0; fi
  return 9
}

_mcc_open_folder() {
  if open -- $MCC_DIR 2>/dev/null; then _mcc_toast ok "$LOTUS_L[mc_opened]"
  else _mcc_toast err "$LOTUS_L[mc_err_open]"; fi
}

# The question in the bottom line
_mcc_ask_key() {
  local key=$1 ask=$MCC_ASK
  MCC_ASK=
  case $ask in
    quit)
      case $key in
        enter|q|y) return 9 ;;
        s|S) MCC_LEAVE=1; _mcc_stop ;;
      esac ;;
    stop)    [[ $key == (y|Y|j|J|enter) ]] && _mcc_stop ;;
    restart) [[ $key == (y|Y|j|J|enter) ]] && { MCC_RESTART=1; _mcc_stop } ;;
    eula)
      if [[ $key == (y|Y|j|J) ]]; then
        print -r -- "eula=true" >| $MCC_DIR/eula.txt
        lotus_log INFO minecraft "EULA accepted for $MCC_NAME"
        MCC_PROBLEM=
        _mcc_start
      fi ;;
    icondel)
      if [[ $key == (y|Y|j|J) ]]; then
        rm -f -- $MCC_DIR/server-icon.png
        _mcc_changed
        _mcc_toast ok "$LOTUS_L[mc_icon_removed]"
      fi ;;
    remove:*)
      if [[ $key == (y|Y|j|J) ]]; then
        if _mcp_remove $MCC_DIR ${ask#remove:}; then _mcc_changed; _mcc_toast ok "${LOTUS_L[mc_pl_removed]//\%s/${ask#remove:}}"
        else _mcc_toast err "$LOTUS_L[mc_err_remove]"; fi
        _mcc_inst_load
      fi ;;
    player:*)
      local p=${ask#player:} cmd=
      case $key in
        1) cmd="op $p" ;; 2) cmd="deop $p" ;; 3) cmd="kick $p" ;; 4) cmd="ban $p" ;;
        5) cmd="gamemode creative $p" ;; 6) cmd="gamemode survival $p" ;; 7) cmd="whitelist add $p" ;;
      esac
      if [[ -n $cmd ]]; then
        _mcc_send "$cmd" && _mcc_toast ok "› $cmd" || _mcc_toast err "$LOTUS_L[mc_err_cmd]"
      fi ;;
  esac
  return 0
}

# Something that only counts after a restart
_mcc_changed() { [[ $MCC_STATE == (running|starting|preparing) ]] && MCC_CHANGED=1 }

# ── Text input in the bottom area: commands, the description, dropped files, the search ──

_mcc_input() {   # <kind> <label> [text]
  MCC_IN=$1 MCC_INLABEL=$2 MCC_INTEXT=${3-} MCC_HISTI=$(( ${#MCC_HIST} + 1 ))
}

_mcc_input_key() {
  local key=$1 kind=$MCC_IN
  case $key in
    timeout|ignore|tab|btab|left|right|home|end|pgup|pgdn|del) ;;
    esc|ctrlc) MCC_IN= ;;
    back) MCC_INTEXT=${MCC_INTEXT[1,-2]} ;;
    space) MCC_INTEXT+=' ' ;;
    up)
      if [[ $kind == cmd ]] && (( MCC_HISTI > 1 )); then (( MCC_HISTI-- )); MCC_INTEXT=$MCC_HIST[MCC_HISTI]
      elif [[ $kind == search ]]; then MCC_IN=; _mcc_plugins_key up; fi ;;
    down)
      if [[ $kind == cmd ]] && (( MCC_HISTI <= ${#MCC_HIST} )); then (( MCC_HISTI++ )); MCC_INTEXT=${MCC_HIST[MCC_HISTI]-}
      elif [[ $kind == search ]]; then MCC_IN=; _mcc_plugins_key down; fi ;;
    enter)
      MCC_IN=
      _mcc_input_done $kind "$MCC_INTEXT" ;;
    *) (( ${#MCC_INTEXT} < 400 )) && MCC_INTEXT+=$key ;;
  esac
  # more keys that are already waiting (a pasted or dropped path) come in before the next frame
  if [[ -n $MCC_IN && $key != (timeout|enter|esc) ]]; then
    local k
    while read -rsk1 -t 0.002 k < /dev/tty; do
      case $k in
        $'\n'|$'\r') kind=$MCC_IN; MCC_IN=; _mcc_input_done $kind "$MCC_INTEXT"; break ;;
        $'\x7f'|$'\b') MCC_INTEXT=${MCC_INTEXT[1,-2]} ;;
        $'\e') MCC_IN=; break ;;
        [[:print:]]) MCC_INTEXT+=$k ;;
      esac
    done
  fi
  [[ $MCC_IN == search ]] && MCC_Q=$MCC_INTEXT MCC_QAT=$EPOCHREALTIME
}

_mcc_input_done() {   # <kind> <text>
  local kind=$1 text=$2
  case $kind in
    cmd)
      text=${text##[[:space:]/]##}
      [[ -z $text ]] && return
      _mcc_hist_add "$text"
      if _mcc_send "$text"; then MCC_BACK=0
      else _mcc_toast err "$LOTUS_L[mc_err_cmd]"; fi ;;
    motd)
      text=${text//[[:cntrl:]]/}
      _mcc_prop_set motd "$text"
      _mcc_changed
      _mcc_toast ok "$LOTUS_L[mc_motd_saved]"
      lotus_log INFO minecraft "Description changed for $MCC_NAME" ;;
    icon)
      [[ -z ${text//[[:space:]]/} ]] && return
      local -a w=(${(z)text})
      ui_clean_path "${(Q)w[1]}"
      _mcc_icon_set $REPLY ;;
    drop)
      [[ -z ${text//[[:space:]]/} ]] && return
      if _mcp_drop $MCC_DIR "$text"; then
        _mcc_changed
        _mcc_toast ok "${LOTUS_L[mc_pl_added]//\%s/${(j:, :)MCP_DONE}}"
        [[ -n $MCP_ERR ]] && _mcc_toast err "${(j:, :)MCP_DONE} ✓ · $MCP_ERR"
      else
        _mcc_toast err "${MCP_ERR:-$LOTUS_L[mc_err_drop]}"
      fi
      _mcc_inst_load ;;
    search)
      MCC_Q=$text MCC_QAT=0 ;;
  esac
}

# ── Page 1: Stats ────────────────────────────────────────────

_mcc_stats_key() {
  local -i n=${#MCC_PORDER}
  case $1 in
    up)   (( n )) && (( MCC_SEL = MCC_SEL > 1 ? MCC_SEL - 1 : n )) ;;
    down) (( n )) && (( MCC_SEL = MCC_SEL < n ? MCC_SEL + 1 : 1 )) ;;
    enter)
      (( n )) || return 0
      (( MCC_SEL > n )) && MCC_SEL=n
      if [[ $MCC_MODE == ours ]]; then MCC_ASK="player:$MCC_PORDER[MCC_SEL]"
      else _mcc_toast info "$LOTUS_L[mc_external_cmd]"; fi ;;
  esac
}

# The state of the server in a few words, with its color → REPLY
_mcc_state_text() {
  local -a spin=(◐ ◓ ◑ ◒)
  local sp=$spin[$(( int(EPOCHREALTIME * 4) % 4 + 1 ))]
  case $MCC_STATE in
    running)
      _mcc_dur $MCC_UP
      REPLY="$MCC_C[key]● $LOTUS_L[mc_st_running]$MCC_C[r]$MCC_C[dim] · $REPLY$MCC_C[r]"
      [[ $MCC_MODE == external ]] && REPLY+="$MCC_C[dim] · $LOTUS_L[mc_st_external]$MCC_C[r]" ;;
    starting)  REPLY="$MCC_C[key2]$sp $LOTUS_L[mc_st_starting]$MCC_C[r]"
               (( MCC_PROGRESS )) && REPLY+="$MCC_C[dim] · $MCC_PROGRESS %$MCC_C[r]" ;;
    preparing) REPLY="$MCC_C[key2]$sp $LOTUS_L[mc_st_preparing]$MCC_C[r]" ;;
    stopping)  REPLY="$MCC_C[key2]$sp $LOTUS_L[mc_st_stopping]$MCC_C[r]" ;;
    crashed)   REPLY="$MCC_C[red]✗ $LOTUS_L[mc_st_crashed]$MCC_C[r]" ;;
    *)         REPLY="$MCC_C[dim]○ $LOTUS_L[mc_st_stopped]$MCC_C[r]" ;;
  esac
  case $MCC_PROBLEM in
    eula) REPLY="$MCC_C[red]✗ $LOTUS_L[mc_pr_eula]$MCC_C[r]" ;;
    port) [[ $MCC_STATE != running ]] && REPLY="$MCC_C[red]✗ ${LOTUS_L[mc_pr_port]//\%s/${MCC_PROP[server-port]:-25565}}$MCC_C[r]" ;;
  esac
}

# The info column: label and value lines → reply
_mcc_info_rows() {
  local k=$'\e[1;'"${LOTUS_C[key]}m" r=$MCC_C[r] d=$MCC_C[dim]
  local -a rows=()
  local -i maxp=${MCC_PROP[max-players]:-20} n=${#MCC_PORDER}
  _mcc_state_text; rows+=("${k}${(r:9:)LOTUS_L[mc_i_status]}$r $REPLY")
  local t=${(C)MCC_TYPE}
  rows+=("${k}${(r:9:)LOTUS_L[mc_i_server]}$r $t ${MCC_VER:-?}")
  _mcc_bar $(( maxp ? n * 100 / maxp : 0 )) 10 $MCC_C[key]
  rows+=("${k}${(r:9:)LOTUS_L[mc_i_players]}$r ${(r:8:)${:-$n / $maxp}} $REPLY")
  if (( MCC_BRIDGE )) && [[ $MCC_TPS != - ]]; then
    local -i tp=${MCC_TPS%%.*} c
    local col=$MCC_C[key]
    (( tp < 18 )) && col=$MCC_C[key2]
    (( tp < 12 )) && col=$MCC_C[red]
    _mcc_bar $(( tp * 5 )) 10 $col
    rows+=("${k}${(r:9:)LOTUS_L[mc_i_tps]}$r ${(r:8:)MCC_TPS} $REPLY ${d}${MCC_MSPT} ms$r")
  elif [[ $MCC_TYPE == paper ]]; then
    rows+=("${k}${(r:9:)LOTUS_L[mc_i_tps]}$r ${d}–  ${${MCC_PID:#0}:+$LOTUS_L[mc_tps_wait]}$r")
  else
    rows+=("${k}${(r:9:)LOTUS_L[mc_i_tps]}$r ${d}–  $LOTUS_L[mc_tps_paper]$r")
  fi
  if (( MCC_PID && MCC_RSS )); then
    _mcc_mb $MCC_RSS; local used=$REPLY
    if (( MCC_XMX )); then
      _mcc_mb $MCC_XMX; local max=$REPLY
      _mcc_bar $(( MCC_RSS * 100 / MCC_XMX )) 10 $MCC_C[accent]
      rows+=("${k}${(r:9:)LOTUS_L[mc_i_memory]}$r ${(r:8:)used} $REPLY ${d}${LOTUS_L[mc_of]} $max$r")
    else
      rows+=("${k}${(r:9:)LOTUS_L[mc_i_memory]}$r $used")
    fi
    rows+=("${k}${(r:9:)LOTUS_L[mc_i_cpu]}$r ${MCC_CPU} %")
  else
    rows+=("${k}${(r:9:)LOTUS_L[mc_i_memory]}$r ${d}–$r")
    rows+=("${k}${(r:9:)LOTUS_L[mc_i_cpu]}$r ${d}–$r")
  fi
  if (( MCC_WORLDKB >= 0 )); then _mcc_mb $(( MCC_WORLDKB / 1024 )); rows+=("${k}${(r:9:)LOTUS_L[mc_i_world]}$r $REPLY")
  else rows+=("${k}${(r:9:)LOTUS_L[mc_i_world]}$r ${d}${${(M)MCC_WORLDKB:#-2}:+–}${${MCC_WORLDKB:#-2}:+…}$r"); fi
  _mcc_addr
  rows+=("${k}${(r:9:)LOTUS_L[mc_i_address]}$r $REPLY${d}  · localhost $LOTUS_L[mc_on_mac]$r")
  reply=("${rows[@]}")
}

_mcc_page_stats() {
  local -i W=$1 H=$2 aw ar i base=${#out}
  local d=$MCC_C[dim] r=$MCC_C[r] b=$MCC_C[border]
  _mcc_info_rows; local -a info=("${reply[@]}")
  local -i players=${#MCC_PORDER}
  local moving=0
  [[ $MCC_STATE == (running|starting) ]] && moving=1
  if (( W >= 78 && H >= 15 )); then
    # the world on the left, the numbers next to it
    (( aw = W - 62, aw > 64 && (aw = 64), aw < 16 && (aw = 16), ar = H - 9, ar > 12 && (ar = 12), ar < 6 && (ar = 6) ))
    _mcw_frame $aw $ar $players $moving
    local -a art=("${reply[@]}")
    local top="╭${(pl:aw::─:)}╮" bot="╰${(pl:aw::─:)}╯"
    local label=" ${LOTUS_L[mc_world]} "
    top="╭─${label}${(pl:aw-1-${#label}::─:)}╮"
    out+=("  $b$top$r")
    for (( i = 1; i <= ar; i++ )); do
      out+=("  $b│$r${art[i]}$b│$r   ${info[i]-}")
    done
    out+=("  $b$bot$r   ${info[ar+1]-}")
    for (( i = ar + 2; i <= ${#info}; i++ )); do out+=("  ${(l:aw+2:)}   ${info[i]}"); done
  else
    local row
    for row in $info; do out+=("  $row"); done
    (( ar = H - ${#info} - 9 ))
    if (( ar >= 3 )); then
      (( ar > 6 )) && ar=6
      _mcw_frame $(( W - 4 )) $ar $players $moving
      out+=("")
      for row in "${reply[@]}"; do out+=("  $row"); done
    fi
  fi
  out+=("")
  # players online, with ping
  local a=$'\e[1;'"${LOTUS_C[accent]}m"
  out+=("  ${a}${(U)LOTUS_L[mc_players_online]}$r${d}  $players$r")
  local -i left=$(( H - (${#out} - base) - 1 ))
  if (( players == 0 )); then
    _mcc_addr
    if [[ $MCC_STATE == running ]]; then out+=("    ${d}${LOTUS_L[mc_nobody]//\%s/$REPLY}$r")
    else out+=("    ${d}–$r"); fi
  else
    (( MCC_SEL > players )) && MCC_SEL=players
    local p f pingtxt extra mark
    local -i shown=0 maxrows=$(( left > 8 ? left - 4 : left ))
    (( maxrows < 1 )) && maxrows=1
    for (( i = 1; i <= players && shown < maxrows; i++ )); do
      p=$MCC_PORDER[i]
      local -a bf=("${(@ps:\t:)MCC_BR[$p]}")
      if [[ -n ${MCC_BR[$p]} ]]; then
        _mcc_ping_bars $bf[1]; pingtxt="$REPLY ${(l:4:)bf[1]} ms"
        extra="${bf[4]} · ♥ ${bf[3]} · ${bf[2]}"
      else
        _mcc_ping_bars -1; pingtxt="$REPLY    – ms"
        extra=
      fi
      _mcc_online_for ${MCC_PLAYERS[$p]}
      local since=$REPLY
      _mcc_pad $p 18; local nm=$REPLY
      if (( i == MCC_SEL && MCC_PAGE == 1 )); then mark="$MCC_C[accent]›$r $MCC_C[B]$nm$r"
      else mark="  $nm"; fi
      _mcc_cut "$extra" $(( W - 52 ))
      out+=("   $mark $pingtxt   ${(l:7:)since}   $d$REPLY$r")
      (( shown++ ))
    done
    (( players > shown )) && out+=("     $d+ $(( players - shown ))$r")
    if (( ! MCC_BRIDGE )); then
      if [[ $MCC_TYPE == paper ]]; then out+=("    $d$LOTUS_L[mc_ping_restart]$r")
      else out+=("    $d$LOTUS_L[mc_ping_paper]$r"); fi
    fi
  fi
  # the newest events, as many as fit
  (( left = H - (${#out} - base) - 2 ))
  (( left - 2 > ${#MCC_EVENTS} )) && left=$(( ${#MCC_EVENTS} + 2 ))
  if (( left >= 3 && ${#MCC_EVENTS} )); then
    out+=("")
    out+=("  ${a}${(U)LOTUS_L[mc_latest]}$r")
    local ev
    local -a evs=("${(@)MCC_EVENTS[-(left-2),-1]}")
    for ev in $evs; do
      local -a e=("${(@ps:\t:)ev}")
      local col=
      case $e[2] in join|ready) col=$MCC_C[key] ;; leave|stop) col=$d ;; goal) col=$MCC_C[salute] ;; chat) col=$MCC_C[accent] ;; esac
      _mcc_cut "$e[3]" $(( W - 14 ))
      out+=("    $d$e[1]$r  $col$REPLY$r")
    done
  fi
}

# ── Page 2: Settings ─────────────────────────────────────────

_mcc_settings_key() {
  case $1 in
    up)   (( MCC_SSEL = MCC_SSEL > 1 ? MCC_SSEL - 1 : 4 )) ;;
    down) (( MCC_SSEL = MCC_SSEL < 4 ? MCC_SSEL + 1 : 1 )) ;;
    enter|right)
      case $MCC_SSEL in
        1) _mcc_input icon "$LOTUS_L[mc_icon_drop]" ;;
        2) _mcc_motd; _mcc_input motd "$LOTUS_L[mc_motd_label]" "$REPLY" ;;
        3) MCC_SUB=plugins MCC_PSEL=1; _mcc_inst_load
           [[ $MCC_TYPE == paper && $MCC_QSENT == - ]] && MCC_Q= MCC_QAT=0 ;;
        4) _mcc_open_folder ;;
      esac ;;
    x|X|del|back) (( MCC_SSEL == 1 )) && [[ -f $MCC_DIR/server-icon.png ]] && MCC_ASK=icondel ;;
  esac
}

# A picture as the server icon: the middle square, 64 × 64 pixels, PNG (macOS' sips does it)
_mcc_icon_set() {
  local src=$1
  [[ -f $src ]] || { _mcc_toast err "${LOTUS_L[mc_err_nofile]//\%s/${src:t}}"; return 1 }
  (( $+commands[sips] )) || { _mcc_toast err "$LOTUS_L[mc_err_sips]"; return 1 }
  local info=$(sips -g pixelWidth -g pixelHeight -- $src 2>/dev/null)
  local -i w=0 h=0
  [[ $info == (#b)*pixelWidth:\ ([0-9]##)* ]] && w=$match[1]
  [[ $info == (#b)*pixelHeight:\ ([0-9]##)* ]] && h=$match[1]
  (( w && h )) || { _mcc_toast err "${LOTUS_L[mc_err_image]//\%s/${src:t}}"; return 1 }
  local -i m=$(( w < h ? w : h ))
  local tmp=$MCC_S/icon-new
  if sips -s format png -c $m $m -- $src --out $tmp-a.png >/dev/null 2>&1 &&
     sips -z 64 64 $tmp-a.png --out $tmp-b.png >/dev/null 2>&1 && [[ -s $tmp-b.png ]]; then
    zf_mv -f $tmp-b.png $MCC_DIR/server-icon.png
    rm -f $tmp-a.png
    MCC_ICONKEY=
    _mcc_changed
    _mcc_toast ok "$LOTUS_L[mc_icon_saved]"
    lotus_log INFO minecraft "Server icon set for $MCC_NAME from ${src:t}"
  else
    rm -f $tmp-a.png $tmp-b.png
    _mcc_toast err "${LOTUS_L[mc_err_image]//\%s/${src:t}}"
  fi
}

# The icon as character art, 12 × 6 (the grass block when there is none) → MCC_ICON
_mcc_icon_art() {
  local f=$MCC_DIR/server-icon.png
  local -A st
  local key=none
  zstat -H st $f 2>/dev/null && key="$st[mtime] $st[size] $LOTUS_MODE"
  [[ $key == $MCC_ICONKEY && -n $MCC_ICON ]] && return
  MCC_ICONKEY=$key
  if [[ $key != none ]] && (( $+commands[sips] )); then
    local bmp=$MCC_S/icon.bmp
    if sips -s format bmp -Z 48 -- $f --out $bmp >/dev/null 2>&1; then
      MCC_ICON=("${(@f)$(/usr/bin/perl $LOTUS_ROOT/lib/cover.pl $bmp 12 6 $LOTUS_MODE 2>/dev/null)}")
      rm -f $bmp
      (( ${#MCC_ICON} )) && return
    fi
  fi
  _mcw_icon
  MCC_ICON=("${reply[@]}")
}

# The server as it shows in Minecraft's server list → lines into out
_mcc_preview() {
  local -i w=$1 i
  (( w > 70 )) && w=70
  local b=$MCC_C[border] r=$MCC_C[r] d=$MCC_C[dim]
  _mcc_icon_art
  _mcc_motd; local motd=$REPLY
  local -a ml=("${(@f)${motd//\\n/$'\n'}}")
  local -i maxp=${MCC_PROP[max-players]:-20} inner=$(( w - 4 ))
  local count="${#MCC_PORDER}/$maxp"
  _mcc_ping_bars $(( MCC_STATE == running ? 20 : -1 ))
  local ping=$REPLY
  [[ $MCC_STATE == running ]] || count=$LOTUS_L[mc_offline]
  local -i tw=$(( inner - 14 - ${#count} - 8 ))
  _mcc_pad "$MCC_NAME" $tw; local name=$REPLY
  local -a text=("$MCC_C[B]$name$r  $d$count$r  $ping")
  _mcc_pad "${ml[1]}" $(( inner - 14 )); text+=("$REPLY")
  _mcc_pad "${ml[2]-}" $(( inner - 14 )); text+=("$d$REPLY$r")
  local title=" ${LOTUS_L[mc_preview]} "
  out+=("  $b╭─$r$d$title$r$b${(pl:inner+1-${#title}::─:)}╮$r")
  for (( i = 1; i <= 6; i++ )); do
    if (( i >= 2 && i <= 4 )); then
      _mcc_vw "${text[i-1]}"
      out+=("  $b│$r ${MCC_ICON[i]-${(l:12:)}}$r  ${text[i-1]}${(l:inner-13-REPLY:)}$b│$r")
    else
      out+=("  $b│$r ${MCC_ICON[i]-${(l:12:)}}$r  ${(l:inner-13:)}$b│$r")
    fi
  done
  out+=("  $b╰${(pl:inner+2::─:)}╯$r")
}

_mcc_page_settings() {
  local -i W=$1 H=$2 i base=${#out}
  local r=$MCC_C[r] d=$MCC_C[dim] a=$'\e[1;'"${LOTUS_C[accent]}m"
  if [[ $MCC_SUB == plugins ]]; then _mcc_page_plugins $W $H; return; fi
  local -a jars=($MCC_DIR/plugins/*.jar(N))
  local -i nplug=${#jars}
  _mcc_motd; local motd=$REPLY
  _mcc_cut "$motd" $(( W - 30 )); motd=$REPLY
  local icon
  [[ -f $MCC_DIR/server-icon.png ]] && icon="server-icon.png · 64 × 64" || icon=$LOTUS_L[mc_icon_none]
  local plug
  if [[ $MCC_TYPE == paper ]]; then plug="${LOTUS_L[mc_pl_count]//\%d/$nplug}"
  else plug=$LOTUS_L[mc_pl_vanilla]; fi
  ui_path $MCC_DIR $(( W - 30 )); local folder=$REPLY
  local -a items=(
    "$LOTUS_L[mc_s_icon]|$icon|$LOTUS_L[mc_s_icon_d]"
    "$LOTUS_L[mc_s_motd]|$motd|$LOTUS_L[mc_s_motd_d]"
    "$LOTUS_L[mc_s_plugins]|$plug|$LOTUS_L[mc_s_plugins_d]"
    "$LOTUS_L[mc_s_folder]|$folder|$LOTUS_L[mc_s_folder_d]")
  out+=("  ${a}${(U)LOTUS_L[mc_server]}$r")
  out+=("")
  local -a f
  for (( i = 1; i <= 4; i++ )); do
    f=("${(@s:|:)items[i]}")
    if (( i == MCC_SSEL )); then
      out+=("  $MCC_C[accent]›$r $MCC_C[B]${(r:14:)f[1]}$r $f[2]")
      out+=("                   $d$f[3]$r")
    else
      out+=("    ${(r:14:)f[1]} $d$f[2]$r")
    fi
  done
  out+=("")
  if (( MCC_CHANGED )); then
    out+=("  $MCC_C[key2]↻ $LOTUS_L[mc_restart_needed]$r")
    out+=("")
  fi
  (( H - (${#out} - base) >= 9 )) && _mcc_preview $(( W - 4 ))
}

# ── Settings → Plugins ───────────────────────────────────────

_mcc_inst_load() { _mcp_installed $MCC_DIR; MCC_INST=("${reply[@]}") }

# The background search: started a moment after the last key, read when it is there
_mcc_search_poll() {
  [[ $MCC_SUB == plugins && $MCC_TYPE == paper ]] || return
  if [[ $MCC_Q != $MCC_QSENT ]] && (( EPOCHREALTIME - MCC_QAT > 0.35 )); then
    MCC_QSENT=$MCC_Q
    MCC_QFILE=$LOTUS_CACHE/mc-search.$$.$RANDOM
    zf_mkdir -p $LOTUS_CACHE
    MCC_RLOADING=1 MCC_RSTATE=loading MCC_RES=() MCC_RTOTAL=0
    _mcp_search_start "$MCC_Q" "$MCC_VER" 0 $MCC_QFILE
    return
  fi
  if (( MCC_RLOADING )) && [[ -e $MCC_QFILE ]]; then
    local -a lines=("${(@f)$(<$MCC_QFILE)}")
    rm -f -- $MCC_QFILE $MCC_QFILE.err
    MCC_RLOADING=0
    if [[ $lines[1] == error ]]; then MCC_RSTATE=error; return; fi
    MCC_RSTATE=idle
    MCC_RTOTAL=${lines[1]:-0}
    MCC_RES+=("${(@)lines[2,-1]}")
    MCC_RES=(${MCC_RES:#})
  fi
}

# More results when the list reaches its end
_mcc_search_more() {
  (( MCC_RLOADING || ${#MCC_RES} >= MCC_RTOTAL || ${#MCC_RES} >= 300 )) && return
  MCC_QFILE=$LOTUS_CACHE/mc-search.$$.$RANDOM
  MCC_RLOADING=1
  _mcp_search_start "$MCC_Q" "$MCC_VER" ${#MCC_RES} $MCC_QFILE
}

_mcc_plugins_key() {
  local -i n=$(( ${#MCC_INST} + ${#MCC_RES} ))
  case $1 in
    esc|left) MCC_SUB= ;;
    up)   (( n )) && (( MCC_PSEL = MCC_PSEL > 1 ? MCC_PSEL - 1 : n )) ;;
    down) (( n )) && (( MCC_PSEL = MCC_PSEL < n ? MCC_PSEL + 1 : 1 )) ;;
    pgup) (( MCC_PSEL -= 10, MCC_PSEL < 1 && (MCC_PSEL = 1) )) ;;
    pgdn) (( MCC_PSEL += 10, MCC_PSEL > n && (MCC_PSEL = n) )) ;;
    home) MCC_PSEL=1 ;;
    end)  MCC_PSEL=$n ;;
    /|f)  [[ $MCC_TYPE == paper ]] && _mcc_input search "$LOTUS_L[mc_search]" "$MCC_Q" ;;
    d|D)  [[ $MCC_TYPE == paper ]] && _mcc_input drop "$LOTUS_L[mc_drop_label]" ;;
    x|X|del)
      if (( MCC_PSEL <= ${#MCC_INST} )); then
        local -a f=("${(@ps:\t:)MCC_INST[MCC_PSEL]}")
        [[ $f[4] == lotus ]] && { _mcc_toast info "$LOTUS_L[mc_bridge_keep]"; return 0 }
        MCC_ASK="remove:$f[1]"
      fi ;;
    enter)
      if (( MCC_PSEL > ${#MCC_INST} && MCC_PSEL <= n )); then
        local -a f=("${(@ps:\t:)MCC_RES[MCC_PSEL - ${#MCC_INST}]}")
        _mcc_install_one $f[1] $f[2] $f[3]
      elif (( MCC_PSEL <= ${#MCC_INST} && n )); then
        local -a f=("${(@ps:\t:)MCC_INST[MCC_PSEL]}")
        _mcc_toast info "plugins/$f[1]"
      fi ;;
    [[:print:]])
      # typing starts the search right away
      [[ $MCC_TYPE == paper && $1 != (q|Q|s|S|r|R|o|O|1|2|3) ]] && { _mcc_input search "$LOTUS_L[mc_search]" "$MCC_Q$1"; MCC_Q=$MCC_INTEXT MCC_QAT=$EPOCHREALTIME } ;;
  esac
  (( n && MCC_PSEL >= n - 2 && MCC_PSEL > ${#MCC_INST} )) && _mcc_search_more
  return 0
}

# Installs with a frame that says so first (the download takes a moment)
_mcc_install_one() {   # <id> <slug> <title>
  MCC_TOAST="${LOTUS_L[mc_installing]//\%s/$3}" MCC_TOASTK=info MCC_TOAST_AT=$EPOCHSECONDS
  _mcc_draw
  MCP_DONE=() MCP_ERR=
  if _mcp_install $MCC_DIR $1 $2 $3 $MCC_VER; then
    _mcc_changed
    _mcc_toast ok "${LOTUS_L[mc_installed]//\%s/${(j:, :)MCP_DONE}}"
    [[ -n $MCP_ERR ]] && _mcc_toast err "${(j:, :)MCP_DONE} ✓ · $MCP_ERR"
  else
    _mcc_toast err "$MCP_ERR"
  fi
  _mcc_inst_load
}

_mcc_page_plugins() {
  local -i W=$1 H=$2 i base=${#out}
  local r=$MCC_C[r] d=$MCC_C[dim] a=$'\e[1;'"${LOTUS_C[accent]}m" k=$MCC_C[key]
  out+=("  ${a}${(U)LOTUS_L[mc_s_plugins]}$r$d  ${(C)MCC_TYPE} ${MCC_VER:-?} · Modrinth$r")
  out+=("")
  if [[ $MCC_TYPE != paper ]]; then
    out+=("    $LOTUS_L[mc_pl_vanilla_1]")
    out+=("    $d$LOTUS_L[mc_pl_vanilla_2]$r")
    return
  fi
  # the search field
  local q=$MCC_Q cursor=
  [[ $MCC_IN == search ]] && { q=$MCC_INTEXT cursor="$k▏$r" }
  local stat_txt=
  case $MCC_RSTATE in
    loading) stat_txt="$d$LOTUS_L[mc_searching]$r" ;;
    error)   stat_txt="$MCC_C[red]$LOTUS_L[mc_err_search]$r" ;;
    *)       _mcp_count $MCC_RTOTAL; stat_txt="$d${${LOTUS_L[mc_found]//\%d/${#MCC_RES}}//\%t/$REPLY}$r" ;;
  esac
  _mcc_cut "$q" $(( W - 40 ))
  if [[ -z $q && $MCC_IN != search ]]; then
    _mcc_cut "/ $LOTUS_L[mc_search_hint]" $(( W - 18 ))
    out+=("    ${(r:8:)LOTUS_L[mc_search]} $d$REPLY$r")
  else
    out+=("    ${(r:8:)LOTUS_L[mc_search]} $MCC_C[accent]›$r $REPLY$cursor")
  fi
  out+=("             $stat_txt")
  out+=("")
  # one list: installed first, then what Modrinth found
  local -a rows=()
  local -i ni=${#MCC_INST} nr=${#MCC_RES} n
  (( n = ni + nr ))
  (( MCC_PSEL > n )) && MCC_PSEL=n
  (( MCC_PSEL < 1 )) && MCC_PSEL=1
  local line from
  local -a f
  local -A have=()
  for line in $MCC_INST; do f=("${(@ps:\t:)line}"); have[${(L)f[2]}]=1; done
  _mcp_mine $MCC_DIR
  rows+=("H|${(U)LOTUS_L[mc_installed_h]}  $ni")
  (( ni )) || rows+=("T|$LOTUS_L[mc_none_yet]")
  for (( i = 1; i <= ni; i++ )); do
    f=("${(@ps:\t:)MCC_INST[i]}")
    case $f[4] in lotus) from=$LOTUS_L[mc_from_lotus] ;; modrinth) from=Modrinth ;; *) from=$LOTUS_L[mc_from_you] ;; esac
    _mcc_pad "$f[2]" 24; local nm=$REPLY
    _mcc_pad "$f[3]" 12
    rows+=("$i|$k●$r ${nm}|$d$REPLY  $from$r")
  done
  rows+=("B|")
  if [[ -z $MCC_QSENT || $MCC_QSENT == - ]]; then rows+=("H|${(U)LOTUS_L[mc_popular]//\%s/$MCC_VER}")
  else rows+=("H|${(U)LOTUS_L[mc_results]}"); fi
  for (( i = 1; i <= nr; i++ )); do
    f=("${(@ps:\t:)MCC_RES[i]}")
    _mcp_count $f[4]; local dl=$REPLY
    _mcc_pad "$f[3]" 24; local nm=$REPLY
    local mark=' '
    [[ -n ${MCP_MINE[$f[1]]} || -n ${have[${(L)f[3]}]} ]] && mark="$k●$r"
    _mcc_cut "$f[6]" $(( W - 44 ))
    rows+=("$(( ni + i ))|$mark ${nm}|$d${(l:6:)dl}$r  $REPLY")
  done
  (( MCC_RLOADING && nr )) && rows+=("T|$LOTUS_L[mc_searching]")
  # a window around the selection
  local -i room=$(( H - (${#out} - base) - 1 )) sel=0 top=1
  for (( i = 1; i <= ${#rows}; i++ )); do [[ ${rows[i]%%|*} == $MCC_PSEL ]] && sel=i; done
  (( room < 3 )) && room=3
  (( sel > room - 1 )) && (( top = sel - room + 2 ))
  for (( i = top; i < top + room && i <= ${#rows}; i++ )); do
    local tag=${rows[i]%%|*} rest=${rows[i]#*|}
    case $tag in
      H) out+=("  ${a}${rest}$r") ;;
      B) out+=("") ;;
      T) out+=("    $d$rest$r") ;;
      *)
        local c1=${rest%%|*} c2=${rest#*|}
        if (( tag == MCC_PSEL )); then out+=("  $MCC_C[accent]›$r $c1 $c2")
        else out+=("    $c1 $c2"); fi ;;
    esac
  done
}

# ── Page 3: Log ──────────────────────────────────────────────

_mcc_log_key() {
  case $1 in
    up)    (( MCC_BACK++ )) ;;
    down)  (( MCC_BACK > 0 && MCC_BACK-- )) ;;
    pgup)  (( MCC_BACK += MCC_H - 12 )) ;;
    pgdn)  (( MCC_BACK -= MCC_H - 12, MCC_BACK < 0 && (MCC_BACK = 0) )) ;;
    home)  MCC_BACK=999999 ;;
    end|G) MCC_BACK=0 ;;
    f|F)   case $MCC_FILTER in all) MCC_FILTER=chat ;; chat) MCC_FILTER=warn ;; *) MCC_FILTER=all ;; esac; MCC_BACK=0 ;;
    /|enter|:)
      if [[ $MCC_MODE == ours ]] && (( MCC_PID )); then _mcc_input cmd "/"
      else _mcc_toast info "$LOTUS_L[mc_external_cmd]"; fi ;;
    t|T)
      if [[ $MCC_MODE == ours ]] && (( MCC_PID )); then _mcc_input cmd "/" "say "
      else _mcc_toast info "$LOTUS_L[mc_external_cmd]"; fi ;;
  esac
}

# Does a line belong to the filter?
_mcc_log_match() {
  case $MCC_FILTER in
    chat) [[ $1 == *\]:\ (\<*|\[Not\ Secure\]*|*\ joined\ the\ game|*\ left\ the\ game|*\ has\ made\ the\ advancement*)* || $1 == \[Lotus\]\ \>* ]] ;;
    warn) [[ $1 == *(WARN|ERROR|FATAL|Exception|Error:)* || $1 == [[:space:]]at\ * ]] ;;
    *) return 0 ;;
  esac
}

# A console line in color, cut to the width → REPLY
_mcc_log_color() {
  local l=$1
  local -i w=$2
  local r=$MCC_C[r] d=$MCC_C[dim]
  _mcc_cut "$l" $w; l=$REPLY
  if [[ $l == \[Lotus\]* ]]; then REPLY="$MCC_C[logo]$l$r"; return; fi
  local head= msg=$l col=
  if [[ $l == (#b)(\[[0-2][0-9]:[0-5][0-9]:[0-5][0-9][^\]]#\][^:]#:\ )(*) ]]; then head=$match[1] msg=$match[2]; fi
  case $head$msg in
    *(ERROR|FATAL)*|*Exception*|[[:space:]]at\ *) col=$MCC_C[red] ;;
    *WARN*) col=$MCC_C[key2] ;;
  esac
  case $msg in
    (#b)(\[Not\ Secure\]\ |)\<([^\>]##)\>(*)) msg="$d$match[1]$r$MCC_C[accent]<$match[2]>$r$match[3]" ;;
    *\ joined\ the\ game|*\ left\ the\ game|Done\ \(*) msg="$MCC_C[key]$msg$r" ;;
    *) [[ -n $col ]] && msg="$col$msg$r" ;;
  esac
  REPLY="$d$head$r$msg"
}

_mcc_page_log() {
  local -i W=$1 H=$2 i base=${#out}
  local r=$MCC_C[r] d=$MCC_C[dim] a=$'\e[1;'"${LOTUS_C[accent]}m"
  local -A fl=(all $LOTUS_L[mc_f_all] chat $LOTUS_L[mc_f_chat] warn $LOTUS_L[mc_f_warn])
  local -a lines
  if [[ $MCC_FILTER == all ]]; then lines=("${MCC_LOG[@]}")
  else
    local l
    for l in "${MCC_LOG[@]}"; do _mcc_log_match "$l" && lines+=("$l"); done
  fi
  local -i room=$(( H - 4 )) n=${#lines}
  (( MCC_BACK > n - room )) && MCC_BACK=$(( n - room > 0 ? n - room : 0 ))
  local follow="$MCC_C[key]● $LOTUS_L[mc_live]$r"
  (( MCC_BACK )) && follow="$d${LOTUS_L[mc_back]//\%d/$MCC_BACK}$r"
  local src=console.log
  [[ $MCC_MODE == external ]] && src=logs/latest.log
  _mcp_count $n
  out+=("  ${a}${(U)LOTUS_L[mc_console]}$r$d  $REPLY ${LOTUS_L[mc_lines]} · $src · ${LOTUS_L[mc_filter]}: ${fl[$MCC_FILTER]}$r   $follow")
  out+=("")
  local -i from=$(( n - MCC_BACK - room + 1 )) to=$(( n - MCC_BACK ))
  (( from < 1 )) && from=1
  if (( n == 0 )); then
    out+=("    $d$LOTUS_L[mc_log_empty]$r")
  fi
  for (( i = from; i <= to; i++ )); do
    _mcc_log_color "${lines[i]}" $(( W - 4 ))
    out+=("  $REPLY")
  done
  while (( ${#out} - base < H - 1 )); do out+=(""); done
  # the command line
  if [[ $MCC_IN == cmd ]]; then
    _mcc_cut "$MCC_INTEXT" $(( W - 10 ))
    out+=("  $MCC_C[accent]›$r $MCC_C[B]/$r$REPLY$MCC_C[key]▏$r")
  elif [[ $MCC_MODE == ours ]] && (( MCC_PID )); then
    out+=("  $d› $LOTUS_L[mc_cmd_hint]$r")
  else
    out+=("  $d› $LOTUS_L[mc_cmd_off]$r")
  fi
}

# ── The frame around the pages ───────────────────────────────

_mcc_draw() {
  local -i W=$MCC_W H=$MCC_H i
  local -a out=()
  local r=$MCC_C[r] d=$MCC_C[dim] a=$MCC_C[accent] B=$MCC_C[B]
  if (( W < 60 || H < 18 )); then
    local buf=$'\e[?2026h\e[H\e[2J'"  $LOTUS_L[mc_too_small]"$'\e[?2026l'
    print -rn -- $buf
    return
  fi
  # head: lotus / Minecraft · name, the state on the right
  _mcc_state_text; local st=$REPLY
  _mcc_vw "$st"; local -i stw=$REPLY
  local left="    $a◇$r ${B}lotus$r$d / $r${B}Minecraft$r$d  ·  $r$MCC_NAME"
  _mcc_vw "$left"
  out+=("")
  out+=("$left${(l:W - REPLY - stw - 3:)}$st")
  out+=("")
  # tabs, the open one like the selected slot of the hotbar
  local -a tabs=("$LOTUS_L[mc_tab_stats]" "$LOTUS_L[mc_tab_settings]" "$LOTUS_L[mc_tab_log]")
  local t="    "
  for (( i = 1; i <= 3; i++ )); do
    if (( i == MCC_PAGE )); then t+="$MCC_C[tab] $i  ${tabs[i]} $r "
    else t+="$d $i  ${tabs[i]} $r "; fi
  done
  out+=("$t")
  out+=("")
  local -i body=$(( H - 7 ))
  local -i start=${#out}
  case $MCC_PAGE in
    1) _mcc_page_stats $W $body ;;
    2) _mcc_page_settings $W $body ;;
    3) _mcc_page_log $W $body ;;
  esac
  # never more than the window has
  (( ${#out} > start + body )) && out[start+body+1,-1]=()
  while (( ${#out} < H - 2 )); do out+=(""); done
  # the bottom: a message, a question, an input – and the keys
  local msg= keys=
  if [[ -n $MCC_IN && $MCC_IN != (cmd|search) ]]; then
    _mcc_cut "$MCC_INTEXT" $(( W - ${#MCC_INLABEL} - 10 ))
    msg="  $MCC_C[accent]›$r $MCC_INLABEL  $B$REPLY$r$MCC_C[key]▏$r"
    keys="⏎ $LOTUS_L[mc_k_ok]   esc $LOTUS_L[mc_k_cancel]"
  elif [[ -n $MCC_ASK ]]; then
    _mcc_ask_text; msg="  $MCC_C[key2]?$r $REPLY"
    keys=$reply[1]
  else
    if [[ -n $MCC_TOAST ]]; then
      case $MCC_TOASTK in
        ok)  msg="  $MCC_C[key]✓$r $MCC_TOAST" ;;
        err) msg="  $MCC_C[red]✗$r $MCC_TOAST" ;;
        *)   msg="  $a›$r $MCC_TOAST" ;;
      esac
    fi
    case $MCC_PAGE in
      1) keys=$LOTUS_L[mc_k_stats] ;;
      2) [[ $MCC_SUB == plugins ]] && keys=$LOTUS_L[mc_k_plugins] || keys=$LOTUS_L[mc_k_settings] ;;
      3) if [[ $MCC_IN == cmd ]]; then keys=$LOTUS_L[mc_k_cmd]; else keys=$LOTUS_L[mc_k_log]; fi ;;
    esac
    [[ $MCC_IN == search ]] && keys=$LOTUS_L[mc_k_search]
    [[ $MCC_PROBLEM == eula ]] && keys="e $LOTUS_L[mc_k_eula]   $keys"
    [[ $MCC_STATE == (stopped|crashed) && $MCC_PAGE != 2 ]] && keys=${keys//s $LOTUS_L[mc_k_stop]/s $LOTUS_L[mc_k_start]}
  fi
  _mcc_vw "$msg"; (( REPLY > W - 2 )) && { local plain=${msg//$'\e'\[[0-9;?]#[A-Za-z]/}; _mcc_cut "$plain" $(( W - 2 )); msg=$REPLY }
  out[H-1]=$msg
  _mcc_cut "$keys" $(( W - 6 ))
  out[H]="    $d$REPLY$r"
  # whatever is still too wide is cut, so nothing wraps and moves the window
  for (( i = 1; i <= H; i++ )); do
    _mcc_vw "${out[i]}"
    (( REPLY > W )) && { _mcc_clip "${out[i]}" $W; out[i]=$REPLY }
  done
  local buf=$'\e[?2026h\e[H'
  for (( i = 1; i < H; i++ )); do buf+="${out[i]}$r"$'\e[K\n'; done
  buf+="${out[H]}$r"$'\e[K\e[J\e[?2026l'
  print -rn -- $buf
}

# The question being asked → REPLY, its keys → reply[1]
_mcc_ask_text() {
  case $MCC_ASK in
    quit)     REPLY=$LOTUS_L[mc_q_quit]; reply=("⏎ $LOTUS_L[mc_k_leave]   s $LOTUS_L[mc_k_stopleave]   esc $LOTUS_L[mc_k_stay]") ;;
    stop)     REPLY="${LOTUS_L[mc_q_stop]//\%d/${#MCC_PORDER}}"; reply=("y $LOTUS_L[mc_k_yes]   n $LOTUS_L[mc_k_no]") ;;
    restart)  REPLY="${LOTUS_L[mc_q_restart]//\%d/${#MCC_PORDER}}"; reply=("y $LOTUS_L[mc_k_yes]   n $LOTUS_L[mc_k_no]") ;;
    eula)     REPLY=$LOTUS_L[mc_q_eula]; reply=("y $LOTUS_L[mc_k_accept]   n $LOTUS_L[mc_k_no]   https://aka.ms/MinecraftEULA") ;;
    icondel)  REPLY=$LOTUS_L[mc_q_icondel]; reply=("y $LOTUS_L[mc_k_yes]   n $LOTUS_L[mc_k_no]") ;;
    remove:*) REPLY="${LOTUS_L[mc_q_remove]//\%s/${MCC_ASK#remove:}}"; reply=("y $LOTUS_L[mc_k_yes]   n $LOTUS_L[mc_k_no]") ;;
    player:*) REPLY="${MCC_ASK#player:}:  1 op · 2 deop · 3 kick · 4 ban · 5 creative · 6 survival · 7 whitelist"
              reply=("1–7 $LOTUS_L[mc_k_choose]   esc $LOTUS_L[mc_k_cancel]") ;;
  esac
}
