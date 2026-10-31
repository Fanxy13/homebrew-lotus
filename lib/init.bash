# lotus – shell integration for bash. Loaded from ~/.bashrc (see: lotus setup).
#
# Lotus' engine is zsh (bin/lotus). In bash this file shows the start screen, forwards the /commands and keeps the prompt
# in the theme's color. What zsh does inside the shell itself – the live now-playing lines under the start screen – is
# not done here: there the start screen is drawn once.
#
# /weather, /skip … cannot be aliases in bash (an alias name has no "/"), and a word with a "/" never reaches
# command_not_found_handle. So Enter is bound to a small readline function that rewrites the line before bash reads
# it: "/weather Paris" becomes "lotus weather Paris". That needs bash 4.4 (READLINE_LINE, local -); an older bash gets
# the start screen and the lotus command, but not the /commands.

case $- in *i*) ;; *) return 0 2>/dev/null || exit 0 ;; esac
[ -n "${__LOTUS_BASH:-}" ] && return 0
command -v lotus >/dev/null 2>&1 || return 0

__LOTUS_BASH=1
__LOTUS_PS1_ORIG=$PS1

# What zsh says about the settings (lotus bash-init prints bash code, every value quoted)
__lotus_load() {
  local code
  code=$(command lotus bash-init 2>/dev/null) || return 1
  eval "$code"
}

# The prompt in the theme's color
__lotus_prompt() {
  if [ -n "${__LOTUS_ACCENT:-}" ]; then
    PS1="\[\e[${__LOTUS_ACCENT}m\]\u@\h \W \\$\[\e[0m\] "
  else
    PS1=$__LOTUS_PS1_ORIG
  fi
}

# ── The lotus command ─────────────────────────────────────────

# A command Lotus prepared (/ai command, /help) goes onto the command line – it is never run. bash can only change the
# line from inside a key binding, so the terminal is asked for its status (ESC [ 5 n): its answer (ESC [ 0 n) triggers the binding.
__lotus_take_prompt() {
  local f=${LOTUS_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/lotus}/ai-prompt
  [ -r "$f" ] || return 0
  __LOTUS_PREFILL=$(<"$f")
  rm -f "$f"
  [ -n "$__LOTUS_PREFILL" ] && printf '\e[5n'
}

__lotus_prefill() {
  READLINE_LINE=$__LOTUS_PREFILL
  READLINE_POINT=${#READLINE_LINE}
  __LOTUS_PREFILL=
}

lotus() {
  local rc
  case $1 in
    ''|show)
      printf '\e[H\e[2J'
      command lotus show ;;
    settings|config)
      command lotus settings; rc=$?
      if [ "$rc" -eq 10 ]; then __lotus_unload; return 0; fi
      [ "$rc" -ne 0 ] && return "$rc"
      __lotus_load; __lotus_prompt
      printf '\e[H\e[2J'
      command lotus show ;;
    setup|features|pets|pet|feed|zetamac)
      rm -f "${LOTUS_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/lotus}/ai-prompt"
      command lotus "$@"; rc=$?
      __lotus_load; __lotus_prompt
      __lotus_take_prompt
      return "$rc" ;;
    help|cheatsheet|ai)
      rm -f "${LOTUS_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/lotus}/ai-prompt"
      command lotus "$@"; rc=$?
      __lotus_take_prompt
      return "$rc" ;;
    uninstall)
      command lotus uninstall && __lotus_unload ;;
    shortcut|shortcuts|logo|themes)
      command lotus "$@"; rc=$?
      __lotus_load
      return "$rc" ;;
    *)
      command lotus "$@" ;;
  esac
}

# ── Enter ─────────────────────────────────────────────────────

__LOTUS_ORIG=         # the line as it was typed, when Enter rewrote it (history keeps what you typed)
__LOTUS_NOGLOB=       # 1 while the rewritten line runs without pathname expansion (zsh: noglob)

# Rewrites the line a few friendly ways before bash reads it – only for features that are turned on:
#   /weather Paris          → lotus weather Paris           (the /commands of Lotus, plugins and your shortcuts)
#   /unknown                → lotus suggest /unknown
#   a pasted link           → lotus open <link>
#   open Spotify            → lotus app Spotify              (when no such file exists)
#   a pet's name            → lotus pet <name> '<what you said>'  (when nothing else has that name)
#   who is the goat?        → lotus goat
__lotus_enter() {
  local line=$READLINE_LINE
  case $line in *$'\n'*) return 0 ;; esac
  line=${line#"${line%%[![:space:]]*}"}          # leading blanks
  line=${line%"${line##*[![:space:]]}"}          # trailing blanks
  [ -n "$line" ] || return 0
  local first=${line%%[[:space:]]*} rest=
  case $line in *[[:space:]]*) rest=${line#"$first"}; rest=${rest#"${rest%%[![:space:]]*}"} ;; esac
  local new=
  local lower=${line,,}
  if [ "$lower" = "who is the goat" ] || [ "$lower" = "who is the goat?" ]; then
    new="lotus goat"
  elif [ "${first:0:1}" = "/" ] && [ -n "${__LOTUS_SLASH[$first]+x}" ] && [ ! -e "$first" ]; then
    new="lotus ${__LOTUS_SLASH[$first]}${rest:+ $rest}"
    __LOTUS_NOGLOB=1
  elif [ -z "$rest" ] && [ "${__LOTUS_WEB:-0}" = 1 ] && [[ $line =~ ^[Hh][Tt][Tt][Pp][Ss]?://[^[:space:]]+$ ]]; then
    new="lotus open $(printf '%q' "$line")"
  elif [ "$first" = open ] && [ -n "$rest" ] && [ "${__LOTUS_APPS:-0}" = 1 ] && [ "${rest:0:1}" != "-" ]; then
    local target=$rest
    if [ ! -e "${target/#\~/$HOME}" ] && [[ $target != *:* && $target != *.* ]]; then
      new="lotus app $(printf '%q' "$target")"
    fi
  elif [[ $first =~ ^/[[:alpha:]][[:alnum:]_-]*$ ]] && [ ! -e "$first" ]; then
    new="lotus suggest $first${rest:+ $rest}"
    __LOTUS_NOGLOB=1
  elif [ -n "${__LOTUS_PETS:-}" ]; then
    # "Mochi", "mochi how are you?", "Mochi, sit!" – unless a command, alias or function has that name
    local name=${first%%[,:!?.]*}
    name=${name,,}
    if [ -n "$name" ] && [[ $__LOTUS_PETS == *" $name "* ]] && ! type -t "$first" >/dev/null 2>&1; then
      local said=${line#"$first"}
      said=${said#"${said%%[![:space:],:!?.]*}"}
      new="lotus pet $name${said:+ $(printf '%q' "$said")}"
    fi
  fi
  [ -n "$new" ] || { __LOTUS_NOGLOB=; return 0; }
  __LOTUS_ORIG=$READLINE_LINE
  # globbing stays off for the rewritten line (links with ? must reach Lotus unchanged); the prompt turns it on again
  if [ -n "$__LOTUS_NOGLOB" ]; then
    case $- in *f*) __LOTUS_NOGLOB=0 ;; *) set -f ;; esac
  fi
  READLINE_LINE=$new
  READLINE_POINT=${#READLINE_LINE}
}

# Before each prompt: globbing back on, the history keeps what was typed
__lotus_precmd() {
  local rc=$?
  if [ "$__LOTUS_NOGLOB" = 1 ]; then set +f; fi
  __LOTUS_NOGLOB=
  if [ -n "$__LOTUS_ORIG" ]; then
    history -d $((HISTCMD - 1)) 2>/dev/null
    history -s -- "$__LOTUS_ORIG"
    __LOTUS_ORIG=
  fi
  return "$rc"
}

__lotus_bind() {
  # Enter = the rewriting function, then accept-line (Ctrl-J)
  bind -x '"\C-x\C-l": __lotus_enter' 2>/dev/null
  bind -x '"\e[0n": __lotus_prefill' 2>/dev/null
  bind -m emacs '"\C-m": "\C-x\C-l\C-j"' 2>/dev/null
  bind -m vi-insert '"\C-m": "\C-x\C-l\C-j"' 2>/dev/null
}

# Removes lotus from the running shell (after an uninstall)
__lotus_unload() {
  bind -m emacs '"\C-m": accept-line' 2>/dev/null
  bind -m vi-insert '"\C-m": accept-line' 2>/dev/null
  bind -r '\C-x\C-l' 2>/dev/null
  bind -r '\e[0n' 2>/dev/null
  PS1=$__LOTUS_PS1_ORIG
  if declare -p PROMPT_COMMAND 2>/dev/null | grep -q '^declare -a'; then
    local i
    for i in "${!PROMPT_COMMAND[@]}"; do [ "${PROMPT_COMMAND[$i]}" = __lotus_precmd ] && unset 'PROMPT_COMMAND[i]'; done
  else
    PROMPT_COMMAND=${PROMPT_COMMAND//__lotus_precmd;/}
    PROMPT_COMMAND=${PROMPT_COMMAND//__lotus_precmd/}
  fi
  unset -f lotus
  unset -f __lotus_load __lotus_prompt __lotus_take_prompt __lotus_prefill __lotus_enter __lotus_precmd __lotus_bind __lotus_unload
  unset __LOTUS_BASH __LOTUS_ORIG __LOTUS_NOGLOB __LOTUS_SLASH __LOTUS_PETS __LOTUS_PS1_ORIG
}

# ── Start ─────────────────────────────────────────────────────

if __lotus_load; then
  if [ "${__LOTUS_CONFIGURED:-0}" != 1 ] && [ -t 0 ] && [ -t 1 ]; then
    command lotus setup --tty && __lotus_load
  fi
  __lotus_prompt
  if [ "${BASH_VERSINFO[0]}" -gt 4 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -ge 4 ]; }; then
    __lotus_bind
  fi
  # before every prompt
  if declare -p PROMPT_COMMAND 2>/dev/null | grep -q '^declare -a'; then
    PROMPT_COMMAND=(__lotus_precmd "${PROMPT_COMMAND[@]}")
  else
    PROMPT_COMMAND="__lotus_precmd${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
  fi
  if [ "${__LOTUS_AI_BOOT:-0}" = 1 ]; then
    ( command lotus ai server start --quiet </dev/null >/dev/null 2>&1 & )
  fi
  if [ "${__LOTUS_STARTUP:-1}" = 1 ] && [ -t 1 ]; then
    command lotus show
  fi
else
  unset __LOTUS_BASH
fi
