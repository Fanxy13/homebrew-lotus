# lotus – platform layer for macOS (loaded by lib/platform.zsh)
# These functions hold what the commands used to call directly (open, pbcopy, osascript, caffeinate, security, sips …).
# Behavior is the same as before 3.0 – only the place moved.

# ── Open things ───────────────────────────────────────────────

lotus_os_open()   { _lotus_os_target "$1"; open -- "$REPLY" }              # a link or a path, in the default app
lotus_os_reveal() { _lotus_os_target "$1"; open -R -- "$REPLY" }           # shown in Finder

# Installed apps → LOTUS_APPS[name]=path (the first location wins)
lotus_os_apps() {
  typeset -gA LOTUS_APPS=()
  local p n
  for p in /Applications/*.app(N) /Applications/*/*.app(N) ~/Applications/*.app(N) \
           /System/Applications/*.app(N) /System/Applications/Utilities/*.app(N) \
           /Applications/Utilities/*.app(N) /System/Library/CoreServices/Finder.app(N); do
    n=${p:t:r}
    [[ -z $LOTUS_APPS[$n] ]] && LOTUS_APPS[$n]=$p
  done
}
lotus_os_open_app() { open -a "$1" 2>/dev/null }

# ── Clipboard ─────────────────────────────────────────────────

lotus_os_clip_copy()  { pbcopy }
lotus_os_clip_paste() { pbpaste 2>/dev/null }

# What the clipboard holds → REPLY: "files <n>", "image <w>x<h>" or "none"
lotus_os_clip_peek() {
  REPLY=$(osascript -l JavaScript $LOTUS_ROOT/lib/bg/clipboard.js peek 2>/dev/null)
  [[ -n $REPLY ]] || REPLY=none
}

# The clipboard as files: copied files as they are, an image saved as PNG to <out.png> – one path per line
lotus_os_clip_save() { osascript -l JavaScript $LOTUS_ROOT/lib/bg/clipboard.js save "$1" 2>/dev/null }

# ── Notifications, keep awake ─────────────────────────────────

lotus_os_notify() {   # <title> <text>
  local t=${1//\\/\\\\} x=${2//\\/\\\\}
  t=${t//\"/\\\"} x=${x//\"/\\\"}
  osascript -e "display notification \"$x\" with title \"$t\"" >/dev/null 2>&1
}

# Keeps the Mac awake for <seconds> (0 = until stopped) with caffeinate: display, idle sleep and disk stay awake.
# It runs on its own – closing the terminal does not stop it. → REPLY = its process id
lotus_os_awake_start() {
  (( $+commands[caffeinate] )) || return 2
  local -a args=(-d -i -m)
  (( $1 > 0 )) && args+=(-t $1)
  nohup caffeinate $args >/dev/null 2>&1 &!
  REPLY=$!
  sleep 0.1
  kill -0 $REPLY 2>/dev/null
}
lotus_os_awake_name() { REPLY=caffeinate }
lotus_os_awake_is()   { kill -0 $1 2>/dev/null && [[ $(ps -p $1 -o comm= 2>/dev/null) == *caffeinate ]] }
lotus_os_awake_stop() { kill $1 2>/dev/null }

# ── Sound ─────────────────────────────────────────────────────

# lotus_os_volume up|down|mute → REPLY = the volume in percent (up, down) or 1 = muted / 0 = sound on (mute)
lotus_os_volume() {
  local -i step vol
  case $1 in
    up|down)
      [[ $1 == up ]] && step=6 || step=-6
      vol=$(osascript -e "set v to (output volume of (get volume settings)) + $step" -e 'if v > 100 then set v to 100' -e 'if v < 0 then set v to 0' -e 'set volume output volume v' -e 'return v' 2>/dev/null) || return 1
      REPLY=$vol ;;
    mute)
      REPLY=$(osascript -e 'set m to not (output muted of (get volume settings))' -e 'set volume output muted m' -e 'return m' 2>/dev/null) || return 1
      [[ $REPLY == true ]] && REPLY=1 || REPLY=0 ;;
    *) return 2 ;;
  esac
}

# Media control – lotus_os_media play|pause|next|previous|repeat <player id>
#   status 0 done · 1 failed (LOTUS_OS_MSG = title, detail, hint) · 2 this player cannot do it
# Spotify and Music are controlled directly (AppleScript), other players get the macOS media keys.
typeset -ga LOTUS_OS_MSG=()
_lotus_os_scriptable() {   # <player id> → REPLY = AppleScript name
  case $1 in
    com.spotify.client) REPLY=Spotify ;;
    com.apple.Music)    REPLY=Music ;;
    *)                  REPLY= ; return 1 ;;
  esac
}
_lotus_os_ax_trusted() {
  [[ $(osascript -l JavaScript -e 'ObjC.import("ApplicationServices"); $.AXIsProcessTrusted()' 2>/dev/null) == true ]]
}
# NX key codes: play/pause 16, next 17, previous 18
_lotus_os_media_key() {
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
lotus_os_media() {
  local action=$1 id=$2 player=$3 app verb state
  LOTUS_OS_MSG=()
  if [[ $action == repeat ]]; then
    _lotus_os_scriptable $id || return 2
    app=$REPLY
    if [[ $app == Spotify ]]; then
      state=$(osascript -e 'tell application "Spotify"' -e 'set repeating to not repeating' -e 'return repeating' -e 'end tell' 2>/dev/null)
      [[ $state == true ]] && REPLY="Repeat on  Spotify" || REPLY="Repeat off  Spotify"
    else
      state=$(osascript -e 'tell application "Music"' -e 'if song repeat is off then' -e 'set song repeat to all' -e 'else' -e 'set song repeat to off' -e 'end if' -e 'return song repeat as text' -e 'end tell' 2>/dev/null)
      REPLY="Repeat ${state:-?}  Music"
    fi
    return 0
  fi
  if _lotus_os_scriptable $id; then
    app=$REPLY
    verb=${${${${action/next/next track}/previous/previous track}/play/play}/pause/pause}
    if osascript -e "tell application \"$app\" to $verb" >/dev/null 2>&1; then REPLY=$player; return 0; fi
    LOTUS_OS_MSG=("$app did not respond" "macOS may have asked for permission to control $app." "Allow it in System Settings → Privacy & Security → Automation.")
    return 1
  fi
  if ! _lotus_os_ax_trusted; then
    LOTUS_OS_MSG=("Lotus cannot press media keys yet" "${player:-This player} is controlled with the macOS media keys." "Allow your terminal app in System Settings → Privacy & Security → Accessibility.")
    return 1
  fi
  local -A codes=(play 16 pause 16 next 17 previous 18)
  _lotus_os_media_key $codes[$action]
  REPLY=${player:-media key}
}

# ── Secrets (the Keychain) ────────────────────────────────────

# lotus_os_secret_get <service> → REPLY (status 1 when there is none)
lotus_os_secret_get() { REPLY=$(security find-generic-password -s "$1" -w 2>/dev/null); [[ -n $REPLY ]] }
# lotus_os_secret_set <service> <value>   (the value goes in through security's own prompt, never into a process list)
lotus_os_secret_set() {
  [[ $2 == [[:alnum:]._~+/=:-]## ]] || return 1
  print -r -- "add-generic-password -U -s $1 -a ${USER:-lotus} -w $2" | security -i >/dev/null 2>&1
}
lotus_os_secret_del() { security delete-generic-password -s "$1" >/dev/null 2>&1 }
lotus_os_secret_store_name() { REPLY="your Keychain" }

# ── This computer ─────────────────────────────────────────────

lotus_os_cpu_count() {   # [perf] – the cores in all, or only the performance cores
  if [[ $1 == perf ]]; then REPLY=$(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null || sysctl -n hw.physicalcpu 2>/dev/null || print 4)
  else REPLY=$(sysctl -n hw.ncpu 2>/dev/null || print 4); fi
}
lotus_os_mem_bytes() { REPLY=$(sysctl -n hw.memsize 2>/dev/null || print 0) }
lotus_os_chip()      { REPLY=$(sysctl -n machdep.cpu.brand_string 2>/dev/null) }
lotus_os_fullname()  { REPLY=$(id -F 2>/dev/null) }
lotus_os_lan_ip()    { REPLY=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null); [[ -n $REPLY ]] }

# ── Files and folders ─────────────────────────────────────────

# To the Trash (Finder can put it back). Status 2 when this Mac has no way to do it from a script.
lotus_os_trash() {
  local f
  for f in "$@"; do
    if (( $+commands[trash] )) && trash -- $f 2>/dev/null; then continue; fi        # macOS 15 and newer
    osascript -e "tell application \"Finder\" to delete POSIX file \"${f:A}\"" >/dev/null 2>&1 || return 1
  done
}

# A folder picker (a native sheet) → REPLY = the path; status 1 when cancelled
lotus_os_choose_folder() {   # <prompt> <start folder>
  local prompt=${1//\"/} start=$2
  REPLY=$(osascript -e 'activate' -e "POSIX path of (choose folder with prompt \"$prompt\" default location (POSIX file \"${start:-$HOME}\"))" 2>/dev/null) || return 1
  REPLY=${REPLY%/}
  [[ -n $REPLY ]]
}

# "WxH" of an image file → REPLY
lotus_os_image_info() {
  local info=$(sips -g pixelWidth -g pixelHeight -- "$1" 2>/dev/null)
  local w=${${(M)${(f)info}:#*pixelWidth*}##* } h=${${(M)${(f)info}:#*pixelHeight*}##* }
  [[ $w == <-> && $h == <-> ]] || return 1
  REPLY=${w}x${h}
}

# ── Programs and processes ────────────────────────────────────

# Java home for at least <major> → REPLY (status 1 when there is none)
lotus_os_java() {
  REPLY=$(/usr/libexec/java_home -v $1+ 2>/dev/null) || REPLY=$(/usr/libexec/java_home -v $1 2>/dev/null) || { REPLY=; return 1 }
  [[ -n $REPLY ]]
}

# The working folders of running programs called <comm> → lines "pid<TAB>folder"
lotus_os_proc_cwds() {
  local line pid
  for line in "${(@f)$(lsof -a -d cwd -c $1 -Fpn 2>/dev/null)}"; do
    case $line in
      p*) pid=${line#p} ;;
      n*) print -r -- "$pid"$'\t'"${line#n}" ;;
    esac
  done
}

# The package of Java <major>: a Homebrew cask (Eclipse Temurin) → REPLY = "cask temurin"
lotus_os_java_package() { REPLY="cask temurin" }

# Processes of this user that run in <dir> or below it → lines "pid<TAB>command line"
lotus_os_proc_in() {
  local dir=${1:A} line pid=
  (( $+commands[lsof] )) || return 1
  for line in "${(@f)$(lsof -a -u ${UID:-$(id -u)} -d cwd -Fpn 2>/dev/null)}"; do
    [[ $line == p* ]] && { pid=${line#p}; continue }
    [[ $line == n* && ( ${line#n} == $dir || ${line#n} == $dir/* ) ]] || continue
    print -r -- "$pid"$'\t'"$(ps -o args= -p $pid 2>/dev/null)"
  done
}

# Keeps the Mac awake for as long as the process <pid> runs
lotus_os_awake_while() { (( $+commands[caffeinate] )) && caffeinate -i -w $1 >/dev/null 2>&1 &! }

# ── Sandbox for plugins ───────────────────────────────────────

lotus_os_sandbox_available() { [[ -x /usr/bin/sandbox-exec ]] }

# The sandbox of a limited plugin (sandbox-exec): its own folder to read, its data folder and the temporary
# folder to write, nothing of the home folder or other disks, no keychain, no Apple Events (no controlling
# other apps), no internet unless the plugin says network = yes. Files given as extra arguments may be read too.
_lotus_os_sandbox_profile() {   # <dir> <data> <network yes|no> [files] → REPLY
  local q=$'"' tmp=${TMPDIR:-/tmp}
  REPLY="(version 1)
(allow default)
(allow file-write* (subpath $q${tmp:A}$q) (subpath \"/private/tmp\") (subpath \"/private/var/folders\"))
(deny file-read* (subpath $q${HOME:A}$q) (subpath \"/Volumes\"))
(deny file-write* (subpath $q${HOME:A}$q) (subpath \"/Volumes\"))
(allow file-read* (subpath $q${1:A}$q) (subpath $q${2:A}$q))
(allow file-write* (subpath $q${2:A}$q))
(deny process-exec (literal \"/usr/bin/security\") (literal \"/usr/bin/osascript\") (literal \"/usr/bin/sudo\") (literal \"/usr/bin/su\"))
(deny appleevent-send)
(deny mach-lookup (global-name \"com.apple.SecurityServer\") (global-name \"com.apple.securityd.xpc\"))"
  [[ $3 == yes ]] || REPLY+=$'\n(deny network*)'
  # a file the AI gave a tool (a path parameter – it asked the user already, like read_file): this one file to read
  local f
  for f in "${@[4,-1]}"; do
    [[ $f == /* && $f != *[\"\\]* ]] && REPLY+=$'\n'"(allow file-read* (literal $q${f:A}$q))"
  done
}

# lotus_os_sandbox_wrap <dir> <data> <network yes|no> [files the plugin may read…] → reply = the words that go in
# front of the program: sandbox-exec -p <profile>
lotus_os_sandbox_wrap() {
  _lotus_os_sandbox_profile "$@"
  reply=(/usr/bin/sandbox-exec -p $REPLY)
}
