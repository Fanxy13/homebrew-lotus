# lotus – Homebrew search and installation (/brew)

lotus_cmd_brew() {
  shift   # "brew"
  lotus_need_brew || return 1
  export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1
  local sub=$1
  case $sub in
    search)  shift; lotus_brew_search "$@" ;;
    info)    shift; lotus_brew_card "$1" ;;
    install) shift; lotus_brew_install "$1" ;;
    '')      ui_error "What should Lotus look for?" "" "Example: /brew firefox   or   /brew install firefox"; return 1 ;;
    *)       lotus_brew_search "$@" ;;
  esac
}

# Homebrew missing → explain and offer the official installer
lotus_need_brew() {
  (( $+commands[brew] )) && return 0
  for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [[ -x $p ]] && { path=(${p:h} $path); return 0 }
  done
  ui_error "Homebrew is not installed" "Homebrew is the package manager Lotus uses to install apps."
  ui_choose "What now?" "Install Homebrew (official script from brew.sh)" "Show instructions" "Cancel" || return 1
  case $REPLY in
    1) ui_info "Running the official installer – it will ask for your password."
       /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" ;;
    2) open "https://brew.sh" ;;
  esac
  return 1
}

lotus_valid_pkg() { [[ $1 == [[:alnum:]@._+-]##(/[[:alnum:]@._+-]##)# && $1 != *..* ]] }

# Details of packages as tab separated lines: name kind version installed desc homepage
#   lotus_brew_details formula|cask <names…> → reply
lotus_brew_details() {
  local kind=$1; shift
  (( $# )) || { reply=(); return }
  local json=$(brew info --json=v2 --$kind "$@" 2>/dev/null)
  if [[ $kind == formula ]]; then
    reply=(${(f)"$(print -r -- $json | lotus_jq -r '.formulae[] | [.name, "Formula", .versions.stable, (if (.installed | length) > 0 then "1" else "" end), .desc, .homepage] | @tsv')"})
  else
    reply=(${(f)"$(print -r -- $json | lotus_jq -r '.casks[] | [.token, "Cask", .version, (if .installed then "1" else "" end), .desc, .homepage] | @tsv')"})
  fi
}

lotus_brew_search() {
  local query="$*"
  if ! lotus_valid_pkg ${query// /-}; then
    ui_error "Unusual search text" "$query" "Use letters, numbers and - . @ + only"
    return 1
  fi
  ui_header Homebrew "search: $query"
  ui_step "Searching …"
  local -a formulae=(${(f)"$(brew search --formula $query 2>/dev/null)"}) casks=(${(f)"$(brew search --cask $query 2>/dev/null)"})
  formulae=(${formulae:#(==>|Warning|If you meant)*}) casks=(${casks:#(==>|Warning|If you meant)*})
  # best matches first, at most 8 of each
  lotus_rank $query 0 $formulae; formulae=(${reply[1,8]})
  lotus_rank $query 0 $casks; casks=(${reply[1,8]})
  local -a rows
  lotus_brew_details cask $casks; rows+=($reply)
  lotus_brew_details formula $formulae; rows+=($reply)
  print -n $'\e[1A\e[K'
  if (( ! ${#rows} )); then
    ui_error "Nothing found for \"$query\"" "" "Try a shorter word, or /install to browse apps by category"
    return 1
  fi
  # sort all results by how well the name matches
  local -A row_of
  local r
  for r in $rows; do row_of[${r%%$'\t'*}]=$r; done
  lotus_rank $query 0 ${(k)row_of}
  local -a order=($reply) f labels
  local -i i=0
  for r in $order; do
    f=("${(@ps:\t:)row_of[$r]}")
    (( i++ ))
    ui_result $i $f[1] "$f[2] $f[3]" $f[5] $f[4]
    labels+=("$f[1]  ($f[2])")
  done
  ui_blank
  ui_dim "● installed"
  ui_choose "Show details" $labels || return 0
  local pick=$order[REPLY]
  f=("${(@ps:\t:)row_of[$pick]}")
  lotus_brew_card $pick ${(L)f[2]}
}

# Card for one package, then offer to install it
lotus_brew_card() {   # <name> [formula|cask]
  local name=$1 kind=$2
  [[ -z $name ]] && { ui_error "Which package?" "" "Example: /brew info vlc"; return 1 }
  lotus_valid_pkg $name || { ui_error "Not a valid package name" "$name"; return 1 }
  local -a f
  if [[ -z $kind || $kind == cask ]]; then lotus_brew_details cask $name; f=("${(@ps:\t:)reply[1]}"); [[ -n $f[1] ]] && kind=cask; fi
  if [[ -z $f[1] ]]; then lotus_brew_details formula $name; f=("${(@ps:\t:)reply[1]}"); [[ -n $f[1] ]] && kind=formula; fi
  if [[ -z $f[1] ]]; then
    ui_error "Homebrew has no package called \"$name\"" "" "Search instead: /brew $name"
    return 1
  fi
  ui_blank
  ui_card $f[1] "TYPE|$f[2]" "VERSION|$f[3]" "STATUS|${${f[4]:+installed}:-not installed}" "ABOUT|$f[5]" "WEBSITE|$f[6]"
  ui_blank
  [[ -n $f[4] ]] && { ui_success "Already installed"; return 0 }
  ui_confirm "Install $f[1]?" n || return 0
  lotus_brew_run $kind $f[1]
}

lotus_brew_install() {
  local name=$1
  [[ -z $name ]] && { ui_error "Which package?" "" "Example: /brew install firefox"; return 1 }
  lotus_brew_card $name
}

# Runs the installation in the open – Homebrew's own output, prompts and errors stay visible
lotus_brew_run() {   # formula|cask <name>
  local kind=$1 name=$2
  ui_blank
  ui_info "Running: brew install --$kind $name"
  ui_dim "Homebrew may ask for your password. Lotus never sees or stores it."
  ui_blank
  if brew install --$kind $name; then
    ui_blank; ui_success "$name is installed"
  else
    ui_error "Installation of $name failed" "Homebrew's message is shown above." "You can retry with: brew install --$kind $name"
    return 1
  fi
}
