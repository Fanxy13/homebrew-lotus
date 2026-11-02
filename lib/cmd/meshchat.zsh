# lotus – /meshchat: one chat with everyone nearby over Bluetooth Low Energy – no internet, no Wi-Fi, no server. Every
# Mac in the chat passes each message on (a mesh), as far as there are Macs to pass it on. Public, and signed.
#   /meshchat                  the chat – the same on every Mac nearby, nothing to set up
#   /meshchat demo             two simulated people, one of them a relay away – no Bluetooth, no second Mac
#   /meshchat doctor           macOS, the Command Line Tools and the build – then Bluetooth and its permission
#   /meshchat help             everything else: history, nick, set links, relay, selftest
# The chat is a Swift program in lib/meshchat (CoreBluetooth for the radio, CryptoKit for the signatures) that
# lib/meshchat/meshchat.zsh builds once on this Mac. It reads what any Mac nearby sends, so it runs in a sandbox – the
# one of Lotus' limited plugins, which MeshChat was before: it reads only lib/meshchat, writes only its data folder
# (~/.local/share/lotus/meshchat: this Mac's identity, the name, the history) and has no network. Bluetooth is not
# the network: macOS asks whether your terminal app may use it. Without a sandbox it does not run at all. macOS only.

lotus_cmd_meshchat() {
  shift   # "meshchat"
  # its own name in the log – only while it runs: bin/lotus also loads this file for the move of the old plugin
  local LOTUS_LOG_COMP=meshchat
  if [[ $LOTUS_OS != macos ]]; then
    ui_error "MeshChat runs on macOS only" "It talks over Apple's CoreBluetooth and signs with CryptoKit – both are part of macOS."
    return 1
  fi
  local dir=$LOTUS_ROOT/lib/meshchat data=$LOTUS_DATA/meshchat
  if ! lotus_os_sandbox_available; then
    ui_error "MeshChat runs in a sandbox, and there is none here" "/usr/bin/sandbox-exec is missing – MeshChat is not started without it."
    return 126
  fi
  zf_mkdir -p $data && chmod 700 $data 2>/dev/null     # this Mac's identity is in it: yours alone
  lotus_log INFO meshchat "meshchat${1:+ $1}"
  lotus_os_sandbox_wrap $dir $data no
  local -a wrap=("${reply[@]}") env=(
    PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin HOME=$HOME TMPDIR=${TMPDIR:-/tmp}
    LANG=${LANG:-en_US.UTF-8} LC_ALL=${LC_ALL:-en_US.UTF-8} TERM=${TERM:-xterm-256color} COLUMNS=${COLUMNS:-80}
    LOTUS_MESHCHAT_DATA=$data LOTUS_VERSION=$LOTUS_VERSION LOTUS_LANG=$LOTUS_LANG
    LOTUS_COLOR_KEY=$LOTUS_C[key] LOTUS_COLOR_ACCENT=$LOTUS_C[accent] LOTUS_COLOR_DIM=$LOTUS_C[dim] LOTUS_COLOR_LOGO=$LOTUS_C[logo]
  )
  # a clean environment, as for a limited plugin: nothing of Lotus' settings, never the AI's keys
  (cd $dir && exec env -i $env $wrap ${commands[zsh]:-/bin/zsh} -f $dir/meshchat.zsh "$@")
}

# MeshChat was a plugin ("meshchat") before it became part of Lotus. That plugin – only Lotus' own, by its plugin.conf –
# goes: a command of Lotus' own cannot be a plugin's. What it kept comes along into MeshChat's data folder: this Mac's
# identity (the Macs nearby know it by its fingerprint), the name, the history, the settings and the rooms of
# MeshChat 1. Nothing is deleted before it has moved. bin/lotus calls this at every start while the old plugin is there.
lotus_meshchat_migrate() {
  local dir=$LOTUS_CONF/plugins/meshchat old=$LOTUS_DATA/plugins/meshchat new=$LOTUS_DATA/meshchat f
  [[ -f $dir/plugin.conf && ! -L $dir ]] || return 0
  grep -Eq '^name[[:space:]]*=[[:space:]]*meshchat[[:space:]]*$' $dir/plugin.conf 2>/dev/null &&
    grep -Eq '^author[[:space:]]*=[[:space:]]*Lotus[[:space:]]*$' $dir/plugin.conf 2>/dev/null || return 0
  if [[ -d $old && ! -L $old ]]; then
    if [[ ! -e $new && ! -L $new ]]; then
      zf_mv $old $new 2>/dev/null || return 0              # could not move it: nothing is deleted, again next time
    else
      # MeshChat ran as part of Lotus already: what it keeps stays, the rest comes along
      for f in $old/*(ND); do
        [[ -e $new/${f:t} || -L $new/${f:t} ]] || zf_mv $f $new/${f:t} 2>/dev/null || return 0
      done
    fi
  fi
  rm -rf -- "${dir:?}" "${old:?}" "$LOTUS_DATA/plugins/.meshchat-source"
  (( ${+functions[_plg_drop_entry]} )) || source $LOTUS_ROOT/lib/cmd/plugin.zsh
  _plg_drop_entry meshchat
  lotus_log INFO meshchat "The plugin meshchat was removed: MeshChat is part of Lotus now, its data is in ${new/#$HOME/~}"
  [[ -t 2 ]] && print -ru2 -- "  "$'\e['"$LOTUS_C[dim]mMeshChat is part of Lotus now – the old meshchat plugin was removed; your name, identity and history came along."$'\e[0m'
  return 0
}
