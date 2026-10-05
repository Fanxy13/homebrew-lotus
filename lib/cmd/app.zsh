# lotus – open installed apps by name, typos included (/app, open <name>)

lotus_cmd_app() {
  shift   # "app"
  local query="$*"
  if [[ -z ${query// } ]]; then
    ui_error "Which app?" "" "Example: /app Spotify"
    return 1
  fi
  lotus_installed_apps
  local -A path_of=("${(@kv)LOTUS_APPS}")
  if ! lotus_pick "$query" app ${(k)path_of}; then
    ui_error "No app found for \"$query\"" "" "Install new apps with: /install $query"
    return 1
  fi
  local name=$REPLY
  if open -a "$path_of[$name]" 2>/dev/null; then
    ui_info "Opening $name"
  else
    ui_error "Could not open $name" "$path_of[$name]"
    return 1
  fi
}

# Installed apps → LOTUS_APPS[name]=path (the first location wins)
lotus_installed_apps() {
  typeset -gA LOTUS_APPS=()
  local p n
  for p in /Applications/*.app(N) /Applications/*/*.app(N) ~/Applications/*.app(N) \
           /System/Applications/*.app(N) /System/Applications/Utilities/*.app(N) \
           /Applications/Utilities/*.app(N) /System/Library/CoreServices/Finder.app(N); do
    n=${p:t:r}
    [[ -z $LOTUS_APPS[$n] ]] && LOTUS_APPS[$n]=$p
  done
}
