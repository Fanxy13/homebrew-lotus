# lotus – what other shells ask zsh (the engine) for. `lotus bash-init` prints the bash code that lib/init.bash evaluates:
# the settings that matter in the shell, the /commands (what init.zsh makes aliases of), the pets' names.
# Nothing here runs anything; it only prints text for bash to read, every value quoted.

lotus_cmd_shell() {
  local cmd=$1; shift
  case $cmd in
    bash-init) lotus_bash_init ;;
  esac
}

# Quoting that bash reads the same: '…' with every ' written as '\''
_lsh_q() { REPLY="'${1//\'/\'\\\'\'}'" }

lotus_bash_init() {
  setopt localoptions extendedglob
  local line trig sub conf w pet
  local -a f
  local -A slash=()
  typeset -g REPLY

  # /weather, /skip … from data/commands.tsv (what init.zsh turns into aliases)
  for line in "${(@f)$(<$LOTUS_ROOT/data/commands.tsv)}"; do
    [[ $line == \#* ]] && continue
    f=("${(@ps:\t:)line}")
    trig=$f[2] sub=$f[3]
    [[ $trig == /* ]] || continue
    [[ $trig == /lotus ]] && sub=
    slash[$trig]=$sub
  done
  # your own shortcuts
  for trig in ${(k)LOTUS_SHORTCUTS}; do
    [[ ${LOTUS_SHORTCUTS[$trig]##*|} == on && -z ${slash[/$trig]} ]] || continue
    slash[/$trig]="run $trig"
  done
  # the commands of plugins: /word runs lotus word
  if lotus_feature_on plugins; then
    for conf in $LOTUS_CONF/plugins/*/plugin.conf(N); do
      for line in "${(@M)${(@f)$(<$conf)}:#[[:space:]]#command[[:space:]]#*=*}"; do
        w=${${${line%%=*}##[[:space:]]#command}//[[:space:]]/}
        [[ -n $w ]] || w=${conf:h:t}
        [[ $w == [a-z][a-z0-9-]## && -z ${slash[/$w]} ]] || continue
        slash[/$w]=$w
      done
    done
  fi

  # pets answer to their names
  local pets=
  if lotus_feature_on pets && [[ -r $LOTUS_CONF/pets.tsv ]]; then
    for line in "${(@f)$(<$LOTUS_CONF/pets.tsv)}"; do
      [[ $line == \#* || -z $line ]] && continue
      pets+=" ${(L)line%%$'\t'*}"
    done
    pets+=" "
  fi

  # the web chat starts with the first terminal – only when that is turned on and it does not run yet
  local -i boot=0
  if (( LOTUS_AI_SERVER_BOOT )) && lotus_feature_on ai; then
    boot=1
    if [[ -r $LOTUS_STATE/ai-server ]]; then
      local -a v=(${=$(<$LOTUS_STATE/ai-server)})
      [[ $v[1] == <-> ]] && kill -0 $v[1] 2>/dev/null && boot=0
    fi
  fi

  # the prompt in the theme's color: an SGR sequence, or nothing
  local accent=
  (( LOTUS_PROMPT )) && accent=$LOTUS_C[accent]

  print -r -- "__LOTUS_CONFIGURED=$LOTUS_CONFIGURED"
  print -r -- "__LOTUS_STARTUP=$LOTUS_STARTUP"
  _lsh_q "$accent"; print -r -- "__LOTUS_ACCENT=$REPLY"
  print -r -- "__LOTUS_AI_BOOT=$boot"
  print -r -- "__LOTUS_WEB=$(lotus_feature_on web && print 1 || print 0)"
  print -r -- "__LOTUS_APPS=$(lotus_feature_on apps && print 1 || print 0)"
  _lsh_q "$pets"; print -r -- "__LOTUS_PETS=$REPLY"
  print -rn -- "declare -gA __LOTUS_SLASH=("
  for trig in ${(ok)slash}; do
    [[ $trig == /[[:alnum:]_-]## ]] || continue
    _lsh_q "${slash[$trig]}"
    print -rn -- "[$trig]=$REPLY "
  done
  print -r -- ")"
}
