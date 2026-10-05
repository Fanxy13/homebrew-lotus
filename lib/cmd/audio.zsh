# lotus – audio control: /np /play /pause /skip /back /repeat /mute /vu /vd
# Spotify and Music are controlled directly (AppleScript). Other players get
# the macOS media keys, which needs the Accessibility permission for the terminal.

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

# AppleScript target for players Lotus can control directly
_lotus_scriptable() {
  case $LOTUS_NP[id] in
    com.spotify.client) REPLY=Spotify ;;
    com.apple.Music)    REPLY=Music ;;
    *)                  REPLY= ; return 1 ;;
  esac
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

# NX key codes: play/pause 16, next 17, previous 18
_lotus_media_key() {
  osascript -l JavaScript - $1 <<'JXA' >/dev/null 2>&1
ObjC.import('Cocoa');
function run(argv) {
  const code = parseInt(argv[0]);
  for (const down of [true, false]) {
    const flags = down ? 0xa00 : 0xb00;
    const data1 = (code << 16) | ((down ? 0xa : 0xb) << 8);
    const ev = $.NSEvent.otherEventWithTypeLocationModifierFlagsTimestampWindowNumberContextSubtypeData1Data2(
      14, $.NSMakePoint(0, 0), flags, 0, 0, null, 8, data1, -1);
    $.CGEventPost(0, ev.CGEvent);
  }
}
JXA
}

_lotus_ax_trusted() {
  [[ $(osascript -l JavaScript -e 'ObjC.import("ApplicationServices"); $.AXIsProcessTrusted()' 2>/dev/null) == true ]]
}

lotus_audio_transport() {
  local action=$1 app label
  label=${${${${action/next/Next track}/previous/Previous track}/play/Play}/pause/Pause}
  if [[ -z $LOTUS_NP[title] ]]; then
    ui_warn "Nothing is playing right now"
    [[ $action == play ]] || return 1
  fi
  if _lotus_scriptable; then
    app=$REPLY
    local verb=${${${${action/next/next track}/previous/previous track}/play/play}/pause/pause}
    if osascript -e "tell application \"$app\" to $verb" >/dev/null 2>&1; then
      ui_info "$label  $LOTUS_NP[player]"
    else
      ui_error "$app did not respond" "macOS may have asked for permission to control $app." "Allow it in System Settings → Privacy & Security → Automation."
      return 1
    fi
  else
    if ! _lotus_ax_trusted; then
      ui_error "Lotus cannot press media keys yet" "${LOTUS_NP[player]:-This player} is controlled with the macOS media keys." \
        "Allow your terminal app in System Settings → Privacy & Security → Accessibility."
      return 1
    fi
    local -A codes=(play 16 pause 16 next 17 previous 18)
    _lotus_media_key $codes[$action]
    ui_info "$label  ${LOTUS_NP[player]:-media key}"
  fi
  if [[ $action == (next|previous) ]]; then
    sleep 0.6
    lotus_np_state && ui_dim "  ♫ $LOTUS_NP[title]${LOTUS_NP[artist]:+ — $LOTUS_NP[artist]}"
  fi
}

lotus_audio_repeat() {
  if ! _lotus_scriptable; then
    ui_error "Repeat works with Spotify and Music" "${LOTUS_NP[player]:-Nothing} is playing right now." "Other players do not let macOS change their repeat mode."
    return 1
  fi
  local state
  if [[ $REPLY == Spotify ]]; then
    state=$(osascript -e 'tell application "Spotify"' -e 'set repeating to not repeating' -e 'return repeating' -e 'end tell' 2>/dev/null)
    [[ $state == true ]] && ui_info "Repeat on  Spotify" || ui_info "Repeat off  Spotify"
  else
    state=$(osascript -e 'tell application "Music"' -e 'if song repeat is off then' -e 'set song repeat to all' -e 'else' -e 'set song repeat to off' -e 'end if' -e 'return song repeat as text' -e 'end tell' 2>/dev/null)
    ui_info "Repeat ${state:-?}  Music"
  fi
}

lotus_audio_mute() {
  local muted=$(osascript -e 'set m to not (output muted of (get volume settings))' -e 'set volume output muted m' -e 'return m' 2>/dev/null)
  [[ $muted == true ]] && ui_info "Muted" || ui_info "Sound on"
}

lotus_audio_volume() {
  local -i step=-6 vol
  [[ $1 == up ]] && step=6
  vol=$(osascript -e "set v to (output volume of (get volume settings)) + $step" -e 'if v > 100 then set v to 100' -e 'if v < 0 then set v to 0' -e 'set volume output volume v' -e 'return v' 2>/dev/null)
  ui_progress "Volume" $vol
  (( vol < 100 )) && print
}
