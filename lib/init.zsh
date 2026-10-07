# lotus – shell integration. Loaded from ~/.zshrc (see: lotus setup).
[[ -o interactive ]] || return 0

zmodload zsh/datetime
typeset -gF _lotus_t0=$EPOCHREALTIME
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
  _lotus_t0=$EPOCHREALTIME
  print -n $'\e[H\e[2J'
  lotus_render live
  lotus_startup_details
}

# ── Slash commands, shortcuts and the Enter key ───────────────

# /weather, /skip, … from data/commands.tsv, plus the user's shortcuts → aliases
_lotus_aliases() {
  local line trig sub
  local -a f
  (( ${+_lotus_alias_names} )) && unalias ${_lotus_alias_names} 2>/dev/null
  typeset -ga _lotus_alias_names=()
  for line in "${(@f)$(<$LOTUS_ROOT/data/commands.tsv)}"; do
    [[ $line == \#* ]] && continue
    f=("${(@ps:\t:)line}")
    trig=$f[2] sub=$f[3]
    [[ $trig == /* ]] || continue
    [[ $trig == /lotus ]] && sub=
    alias "$trig=noglob lotus${sub:+ $sub}"
    _lotus_alias_names+=($trig)
  done
  # links with ? or & must reach Lotus unchanged, so no globbing for lotus commands
  alias lotus='noglob lotus'
  for trig in ${(k)LOTUS_SHORTCUTS}; do
    [[ ${LOTUS_SHORTCUTS[$trig]##*|} == on && -z ${aliases[/$trig]} ]] || continue
    alias "/$trig=noglob lotus run $trig"
    _lotus_alias_names+=(/$trig)
  done
}

# Enter: a few friendly extras before zsh runs the line
#   pasted link → open it · "open Spotify" (no such file) → /app · unknown /word → suggestion
#   Only for features that are turned on; the goat question always gets its answer.
_lotus_accept_line() {
  setopt localoptions extendedglob
  local line=${BUFFER##[[:space:]]#}
  line=${line%%[[:space:]]#}
  local -a w=(${(z)line})
  if [[ ${(L)line} == who\ is\ the\ goat(\?|) ]]; then
    BUFFER="lotus goat"
  elif (( ${#w} == 1 )) && [[ $line == (#i)https#://[^[:space:]]## ]] && lotus_feature_on web; then
    BUFFER="lotus open ${(q)line}"
  elif [[ $w[1] == open ]] && (( ${#w} >= 2 )) && [[ $w[2] != -* ]] && lotus_feature_on apps; then
    local target=${(Q)${(j: :)w[2,-1]}}
    [[ -e ${target/#\~/$HOME} || $target == *:* || $target == *.* ]] || BUFFER="lotus app ${(q)target}"
  elif [[ $w[1] == /[[:alpha:]][[:alnum:]_-]# && -z ${aliases[$w[1]]} && ! -e $w[1] ]]; then
    BUFFER="lotus suggest ${(q)w[1]} ${(j: :)w[2,-1]}"
  fi
  zle _lotus_orig_accept_line
}

_lotus_widget() {
  [[ -o zle ]] || return
  (( ${+widgets[_lotus_orig_accept_line]} )) && return
  zle -A accept-line _lotus_orig_accept_line
  zle -N accept-line _lotus_accept_line
}

# Removes lotus from the running shell (after an uninstall)
_lotus_unload() {
  _lotus_live_stop
  add-zsh-hook -d preexec _lotus_preexec
  add-zsh-hook -d precmd _lotus_precmd
  add-zsh-hook -d zshexit _lotus_live_stop
  PROMPT=$_lotus_prompt_orig
  (( ${+_lotus_alias_names} )) && unalias $_lotus_alias_names 2>/dev/null
  if (( ${+widgets[_lotus_orig_accept_line]} )); then
    zle -A _lotus_orig_accept_line accept-line
    zle -D _lotus_orig_accept_line
  fi
  unfunction TRAPWINCH 2>/dev/null
  unfunction -m 'lotus*' '_lotus*'
  unset -m 'LOTUS_*' '_lotus_*'
}

# After a Homebrew update the old version folder is gone: switch to the new one
_lotus_fix_root() {
  [[ -d $LOTUS_ROOT/lib ]] && return
  local root=${${commands[lotus]:A}:h:h}
  [[ -d $root/lib ]] && LOTUS_ROOT=$root
}

# "function" keeps the lotus alias (noglob) from touching this definition when re-sourced
function lotus {
  local -i rc
  _lotus_fix_root
  case $1 in
    ''|show)
      lotus_show ;;
    settings|config)
      command lotus settings; rc=$?
      if (( rc == 10 )); then _lotus_unload; return 0; fi
      (( rc )) && return rc
      lotus_load; _lotus_prompt; _lotus_aliases
      lotus_show ;;
    setup|features)
      command lotus "$@"; rc=$?
      lotus_load; _lotus_prompt; _lotus_aliases
      return rc ;;
    uninstall)
      command lotus uninstall && _lotus_unload ;;
    shortcut|shortcuts|logo|themes)
      command lotus "$@"; rc=$?
      lotus_load; _lotus_aliases
      return rc ;;
    ai)
      rm -f $LOTUS_CACHE/ai-prompt
      command lotus "$@"; rc=$?
      # /ai command: the suggestion goes onto the command line, it is never run
      [[ -r $LOTUS_CACHE/ai-prompt ]] && { print -z -- "$(<$LOTUS_CACHE/ai-prompt)"; rm -f $LOTUS_CACHE/ai-prompt }
      return rc ;;
    *)
      command lotus "$@" ;;
  esac
}

# ── Start ─────────────────────────────────────────────────────

autoload -Uz add-zsh-hook
add-zsh-hook preexec _lotus_preexec
add-zsh-hook precmd _lotus_precmd
add-zsh-hook zshexit _lotus_live_stop

_lotus_aliases
_lotus_widget
_lotus_prompt
if (( ! LOTUS_CONFIGURED )) && [[ -t 0 && -t 1 ]]; then
  command lotus setup --tty && lotus_load && _lotus_prompt
fi
lotus_log DEBUG startup "Shell ready (Lotus $LOTUS_VERSION, $LOTUS_ROOT)"
(( LOTUS_STARTUP )) && [[ -t 1 ]] && lotus_render live && lotus_startup_details
