# lotus – app discovery and installation (/install), backed by Homebrew Cask
source $LOTUS_ROOT/lib/cmd/brew.zsh

typeset -ga LOTUS_CATEGORIES=(Browsers Communication Microsoft Development Media Utilities Games Productivity "Free alternatives" "Open-source software")

lotus_cmd_install() {
  shift   # "install"
  lotus_need_brew || return 1
  export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1
  lotus_catalog
  if (( $# )); then lotus_install_find "$*"; else lotus_install_browse; fi
}

# data/apps.tsv → LOTUS_CAT_ROW[name]=line, LOTUS_CAT_NAMES
lotus_catalog() {
  typeset -gA LOTUS_CAT_ROW=()
  typeset -ga LOTUS_CAT_NAMES=()
  local line
  for line in "${(@f)$(<$LOTUS_ROOT/data/apps.tsv)}"; do
    [[ $line == \#* ]] && continue
    LOTUS_CAT_ROW[${line%%$'\t'*}]=$line
    LOTUS_CAT_NAMES+=(${line%%$'\t'*})
  done
}

# Installed? Homebrew knows its own casks; apps installed another way are found in /Applications
lotus_app_installed() {   # <app bundle> <cask>
  [[ $1 != - && ( -d /Applications/$1 || -d ~/Applications/$1 ) ]] && return 0
  (( ${+LOTUS_CASKROOM} )) || typeset -g LOTUS_CASKROOM=$(brew --caskroom 2>/dev/null)
  [[ -n $LOTUS_CASKROOM && -d $LOTUS_CASKROOM/$2 ]]
}

lotus_install_browse() {
  ui_header Install "${#LOTUS_CAT_NAMES} apps · Homebrew Cask"
  local -a labels f
  local -A count
  local c name
  for name in $LOTUS_CAT_NAMES; do
    f=("${(@ps:\t:)LOTUS_CAT_ROW[$name]}")
    for c in ${(s:,:)f[3]}; do (( count[$c]++ )); done
  done
  for c in $LOTUS_CATEGORIES; do labels+=("${(r:22:)c} $count[$c] apps"); done
  ui_choose "Pick a category" "Search all apps" $labels || return 0
  if (( REPLY == 1 )); then
    ui_input "Search" || return 0
    [[ -n $REPLY ]] && lotus_install_find "$REPLY"
    return
  fi
  local cat=$LOTUS_CATEGORIES[REPLY-1] mark k=$'\e['"$LOTUS_C[key]m" d=$'\e['"$LOTUS_C[dim]m" r=$'\e[0m'
  local -a names rows
  print -n $'\e[H\e[2J'
  ui_header Install "$cat  ·  ${k}●${r}${d} installed"
  for name in $LOTUS_CAT_NAMES; do
    f=("${(@ps:\t:)LOTUS_CAT_ROW[$name]}")
    [[ ,$f[3], == *,$cat,* ]] || continue
    names+=($name)
    mark=" "; lotus_app_installed $f[4] $f[2] && mark="${k}●${r}"
    rows+=("$mark ${(r:22:)name}${r} ${d}${f[5][1,${COLUMNS:-100}-40]}${r}")
  done
  ui_choose "" $rows || return 0
  lotus_install_card $names[REPLY]
}

lotus_install_find() {
  local query=$1
  if lotus_pick "$query" app $LOTUS_CAT_NAMES; then
    lotus_install_card $REPLY
    return
  fi
  # not in the catalog: ask Homebrew directly
  ui_info "\"$query\" is not in the Lotus catalog – searching Homebrew Cask …"
  local -a casks=(${(f)"$(brew search --cask ${query// /-} 2>/dev/null)"})
  casks=(${casks:#(==>|Warning|If you meant)*})
  if lotus_pick "$query" app $casks; then
    lotus_brew_card $REPLY cask
  else
    ui_error "No app found for \"$query\"" "" "Browse by category: /install"
    return 1
  fi
}

lotus_install_card() {
  local name=$1
  local -a f=("${(@ps:\t:)LOTUS_CAT_ROW[$name]}")
  local cask=$f[2] json url size=unknown home inst=no
  ui_step "Looking up $name …"
  json=$(brew info --json=v2 --cask $cask 2>/dev/null)
  url=$(print -r -- $json | lotus_jq -r '.casks[0].url // empty' 2>/dev/null)
  home=$(print -r -- $json | lotus_jq -r '.casks[0].homepage // empty' 2>/dev/null)
  local version=$(print -r -- $json | lotus_jq -r '.casks[0].version // empty' 2>/dev/null)
  if [[ -n $url ]]; then
    local bytes=${${(M)${(f)"$(curl -sIL -m 4 $url 2>/dev/null)"}:#(#i)content-length:*}[-1]//[^0-9]/}
    (( bytes > 100000 )) && size="$(( bytes / 1048576 )) MB"
  fi
  lotus_app_installed $f[4] $cask && inst=yes
  print -n $'\e[1A\e[K'
  ui_blank
  ui_card $name "ABOUT|$f[5]" "CATEGORY|${f[3]//,/, }" "VERSION|${version:-?}" "SIZE|$size" \
    "SOURCE|Homebrew Cask ($cask)" "WEBSITE|${home:--}" "METHOD|brew install --cask $cask" \
    "STATUS|${${inst:#no}:+installed}${${inst:#yes}:+not installed}"
  ui_blank
  if [[ $inst == yes ]]; then
    ui_success "$name is already installed"
    ui_confirm "Open it?" y && open -a "${f[4]:r}" 2>/dev/null
    return 0
  fi
  ui_confirm "Install $name?" n || return 0
  lotus_brew_run cask $cask
}
