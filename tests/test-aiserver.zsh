# The AI web chat (lotus ai server): settings, port, 127.0.0.1 only, the access key and the request
# checks, a streamed answer with a question answered from "the browser", the permissions and settings of
# the browser (auto mode, don't ask again, what never runs), memory, context, compact, improving prompts, stop.
# The answers come from tests/fake-openai.py – an OpenAI-compatible model on this Mac, no real AI needed.
source $LOTUS_ROOT/lib/core.zsh
source $LOTUS_ROOT/lib/ui.zsh
lotus_load
lotus() { $LOTUS_ROOT/bin/lotus "$@" }
zmodload zsh/net/tcp

check_eq "the default port is 3000" "$LOTUS_AI_SERVER_PORT" 3000
check_eq "it does not start with the terminal unless turned on" "$LOTUS_AI_SERVER_BOOT" 0
check_eq "other devices are off by default" "$LOTUS_AI_SERVER_LAN" 0
check_has "off at first" "$(lotus ai server status)" "off (port 3000)"

lotus ai server port abc >/dev/null 2>&1; check_eq "a port must be a number" $? 2
lotus ai server port 80 >/dev/null 2>&1; check_eq "ports below 1024 are refused" $? 2
lotus ai server port 70000 >/dev/null 2>&1; check_eq "ports above 65535 are refused" $? 2
lotus_load
check_eq "a refused port changes nothing" "$LOTUS_AI_SERVER_PORT" 3000

if ! lotus_can_swift || ! (( $+commands[python3] && $+commands[curl] )); then
  print -r -- "  - the server checks need the Command Line Tools, python3 and curl – skipped"
  return 0
fi

# the AI program, built in this test's home (about 10 seconds)
source $LOTUS_ROOT/lib/cmd/ai.zsh
_ai_build 2>/dev/null
lotus_ai_helper
bin=$REPLY
check "the AI program builds" test -x $bin

# two free ports: the web chat and the test model
typeset -i port=0 mport=0 p
for (( p = 39100 + RANDOM % 600; p < 39900; p++ )); do
  [[ $($bin --port-check $p) == free ]] || continue
  if (( ! mport )); then mport=p; else port=p; break; fi
done
python3 $LOTUS_ROOT/tests/fake-openai.py $mport &
fake=$!
lotus ai server port $port >/dev/null
lotus_load
check_eq "the port is kept in the settings" "$LOTUS_AI_SERVER_PORT" $port
check_has "it is in the settings file" "$(<$LOTUS_CONF/settings.zsh)" "LOTUS_AI_SERVER_PORT='$port'"
LOTUS_AI_PROVIDER=openai LOTUS_AI_URL=http://127.0.0.1:$mport/v1 LOTUS_AI_MODEL=test-model
lotus_save
export LOTUS_AI_KEY=sk-lotus-test-secret-0123456789
for p in {1..50}; do curl -s -m 1 -o /dev/null http://127.0.0.1:$mport/ && break; sleep 0.1; done

# an occupied port: a clear error, and the port in the settings stays as it is
ztcp -l $port
busy=$REPLY
out=$(lotus ai server start 2>&1); rc=$?
check_eq "an occupied port: it does not start" $rc 1
check_has "and says the port is in use" "$out" "Port $port is already in use"
check_has "and offers another one" "$out" "lotus ai server port"
ztcp -c $busy
lotus_load
check_eq "the port was not changed silently" "$LOTUS_AI_SERVER_PORT" $port

zf_mkdir -p $HOME/work
out=$(cd $HOME/work && lotus ai server start 2>&1); rc=$?
check_eq "it starts" $rc 0
check_has "on 127.0.0.1" "$out" "http://127.0.0.1:$port"
check_has "status: running" "$(lotus ai server status)" "running on http://127.0.0.1:$port"
check_has "starting again: it says it runs already" "$(lotus ai server start 2>&1)" "already running"
if (( $+commands[lsof] )); then
  listen=$(lsof -nP -iTCP:$port -sTCP:LISTEN 2>/dev/null)
  check_has "it listens on 127.0.0.1 only" "$listen" "127.0.0.1:$port"
  check "not on every address" eval '[[ $listen != *"*:$port"* ]]'
fi

B=http://127.0.0.1:$port
key=$(<$LOTUS_STATE/ai-server.key)
check "the access key file is private" eval '[[ $(stat -f %Lp $LOTUS_STATE/ai-server.key) == 600 ]]'
code() { curl -s -m 5 -o /dev/null -w '%{http_code}' "$@" }
check_has "health" "$(curl -s -m 5 $B/api/health)" '"app":"lotus-ai"'
check_eq "the page without the key: locked" "$(code $B/)" 401
check_eq "a wrong key: locked" "$(code "$B/?key=nope")" 401
check_has "the right key signs in (cookie)" "$(curl -s -m 5 -D - -o /dev/null "$B/?key=$key")" "Set-Cookie: lotus_ai_key="
check_eq "another host name is refused (DNS rebinding)" "$(code -H "Host: evil.example:$port" --cookie "lotus_ai_key=$key" $B/)" 421
page=$(curl -s -m 5 --cookie "lotus_ai_key=$key" $B/)
token=$(print -r -- $page | sed -n 's/.*name="lotus-token" content="\([a-z0-9]*\)".*/\1/p')
check_eq "the page has a token" ${#token} 32
check_eq "the API without the token: refused" "$(code --cookie "lotus_ai_key=$key" $B/api/state)" 401
check_eq "the API without the cookie: refused" "$(code -H "X-Lotus-Token: $token" $B/api/state)" 401
H=(--cookie "lotus_ai_key=$key" -H "X-Lotus-Token: $token")
check_eq "a change without Origin: refused" "$(code -X POST $H $B/api/chats)" 403
check_eq "a change from another site: refused" "$(code -X POST $H -H 'Origin: http://evil.example' $B/api/chats)" 403
H+=(-H "Origin: $B")
state=$(curl -s -m 5 $H $B/api/state)
check_has "the state names the AI" "$state" '"ai":"test-model'
check "the API key never reaches the browser" eval '[[ $state$page != *sk-lotus-test-secret* ]]'
chat=$(curl -s -m 5 -X POST $H $B/api/chats | sed -n 's/.*"id":"\([a-z0-9]*\)".*/\1/p')
check_eq "a new conversation" ${#chat} 12
check_eq "an unknown conversation" "$(code $H $B/api/chats/aaaaaaaaaaaa)" 404
check_eq "an empty message is refused" "$(code $H -H 'Content-Type: application/json' -d '{"text":"  "}' $B/api/chats/$chat/send)" 400

# a message: the model wants to run a command – in ask mode it asks first, like in the terminal
send_to() { curl -sN -m 30 $H -H 'Content-Type: application/json' -d "{\"text\":\"$2\"}" $B/api/chats/$1/send }
answer() { code $H -H 'Content-Type: application/json' -d "{\"id\":\"$1\",\"answer\":\"$2\"}" $B/api/answer }
asked() {   # <chat> <text> – sends it in the background, waits for the question → REPLY = its id
  : >| $events
  curl -sN -m 60 $H -H 'Content-Type: application/json' -d "{\"text\":\"$2\"}" $B/api/chats/$1/send >| $events &
  sender=$!
  local p
  for p in {1..100}; do [[ $(<$events) == *'"type":"ask"'* ]] && break; sleep 0.1; done
  REPLY=$(sed -n 's/.*"type":"ask".*/&/p' $events | sed -n 's/.*"id":"\([a-z0-9]\{10\}\)".*/\1/p' | head -1)
}
events=$HOME/events.txt
: >| $events
curl -sN -m 60 $H -H 'Content-Type: application/json' -d '{"text":"please run the check"}' $B/api/chats/$chat/send >| $events &
sender=$!
for p in {1..100}; do [[ $(<$events) == *'"type":"ask"'* ]] && break; sleep 0.1; done
qid=$(sed -n 's/.*"type":"ask".*/&/p' $events | sed -n 's/.*"id":"\([a-z0-9]\{10\}\)".*/\1/p' | head -1)
check_eq "the command asks first" ${#qid} 10
check_has "with the command shown" "$(<$events)" '"detail":"echo lotus-test-ok"'
check_has "it may be allowed for this conversation" "$(<$events)" '"always":true'
check_eq "busy: a second message waits" "$(code $H -H 'Content-Type: application/json' -d '{"text":"hi"}' $B/api/chats/$chat/send)" 409
check_eq "an answer that is none: refused" "$(answer $qid maybe)" 400
check_eq "yes, don't ask again – from the browser" "$(answer $qid always)" 200
wait $sender
out=$(<$events)
check_has "the command ran" "$out" '"text":"exit 0'
check_has "the answer streams the result" "$out" 'lotus-test-ok'
check_has "and ends" "$out" '"type":"done"'
saved=$(curl -s -m 5 $H $B/api/chats/$chat)
check_has "the conversation is kept" "$saved" '"role":"assistant"'
check_has "with its title" "$saved" '"title":"please run the check"'
check "the conversation file is private" eval '[[ $(stat -f %Lp $LOTUS_STATE/ai-chats/$chat.json) == 600 ]]'
out=$(curl -sN -m 30 $H -H 'Content-Type: application/json' -d '{"text":"hello"}' $B/api/chats/$chat/send)
check_has "a plain answer streams as text" "$out" 'from** the test model'
out=$(send_to $chat "please run the check again")
check "don't ask again: the next command runs without a question" eval '[[ $out != *"\"type\":\"ask\""* && $out == *"\"text\":\"exit 0"* ]]'
other=$(curl -s -m 5 -X POST $H $B/api/chats | sed -n 's/.*"id":"\([a-z0-9]*\)".*/\1/p')
asked $other "please run the check"
check_eq "it counts for one conversation – a new one asks again" ${#REPLY} 10
check_eq "no from the browser" "$(answer $REPLY no)" 200
wait $sender
check_has "declined: it did not run" "$(<$events)" '"text":"Declined"'
check_eq "clear" "$(code -X POST $H $B/api/chats/$chat/clear)" 200
check_has "cleared: no messages" "$(curl -s -m 5 $H $B/api/chats/$chat)" '"messages":[]'
check_eq "delete" "$(code -X DELETE $H $B/api/chats/$chat)" 200
check "deleted: the file is gone" eval '[[ ! -e $LOTUS_STATE/ai-chats/$chat.json ]]'

# ── Improve prompts (LOTUS_AI_ENHANCE): read from the settings before every message ──
check_has "the setting is off at first" "$(curl -s -m 5 $H $B/api/state)" '"enhance":"off"'
enhance() {   # <mode> – as /settings or /enhance would save it
  LOTUS_AI_ENHANCE=$1
  lotus_save
}
say() {   # <text> → the events of the answer
  curl -sN -m 30 $H -H 'Content-Type: application/json' -d "{\"text\":\"$1\"}" $B/api/chats/$chat/send
}
turns() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["turns"][-2]["text"])' $LOTUS_STATE/ai-chats/$chat.json }
chat=$(curl -s -m 5 -X POST $H $B/api/chats | sed -n 's/.*"id":"\([a-z0-9]*\)".*/\1/p')
out=$(say "tell me a short story please")
check "off: sent as typed" eval '[[ $out != *"\"improved\""* ]]'
enhance on
out=$(say "tell me a short story please")
check_has "on: the improved prompt is shown" "$out" '"type":"improved"'
check_has "with the improved text" "$out" 'Goal: tell me a short story please'
check_has "and the answer still comes" "$out" 'from** the test model'
check_eq "the conversation keeps what the AI saw" "$(turns)" "Goal: tell me a short story please"
check_has "the state says it" "$(curl -s -m 5 $H $B/api/state)" '"enhance":"on"'
out=$(say "hi there you")
check "3 words or fewer: sent as typed" eval '[[ $out != *"\"improved\""* ]]'
check_eq "and kept as typed" "$(turns)" "hi there you"
out=$(say "/help me with this please")
check "a command: sent as typed" eval '[[ $out != *"\"improved\""* ]]'
long=${(l:3100::a:)}
out=$(say "please read $long")
check "longer than 3000 characters: sent as typed" eval '[[ $out != *"\"improved\""* ]]'
out=$(say "fail-enhance tell me something nice")
check "the rewrite fails: sent as typed" eval '[[ $out != *"\"improved\""* && $out == *"from** the test model"* ]]'
check_eq "and kept as typed" "$(turns)" "fail-enhance tell me something nice"

# ask: the browser chooses – the improved prompt, the original, or nothing
enhance ask
choose() {   # <text> <answer> → the events
  local f=$HOME/choose.txt q
  : >| $f
  curl -sN -m 30 $H -H 'Content-Type: application/json' -d "{\"text\":\"$1\"}" $B/api/chats/$chat/send >| $f &
  local -i p=$!
  for q in {1..100}; do [[ $(<$f) == *'"type":"improve"'* ]] && break; sleep 0.1; done
  q=$(sed -n 's/.*"type":"improve".*/&/p' $f | sed -n 's/.*"id":"\([a-z0-9]\{10\}\)".*/\1/p' | head -1)
  [[ $2 == always ]] && code $H -H 'Content-Type: application/json' -d "{\"id\":\"$q\",\"answer\":\"always\"}" $B/api/answer >| $HOME/always.txt
  curl -s -m 5 -o /dev/null $H -H 'Content-Type: application/json' -d "{\"id\":\"$q\",\"answer\":\"${2/always/improved}\"}" $B/api/answer
  wait $p
  REPLY=$(<$f)
}
choose "write me a haiku about lotus flowers" improved
check_has "ask: the improved prompt is offered" "$REPLY" '"type":"improve"'
check_eq "send it: the AI got the improved prompt" "$(turns)" "Goal: write me a haiku about lotus flowers"
choose "write me a poem about water lilies" original
check_eq "send mine: the AI got it as typed" "$(turns)" "write me a poem about water lilies"
before=$(turns)
choose "write me a song about the moon" cancel
check_has "cancel: nothing is sent" "$REPLY" '"text":"Not sent."'
check_eq "and the conversation is as it was" "$(turns)" "$before"
choose "write me a limerick about a cat" always
check_eq "'always' is not an answer to this question" "$(<$HOME/always.txt)" 400
# HTML that models write into Markdown: the terminal shows what it means, code and unknown tags stay
out=$(cd $HOME && lotus ai "show me some html please" 2>&1 | sed $'s/\e\\[[0-9;]*m//g')
check "/ai: <br> starts a new line" eval '[[ $out == *"Line one"$'"'"'\n'"'"'*"line two & more → x"* && $out != *"Line one<br>"* ]]'
check_has "/ai: unknown tags stay as written" "$out" "Use List<T> here and bold too."
check_has "/ai: code keeps its HTML" "$out" "<p>a<br>b</p>"
check_has "/ai: a <br> in a table row keeps the row" "$out" "| 1 | x / y |"
# the terminal: /ai <question> shows the improved prompt the same way
enhance on
out=$(cd $HOME && lotus ai "tell me a short story please" 2>&1)
check_has "/ai: the improved prompt is shown" "$out" "Improved prompt"
check_has "/ai: then the answer" "$out" "the test model"
out=$(cd $HOME && lotus ai "hi" 2>&1)
check "/ai: a short question goes as typed" eval '[[ $out != *"Improved prompt"* ]]'
enhance off

# ── Settings from the browser: the same Lotus settings as /settings and /ai ──
setting() { code $H -H 'Content-Type: application/json' -d "{\"key\":\"$1\",\"value\":\"$2\"}" $B/api/settings }
check_has "the settings list what the AI may do" "$(curl -s -m 5 $H $B/api/settings)" '"key":"LOTUS_AI_PERM_RUN"'
check_eq "a value that does not exist: refused" "$(setting LOTUS_AI_PERM_RUN sometimes)" 400
check_eq "other devices cannot be turned on from the browser" "$(setting LOTUS_AI_SERVER_LAN 1)" 400
check_eq "nor the port changed" "$(setting LOTUS_AI_SERVER_PORT 3001)" 400
check_eq "auto mode from the browser" "$(setting LOTUS_AI_PERM_MODE auto)" 200
check_has "saved in the Lotus settings" "$(<$LOTUS_CONF/settings.zsh)" "LOTUS_AI_PERM_MODE='auto'"
check_has "the state says auto" "$(curl -s -m 5 $H $B/api/state)" '"mode":"auto"'
auto=$(curl -s -m 5 -X POST $H $B/api/chats | sed -n 's/.*"id":"\([a-z0-9]*\)".*/\1/p')
out=$(send_to $auto "please run the check")
check "auto: a harmless command runs without a question" eval '[[ $out != *"\"type\":\"ask\""* && $out == *"\"text\":\"exit 0"* ]]'
asked $auto "please delete the old build"
check_eq "auto: deleting still asks" ${#REPLY} 10
check_has "and never with 'don't ask again'" "$(<$events)" '"always":false'
answer $REPLY no >/dev/null
wait $sender
out=$(send_to $auto "please use admin rights")
check_has "sudo never runs" "$out" "Lotus never uses sudo"
setting LOTUS_AI_PERM_MODE ask >/dev/null
check_eq "thinking from the browser" "$(setting LOTUS_AI_EFFORT low)" 200
check_has "the state says it" "$(curl -s -m 5 $H $B/api/state)" '"effort":"quick"'
setting LOTUS_AI_EFFORT high >/dev/null
check_has "who answers: the test model" "$(curl -s -m 5 $H $B/api/models)" '"current":true'
check_eq "an AI that is not there: refused" "$(code $H -H 'Content-Type: application/json' -d '{"kind":"claude","model":"claude-nope"}' $B/api/model)" 400

# memory, context, compact
check_has "memory: empty at first" "$(curl -s -m 5 $H $B/api/memory)" '"facts":[]'
print -r -- $'# What Lotus AI remembers\n\n- The user likes short answers.' >| $LOTUS_CONF/ai-memory.md
check_has "memory: what it keeps" "$(curl -s -m 5 $H $B/api/memory)" 'The user likes short answers.'
check_eq "memory: forget" "$(code -X POST $H $B/api/memory/clear)" 200
check_has "memory: forgotten" "$(curl -s -m 5 $H $B/api/memory)" '"facts":[]'
check_has "context: how full" "$(curl -s -m 5 $H $B/api/chats/$auto/context)" '"percent":'
out=$(curl -sN -m 30 -X POST $H $B/api/chats/$auto/compact)
check_has "compact: done" "$out" 'Compacted'
check "compact: older messages became a summary" python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); sys.exit(0 if len(c["turns"]) <= 2 and c["summary"] else 1)' $LOTUS_STATE/ai-chats/$auto.json

pid=$(cut -d' ' -f1 $LOTUS_STATE/ai-server | head -1)
out=$(lotus ai server stop); rc=$?
check_eq "stop" $rc 0
check "the server is gone" eval '! kill -0 $pid 2>/dev/null'
check_has "status: off" "$(lotus ai server status)" "off (port $port)"
check_eq "the port is free again" "$($bin --port-check $port)" free
kill $fake 2>/dev/null
