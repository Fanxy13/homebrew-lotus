# lotus – /ai: the AI terminal and quick AI commands.
# The AI itself is a small Swift program (lib/ai/*.swift), built once on this Mac.
# Providers, tried in this order with LOTUS_AI_PROVIDER=auto:
#   claude  Claude API – key from $ANTHROPIC_API_KEY or the Keychain item "lotus-ai-claude"
#   apple   Apple Intelligence on this Mac (macOS 26+, Apple silicon)
#   ollama  local models through Ollama (http://localhost:11434)
#   openai  any OpenAI-compatible API: LOTUS_AI_URL + key from $LOTUS_AI_KEY or the Keychain item "lotus-ai"
# Lotus never writes API keys to files; they reach the AI program only through its environment.

lotus_cmd_ai() {
  shift   # "ai"
  local sub=$1
  case $sub in
    status)    lotus_ai_status ;;
    key|keys)  shift; lotus_ai_key "$@" ;;
    new|clear|reset)
      shift
      rm -f $LOTUS_CACHE/ai/conversation.json
      ui_success "New conversation – the AI forgot the last one"
      (( $# )) && lotus_ai_run --once "$*" ;;
    explain)   shift; lotus_ai_task "Explain clearly and completely, for someone using the macOS terminal. Use an example where it helps." "Explain: $*" ;;
    summarize|summarise) shift; lotus_ai_summarize "$@" ;;
    write)     shift; lotus_ai_task "Help the user write text. Return only the finished text." "Write: $*" ;;
    command)   shift; lotus_ai_command "$*" ;;
    chat|'')   lotus_ai_run --tui ;;
    *)         lotus_ai_run --once "$*" ;;
  esac
}

# ── The AI program ────────────────────────────────────────────

# Path of the built program; the name changes whenever the source changes
lotus_ai_helper() {
  local sum=$(cat $LOTUS_ROOT/lib/ai/*.swift(N) | cksum)
  REPLY=$LOTUS_CACHE/bin/lotus-ai-${sum%% *}
}

_ai_can_build() { xcode-select -p >/dev/null 2>&1 && xcrun --find swiftc >/dev/null 2>&1 }

# Builds the program once (about 15 seconds)
_ai_build() {
  lotus_ai_helper
  local bin=$REPLY
  [[ -x $bin ]] && return 0
  if ! _ai_can_build; then
    ui_error "The AI terminal needs Apple's Command Line Tools once" "They contain the compiler Lotus uses to set up the AI." \
      "Install them with: xcode-select --install" "Then run /ai again." >&2
    return 1
  fi
  zf_mkdir -p ${bin:h}
  ui_step "Setting up the AI terminal (one time, about 15 seconds) …" >&2
  if ! xcrun swiftc -Onone -parse-as-library -swift-version 5 -o $bin.tmp $LOTUS_ROOT/lib/ai/*.swift >/dev/null 2>$LOTUS_CACHE/ai-build.log; then
    rm -f $bin.tmp
    ui_error "Could not set up the AI terminal" "The Swift compiler reported an error." "Details: $LOTUS_CACHE/ai-build.log" >&2
    return 1
  fi
  zf_mv -f $bin.tmp $bin
  rm -f ${bin:h}/lotus-ai-^${bin:t:s/lotus-ai-/}(N)
}

# ── Providers ─────────────────────────────────────────────────

_ai_claude_key() {
  REPLY=${ANTHROPIC_API_KEY:-$(security find-generic-password -s lotus-ai-claude -w 2>/dev/null)}
  [[ -n $REPLY ]]
}

_ai_openai_key() {
  REPLY=${LOTUS_AI_KEY:-$(security find-generic-password -s lotus-ai -w 2>/dev/null)}
  [[ -n $REPLY ]]
}

_ai_openai_ok() { [[ -n $LOTUS_AI_URL ]] && _ai_openai_key }

# Apple Intelligence: Apple silicon, macOS 26+, turned on. Needs the AI program for the check.
_ai_apple_ok() {
  [[ $(uname -m) == arm64 && -d /System/Library/Frameworks/FoundationModels.framework ]] || return 1
  lotus_ai_helper
  if [[ ! -x $REPLY ]]; then
    _ai_can_build || return 1
    [[ $1 == build ]] || return 0      # available once built
    _ai_build || return 1
    lotus_ai_helper
  fi
  [[ $1 == build ]] || return 0
  [[ $($REPLY --check 2>/dev/null) == available ]]
}

_ai_ollama_models() {
  (( $+commands[curl] )) || return 1
  local tags=$(curl -fsS -m 1 http://localhost:11434/api/tags 2>/dev/null) || return 1
  reply=(${(f)"$(print -r -- $tags | lotus_jq -r '.models[].name' 2>/dev/null)"})
  (( ${#reply} ))
}

_ai_ollama_model() {
  _ai_ollama_models || return 1
  if [[ -n $LOTUS_AI_MODEL && ${reply[(Ie)$LOTUS_AI_MODEL]} -gt 0 ]]; then REPLY=$LOTUS_AI_MODEL; else REPLY=$reply[1]; fi
}

# Picks the provider → REPLY (claude|apple|ollama|openai), status 1 when none works
lotus_ai_provider() {
  local want=${LOTUS_AI_PROVIDER:-auto} p
  local -a order=(claude apple ollama openai)
  [[ $want != auto ]] && order=($want)
  for p in $order; do
    case $p in
      claude) _ai_claude_key && { REPLY=claude; return 0 } ;;
      apple)  _ai_apple_ok build && { REPLY=apple; return 0 } ;;
      ollama) _ai_ollama_model && { REPLY=ollama; return 0 } ;;
      openai) _ai_openai_ok && { REPLY=openai; return 0 } ;;
    esac
  done
  return 1
}

lotus_ai_none() {
  ui_error "No AI is available yet" "Lotus did not find an AI it can use on this Mac." \
    "Claude: add your API key with: lotus ai key claude" \
    "Apple Intelligence: macOS 26+, Apple silicon, turned on in System Settings" \
    "Ollama: install it, open the app and download a model, e.g. ollama pull qwen3" \
    "Other: set the AI URL in /settings and add a key with: lotus ai key openai"
}

# Runs the AI program with everything it needs in its environment (keys never on the command line)
lotus_ai_run() {
  local mode=$1; shift
  lotus_ai_helper
  if [[ ! -x $REPLY ]] && ! _ai_can_build; then
    _ai_fallback $mode "$*"
    return
  fi
  _ai_build || return 1
  lotus_ai_provider || { lotus_ai_none; return 1 }
  local provider=$REPLY model=$LOTUS_AI_MODEL
  case $provider in
    claude) [[ $model == claude-* ]] || model= ;;
    ollama) _ai_ollama_model; model=$REPLY ;;
    apple)  model= ;;
  esac
  local -a avail=()
  _ai_claude_key && avail+=claude
  [[ -d /System/Library/Frameworks/FoundationModels.framework ]] && avail+=apple
  _ai_openai_ok && avail+=openai
  lotus_ai_helper
  local bin=$REPLY
  zf_mkdir -p $LOTUS_CACHE/ai && chmod 700 $LOTUS_CACHE/ai
  (
    export LOTUS_AI_PROVIDER=$provider LOTUS_AI_MODEL=$model LOTUS_AI_EFFORT=${LOTUS_AI_EFFORT:-high}
    export LOTUS_AI_STATE=$LOTUS_CACHE/ai LOTUS_AI_URL=$LOTUS_AI_URL LOTUS_AI_AVAILABLE=${(j:,:)avail}
    export LOTUS_NAME LOTUS_ROOT LOTUS_VERSION
    export LOTUS_AI_C_LOGO=$LOTUS_C[logo] LOTUS_AI_C_KEY=$LOTUS_C[key] LOTUS_AI_C_ACCENT=$LOTUS_C[accent]
    export LOTUS_AI_C_BORDER=$LOTUS_C[border] LOTUS_AI_C_DIM=$LOTUS_C[dim] LOTUS_AI_C_MUSIC=$LOTUS_C[music]
    _ai_claude_key && export LOTUS_AI_CLAUDE_KEY=$REPLY
    _ai_openai_key && export LOTUS_AI_OPENAI_KEY=$REPLY
    [[ -n $LOTUS_AI_INSTRUCTIONS ]] && export LOTUS_AI_INSTRUCTIONS
    exec $bin $mode "$@"
  )
}

# Without the Command Line Tools: one answer through curl, no memory, no tools
_ai_fallback() {
  local mode=$1 prompt=$2
  [[ $prompt == - ]] && prompt=$(cat)
  if [[ $mode == --tui ]]; then
    ui_error "The AI terminal needs Apple's Command Line Tools once" "" "Install them with: xcode-select --install" \
      "Until then, ask single questions: /ai <question>"
    return 1
  fi
  lotus_ai_provider || { lotus_ai_none; return 1 }
  local p=$REPLY instr=${LOTUS_AI_INSTRUCTIONS:-"You are Lotus, a helpful assistant inside the macOS terminal. Answer thoroughly and clearly."} body
  case $p in
    claude)
      _ai_claude_key
      local key=$REPLY model=${${(M)LOTUS_AI_MODEL:#claude-*}:-claude-opus-5-5}
      body=$(lotus_jq -n --arg m $model --arg s $instr --arg p $prompt \
        '{model: $m, max_tokens: 16000, stream: true, system: $s, messages: [{role: "user", content: $p}]}')
      curl -fsSN -m 600 https://api.anthropic.com/v1/messages -H "x-api-key: $key" -H 'anthropic-version: 2023-06-01' \
          -H 'Content-Type: application/json' -d $body 2>/dev/null \
        | sed -un 's/^data: //p' | lotus_jq --unbuffered -rj 'select(.type == "content_block_delta" and .delta.type == "text_delta") | .delta.text' ;;
    ollama)
      _ai_ollama_model
      body=$(lotus_jq -n --arg m $REPLY --arg s $instr --arg p $prompt '{model: $m, system: $s, prompt: $p, stream: true}')
      curl -fsSN -m 600 http://localhost:11434/api/generate -d $body 2>/dev/null | lotus_jq --unbuffered -rj '.response // empty' ;;
    openai)
      _ai_openai_key
      local key=$REPLY
      body=$(lotus_jq -n --arg m ${LOTUS_AI_MODEL:-gpt-4o-mini} --arg s $instr --arg p $prompt \
        '{model: $m, stream: true, messages: [{role: "system", content: $s}, {role: "user", content: $p}]}')
      curl -fsSN -m 600 "${LOTUS_AI_URL%/}/chat/completions" -H "Authorization: Bearer $key" -H 'Content-Type: application/json' -d $body 2>/dev/null \
        | sed -un 's/^data: //p' | grep --line-buffered -v '^\[DONE\]' | lotus_jq --unbuffered -rj '.choices[0].delta.content // empty' ;;
    *) lotus_ai_none; return 1 ;;
  esac
  print
}

# ── Quick commands ────────────────────────────────────────────

# One answer without memory or tools.  lotus_ai_task <instructions> <prompt>
lotus_ai_task() {
  [[ -z ${2// } || $2 == (Explain|Write):\ # ]] && { ui_error "What should the AI do?" "" "Example: /ai explain chmod 755"; return 1 }
  LOTUS_AI_INSTRUCTIONS=$1 lotus_ai_run --task "$2"
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
  (( ${#text} > 60000 )) && { text=${text[1,60000]}; ui_dim "Long text: the first 60,000 characters are used." }
  ui_header AI "summary of $src"
  print -r -- $text | LOTUS_AI_INSTRUCTIONS="Summarize the text: first one sentence with the gist, then the key points as short '-' bullets. Plain text." lotus_ai_run --task -
  ui_blank
}

# Suggests one command. It is never run – the user decides.
lotus_ai_command() {
  local task=$1
  [[ -z ${task// } ]] && { ui_error "What should the command do?" "" "Example: /ai command find files larger than 1 GB"; return 1 }
  ui_header AI "command for: $task"
  local answer=$(LOTUS_AI_INSTRUCTIONS="You are a macOS terminal expert. Answer with a single shell command line for zsh on macOS, nothing else." lotus_ai_run --plain "$task")
  local -a lines=(${(f)${answer//\`/}})
  lines=(${lines:#(zsh|bash|sh|shell)})
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

# ── Status and keys ───────────────────────────────────────────

lotus_ai_status() {
  local ok=$'\e[1;'"$LOTUS_C[key]m✓"$'\e[0m' no=$'\e['"$LOTUS_C[dim]m·"$'\e[0m' state
  local -A effort=(low quick medium balanced high thorough max maximum)
  ui_header AI "provider: ${LOTUS_AI_PROVIDER:-auto} · thinks ${effort[${LOTUS_AI_EFFORT:-high}]:-thorough}"
  local cm=${(M)LOTUS_AI_MODEL:#claude-*}
  if _ai_claude_key; then print -r -- "  $ok Claude              key saved${cm:+ · $cm}"
  else print -r -- "  $no Claude              add a key: lotus ai key claude"; fi
  if _ai_apple_ok; then
    lotus_ai_helper
    if [[ -x $REPLY ]]; then state=$($REPLY --check 2>/dev/null); else state="ready (the first /ai sets it up)"; fi
    print -r -- "  ${${(M)state:#available}:+$ok}${${state:#available}:+$no} Apple Intelligence  $state"
  else
    print -r -- "  $no Apple Intelligence  needs macOS 26+, Apple silicon and the Command Line Tools"
  fi
  if _ai_ollama_model; then print -r -- "  $ok Ollama              ${#reply} model(s), e.g. $REPLY"
  elif (( $+commands[ollama] )); then print -r -- "  $no Ollama              installed, but not running – open the Ollama app"
  else print -r -- "  $no Ollama              not installed"; fi
  if _ai_openai_ok; then print -r -- "  $ok OpenAI-compatible   $LOTUS_AI_URL"
  else print -r -- "  $no OpenAI-compatible   set a URL in /settings and a key with: lotus ai key openai"; fi
  ui_blank
  if [[ -f $LOTUS_CACHE/ai/conversation.json ]]; then
    ui_dim "Memory: the current conversation is kept for an hour after the last message (/ai new forgets it)."
  else
    ui_dim "Memory: no conversation right now."
  fi
  _ai_can_build || ui_dim "The AI terminal needs the Command Line Tools: xcode-select --install"
  ui_blank
}

# Stores an API key in the macOS Keychain. macOS asks for it – it never shows up on screen or in a file.
lotus_ai_key() {
  local which=$1
  if [[ -z $which ]]; then
    ui_header AI "API keys"
    ui_choose "Which key?" "Claude (Anthropic)" "OpenAI-compatible API" "Remove a saved key" || return 0
    case $REPLY in 1) which=claude ;; 2) which=openai ;; 3) which=remove ;; esac
  fi
  case $which in
    claude|anthropic)
      ui_header AI "Claude API key"
      ui_text "Create a key at console.anthropic.com (API keys). Paste it when macOS asks for the password –"
      ui_text "it is stored in your Keychain as \"lotus-ai-claude\" and is not shown while you type."
      ui_blank
      if security add-generic-password -U -s lotus-ai-claude -a "$USER" -w; then
        ui_success "Saved in the Keychain"
        [[ ${LOTUS_AI_PROVIDER:-auto} == auto ]] && ui_dim "Lotus uses Claude from now on (switch with /model inside /ai)."
      fi ;;
    openai)
      ui_header AI "API key"
      ui_text "macOS will ask for the key and keep it in your Keychain (item: lotus-ai)."
      security add-generic-password -U -s lotus-ai -a "$USER" -w && ui_success "Saved in the Keychain" ;;
    remove)
      ui_choose "Remove which key?" "Claude" "OpenAI-compatible API" || return 0
      local item=lotus-ai-claude
      (( REPLY == 2 )) && item=lotus-ai
      ui_confirm "Remove the key \"$item\" from the Keychain?" n || return 0
      security delete-generic-password -s $item >/dev/null 2>&1 && ui_success "Removed" || ui_warn "There was no saved key." ;;
    *) ui_error "Unknown key type" "$which" "Use: lotus ai key claude   or   lotus ai key openai" ;;
  esac
}
