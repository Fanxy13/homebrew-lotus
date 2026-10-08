# lotus – setup, update, doctor, uninstall

is_brew() { [[ $LOTUS_ROOT == */(Cellar|Caskroom)/lotus/* ]] }

lotus_cmd_system() {
  local cmd=$1; shift
  case $cmd in
    setup)            lotus_setup "$@" ;;
    update|upgrade)   lotus_update ;;
    doctor)           lotus_doctor "$@" ;;
    uninstall)        lotus_uninstall "$@" ;;
    unhook)           lotus_unhook ;;
  esac
}

# Wizard + the ~/.zshrc lines
#   --hook   only the ~/.zshrc lines (Homebrew install steps)
#   --first  wizard only when Lotus was never set up (install script, also on updates)
#   --tty    wizard even without a terminal on stdin
lotus_setup() {
  local wizard=0
  case $1 in
    --hook)  wizard=0 ;;
    --first) (( LOTUS_CONFIGURED )) || wizard=1 ;;
    --tty)   wizard=1 ;;
    *)       [[ -t 0 ]] && wizard=1 ;;
  esac
  if (( wizard )) && ui_has_tty; then
    source $LOTUS_ROOT/lib/cmd/setup.zsh
    lotus_cmd_setup_wizard || return 1
  fi
  [[ -e $LOTUS_CONF/settings.zsh ]] || lotus_save
  lotus_build force
  lotus_hook
}

# Adds the lotus block to ~/.zshrc. It finds lotus through the `lotus` command,
# so it keeps working after Homebrew upgrades – without starting a process.
lotus_hook() {
  local block="# >>> lotus >>>"$'\n'
  if [[ $LOTUS_ROOT == $HOME/.local/share/lotus && ${path[(I)$HOME/.local/bin]} == 0 ]]; then
    block+='export PATH="$HOME/.local/bin:$PATH"'$'\n'
  fi
  block+='(( $+commands[lotus] )) && source ${${commands[lotus]:A}:h:h}/lib/init.zsh'$'\n'"# <<< lotus <<<"

  local rc=
  [[ -r $LOTUS_RC ]] && rc=$(<$LOTUS_RC)
  if [[ $rc == *'# >>> lotus >>>'*'# <<< lotus <<<'* ]]; then
    rc=${rc/'# >>> lotus >>>'*'# <<< lotus <<<'/$block}
  else
    rc+=${rc:+$'\n\n'}$block
  fi
  print -r -- $rc >| $LOTUS_RC
  ui_success "$LOTUS_L[added_to] $LOTUS_RC"
  ui_info $LOTUS_L[open_new]
}

# Removes the lotus lines from ~/.zshrc (also used by `brew uninstall lotus`)
lotus_unhook() {
  [[ -r $LOTUS_RC ]] || return 0
  local rc=$(<$LOTUS_RC)
  [[ $rc == *'# >>> lotus >>>'* ]] || return 0
  rc=${rc/$'\n'#'# >>> lotus >>>'*'# <<< lotus <<<'/}
  print -r -- $rc >| $LOTUS_RC
  ui_success "$LOTUS_L[removed_from] $LOTUS_RC"
}

# Removes everything lotus created. With --yes no question is asked.
lotus_uninstall() {
  if [[ $1 != --yes ]]; then
    ui_header Uninstall
    ui_text "Removes Lotus, its settings, pets, shortcuts, AI memory and keys, the log, the Remove BG models, cache and the lines in ~/.zshrc."
    ui_blank
    ui_confirm "Uninstall Lotus completely?" n || { ui_info $LOTUS_L[cancelled]; return 1 }
  fi

  lotus_unhook
  [[ -e $LOTUS_CONF/hushlogin-by-lotus ]] && rm -f $HOME/.hushlogin
  rm -rf $LOTUS_CONF $LOTUS_CACHE $LOTUS_STATE
  # Remove BG: its Python environment and the downloaded models
  rm -rf $LOTUS_DATA/runtime $LOTUS_DATA/models $LOTUS_DATA/llm
  [[ $LOTUS_DATA != $LOTUS_ROOT ]] && rmdir $LOTUS_DATA 2>/dev/null
  local item
  for item in lotus-ai lotus-ai-claude; do security delete-generic-password -s $item >/dev/null 2>&1; done

  if is_brew; then
    ui_step $LOTUS_L[removed_brew]
    local kind=--formula
    [[ $LOTUS_ROOT == */Caskroom/* ]] && kind=--cask
    HOMEBREW_NO_AUTOREMOVE=1 brew uninstall --quiet $kind lotus
    brew untap --quiet fanxy13/lotus 2>/dev/null
    ui_info $LOTUS_L[ff_kept]
  elif [[ $LOTUS_ROOT == $HOME/.local/share/lotus ]]; then
    rm -f $HOME/.local/bin/lotus
    rm -rf $LOTUS_ROOT
  else
    ui_info "$LOTUS_L[own_install] $LOTUS_ROOT"
  fi
  ui_success $LOTUS_L[removed]
}

# Latest published version → REPLY (empty when offline)
lotus_latest_version() {
  local src
  if is_brew; then
    local tap=$(brew --repository fanxy13/lotus 2>/dev/null)
    [[ -d $tap/.git ]] && git -C $tap pull --ff-only --quiet 2>/dev/null
    [[ -r $tap/Casks/lotus.rb ]] && src=$(<$tap/Casks/lotus.rb)
    REPLY=${${(M)${(f)src}:#*version \"*}//[^0-9.]/}
  else
    src=$(curl -fsSL -m 8 "https://raw.githubusercontent.com/$LOTUS_P[repo]/main/lib/core.zsh" 2>/dev/null)
    REPLY=${${(M)${(f)src}:#typeset -g LOTUS_VERSION=*}#*=}
  fi
}

lotus_update() {
  ui_header Update
  ui_step "Checking for a new version …"
  lotus_latest_version
  local latest=$REPLY
  if [[ -z $latest ]]; then
    ui_error "Could not reach GitHub" "Check your internet connection and try again."
    return 1
  fi
  ui_card Lotus "INSTALLED|$LOTUS_VERSION" "AVAILABLE|$latest" "SOURCE|${${(M)LOTUS_ROOT:#*/Caskroom/*}:+Homebrew}${${LOTUS_ROOT:#*/Caskroom/*}:+install script}"
  ui_blank
  if [[ $latest == $LOTUS_VERSION ]]; then
    ui_success "$LOTUS_L[up_to_date] ($LOTUS_VERSION)"
    return
  fi
  ui_step "Updating to $latest – your settings stay as they are"
  ui_blank
  if is_brew; then
    export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1 HOMEBREW_NO_ENV_HINTS=1
    # reinstall picks up the new version; unlike `brew upgrade` it does not try
    # to rebuild unrelated packages (e.g. pkgconf after a macOS update)
    if brew reinstall --cask fanxy13/lotus/lotus; then
      ui_success "Lotus $latest is installed. Open a new terminal window."
    else
      ui_error "The update failed" "Homebrew reported the error above." "Try again later or run: brew reinstall --cask fanxy13/lotus/lotus"
      return 1
    fi
  else
    curl -fsSL "https://raw.githubusercontent.com/$LOTUS_P[repo]/main/install.sh" | zsh
  fi
}

lotus_doctor() {
  local ok=$'\e[1;'"$LOTUS_C[key]m✓"$'\e[0m' bad=$'\e[1;38;5;203m✗\e[0m' opt=$'\e['"$LOTUS_C[dim]m·"$'\e[0m'
  local -a v
  _row() { print -r -- "  $1 ${(r:17:)2} $3" }
  ui_header Doctor "lotus $LOTUS_VERSION"
  _row $ok macOS "$(sw_vers -productVersion 2>/dev/null) on ${$(uname -m)/arm64/Apple silicon}"
  _row $ok zsh "$ZSH_VERSION"
  _row $ok Lotus "$LOTUS_ROOT"
  if [[ -x $LOTUS_FF ]]; then _row $ok fastfetch "$($LOTUS_FF --version 2>/dev/null) ($LOTUS_FF)"
  else _row $bad fastfetch $LOTUS_L[doc_missing]; fi
  _row $ok $LOTUS_L[doc_colors] "$LOTUS_MODE (${TERM_PROGRAM:-$LOTUS_L[unknown_term]})"
  _row $ok Settings "$LOTUS_CONF/settings.zsh"
  if [[ -r $LOTUS_RC && $(<$LOTUS_RC) == *'# >>> lotus >>>'* ]]; then _row $ok .zshrc $LOTUS_L[doc_rc_ok]
  else _row $bad .zshrc $LOTUS_L[doc_rc_no]; fi
  lotus_build
  lotus_np_query
  _row $ok $LOTUS_L[doc_music] "${${(f)"$(<$LOTUS_CACHE/np-$LOTUS_MODE-$LOTUS_LANG)"}[1]}"$'\e[0m'
  ui_blank
  ui_dim "Optional, for single commands"
  (( $+commands[brew] )) && _row $ok Homebrew "$(brew --prefix)  (/brew, /install)" || _row $opt Homebrew "not installed – /brew and /install need it"
  (( $+commands[jq] )) && _row $ok jq "$commands[jq]" || _row $opt jq "not found – plutil is used instead"
  if (( $+commands[yt-dlp] && $+commands[ffmpeg] )); then
    source $LOTUS_ROOT/lib/cmd/convert.zsh
    lotus_ytdlp_info
    if (( ${REPLY:-0} > LOTUS_YTDLP_OLD )); then
      _row $'\e[1;'"$LOTUS_C[key2]m!"$'\e[0m' yt-dlp "$reply[1] – $REPLY days old, /convert offers an update"
    else
      _row $ok yt-dlp "$reply[1] with ffmpeg  (/convert)"
    fi
  else
    _row $opt yt-dlp "yt-dlp and ffmpeg are needed for /convert"
  fi
  (( $+commands[ideviceinfo] )) && _row $ok libimobiledevice "(/ios devices)" || _row $opt libimobiledevice "optional: shows the iOS version of connected devices"
  /usr/libexec/java_home >/dev/null 2>&1 && _row $ok Java "$(/usr/libexec/java_home 2>/dev/null)  (/minecraft)" || _row $opt Java "not installed – /minecraft can set it up"
  xcrun --find swiftc >/dev/null 2>&1 && _row $ok Swift "for the AI terminal (/ai)" || _row $opt Swift "Command Line Tools are needed for the AI terminal: xcode-select --install"
  { [[ -n $ANTHROPIC_API_KEY ]] || security find-generic-password -s lotus-ai-claude >/dev/null 2>&1 } && _row $ok Claude "API key in the Keychain  (/ai)" || _row $opt Claude "optional AI provider: lotus ai login"
  (( $+commands[ollama] )) && _row $ok Ollama "$commands[ollama]  (/ai)" || _row $opt Ollama "optional AI provider for /ai"
  ui_blank
  # Remove BG: when the feature is on, or on request (lotus doctor --bg)
  if lotus_feature_on bg || [[ $1 == (--bg|--all) ]]; then
    ui_dim "Remove BG"
    source $LOTUS_ROOT/lib/cmd/bg.zsh
    bg_doctor_rows
    ui_blank
  fi
  # Pets: how many, how they think
  if lotus_feature_on pets; then
    ui_dim "Pets"
    source $LOTUS_ROOT/lib/cmd/pets.zsh
    lotus_lang_group pets
    _pet_load; _pet_species
    local -i i
    if (( ${#PET_N} )); then
      for (( i = 1; i <= ${#PET_N}; i++ )); do _pet_status $i; _row $ok $PET_N[i] "$PET_K[i] · $REPLY"; done
    else
      _row $opt Pets "none adopted yet – /pets"
    fi
    _row $ok Kinds "${(j:, :)PET_KINDS}  (data/pets, ~/.config/lotus/pets)"
    case ${LOTUS_PET_BRAIN:-apple} in
      off) _row $opt Thinking "off – pets answer with short phrases" ;;
      *)   if _pet_brain >/dev/null 2>&1; then _row $ok Thinking "${${(M)PET_BRAIN:#apple}:+Apple Intelligence on this Mac}${${(M)PET_BRAIN:#ai}:+the AI of /ai}"
           else _row $opt Thinking "${LOTUS_L[pt_noai_hint]}"; fi ;;
    esac
    ui_blank
  fi
  ui_dim "Diagnostics"
  local -a lst
  local size=0
  zstat -A lst +size $LOTUS_LOG 2>/dev/null && size=$(( lst[1] / 1024 ))
  ui_path $LOTUS_LOG 60
  _row $ok Log "$REPLY ($size KB, level: $LOTUS_LOG_LEVEL)"
  lotus_features
  local -a off=()
  local id
  for id in $LOTUS_FEATURE_IDS; do lotus_feature_on $id || off+=($id); done
  _row $ok Features "$(( ${#LOTUS_FEATURE_IDS} - ${#off} )) of ${#LOTUS_FEATURE_IDS} on${off:+ (off: ${(j:, :)off})}"
  ui_blank
  lotus_log DEBUG doctor "Doctor run"
}
