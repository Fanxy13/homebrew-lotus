# lotus – Shell-Integration. Wird aus ~/.zshrc geladen (siehe: lotus setup).
[[ -o interactive ]] || return 0

source ${${(%):-%x}:A:h}/core.zsh
lotus_load
zmodload zsh/zselect 2>/dev/null

typeset -gi LOTUS_NP_ROW=0 LOTUS_NP_COL=1 LOTUS_NP_IDX=0 LOTUS_NP_CURSOR=0 _lotus_live_pid=0
typeset -g LOTUS_NP_LAST= _lotus_prompt_orig=$PROMPT

# ── Live-Aktualisierung der Song-Zeilen ───────────────────────

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
      # Pausiert/nichts los → seltener nachschauen
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

# Während ein Befehl läuft, nichts zeichnen (sonst z. B. mitten in vim)
_lotus_preexec() { _lotus_live_stop }

# Nach einem Befehl weitermachen – solange nichts gescrollt oder gelöscht wurde
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

# ── Befehle ───────────────────────────────────────────────────

lotus_show() {
  _lotus_live_stop
  print -n $'\e[H\e[2J'
  lotus_render live
}

lotus() {
  case $1 in
    ''|show)
      lotus_show ;;
    settings|config)
      command lotus settings || return
      lotus_load; _lotus_prompt
      lotus_show ;;
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
