# lotus – cheatsheet, theme preview and suggestions for unknown commands

lotus_cmd_help() {
  local cmd=$1; shift
  case $cmd in
    themes)  lotus_themes_preview ;;
    suggest) lotus_cmd_suggest "$@" ;;
    help|-h|--help)
      # with a pet: it asks what you need (/help all shows every command)
      if [[ $1 != (all|--all|-a) ]] && (( LOTUS_PET_HELP )) && lotus_feature_on pets && [[ -s $LOTUS_CONF/pets.tsv && -t 1 ]] && ui_has_tty; then
        source $LOTUS_ROOT/lib/cmd/pets.zsh
        lotus_lang_group pets
        lotus_pet_help && return 0
      fi
      lotus_cheatsheet ;;
    *)       lotus_cheatsheet "$@" ;;
  esac
}

# data/commands.tsv → LOTUS_CMDS (one entry per line, tab separated)
lotus_registry() {
  (( ${+LOTUS_CMDS} )) && return
  typeset -ga LOTUS_CMDS=(${(f)"$(<$LOTUS_ROOT/data/commands.tsv)"})
  LOTUS_CMDS=(${LOTUS_CMDS:#\#*})
}

# Is the command of a registry line part of a feature that is turned on?
_lotus_cmd_on() { lotus_feature_on ${LOTUS_FEATURE_OF[${1%% *}]:-core} }

lotus_cheatsheet() {
  lotus_registry
  lotus_features
  local line cat last= d=$'\e['"$LOTUS_C[dim]m" r=$'\e[0m' k=$'\e['"$LOTUS_C[key]m" id
  local -a f off=()
  local -i wide=$(( ${COLUMNS:-100} >= 118 ))
  for id in $LOTUS_FEATURE_IDS; do lotus_feature_on $id || { lotus_feature_label $id; off+=($REPLY) }; done
  {
    ui_header Cheatsheet "every command, with an example"
    for line in $LOTUS_CMDS; do
      f=("${(@ps:\t:)line}")
      [[ $f[7] == 1 ]] && continue
      _lotus_cmd_on $f[3] || continue
      if [[ $f[1] != $last ]]; then
        [[ -n $last ]] && print
        ui_category $f[1]
        last=$f[1]
      fi
      if (( wide )); then
        print -r -- "    ${k}${(r:34:)f[4]}${r} ${(r:52:)f[5]} ${d}${f[6]}${r}"
      else
        print -r -- "    ${k}${f[4]}${r}"
        print -r -- "      ${f[5]}  ${d}${f[6]}${r}"
      fi
    done
    if (( ${#LOTUS_SHORTCUTS} )); then
      print; ui_category "Your shortcuts" ${#LOTUS_SHORTCUTS}
      local s
      for s in ${(ko)LOTUS_SHORTCUTS}; do
        print -r -- "    ${k}${(r:34:)${:-/$s}}${r} ${d}${${LOTUS_SHORTCUTS[$s]#*|}%%|*}${r}"
      done
    fi
    print
    (( ${#off} )) && { ui_dim "Turned off: ${(j:, :)off} – lotus features"; print }
    ui_dim "Typos are fine: Lotus suggests the closest command. Website: $LOTUS_P[website]"
    print
  } | if [[ -t 1 ]] && (( ${COLUMNS:-0} )); then less -RFX; else cat; fi
}

# Unknown command → clean error screen with the closest commands
#   lotus_cmd_suggest <typed word without slash> [args…]
lotus_cmd_suggest() {
  lotus_registry
  lotus_features
  local typed=${1#/}; shift
  local line name
  local -a f names targets
  local -A target_of
  for line in $LOTUS_CMDS; do
    f=("${(@ps:\t:)line}")
    [[ $f[7] == 1 ]] && continue
    _lotus_cmd_on $f[3] || continue
    if [[ $f[2] != - ]]; then name=$f[2]; else name=${f[4]%% *}; [[ $name == lotus || $name == /lotus ]] && name="/lotus ${${f[4]#* }%% *}"; fi
    [[ -n $target_of[$name] ]] && continue
    target_of[$name]=$f[3]
    names+=($name)
  done
  for name in ${(k)LOTUS_SHORTCUTS}; do target_of[/$name]="run $name"; names+=(/$name); done

  # compare the typed word with the command word (without "/" or "/lotus ")
  local -a words
  local -A name_of
  for name in $names; do
    words+=(${${name#/lotus }#/})
    name_of[${${name#/lotus }#/}]=$name
  done
  lotus_rank $typed 50 $words
  local -a hits=("${reply[@]}")
  local -i best_score=${LOTUS_SCORES[1]:-0}

  ui_error "Command not found" "/$typed"
  lotus_pet_react typo
  if (( ${#hits} )); then
    local best=$name_of[$hits[1]]
    print -r -- "  Did you mean:"
    local h
    for h in ${hits[1,3]}; do print -r -- "    "$'\e['"$LOTUS_C[key]m$name_of[$h]"$'\e[0m'; done
    print
    if ui_has_tty && ui_confirm "Run $best${*:+ $*} now?" ${${(M)best_score:#<60->}:+y}${${best_score:#<60->}:+n}; then
      print
      exec $LOTUS_ROOT/bin/lotus ${=target_of[$best]} "$@"
    fi
  else
    ui_dim "Type /lotus cheatsheet to see every command."
    print
  fi
  return 1
}

lotus_themes_preview() {
  source $LOTUS_ROOT/lib/cmd/setup.zsh
  local n theme_was=$LOTUS_THEME
  local -a names=($LOTUS_THEME_NAMES) labels=()
  ui_header Themes "${#names} themes"
  for n in $names; do
    _lotus_swatch $n
    labels+=("${(r:10:)LOTUS_THEME_LABELS[$n]} $REPLY${${(M)n:#$theme_was}:+  (current)}")
  done
  if ui_choose "Apply a theme" "${labels[@]}"; then
    LOTUS_THEME=$names[REPLY]
    lotus_save
    lotus_colors
    ui_success "Theme: $LOTUS_THEME_LABELS[$LOTUS_THEME]"
  fi
}
