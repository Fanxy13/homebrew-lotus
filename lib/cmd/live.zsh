# lotus – /liveserver: serves the folder you are in, like Live Server in VS Code.
#   /liveserver                  the folder you are in: opens index.html, or a menu of all its pages
#   /liveserver <folder|page>    another folder, or that page
#   /liveserver --port <n>       a port of your choice (otherwise 5500 or the next free one)
#   /liveserver --no-open        without opening the browser · --local: only this Mac, not the Wi-Fi
#   /liveserver stop             stops the ones that run in other windows
# The server is lib/live/liveserver.py – Python's standard library, nothing to install. It reloads the page when you
# save, answers this Mac and the devices in its Wi-Fi (nobody else), and serves nothing outside the folder.
# lib/cmd/html.zsh (/html) takes the page that is open in its browser.

typeset -g LOTUS_LOG_COMP=live

lotus_cmd_live() {
  shift   # "liveserver"
  if (( ! $+commands[python3] )); then
    ui_error "Live Server needs Python 3" "" "xcode-select --install   (Apple's Command Line Tools bring it)"
    return 1
  fi
  zf_mkdir -p $LOTUS_STATE/live 2>/dev/null
  lotus_log INFO live "liveserver${*:+ $*}"
  # the folder you are in, Lotus' colors, and where the servers that run leave a note (for stop and /html)
  env PYTHONDONTWRITEBYTECODE=1 LOTUS_PWD=$PWD LOTUS_LIVE_DATA=$LOTUS_STATE/live \
    LOTUS_COLOR_KEY=$LOTUS_C[key] LOTUS_COLOR_ACCENT=$LOTUS_C[accent] LOTUS_COLOR_DIM=$LOTUS_C[dim] LOTUS_COLOR_LOGO=$LOTUS_C[logo] \
    python3 -B $LOTUS_ROOT/lib/live/liveserver.py "$@"
}

# Live Server and /html were a plugin ("liveserver") before they became part of Lotus. That plugin – only Lotus' own,
# by its plugin.conf – goes: a command of Lotus' own cannot be a plugin's, and its servers that still run and the list of
# the documents /html made come along. bin/lotus calls this at every start.
lotus_live_migrate() {
  local dir=$LOTUS_CONF/plugins/liveserver old=$LOTUS_DATA/plugins/liveserver f
  [[ -f $dir/plugin.conf && ! -L $dir ]] || return 0
  grep -Eq '^name[[:space:]]*=[[:space:]]*liveserver[[:space:]]*$' $dir/plugin.conf 2>/dev/null &&
    grep -Eq '^author[[:space:]]*=[[:space:]]*Lotus[[:space:]]*$' $dir/plugin.conf 2>/dev/null || return 0
  zf_mkdir -p $LOTUS_STATE/live/running 2>/dev/null
  for f in $old/running/*(N); do [[ -e $LOTUS_STATE/live/running/${f:t} ]] || zf_mv $f $LOTUS_STATE/live/running/${f:t} 2>/dev/null; done
  [[ -e $old/made.tsv && ! -e $LOTUS_STATE/live/made.tsv ]] && zf_mv $old/made.tsv $LOTUS_STATE/live/made.tsv 2>/dev/null
  [[ -e $old/html-last && ! -e $LOTUS_STATE/html-last ]] && zf_mv $old/html-last $LOTUS_STATE/html-last 2>/dev/null
  rm -rf -- "${dir:?}" "${old:?}" "$LOTUS_DATA/plugins/.liveserver-source"
  (( ${+functions[_plg_drop_entry]} )) || source $LOTUS_ROOT/lib/cmd/plugin.zsh
  _plg_drop_entry liveserver
  lotus_log INFO live "The plugin liveserver was removed: Live Server and /html are part of Lotus now"
  [[ -t 2 ]] && print -ru2 -- "  "$'\e['"$LOTUS_C[dim]mLive Server and /html are part of Lotus now – the old liveserver plugin was removed."$'\e[0m'
  return 0
}
