# lotus ai local: models with a sliding window (gpt-oss, Gemma) run without the memory saver – mlx cannot
# compress their cache, and every answer broke off once a conversation reached about 5000 tokens. A server
# that an older Lotus started that way is started again. The model server is a stand-in on its own port.
source $LOTUS_ROOT/lib/core.zsh
source $LOTUS_ROOT/lib/ui.zsh
lotus_load
source $LOTUS_ROOT/lib/cmd/ai.zsh
zmodload zsh/zselect 2>/dev/null

LLM_MODELS=$HOME/models LLM_RUNTIME=$HOME/rt LLM_PORT=18999
zf_mkdir -p $LLM_MODELS/gpt-oss-20b $LLM_MODELS/qwen $LLM_MODELS/gemma $LLM_RUNTIME/bin
print -r -- '{"model_type": "gpt_oss", "sliding_window": 128, "layer_types": ["sliding_attention", "full_attention"]}' >| $LLM_MODELS/gpt-oss-20b/config.json
print -r -- '{"model_type": "qwen3", "sliding_window": 32768, "use_sliding_window": false}' >| $LLM_MODELS/qwen/config.json
print -r -- '{"model_type": "gemma3", "text_config": {"sliding_window": 1024}}' >| $LLM_MODELS/gemma/config.json
check "gpt-oss has a sliding window" _llm_slides gpt-oss-20b
check "Gemma too" _llm_slides gemma
check "Qwen does not (its window is off)" eval '! _llm_slides qwen'

# the stand-in: writes what it was started with, runs until it is stopped
cat >| $LLM_RUNTIME/bin/mlx_lm.server <<'STUB'
#!/bin/zsh
trap 'rm -f $HOME/args; exit 0' TERM
print -r -- "$*" >| $HOME/args
sleep 60 &
wait
STUB
chmod +x $LLM_RUNTIME/bin/mlx_lm.server
curl() { pgrep -qf "$LLM_RUNTIME/bin/mlx_lm.server" && [[ -e $HOME/args ]] }      # "it answers"

LOTUS_AI_KVBITS=8 LOTUS_AI_LOCAL=qwen
_llm_start 2>/dev/null
check_has "Qwen gets the memory saver" "$(<$HOME/args)" "--kv-bits 8"
check_has "and a limit for the prompt cache – ten whole conversations filled the memory" "$(<$HOME/args)" "--prompt-cache-size 4 --prompt-cache-bytes"
# a server that an older Lotus started with it, now for gpt-oss: Lotus starts it again without
LOTUS_AI_LOCAL=gpt-oss-20b
_llm_start 2>/dev/null
check_eq "a server started with it for gpt-oss: started again" "$REPLY" "http://127.0.0.1:18999/v1"
check "now without the memory saver" eval '[[ -e $HOME/args && $(<$HOME/args) == *"--model $LLM_MODELS/gpt-oss-20b"* && $(<$HOME/args) != *--kv-bits* ]]'
check_has "and the log says why" "$(<$LOTUS_STATE/lotus.log)" "without the memory saver"
args=$(<$HOME/args)
_llm_start 2>/dev/null
check_eq "a right one is kept as it is" "$(<$HOME/args)" "$args"
# out of memory: mlx still answers, but its generation thread is gone – it starts again
print -r -- "RuntimeError: generation thread died" >> $LOTUS_CACHE/llm/server.log
before=$(pgrep -f "$LLM_RUNTIME/bin/mlx_lm.server")
_llm_start 2>/dev/null
check "a server that crashed is started again" eval '[[ -n $before && $(pgrep -f "$LLM_RUNTIME/bin/mlx_lm.server") != $before ]]'
check_has "and the log says why" "$(<$LOTUS_STATE/lotus.log)" "it had crashed (out of memory)"
# one an older Lotus started without the limit
pkill -f "$LLM_RUNTIME/bin/mlx_lm.server"; for i in {1..50}; do curl || break; sleep 0.1; done
rm -f $HOME/args
$LLM_RUNTIME/bin/mlx_lm.server --model $LLM_MODELS/gpt-oss-20b --host 127.0.0.1 --port 18999 --max-tokens 8192 >/dev/null 2>&1 &!
for i in {1..50}; do curl && break; sleep 0.1; done
_llm_start 2>/dev/null
check_has "a server without the limit is started again with it" "$(<$HOME/args)" "--prompt-cache-bytes"
# lotus ai local restart
before=$(pgrep -f "$LLM_RUNTIME/bin/mlx_lm.server")
_llm_ok() { true }
_llm_restart 2>/dev/null
check "lotus ai local restart: a new server" eval '[[ $(pgrep -f "$LLM_RUNTIME/bin/mlx_lm.server") != $before && -e $HOME/args ]]'
_llm_stop
pkill -f "$LLM_RUNTIME/bin/mlx_lm.server" 2>/dev/null
