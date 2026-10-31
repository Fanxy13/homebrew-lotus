# lotus – platform layer, the parts that are the same everywhere (see lib/platform.zsh)

# The functions every system file has to define (or stub with status 2). tests/test-platform.zsh checks that
# lib/platform/macos.zsh and lib/platform/linux.zsh both cover the whole list, so a new function cannot be forgotten.
typeset -ga LOTUS_OS_CONTRACT=(
  lotus_os_open lotus_os_reveal lotus_os_apps lotus_os_open_app
  lotus_os_clip_copy lotus_os_clip_paste lotus_os_clip_peek lotus_os_clip_save
  lotus_os_notify lotus_os_awake_start lotus_os_awake_is lotus_os_awake_stop lotus_os_awake_name
  lotus_os_volume lotus_os_media
  lotus_os_secret_get lotus_os_secret_set lotus_os_secret_del lotus_os_secret_store_name
  lotus_os_cpu_count lotus_os_mem_bytes lotus_os_chip lotus_os_fullname lotus_os_lan_ip
  lotus_os_trash lotus_os_choose_folder lotus_os_java lotus_os_java_package lotus_os_proc_cwds lotus_os_proc_in lotus_os_awake_while
  lotus_os_sandbox_available lotus_os_sandbox_wrap lotus_os_image_info
  lotus_os_image_bmp lotus_os_image_square lotus_os_media_cover
)

# The first of these programs that is installed → REPLY (status 1 when there is none)
lotus_os_first() {
  local c
  for c in "$@"; do (( $+commands[$c] )) && { REPLY=$c; return 0 }; done
  REPLY=
  return 1
}

# SHA-256 of a file → REPLY (64 hex characters). The same value on every system.
lotus_os_sha256() {
  REPLY=
  local out
  if   (( $+commands[sha256sum] )); then out=$(sha256sum -- "$1" 2>/dev/null)
  elif (( $+commands[shasum] ));    then out=$(shasum -a 256 -- "$1" 2>/dev/null)
  elif (( $+commands[openssl] ));   then out=$(openssl dgst -sha256 -r -- "$1" 2>/dev/null)
  else return 2; fi
  REPLY=${out%% *}
  [[ $REPLY == [0-9a-f](#c64) ]]
}

# SHA-256 of what comes in on stdin → REPLY
lotus_os_sha256_stdin() {
  REPLY=
  local out
  if   (( $+commands[sha256sum] )); then out=$(sha256sum 2>/dev/null)
  elif (( $+commands[shasum] ));    then out=$(shasum -a 256 2>/dev/null)
  elif (( $+commands[openssl] ));   then out=$(openssl dgst -sha256 -r 2>/dev/null)
  else return 2; fi
  REPLY=${out%% *}
  [[ $REPLY == [0-9a-f](#c64) ]]
}

# A target for lotus_os_open that cannot be taken for an option
_lotus_os_target() { [[ $1 == -* ]] && REPLY=./$1 || REPLY=$1 }

# Names of PNG dimensions without any image program: "WxH" of a PNG file → REPLY (status 1: not a PNG)
lotus_os_png_size() {
  local -a b
  b=(${=$(od -An -tu1 -j16 -N8 -- "$1" 2>/dev/null)})
  (( ${#b} == 8 )) || return 1
  [[ $(od -An -c -N4 -j1 -- "$1" 2>/dev/null | tr -d ' ') == PNG* ]] || return 1
  REPLY="$(( b[1] * 16777216 + b[2] * 65536 + b[3] * 256 + b[4] ))x$(( b[5] * 16777216 + b[6] * 65536 + b[7] * 256 + b[8] ))"
}

# A link could not be opened. Without a graphical session (an SSH login, a server) that is no error: the address is
# shown to open somewhere else. Otherwise it is one.
lotus_os_open_failed() {
  if [[ $LOTUS_OS == linux && $LOTUS_SESSION == tty && $LOTUS_WSL == 0 ]]; then
    ui_info "There is no graphical session here – open this address in a browser:"
    ui_text "$1"
  else
    ui_error "Could not open the link" "$1"
  fi
}

# Starts a command in the background, detached from this terminal: its own session, so a window that is closed
# (the terminal hangs up) cannot stop it, and no output. → status 0 when it was started
lotus_os_detach() {
  if   (( $+commands[setsid] )); then setsid -f "$@" </dev/null >/dev/null 2>&1
  elif (( $+commands[perl] ));   then perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' nohup "$@" </dev/null >/dev/null 2>&1 &!
  else nohup "$@" </dev/null >/dev/null 2>&1 &!; fi
}

# The hash of a file: lotus_os_hash <1|256|512> <file> → REPLY
lotus_os_hash() {
  local out
  if   (( $+commands[sha${1}sum] )); then out=$(sha${1}sum -- "$2" 2>/dev/null)
  elif (( $+commands[shasum] ));     then out=$(shasum -a $1 -- "$2" 2>/dev/null)
  elif (( $+commands[openssl] ));    then out=$(openssl dgst -sha$1 -r -- "$2" 2>/dev/null)
  else REPLY=; return 2; fi
  REPLY=${out%% *}
  [[ -n $REPLY ]]
}
