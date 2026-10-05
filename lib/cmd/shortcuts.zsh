# lotus – your own commands: lotus shortcut add yt https://youtube.com  →  /yt
# Stored in settings.zsh as LOTUS_SHORTCUTS[name]="type|target|on/off".
# Types: url (with optional {q} for search words), app, path (folder or file), lotus (a Lotus command).
# Arbitrary shell commands are deliberately not supported.

source $LOTUS_ROOT/lib/cmd/web.zsh

lotus_cmd_shortcuts() {
  local cmd=$1; shift
  case $cmd in
    run)       lotus_shortcut_run "$@" ;;
    shortcuts) lotus_shortcuts_manage ;;
    shortcut)
      local sub=$1; (( $# )) && shift
      case $sub in
        add)              lotus_shortcut_add "$@" ;;
        edit)             lotus_shortcut_add --edit "$@" ;;
        rm|remove|delete) lotus_shortcut_rm "$1" ;;
        on|enable)        lotus_shortcut_toggle "$1" on ;;
        off|disable)      lotus_shortcut_toggle "$1" off ;;
        list|'')          lotus_shortcuts_list ;;
        *) ui_error "Unknown shortcut action" "$sub" "Use: add, edit, rm, on, off, list"; return 1 ;;
      esac ;;
  esac
}

lotus_registry_triggers() {
  local -a lines=(${(f)"$(<$LOTUS_ROOT/data/commands.tsv)"})
  reply=(${${(M)${lines#*$'\t'}:#/*}%%$'\t'*})
}

# What a target is → REPLY=type, LOTUS_SC_TARGET=normalized target
lotus_shortcut_detect() {
  local t=$1
  typeset -g LOTUS_SC_TARGET=$t
  if lotus_as_url "${t//\{q\}/x}"; then
    [[ $t == (#i)https#://* ]] && LOTUS_SC_TARGET=$t || LOTUS_SC_TARGET="https://$t"
    REPLY=url; return
  fi
  local p=${t/#\~/$HOME}
  if [[ -e $p ]]; then REPLY=path; LOTUS_SC_TARGET=${p:A}; return; fi
  if [[ $t == /* ]]; then
    lotus_registry_triggers
    if (( ${reply[(Ie)${t%% *}]} )); then REPLY=lotus; return; fi
  fi
  source $LOTUS_ROOT/lib/cmd/app.zsh
  lotus_installed_apps
  local app
  for app in ${(k)LOTUS_APPS}; do
    [[ ${(L)app} == ${(L)t} ]] && { REPLY=app; LOTUS_SC_TARGET=$app; return }
  done
  REPLY=
  return 1
}

lotus_shortcut_add() {
  local edit=0
  [[ $1 == --edit ]] && { edit=1; shift }
  local name=${(L)${1#/}} target="${(j: :)@[2,-1]}"
  if [[ -z $name ]]; then
    ui_header Shortcuts "new shortcut"
    ui_input "Name (you will type /name)" || return 1; name=${(L)${REPLY#/}}
  fi
  if [[ $name != [a-z0-9][a-z0-9_-](#c0,23) ]]; then
    ui_error "Invalid name" "$name" "Use 1-24 lowercase letters, numbers, - or _"
    return 1
  fi
  lotus_registry_triggers
  if (( ${reply[(Ie)/$name]} )); then
    ui_error "/$name is a Lotus command" "" "Pick another name."
    return 1
  fi
  if (( edit )) && [[ -z $LOTUS_SHORTCUTS[$name] ]]; then
    ui_error "No shortcut called /$name" "" "Add it with: lotus shortcut add $name <target>"; return 1
  fi
  if (( ! edit )) && [[ -n $LOTUS_SHORTCUTS[$name] ]] && ! ui_confirm "/$name exists. Replace it?" n; then return 0; fi
  if [[ -z $target ]]; then
    ui_dim "A link (https://… – {q} is replaced by search words), an app, a folder or a Lotus command like /weather Zurich"
    ui_input "Target" || return 1; target=$REPLY
  fi
  if ! lotus_shortcut_detect "$target"; then
    ui_error "Lotus does not know what to open" "$target" \
      "Use a link, an installed app's exact name, an existing folder or file, or a Lotus command." \
      "Shell commands are not allowed in shortcuts."
    return 1
  fi
  local type=$REPLY
  LOTUS_SHORTCUTS[$name]="$type|$LOTUS_SC_TARGET|on"
  lotus_save
  ui_success "/$name → $LOTUS_SC_TARGET  ($type)"
  ui_dim "Works in new terminal windows right away, in this one after: lotus"
}

lotus_shortcut_rm() {
  local name=${(L)${1#/}}
  [[ -z $LOTUS_SHORTCUTS[$name] ]] && { ui_error "No shortcut called /$name"; return 1 }
  ui_confirm "Delete /$name?" n || return 0
  unset "LOTUS_SHORTCUTS[$name]"
  lotus_save
  ui_success "/$name deleted"
}

lotus_shortcut_toggle() {
  local name=${(L)${1#/}} state=$2
  [[ -z $LOTUS_SHORTCUTS[$name] ]] && { ui_error "No shortcut called /$name"; return 1 }
  LOTUS_SHORTCUTS[$name]="${LOTUS_SHORTCUTS[$name]%|*}|$state"
  lotus_save
  ui_success "/$name is $state"
}

lotus_shortcuts_list() {
  ui_header Shortcuts "${#LOTUS_SHORTCUTS} saved"
  if (( ! ${#LOTUS_SHORTCUTS} )); then
    ui_dim "None yet. Example: lotus shortcut add yt https://youtube.com"
    ui_blank; return 0
  fi
  local n
  local -a f
  for n in ${(ko)LOTUS_SHORTCUTS}; do
    f=("${(@s:|:)LOTUS_SHORTCUTS[$n]}")
    print -r -- "  "$'\e['"${${(M)f[3]:#on}:+$LOTUS_C[key]}${${f[3]:#on}:+$LOTUS_C[dim]}m${(r:14:)${:-/$n}}"$'\e[0m'" ${(r:6:)f[1]} ${f[2]}${${f[3]:#on}:+  (off)}"
  done
  ui_blank
}

lotus_shortcuts_manage() {
  while :; do
    print -n $'\e[H\e[2J'
    lotus_shortcuts_list
    local -a names=(${(ko)LOTUS_SHORTCUTS})
    ui_choose "Manage" "Add a shortcut" ${names/#//} "Done" || return 0
    (( REPLY == 1 )) && { lotus_shortcut_add; ui_dim "Press a key"; ui_key; continue }
    (( REPLY == ${#names} + 2 )) && return 0
    local name=$names[REPLY-1] state=${LOTUS_SHORTCUTS[$names[REPLY-1]]##*|}
    ui_choose "/$name" "Run" "Edit target" "${${(M)state:#on}:+Disable}${${state:#on}:+Enable}" "Delete" "Back" || continue
    case $REPLY in
      1) lotus_shortcut_run $name; return ;;
      2) lotus_shortcut_add --edit $name ;;
      3) lotus_shortcut_toggle $name ${${(M)state:#on}:+off}${${state:#on}:+on} ;;
      4) lotus_shortcut_rm $name ;;
      *) continue ;;
    esac
    ui_dim "Press a key"; ui_key
  done
}

lotus_shortcut_run() {
  local name=${(L)${1#/}}; shift
  local entry=$LOTUS_SHORTCUTS[$name]
  if [[ -z $entry ]]; then
    source $LOTUS_ROOT/lib/cmd/help.zsh
    lotus_cmd_suggest $name "$@"; return 1
  fi
  local -a f=("${(@s:|:)entry}")
  [[ $f[3] == off ]] && { ui_warn "/$name is turned off – turn it on with: lotus shortcut on $name"; return 1 }
  case $f[1] in
    url)
      local url=$f[2]
      if [[ $url == *\{q\}* ]]; then lotus_urlencode "$*"; url=${url//\{q\}/$REPLY}; fi
      lotus_open_url $url "/$name" ;;
    app)   open -a "$f[2]" 2>/dev/null && ui_info "Opening $f[2]" || ui_error "Could not open $f[2]" ;;
    path)  [[ -e $f[2] ]] && { open "$f[2]"; ui_info "Opening ${f[2]/#$HOME/~}" } || ui_error "Not found" "$f[2]" ;;
    lotus) local -a words=(${=f[2]})
           local trig=${words[1]} line
           for line in "${(@f)$(<$LOTUS_ROOT/data/commands.tsv)}"; do
             [[ ${${line#*$'\t'}%%$'\t'*} == $trig ]] || continue
             local sub=${${${line#*$'\t'}#*$'\t'}%%$'\t'*}
             exec $LOTUS_ROOT/bin/lotus ${=sub} ${words[2,-1]} "$@"
           done
           ui_error "Unknown Lotus command in /$name" "$f[2]" ;;
  esac
}
