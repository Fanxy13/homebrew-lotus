# lotus – shell integration. Loaded from ~/.zshrc (see: lotus setup).
[[ -o interactive ]] || return 0

source ${${(%):-%x}:A:h}/core.zsh
lotus_load
zmodload zsh/zselect 2>/dev/null

typeset -gi LOTUS_NP_ROW=0 LOTUS_NP_COL=1 LOTUS_NP_IDX=0 LOTUS_NP_CURSOR=0 _lotus_live_pid=0
typeset -g LOTUS_NP_LAST= _lotus_prompt_orig=$PROMPT

# ── Live updates of the now playing lines ─────────────────────

_lotus_live_stop() {
  (( _lotus_live_pid )) && kill $_lotus_live_pid 2>/dev/null
  _lotus_live_pid=0
}

_lotus_live_off() {
  _lotus_live_stop
  LOTUS_NP_ROW=0
}

_lotus_live_start() {
  _lotus_live_stop
  (( LOTUS_NP_ROW > 0 && LOTUS_LIVE )) || return
  {
    unfunction TRAPWINCH 2>/dev/null
    local last=$LOTUS_NP_LAST cur
    local -i wait
    while :; do
      # Paused or nothing playing → check less often
      (( wait = LOTUS_INTERVAL * 100 ))
      [[ $last == *▶* ]] || (( wait = wait < 500 ? 500 : wait ))
      zselect -t $wait 2>/dev/null || [[ $? == 1 ]] || sleep $(( wait / 100 ))
      lotus_np_get
      cur=${(F)reply}
      [[ $cur == $last ]] && continue
      last=$cur
      print -n -- $'\e7\e[?7l'"\e[${LOTUS_NP_ROW};${LOTUS_NP_COL}H"$'\e[0m\e[K'"${reply[1]}\e[$((LOTUS_NP_ROW + 1));${LOTUS_NP_COL}H"$'\e[0m\e[K'"${reply[2]}"$'\e[0m\e[?7h\e8' \
        > /dev/tty 2>/dev/null || exit
    done
  } &!
  _lotus_live_pid=$!
}

# Never draw while a command runs (e.g. inside vim)
_lotus_preexec() { _lotus_live_stop }

# After a command: keep going as long as nothing scrolled or was cleared
_lotus_precmd() {
  (( LOTUS_NP_ROW > 0 )) || return
  if ! lotus_cursor_row || (( REPLY >= LINES || REPLY < LOTUS_NP_CURSOR )); then
    _lotus_live_off
    return
  fi
  LOTUS_NP_CURSOR=$REPLY
  _lotus_live_start
}

TRAPWINCH() { _lotus_live_off }

# ── Prompt ────────────────────────────────────────────────────

_lotus_prompt() {
  if (( LOTUS_PROMPT )); then
    local c=${LOTUS_C[accent]}
    if [[ $c == 38\;2\;* ]]; then
      local -a v=(${(s:;:)c#38;2;})
      c="#${(l:2::0:)$(( [##16] v[1] ))}${(l:2::0:)$(( [##16] v[2] ))}${(l:2::0:)$(( [##16] v[3] ))}"
    else
      c=${c#38;5;}
    fi
    PROMPT="%F{$c}%n@%m %1~ %#%f "
  else
    PROMPT=$_lotus_prompt_orig
  fi
}

# ── Commands ──────────────────────────────────────────────────

lotus_show() {
  _lotus_live_stop
  print -n $'\e[H\e[2J'
  lotus_render live
}

# Removes lotus from the running shell (after an uninstall)
_lotus_unload() {
  _lotus_live_stop
  add-zsh-hook -d preexec _lotus_preexec
  add-zsh-hook -d precmd _lotus_precmd
  add-zsh-hook -d zshexit _lotus_live_stop
  PROMPT=$_lotus_prompt_orig
  unalias /settings /lotus 2>/dev/null
  unfunction TRAPWINCH 2>/dev/null
  unfunction -m 'lotus*' '_lotus*'
  unset -m 'LOTUS_*' '_lotus_*'
}

lotus() {
  local -i rc
  case $1 in
    ''|show)
      lotus_show ;;
    settings|config)
      command lotus settings; rc=$?
      if (( rc == 10 )); then _lotus_unload; return 0; fi
      (( rc )) && return rc
      lotus_load; _lotus_prompt
      lotus_show ;;
    uninstall)
      command lotus uninstall && _lotus_unload ;;
    *)
      command lotus "$@" ;;
  esac
}

alias /settings='lotus settings'
alias /lotus='lotus'

# ── Start ─────────────────────────────────────────────────────

autoload -Uz add-zsh-hook
add-zsh-hook preexec _lotus_preexec
add-zsh-hook precmd _lotus_precmd
add-zsh-hook zshexit _lotus_live_stop

_lotus_prompt
(( LOTUS_STARTUP )) && [[ -t 1 ]] && lotus_render live
