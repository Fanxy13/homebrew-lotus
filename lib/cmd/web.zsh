# lotus – browser: /google, /search, /web, links, /lotus web, /lotus github

typeset -gA LOTUS_ENGINES=(
  google     'https://www.google.com/search?q='
  duckduckgo 'https://duckduckgo.com/?q='
  bing       'https://www.bing.com/search?q='
  ecosia     'https://www.ecosia.org/search?q='
  brave      'https://search.brave.com/search?q='
)

# Sites /web knows by name: "/web github lotus" searches GitHub for lotus
typeset -gA LOTUS_SITES=(
  github        'https://github.com|https://github.com/search?q='
  youtube       'https://www.youtube.com|https://www.youtube.com/results?search_query='
  reddit        'https://www.reddit.com|https://www.reddit.com/search/?q='
  wikipedia     'https://en.wikipedia.org|https://en.wikipedia.org/w/index.php?search='
  maps          'https://maps.apple.com|https://maps.apple.com/?q='
  amazon        'https://www.amazon.com|https://www.amazon.com/s?k='
  stackoverflow 'https://stackoverflow.com|https://stackoverflow.com/search?q='
  npm           'https://www.npmjs.com|https://www.npmjs.com/search?q='
  brew          'https://brew.sh|https://formulae.brew.sh/?search='
  x             'https://x.com|https://x.com/search?q='
  spotify       'https://open.spotify.com|https://open.spotify.com/search/'
  translate     'https://translate.google.com|https://translate.google.com/?text='
)

lotus_cmd_web() {
  local cmd=$1; shift
  case $cmd in
    web)    lotus_open_url $LOTUS_P[website] "Lotus website" ;;
    github) lotus_open_url $LOTUS_P[github] "GitHub" ;;
    goat)   lotus_open_url $LOTUS_P[github] quiet && ui_dim "Obviously." ;;
    google) lotus_search google "$@" ;;
    search) lotus_search ${LOTUS_SEARCH_ENGINE:-google} "$@" ;;
    browse) lotus_browse "$@" ;;
    open)   lotus_open_link "$@" ;;
  esac
}

# A link Lotus is willing to open: http(s), no spaces or control characters
lotus_valid_url() {
  [[ $1 == (#i)https#://[^[:space:]/]##.[^[:space:]]## && $1 != *[[:cntrl:]]* ]]
}

lotus_open_url() {   # <url> [label|quiet]
  if ! lotus_valid_url $1; then
    ui_error "That is not a valid link" "$1" "Links need to start with http:// or https://"
    return 1
  fi
  open "$1" 2>/dev/null || { ui_error "Could not open the link" "$1"; return 1 }
  [[ $2 == quiet ]] || ui_info "Opening ${2:-$1}"
}

lotus_search() {   # <engine> <words…>
  local engine=$1; shift
  if [[ -z ${*// } ]]; then
    ui_error "Nothing to search for" "" "Example: /search best minecraft server plugins"
    return 1
  fi
  lotus_urlencode "$*"
  lotus_open_url "${LOTUS_ENGINES[$engine]:-$LOTUS_ENGINES[google]}$REPLY" "${(C)engine}: $*"
}

# Turns "example.com/page" or "https://…" into a link → REPLY (status 1 if it is not one)
lotus_as_url() {
  local s=$1
  [[ $s == *[[:space:]]* ]] && return 1
  if [[ $s == (#i)https#://* ]]; then REPLY=$s
  elif [[ $s == [[:alnum:]-]##(.[[:alnum:]-]##)#.[[:alpha:]](#c2,)(/*|) ]]; then REPLY="https://$s"
  else return 1; fi
  lotus_valid_url $REPLY
}

lotus_browse() {
  if (( ! $# )); then lotus_open_url $LOTUS_P[website] "Lotus website"; return; fi
  local site=${(L)1} parts
  if (( $# == 1 )) && lotus_as_url $1; then
    lotus_open_url $REPLY
  elif [[ -n $LOTUS_SITES[$site] ]]; then
    parts=$LOTUS_SITES[$site]
    if (( $# == 1 )); then
      lotus_open_url ${parts%%|*} ${(C)site}
    else
      shift
      lotus_urlencode "$*"
      lotus_open_url "${parts#*|}$REPLY" "${(C)site}: $*"
    fi
  else
    lotus_search ${LOTUS_SEARCH_ENGINE:-google} "$@"
  fi
}

lotus_open_link() {
  if (( $# != 1 )) || ! lotus_as_url "$1"; then
    ui_error "That is not a valid link" "$*" "Example: https://github.com/Fanxy13"
    return 1
  fi
  lotus_open_url $REPLY
}
