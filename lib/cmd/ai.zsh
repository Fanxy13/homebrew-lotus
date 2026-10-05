# lotus – /ai: one entry point for AI in the terminal.
# Providers, tried in this order with LOTUS_AI_PROVIDER=auto:
#   apple   Apple Intelligence on this Mac (macOS 26+, Apple silicon; a small Swift helper is built once)
#   ollama  local models through Ollama (http://localhost:11434)
#   openai  any OpenAI-compatible API: LOTUS_AI_URL + key from $LOTUS_AI_KEY or the Keychain item "lotus-ai"
# Lotus never writes API keys to files.

lotus_cmd_ai() {
  shift   # "ai"
  local sub=$1
  case $sub in
    status)    lotus_ai_status ;;
    key)       lotus_ai_key ;;
    explain)   shift; lotus_ai_task "Explain clearly and briefly, for someone using the macOS terminal." "Explain: $*" ;;
    summarize|summarise) shift; lotus_ai_summarize "$@" ;;
    write)     shift; lotus_ai_task "Help the user write text. Return only the finished text." "Write: $*" ;;
    command)   shift; lotus_ai_command "$*" ;;
    '')        lotus_ai_chat ;;
    *)         lotus_ai_task "" "$*" ;;
  esac
}

# ── Providers ─────────────────────────────────────────────────

lotus_ai_helper() { REPLY=$LOTUS_CACHE/bin/lotus-ai-$LOTUS_VERSION }

# Apple Intelligence: needs macOS 26+, the FoundationModels framework and a compiler once
_ai_apple_ok() {
  [[ $(uname -m) == arm64 && -d /System/Library/Frameworks/FoundationModels.framework ]] || return 1
  lotus_ai_helper
  if [[ ! -x $REPLY ]]; then
    xcrun --find swiftc >/dev/null 2>&1 || return 1
    [[ $1 == build ]] || return 0      # available once built
    _ai_build || return 1
  fi
  [[ $1 == build ]] || return 0
  [[ $($REPLY --check 2>/dev/null) == available ]]
}

_ai_build() {
  lotus_ai_helper
  local bin=$REPLY
  zf_mkdir -p ${bin:h}
  ui_step "Preparing Apple Intelligence for the terminal (one time, about 20 seconds) …" >&2
  if ! xcrun swiftc -O -parse-as-library -o $bin.tmp $LOTUS_ROOT/lib/ai/lotus-ai.swift >/dev/null 2>$LOTUS_CACHE/ai-build.log; then
    ui_error "Could not prepare Apple Intelligence" "The Swift compiler reported an error." "Details: $LOTUS_CACHE/ai-build.log" >&2
    return 1
  fi
  zf_mv -f $bin.tmp $bin
  rm -f ${bin:h}/lotus-ai-^$LOTUS_VERSION(N)
}

_ai_ollama_model() {
  (( $+commands[curl] )) || return 1
  local tags=$(curl -fsS -m 1 http://localhost:11434/api/tags 2>/dev/null) || return 1
  local -a models=(${(f)"$(print -r -- $tags | lotus_jq -r '.models[].name' 2>/dev/null)"})
  (( ${#models} )) || return 1
  if [[ -n $LOTUS_AI_MODEL && ${models[(Ie)$LOTUS_AI_MODEL]} -gt 0 ]]; then REPLY=$LOTUS_AI_MODEL; else REPLY=$models[1]; fi
}

_ai_openai_key() {
  REPLY=${LOTUS_AI_KEY:-$(security find-generic-password -s lotus-ai -w 2>/dev/null)}
  [[ -n $REPLY ]]
}

_ai_openai_ok() { [[ -n $LOTUS_AI_URL ]] && _ai_openai_key }

# Picks the provider → REPLY (apple|ollama|openai), status 1 when none works
lotus_ai_provider() {
  local want=${LOTUS_AI_PROVIDER:-auto} p
  local -a order=(apple ollama openai)
  [[ $want != auto ]] && order=($want)
  for p in $order; do
    case $p in
      apple)  _ai_apple_ok build && { REPLY=apple; return 0 } ;;
      ollama) _ai_ollama_model && { REPLY=ollama; return 0 } ;;
      openai) _ai_openai_ok && { REPLY=openai; return 0 } ;;
    esac
  done
  return 1
}

lotus_ai_none() {
  ui_error "No AI is available yet" "Lotus did not find a usable AI provider on this Mac." \
    "Apple Intelligence: macOS 26+, Apple silicon, turned on in System Settings, plus Command Line Tools" \
    "Ollama: install it, start the app and pull a model, e.g. ollama pull llama3.2" \
    "Other: set LOTUS_AI_URL in /settings and add a key with: lotus ai key"
}

# ── Asking ────────────────────────────────────────────────────

# Streams one answer to stdout.  lotus_ai_ask <instructions> <prompt>
lotus_ai_ask() {
  local instr=${1:-"You are Lotus, a helpful assistant inside the macOS terminal. Answer clearly and concisely in plain text."} prompt=$2
  lotus_ai_provider || { lotus_ai_none; return 1 }
  case $REPLY in
    apple)
      lotus_ai_helper
      print -r -- $prompt | LOTUS_AI_INSTRUCTIONS=$instr $REPLY - ;;
    ollama)
      local model=$REPLY body
      _ai_ollama_model; model=$REPLY
      body=$(lotus_jq -n --arg m $model --arg s $instr --arg p $prompt '{model: $m, system: $s, prompt: $p, stream: true}')
      curl -fsSN -m 300 http://localhost:11434/api/generate -d $body 2>/dev/null | lotus_jq --unbuffered -rj '.response // empty'
      print ;;
    openai)
      _ai_openai_key
      local key=$REPLY body
      body=$(lotus_jq -n --arg m ${LOTUS_AI_MODEL:-gpt-4o-mini} --arg s $instr --arg p $prompt \
        '{model: $m, stream: true, messages: [{role: "system", content: $s}, {role: "user", content: $p}]}')
      curl -fsSN -m 300 "${LOTUS_AI_URL%/}/chat/completions" -H "Authorization: Bearer $key" -H 'Content-Type: application/json' -d $body 2>/dev/null \
        | sed -un 's/^data: //p' | grep --line-buffered -v '^\[DONE\]' | lotus_jq --unbuffered -rj '.choices[0].delta.content // empty'
      print ;;
  esac
}

lotus_ai_task() {   # <instructions> <prompt>
  [[ -z ${2// } || $2 == (Explain|Write):\ # ]] && { ui_error "What should the AI do?" "" "Example: /ai explain chmod 755"; return 1 }
  ui_blank
  lotus_ai_ask "$1" "$2" | sed 's/^/  /'
  ui_blank
}

lotus_ai_summarize() {
  local text src
  if [[ -n $1 ]]; then
    [[ -f $1 && -r $1 ]] || { ui_error "File not found" "$1"; return 1 }
    [[ $(file -b --mime-type -- $1) == text/* ]] || { ui_error "Not a text file" "$1" "Summaries work with text files, e.g. .txt or .md"; return 1 }
    text=$(<$1); src=${1:t}
  else
    text=$(pbpaste 2>/dev/null); src=clipboard
  fi
  [[ -z ${text// } ]] && { ui_error "Nothing to summarize" "The ${src:-clipboard} is empty." "Usage: /ai summarize <file>   or copy text first"; return 1 }
  (( ${#text} > 12000 )) && { text=${text[1,12000]}; ui_dim "Long text: the first 12,000 characters are used." }
  ui_header AI "summary of $src"
  lotus_ai_ask "Summarize the text in a few short bullet points using '-'. Plain text only." "$text" | sed 's/^/  /'
  ui_blank
}

# Suggests one command. It is never run – the user decides.
lotus_ai_command() {
  local task=$1
  [[ -z ${task// } ]] && { ui_error "What should the command do?" "" "Example: /ai command find files larger than 1 GB"; return 1 }
  ui_header AI "command for: $task"
  local answer=$(lotus_ai_ask "You are a macOS terminal expert. Answer with a single shell command line, nothing else." "$task")
  local -a lines=(${(f)${answer//\`/}})
  local cmd=$lines[1]
  cmd=${${cmd##[[:space:]]#}%%[[:space:]]#}
  [[ -z $cmd ]] && { ui_error "The AI did not suggest a command" "" "Try describing the task with other words."; return 1 }
  ui_card Suggestion "COMMAND|$cmd"
  ui_blank
  ui_warn "Lotus never runs it. Check it before you press Enter."
  ui_choose "" "Put it on the command line" "Copy to clipboard" "Cancel" || return 0
  case $REPLY in
    1) zf_mkdir -p $LOTUS_CACHE; print -r -- $cmd >| $LOTUS_CACHE/ai-prompt
       ui_success "Ready on your command line" ;;
    2) print -rn -- $cmd | pbcopy && ui_success "Copied" ;;
  esac
}

lotus_ai_chat() {
  lotus_ai_provider || { lotus_ai_none; return 1 }
  local p=$REPLY
  ui_header AI "chat with ${${${p/apple/Apple Intelligence}/ollama/Ollama}/openai/$LOTUS_AI_URL}"
  ui_dim "Empty line or Ctrl-D to stop."
  case $p in
    apple)  lotus_ai_helper; $REPLY --chat ;;
    ollama) _ai_ollama_model; ollama run $REPLY ;;
    openai)
      local line
      while :; do
        print -rn -- $'\n\e[1myou ›\e[0m '
        read -r line < /dev/tty || break
        [[ -z ${line// } || $line == (exit|quit) ]] && break
        print
        lotus_ai_ask "" "$line"
      done ;;
  esac
  ui_blank
}

lotus_ai_status() {
  local ok=$'\e[1;'"$LOTUS_C[key]m✓"$'\e[0m' no=$'\e['"$LOTUS_C[dim]m·"$'\e[0m' state
  ui_header AI "provider: ${LOTUS_AI_PROVIDER:-auto}"
  if _ai_apple_ok; then
    lotus_ai_helper
    if [[ -x $REPLY ]]; then state=$($REPLY --check 2>/dev/null); else state="ready to set up (first /ai builds a small helper)"; fi
    print -r -- "  ${${(M)state:#available}:+$ok}${${state:#available}:+$no} Apple Intelligence  $state"
  else
    print -r -- "  $no Apple Intelligence  needs macOS 26+, Apple silicon and the Command Line Tools"
  fi
  if _ai_ollama_model; then print -r -- "  $ok Ollama              model: $REPLY"
  elif (( $+commands[ollama] )); then print -r -- "  $no Ollama              installed, but not running – open the Ollama app"
  else print -r -- "  $no Ollama              not installed"; fi
  if _ai_openai_ok; then print -r -- "  $ok OpenAI-compatible   $LOTUS_AI_URL"
  else print -r -- "  $no OpenAI-compatible   set a URL in /settings and a key with: lotus ai key"; fi
  ui_blank
}

# Stores the API key in the macOS Keychain. macOS asks for it – Lotus never sees it.
lotus_ai_key() {
  ui_header AI "API key"
  ui_text "macOS will ask for the key and keep it in your Keychain (item: lotus-ai)."
  security add-generic-password -U -s lotus-ai -a "$USER" -w && ui_success "Saved in the Keychain"
}
