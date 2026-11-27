# lotus – platform layer for Linux (loaded by lib/platform.zsh)
# Native Linux tools, in the order a normal desktop has them. Nothing here needs more than the system provides:
# when a program is missing the function returns 2 ("not possible here") and the command says what would help.

# ── Open things ───────────────────────────────────────────────

# A link or a path, in the default application, without waiting for it. Without a graphical session (an SSH login,
# a server) nothing is opened – xdg-open would start a text browser in this very terminal – and status 2 tells the
# command to print the link instead.
lotus_os_open() {
  _lotus_os_target "$1"
  local t=$REPLY
  if (( LOTUS_WSL )) && (( $+commands[wslview] )); then ( wslview -- "$t" >/dev/null 2>&1 & ); return 0; fi
  [[ $LOTUS_SESSION == tty && $LOTUS_WSL == 0 ]] && return 2
  if   (( $+commands[xdg-open] )); then ( xdg-open "$t" >/dev/null 2>&1 & )
  elif (( $+commands[gio] ));      then ( gio open "$t" >/dev/null 2>&1 & )
  elif (( $+commands[kde-open] )); then ( kde-open "$t" >/dev/null 2>&1 & )
  else return 2; fi
  return 0
}

# Shown in the file manager (D-Bus FileManager1, which GNOME Files, Dolphin, Thunar and Nemo answer), else its folder opened
lotus_os_reveal() {
  local p=${1:A}
  [[ -e $p ]] || return 1
  [[ $LOTUS_SESSION == tty && $LOTUS_WSL == 0 ]] && return 2
  if (( $+commands[gdbus] )) && gdbus call --session --dest org.freedesktop.FileManager1 --object-path /org/freedesktop/FileManager1 \
       --method org.freedesktop.FileManager1.ShowItems "['file://${p}']" "" >/dev/null 2>&1; then
    return 0
  fi
  lotus_os_open ${p:h}
}

# Installed apps → LOTUS_APPS[name]=desktop file (the first location wins: your own, then the system's, Flatpak, Snap)
# From the desktop entries of the XDG folders; entries that are hidden, not applications or have no name are left out.
lotus_os_apps() {
  setopt localoptions extendedglob
  typeset -gA LOTUS_APPS=()
  local -a dirs=(${XDG_DATA_HOME:-$HOME/.local/share}/applications)
  local d
  for d in ${(s.:.)${XDG_DATA_DIRS:-/usr/local/share:/usr/share}}; do dirs+=($d/applications); done
  dirs+=(/var/lib/flatpak/exports/share/applications ${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/exports/share/applications /var/lib/snapd/desktop/applications)
  local f line key name type hidden in
  for d in ${(u)dirs}; do
    for f in $d/*.desktop(N-.); do
      name= type= hidden=0 in=0
      for line in "${(@f)$(<$f)}"; do
        if [[ $line == \[*\] ]]; then [[ $line == '[Desktop Entry]' ]] && in=1 || { (( in )) && break; }; continue; fi
        (( in )) || continue
        case $line in
          Name=*)       name=${line#Name=} ;;
          Type=*)       type=${line#Type=} ;;
          NoDisplay=true|Hidden=true) hidden=1 ;;
        esac
      done
      [[ $type == Application && $hidden == 0 && -n $name ]] || continue
      [[ -z $LOTUS_APPS[$name] ]] && LOTUS_APPS[$name]=$f
    done
  done
}

# Starts an app from its desktop file (lotus_os_apps) – the launcher of the desktop first, then the Exec line
lotus_os_open_app() {
  local f=$1
  [[ -r $f ]] || return 1
  if (( $+commands[gio] )) && gio launch -- $f >/dev/null 2>&1; then return 0; fi
  if (( $+commands[gtk-launch] )) && gtk-launch ${f:t:r} >/dev/null 2>&1; then return 0; fi
  local line exec=
  for line in "${(@f)$(<$f)}"; do [[ $line == Exec=* && -z $exec ]] && exec=${line#Exec=}; done
  [[ -n $exec ]] || return 1
  # the field codes (%U, %f …) stand for files and links: none here, and %% is a percent sign
  exec=${exec//%%/@@PERCENT@@}
  exec=${exec//%[a-zA-Z]/}
  exec=${exec//@@PERCENT@@/%}
  local -a argv=(${(Q)${(z)exec}})
  (( ${#argv} )) || return 1
  ( nohup ${argv[@]} >/dev/null 2>&1 & )
}

# ── Clipboard ─────────────────────────────────────────────────
# Wayland: wl-clipboard · X11: xclip or xsel · WSL: the Windows clipboard. Without any of them status 2.

lotus_os_clip_copy() {
  if   [[ -n $WAYLAND_DISPLAY ]] && (( $+commands[wl-copy] )); then wl-copy
  elif [[ -n $DISPLAY ]] && (( $+commands[xclip] ));            then xclip -selection clipboard -in >/dev/null 2>&1
  elif [[ -n $DISPLAY ]] && (( $+commands[xsel] ));             then xsel --clipboard --input >/dev/null 2>&1
  elif (( LOTUS_WSL && $+commands[clip.exe] ));                 then clip.exe
  else cat >/dev/null; return 2; fi
}

lotus_os_clip_paste() {
  if   [[ -n $WAYLAND_DISPLAY ]] && (( $+commands[wl-paste] )); then wl-paste --no-newline 2>/dev/null
  elif [[ -n $DISPLAY ]] && (( $+commands[xclip] ));            then xclip -selection clipboard -out 2>/dev/null
  elif [[ -n $DISPLAY ]] && (( $+commands[xsel] ));             then xsel --clipboard --output 2>/dev/null
  elif (( LOTUS_WSL && $+commands[powershell.exe] ));           then powershell.exe -NoProfile -Command Get-Clipboard 2>/dev/null | tr -d '\r'
  else return 2; fi
}

# What the clipboard offers, as the targets (MIME types) it lists
_lotus_os_clip_targets() {
  if   [[ -n $WAYLAND_DISPLAY ]] && (( $+commands[wl-paste] )); then wl-paste --list-types 2>/dev/null
  elif [[ -n $DISPLAY ]] && (( $+commands[xclip] ));            then xclip -selection clipboard -t TARGETS -o 2>/dev/null
  else return 2; fi
}
# The clipboard in one MIME type, into a file (status 0 when it is not empty)
_lotus_os_clip_get() {   # <type> <file>
  if   [[ -n $WAYLAND_DISPLAY ]] && (( $+commands[wl-paste] )); then wl-paste --type "$1" >| "$2" 2>/dev/null
  elif [[ -n $DISPLAY ]] && (( $+commands[xclip] ));            then xclip -selection clipboard -t "$1" -o >| "$2" 2>/dev/null
  else return 2; fi
  [[ -s $2 ]]
}

# What the clipboard holds → REPLY: "files <n>" (copied in the file manager), "image <w>x<h>" or "none"
lotus_os_clip_peek() {
  REPLY=none
  local targets tmp=$LOTUS_CACHE/.clip-peek.$$
  targets=$(_lotus_os_clip_targets) || return 0
  if [[ $targets == *text/uri-list* ]] && _lotus_os_clip_get text/uri-list $tmp; then
    local -a uris=(${(M)${(f)"$(<$tmp)"}:#file://*})
    rm -f -- $tmp
    (( ${#uris} )) && { REPLY="files ${#uris}"; return 0 }
  fi
  if [[ $targets == *image/png* ]] && zf_mkdir -p ${tmp:h} 2>/dev/null && _lotus_os_clip_get image/png $tmp; then
    local size=
    lotus_os_png_size $tmp && size=$REPLY
    rm -f -- $tmp
    REPLY="image ${size:-?x?}"
    return 0
  fi
  rm -f -- $tmp 2>/dev/null
  REPLY=none
}

# The clipboard as files: the files that were copied, or an image saved as PNG to <out.png> – one path per line
lotus_os_clip_save() {
  local out=$1 tmp=$LOTUS_CACHE/.clip-save.$$ targets
  targets=$(_lotus_os_clip_targets) || return 2
  zf_mkdir -p ${tmp:h} 2>/dev/null
  if [[ $targets == *text/uri-list* ]] && _lotus_os_clip_get text/uri-list $tmp; then
    local uri p
    local -a found=()
    for uri in ${(M)${(f)"$(<$tmp)"}:#file://*}; do
      p=${uri#file://}; p=${p%%$'\r'}
      p=${(g::)${p//\%/\\x}}                      # %20 → a space
      [[ -e $p ]] && found+=($p)
    done
    rm -f -- $tmp
    (( ${#found} )) && { print -rl -- $found; return 0 }
  fi
  if [[ $targets == *image/png* ]] && _lotus_os_clip_get image/png $out; then
    rm -f -- $tmp
    print -r -- $out
    return 0
  fi
  rm -f -- $tmp
  return 1
}

# ── Notifications, keep awake ─────────────────────────────────

lotus_os_notify() {   # <title> <text>
  if (( $+commands[notify-send] )); then notify-send -a Lotus -- "$1" "$2" >/dev/null 2>&1
  elif (( $+commands[gdbus] )); then
    gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
      --method org.freedesktop.Notifications.Notify Lotus 0 "" "$1" "$2" "[]" "{}" 5000 >/dev/null 2>&1
  else return 2; fi
}

# Keeps the system awake for <seconds> (0 = until stopped): an inhibitor lock of systemd (idle and sleep), or the
# one of the GNOME session. The process carries LOTUS_AWAKE=1 in its environment, so Lotus can tell its own process
# from another one that got the same number. Without a session bus or logind (a container) it fails – status 1.
# → REPLY = its process id
lotus_os_awake_start() {
  local -i secs=$1
  (( secs > 0 )) || secs=2147483647
  local -a cmd
  if   (( $+commands[systemd-inhibit] )); then cmd=(systemd-inhibit --what=idle:sleep --who=Lotus --why="Keep awake" --mode=block sleep $secs)
  elif (( $+commands[gnome-session-inhibit] )); then cmd=(gnome-session-inhibit --inhibit idle:suspend --reason "Lotus keeps the system awake" sleep $secs)
  else return 2; fi
  LOTUS_AWAKE=1 nohup $cmd >/dev/null 2>&1 &!
  REPLY=$!
  sleep 0.3
  kill -0 $REPLY 2>/dev/null
}
lotus_os_awake_name() { REPLY=systemd-inhibit }
lotus_os_awake_is() {
  kill -0 $1 2>/dev/null || return 1
  [[ -r /proc/$1/environ ]] && tr '\0' '\n' < /proc/$1/environ 2>/dev/null | grep -qx 'LOTUS_AWAKE=1'
}
lotus_os_awake_stop() {
  pkill -TERM -P $1 2>/dev/null
  kill $1 2>/dev/null
}

# ── Sound ─────────────────────────────────────────────────────

# The volume and mute state of the default output, whichever sound server runs: PipeWire (wpctl), PulseAudio (pactl),
# else ALSA (amixer) → LOTUS_VOL = percent, LOTUS_MUTED = 0|1
typeset -gi LOTUS_VOL=0 LOTUS_MUTED=0
_lotus_os_vol_get() {
  local out
  if (( $+commands[wpctl] )); then
    out=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null) || return 1
    [[ $out == Volume:\ * ]] || return 1
    LOTUS_VOL=$(( ${${out#Volume: }%% *} * 100 + 0.5 ))
    [[ $out == *MUTED* ]] && LOTUS_MUTED=1 || LOTUS_MUTED=0
  elif (( $+commands[pactl] )); then
    out=$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null) || return 1
    [[ $out =~ '([0-9]+)%' ]] || return 1
    LOTUS_VOL=$match[1]
    [[ $(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null) == *yes* ]] && LOTUS_MUTED=1 || LOTUS_MUTED=0
  elif (( $+commands[amixer] )); then
    out=$(amixer sget Master 2>/dev/null) || return 1
    [[ $out =~ '\[([0-9]+)%\]' ]] || return 1
    LOTUS_VOL=$match[1]
    [[ $out == *'[off]'* ]] && LOTUS_MUTED=1 || LOTUS_MUTED=0
  else
    return 2
  fi
}
_lotus_os_vol_set() {   # <percent>
  local -i v=$1
  (( v > 100 )) && v=100
  (( v < 0 )) && v=0
  if   (( $+commands[wpctl] )); then wpctl set-volume @DEFAULT_AUDIO_SINK@ ${v}% >/dev/null 2>&1
  elif (( $+commands[pactl] )); then pactl set-sink-volume @DEFAULT_SINK@ ${v}% >/dev/null 2>&1
  elif (( $+commands[amixer] )); then amixer -q sset Master ${v}% >/dev/null 2>&1
  else return 2; fi
}
_lotus_os_mute_toggle() {
  if   (( $+commands[wpctl] )); then wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle >/dev/null 2>&1
  elif (( $+commands[pactl] )); then pactl set-sink-mute @DEFAULT_SINK@ toggle >/dev/null 2>&1
  elif (( $+commands[amixer] )); then amixer -q sset Master toggle >/dev/null 2>&1
  else return 2; fi
}

# lotus_os_volume up|down|mute → REPLY = the volume in percent (up, down) or 1 = muted / 0 = sound on (mute)
lotus_os_volume() {
  local -i st
  _lotus_os_vol_get; st=$?
  (( st )) && return $st
  case $1 in
    up)   _lotus_os_vol_set $(( LOTUS_VOL + 6 )) || return $?; _lotus_os_vol_get; REPLY=$LOTUS_VOL ;;
    down) _lotus_os_vol_set $(( LOTUS_VOL - 6 )) || return $?; _lotus_os_vol_get; REPLY=$LOTUS_VOL ;;
    mute) _lotus_os_mute_toggle || return $?; _lotus_os_vol_get; REPLY=$LOTUS_MUTED ;;
    *)    return 2 ;;
  esac
}

# Media control of the player that plays, over MPRIS: playerctl, else a D-Bus call to the first player there is
#   lotus_os_media play|pause|next|previous|repeat <player id> <player name>
#   status 0 done · 1 failed (LOTUS_OS_MSG = title, detail, hint) · 2 this system cannot do it
typeset -ga LOTUS_OS_MSG=()
_lotus_os_mpris_player() {   # → REPLY = the D-Bus name of a player
  REPLY=
  if (( $+commands[busctl] )); then REPLY=$(busctl --user list --no-legend 2>/dev/null | awk '$1 ~ /^org\.mpris\.MediaPlayer2\./ { print $1; exit }')
  elif (( $+commands[gdbus] )); then
    REPLY=$(gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.ListNames 2>/dev/null | tr -d "[]()',@" | tr ' ' '\n' | grep -m1 '^org\.mpris\.MediaPlayer2\.')
  fi
  [[ -n $REPLY ]]
}
lotus_os_media() {
  local action=$1 id=$2 player=$3 verb
  LOTUS_OS_MSG=()
  if (( $+commands[playerctl] )); then
    local -a pc=(playerctl)
    [[ -n $id && $id != null ]] && pc+=(-p $id)
    case $action in
      play|pause|next|previous) "${pc[@]}" $action >/dev/null 2>&1 || { LOTUS_OS_MSG=("The player did not respond" "${player:-It} did not accept the command." "Is a player running that supports MPRIS?"); return 1 } ;;
      repeat)
        local cur=$("${pc[@]}" loop 2>/dev/null)
        [[ -n $cur ]] || return 2
        if [[ $cur == None ]]; then "${pc[@]}" loop Playlist >/dev/null 2>&1; REPLY="Repeat on  ${player:-player}"
        else "${pc[@]}" loop None >/dev/null 2>&1; REPLY="Repeat off  ${player:-player}"; fi
        return 0 ;;
      *) return 2 ;;
    esac
    REPLY=${player:-player}
    return 0
  fi
  [[ $action == repeat ]] && return 2
  _lotus_os_mpris_player || { LOTUS_OS_MSG=("No player to control" "Lotus controls players over MPRIS and found none." "Install playerctl for more: your package manager has it."); return 1 }
  local name=$REPLY
  case $action in play) verb=Play ;; pause) verb=Pause ;; next) verb=Next ;; previous) verb=Previous ;; *) return 2 ;; esac
  if (( $+commands[busctl] )); then busctl --user call $name /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player $verb >/dev/null 2>&1 || return 1
  else gdbus call --session --dest $name --object-path /org/mpris/MediaPlayer2 --method org.mpris.MediaPlayer2.Player.$verb >/dev/null 2>&1 || return 1; fi
  REPLY=${player:-$name}
}

# ── Secrets ───────────────────────────────────────────────────
# The desktop keyring (Secret Service: GNOME Keyring, KWallet) through secret-tool. A system without a running
# keyring keeps the secret in a file only you can read (mode 600 in a folder with mode 700) – LOTUS_OS_SECRET_WHERE
# says which one was used, so the command can tell the user.

typeset -g LOTUS_OS_SECRET_WHERE=
_lotus_os_secret_file() { REPLY=$LOTUS_CONF/secrets/${1//[^[:alnum:]._-]/_} }

lotus_os_secret_get() {
  REPLY=
  if (( $+commands[secret-tool] )); then
    REPLY=$(secret-tool lookup lotus-service "$1" 2>/dev/null)
    [[ -n $REPLY ]] && { LOTUS_OS_SECRET_WHERE=keyring; return 0 }
  fi
  _lotus_os_secret_file "$1"
  [[ -r $REPLY ]] && { local f=$REPLY; REPLY=$(<$f); LOTUS_OS_SECRET_WHERE=file; [[ -n $REPLY ]]; return }
  REPLY=
  return 1
}

# lotus_os_secret_set <service> <value>
lotus_os_secret_set() {
  [[ $2 == [[:alnum:]._~+/=:-]## ]] || return 1
  LOTUS_OS_SECRET_WHERE=
  if (( $+commands[secret-tool] )) && print -rn -- "$2" | secret-tool store --label="Lotus $1" lotus-service "$1" >/dev/null 2>&1; then
    LOTUS_OS_SECRET_WHERE=keyring
    return 0
  fi
  _lotus_os_secret_file "$1"
  local f=$REPLY
  ( umask 077; zf_mkdir -p ${f:h} && chmod 700 ${f:h} && print -rn -- "$2" >| $f ) 2>/dev/null || return 1
  chmod 600 $f 2>/dev/null
  LOTUS_OS_SECRET_WHERE=file
}

lotus_os_secret_del() {
  local gone=1
  (( $+commands[secret-tool] )) && secret-tool clear lotus-service "$1" >/dev/null 2>&1 && gone=0
  _lotus_os_secret_file "$1"
  [[ -e $REPLY ]] && rm -f -- $REPLY && gone=0
  return $gone
}

# What a message calls the place where secrets are kept: the desktop keyring when there is one, else the file
lotus_os_secret_store_name() {
  if (( $+commands[secret-tool] )) && [[ -n $DBUS_SESSION_BUS_ADDRESS ]]; then REPLY="your desktop keyring"
  else REPLY="a file only you can read (${LOTUS_CONF/#$HOME/~}/secrets)"; fi
}

# ── This computer ─────────────────────────────────────────────

lotus_os_cpu_count() {
  if   (( $+commands[nproc] ));   then REPLY=$(nproc 2>/dev/null)
  elif (( $+commands[getconf] )); then REPLY=$(getconf _NPROCESSORS_ONLN 2>/dev/null); fi
  [[ $REPLY == <-> ]] || REPLY=4
}
lotus_os_mem_bytes() {
  local line kb=0
  for line in "${(@f)$(</proc/meminfo)}"; do [[ $line == MemTotal:* ]] && { kb=${${line#MemTotal:}//[^0-9]/}; break }; done 2>/dev/null
  REPLY=$(( kb * 1024 ))
}
lotus_os_chip() {
  REPLY=
  if (( $+commands[lscpu] )); then REPLY=$(lscpu 2>/dev/null | awk -F: '/^Model name/ { gsub(/^[ \t]+/, "", $2); print $2; exit }'); fi
  if [[ -z $REPLY && -r /proc/cpuinfo ]]; then
    local line
    for line in "${(@f)$(</proc/cpuinfo)}"; do [[ $line == (model name|Model|Hardware)[[:space:]]#:* ]] && { REPLY=${line#*: }; break }; done
  fi
  [[ -n $REPLY ]]
}
lotus_os_fullname() {
  REPLY=
  (( $+commands[getent] )) || return 1
  local rec=$(getent passwd ${USER:-$(id -un)} 2>/dev/null)
  local -a f=("${(@s/:/)rec}")
  REPLY=${${f[5]}%%,*}
  [[ -n $REPLY ]]
}
lotus_os_lan_ip() {
  REPLY=
  if (( $+commands[ip] )); then REPLY=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{ for (i = 1; i < NF; i++) if ($i == "src") { print $(i + 1); exit } }'); fi
  [[ -z $REPLY ]] && (( $+commands[hostname] )) && REPLY=${$(hostname -I 2>/dev/null)%% *}
  [[ -n $REPLY ]]
}

# ── Files and folders ─────────────────────────────────────────

# To the trash of the desktop (it can be put back). Status 2 when this system has no trash that a script can use –
# the caller must then ask before it deletes anything for good.
lotus_os_trash() {
  local f
  LOTUS_OS_TRASHED=
  for f in "$@"; do
    if   [[ $LOTUS_TRASH == own ]];    then _lotus_os_trash_xdg $f || return $?       # LOTUS_TRASH=own: Lotus' own trash, whatever is installed
    elif (( $+commands[gio] ));        then gio trash -- $f 2>/dev/null || return 1
    elif (( $+commands[trash-put] ));  then trash-put -- $f 2>/dev/null || return 1
    elif (( $+commands[kioclient5] )); then kioclient5 move $f trash:/ 2>/dev/null || return 1
    else _lotus_os_trash_xdg $f || return $?; fi
  done
}

# The freedesktop.org Trash, written by Lotus itself when no trash program is installed – the one every file manager,
# gio and trash-cli share: the file goes to ~/.local/share/Trash/files and a .trashinfo remembers where it came from, so
# it can be put back. Only the trash of the home disk: a file on another disk is not copied over (status 3).
#   _lotus_os_trash_xdg <path>     LOTUS_OS_TRASHED = where it is now
_lotus_os_trash_xdg() {
  local src=${1:A} home=${XDG_DATA_HOME:-$HOME/.local/share}/Trash name dest n=1 enc= ch
  [[ -e $1 || -L $1 ]] || return 1
  zf_mkdir -p -m 700 $home/files $home/info 2>/dev/null || return 1
  local -A a b
  zstat -H a $src 2>/dev/null; zstat -H b $home/files 2>/dev/null
  [[ $a[device] == $b[device] ]] || return 3
  name=${src:t}; dest=$name
  while [[ -e $home/files/$dest || -L $home/files/$dest || -e $home/info/$dest.trashinfo ]]; do (( n++ )); dest=$name.$n; done
  # the path as the specification wants it: percent-encoded bytes
  {
    local LC_ALL=C
    for ch in ${(s::)src}; do
      if [[ $ch == [A-Za-z0-9/._~-] ]]; then enc+=$ch; else enc+=$(printf '%%%02X' "'$ch"); fi
    done
  }
  print -r -- "[Trash Info]"$'\n'"Path=$enc"$'\n'"DeletionDate=$(date +%Y-%m-%dT%H:%M:%S)" >| $home/info/$dest.trashinfo 2>/dev/null || return 1
  if command mv -- $src $home/files/$dest 2>/dev/null; then
    LOTUS_OS_TRASHED=$home/files/$dest
    return 0
  fi
  # still there: whatever was copied goes again, nothing else changes
  [[ -e $src ]] && rm -rf -- $home/files/$dest
  rm -f -- $home/info/$dest.trashinfo
  return 1
}

# perl for lib/cover.pl
typeset -g LOTUS_PERL=${commands[perl]:-}

# What kind of picture a file is, by its first bytes: jpeg, png, gif, webp or bmp → REPLY. Nothing else is opened: a cover
# can come from a web page (browsers hand a page's artwork to the media controls), and image programs read far more
# kinds of files than a cover is.
_lotus_os_image_kind() {
  local hex
  hex=$(od -An -tx1 -N12 -- "$1" 2>/dev/null | tr -d ' \n')
  REPLY=
  case $hex in
    ffd8ff*)                   REPLY=jpeg ;;
    89504e470d0a1a0a*)         REPLY=png ;;
    47494638*)                 REPLY=gif ;;
    52494646????????57454250*) REPLY=webp ;;
    424d*)                     REPLY=bmp ;;
  esac
  [[ -n $REPLY ]]
}

# ImageMagick with limits, reading only the kind of file it was told it is
_lotus_os_magick() {
  local -a im=(magick)
  (( $+commands[magick] )) || im=(convert)
  (( $+commands[timeout] )) && im=(timeout 20 $im)
  $im -limit memory 256MiB -limit map 256MiB -limit disk 1GiB -limit area 64MP -limit time 15 "$@" >/dev/null 2>&1
}

# A picture as a 24-bit BMP, no bigger than <px> × <px> (lib/cover.pl turns it into terminal art). ImageMagick, else ffmpeg.
lotus_os_image_bmp() {   # <src> <px> <out.bmp>
  local src=$1
  [[ $src == -* ]] && src=./$src
  _lotus_os_image_kind $src || return 1
  local kind=$REPLY
  if   (( $+commands[magick] || $+commands[convert] )); then _lotus_os_magick ${kind:u}:"$src" -resize ${2}x${2} BMP3:"$3"
  elif (( $+commands[ffmpeg] )); then
    ffmpeg -v error -y -i "$src" -frames:v 1 -vf "scale='min($2,iw)':'min($2,ih)':force_original_aspect_ratio=decrease" -pix_fmt bgr24 -f image2 -c:v bmp "$3" >/dev/null 2>&1
  else return 2; fi
  [[ -s $3 ]]
}

# The middle square of a picture as a PNG of <size> × <size> (status 2: no image program)
lotus_os_image_square() {   # <src> <size> <out.png>
  local src=$1
  [[ $src == -* ]] && src=./$src
  _lotus_os_image_kind $src || return 1
  local kind=$REPLY
  if   (( $+commands[magick] || $+commands[convert] )); then _lotus_os_magick ${kind:u}:"$src" -resize ${2}x${2}^ -gravity center -extent ${2}x${2} PNG:"$3"
  elif (( $+commands[ffmpeg] )); then
    ffmpeg -v error -y -i "$src" -frames:v 1 -vf "crop='min(iw,ih)':'min(iw,ih)',scale=$2:$2" -f image2 -c:v png "$3" >/dev/null 2>&1
  else return 2; fi
  [[ -s $3 ]]
}

# What plays, and its cover → reply = (status title artist album cover-file); 1 = nothing. Over MPRIS (playerctl).
# The cover is the picture the player names: a file on this computer, or an https address, which is fetched once
# (kept per address in the cache) – nothing else. The cover file handed out is a new copy named ff_… that the
# caller removes (lotus_cover in lib/art.zsh).
lotus_os_media_cover() {
  setopt localoptions extendedglob
  reply=()
  (( $+commands[playerctl] )) || return 1
  local out
  out=$(playerctl metadata --format $'{{status}}\n{{title}}\n{{artist}}\n{{album}}\n{{mpris:artUrl}}' 2>/dev/null) || return 1
  local -a v=("${(@f)out}")
  (( ${#v} >= 1 )) || return 1
  local url=${v[5]} src= tmp
  case $url in
    file://*)
      src=${url#file://}
      src=${(g::)${src//\%/\\x}}                    # %41 → \x41 → A
      ;;
    https://*)
      local -a sum=(${=$(print -rn -- $url | cksum)})
      local dir=$LOTUS_CACHE/covers
      local cache=$dir/src-$sum[1]
      if [[ ! -s $cache ]] && (( $+commands[curl] )); then
        zf_mkdir -p $dir
        curl -fsSL -m 6 --max-filesize 8000000 --proto '=https' --proto-redir '=https' -o $cache.$$ -- $url 2>/dev/null \
          && zf_mv -f $cache.$$ $cache || rm -f -- $cache.$$
        local -a old=($dir/src-*(NOm[41,-1]))      # keep the newest 40
        (( ${#old} )) && rm -f -- $old
      fi
      [[ -s $cache ]] && src=$cache
      ;;
  esac
  local state=${v[1]:-Stopped}
  if [[ -n $src && -f $src && -r $src ]]; then
    tmp=$(mktemp "${TMPDIR:-/tmp}/ff_XXXXXXXX") || return 1
    mv -- $tmp $tmp.img && tmp=$tmp.img || { rm -f -- $tmp; return 1 }      # lotus_cover only removes ff_<name>.<ext>
    cp -- $src $tmp 2>/dev/null || { rm -f -- $tmp; return 1 }
    reply=("$state" "${v[2]}" "${v[3]}" "${v[4]}" "$tmp")
  else
    reply=("$state" "${v[2]}" "${v[3]}" "${v[4]}" "")
  fi
}

# A folder picker (zenity or kdialog) → REPLY = the path; status 1 when cancelled, 2 without a desktop or a picker
lotus_os_choose_folder() {   # <prompt> <start folder>
  [[ $LOTUS_SESSION == tty ]] && return 2
  if   (( $+commands[zenity] ));  then REPLY=$(zenity --file-selection --directory --title="$1" --filename="${2:-$HOME}/" 2>/dev/null) || return 1
  elif (( $+commands[kdialog] )); then REPLY=$(kdialog --getexistingdirectory "${2:-$HOME}" --title "$1" 2>/dev/null) || return 1
  else return 2; fi
  REPLY=${REPLY%/}
  [[ -n $REPLY ]]
}

# "WxH" of an image file → REPLY (a PNG without any program; else ImageMagick, vips, or what `file` says)
lotus_os_image_info() {
  local out
  lotus_os_png_size "$1" && return 0
  if   (( $+commands[magick] ));   then out=$(magick identify -format '%wx%h' -- "$1[0]" 2>/dev/null)
  elif (( $+commands[identify] )); then out=$(identify -format '%wx%h' -- "$1[0]" 2>/dev/null)
  elif (( $+commands[vipsheader] )); then out="$(vipsheader -f width -- "$1" 2>/dev/null)x$(vipsheader -f height -- "$1" 2>/dev/null)"
  elif (( $+commands[file] )); then
    [[ $(file -b -- "$1" 2>/dev/null) =~ '([0-9]+) ?x ?([0-9]+)' ]] && out="$match[1]x$match[2]"
  fi
  [[ $out == <->x<-> ]] || return 1
  REPLY=$out
}

# ── Folder icons ──────────────────────────────────────────────
# A picture as the icon of a folder. Desktop file managers keep it in one of two places:
#   gio    GNOME Files, Cinnamon (Nemo), MATE (Caja), XFCE (Thunar), Budgie, Pantheon: the attribute metadata::custom-icon of
#          the folder, which GVfs stores for the user – so it needs the gio program and GVfs' metadata service, which those
#          desktops have. The folder itself is not touched.
#   file   KDE Plasma (Dolphin and the desktop) and LXQt: a ".directory" file in the folder, "Icon=<picture>" in [Desktop Entry]
# Both only point to the picture, so Lotus keeps a copy of its own in $LOTUS_DATA/icons – the original may be moved or deleted.
# LOTUS_ICON_METHOD=gio|file chooses the way when the desktop is not one of those (and in the tests).

# The Desktop folder of this user, from xdg-user-dirs (it may be called Schreibtisch, Bureau …) → REPLY
# Status 1: there is none – REPLY is the folder that was expected, or empty when xdg-user-dirs says there is no desktop folder
lotus_os_desktop() {
  local conf=${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs line d=${XDG_DESKTOP_DIR-}
  if [[ -z $d && -r $conf ]]; then
    for line in "${(@f)$(<$conf)}"; do
      [[ $line == XDG_DESKTOP_DIR=* ]] && d=${(Q)${line#XDG_DESKTOP_DIR=}}
    done
    d=${d//\$HOME/$HOME}
  fi
  if [[ -z $d ]]; then d=$HOME/Desktop
  elif [[ $d != /* || ${d%/} == ${HOME%/} ]]; then REPLY=; return 1       # "$HOME/" is how xdg-user-dirs says: no desktop folder
  fi
  REPLY=${d%/}
  [[ -d $REPLY ]]
}

# What the drop zone says a picture may be
lotus_os_folder_icon_types() {
  REPLY="PNG · JPEG · SVG · GIF"
  (( $+commands[magick] || $+commands[convert] )) && REPLY+=" · WebP · HEIC · TIFF"
}

# Which way this desktop keeps folder icons → REPLY = gio | file
_lotus_os_icon_method() {
  case ${LOTUS_ICON_METHOD:-} in gio|file) REPLY=$LOTUS_ICON_METHOD; return 0 ;; esac
  case $LOTUS_DESKTOP in
    kde|plasma|lxqt) REPLY=file ;;
    *)               REPLY=gio ;;
  esac
}

# Does GVfs keep what gio gives it? Tried once on a folder of its own (a system without a desktop session, or without GVfs,
# says "not supported"). Cached for the process.
typeset -gi _LOTUS_ICON_GIO=-1
_lotus_os_gio_ready() {
  (( _LOTUS_ICON_GIO >= 0 )) && return $(( 1 - _LOTUS_ICON_GIO ))
  _LOTUS_ICON_GIO=0
  (( $+commands[gio] )) || return 1
  local dir
  dir=$(mktemp -d "${TMPDIR:-/tmp}/lotus-gio.XXXXXX" 2>/dev/null) || return 1
  if gio set -t string -- $dir metadata::lotus-probe 1 >/dev/null 2>&1 &&
     [[ $(gio info -a metadata::lotus-probe -- $dir 2>/dev/null) == *"metadata::lotus-probe: 1"* ]]; then
    _LOTUS_ICON_GIO=1
  fi
  gio set -t unset -- $dir metadata::lotus-probe >/dev/null 2>&1
  rm -rf -- ${dir:?}
  (( _LOTUS_ICON_GIO ))
}

# file:///… for a path: every byte that is not plain is written as %XX (what GIO expects) → REPLY
_lotus_os_file_uri() {
  local LC_ALL=C ch h enc=
  for ch in ${(s::)1}; do
    if [[ $ch == [A-Za-z0-9/._~-] ]]; then enc+=$ch; else printf -v h '%%%02X' "'$ch"; enc+=$h; fi
  done
  REPLY=file://$enc
}

# What kind of picture a file is, by its first bytes (the extension can be wrong) → REPLY: png jpeg gif bmp webp tiff ico
# icns heic avif svg, or nothing
_lotus_os_icon_kind() {
  local hex
  REPLY=
  hex=$(od -An -tx1 -N16 -- "$1" 2>/dev/null | tr -d ' \n')
  case $hex in
    89504e470d0a1a0a*)         REPLY=png ;;
    ffd8ff*)                   REPLY=jpeg ;;
    47494638*)                 REPLY=gif ;;
    424d*)                     REPLY=bmp ;;
    52494646????????57454250*) REPLY=webp ;;
    49492a00*|4d4d002a*)       REPLY=tiff ;;
    0000010000*)               ;;                          # an icon file that holds no icon
    00000100*)                 REPLY=ico ;;
    69636e73*)                 REPLY=icns ;;
    ????????66747970(68656963|68656978|68657663|68657678|6865696d|68656973|6d696631|6d736631)*) REPLY=heic ;;
    ????????66747970(61766966|61766973)*) REPLY=avif ;;
    *) head -c 4096 -- "$1" 2>/dev/null | grep -aqi '<svg' && REPLY=svg ;;
  esac
  [[ -n $REPLY ]]
}

# Lotus' own copy of the picture, named by what is in it (the same picture for many folders is kept once) → REPLY = its path
# A PNG, JPEG, GIF, BMP or SVG that is not big is copied as it is; everything else becomes a PNG of at most 512 pixels, with
# ImageMagick. Status 1: LOTUS_OS_MSG says why.
_lotus_os_icon_store() {   # <picture>
  local src=$1 kind sum dest tmp dir=$LOTUS_DATA/icons
  local -i size=0 im=0
  local -a st
  LOTUS_OS_MSG=()
  _lotus_os_icon_kind $src || {
    LOTUS_OS_MSG=("Lotus cannot use this picture" "${src:t} is not a PNG, JPEG, SVG, GIF, BMP, WebP, TIFF, ICO, ICNS or HEIC picture." "Pick another picture.")
    return 1
  }
  kind=$REPLY
  zstat -A st +size -- $src 2>/dev/null && size=$st[1]
  (( $+commands[magick] || $+commands[convert] )) && im=1
  lotus_os_hash 256 $src || { REPLY=${$(cksum < $src)%% *}; }
  sum=${REPLY[1,16]}
  zf_mkdir -p $dir 2>/dev/null || { LOTUS_OS_MSG=("Lotus cannot keep the picture" "${dir/#$HOME/~} cannot be written." "Check the rights of that folder."); return 1 }
  tmp=$dir/.new.$$
  if [[ $kind == svg ]] || { [[ $kind == (png|jpeg|gif|bmp) ]] && (( size <= 2097152 || ! im )) }; then
    dest=$dir/$sum.${kind/jpeg/jpg}
    [[ -s $dest ]] || { cp -- $src $tmp && zf_mv -f $tmp $dest } 2>/dev/null || { rm -f -- $tmp; [[ -s $dest ]] || { LOTUS_OS_MSG=("Lotus cannot keep the picture" "Copying it to ${dir/#$HOME/~} failed." "Is the disk full?"); return 1 } }
  elif (( im )); then
    dest=$dir/$sum.png
    if [[ ! -s $dest ]]; then
      _lotus_os_magick ${kind:u}:"${src}[0]" -auto-orient -resize '512x512>' -strip PNG:"$tmp" && [[ -s $tmp ]] && zf_mv -f $tmp $dest 2>/dev/null
      if [[ ! -s $dest ]]; then
        rm -f -- $tmp
        LOTUS_OS_MSG=("ImageMagick could not read this picture" "${src:t} is a ${kind:u} picture that it cannot turn into a PNG." "Save it as a PNG or JPEG and use that one.")
        return 1
      fi
    fi
  else
    lotus_pkg_hint magick
    LOTUS_OS_MSG=("This picture needs ImageMagick" "A ${kind:u} picture is turned into a PNG first, and no image program is installed." "$REPLY   –   or use a PNG, JPEG or SVG picture.")
    return 1
  fi
  REPLY=$dest
}

# The .directory file of a folder (KDE, LXQt): the key Icon in [Desktop Entry]; every other line stays as it is, blank lines
# too. "unset" takes the key away, the heading with it when nothing else is in that group, and the whole file when nothing
# else is in it – it was only there for the icon. Status 1: it could not be written.
_lotus_os_dotdirectory() {   # set <folder> <picture> | unset <folder>
  local mode=$1 file=$2/.directory line
  local -a lines=() out=() held=()
  local -i in=0 seen=0 keep=0
  [[ $mode == unset && ! -e $file ]] && return 0
  [[ -r $file ]] && lines=("${(@f)$(<$file)}")
  # (every append is quoted: an empty line must not vanish)
  for line in "${lines[@]}"; do
    if [[ $line == '['*']' ]]; then
      in=0 held=()                                 # a group that stayed empty goes with its heading
      if [[ $line == '[Desktop Entry]' ]]; then
        in=1
        if [[ $mode == set ]]; then
          out+=("$line")
          (( seen )) || out+=("Icon=$3")
        else
          held=("$line")
        fi
        seen=1
        continue
      fi
    fi
    if (( in )); then
      [[ $line == Icon=* ]] && continue
      if (( ${#held} )); then
        if [[ -z ${line//[[:space:]]/} ]]; then held+=("$line"); continue; fi
        out+=("${held[@]}"); held=()
      fi
    fi
    out+=("$line")
  done
  if [[ $mode == set ]]; then
    (( seen )) || out=("[Desktop Entry]" "Icon=$3" "${out[@]}")
  else
    for line in "${out[@]}"; do [[ -z ${line//[[:space:]]/} ]] || { keep=1; break }; done
    (( keep )) || { rm -f -- $file; return }
  fi
  { print -r -- "${(F)out}" >| $file.lotus.$$ && zf_mv -f $file.lotus.$$ $file } 2>/dev/null || { rm -f -- $file.lotus.$$; return 1 }
}

# A picture as the icon of a folder → status 0 done · 1 failed (LOTUS_OS_MSG = title, detail, hint) · 2 not possible here
lotus_os_folder_icon_set() {   # <folder> <picture>
  local folder=${1:A} method err
  LOTUS_OS_MSG=()
  _lotus_os_icon_method; method=$REPLY
  if [[ $method == gio ]]; then
    (( $+commands[gio] )) || return 2
    _lotus_os_gio_ready || {
      lotus_pkg_hint gvfs
      LOTUS_OS_MSG=("The icon service of your desktop is not running" "gio is installed, but GVfs does not keep what it is given – a desktop session has it running." "In a desktop window: $REPLY")
      return 1
    }
  elif [[ ! -w $folder ]]; then
    LOTUS_OS_MSG=("Lotus cannot write into this folder" "${folder/#$HOME/~} is locked." "KDE keeps the icon in a small file inside the folder.")
    return 1
  fi
  _lotus_os_icon_store "$2" || return 1
  local stored=$REPLY
  case $method in
    gio)
      _lotus_os_file_uri $stored
      err=$(gio set -t string -- $folder metadata::custom-icon $REPLY 2>&1) || {
        err=${err%%$'\n'*}                           # (the first line)
        LOTUS_OS_MSG=("Your desktop did not take the icon" "${err:-gio said no.}" "Is a desktop session running? GNOME Files, Nemo, Caja and Thunar keep icons through GVfs.")
        return 1
      } ;;
    file)
      _lotus_os_dotdirectory set $folder $stored || { LOTUS_OS_MSG=("Lotus cannot write into this folder" "The .directory file could not be written." "Is the folder locked?"); return 1 } ;;
  esac
  return 0
}

# The normal icon again → status 0 · 1 failed (LOTUS_OS_MSG) · 2 not possible here
lotus_os_folder_icon_reset() {   # <folder>
  local folder=${1:A} method err
  LOTUS_OS_MSG=()
  _lotus_os_icon_method; method=$REPLY
  case $method in
    gio)
      (( $+commands[gio] )) || return 2
      err=$(gio set -t unset -- $folder metadata::custom-icon 2>&1) || {
        err=${err%%$'\n'*}
        LOTUS_OS_MSG=("Your desktop did not take the icon away" "${err:-gio said no.}" "Is a desktop session running?")
        return 1
      } ;;
    file)
      _lotus_os_dotdirectory unset $folder || { LOTUS_OS_MSG=("Lotus cannot write into this folder" "The .directory file could not be changed." "Is the folder locked?"); return 1 } ;;
  esac
  return 0
}

# Does the folder have a picture of its own?
lotus_os_folder_icon_has() {   # <folder>
  _lotus_os_icon_method
  case $REPLY in
    gio)  (( $+commands[gio] )) && [[ $(gio info -a metadata::custom-icon -- ${1:A} 2>/dev/null) == *"metadata::custom-icon: "* ]] ;;
    file) [[ -r $1/.directory ]] && grep -q -- '^Icon=' $1/.directory 2>/dev/null ;;
  esac
}

# What the feature needs, and whether this system has it → reply = rows "status|what|detail|how to fix it" with the status ok,
# warn (works, but …) or fail; the status of the function is 1 when a row failed.
lotus_os_folder_icon_needs() {
  local -a rows=()                       # (lotus_pkg_hint uses reply itself)
  local -i bad=0
  local method desk=${LOTUS_DESKTOP:-none} name fm d hint
  _lotus_os_icon_method; method=$REPLY
  case $desk in
    gnome|ubuntu|unity)  name=GNOME fm="GNOME Files" ;;
    budgie)              name=Budgie fm="GNOME Files" ;;
    x-cinnamon|cinnamon) name=Cinnamon fm=Nemo ;;
    mate)                name=MATE fm=Caja ;;
    xfce)                name=XFCE fm=Thunar ;;
    pantheon)            name=Pantheon fm=Files ;;
    kde|plasma)          name="KDE Plasma" fm=Dolphin ;;
    lxqt)                name=LXQt fm=PCManFM-Qt ;;
    none)                name= ;;
    *)                   name=$desk fm= ;;
  esac
  if [[ -n $name && -n $fm ]]; then rows+=("ok|A desktop that shows folder icons|$name – $fm|")
  elif [[ -n $name ]]; then rows+=("warn|A desktop that shows folder icons|$name is not one Lotus knows|GNOME Files, Nemo, Caja, Thunar and Dolphin show them – yours may not.")
  else rows+=("warn|A desktop that shows folder icons|no desktop is running here (SSH or a text login)|The icon is saved for your next desktop session. GNOME Files, Nemo, Caja, Thunar and Dolphin show it.")
  fi
  if [[ $method == file ]]; then
    rows+=("ok|Nothing to install|a small .directory file is written in each folder|")
  elif (( ! $+commands[gio] )); then
    lotus_pkg_hint gio; hint=$REPLY
    rows+=("fail|gio|the program that keeps folder icons is missing|$hint"); bad=1
  elif _lotus_os_gio_ready; then
    rows+=("ok|gio and GVfs|your desktop keeps the icons for you|")
  else
    lotus_pkg_hint gvfs; hint=$REPLY
    rows+=("fail|GVfs|its icon service is not running – a desktop session has it|In a desktop window, or install it: $hint"); bad=1
  fi
  if lotus_os_desktop; then rows+=("ok|Your Desktop folder|${REPLY/#$HOME/~}|")
  elif [[ -n $REPLY ]]; then rows+=("warn|No Desktop folder|${REPLY/#$HOME/~} is not there|You can still drop other folders into the window.")
  else rows+=("warn|No Desktop folder|your system has none (xdg-user-dirs)|You can still drop other folders into the window.")
  fi
  if (( $+commands[magick] || $+commands[convert] )); then
    rows+=("ok|ImageMagick (optional)|turns WebP, HEIC, TIFF and big pictures into PNG|")
  else
    lotus_pkg_hint magick; hint=$REPLY
    rows+=("warn|ImageMagick (optional)|only for WebP, HEIC and TIFF pictures – PNG, JPEG and SVG work without|$hint")
  fi
  reply=("${rows[@]}")
  return bad
}

# ── Programs and processes ────────────────────────────────────

# Java home for at least <major> → REPLY (status 1 when there is none). Looks at JAVA_HOME, the system's own
# java, the usual JVM folders of the distributions and SDKMAN; the newest that is new enough wins, JAVA_HOME first.
lotus_os_java() {
  setopt localoptions extendedglob
  local need=$1 h v
  local -a homes=() ok=()
  [[ -n $JAVA_HOME ]] && homes+=($JAVA_HOME)
  (( $+commands[java] )) && homes+=(${${${commands[java]:A}:h}:h})
  homes+=(/usr/lib/jvm/*(N-/) /usr/lib64/jvm/*(N-/) /usr/java/*(N-/) /opt/java/*(N-/) ${SDKMAN_DIR:-$HOME/.sdkman}/candidates/java/*(N-/) $LOTUS_DATA/java/*(N-/))
  local -A seen=()
  for h in $homes; do
    h=${h:A}
    [[ -n $seen[$h] || ! -x $h/bin/java ]] && continue
    seen[$h]=1
    v=$("$h/bin/java" -version 2>&1 | head -1)
    [[ $v =~ '"([0-9]+)(\.([0-9]+))?' ]] || continue
    local -i major=$match[1]
    (( major == 1 )) && major=${match[3]:-8}          # 1.8.0 means Java 8
    (( major >= need )) && ok+=("$major $h")
  done
  (( ${#ok} )) || { REPLY=; return 1 }
  # JAVA_HOME first when it fits, else the newest
  local first=${ok[1]#* }
  if [[ -n $JAVA_HOME && ${JAVA_HOME:A} == $first ]]; then REPLY=$first
  else REPLY=${${${(On)ok}[1]}#* }; fi
}

# The working folders of running programs called <comm> → lines "pid<TAB>folder" (from /proc)
lotus_os_proc_cwds() {
  setopt localoptions extendedglob
  local d pid cwd
  local -a l
  for d in /proc/<->(N/); do
    pid=${d:t}
    [[ -r $d/comm && $(<$d/comm) == $1 ]] || continue
    zstat -A l +link $d/cwd 2>/dev/null || continue
    print -r -- "$pid"$'\t'"$l[1]"
  done 2>/dev/null
}

# The package of Java <major> for the system's package manager → REPLY (status 1: this manager does not know it)
# The whole JDK, not only the runtime: the Paper bridge (ping and TPS) is built with javac
lotus_os_java_package() {
  case $LOTUS_PKG in
    apt)    REPLY=openjdk-$1-jdk-headless ;;
    dnf|zypper) REPLY=java-$1-openjdk-devel ;;
    pacman) REPLY=jdk$1-openjdk ;;
    apk)    REPLY=openjdk$1-jdk ;;
    *)      REPLY=; return 1 ;;
  esac
}

# Eclipse Temurin for the user, from adoptium.net, into Lotus' own folder (no administrator rights; the checksum from
# the same API is checked before anything is unpacked) → $LOTUS_DATA/java/<major>
lotus_java_fetch() {   # <major>
  setopt localoptions extendedglob
  local major=$1 arch os=linux row url want size tmp
  [[ $major == <8-99> ]] || return 2
  case $LOTUS_ARCH in arm64) arch=aarch64 ;; *) arch=x64 ;; esac
  [[ $LOTUS_DISTRO == alpine ]] && os=alpine-linux
  ui_step "Looking up Eclipse Temurin $major …"
  row=$(curl -fsSL -m 20 "https://api.adoptium.net/v3/assets/latest/$major/hotspot?architecture=$arch&image_type=jdk&os=$os&vendor=eclipse" 2>/dev/null \
        | lotus_jq -r '.[0].binary.package | [.link, .checksum, .size] | @tsv' 2>/dev/null)
  [[ -n $row ]] || { ui_error "Temurin $major was not found for this system" "adoptium.net did not list a build for $os/$arch." "Install a JDK with your package manager."; return 1 }
  url=${row%%$'\t'*}; row=${row#*$'\t'}; want=${row%%$'\t'*}; size=${row#*$'\t'}
  [[ $url == https://github.com/adoptium/*.tar.gz && $want == [0-9a-f](#c64) ]] || { ui_error "Unexpected answer from adoptium.net" "$url"; return 1 }
  zf_mkdir -p $LOTUS_DATA/java $LOTUS_CACHE
  tmp=$LOTUS_CACHE/java-$major.tar.gz
  ui_dim "From: github.com/adoptium · $(( size / 1048576 )) MB"
  curl -fL --progress-bar -o $tmp $url || { rm -f $tmp; ui_error "The download failed"; return 1 }
  lotus_os_sha256 $tmp
  if [[ $REPLY != $want ]]; then rm -f $tmp; ui_error "Checksum mismatch" "The download was damaged or changed." "Nothing was installed."; return 1; fi
  ui_success "Checksum verified"
  rm -rf $LOTUS_DATA/java/$major
  zf_mkdir -p $LOTUS_DATA/java/$major
  tar -xzf $tmp -C $LOTUS_DATA/java/$major --strip-components=1 || { rm -rf $LOTUS_DATA/java/$major $tmp; ui_error "The download could not be unpacked"; return 1 }
  rm -f $tmp
  [[ -x $LOTUS_DATA/java/$major/bin/java ]] || { ui_error "Java is not in the download"; return 1 }
  lotus_log INFO java "Temurin $major in ${LOTUS_DATA/#$HOME/~}/java/$major"
  ui_success "Java $major is ready in ${LOTUS_DATA/#$HOME/~}/java/$major"
}

# Processes of this user that run in <dir> or below it → lines "pid<TAB>command line" (from /proc)
lotus_os_proc_in() {
  setopt localoptions extendedglob
  local dir=${1:A} d pid cwd args
  local -a l u
  for d in /proc/<->(N/); do
    pid=${d:t}
    zstat -A u +uid $d 2>/dev/null && [[ $u[1] == ${UID:-$(id -u)} ]] || continue
    zstat -A l +link $d/cwd 2>/dev/null || continue
    cwd=$l[1]
    [[ $cwd == $dir || $cwd == $dir/* ]] || continue
    args=$(tr '\0' ' ' < $d/cmdline 2>/dev/null)
    print -r -- "$pid"$'\t'"${args% }"
  done 2>/dev/null
}

# Keeps the system awake for as long as the process <pid> runs (an inhibitor lock held by a small waiting loop)
lotus_os_awake_while() {
  (( $+commands[systemd-inhibit] )) || return 2
  nohup systemd-inhibit --what=idle:sleep --who=Lotus --why="A Minecraft server is running" --mode=block \
    sh -c 'while kill -0 "$0" 2>/dev/null; do sleep 5; done' $1 >/dev/null 2>&1 &!
}

# ── Sandbox for plugins ───────────────────────────────────────
# bubblewrap, and it has to really work here: a system can ship it and still forbid user namespaces (containers,
# hardened kernels), so it is tried once. Cached for the process.
typeset -gi _LOTUS_BWRAP_OK=-1
lotus_os_sandbox_available() {
  (( _LOTUS_BWRAP_OK >= 0 )) && return $(( 1 - _LOTUS_BWRAP_OK ))
  _LOTUS_BWRAP_OK=0
  (( $+commands[bwrap] )) && bwrap --unshare-user --ro-bind / / --dev /dev -- true >/dev/null 2>&1 && _LOTUS_BWRAP_OK=1
  (( _LOTUS_BWRAP_OK ))
}

# lotus_os_sandbox_wrap <dir> <data> <network yes|no> [files the plugin may read…] → reply = the words that go in
# front of the program. Read-only view of the system, an empty home folder and /tmp, the plugin's own folder to
# read, its data folder to write, no keyring or session bus, a new session (no keystrokes into your terminal),
# no network unless the plugin says network = yes. Every folder that is hidden has to exist: bubblewrap cannot
# make a mount point inside the read-only system.
lotus_os_sandbox_wrap() {
  local dir=${1:A} data=${2:A} net=$3 f d
  local -a hidden=()
  shift 3
  # setsid -w: the whole sandbox lives in a session of its own, so a terminal that hangs up (a window closed right
  # after the start screen) cannot reach it – bubblewrap itself would not ignore the hang-up
  reply=()
  (( $+commands[setsid] )) && reply=(setsid -w)
  reply+=(bwrap --die-with-parent --new-session --unshare-all)
  [[ $net == yes ]] && reply+=(--share-net)
  reply+=(--ro-bind / / --dev /dev --proc /proc --tmpfs /tmp)
  for d in ${HOME:A} /home /root /mnt /media /run/media /run/user /run/dbus /var/run/dbus; do
    [[ -d $d ]] || continue
    d=${d:A}                                   # /var/run is a link to /run: the same folder is hidden once, under its real name
    (( ${hidden[(Ie)$d]} )) && continue
    reply+=(--tmpfs $d); hidden+=($d)
  done
  # the network needs the name servers: the resolver of systemd lives under /run
  [[ $net == yes && -d /run/systemd/resolve ]] && reply+=(--ro-bind /run/systemd/resolve /run/systemd/resolve)
  reply+=(--ro-bind $dir $dir --bind $data $data)
  for f in "$@"; do
    [[ $f == /* && -e $f ]] && reply+=(--ro-bind ${f:A} ${f:A})
  done
  # what is hidden is also closed: a write there fails, instead of landing in an empty folder that vanishes
  for d in $hidden; do reply+=(--remount-ro $d); done
  reply+=(--)
}
