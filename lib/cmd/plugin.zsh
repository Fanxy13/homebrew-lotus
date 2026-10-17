# Plugins – your own things in Lotus: commands, tools for the AI and lines on the start screen.
#   lotus plugin                          the plugins you have, and what they may do
#   lotus plugin new <name> [full]        a new plugin to start from, in ~/.config/lotus/plugins/<name>
#   lotus plugin install <folder|git URL> install one – it shows what it brings and may do, and asks
#   lotus plugin info|check <name>        what it brings and may do · check its plugin.conf
#   lotus plugin on|off <name>            turn it on or off · lotus plugin remove <name> deletes it (asks)
#   lotus plugin allow <name>             allow it again after its files changed (full access)
#   lotus plugin update <name>            a plugin installed from git: its newest version
#   lotus plugin help                     how to build one (PLUGINS.md has all of it)
# A plugin is a folder with a plugin.conf and its programs, in any language. It runs in one of two ways:
#   limited (the default)  in a macOS sandbox: it reads only its own folder, writes only its data folder
#                          (~/.local/share/lotus/plugins/<name>), has no internet unless "network = yes", no
#                          keychain, cannot control other apps and sees nothing of your files or Lotus' settings
#   full                   with your rights and Lotus' own functions (source $LOTUS_ROOT/lib/core.zsh) – you
#                          allow it when you install it, and again whenever its files change
# The list of plugins and what you allowed: ~/.config/lotus/plugins.tsv (name, on/off, access, fingerprint).

typeset -g LOTUS_PLUGINS=$LOTUS_CONF/plugins LOTUS_PLUGINS_TSV=$LOTUS_CONF/plugins.tsv
typeset -g LOTUS_PLUGIN_DATA=$LOTUS_DATA/plugins

lotus_cmd_plugin() {
  setopt localoptions extendedglob
  local cmd=$1; shift
  lotus_features
  if [[ $cmd == plugin-tool ]]; then lotus_plugin_tool "$@"; return; fi
  local sub=${1:-list}
  (( $# )) && shift
  case $sub in
    list|ls)          _plg_list ;;
    new|create)       _plg_new "$@" ;;
    install|add)      _plg_install "$@" ;;
    info|show)        _plg_info "$1" ;;
    check)            _plg_check_cmd "$1" ;;
    on|enable)        _plg_switch "$1" on ;;
    off|disable)      _plg_switch "$1" off ;;
    allow|trust)      _plg_allow "$1" ;;
    remove|rm|delete) _plg_remove "$1" ;;
    update)           _plg_update "$1" ;;
    help|-h|--help)   _plg_help ;;
    run)              local n=$1; (( $# )) && shift; _plg_run_command "$n" "" "$@" ;;
    *)                ui_error "Unknown: lotus plugin $sub" "" "lotus plugin help shows what it can do"; return 2 ;;
  esac
}

# ── plugin.conf ───────────────────────────────────────────────
#   name = todo                  key = value, one per line; lines starting with # are comments
#   command todo = todo.zsh      lotus todo … runs todo.zsh with the arguments
#   tool add = todo.zsh add      a tool for the AI; tool add.description = …, tool add.param text = text, required, …
#   startup = status.zsh         one line under the start screen (refreshed in the background)

# Reads <folder>/plugin.conf → PLG (name title version author description homepage access network startup
# startup.every), PLG_CMDS (word → program), PLG_TOOLS (names in order), PLG_TOOL (name.key → value),
# PLG_PARAMS (tool → parameter names in order), PLG_PARAM (tool.param → "type, required, description").
# Status 1 when there is no plugin.conf.
_plg_read() {
  local dir=$1 line key value
  typeset -gA PLG=() PLG_CMDS=() PLG_TOOL=() PLG_PARAM=() PLG_PARAMS=()
  typeset -ga PLG_TOOLS=()
  [[ -r $dir/plugin.conf ]] || return 1
  PLG[dir]=$dir PLG[access]=limited PLG[network]=no PLG[startup.every]=300
  for line in "${(@f)$(<$dir/plugin.conf)}"; do
    line=${line//$'\r'/}
    [[ $line == [[:space:]]#\#* || $line != *=* ]] && continue
    key=${${line%%=*}//[[:space:]]##/ }; key=${${key## }%% }
    value=${${line#*=}## #}; value=${value%% #}
    case $key in
      command\ *)
        PLG_CMDS[${key#command }]=$value ;;
      command)
        PLG_CMDS[__self]=$value ;;
      tool\ *.param\ *)
        local t=${${key#tool }%%.param *} p=${key##*.param }
        PLG_PARAM[$t.$p]=$value
        [[ " $PLG_PARAMS[$t] " == *" $p "* ]] || PLG_PARAMS[$t]=${PLG_PARAMS[$t]:+$PLG_PARAMS[$t] }$p ;;
      tool\ *.*)
        local t=${${key#tool }%%.*}
        PLG_TOOL[$t.${key#tool $t.}]=$value ;;
      tool\ *)
        local t=${key#tool }
        PLG_TOOL[$t.run]=$value
        (( ${PLG_TOOLS[(Ie)$t]} )) || PLG_TOOLS+=($t) ;;
      *)
        PLG[$key]=$value ;;
    esac
  done
  # "command = x" is the command with the plugin's own name
  if [[ -n $PLG_CMDS[__self] ]]; then PLG_CMDS[$PLG[name]]=$PLG_CMDS[__self]; unset 'PLG_CMDS[__self]'; fi
  return 0
}

# "type, required|optional, description" of a parameter → reply (type required description); the type may have
# commas of its own: int(1,999)
_plg_param_spec() {
  local v=${1## #} type rest
  if [[ $v == (int|enum)\(*\)* ]]; then
    type=${v%%\)*}\) rest=${v#*\)}
    rest=${rest## #}; rest=${rest#,}
  else
    type=${v%%,*} rest=${v#*,}
    [[ $v == *,* ]] || rest=
  fi
  rest=${rest## #}
  reply=("${type// }" "${${rest%%,*}// }" "${${rest#*,}## #}")
  [[ $rest == *,* ]] || reply[3]=
}

# Lotus' own commands – a plugin cannot take them over (the list of bin/lotus, LOTUS_MODULES)
_plg_builtin() {
  [[ $1 == (show|settings|config|version|-v|--version|plugin|plugins|plugin-tool|ai-tool) ]] && return 0
  if (( ! ${+LOTUS_MODULES} )); then
    local src=$(<$LOTUS_ROOT/bin/lotus)
    local -a w=(${=${${src#*typeset -A LOTUS_MODULES=\(}%%\)*}})
    typeset -gA LOTUS_MODULES=()
    local -i i
    for (( i = 1; i < $#w; i += 2 )); do LOTUS_MODULES[$w[i]]=$w[i+1]; done
  fi
  [[ -n ${LOTUS_MODULES[$1]-} ]]
}

# A program of the plugin: inside its folder, no way out of it → REPLY = the path ("" when it is not right)
_plg_program() {   # <dir> <program>
  local p=${2%% *}
  REPLY=
  [[ -n $p && $p != /* && $p != *..* && $p == [A-Za-z0-9._/-]## && -f $1/$p ]] || return 1
  REPLY=$1/$p
}

# Problems with the plugin in <dir> → reply (empty: it is fine). Needs _plg_read first.
_plg_problems() {
  local dir=$1 w t p
  local -a spec
  reply=()
  local -a probs=()
  [[ $PLG[name] == [a-z][a-z0-9-](#c1,30) ]] || probs+=("name must be 2–31 letters, digits or -, starting with a letter (it is \"$PLG[name]\")")
  [[ $PLG[name] == ${dir:t} || $dir == */.lotus-plugin-* ]] || probs+=("the folder must have the plugin's name: ${dir:t} ≠ $PLG[name]")
  [[ $PLG[access] == (limited|full) ]] || probs+=("access must be limited or full (it is \"$PLG[access]\")")
  [[ $PLG[network] == (yes|no) ]] || probs+=("network must be yes or no (it is \"$PLG[network]\")")
  [[ -n $PLG[description] ]] || probs+=("a description is missing (description = what it does)")
  (( ${#PLG_CMDS} + ${#PLG_TOOLS} )) || [[ -n $PLG[startup] ]] || probs+=("it brings nothing: give it a command, a tool or a startup line")
  for w in ${(k)PLG_CMDS}; do
    [[ $w == [a-z][a-z0-9-](#c1,30) ]] || { probs+=("command \"$w\": letters, digits and - only"); continue }
    _plg_builtin $w && probs+=("command \"$w\" is one of Lotus' own commands – choose another name")
    _plg_program $dir $PLG_CMDS[$w] || probs+=("command \"$w\": $PLG_CMDS[$w] is not a file in the plugin's folder")
  done
  for t in $PLG_TOOLS; do
    [[ $t == [a-z][a-z0-9_](#c1,30) ]] || { probs+=("tool \"$t\": letters, digits and _ only"); continue }
    _plg_program $dir $PLG_TOOL[$t.run] || probs+=("tool \"$t\": $PLG_TOOL[$t.run] is not a file in the plugin's folder")
    [[ -n $PLG_TOOL[$t.description] ]] || probs+=("tool \"$t\" has no description (tool $t.description = …) – the AI needs it to know when to use it")
    [[ ${PLG_TOOL[$t.level]:-act} == (read|act) ]] || probs+=("tool \"$t\": level must be read or act")
    for p in ${=PLG_PARAMS[$t]}; do
      [[ $p == [a-z][a-z0-9_](#c0,30) ]] || probs+=("tool \"$t\", parameter \"$p\": letters, digits and _ only")
      _plg_param_spec $PLG_PARAM[$t.$p]; spec=("${reply[@]}")
      [[ $spec[1] == (text|path|int\([0-9-]##,[0-9-]##\)|enum\([a-z0-9_.|-]##\)) ]] \
        || probs+=("tool \"$t\", parameter \"$p\": the type must be text, path, int(min,max) or enum(a|b|c) (it is \"$spec[1]\")")
      [[ $spec[2] == (required|optional) ]] || probs+=("tool \"$t\", parameter \"$p\": say required or optional")
    done
  done
  if [[ -n $PLG[startup] ]]; then
    _plg_program $dir $PLG[startup] || probs+=("startup: $PLG[startup] is not a file in the plugin's folder")
  fi
  reply=("${probs[@]}")
}

# ── What you allowed: plugins.tsv ─────────────────────────────

# The fingerprint of every file of the plugin (not its .git) → REPLY
_plg_fingerprint() {
  local dir=$1
  REPLY=$(cd $dir && find . -type f ! -path './.git/*' -print0 2>/dev/null | LC_ALL=C sort -z | xargs -0 shasum -a 256 2>/dev/null | shasum -a 256)
  REPLY=${REPLY%% *}
}

# The line of a plugin → reply (name state access fingerprint); status 1 when it is not in the list
_plg_entry() {
  local line
  reply=()
  [[ -r $LOTUS_PLUGINS_TSV ]] || return 1
  for line in "${(@f)$(<$LOTUS_PLUGINS_TSV)}"; do
    [[ $line == ${1}$'\t'* ]] && { reply=("${(@ps:\t:)line}"); return 0 }
  done
  return 1
}

_plg_save_entry() {   # <name> <on|off> <access> <fingerprint>
  local tmp=$LOTUS_PLUGINS_TSV.tmp line
  zf_mkdir -p ${LOTUS_PLUGINS_TSV:h}
  {
    [[ -r $LOTUS_PLUGINS_TSV ]] && for line in "${(@f)$(<$LOTUS_PLUGINS_TSV)}"; do
      [[ -n $line && $line != ${1}$'\t'* ]] && print -r -- $line
    done
    print -r -- "$1"$'\t'"$2"$'\t'"$3"$'\t'"$4"
  } >| $tmp && zf_mv -f $tmp $LOTUS_PLUGINS_TSV
}

_plg_drop_entry() {
  [[ -r $LOTUS_PLUGINS_TSV ]] || return 0
  local tmp=$LOTUS_PLUGINS_TSV.tmp line
  { for line in "${(@f)$(<$LOTUS_PLUGINS_TSV)}"; do [[ -n $line && $line != ${1}$'\t'* ]] && print -r -- $line; done } >| $tmp
  zf_mv -f $tmp $LOTUS_PLUGINS_TSV
}

# The installed plugins, by name → reply
_plg_names() {
  reply=(${LOTUS_PLUGINS}/*/plugin.conf(N:h:t))
}

# May the plugin run now? → status 0; else REPLY says why. Reads its plugin.conf (PLG …).
_plg_ready() {
  local name=$1 dir=$LOTUS_PLUGINS/$1
  REPLY=
  lotus_feature_on plugins || { REPLY="Plugins are turned off – turn them on with: lotus features plugins on"; return 1 }
  _plg_read $dir || { REPLY="There is no plugin \"$name\" – lotus plugin lists them"; return 1 }
  _plg_entry $name || { REPLY="The plugin \"$name\" is not installed yet – install it with: lotus plugin install $dir"; return 1 }
  local -a e=("${reply[@]}")
  [[ $e[2] == on ]] || { REPLY="The plugin \"$name\" is turned off – lotus plugin on $name"; return 1 }
  _plg_problems $dir
  (( ${#reply} )) && { REPLY="The plugin \"$name\" has a problem in its plugin.conf: $reply[1] – lotus plugin check $name"; return 1 }
  if [[ $PLG[access] == full ]]; then
    _plg_fingerprint $dir
    [[ $e[3] == full && $e[4] == $REPLY ]] || { REPLY="The plugin \"$name\" asks for full access and changed since you allowed it – allow it again with: lotus plugin allow $name"; return 1 }
  fi
  REPLY=
  return 0
}

# ── Running a program of a plugin ─────────────────────────────

# The sandbox of a limited plugin (sandbox-exec): its own folder to read, its data folder and the temporary
# folder to write, nothing of the home folder or other disks, no keychain, no Apple Events (no controlling
# other apps), no internet unless the plugin says network = yes.
_plg_profile() {   # <dir> <data> <network yes|no> → REPLY
  local q=$'"' tmp=${TMPDIR:-/tmp}
  REPLY="(version 1)
(allow default)
(allow file-write* (subpath $q${tmp:A}$q) (subpath \"/private/tmp\") (subpath \"/private/var/folders\"))
(deny file-read* (subpath $q${HOME:A}$q) (subpath \"/Volumes\"))
(deny file-write* (subpath $q${HOME:A}$q) (subpath \"/Volumes\"))
(allow file-read* (subpath $q${1:A}$q) (subpath $q${2:A}$q))
(allow file-write* (subpath $q${2:A}$q))
(deny process-exec (literal \"/usr/bin/security\") (literal \"/usr/bin/osascript\") (literal \"/usr/bin/sudo\") (literal \"/usr/bin/su\"))
(deny appleevent-send)
(deny mach-lookup (global-name \"com.apple.SecurityServer\") (global-name \"com.apple.securityd.xpc\"))"
  [[ $3 == yes ]] || REPLY+=$'\n(deny network*)'
  # a file the AI gave a tool (a path parameter – it asked the user already, like read_file): this one file to read
  local f
  for f in ${(f)LOTUS_PLUGIN_READ}; do
    [[ $f == /* && $f != *[\"\\]* ]] && REPLY+=$'\n'"(allow file-read* (literal $q${f:A}$q))"
  done
}

# Runs <program> of the plugin (read by _plg_read) with the arguments. Limited plugins in their sandbox and with
# a clean environment; full ones with Lotus' folders and functions. Never with the AI's API keys.
#   _plg_exec <program and its fixed arguments> [arguments…]   (LOTUS_PLUGIN_ENV: more NAME=value for it)
_plg_exec() {
  local spec=$1; shift
  local dir=$PLG[dir] name=$PLG[name]
  local -a fixed=(${(z)spec}); fixed=(${(Q)fixed})
  _plg_program $dir $fixed[1] || { print -u2 -r -- "lotus: $fixed[1] is not a file of the plugin $name"; return 2 }
  local prog=$REPLY data=$LOTUS_PLUGIN_DATA/$name
  zf_mkdir -p $data
  local -a run
  case $prog in
    *.zsh) run=(/bin/zsh -f $prog) ;;
    *.sh)  run=(/bin/sh $prog) ;;
    *.py)  run=(python3 $prog) ;;
    *.js|*.mjs) run=(node $prog) ;;
    *.rb)  run=(ruby $prog) ;;
    *)     [[ -x $prog ]] || chmod +x $prog 2>/dev/null; run=($prog) ;;
  esac
  local -a env=(
    PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin HOME=$HOME TMPDIR=${TMPDIR:-/tmp}
    LANG=${LANG:-en_US.UTF-8} LC_ALL=${LC_ALL:-en_US.UTF-8} TERM=${TERM:-xterm-256color} COLUMNS=${COLUMNS:-80}
    LOTUS_PLUGIN=$name LOTUS_PLUGIN_DIR=$dir LOTUS_PLUGIN_DATA=$data LOTUS_VERSION=$LOTUS_VERSION LOTUS_LANG=$LOTUS_LANG
    LOTUS_COLOR_KEY=$LOTUS_C[key] LOTUS_COLOR_ACCENT=$LOTUS_C[accent] LOTUS_COLOR_DIM=$LOTUS_C[dim] LOTUS_COLOR_LOGO=$LOTUS_C[logo]
    ${(f)LOTUS_PLUGIN_ENV}
  )
  if [[ $PLG[access] == full ]]; then
    env+=(LOTUS_ROOT=$LOTUS_ROOT LOTUS_CONF=$LOTUS_CONF LOTUS_CACHE=$LOTUS_CACHE LOTUS_DATA=$LOTUS_DATA LOTUS_STATE=$LOTUS_STATE
          LOTUS_NAME=$LOTUS_NAME USER=$USER SHELL=$SHELL)
    (cd $dir && exec env -i $env $run $fixed[2,-1] "$@")
  else
    _plg_profile $dir $data $PLG[network]
    (cd $dir && exec env -i $env /usr/bin/sandbox-exec -p $REPLY $run $fixed[2,-1] "$@")
  fi
}

# lotus <word> …: a command of a plugin → its status; 127 when no plugin has it
lotus_plugin_command() {
  setopt localoptions extendedglob
  local word=$1 n
  _plg_names
  for n in $reply; do
    _plg_read $LOTUS_PLUGINS/$n || continue
    [[ -n $PLG_CMDS[$word] ]] || continue
    _plg_run_command $n $word "${@:2}"
    return
  done
  return 127
}

_plg_run_command() {   # <plugin> <word|""> [arguments…]
  local name=$1 word=$2; shift 2
  if ! _plg_ready $name; then
    ui_error "$REPLY"
    return 1
  fi
  [[ -n $word ]] || word=${${(k)PLG_CMDS}[1]}
  [[ -n $PLG_CMDS[$word] ]] || { ui_error "The plugin \"$name\" has no command" "" "lotus plugin info $name shows what it brings"; return 1 }
  lotus_log INFO plugin "$name: lotus $word${*:+ (${#} arguments)}"
  _plg_exec $PLG_CMDS[$word] "$@"
}

# lotus plugin-tool <plugin> <tool> <values in the order of its parameters…> – what the AI calls (the AI asked the
# user already, as for every Lotus tool). The program gets the values as LOTUS_ARG_<NAME> and as arguments.
lotus_plugin_tool() {
  setopt localoptions extendedglob
  local name=$1 tool=$2
  (( $# >= 2 )) && shift 2
  _plg_ready $name || { print -r -- "$REPLY"; return 1 }
  [[ -n $PLG_TOOL[$tool.run] ]] || { print -r -- "The plugin \"$name\" has no tool \"$tool\"."; return 2 }
  local p v i=0 envlines= reads=
  for p in ${=PLG_PARAMS[$tool]}; do
    (( i++ ))
    v=${@[i]-}
    envlines+="LOTUS_ARG_${(U)p}=$v"$'\n'
    _plg_param_spec $PLG_PARAM[$tool.$p]
    [[ $reply[1] == path && -n $v ]] && reads+="$v"$'\n'
  done
  local LOTUS_PLUGIN_READ=$reads
  lotus_log INFO plugin "$name: tool $tool"
  local out rc LOTUS_PLUGIN_ENV=${envlines%$'\n'}
  out=$(_plg_with_timeout 60 _plg_exec $PLG_TOOL[$tool.run] "$@" 2>&1)
  rc=$?
  print -r -- ${out[1,20000]}
  (( rc == 124 )) && print -r -- "(The plugin took longer than 60 seconds and was stopped.)"
  return $rc
}

# Runs a command, stopped after <seconds> → its status, 124 when it took too long
_plg_with_timeout() {
  local secs=$1; shift
  "$@" &
  local pid=$! waited=0
  while kill -0 $pid 2>/dev/null; do
    (( waited >= secs * 10 )) && { kill -TERM $pid 2>/dev/null; sleep 0.2; kill -KILL $pid 2>/dev/null; wait $pid 2>/dev/null; return 124 }
    sleep 0.1
    (( waited++ ))
  done
  wait $pid
}

# ── For the AI: the plugins' tools in Lotus' list ─────────────

# The tools of the plugins that may run, as JSON objects for lib/cmd/aitools.zsh → reply. A tool of a plugin with
# full access is always level act (it asks first unless the user allowed Lotus tools or uses auto mode), whatever its
# plugin.conf says.
lotus_plugin_ai_tools() {
  setopt localoptions extendedglob
  local n t p tj pj av label desc level ptype preq pdesc extra v ej dj
  local -a out=() spec vals mm
  reply=()
  lotus_feature_on plugins || return 0
  _plg_names
  for n in $reply; do
    _plg_ready $n || continue
    for t in $PLG_TOOLS; do
      pj= av="\"plugin-tool\",\"$n\",\"$t\""
      for p in ${=PLG_PARAMS[$t]}; do
        _plg_param_spec $PLG_PARAM[$t.$p]
        ptype=$reply[1] preq=$reply[2] pdesc=$reply[3] extra=
        if [[ $ptype == enum\(*\) ]]; then
          vals=(${(s:|:)${${ptype#enum\(}%\)}}) ej=
          for v in $vals; do ej+=${ej:+,}\"$v\"; done
          extra=",\"enum\":[$ej]" ptype=enum
        elif [[ $ptype == int\(*\) ]]; then
          mm=(${(s:,:)${${ptype#int\(}%\)}})
          extra=",\"min\":$mm[1],\"max\":$mm[2]" ptype=int
        fi
        _ait_json "$pdesc"; dj=$REPLY
        pj+="${pj:+,}{\"name\":\"$p\",\"type\":\"$ptype\",\"required\":${${(M)preq:#required}:+true}${${preq:#required}:+false},\"description\":$dj$extra}"
        av+=",\"{$p}\""
      done
      level=${PLG_TOOL[$t.level]:-act}
      [[ $PLG[access] == full ]] && level=act
      _ait_json "${PLG_TOOL[$t.label]:-${PLG[title]:-$n}}"; label=$REPLY
      _ait_json "$PLG_TOOL[$t.description] (from the plugin ${PLG[title]:-$n})"; desc=$REPLY
      out+=("{\"name\":\"${n//-/_}_$t\",\"feature\":\"plugins\",\"level\":\"$level\",\"mode\":\"run\",\"label\":$label,\"argv\":[$av],\"params\":[$pj],\"description\":$desc,\"missing\":\"\"}")
    done
  done
  reply=("${out[@]}")
}

# ── Lines on the start screen ─────────────────────────────────

# One line per plugin with "startup = …": what it printed last time, right away – a new one is made in the
# background when the old one is older than "startup.every" seconds (300), so the start screen stays fast.
lotus_plugin_lines() {
  setopt localoptions extendedglob
  [[ -t 1 ]] && lotus_feature_on plugins || return 0
  [[ -d $LOTUS_PLUGINS ]] || return 0
  local n cache line
  local -i width=$(( ${COLUMNS:-80} < 40 ? 76 : ${COLUMNS:-80} - 4 ))     # a terminal that says it is 0 wide
  _plg_names
  local -a names=($reply)
  for n in $names; do
    _plg_read $LOTUS_PLUGINS/$n && [[ -n $PLG[startup] ]] || continue
    _plg_ready $n || continue
    cache=$LOTUS_PLUGIN_DATA/$n/.startup-line
    if [[ -s $cache ]]; then
      local -a got=("${(@f)$(<$cache)}")
      line=$got[1]
      line=${line//[[:cntrl:]]/}
      [[ -n $line ]] && print -r -- "  "$'\e['"$LOTUS_C[dim]m${${PLG[title]:-$n}[1,24]} · ${line[1,width]}"$'\e[0m'
    fi
    local -a st=()
    [[ -e $cache ]] && zstat -A st +mtime $cache 2>/dev/null
    if (( ! ${#st} || EPOCHSECONDS - st[1] > ${PLG[startup.every]:-300} )); then
      zf_mkdir -p ${cache:h}
      touch $cache     # one refresh at a time
      # not stopped when the terminal closes (the start screen of a window that is closed right away)
      ( trap '' HUP; _plg_with_timeout 10 _plg_exec $PLG[startup] >| $cache.new 2>/dev/null && zf_mv -f $cache.new $cache ) &!
    fi
  done
}

# ── lotus plugin: list, info, check ───────────────────────────

_plg_what() {   # what the plugin read by _plg_read brings → REPLY
  local -a parts=()
  local w
  for w in ${(ko)PLG_CMDS}; do parts+=("lotus $w"); done
  (( ${#PLG_TOOLS} )) && parts+=("${#PLG_TOOLS} AI tool$( (( ${#PLG_TOOLS} > 1 )) && print s)")
  [[ -n $PLG[startup] ]] && parts+=("a start screen line")
  REPLY=${(j: · :)parts}
}

_plg_access_text() {   # → REPLY
  if [[ $PLG[access] == full ]]; then REPLY="full access – your files, the internet, Lotus' settings"
  elif [[ $PLG[network] == yes ]]; then REPLY="limited – its own folder and the internet"
  else REPLY="limited – only its own folder"; fi
}

_plg_list() {
  ui_header Plugins "your own commands, AI tools and start screen lines"
  lotus_feature_on plugins || ui_dim "  Plugins are turned off – lotus features plugins on"
  _plg_names
  if (( ! ${#reply} )); then
    print
    ui_dim "  No plugins yet."
    print -r -- "  Make your own:   lotus plugin new <name>"
    print -r -- "  Install one:     lotus plugin install <folder or git URL>"
    print -r -- "  How it works:    lotus plugin help"
    return 0
  fi
  local n state d=$'\e['"$LOTUS_C[dim]m" k=$'\e['"$LOTUS_C[key]m" x=$'\e[0m'
  print
  for n in $reply; do
    _plg_read $LOTUS_PLUGINS/$n || continue
    _plg_entry $n && state=$reply[2] || state="not installed"
    _plg_what; local what=$REPLY
    _plg_access_text; local access=$REPLY
    _plg_ready $n || [[ $state != on ]] || state="needs you: $REPLY"
    print -r -- "  $k${(r:16:)n}$x ${PLG[title]:-$n} ${PLG[version]:+$d$PLG[version]$x}"
    print -r -- "  ${(r:16:)} $d$PLG[description]$x"
    print -r -- "  ${(r:16:)} $d${what:-nothing} · $access · $state$x"
  done
  print
  ui_dim "  lotus plugin info <name> · on|off <name> · remove <name> · new <name> · help"
}

_plg_info() {
  local name=$1
  [[ -n $name ]] || { ui_error "Which plugin?" "" "lotus plugin info <name>"; return 2 }
  _plg_read $LOTUS_PLUGINS/$name || { ui_error "There is no plugin \"$name\"" "" "lotus plugin lists them"; return 1 }
  _plg_summary
  local -a e; _plg_entry $name && e=("${reply[@]}")
  ui_kv State "${e[2]:-not installed}"
  ui_kv Folder "${LOTUS_PLUGINS/#$HOME/~}/$name"
  ui_kv Data "${LOTUS_PLUGIN_DATA/#$HOME/~}/$name"
  _plg_ready $name || ui_dim "  $REPLY"
  return 0
}

# What a plugin brings and may do – before it is installed, and in info
_plg_summary() {
  local t w p
  print
  print -r -- "  "$'\e[1m'"${PLG[title]:-$PLG[name]}"$'\e[0m'"  ${PLG[version]:+$PLG[version]}${PLG[author]:+ · by $PLG[author]}"
  ui_dim "  $PLG[description]"
  [[ -n $PLG[homepage] ]] && ui_dim "  $PLG[homepage]"
  print
  for w in ${(ko)PLG_CMDS}; do ui_kv Command "lotus $w"; done
  for t in $PLG_TOOLS; do
    ui_kv "AI tool" "$t – $PLG_TOOL[$t.description]${${(M)PLG_TOOL[$t.level]:#read}:+ (runs without asking)}"
  done
  [[ -n $PLG[startup] ]] && ui_kv Start "a line under the start screen"
  _plg_access_text
  if [[ $PLG[access] == full ]]; then
    ui_kv Access $'\e['"38;5;203m$REPLY"$'\e[0m'
    ui_dim "             It runs with your rights: it can read, change and delete your files, use the internet"
    ui_dim "             and change Lotus. Only allow it when you trust who made it."
  else
    ui_kv Access "$REPLY"
    ui_dim "             In a sandbox: no access to your files, the keychain or other apps."
  fi
}

_plg_check_cmd() {
  local name=$1 dir
  [[ -n $name ]] || { ui_error "Which plugin?" "" "lotus plugin check <name or folder>"; return 2 }
  dir=$LOTUS_PLUGINS/$name
  [[ -d $name && -r $name/plugin.conf ]] && dir=${name:A}
  _plg_read $dir || { ui_error "No plugin.conf in $dir"; return 1 }
  _plg_problems $dir
  if (( ${#reply} )); then
    ui_error "plugin.conf has ${#reply} problem$( (( ${#reply} > 1 )) && print s)" "$dir/plugin.conf"
    local r; for r in $reply; do print -r -- "    – $r"; done
    return 1
  fi
  _plg_what
  ui_success "plugin.conf is fine – ${REPLY:-it brings nothing}"
}

# ── New, install, allow, on/off, remove, update ───────────────

_plg_new() {
  local name=$1 access=limited
  [[ $2 == (full|--full) ]] && access=full
  [[ $name == [a-z][a-z0-9-](#c1,30) ]] || { ui_error "A plugin needs a name" "$name" "2–31 letters, digits or -, e.g.: lotus plugin new my-tool"; return 2 }
  _plg_builtin $name && { ui_error "\"$name\" is one of Lotus' own commands" "" "Choose another name"; return 2 }
  local dir=$LOTUS_PLUGINS/$name
  [[ -e $dir ]] && { ui_error "There is a plugin \"$name\" already" "${dir/#$HOME/~}"; return 1 }
  zf_mkdir -p $dir
  local tool=${name//-/_}
  print -r -- "# A Lotus plugin – everything about it: lotus plugin help, and PLUGINS.md in the Lotus repository.
# One setting per line: key = value. Lines starting with # are comments.

name        = $name
title       = ${(C)${name//-/ }}
version     = 0.1
author      = ${LOTUS_NAME:-you}
description = What it does, in one sentence

# limited: it runs in a sandbox and sees only its own folder (the safe default)
# full:    it runs with your rights and can use Lotus' own functions – you allow it when you install it
access      = $access
# limited plugins: may it use the internet? (yes / no)
network     = no

# A command: lotus $name … runs $name.zsh with the arguments
command $name = $name.zsh

# A tool for the AI in /ai and the web chat. It gets the values as LOTUS_ARG_<NAME> and prints its answer.
# level read runs right away, act asks first (in auto mode it runs).
tool hello             = tool.zsh
tool hello.label       = Hello
tool hello.level       = read
tool hello.description = Says hello to someone. Use it when the user asks you to greet a person.
tool hello.param who   = text, required, The name of the person

# A line under the start screen (made in the background, at most every 300 seconds)
startup = startup.zsh" >| $dir/plugin.conf
  print -r -- "# lotus $name … – the arguments are in \$@
# LOTUS_PLUGIN_DATA is this plugin's own folder for its files; LOTUS_COLOR_KEY and friends are the theme's colors
# (codes like 38;5;147 for \$'\\e[…m').
k=\$'\\e['\${LOTUS_COLOR_KEY:-38;5;150}m x=\$'\\e[0m'
print -r -- \"\${k}Hello from $name\${x} – you gave me: \${*:-nothing}\"" >| $dir/$name.zsh
  print -r -- "# The tool hello for the AI: the value of the parameter who is in \$LOTUS_ARG_WHO.
# Print the answer for the AI. Exit with 0 (done), 1 (failed), 2 (wrong arguments) or 3 (the user has to decide).
[[ -n \$LOTUS_ARG_WHO ]] || { print -r -- \"Whom should I greet?\"; exit 2 }
print -r -- \"Hello, \$LOTUS_ARG_WHO!\"" >| $dir/tool.zsh
  print -r -- "# One short line for the start screen
print -r -- \"$name is ready – \$(date +%H:%M)\"" >| $dir/startup.zsh
  print -r -- "# ${(C)${name//-/ }}

A plugin for [Lotus](https://github.com/Fanxy13/homebrew-lotus).

    lotus plugin install <this folder or its git URL>
    lotus $name" >| $dir/README.md
  _plg_fingerprint $dir
  _plg_save_entry $name on $access $REPLY
  lotus_log INFO plugin "New plugin $name ($access)"
  ui_success "Your plugin \"$name\" is ready to change" "${dir/#$HOME/~}"
  ui_kv Try "lotus $name"
  ui_kv Change "${dir/#$HOME/~}/plugin.conf – then: lotus plugin check $name"
  [[ $access == full ]] && ui_dim "  It has full access: after you change its files, allow it again with lotus plugin allow $name"
  return 0
}

_plg_install() {
  local src=$1
  [[ -n $src ]] || { ui_error "Install what?" "" "lotus plugin install <folder or git URL>"; return 2 }
  local tmp=$LOTUS_PLUGINS/.lotus-plugin-$$ from=
  rm -rf -- "$tmp"
  zf_mkdir -p $LOTUS_PLUGINS
  if [[ $src == (https://|git@)* ]]; then
    (( $+commands[git] )) || { ui_error "Installing from git needs git" "" "xcode-select --install"; return 1 }
    ui_dim "  Getting ${src} …"
    git clone -q --depth 1 -- "$src" $tmp 2>/dev/null || { rm -rf -- "$tmp"; ui_error "Could not get the plugin" "$src"; return 1 }
    from=git
  elif [[ -d $src ]]; then
    [[ ${src:A} == ${LOTUS_PLUGINS:A}/* ]] && { ui_error "It is in the plugins folder already" "" "lotus plugin allow ${src:A:t}"; return 1 }
    cp -R -- "${src:A}" $tmp || return 1
    from=folder
  else
    ui_error "Not a folder or a git URL" "$src"; return 2
  fi
  _plg_read $tmp || { rm -rf -- "$tmp"; ui_error "There is no plugin.conf" "$src" "A plugin is a folder with a plugin.conf – lotus plugin help"; return 1 }
  local name=$PLG[name]
  _plg_problems $tmp
  if (( ${#reply} )); then
    rm -rf -- "$tmp"
    ui_error "This plugin cannot be installed" "$src"
    local r; for r in $reply; do print -r -- "    – $r"; done
    return 1
  fi
  [[ $name == [a-z][a-z0-9-](#c1,30) ]] || { rm -rf -- "$tmp"; return 1 }
  local dest=$LOTUS_PLUGINS/$name
  _plg_summary
  print
  if [[ -e $dest ]]; then ui_dim "  This replaces the plugin \"$name\" you have."; fi
  local q="Install the plugin \"$name\"?"
  [[ $PLG[access] == full ]] && q="Install \"$name\" with full access to your Mac and Lotus?"
  if ! ui_confirm "$q" n; then
    rm -rf -- "$tmp"
    ui_dim "  Not installed."
    return 1
  fi
  rm -rf -- "$dest"
  zf_mv $tmp $dest
  [[ $from == git ]] && print -r -- $src >| $LOTUS_PLUGIN_DATA/.$name-source 2>/dev/null
  _plg_fingerprint $dest
  _plg_save_entry $name on $PLG[access] $REPLY
  lotus_log INFO plugin "Installed $name ($PLG[access], from $from)"
  _plg_read $dest; _plg_what
  ui_success "The plugin \"$name\" is installed" "$REPLY"
}

_plg_allow() {
  local name=$1
  [[ -n $name ]] || { ui_error "Which plugin?" "" "lotus plugin allow <name>"; return 2 }
  _plg_read $LOTUS_PLUGINS/$name || { ui_error "There is no plugin \"$name\""; return 1 }
  _plg_problems $LOTUS_PLUGINS/$name
  (( ${#reply} )) && { ui_error "Fix its plugin.conf first" "" "lotus plugin check $name"; return 1 }
  _plg_summary
  print
  if [[ $PLG[access] == full ]]; then
    ui_confirm "Allow \"$name\" full access to your Mac and Lotus?" n || { ui_dim "  Not allowed."; return 1 }
  fi
  local state=on
  _plg_entry $name && state=$reply[2]
  _plg_fingerprint $LOTUS_PLUGINS/$name
  _plg_save_entry $name $state $PLG[access] $REPLY
  lotus_log INFO plugin "Allowed $name ($PLG[access])"
  ui_success "\"$name\" may run ($PLG[access])"
}

_plg_switch() {   # <name> <on|off>
  local name=$1
  _plg_entry $name || { ui_error "There is no installed plugin \"$name\"" "" "lotus plugin lists them"; return 1 }
  local -a e=("${reply[@]}")
  _plg_save_entry $name $2 $e[3] $e[4]
  lotus_log INFO plugin "$name turned $2"
  ui_success "The plugin \"$name\" is $2"
}

_plg_remove() {
  local name=$1
  [[ $name == [a-z][a-z0-9-](#c1,30) && -d $LOTUS_PLUGINS/$name ]] || { ui_error "There is no plugin \"$name\""; return 1 }
  local data=$LOTUS_PLUGIN_DATA/$name
  ui_confirm "Remove the plugin \"$name\"${${:-}:+}$([[ -d $data ]] && print " and its data")?" n || return 0
  rm -rf -- "${LOTUS_PLUGINS:?}/${name:?}" "${LOTUS_PLUGIN_DATA:?}/${name:?}" "$LOTUS_PLUGIN_DATA/.$name-source"
  _plg_drop_entry $name
  lotus_log INFO plugin "Removed $name"
  ui_success "The plugin \"$name\" is removed"
}

_plg_update() {
  local name=$1 src
  [[ -r $LOTUS_PLUGIN_DATA/.$name-source ]] || { ui_error "\"$name\" was not installed from git" "" "Install the new version: lotus plugin install <folder>"; return 1 }
  src=$(<$LOTUS_PLUGIN_DATA/.$name-source)
  _plg_install $src
}

_plg_help() {
  ui_header Plugins "add your own things to Lotus"
  print -r -- "
  A plugin is a folder in ${LOTUS_PLUGINS/#$HOME/~} with a plugin.conf and its programs –
  zsh, sh, Python, Node, Ruby or any program. It can bring:

    commands         lotus <word> … runs one of its programs
    AI tools         /ai and the web chat can use them; the program gets LOTUS_ARG_<NAME> and prints the answer
    a startup line   one line under the start screen

  Access:
    limited          (the default) a sandbox: only its own folder, its data in ${LOTUS_PLUGIN_DATA/#$HOME/~}/<name>,
                     no internet unless network = yes, no keychain, no other apps
    full             your rights and Lotus' functions (source \$LOTUS_ROOT/lib/core.zsh) – you allow it, and again
                     whenever its files change

  Start:     lotus plugin new <name>        (lotus plugin new <name> full for full access)
  Check:     lotus plugin check <name>
  Share:     put the folder on GitHub – others install it with: lotus plugin install <git URL>
  Examples:  the plugins folder of the Lotus repository (todo, hello)
  Everything else: PLUGINS.md – https://github.com/Fanxy13/homebrew-lotus/blob/main/PLUGINS.md
"
}
