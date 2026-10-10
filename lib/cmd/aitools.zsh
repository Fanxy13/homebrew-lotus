# Lotus tools for the AI (data/ai-tools.tsv): the list the AI gets, and the handlers it calls.
#   lotus ai-tool <name> [arguments…]   runs one tool without questions (the AI asked the user already)
# A handler prints plain text for the AI and ends with:
#   0 done · 1 failed · 2 the arguments are wrong · 3 the user has to decide (e.g. which of several apps)
# The AI program checks the arguments too; the handlers check them again – they never run a shell string.

lotus_cmd_aitools() {
  shift   # "ai-tool"
  local name=$1
  (( $# )) && shift
  lotus_features
  local row
  lotus_ai_tool_row $name || { print -r -- "There is no Lotus tool called \"$name\"."; return 2 }
  row=$REPLY
  local feature=${${(ps:\t:)row}[2]}
  if ! lotus_feature_on $feature; then
    lotus_feature_label $feature
    print -r -- "The feature \"$REPLY\" is turned off. The user can turn it on with: lotus features $feature on"
    return 1
  fi
  (( ${+functions[_ait_$name]} )) || { print -r -- "The tool \"$name\" has no handler."; return 2 }
  lotus_log INFO ai "Lotus tool $name ${(j: :)${(q-)@}}"
  _ait_$name "$@"
}

# The line of a tool in data/ai-tools.tsv → REPLY
lotus_ai_tool_row() {
  local line
  for line in "${(@f)$(<$LOTUS_ROOT/data/ai-tools.tsv)}"; do
    [[ $line == \#* || -z $line ]] && continue
    [[ ${line%%$'\t'*} == $1 ]] && { REPLY=$line; return 0 }
  done
  return 1
}

# ── The list for the AI ──────────────────────────────────────

_ait_json() {   # <text> → REPLY, a JSON string
  local s=$1
  s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\n'/\\n}; s=${s//$'\t'/\\t}; s=${s//[[:cntrl:]]/}
  REPLY="\"$s\""
}

# Writes the tools of the features that are on as JSON → REPLY (the file). Tools whose program is
# missing are listed with "missing" – the AI then explains what to do instead of failing silently.
lotus_ai_toolkit() {
  setopt localoptions extendedglob
  lotus_features
  local out=$LOTUS_CACHE/ai/tools.json line p a v id
  local missing pj pname ptype preq pdesc extra ej dj desc label mj
  local -a f parts tools off vals mm argv aj plist
  zf_mkdir -p ${out:h}
  for line in "${(@f)$(<$LOTUS_ROOT/data/ai-tools.tsv)}"; do
    [[ $line == \#* || -z $line ]] && continue
    f=("${(@ps:\t:)line}")
    lotus_feature_on $f[2] || continue
    missing=
    case $f[2] in
      homebrew) (( $+commands[brew] )) || [[ -x /opt/homebrew/bin/brew || -x /usr/local/bin/brew ]] || missing="Homebrew is not installed. The user can install it from https://brew.sh, then Lotus can install apps." ;;
      weather)  (( $+commands[jq] )) || missing="This needs jq on this macOS version: brew install jq" ;;
    esac
    pj=
    if [[ $f[7] != - ]]; then
      # parameters are separated by ";" – a ";" inside a description does not start a new one
      plist=()
      for p in "${(@s:;:)f[7]}"; do
        if [[ ${p## #} == [a-z_]##:(text|int\(*\)|enum\(*\)|path):* || ! ${#plist} ]]; then plist+=("${p## #}")
        else plist[-1]+=";$p"; fi
      done
      for p in $plist; do
        parts=("${(@s.:.)p}")
        pname=$parts[1] ptype=$parts[2] preq=$parts[3] pdesc=${(j.:.)parts[4,-1]} extra=
        if [[ $ptype == enum\(*\) ]]; then
          case $ptype in
            'enum(@themes)')   vals=($LOTUS_THEME_NAMES) ;;
            'enum(@features)') vals=(${LOTUS_FEATURE_IDS:#core}) ;;
            *)                 vals=(${(s:|:)${${ptype#enum\(}%\)}}) ;;
          esac
          ej=
          for v in $vals; do _ait_json $v; ej+=${ej:+,}$REPLY; done
          extra=",\"enum\":[$ej]" ptype=enum
        elif [[ $ptype == int\(*\) ]]; then
          mm=(${(s:,:)${${ptype#int\(}%\)}})
          extra=",\"min\":$mm[1],\"max\":$mm[2]" ptype=int
        fi
        _ait_json $pdesc; dj=$REPLY
        pj+="${pj:+,}{\"name\":\"$pname\",\"type\":\"$ptype\",\"required\":${${(M)preq:#1}:+true}${${preq:#1}:+false},\"description\":$dj$extra}"
      done
    fi
    argv=(${=f[6]}) aj=()
    for a in $argv; do _ait_json $a; aj+=($REPLY); done
    _ait_json $f[8]; desc=$REPLY
    _ait_json $f[5]; label=$REPLY
    _ait_json $missing; mj=$REPLY
    tools+=("{\"name\":\"$f[1]\",\"feature\":\"$f[2]\",\"level\":\"$f[3]\",\"mode\":\"$f[4]\",\"label\":$label,\"argv\":[${(j:,:)aj}],\"params\":[$pj],\"description\":$desc,\"missing\":$mj}")
  done
  for id in ${LOTUS_FEATURE_IDS:#core}; do
    lotus_feature_on $id && continue
    lotus_feature_label $id
    _ait_json "$REPLY (lotus features $id on)"; off+=($REPLY)
  done
  print -r -- "{\"tools\":[${(j:,:)tools}],\"off\":[${(j:,:)off}]}" >| $out
  REPLY=$out
}

# ── Handlers ─────────────────────────────────────────────────

_ait_text_ok() {   # a short, printable argument
  [[ -n ${1// } && ${#1} -le 120 && $1 != *[[:cntrl:]]* ]]
}

_ait_lotus_status() {
  lotus_features
  local id on= offl= theme
  for id in ${LOTUS_FEATURE_IDS:#core}; do
    lotus_feature_label $id
    if lotus_feature_on $id; then on+="${on:+, }$REPLY"; else offl+="${offl:+, }$REPLY"; fi
  done
  theme=${LOTUS_THEME_LABELS[$LOTUS_THEME]:-$LOTUS_THEME}
  print -r -- "Lotus $LOTUS_VERSION · theme $theme · language $LOTUS_LANG"
  print -r -- "Features on: ${on:-none}"
  print -r -- "Features off: ${offl:-none}"
  if lotus_feature_on caffeine; then
    source $LOTUS_ROOT/lib/cmd/caffeine.zsh
    lotus_caffeine_status
  fi
  [[ -s $LOTUS_CONF/pets.tsv ]] && lotus_feature_on pets && print -r -- "Pets: ${(j:, :)${(f)$(cut -f1 $LOTUS_CONF/pets.tsv)}}"
  return 0
}

_ait_open_app() {
  local q=$1
  _ait_text_ok "$q" || { print -r -- "Which app? Give its name."; return 2 }
  source $LOTUS_ROOT/lib/cmd/app.zsh
  lotus_installed_apps
  lotus_rank "$q" 55 ${(k)LOTUS_APPS}
  local -a found=("${reply[@]}") scores=("${LOTUS_SCORES[@]}")
  if (( ! ${#found} )); then
    print -r -- "No installed app matches \"$q\". If it is not installed, find_app and install_app can help."
    return 1
  fi
  local -i top=${scores[1]} second=${scores[2]:-0}
  if (( top == 100 || (top >= 85 && top - second >= 8) || (${#found} == 1 && top >= 60) )); then
    if open -a "$LOTUS_APPS[$found[1]]" 2>/dev/null; then
      print -r -- "Opened $found[1]."
      return 0
    fi
    print -r -- "macOS could not open $found[1] ($LOTUS_APPS[$found[1]])."
    return 1
  fi
  print -r -- "Several installed apps could be meant: ${(j:, :)found[1,5]}. Ask the user which one, then call open_app with its exact name."
  return 3
}

_ait_find_app() {
  local q=$1
  _ait_text_ok "$q" || { print -r -- "What should I look for?"; return 2 }
  source $LOTUS_ROOT/lib/cmd/install.zsh
  lotus_catalog
  local -a f hits
  local name line
  lotus_rank "$q" 50 $LOTUS_CAT_NAMES
  hits=("${reply[@]}")
  # also by what the apps are for ("browser", "notes")
  if (( ${#hits} < 3 )); then
    for name in $LOTUS_CAT_NAMES; do
      f=("${(@ps:\t:)LOTUS_CAT_ROW[$name]}")
      [[ "${(L)f[3]} ${(L)f[5]}" == *${(L)q}* ]] && (( ! ${hits[(Ie)$name]} )) && hits+=($name)
    done
  fi
  if (( ${#hits} )); then
    print -r -- "In Lotus' app catalog:"
    for name in ${hits[1,8]}; do
      f=("${(@ps:\t:)LOTUS_CAT_ROW[$name]}")
      local state="not installed"
      lotus_app_installed $f[4] $f[2] && state="installed"
      print -r -- "- $name (Homebrew cask $f[2], $state): $f[5]"
    done
    return 0
  fi
  lotus_need_brew >/dev/null 2>&1 || { print -r -- "Nothing in Lotus' catalog matches \"$q\", and Homebrew is not installed to search further."; return 1 }
  local -a casks=(${(f)"$(HOMEBREW_NO_AUTO_UPDATE=1 brew search --cask "$q" 2>/dev/null | grep -v '^==>' | head -8)"})
  if (( ${#casks} )); then
    print -r -- "Not in Lotus' catalog. Homebrew has these casks: ${(j:, :)casks}"
    return 0
  fi
  print -r -- "Nothing found for \"$q\" in Lotus' catalog or in Homebrew."
  return 1
}

_ait_install_app() {
  local q=$1 cask= name=
  _ait_text_ok "$q" || { print -r -- "Which app? Give its exact name."; return 2 }
  [[ $q == [A-Za-z0-9._@+-]## || $q == *[[:space:]]* ]] || { print -r -- "That is not an app name: $q"; return 2 }
  source $LOTUS_ROOT/lib/cmd/install.zsh
  lotus_need_brew >/dev/null 2>&1 || { print -r -- "Homebrew is not installed. The user can install it from https://brew.sh."; return 1 }
  export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1
  lotus_catalog
  local -a f
  # exactly a catalog name, or exactly a cask – nothing else is installed (the user approved this name)
  local n
  for n in $LOTUS_CAT_NAMES; do [[ ${(L)n} == ${(L)q} ]] && { name=$n; break }; done
  if [[ -n $name ]]; then
    f=("${(@ps:\t:)LOTUS_CAT_ROW[$name]}")
    cask=$f[2]
    if lotus_app_installed $f[4] $f[2]; then print -r -- "$name is already installed."; return 0; fi
  elif [[ $q == [a-z0-9._@+-]## ]] && brew info --cask "$q" >/dev/null 2>&1; then
    cask=$q name=$q
    brew list --cask "$q" >/dev/null 2>&1 && { print -r -- "$q is already installed."; return 0 }
  else
    print -r -- "\"$q\" is not an exact app name. Call find_app first and use the exact name it gives."
    return 3
  fi
  print -r -- "Installing $name (Homebrew cask $cask) …"
  local log=$LOTUS_CACHE/ai/install-$cask.log
  zf_mkdir -p ${log:h}
  if brew install --cask "$cask" >| $log 2>&1; then
    print -r -- "Installed $name."
    lotus_log INFO ai "Installed $cask for the AI"
    return 0
  fi
  print -r -- "Homebrew could not install $name. Its last lines:"
  tail -5 $log | sed 's/\x1b\[[0-9;]*m//g'
  return 1
}

_ait_weather() {
  local place=${1:-$LOTUS_WEATHER_LOCATION}
  [[ -n ${place// } ]] || { print -r -- "No city given, and the user has no default city. Ask which city."; return 3 }
  if [[ $place == *[[:cntrl:]\;\`\$\\]* || ${#place} -gt 60 ]]; then print -r -- "That does not look like a city name: $place"; return 2; fi
  source $LOTUS_ROOT/lib/cmd/weather.zsh
  # once, in this shell (it fills LOTUS_W); its messages go to a file for the AI
  local msg=$LOTUS_CACHE/ai/weather.msg
  zf_mkdir -p ${msg:h}
  if ! lotus_weather_fetch "$place" >| $msg 2>&1; then
    sed 's/\x1b\[[0-9;]*m//g' $msg | grep -v '^[[:space:]]*$' | head -3
    return 1
  fi
  local deg="°C" spd="km/h"
  [[ $LOTUS_WEATHER_UNITS == imperial ]] && deg="°F" spd="mph"
  lotus_weather_kind $LOTUS_W[code] $LOTUS_W[day]
  print -r -- "$LOTUS_W[name]${LOTUS_W[region]:+, $LOTUS_W[region]}, $LOTUS_W[country]: $LOTUS_W[temp] $deg (feels like $LOTUS_W[feels] $deg), $reply[2], wind $LOTUS_W[wind] $spd, humidity $LOTUS_W[hum] %${${(M)LOTUS_W[offline]:#1}:+ (offline – the last known weather)}"
  local d
  local -a r
  for d in "${LOTUS_WD[@]:1:3}"; do
    r=("${(@ps:\t:)d}")
    lotus_weather_kind $r[2] 1
    print -r -- "$r[1]: $reply[2], $r[4]–$r[3] $deg, rain $r[5] %"
  done
  return 0
}

_ait_music_now() {
  source $LOTUS_ROOT/lib/cmd/audio.zsh
  if ! lotus_np_state || [[ -z $LOTUS_NP[title] ]]; then
    print -r -- "Nothing is playing right now."
    return 0
  fi
  print -r -- "$LOTUS_NP[status]: $LOTUS_NP[title]${LOTUS_NP[artist]:+ – $LOTUS_NP[artist]}${LOTUS_NP[album]:+ ($LOTUS_NP[album])} in $LOTUS_NP[player]"
}

_ait_music_control() {
  local action=$1
  [[ $action == (play|pause|next|previous|louder|quieter) ]] || { print -r -- "Unknown action: $action"; return 2 }
  source $LOTUS_ROOT/lib/cmd/audio.zsh
  lotus_np_state
  case $action in
    louder)  lotus_audio_volume up ;;
    quieter) lotus_audio_volume down ;;
    *)       lotus_audio_transport $action ;;
  esac 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
  return ${pipestatus[1]}
}

_ait_set_theme() {
  local t=$1
  [[ -n $t && -n ${LOTUS_THEMES[$t]} ]] || { print -r -- "There is no theme \"$t\". Themes: ${(j:, :)LOTUS_THEME_NAMES}"; return 2 }
  LOTUS_THEME=$t
  lotus_save
  print -r -- "The theme is now ${LOTUS_THEME_LABELS[$t]:-$t}. The start screen and new /ai sessions use it."
}

_ait_keep_awake() {
  [[ $1 == <-> ]] || { print -r -- "Minutes must be a number from 0 to 1440."; return 2 }
  source $LOTUS_ROOT/lib/cmd/caffeine.zsh
  lotus_caffeine_on $1 2>&1 | sed 's/\x1b\[[0-9;]*m//g; s/^ *[✓✔] *//'
  return ${pipestatus[1]}
}

_ait_keep_awake_off() {
  source $LOTUS_ROOT/lib/cmd/caffeine.zsh
  lotus_caffeine_off 2>&1 | sed 's/\x1b\[[0-9;]*m//g; s/^ *[✓✔ℹ] *//'
  return ${pipestatus[1]}
}

_ait_set_feature() {
  local id=$1 state=$2
  lotus_features
  [[ -n ${LOTUS_FEATURE_ROW[$id]} && $id != core ]] || { print -r -- "There is no feature \"$id\". Features: ${(j:, :)${LOTUS_FEATURE_IDS:#core}}"; return 2 }
  [[ $state == (on|off) ]] || { print -r -- "The state must be on or off."; return 2 }
  lotus_feature_set $id $([[ $state == on ]] && print 1 || print 0)
  lotus_save
  lotus_feature_label $id
  print -r -- "$REPLY is now $state."
}

# Servers in ~/Minecraft (or LOTUS_MC_HOME), and which ones run (a java process working in their folder)
_ait_minecraft_servers() {
  local home=${LOTUS_MC_HOME:-~/Minecraft} dir
  local -a servers=($home/*/start.command(N:h))
  (( ${#servers} )) || { print -r -- "No Minecraft server is set up yet. The user can set one up with /minecraft."; return 0 }
  local running=$(lsof -a -d cwd -c java -Fn 2>/dev/null | sed -n 's/^n//p')
  for dir in $servers; do
    local state="stopped"
    [[ $'\n'$running$'\n' == *$'\n'$dir$'\n'* ]] && state="running"
    print -r -- "- ${dir:t} ($state)"
  done
}

_ait_minecraft_start() {
  local home=${LOTUS_MC_HOME:-~/Minecraft} name=$1
  [[ $name == [A-Za-z0-9._\ -]## && $name != *..* ]] || { print -r -- "That is not a server name: $name"; return 2 }
  local cmd=$home/$name/start.command
  [[ -x $cmd ]] || { print -r -- "There is no server \"$name\". minecraft_servers lists them."; return 2 }
  if open -a Terminal "$cmd" 2>/dev/null; then
    print -r -- "Started $name in a new Terminal window. It is running when the window says \"Done\"; type stop there to shut it down."
    return 0
  fi
  print -r -- "macOS could not open a Terminal window for $name."
  return 1
}
