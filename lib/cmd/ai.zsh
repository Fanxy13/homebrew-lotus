# lotus – /ai: the AI terminal and quick AI commands.
# The AI itself is a small Swift program (lib/ai/*.swift), built once on this Mac.
# Providers, tried in this order with LOTUS_AI_PROVIDER=auto:
#   claude  Claude API – key from $ANTHROPIC_API_KEY or the Keychain item "lotus-ai-claude"
#   apple   Apple Intelligence on this Mac (macOS 26+, Apple silicon)
#   ollama  local models through Ollama (http://localhost:11434)
#   openai  any OpenAI-compatible API: LOTUS_AI_URL + key from $LOTUS_AI_KEY or the Keychain item "lotus-ai"
#   local   a model on this Mac with Apple's MLX, set up by lotus ai local (no Ollama needed)
# Lotus never writes API keys to files; they reach the AI program only through its environment.

lotus_cmd_ai() {
  shift   # "ai"
  local sub=$1
  case $sub in
    status)    lotus_ai_status ;;
    local)     shift; lotus_ai_local "$@" ;;
    login|connect) lotus_ai_login ;;
    logout)    lotus_ai_logout ;;
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

typeset -g LOTUS_LOG_COMP=ai

# Path of the built program; the name changes whenever the source changes
lotus_ai_helper() {
  local sum=$(cat $LOTUS_ROOT/lib/ai/*.swift(N) | cksum)
  REPLY=$LOTUS_CACHE/bin/lotus-ai-${sum%% *}
}

_ai_can_build() { lotus_can_swift }

# Builds the program once (about 15 seconds)
_ai_build() {
  lotus_ai_helper
  [[ -x $REPLY ]] && return 0
  if ! _ai_can_build; then
    ui_error "The AI terminal needs Apple's Command Line Tools once" "They contain the compiler Lotus uses to set up the AI." \
      "Install them with: xcode-select --install" "Then run /ai again." >&2
    return 1
  fi
  ui_step "Setting up the AI terminal (one time, about 15 seconds) …" >&2
  if ! lotus_swift_build lotus-ai $LOTUS_ROOT/lib/ai/*.swift; then
    ui_error "Could not set up the AI terminal" "The Swift compiler reported an error." "Details: $LOTUS_CACHE/lotus-ai-build.log" >&2
    return 1
  fi
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

# Picks the provider → REPLY (claude|local|apple|ollama|openai), status 1 when none works
lotus_ai_provider() {
  local want=${LOTUS_AI_PROVIDER:-auto} p
  local -a order=(claude local apple ollama openai)
  [[ $want != auto ]] && order=($want)
  for p in $order; do
    case $p in
      claude) _ai_claude_key && { REPLY=claude; return 0 } ;;
      local)  _llm_ok && { REPLY=local; return 0 } ;;
      apple)  _ai_apple_ok build && { REPLY=apple; return 0 } ;;
      ollama) _ai_ollama_model && { REPLY=ollama; return 0 } ;;
      openai) _ai_openai_ok && { REPLY=openai; return 0 } ;;
    esac
  done
  return 1
}

lotus_ai_none() {
  if ui_has_tty && [[ -t 1 ]]; then
    ui_header AI "no AI connected yet"
    ui_text "Lotus did not find an AI it can use on this Mac."
    ui_blank
    ui_choose "What do you want to do?" "Connect Claude – paste an API key (about a minute)" "Show the other options" "Cancel" || return 1
    case $REPLY in
      1) lotus_ai_login && return 0 ;;
      3) return 1 ;;
    esac
  fi
  ui_error "No AI is available yet" "Lotus did not find an AI it can use on this Mac." \
    "Claude: lotus ai login  (opens the key page, then paste the key)" \
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
  if ! lotus_ai_provider; then
    lotus_ai_none || return 1
    lotus_ai_provider || return 1
  fi
  local provider=$REPLY model=$LOTUS_AI_MODEL url=$LOTUS_AI_URL key=
  lotus_log INFO ai "AI ${mode#--} with $provider (thinking: ${LOTUS_AI_EFFORT:-high})"
  if [[ $provider == local ]]; then
    # the model on this Mac speaks the OpenAI API while /ai runs, then it leaves the memory again
    _llm_start || return 1
    provider=openai url=$REPLY model=$LLM_MODELS/$LOTUS_AI_LOCAL key=local
    _llm_row $LOTUS_AI_LOCAL
    local llm_label="$reply[2] · on this Mac"
  fi
  case $provider in
    claude) [[ $model == claude-* ]] || model= ;;
    ollama) _ai_ollama_model; model=$REPLY ;;
    apple)  model= ;;
  esac
  local -a avail=()
  _ai_claude_key && avail+=claude
  [[ -d /System/Library/Frameworks/FoundationModels.framework ]] && avail+=apple
  _ai_openai_ok && avail+=openai
  local mac_label=
  if _llm_ok; then avail+=local; _llm_row $LOTUS_AI_LOCAL; mac_label="$reply[2]"; fi
  lotus_ai_helper
  local bin=$REPLY
  zf_mkdir -p $LOTUS_CACHE/ai && chmod 700 $LOTUS_CACHE/ai
  (
    export LOTUS_AI_PROVIDER=$provider LOTUS_AI_MODEL=$model LOTUS_AI_EFFORT=${LOTUS_AI_EFFORT:-high}
    export LOTUS_AI_STATE=$LOTUS_CACHE/ai LOTUS_AI_URL=$url LOTUS_AI_AVAILABLE=${(j:,:)avail} LOTUS_AI_LOCAL_LABEL=$mac_label
    export LOTUS_NAME LOTUS_ROOT LOTUS_VERSION
    export LOTUS_AI_TOOLS LOTUS_AI_PERM_READ LOTUS_AI_PERM_READ_OUT LOTUS_AI_PERM_WRITE LOTUS_AI_PERM_WRITE_OUT LOTUS_AI_PERM_RUN
    [[ -n $llm_label ]] && export LOTUS_AI_LABEL=$llm_label LOTUS_AI_CONTEXT=${LOTUS_AI_CONTEXT:-32768}
    export LOTUS_AI_C_LOGO=$LOTUS_C[logo] LOTUS_AI_C_KEY=$LOTUS_C[key] LOTUS_AI_C_ACCENT=$LOTUS_C[accent]
    export LOTUS_AI_C_BORDER=$LOTUS_C[border] LOTUS_AI_C_DIM=$LOTUS_C[dim] LOTUS_AI_C_MUSIC=$LOTUS_C[music]
    _ai_claude_key && export LOTUS_AI_CLAUDE_KEY=$REPLY
    if [[ -n $key ]]; then export LOTUS_AI_OPENAI_KEY=$key; else _ai_openai_key && export LOTUS_AI_OPENAI_KEY=$REPLY; fi
    [[ -n $LOTUS_AI_INSTRUCTIONS ]] && export LOTUS_AI_INSTRUCTIONS
    export LOTUS_LOG LOTUS_LOG_LEVEL LOTUS_VERBOSE
    [[ $mode == (--tui|--once) ]] && _ai_pet
    exec $bin $mode "$@"
  )
  local -i rc=$?
  _llm_stop
  if (( rc == 75 )); then
    # /model chose the model on this Mac: the choice is saved, so start again with it
    lotus_load
    lotus_ai_run $mode "$@"
    return
  fi
  (( rc && rc != 130 )) && lotus_log WARN ai "The AI program ended with status $rc"
  return rc
}

# The pet of the day comes along into the AI terminal: the welcome box shows it, and while the AI
# thinks the spinner is the whole pet, blinking and wagging (environment only – the AI program draws it)
_ai_pet() {
  lotus_feature_on pets && [[ -s $LOTUS_CONF/pets.tsv ]] || return 0
  (( ${+functions[_pet_load]} )) || source $LOTUS_ROOT/lib/cmd/pets.zsh
  _pet_load; _pet_species
  (( ${#PET_N} )) || return 0
  local -i day idx
  strftime -s day %j $EPOCHSECONDS
  (( idx = day % ${#PET_N} + 1 ))
  _pet_kind $idx
  local kind=$REPLY
  _pet_color $idx
  export LOTUS_AI_PET_NAME=$PET_N[idx] LOTUS_AI_PET_COLOR=$REPLY LOTUS_AI_PET_ART=${PET_ART[$kind,idle]}
  export LOTUS_AI_PET_ART_BLINK=${PET_ART[$kind,blink]} LOTUS_AI_PET_ART_WAG=${PET_ART[$kind,wag]}
  export LOTUS_AI_PET_MINI=${PET_INFO[$kind,mini]:-${PET_INFO[$kind,face]}} LOTUS_AI_PET_MINI_BLINK=$PET_INFO[$kind,mini_blink]
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
  else print -r -- "  $no Claude              connect: lotus ai login"; fi
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
  if _llm_ok; then _llm_row $LOTUS_AI_LOCAL; print -r -- "  $ok On this Mac         $reply[2] (MLX)  · lotus ai local"
  else print -r -- "  $no On this Mac         a model that runs here, without Ollama: lotus ai local"; fi
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
    claude|anthropic) lotus_ai_login ;;
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
    *) ui_error "Unknown key type" "$which" "Use: lotus ai login   or   lotus ai key openai" ;;
  esac
}

# ── Connecting Claude ─────────────────────────────────────────

# Opens the key page, takes the pasted key (hidden), checks it with Claude and keeps it in the Keychain.
# The key never appears on screen, in a file or on a command line (it goes through stdin).
lotus_ai_login() {
  ui_header AI "connect Claude"
  if ! ui_has_tty; then
    ui_error "This needs a terminal window" "" "Run: lotus ai login"
    return 1
  fi
  ui_text "1  Sign in at console.anthropic.com and click \"Create Key\" (any name, e.g. Lotus)."
  ui_text "2  Copy the key and paste it here. Lotus checks it and keeps it in your Keychain."
  ui_dim "   Claude is paid per use by Anthropic – a typical question costs well under one cent."
  ui_blank
  ui_confirm "Open the key page in your browser now?" y && open "https://console.anthropic.com/settings/keys"
  ui_blank
  local key tries=0
  while (( tries++ < 3 )); do
    print -rn -- "  Paste your key "$'\e['"$LOTUS_C[dim]m(hidden, Enter when done)"$'\e[0m'": "
    read -rs key < /dev/tty || return 1
    key=${key//[[:space:]]/}
    if [[ -z $key ]]; then print; ui_info "Cancelled"; return 1; fi
    print -r -- $'\e['"$LOTUS_C[dim]m••••••••••••${key[-4,-1]}"$'\e[0m'
    if [[ $key != sk-ant-[A-Za-z0-9_-]## ]]; then
      ui_warn "That is not a Claude API key – they start with sk-ant-. Try again or press Enter to stop."
      continue
    fi
    ui_step "Checking the key with Claude …"
    local code=$(print -r -- "header = \"x-api-key: $key\"" | curl -sS -o /dev/null -w '%{http_code}' -m 20 -K - \
      -H 'anthropic-version: 2023-06-01' https://api.anthropic.com/v1/models 2>/dev/null)
    case $code in
      200) break ;;
      401|403) ui_warn "Claude did not accept this key. Copy it again (all of it) or create a new one."; continue ;;
      000) ui_warn "Claude could not be reached right now – the key is saved anyway."; break ;;
      *) ui_warn "Claude answered with $code – the key is saved anyway."; break ;;
    esac
  done
  (( tries > 3 )) && return 1
  print -r -- "add-generic-password -U -s lotus-ai-claude -a ${USER:-lotus} -w $key" | security -i >/dev/null 2>&1
  if [[ $(security find-generic-password -s lotus-ai-claude -w 2>/dev/null) != $key ]]; then
    ui_error "The key could not be saved in the Keychain" "" "Try again, or set ANTHROPIC_API_KEY in your ~/.zshrc."
    return 1
  fi
  if [[ ${LOTUS_AI_PROVIDER:-auto} != (auto|claude) ]]; then
    LOTUS_AI_PROVIDER=claude
    [[ $LOTUS_AI_MODEL == claude-* ]] || LOTUS_AI_MODEL=
    lotus_save
  fi
  lotus_log INFO ai "Claude connected (key in the Keychain)"
  ui_success "Claude is connected"
  ui_dim "Type /ai to start. Inside, /model switches between Opus, Sonnet and Haiku."
  ui_blank
}

lotus_ai_logout() {
  if ! security find-generic-password -s lotus-ai-claude >/dev/null 2>&1; then
    ui_info "No Claude key is saved."
    return 0
  fi
  ui_confirm "Remove the Claude key from your Keychain?" n || return 0
  security delete-generic-password -s lotus-ai-claude >/dev/null 2>&1 && ui_success "Claude is disconnected"
  [[ $LOTUS_AI_PROVIDER == claude ]] && { LOTUS_AI_PROVIDER=auto; lotus_save }
}

# ── A model on this Mac: Apple's MLX, without Ollama ──────────
# lotus ai local                   your models: download, use, remove – and the settings
# lotus ai local <id|owner/repo>   download and use a model from the list, or any MLX model on Hugging Face
# lotus ai local use|remove <id>   switch to a downloaded model · delete one (remove all: everything)
# lotus ai local settings          thinking, context window, answer length, creativity, memory saver
# The model runs in Lotus' own Python environment (mlx-lm, pinned) and is started only while /ai
# runs – it listens on 127.0.0.1 only and leaves the memory when /ai ends.

typeset -g LLM_RUNTIME=$LOTUS_DATA/runtime/llm LLM_MODELS=$LOTUS_DATA/llm LLM_MLX=mlx-lm==0.32.0
typeset -gi LLM_PORT=18765 LLM_PID=0

_llm_row() {   # <id> → reply (id label repo revision GB RAM text)
  local line
  for line in "${(@f)$(<$LOTUS_ROOT/data/llm-models.tsv)}"; do
    [[ $line == \#* || -z $line ]] && continue
    [[ ${line%%$'\t'*} == $1 ]] && { reply=("${(@ps:\t:)line}"); return 0 }
  done
  reply=($1 ${1#*/} $1 main '?' 16 'a model from Hugging Face')
  [[ $1 == */* ]]
}

_llm_ok() { [[ -n $LOTUS_AI_LOCAL && -x $LLM_RUNTIME/bin/mlx_lm.server && -r $LLM_MODELS/$LOTUS_AI_LOCAL/config.json ]] }

_llm_ram() { REPLY=$(( $(sysctl -n hw.memsize 2>/dev/null || print 0) / 1073741824 )) }

# Python 3.11–3.14 for arm64 → REPLY
_llm_python() {
  local p v
  for p in /opt/homebrew/bin/python3.1{3,2,4,1} /usr/local/bin/python3.1{3,2,4,1} $commands[python3] /usr/bin/python3; do
    [[ -x $p ]] || continue
    [[ $p == /usr/bin/python3 ]] && ! xcode-select -p >/dev/null 2>&1 && continue
    v=$(arch -arm64 $p -c 'import sys, venv, platform; print("%d.%d %s" % (sys.version_info[:2] + (platform.machine(),)))' 2>/dev/null) || continue
    [[ $v == 3.1[1-4]\ arm64 ]] && { REPLY=$p; return 0 }
  done
  return 1
}

lotus_ai_local() {
  [[ $(uname -m) == arm64 ]] || { ui_error "Local models need Apple silicon" "" "On this Mac: Ollama, or an OpenAI-compatible API (/settings)"; return 1 }
  case $1 in
    ''|list)  _llm_screen ;;
    settings) _llm_settings ;;
    use)      _llm_use "$2" ;;
    remove)   _llm_remove "${2:-all}" ;;
    *)        _llm_install "$1" ;;
  esac
}

_llm_have() { [[ -n $1 && -r $LLM_MODELS/$1/config.json ]] }
_llm_size() { REPLY=$(du -sh $LLM_MODELS/$1 2>/dev/null | cut -f1); REPLY=${REPLY:-0} }

# A bar of <width> cells: <part> of <whole> filled → REPLY (colored: fits, tight, too big)
_llm_bar() {   # <part> <whole> <width> [color]
  local -F part=$1 whole=$2
  local -i w=$3 n
  (( whole > 0 )) || whole=1
  (( n = part / whole * w + 0.5, n = n > w ? w : n, n = n < 0 ? 0 : n ))
  local c=${4:-$LOTUS_C[key]}
  REPLY=$'\e['"${c}m${(l:n::━:)}"$'\e['"$LOTUS_C[dim]m${(l:w-n::─:)}"$'\e[39m'
}

# The Hugging Face token (optional: faster downloads, higher limits) – from $HF_TOKEN or the Keychain
_llm_token() { REPLY=${HF_TOKEN:-$(security find-generic-password -s lotus-hf -w 2>/dev/null)}; [[ -n $REPLY ]] }

# Connect or remove the token: the page opens, the token is pasted hidden, checked and kept in the Keychain
_llm_token_flow() {
  print -n $'\e[H\e[2J'
  ui_hero "AI on this Mac · Faster downloads" "A free Hugging Face account gives faster downloads and higher limits. Optional – downloads work without it."
  if _llm_token; then
    ui_text "A token is connected (Keychain item lotus-hf)."
    ui_blank
    ui_confirm "Remove it?" n || return 0
    security delete-generic-password -s lotus-hf >/dev/null 2>&1
    ui_success "Removed – downloads continue without an account"
    return 0
  fi
  ui_text "1  Sign in at huggingface.co (or create a free account)."
  ui_text "2  Create a token with the type \"Read\" and copy it."
  ui_text "3  Paste it here – Lotus checks it and keeps it in your Keychain."
  ui_blank
  ui_confirm "Open the token page now?" y && open "https://huggingface.co/settings/tokens"
  ui_blank
  local tok name
  print -rn -- "  Paste the token "$'\e['"$LOTUS_C[dim]m(hidden, Enter when done)"$'\e[0m'": "
  read -rs tok < /dev/tty || return 1
  print
  tok=${tok//[[:space:]]/}
  [[ -n $tok ]] || { ui_info $LOTUS_L[cancelled]; return 0 }
  [[ $tok == hf_[A-Za-z0-9]## ]] || { ui_warn "That is not a Hugging Face token – they start with hf_"; return 1 }
  ui_step "Checking it with Hugging Face …"
  name=$(print -r -- "header = \"Authorization: Bearer $tok\"" | curl -fsS -m 15 -K - https://huggingface.co/api/whoami-v2 2>/dev/null | lotus_jq -r '.name // empty' 2>/dev/null)
  [[ -n $name ]] || { ui_warn "Hugging Face did not accept this token – copy all of it and try again."; return 1 }
  print -r -- "add-generic-password -U -s lotus-hf -a ${USER:-lotus} -w $tok" | security -i >/dev/null 2>&1
  _llm_token || { ui_error "The token could not be saved in the Keychain"; return 1 }
  lotus_log INFO ai "Hugging Face token connected (Keychain)"
  ui_success "Connected as $name – downloads are faster now"
}

# Downloads a model with Lotus' own progress line (no Hugging Face output on screen):
#   ━━━━━━━━━━━━━━━━━━──────────  62 %
#   7.5 of 12.1 GB · 31 MB/s · 2 min left
# esc or Ctrl-C stops it; the next start continues where it stopped.
_llm_fetch() {   # <repo> <revision> <id> <label> <GB>
  local repo=$1 rev=$2 dir=$LLM_MODELS/$3 label=$4 log=$LOTUS_CACHE/llm/download.log tok=
  local -F total=0 got=0 last=0 speed=0 t0=$EPOCHREALTIME tl=$EPOCHREALTIME now
  local -i pid rc left tty=0 drawn=0
  total=$(curl -fsS -m 10 "https://huggingface.co/api/models/$repo?blobs=true" 2>/dev/null | lotus_jq '[.siblings[].size // 0] | add' 2>/dev/null)
  (( total > 0 )) || total=$(( ${5:-0} * 1e9 ))
  _llm_token && tok=$REPLY
  zf_mkdir -p $dir ${log:h}
  (
    export HF_HUB_DISABLE_TELEMETRY=1 HF_HUB_DISABLE_PROGRESS_BARS=1 HF_HUB_VERBOSITY=error
    [[ -n $tok ]] && export HF_TOKEN=$tok
    exec $LLM_RUNTIME/bin/python -c 'import sys; from huggingface_hub import snapshot_download as d; d(repo_id=sys.argv[1], revision=sys.argv[2], local_dir=sys.argv[3])' $repo $rev $dir
  ) >| $log 2>&1 &
  pid=$!
  LLM_PID=$pid    # if Lotus ends, the download ends too (bin/lotus' EXIT trap); it continues next time
  lotus_log INFO ai "Downloading $repo@$rev${tok:+ (with a Hugging Face token)}"
  [[ -t 1 ]] && ui_has_tty && tty=1
  local B=$'\e[1m' R0=$'\e[0m' D=$'\e['"$LOTUS_C[dim]m"
  print
  ui_text "${B}Downloading $label${R0}${tok:+  ${D}with your Hugging Face account${R0}}"
  UI_INT=0
  (( tty )) && { TRAPINT() { UI_INT=1; return 0 }; print -n $'\e[?25l' }
  while kill -0 $pid 2>/dev/null; do
    got=$(( $(du -sk $dir 2>/dev/null | cut -f1) * 1024.0 ))
    now=$EPOCHREALTIME
    if (( now - tl >= 1.5 )); then
      (( speed = speed > 0 ? speed * 0.6 + (got - last) / (now - tl) * 0.4 : (got - last) / (now - tl), last = got, tl = now ))
    fi
    if (( tty )); then
      _llm_bar $got $total 36
      local -i pct
      (( pct = total > 0 ? got * 100 / total : 0 ))
      (( pct > 99 )) && pct=99
      local info="$(printf '%.1f' $(( got / 1e9 ))) of $(printf '%.1f' $(( total / 1e9 ))) GB"
      if (( speed >= 1e6 )); then info+=" · $(printf '%.0f' $(( speed / 1e6 ))) MB/s"
      elif (( speed >= 1e3 )); then info+=" · $(printf '%.0f' $(( speed / 1e3 ))) KB/s"; fi
      # a time only once the speed is known and steady
      if (( speed > 5e4 && total > got && now - t0 > 4 )); then
        (( left = (total - got) / speed ))
        if (( left >= 3600 )); then info+=" · about $(( left / 3600 )) h $(( left % 3600 / 60 )) min left"
        elif (( left >= 60 )); then info+=" · about $(( (left + 59) / 60 )) min left"
        else info+=" · less than a minute"; fi
      fi
      (( drawn )) && print -n $'\e[2A'
      print -r -- $'\r\e[K'"    $REPLY  "$'\e[1m'"$pct %"$'\e[0m'
      print -r -- $'\r\e[K'"    "$'\e['"$LOTUS_C[dim]m$info · esc stops – it continues next time"$'\e[0m'
      drawn=1
      ui_keyx 0.5
      [[ $REPLY == (esc|interrupt) ]] && { kill $pid 2>/dev/null; break }
    else
      zselect -t 100 2>/dev/null || sleep 1
    fi
  done
  wait $pid 2>/dev/null; rc=$?
  LLM_PID=0
  (( tty )) && { unfunction TRAPINT 2>/dev/null; [[ -t 1 ]] && trap 'exit 130' INT; print -n $'\e[?25h' }
  if (( rc == 0 )) && [[ -r $dir/config.json ]]; then
    local -i secs=$(( EPOCHREALTIME - t0 ))
    (( drawn )) && print -n $'\e[2A'
    _llm_bar 1 1 36
    print -r -- $'\r\e[K'"    $REPLY  "$'\e[1m'"100 %"$'\e[0m'
    print -r -- $'\r\e[K'"    "$'\e['"$LOTUS_C[dim]m$(printf '%.1f' $(( total / 1e9 ))) GB in $(( secs / 60 )) min $(( secs % 60 )) s"$'\e[0m'
    return 0
  fi
  lotus_log WARN ai "Download stopped: $repo (${$(tail -1 $log 2>/dev/null)[1,200]})"
  return 1
}

# Every model with how much memory it needs (the bar: green fits, yellow tight, red too big),
# whether it is here, the settings and the token
_llm_screen() {
  local -i sel=1 ram n
  local line st badge fit
  local -a ids opts f
  if ! { [[ -t 1 ]] && ui_has_tty }; then
    for line in $LLM_MODELS/*(/N); do _llm_size ${line:t}; print -r -- "${line:t}  $REPLY${${(M)${line:t}:#$LOTUS_AI_LOCAL}:+  (in use)}"; done
    return 0
  fi
  _llm_ram; ram=$REPLY
  local -A th=(low "quick" medium balanced high thorough max maximum)
  local g=$'\e['"$LOTUS_C[key]m" y=$'\e['"$LOTUS_C[key2]m" r=$'\e[38;5;203m' d=$'\e['"$LOTUS_C[dim]m" x=$'\e[39m'
  while :; do
    print -n $'\e[H\e[2J'
    ui_hero "AI on this Mac" "Apple's MLX · no Ollama · nothing leaves your Mac"
    _llm_bar $(( ram * 0.7 )) $ram 24
    print -r -- "    ${d}Memory${x}   $REPLY  ${d}$ram GB · about $(( ram * 7 / 10 )) GB for a model${x}"
    bg_free_gb 2>/dev/null || { (( ${+functions[bg_free_gb]} )) || source $LOTUS_ROOT/lib/bg/runtime.zsh; bg_free_gb }
    print -r -- "    ${d}Disk${x}     ${d}${$(du -sh $LLM_MODELS 2>/dev/null | cut -f1):-nothing} in models · $REPLY GB free${x}"
    _llm_token && print -r -- "    ${d}Account${x}  ${g}✓${x} ${d}Hugging Face token – fast downloads${x}"
    ui_blank
    ids=() opts=()
    local -i dw=$(( ${COLUMNS:-100} - 52 ))
    (( dw < 10 )) && dw=10
    for line in "${(@f)$(<$LOTUS_ROOT/data/llm-models.tsv)}"; do
      [[ $line == \#* || -z $line ]] && continue
      f=("${(@ps:\t:)line}")
      # needs: download size plus room for the context
      local -F need=$(( f[5] * 1.15 ))
      if (( need <= ram * 0.62 )); then fit=$LOTUS_C[key]
      elif (( need <= ram * 0.85 )); then fit=$LOTUS_C[key2]
      else fit="38;5;203"; fi
      _llm_bar $need $(( ram * 0.85 )) 8 $fit
      badge=$REPLY
      if [[ $f[1] == $LOTUS_AI_LOCAL ]] && _llm_have $f[1]; then st="${g}${(r:10:):-● in use}${x}"
      elif _llm_have $f[1]; then st="${g}${(r:10:):-✓ here}${x}"
      else st="${d}${(r:10:):-↓ ${f[5]} GB}${x}"; fi
      ids+=($f[1])
      opts+=("${(r:18:)f[2]}  $badge  $st  $d${${f[7]%% – *}[1,dw]}$x")
    done
    for line in $LLM_MODELS/*--*(/N); do
      _llm_have ${line:t} || continue      # a download that stopped half way is not listed
      ids+=(${line:t})
      st="✓ here"; [[ ${line:t} == $LOTUS_AI_LOCAL ]] && st="● in use"
      opts+=("${(r:18:)${${line:t}#*--}[1,18]}  ${d}········${x}  ${g}${(r:10:)st}${x}  $d${${${line:t}//--//}[1,dw]}$x")
    done
    local -i ow=$(( ${COLUMNS:-100} - 30 ))
    local sd="thinking ${th[${LOTUS_AI_EFFORT:-high}]} · context $(( ${LOTUS_AI_CONTEXT:-32768} / 1024 ))K · answers up to $(( ${LOTUS_AI_MAXTOKENS:-8192} / 1024 ))K · creativity ${LOTUS_AI_TEMP:-0.6}"
    opts+=("${(r:18:):-Settings}  $d${sd[1,ow]}$x")
    if _llm_token; then opts+=("${(r:18:):-Faster downloads}  $d${${:-Hugging Face token connected – remove it}[1,ow]}$x")
    else opts+=("${(r:18:):-Faster downloads}  $d${${:-connect a free Hugging Face account (optional)}[1,ow]}$x"); fi
    n=0; for line in $ids; do _llm_have $line && (( n++ )); done
    (( n )) && opts+=("${(r:18:):-Remove everything}  $d${${:-all $n model(s) and the MLX environment}[1,ow]}$x")
    ui_select $sel "${opts[@]}" || break
    sel=$REPLY
    if (( sel <= ${#ids} )); then _llm_model ${ids[sel]}
    elif (( sel == ${#ids} + 1 )); then _llm_settings
    elif (( sel == ${#ids} + 2 )); then _llm_token_flow; ui_dim "  $LOTUS_L[back]"; ui_key
    else _llm_remove all; ui_dim "  $LOTUS_L[back]"; ui_key; fi
  done
  print -n $'\e[H\e[2J'
}

# One model: use it or remove it – or download it
_llm_model() {
  local id=$1
  if ! _llm_have $id; then
    print -n $'\e[H\e[2J'
    _llm_install $id
    ui_dim "  $LOTUS_L[back]"; ui_key
    return
  fi
  _llm_row $id; local label=$reply[2]
  _llm_size $id; local size=$REPLY
  print -n $'\e[H\e[2J'
  ui_hero "AI on this Mac · $label" "$size on disk${${(M)id:#$LOTUS_AI_LOCAL}:+ · in use}"
  ui_select 1 "Use it|/ai answers with $label" "Remove it|deletes it and frees $size" "Back|" || return 0
  case $REPLY in
    1) _llm_use $id; ui_dim "  $LOTUS_L[back]"; ui_key ;;
    2) _llm_remove $id; ui_dim "  $LOTUS_L[back]"; ui_key ;;
  esac
}

_llm_use() {
  local id=${1//\//--}
  _llm_have $id || { ui_error "Not downloaded" "$1" "Download it first: lotus ai local $1"; return 1 }
  LOTUS_AI_LOCAL=$id LOTUS_AI_PROVIDER=local
  lotus_save
  _llm_row $id
  ui_success "/ai uses $reply[2] now"
}

# Removes one model (or "all": every model and the MLX environment) – after a yes
_llm_remove() {
  local id=${1//\//--} what
  if [[ $id == all ]]; then
    ui_confirm "Remove all local models and the MLX environment ($(du -shc $LLM_MODELS $LLM_RUNTIME 2>/dev/null | tail -1 | cut -f1))?" n || return 0
    rm -rf -- "${LLM_MODELS:?}" "${LLM_RUNTIME:?}"
    LOTUS_AI_LOCAL=
  else
    [[ $id == [A-Za-z0-9._-]## ]] && _llm_have $id || { ui_error "Not downloaded" "$1"; return 1 }
    _llm_row $id; what=$reply[2]
    _llm_size $id
    ui_confirm "Remove $what ($REPLY)?" n || return 0
    rm -rf -- "${LLM_MODELS:?}/${id:?}"
    [[ $id == $LOTUS_AI_LOCAL ]] && LOTUS_AI_LOCAL=
  fi
  [[ -z $LOTUS_AI_LOCAL && $LOTUS_AI_PROVIDER == local ]] && LOTUS_AI_PROVIDER=auto
  lotus_save
  lotus_log INFO ai "Local model removed: $id"
  ui_success "Removed"
}

# Thinking, context window, answer length, creativity, memory saver – Enter changes a value
_llm_cycle() {   # <value> <values…> → REPLY = the next one
  local v=$1; shift
  local -i i=${@[(ie)$v]}
  (( i >= $# )) && i=0
  REPLY=${@[i+1]}
}
_llm_settings() {
  local -i sel=1
  local -A th=(low "quick – no thinking" medium balanced high thorough max maximum) tp=(0.2 precise 0.6 balanced 1.0 creative)
  while :; do
    print -n $'\e[H\e[2J'
    ui_hero "AI on this Mac · Settings" "Used when /ai starts a model on this Mac. Thinking counts for Claude and Ollama too."
    ui_select $sel \
      "Thinking|${th[${LOTUS_AI_EFFORT:-high}]} – how long it thinks before it answers" \
      "Context window|$(( ${LOTUS_AI_CONTEXT:-32768} / 1024 ))K tokens – how much of the conversation it keeps; more needs more memory" \
      "Answer length|up to $(( ${LOTUS_AI_MAXTOKENS:-8192} / 1024 ))K tokens per answer, thinking included" \
      "Creativity|${tp[${LOTUS_AI_TEMP:-0.6}]:-$LOTUS_AI_TEMP} – precise for code, creative for texts" \
      "Memory saver|${${LOTUS_AI_KVBITS:#0}:+on – the context takes half the memory, slightly less exact}${${(M)LOTUS_AI_KVBITS:#0}:+off}" || break
    sel=$REPLY
    case $sel in
      1) _llm_cycle ${LOTUS_AI_EFFORT:-high} low medium high max; LOTUS_AI_EFFORT=$REPLY ;;
      2) _llm_cycle ${LOTUS_AI_CONTEXT:-32768} 8192 16384 32768 65536 131072; LOTUS_AI_CONTEXT=$REPLY ;;
      3) _llm_cycle ${LOTUS_AI_MAXTOKENS:-8192} 2048 4096 8192 16384 32768; LOTUS_AI_MAXTOKENS=$REPLY ;;
      4) _llm_cycle ${LOTUS_AI_TEMP:-0.6} 0.2 0.6 1.0; LOTUS_AI_TEMP=$REPLY ;;
      5) (( LOTUS_AI_KVBITS )) && LOTUS_AI_KVBITS=0 || LOTUS_AI_KVBITS=8 ;;
    esac
    lotus_save
  done
}

# Downloads <id> (from the list, or owner/repo) after a yes, and uses it
_llm_install() {
  local want=$1 line
  _llm_ram; local -i ram=$REPLY
  if ! _llm_row $want; then ui_error "Unknown model" "$want" "Choose from: lotus ai local   or name a Hugging Face repository: owner/model"; return 1; fi
  local id=$reply[1] label=$reply[2] repo=$reply[3] rev=$reply[4] gb=$reply[5] need=$reply[6]
  [[ $repo == [A-Za-z0-9_.-]##/[A-Za-z0-9_.-]## && $rev == [A-Za-z0-9_.-]## ]] || { ui_error "Not a Hugging Face repository" "$repo"; return 1 }
  id=${id//\//--}
  if [[ $gb == '?' ]]; then   # a model from Hugging Face: ask how big it is
    local -F bytes=$(curl -fsS -m 10 "https://huggingface.co/api/models/$repo?blobs=true" 2>/dev/null | lotus_jq '[.siblings[].size // 0] | add' 2>/dev/null)
    (( bytes > 0 )) && gb=$(printf '%.1f' $(( bytes / 1e9 )))
  fi
  (( need > ram )) && ui_warn "$label wants about $need GB of memory – this Mac has $ram GB."
  local -i fresh=0
  [[ -x $LLM_RUNTIME/bin/mlx_lm.server ]] || fresh=1
  if [[ ! -r $LLM_MODELS/$id/config.json ]] || (( fresh )); then
    ui_blank
    ui_kv Model "$label · $repo"
    ui_kv Download "${${(M)fresh:#1}:+about 0.3 GB for the environment (mlx-lm) + }$gb GB for the model"
    ui_kv Where "~/.local/share/lotus"
    ui_blank
    ui_confirm "Download now?" y || return 0
  fi
  if (( fresh )); then
    _llm_python || { ui_error "Python 3.11 or newer is missing" "" "Install it with: brew install python@3.13"; return 1 }
    ui_step "Setting up the environment …"
    rm -rf -- "${LLM_RUNTIME:?}"
    { $REPLY -m venv $LLM_RUNTIME && $LLM_RUNTIME/bin/python -m pip --disable-pip-version-check --no-input -q install $LLM_MLX } 2>&1 | tail -3
    [[ -x $LLM_RUNTIME/bin/mlx_lm.server ]] || { rm -rf -- "${LLM_RUNTIME:?}"; ui_error "mlx-lm could not be installed" "" "Details above – try again later"; return 1 }
    lotus_log INFO ai "Local AI environment: $LLM_MLX"
  fi
  if [[ ! -r $LLM_MODELS/$id/config.json ]]; then
    zf_mkdir -p $LLM_MODELS
    _llm_fetch $repo $rev $id $label $gb || { ui_error "The download stopped" "$repo" "Run lotus ai local $want again – it continues where it stopped"; return 1 }
    lotus_log INFO ai "Local model downloaded: $repo@$rev"
  fi
  LOTUS_AI_LOCAL=$id LOTUS_AI_PROVIDER=local
  lotus_save
  ui_success "$label is ready – /ai uses it now (switch back in /settings → AI)"
  ui_dim "  It loads when /ai starts (some seconds) and leaves the memory when /ai ends."
}

# Starts the model server (127.0.0.1 only) unless it runs → REPLY = API URL
_llm_start() {
  local url=http://127.0.0.1:$LLM_PORT/v1 log=$LOTUS_CACHE/llm/server.log
  curl -fsS -m 1 $url/models >/dev/null 2>&1 && { REPLY=$url; return 0 }
  _llm_row $LOTUS_AI_LOCAL
  zf_mkdir -p ${log:h}
  local effort=${LOTUS_AI_EFFORT:-high} think=true
  [[ $effort == low ]] && think=false
  [[ $effort == max ]] && effort=high
  local -a opts=(--max-tokens ${LOTUS_AI_MAXTOKENS:-8192} --temp ${LOTUS_AI_TEMP:-0.6} --top-p 0.95
    --chat-template-args "{\"enable_thinking\": $think, \"reasoning_effort\": \"$effort\"}")
  (( LOTUS_AI_KVBITS )) && opts+=(--kv-bits $LOTUS_AI_KVBITS)
  $LLM_RUNTIME/bin/mlx_lm.server --model $LLM_MODELS/$LOTUS_AI_LOCAL --host 127.0.0.1 --port $LLM_PORT $opts >| $log 2>&1 &!
  LLM_PID=$!   # bin/lotus' EXIT trap stops it too (Ctrl-C) – a trap set here would run when this function returns
  local -i i
  for (( i = 0; i < 360; i++ )); do
    print -rn -- $'\r\e[K'"  "$'\e['"$LOTUS_C[dim]m… Loading $reply[2] into memory ($(( i / 2 ))s)"$'\e[0m' >&2
    curl -fsS -m 1 $url/models >/dev/null 2>&1 && { print -rn -- $'\r\e[K' >&2; REPLY=$url; return 0 }
    kill -0 $LLM_PID 2>/dev/null || break
    zselect -t 50 2>/dev/null || sleep 0.5
  done
  print -rn -- $'\r\e[K' >&2
  _llm_stop
  ui_error "The local model did not start" "$reply[2]" "${(f)$(tail -3 $log 2>/dev/null)}" "Details: $log" >&2
  return 1
}

_llm_stop() { (( LLM_PID )) && kill $LLM_PID 2>/dev/null; LLM_PID=0; return 0 }
