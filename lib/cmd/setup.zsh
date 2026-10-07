# lotus – first-time setup wizard (lotus setup) and the features page (lotus features)
#   Welcome → You (name, theme, start) → Features → setup of the chosen features → Review
# Esc goes back one page. Nothing is saved before Finish.

lotus_cmd_setup() {
  case $1 in
    features) shift; lotus_features_page "$@" ;;
    *)        lotus_cmd_setup_wizard ;;
  esac
}

# Colored sample of a theme for the theme list
_lotus_swatch() {
  local -a rgb=(${=LOTUS_THEMES[$1]}) out=()
  local i
  for i in 1 2 3 4; do lotus_sgr $rgb[i]; out+=($'\e['"${REPLY}m"'■■'); done
  REPLY="${(j: :)out}"$'\e[0m'
}

# Page header: title, the five steps (done, current, coming), the question
_sw_page() {   # <step 1-5> <question> [explanation]
  local -a names=($LOTUS_L[sw_s1] $LOTUS_L[sw_s2] $LOTUS_L[sw_s3] $LOTUS_L[sw_s4] $LOTUS_L[sw_s5])
  local steps= i d=$'\e['"$LOTUS_C[dim]m"
  for i in {1..5}; do
    if (( i == $1 )); then steps+=$'\e[1;'"$LOTUS_C[accent]m${names[i]}"$_UI_R
    elif (( i < $1 )); then steps+=$'\e['"$LOTUS_C[key]m${names[i]}"$_UI_R
    else steps+="${d}${names[i]}"$_UI_R; fi
    (( i < 5 )) && steps+="${d}   ·   "$_UI_R
  done
  print -n $'\e[H\e[2J'
  ui_hero $LOTUS_L[sw_title]
  print -r -- "    $steps"
  print -r -- ""
  print -r -- ""
  print -r -- "    ${_UI_B}$2${_UI_R}"
  [[ -n $3 ]] && print -r -- "    ${d}$3${_UI_R}"
  print -r -- ""
}

_sw_lang() {
  _sw_page 1 $LOTUS_L[sw_welcome] $LOTUS_L[sw_welcome_sub]
  ui_section $LOTUS_L[lang]; ui_blank
  local -a langs=(en de fr es)
  ui_select ${langs[(i)$LOTUS_LANG]} English Deutsch Français Español || return 1
  LOTUS_LANG=$langs[REPLY]
  lotus_lang; lotus_lang_group setup; lotus_lang_group bg
}

_sw_name() {
  _sw_page 2 $LOTUS_L[sw_name_q] $LOTUS_L[sw_name_sub]
  ui_line $LOTUS_L[name] $LOTUS_NAME || return 1
  [[ -n ${REPLY// } ]] && LOTUS_NAME=${${REPLY## #}%% #}
  return 0
}

_sw_theme() {
  _sw_page 2 $LOTUS_L[sw_theme_q] $LOTUS_L[sw_theme_sub]
  local -a names=($LOTUS_THEME_NAMES) labels=()
  local n
  for n in $names; do _lotus_swatch $n; labels+=("${(r:12:)LOTUS_THEME_LABELS[$n]}$REPLY|"); done
  ui_select ${names[(i)$LOTUS_THEME]} "${labels[@]}" || return 1
  LOTUS_THEME=$names[REPLY]
  lotus_colors
}

_sw_start() {
  _sw_page 2 $LOTUS_L[sw_start_q]
  ui_select $(( LOTUS_STARTUP ? 1 : 2 )) "$LOTUS_L[sw_start_yes]|$LOTUS_L[sw_start_yes_d]" "$LOTUS_L[sw_start_no]|$LOTUS_L[sw_start_no_d]" || return 1
  (( REPLY == 1 )) && LOTUS_STARTUP=1 || LOTUS_STARTUP=0
}

_sw_features() {
  _sw_page 3 $LOTUS_L[sw_feat_q] $LOTUS_L[sw_feat_sub]
  _lotus_feature_toggles || return 1
}

# The feature checklist (wizard and lotus features): reads and sets LOTUS_FEATURES_OFF
_lotus_feature_toggles() {
  lotus_features
  local id
  local -a opts=() f
  typeset -ga LOTUS_TOGGLES=()
  for id in $LOTUS_FEATURE_IDS; do
    f=("${(@ps:\t:)LOTUS_FEATURE_ROW[$id]}")
    lotus_feature_label $id
    opts+=("$REPLY|${LOTUS_L[featd_$id]:-$f[4]}|${${(M)id:#core}:+locked}")
    lotus_feature_on $id && LOTUS_TOGGLES+=(1) || LOTUS_TOGGLES+=(0)
  done
  ui_toggles "${opts[@]}" || return 1
  local -i i
  for (( i = 1; i <= ${#LOTUS_FEATURE_IDS}; i++ )); do
    [[ $LOTUS_FEATURE_IDS[i] == core ]] && continue
    lotus_feature_on $LOTUS_FEATURE_IDS[i] && (( ! LOTUS_TOGGLES[i] )) && lotus_feature_set $LOTUS_FEATURE_IDS[i] 0
    ! lotus_feature_on $LOTUS_FEATURE_IDS[i] && (( LOTUS_TOGGLES[i] )) && lotus_feature_set $LOTUS_FEATURE_IDS[i] 1
  done
  return 0
}

_sw_weather() {
  _sw_page 4 $LOTUS_L[sw_weather_q] $LOTUS_L[sw_weather_sub]
  ui_line $LOTUS_L[sw_city] $LOTUS_WEATHER_LOCATION || return 1
  LOTUS_WEATHER_LOCATION=${${REPLY## #}%% #}
}

_sw_ai() {
  _sw_page 4 $LOTUS_L[sw_ai_q] $LOTUS_L[sw_ai_sub]
  ui_select $(( sw_claude ? 2 : 1 )) "$LOTUS_L[sw_ai_later]|$LOTUS_L[sw_ai_later_d]" "$LOTUS_L[sw_ai_claude]|$LOTUS_L[sw_ai_claude_d]" || return 1
  (( REPLY == 2 )) && sw_claude=1 || sw_claude=0
}

_sw_bgmodel() { _sw_page 4 $LOTUS_L[bg_q_model] $LOTUS_L[bg_q_model_sub]; lotus_bg_pick_model }
_sw_bgout()   { _sw_page 4 $LOTUS_L[bg_q_output] $LOTUS_L[bg_q_output_sub]; lotus_bg_pick_output }
_sw_bgwhen()  {
  (( LOTUS_BG_READY )) && return 0
  _sw_page 4 $LOTUS_L[bg_q_when] $LOTUS_L[bg_q_when_sub]
  lotus_bg_pick_when $sw_bg_now || return 1
  sw_bg_now=$REPLY
}

# Review: everything at a glance, then Back or Finish
_sw_review() {
  _sw_page 5 $LOTUS_L[sw_ready]
  local k=$'\e['"$LOTUS_C[key]m" d=$'\e['"$LOTUS_C[dim]m" id
  local -a on=() off=()
  for id in ${LOTUS_FEATURE_IDS:#core}; do
    lotus_feature_label $id
    lotus_feature_on $id && on+=("${k}✓${_UI_R} ${(r:24:)REPLY}") || off+=("${d}· ${(r:24:)REPLY}${_UI_R}")
  done
  local -i cols=$(( (${COLUMNS:-80} - 4) / 28 )) i
  (( cols < 1 )) && cols=1; (( cols > 3 )) && cols=3
  _sw_cols() { local -a l=("$@"); for (( i = 1; i <= ${#l}; i += cols )); do print -r -- "    ${(j:  :)l[i,i+cols-1]}"; done }
  ui_section $LOTUS_L[sw_enabled]; ui_blank
  if (( ${#on} )); then _sw_cols "${on[@]}"; else ui_dim "  $LOTUS_L[sw_none]"; fi
  ui_blank
  if (( ${#off} )); then ui_section $LOTUS_L[sw_disabled]; ui_blank; _sw_cols "${off[@]}"; ui_blank; fi
  _lotus_swatch $LOTUS_THEME
  ui_kv $LOTUS_L[name] $LOTUS_NAME
  ui_kv $LOTUS_L[theme] "${LOTUS_THEME_LABELS[$LOTUS_THEME]}  $REPLY"
  ui_kv $LOTUS_L[lang] ${${(M)LOTUS_LANG:#en}:+English}${${(M)LOTUS_LANG:#de}:+Deutsch}${${(M)LOTUS_LANG:#fr}:+Français}${${(M)LOTUS_LANG:#es}:+Español}
  ui_kv $LOTUS_L[sw_start] ${${LOTUS_STARTUP:#0}:+$LOTUS_L[sw_start_auto]}${${(M)LOTUS_STARTUP:#0}:+$LOTUS_L[sw_start_manual]}
  if lotus_feature_on bg; then
    lotus_bg_model_label $LOTUS_BG_MODEL
    ui_kv $LOTUS_L[head_bg] $REPLY
    ui_path "${LOTUS_BG_OUTPUT/#\~/$HOME}"; [[ $LOTUS_BG_OUTPUT == @source ]] && REPLY=$LOTUS_L[bg_out_source]
    ui_kv "" $REPLY
  fi
  ui_blank; ui_blank
  ui_buttons 2 $LOTUS_L[sw_back] $LOTUS_L[sw_finish] || return 1
  (( REPLY == 2 ))
}

lotus_cmd_setup_wizard() {
  lotus_lang_group setup
  if ! ui_has_tty; then return 1; fi
  source $LOTUS_ROOT/lib/cmd/bg.zsh
  lotus_lang_group bg
  lotus_features
  lotus_log INFO setup "Setup wizard started"
  local -i p=1 sw_claude=0 sw_bg_now=0
  local -a pages
  print -n $'\e[?1049h'
  trap 'print -n "\e[?25h\e[?1049l"' EXIT
  trap 'return 130' INT
  while :; do
    # The pages after "features" depend on what is turned on
    pages=(lang name theme start features)
    lotus_feature_on weather && pages+=(weather)
    lotus_feature_on ai && pages+=(ai)
    lotus_feature_on bg && pages+=(bgmodel bgout bgwhen)
    pages+=(review)
    if (( p > ${#pages} )); then break; fi
    if (( p < 1 )); then
      print -n $'\e[H\e[2J'; ui_blank; ui_blank
      if ui_confirm "$LOTUS_L[sw_quit_q]" n; then
        lotus_log INFO setup "Setup wizard cancelled"
        return 1
      fi
      p=1; continue
    fi
    if _sw_$pages[p]; then (( p++ )); else (( p-- )); fi
  done
  print -n $'\e[?25h\e[?1049l'
  trap - EXIT

  LOTUS_CONFIGURED=1 LOTUS_CONFIG_VERSION=3
  lotus_save
  lotus_build force
  lotus_log INFO setup "Setup finished (features off: ${LOTUS_FEATURES_OFF:-none})"
  ui_hero $LOTUS_L[sw_ready]
  ui_success "${LOTUS_L[sw_done]//\%s/$LOTUS_NAME}"
  ui_dim "  $LOTUS_L[sw_done_hint]"
  ui_blank
  if (( sw_claude )); then source $LOTUS_ROOT/lib/cmd/ai.zsh; lotus_ai_login; fi
  if (( sw_bg_now )) && lotus_feature_on bg; then lotus_bg_install || true; fi
  return 0
}

# lotus features                 the checklist
# lotus features <id> on|off     switch one feature (for scripts)
lotus_features_page() {
  lotus_lang_group setup
  lotus_features
  local id
  if [[ -n $1 ]]; then
    id=$1
    if [[ -z ${LOTUS_FEATURE_ROW[$id]} || $id == core ]]; then
      ui_error "$LOTUS_L[sw_feat_unknown]" "$id" "${(j:, :)${LOTUS_FEATURE_IDS:#core}}"; return 1
    fi
    case $2 in
      on|1|yes)  lotus_feature_set $id 1 ;;
      off|0|no)  lotus_feature_set $id 0 ;;
      *)         ui_error "$LOTUS_L[sw_feat_onoff]" "$2" "lotus features $id on   ·   lotus features $id off"; return 1 ;;
    esac
    lotus_save
    lotus_feature_label $id
    lotus_feature_on $id && ui_success "${LOTUS_L[feat_now_on]//\%s/$REPLY}" || ui_info "${LOTUS_L[feat_is_off]//\%s/$REPLY}"
    return 0
  fi
  if ! { [[ -t 1 ]] && ui_has_tty }; then
    for id in $LOTUS_FEATURE_IDS; do
      lotus_feature_label $id
      print -r -- "${(r:12:)id} ${(r:22:)REPLY} $(lotus_feature_on $id && print on || print off)"
    done
    return 0
  fi
  local before=$LOTUS_FEATURES_OFF
  ui_hero $LOTUS_L[sw_feat_title] $LOTUS_L[sw_feat_sub]
  _lotus_feature_toggles || { ui_info $LOTUS_L[cancelled]; return 0 }
  if [[ $LOTUS_FEATURES_OFF == $before ]]; then ui_info $LOTUS_L[sw_feat_same]; return 0; fi
  lotus_save
  ui_success $LOTUS_L[sw_feat_saved]
  if lotus_feature_on bg && (( ! LOTUS_BG_READY )) && [[ " $before " == *" bg "* ]]; then
    lotus_lang_group bg
    ui_dim "  $LOTUS_L[bg_on_hint]"
  fi
  ui_blank
}
