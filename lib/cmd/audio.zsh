# lotus – audio control: /np /play /pause /skip /back /repeat /mute /vu /vd
# What plays comes from fastfetch (macOS, Linux and Windows). The controls are the platform layer's
# (lib/platform/*.zsh): on macOS Spotify and Music are controlled directly (AppleScript) and other players get the
# macOS media keys, which needs the Accessibility permission for the terminal; on Linux every MPRIS player works.

lotus_cmd_audio() {
  shift   # "audio"
  local action=$1
  lotus_np_state
  case $action in
    now)              lotus_audio_now ;;
    play|pause|next|previous) lotus_audio_transport $action ;;
    repeat)           lotus_audio_repeat ;;
    mute)             lotus_audio_mute ;;
    up|down)          lotus_audio_volume $action ;;
  esac
}

# What is playing right now → LOTUS_NP[title|artist|album|status|player|id|pos|len]
lotus_np_state() {
  typeset -gA LOTUS_NP=()
  local json=$($LOTUS_FF --logo none -s media --format json 2>/dev/null)
  [[ $json == *'"song"'* ]] || return 1
  local -a v=("${(@f)$(print -r -- $json | lotus_jq -r '.[0].result | .song.name, .song.artist, .song.album, .song.status, .player.name, .player.id, (.song.position // 0), (.song.length // 0)' 2>/dev/null)}")
  LOTUS_NP=(title "$v[1]" artist "$v[2]" album "$v[3]" status "$v[4]" player "$v[5]" id "$v[6]" pos "$v[7]" len "$v[8]")
}

lotus_audio_now() {
  if [[ -z $LOTUS_NP[title] ]]; then
    ui_header "Now playing"
    ui_dim "Nothing is playing right now."
    ui_blank; return 0
  fi
  local -i pos=$(( ${LOTUS_NP[pos]%.*} / 1000 )) len=$(( ${LOTUS_NP[len]%.*} / 1000 ))
  local pct=0
  (( len > 0 )) && pct=$(( pos * 100 / len ))
  local -i n=$(( pct / 10 ))
  ui_header "Now playing" $LOTUS_NP[player]
  ui_card $LOTUS_NP[status] "TITLE|$LOTUS_NP[title]" "ARTIST|${LOTUS_NP[artist]:--}" "ALBUM|${LOTUS_NP[album]:--}" \
    "TIME|[${${(l:n::x:)}//x/■}${${(l:10-n::x:)}//x/·}] $(( pos / 60 )):${(l:2::0:)$(( pos % 60 ))} / $(( len / 60 )):${(l:2::0:)$(( len % 60 ))}"
  ui_blank
}

lotus_audio_transport() {
  local action=$1 label
  label=${${${${action/next/Next track}/previous/Previous track}/play/Play}/pause/Pause}
  if [[ -z $LOTUS_NP[title] ]]; then
    ui_warn "Nothing is playing right now"
    [[ $action == play ]] || return 1
  fi
  lotus_os_media $action "$LOTUS_NP[id]" "$LOTUS_NP[player]"
  case $? in
    0) ui_info "$label  $REPLY" ;;
    2) ui_error "This system cannot $action here" "${LOTUS_NP[player]:-The player} cannot be controlled from the terminal." ""; return 1 ;;
    *) ui_error "${LOTUS_OS_MSG[1]:-The player did not respond}" "${LOTUS_OS_MSG[2]}" "${LOTUS_OS_MSG[3]}"; return 1 ;;
  esac
  if [[ $action == (next|previous) ]]; then
    sleep 0.6
    lotus_np_state && ui_dim "  ♫ $LOTUS_NP[title]${LOTUS_NP[artist]:+ — $LOTUS_NP[artist]}"
  fi
}

lotus_audio_repeat() {
  lotus_os_media repeat "$LOTUS_NP[id]" "$LOTUS_NP[player]"
  case $? in
    0) ui_info "$REPLY" ;;
    *) if [[ $LOTUS_OS == macos ]]; then
         ui_error "Repeat works with Spotify and Music" "${LOTUS_NP[player]:-Nothing} is playing right now." "Other players do not let macOS change their repeat mode."
       else
         ui_error "This player does not let Lotus change its repeat mode" "${LOTUS_NP[player]:-Nothing} is playing right now." "Players that support MPRIS with a loop status work (Spotify, VLC, mpv with a plugin …)."
       fi
       return 1 ;;
  esac
}

lotus_audio_mute() {
  lotus_os_volume mute || { ui_error "The volume cannot be changed from here" "" "${${LOTUS_OS:#macos}:+Install wpctl (PipeWire), pactl (PulseAudio) or amixer (ALSA).}"; return 1 }
  [[ $REPLY == 1 ]] && ui_info "Muted" || ui_info "Sound on"
}

lotus_audio_volume() {
  local -i vol
  lotus_os_volume $1 || { ui_error "The volume cannot be changed from here" "" "${${LOTUS_OS:#macos}:+Install wpctl (PipeWire), pactl (PulseAudio) or amixer (ALSA).}"; return 1 }
  vol=$REPLY
  ui_progress "Volume" $vol
  (( vol < 100 )) && print
}
