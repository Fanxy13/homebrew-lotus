# lotus – first-time setup wizard (also: lotus setup)

lotus_cmd_setup() { lotus_cmd_setup_wizard }

# Colored sample of a theme for the theme list
_lotus_swatch() {
  local -a rgb=(${=LOTUS_THEMES[$1]}) out=()
  local i
  for i in 1 2 3 4; do lotus_sgr $rgb[i]; out+=($'\e['"${REPLY}m"'■■'); done
  REPLY="${(j: :)out}"$'\e[0m'
}

lotus_cmd_setup_wizard() {
  local -i step=0 total=4
  _step() { (( step++ )); ui_blank; print -r -- "  "$'\e['"$LOTUS_C[dim]m$step/$total"$'\e[0m'"  "$'\e[1m'"$1"$'\e[0m' }

  print -n $'\e[H\e[2J'
  ui_header Setup "takes about 20 seconds"
  ui_text "Welcome to Lotus. A few questions and your terminal is ready."
  ui_dim  "Everything can be changed later with /settings."

  _step "What should Lotus call you?"
  ui_input "Name" $LOTUS_NAME || return 1
  [[ -n ${REPLY// } ]] && LOTUS_NAME=${REPLY## #}

  _step "Pick a theme"
  local -a names=($LOTUS_THEME_NAMES) labels=()
  local n
  for n in $names; do _lotus_swatch $n; labels+=("${(r:10:)LOTUS_THEME_LABELS[$n]} $REPLY"); done
  if ui_choose "" "${labels[@]}"; then
    LOTUS_THEME=$names[REPLY]
    lotus_colors
  fi

  _step "Show Lotus automatically when Terminal opens?"
  ui_dim "You can always open it yourself by typing: lotus"
  if ui_confirm "Auto-start Lotus" y; then LOTUS_STARTUP=1; else LOTUS_STARTUP=0; fi

  _step "Interface language"
  local -a langs=(en de fr es)
  if ui_choose "" English Deutsch Français Español; then
    LOTUS_LANG=$langs[REPLY]
    lotus_lang
  fi

  ui_blank
  ui_dim "Optional: your city for /weather (Enter to skip)"
  ui_input "City" $LOTUS_WEATHER_LOCATION && LOTUS_WEATHER_LOCATION=$REPLY

  LOTUS_CONFIGURED=1 LOTUS_CONFIG_VERSION=2
  lotus_save
  lotus_build force
  ui_blank
  ui_success "All set, $LOTUS_NAME."
  ui_dim "Type /lotus cheatsheet to see everything Lotus can do."
  ui_blank
}
