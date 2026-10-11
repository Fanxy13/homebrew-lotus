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
FAKE_LOG=$HOME/requests.jsonl python3 $LOTUS_ROOT/tests/fake-openai.py $mport &
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
send_to() { curl -sN -m 90 $H -H 'Content-Type: application/json' -d "{\"text\":\"$2\"}" $B/api/chats/$1/send }
answer() { code $H -H 'Content-Type: application/json' -d "{\"id\":\"$1\",\"answer\":\"$2\"}" $B/api/answer }
asked() {   # <chat> <text> – sends it in the background, waits for the whole question → REPLY = its id
  : >| $events
  curl -sN -m 90 $H -H 'Content-Type: application/json' -d "{\"text\":\"$2\"}" $B/api/chats/$1/send >| $events &
  sender=$!
  local p line=
  # the event line can arrive in pieces: only a complete one counts
  for p in {1..300}; do
    line=$(grep -m1 '^data: {.*"type":"ask".*}$' $events 2>/dev/null)
    [[ -n $line ]] && break
    sleep 0.1
  done
  REPLY=$(print -r -- $line | sed -n 's/.*"id":"\([a-z0-9]\{10\}\)".*/\1/p')
}
events=$HOME/events.txt
asked $chat "please run the check"
qid=$REPLY
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
code -X POST $H $B/api/stop >/dev/null      # nothing may stay open for the next checks
out=$(send_to $auto "please use admin rights")
check_has "sudo never runs" "$out" "Lotus never uses sudo"
setting LOTUS_AI_PERM_MODE ask >/dev/null
check_eq "thinking from the browser" "$(setting LOTUS_AI_EFFORT low)" 200
check_has "the state says it" "$(curl -s -m 5 $H $B/api/state)" '"effort":"quick"'
check_has "a model on this Mac thinks as set, from the next message on" "$(send_to $auto "how hard do you think")" '"text":"thinking low false, ultra no"'
check_eq "a level that does not exist: refused" "$(setting LOTUS_AI_EFFORT turbo)" 400
check_eq "ultra from the slider" "$(setting LOTUS_AI_EFFORT ultra)" 200
state=$(curl -s -m 5 $H $B/api/state)
check_has "the state has the level for the slider" "$state" '"level":"ultra"'
check_has "and the five levels" "$state" '"name":"ultra"'
check_has "ultra: it thinks as much as it can and gets the ultra instructions" "$(send_to $auto "how hard do you think")" '"text":"thinking high true, ultra yes"'
check_has "the same setting as /effort in /ai" "$(<$LOTUS_CONF/settings.zsh)" "LOTUS_AI_EFFORT='ultra'"
out=$(cd $HOME && lotus ai "how hard do you think" 2>&1)
check_has "/ai thinks ultra too" "$out" "thinking high true, ultra yes"
setting LOTUS_AI_EFFORT high >/dev/null

# ── It acts instead of asking, and a broken step does not end in silence ──
setting LOTUS_AI_PERM_MODE auto >/dev/null
out=$(send_to $auto "please offer to build a page")
check_has "it only asked whether it should: Lotus tells it to do it" "$out" "It asked whether it should instead of doing it"
check_has "and it does" "$out" '"text":"Done without asking."'
out=$(send_to $auto "please explain then offer")
check "a long answer that ends with an offer stays the answer" eval '[[ $out != *"Done without asking"* && $out == *"Would you like me to build a website about it?"* ]]'
out=$(send_to $auto "write a file with a raw newline")
check_has "arguments with real line breaks are repaired" "$out" '"text":"Wrote it."'
want=$'line one\nline two\tend \' quoted'
check "and the file is right" eval '[[ "$(<$HOME/work/raw.txt)" == "$want" ]]'
out=$(send_to $auto "make a broken call")
check_has "arguments that cannot be repaired: it is told what went wrong" "$out" "not valid JSON"
check_has "a quiet end after it: Lotus lets it go on" "$out" "It stopped without an answer"
check_has "and it gets there" "$out" '"text":"Recovered after the broken call."'
check "nothing was written from the broken call" test ! -e $HOME/work/broken.txt
out=$(send_to $auto "please plan two files")
check_has "a plan: the to-do list reaches the browser" "$out" '"type":"plan"'
check_has "with the step in work" "$out" '"state":"doing"'
check_has "it stopped with a step still open: Lotus sends it on" "$out" "Its plan still has open steps"
check_has "and it finishes the plan" "$out" '"text":"Both files are done."'
check "both files are there" eval '[[ -e $HOME/work/plan-a.txt && -e $HOME/work/plan-b.txt ]]'
check "the ticked-off plan" eval '[[ $out == *"\"state\":\"done\",\"text\":\"Write plan-b.txt\""* || $out == *"\"text\":\"Write plan-b.txt\",\"state\":\"done\""* ]]'
out=$(send_to $auto "please plan in text")
check "a plan ticked off in the answer counts – it is not sent on" eval '[[ $out != *"Its plan still has open steps"* && $out != *"Nudged again"* ]]'
check_has "and the list shows it" "$out" '"text":"All steps done"'
out=$(send_to $auto "please break off")
check_has "a model server that breaks off: it says so instead of nothing" "$out" "stopped in the middle of its answer"
setting LOTUS_AI_PERM_MODE ask >/dev/null
check_has "who answers: the test model" "$(curl -s -m 5 $H $B/api/models)" '"current":true'
check_eq "an AI that is not there: refused" "$(code $H -H 'Content-Type: application/json' -d '{"kind":"claude","model":"claude-nope"}' $B/api/model)" 400

# view_page: the AI looks at a web page it built, in WebKit, at desktop and phone width
site=$HOME/work/site
zf_mkdir -p $site
print -r -- '<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Test</title><link rel="stylesheet" href="style.css"><link rel="stylesheet" href="gone.css"></head><body><main><h1>Hello</h1><img src="pic.png"><div style="width:900px">wide</div><input type="email"></main><script>console.error("boom"); nope();</script></body></html>' >| $site/index.html
print -r -- 'h1 { color: rgb(170, 51, 170); }' >| $site/style.css
print -r -- 'SECRET=1' >| $site/.env
render=$($bin --render $site/index.html 390 $HOME/work - 2>/dev/null | tail -1)
check_has "render: errors in the console, with the line" "$render" "Can't find variable: nope (index.html:"
check_has "render: files that did not load" "$render" 'gone.css'
check_has "render: too wide on a phone" "$render" '"scrollWidth":908'
check_has "render: images without alt" "$render" '"noAlt":["pic.png"]'
check_has "render: the field without a label" "$render" '"unlabeled":1'
print -r -- '<html><body><link rel="stylesheet" href=".env"><link rel="stylesheet" href="../../outside.css"><script>fetch("https://example.com/?x=1").then(() => console.error("SENT")).catch(() => console.error("not sent"))</script></body></html>' >| $site/leak.html
render=$($bin --render $site/leak.html 390 $HOME/work - 2>/dev/null | tail -1)
check_has "render: private files are not served" "$render" "(private)"
check "render: nothing outside the folder" eval '[[ $render == *"outside the folder"* || $render == *"outside.css"* ]]'
check_has "render: the page cannot send anything" "$render" "not sent"
look=$(curl -s -m 5 -X POST $H $B/api/chats | sed -n 's/.*"id":"\([a-z0-9]*\)".*/\1/p')
out=$(send_to $look "please look at the page")
check_has "view_page: a step of its own" "$out" '"name":"View"'
check_has "view_page: the screenshot reaches the browser" "$out" '"type":"image"'
check_has "view_page: the model gets the report" "$out" 'Page: site'
check "view_page: the screenshot is kept" test -s $LOTUS_CACHE/ai/pages/index-phone.jpg
# after a page is written, Lotus looks at it by itself and tells the model what it saw
setting LOTUS_AI_PERM_MODE auto >/dev/null
out=$(send_to $look "please make a page")
check_has "written page: looked at in a browser" "$out" 'In a browser:'
check_has "written page: the model hears what is wrong" "$out" 'Lotus opened site2'
check_has "written page: the missing style is named" "$out" 'style.css'
check_has "written page: the whole file reaches the browser for the code panel" "$out" '"type":"file"'
check_has "with its name and all of its content" "$out" '<\/body><\/html>'
setting LOTUS_AI_PERM_MODE ask >/dev/null

# it stopped before it was done: Lotus lets it go on, at most 3 times
setting LOTUS_AI_PERM_MODE auto >/dev/null
goon=$(curl -s -m 5 -X POST $H $B/api/chats | sed -n 's/.*"id":"\([a-z0-9]*\)".*/\1/p')
out=$(send_to $goon "please think too long")
check_has "ran out of room: it goes on" "$out" 'Lotus lets it go on (1\/3)'
check_has "and finishes" "$out" 'Finished after going on.'
check "once was enough" eval '[[ $out != *"(2\\/3)"* ]]'
out=$(send_to $goon "please announce the next step")
check_has "announced a step and stopped: it goes on" "$out" 'It stopped at the next step it announced'
check_has "and does it" "$out" 'All done now.'
out=$(send_to $goon "please ask back")
check_has "a question to the user: it waits" "$out" 'Shall I also add a footer?'
check "and does not go on" eval '[[ $out != *"lets it go on"* ]]'
out=$(send_to $goon "this never ends")
check_has "never done: three times" "$out" '(3\/3)'
check "not more" eval '[[ $out != *"(4\\/3)"* ]]'
check_has "then it says why" "$out" 'The AI keeps running out of room'
out=$(cd $HOME && lotus ai "please think too long" 2>&1)
check_has "/ai in the terminal goes on too" "$out" 'Lotus lets it go on (1/3)'
check_has "/ai: and finishes" "$out" 'Finished after going on.'
setting LOTUS_AI_PERM_MODE ask >/dev/null

# ── Stuck and going in circles: what small models do, and what Lotus does about it ──
setting LOTUS_AI_PERM_MODE auto >/dev/null
stuck=$(curl -s -m 5 -X POST $H $B/api/chats | sed -n 's/.*"id":"\([a-z0-9]*\)".*/\1/p')
print -l "line "{1..50} >| $HOME/work/big.txt
out=$(send_to $stuck "please cut the file short")
check_has "write_file with only a part of a long file: not written" "$out" 'Not written: it would replace 50 lines with 1'
check_eq "and the file is whole" "$(wc -l < $HOME/work/big.txt | tr -d ' ')" 50
check_has "the AI is told to use edit_file" "$(tail -1 $HOME/requests.jsonl)" 'use edit_file'
out=$(send_to $stuck "please search twice for the needle")
check_has "the same step again: not run again" "$out" 'The same as before – not run again'
check_has "the third time: the tools stop for this answer" "$out" 'Lotus stopped the tools for this answer'
check_has "and the AI is told it goes in circles" "$(tail -1 $HOME/requests.jsonl)" 'you are going in circles'
check_has "then it answers" "$out" 'Done with the steps.'
out=$(send_to $stuck "please use the alias")
check_has "a tool by another name (open_file): runs as read_file" "$out" '"name":"Read"'
check_has "on the file it meant" "$out" '"detail":"raw.txt"'
check "with file_path for path" eval '[[ $out != *"left out path"* && $out != *"There is no tool with this name"* ]]'
check_has "the model learns the right name" "$(tail -1 $HOME/requests.jsonl)" 'There is no tool open_file'
out=$(send_to $stuck "make a page and paste the code")
check_has "code in the chat instead of files: it is told to write them" "$out" 'It put the code into the chat instead of creating the files'
check_has "and it does" "$out" 'Created the files now.'
out=$(send_to $stuck "please think in circles")
check_has "thinking in circles: stopped, and it is told to act" "$out" 'Its thinking went in circles'
check_has "then it acts" "$out" 'Acting now.'
check "it was cut off before the end" eval '[[ $out != *"never be reached"* ]]'
: >| $HOME/requests.jsonl
out=$(send_to $stuck "please think then look")
check_has "thinking then a tool: done" "$out" 'Done with the steps.'
check_has "a model on this Mac gets its thinking back with the tool call" "$(<$HOME/requests.jsonl)" '"reasoning_content": "I will look at the folder first."'
# gpt-oss: the thinking with the call, one call per message, as its chat template wants it
LOTUS_AI_MODEL=gpt-oss-test; lotus_save
: >| $HOME/requests.jsonl
out=$(cd $HOME/work && lotus ai "please think then look" 2>&1)
check_has "gpt-oss in /ai: done" "$out" 'Done with the steps.'
check "gpt-oss gets its thinking back as thinking, the call in a message of its own" python3 -c '
import json, sys
reqs = [json.loads(l) for l in open(sys.argv[1])]
calls = [m for r in reqs for m in r["messages"] if m.get("role") == "assistant" and m.get("tool_calls")]
ok = calls and all(len(m["tool_calls"]) == 1 for m in calls) and calls[-1].get("thinking") == "I will look at the folder first." and calls[-1]["content"] == ""
sys.exit(0 if ok else 1)' $HOME/requests.jsonl
LOTUS_AI_MODEL=test-model; lotus_save
check "every request reads the same: the tool list in the same order (so a model on this Mac can reuse its cache)" python3 -c '
import json, sys
tools = {json.dumps(json.loads(l)["tools"]) for l in open(sys.argv[1]) if "\"tools\"" in l}
sys.exit(0 if len(tools) == 1 else 1)' $HOME/requests.jsonl
out=$(send_to $stuck "hello again")
check_has "every model request is measured" "$out" '"type":"model"'
check_has "with the time to the first token" "$out" '"first":'

# ── /performance: the conversation as a report in a text file ──
rep=$(curl -s -m 10 $H $B/api/chats/$stuck/performance)
check_has "the report: the setup" "$rep" "═══ SETUP ═══"
check_has "the AI and this Mac" "$rep" "AI:"
check_has "the totals" "$rep" "Model requests:"
check_has "where Lotus stepped in: the repeated steps" "$rep" "steps repeated: 2"
check_has "and the file it did not cut short" "$rep" "files not cut short: 1"
check_has "every step" "$rep" "STEP Write big.txt"
check_has "every model request with its numbers" "$rep" "model request 1:"
check_has "the Lotus log of that time" "$rep" "═══ LOTUS LOG"
check "no API key in it" eval '[[ $rep != *sk-lotus-test-secret* ]]'
check_has "it comes with a file name" "$(curl -s -m 10 -D - -o /dev/null $H $B/api/chats/$stuck/performance)" "X-Lotus-File: lotus-performance-please-cut-the-file-short-"
check_eq "an unknown conversation: none" "$(code $H $B/api/chats/aaaaaaaaaaaa/performance)" 404
# one question in the terminal, with the report for a benchmark (LOTUS_AI_PERFORMANCE)
out=$(cd $HOME/work && LOTUS_AI_PERFORMANCE=$HOME/perf.txt lotus ai "please think then look" 2>&1)
check_has "/ai: the report of one question" "$(<$HOME/perf.txt)" "STEP List"
check "/ai: and its steps as data" python3 -c 'import json,sys; m=json.load(open(sys.argv[1]))["messages"]; sys.exit(0 if any(e.get("type")=="model" for x in m for e in x.get("events",[])) else 1)' $HOME/perf.txt.json
setting LOTUS_AI_PERM_MODE ask >/dev/null

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

# a command that leaves a program running in the background: the step ends when the command ends
zmodload zsh/datetime
setting LOTUS_AI_PERM_RUN allow >/dev/null
bg=$(curl -s -m 5 -X POST $H $B/api/chats | sed -n 's/.*"id":"\([a-z0-9]*\)".*/\1/p')
t0=$EPOCHREALTIME
out=$(send_to $bg "start the server in the background")
t1=$EPOCHREALTIME
check_has "a program left running: the command's output" "$out" 'started-it'
check "and the step does not wait for that program" eval '(( t1 - t0 < 10 ))'
setting LOTUS_AI_PERM_RUN ask >/dev/null

# ── It works on without a page: only the web chat has to run; the terminal follows it (lotus ai stats) ──
setting LOTUS_AI_PERM_MODE ask >/dev/null
check_has "the web chat says what it is doing in a file only you can read" "$(<$LOTUS_STATE/ai-server.now)" "\"port\":$port"
check "that file is private" eval '[[ $(stat -f %Lp $LOTUS_STATE/ai-server.now) == 600 ]]'
gone=$(curl -s -m 5 -X POST $H $B/api/chats | sed -n 's/.*"id":"\([a-z0-9]*\)".*/\1/p')
curl -sN -m 1 $H -H 'Content-Type: application/json' -d '{"text":"please take your time"}' $B/api/chats/$gone/send >/dev/null 2>&1
check_has "the page is gone: it works on" "$(curl -s -m 5 $H $B/api/state)" "\"busy\":\"$gone\""
for i in {1..30}; do [[ $(<$LOTUS_STATE/ai-server.now) == *'"watching":0'* ]] && break; sleep 0.1; done
now=$(<$LOTUS_STATE/ai-server.now)
check_has "the terminal sees what it does" "$now" '"activity":"Thinking"'
check_has "and since when" "$now" '"started":'
check_has "and that no page watches" "$now" '"watching":0'
out=$(lotus ai stats 2>&1)
check_has "lotus ai stats: the web chat is working" "$out" "working"
check_has "lotus ai stats: on its own" "$out" "no page follows it – it works on anyway"
check_has "lotus ai stats: the conversation" "$out" "please take your time"
back=$(curl -sN -m 2 $H "$B/api/run?chat=$gone&from=0")
first=${${(f)back}[1]}
check_has "a page that comes back gets the clock first" "$first" '"type":"clock"'
elapsed=$(print -r -- $first | sed -n 's/.*"elapsed":\([0-9.]*\).*/\1/p')
check "it has been going for more than a second – the stopwatch goes on from there" eval '(( ${elapsed:-0} >= 1 ))'
check_has "and the thoughts so far, as they came" "$back" '"text":"Thinking step 0. "'
check_has "every event has its time" "$back" '"t":'
for i in {1..80}; do [[ $(curl -s -m 5 $H $B/api/state) == *'"busy":null'* ]] && break; sleep 0.1; done
saved=$(curl -s -m 5 $H $B/api/chats/$gone)
check_has "it finished without a page" "$saved" 'Took my time.'
check_has "the thoughts are kept in one piece" "$saved" 'Thinking step 0. Thinking step 1. Thinking step 2.'
check_has "and how long it thought" "$saved" '"type":"thought"'
sleep 0.3
check "done: the terminal sees nothing running" eval '[[ $(<$LOTUS_STATE/ai-server.now) != *"\"run\""* ]]'

# a question while no page is open: the terminal answers it (lotus ai stats, /stats in /ai)
ask=$(curl -s -m 5 -X POST $H $B/api/chats | sed -n 's/.*"id":"\([a-z0-9]*\)".*/\1/p')
curl -sN -m 1 $H -H 'Content-Type: application/json' -d '{"text":"please run the check"}' $B/api/chats/$ask/send >/dev/null 2>&1
for i in {1..50}; do [[ $(<$LOTUS_STATE/ai-server.now) == *'"question"'* ]] && break; sleep 0.1; done
now=$(<$LOTUS_STATE/ai-server.now)
check_has "the open question is there for the terminal" "$now" '"question":'
check_has "with the command" "$now" 'echo lotus-test-ok'
qid=$(print -r -- $now | sed -n 's/.*"id":"\([a-z0-9]\{10\}\)".*/\1/p')
check_eq "it has its id" ${#qid} 10
out=$(lotus ai stats --once 2>&1)
check_has "lotus ai stats: waiting for your answer" "$out" "waiting for your answer"
tkey=$(<$LOTUS_STATE/ai-server.key)
tanswer() { curl -s -m 5 -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' "$@" -d "{\"id\":\"$qid\",\"answer\":\"yes\"}" $B/api/answer }
check_eq "from the terminal without the key: refused" "$(tanswer -H 'X-Lotus-Key: nope')" 401
check_eq "the key from a web page: refused" "$(tanswer -H "X-Lotus-Key: $tkey" -H 'Origin: http://evil.example')" 401
check_eq "the terminal can only answer and stop" "$(code -H "X-Lotus-Key: $tkey" $B/api/state)" 404
check_eq "the terminal answers: yes" "$(tanswer -H "X-Lotus-Key: $tkey")" 200
for i in {1..80}; do [[ $(curl -s -m 5 $H $B/api/state) == *'"busy":null'* ]] && break; sleep 0.1; done
saved=$(curl -s -m 5 $H $B/api/chats/$ask)
check_has "the command ran after the terminal's yes" "$saved" 'lotus-test-ok'
check_has "the answer is kept with the question" "$saved" '"answer":"yes"'

# and it can stop an answer
halt=$(curl -s -m 5 -X POST $H $B/api/chats | sed -n 's/.*"id":"\([a-z0-9]*\)".*/\1/p')
curl -sN -m 1 $H -H 'Content-Type: application/json' -d '{"text":"please take your time"}' $B/api/chats/$halt/send >/dev/null 2>&1
check_eq "the terminal stops the answer" "$(code -X POST -H "X-Lotus-Key: $tkey" $B/api/stop)" 200
for i in {1..80}; do [[ $(curl -s -m 5 $H $B/api/state) == *'"busy":null'* ]] && break; sleep 0.1; done
check_has "stopped" "$(curl -s -m 5 $H $B/api/chats/$halt)" '"text":"Stopped"'

# the numbers: one line per answer, from the web chat and from /ai – only counts and times
stats=$LOTUS_STATE/ai-stats.tsv
check "the statistics file is private" eval '[[ $(stat -f %Lp $stats) == 600 ]]'
check_has "answers from the web chat are counted" "$(<$stats)" $'\tweb\t'
check_has "and from /ai in the terminal" "$(<$stats)" $'\tterminal\t'
check_has "with the steps by tool" "$(<$stats)" 'run_command:1'
check_has "stopped answers count as stopped" "$(<$stats)" $'\tstopped\t'
check "nothing of what was said is kept there" eval '[[ $(<$stats) != *"take your time"* && $(<$stats) != *"lotus-test-ok"* ]]'
out=$(lotus ai stats 2>&1)
check_has "lotus ai stats: the answers" "$out" "Answers"
check_has "lotus ai stats: the steps by tool" "$out" "Run"
check_has "lotus ai stats: where" "$out" "web chat"
check_has "/stats in the web chat: the same numbers" "$(curl -s -m 5 $H $B/api/stats)" "Answers"
check "lotus ai stats without a terminal: no colors" eval '[[ $out != *$'"'"'\e['"'"'* ]]'

pid=$(cut -d' ' -f1 $LOTUS_STATE/ai-server | head -1)
out=$(lotus ai server stop); rc=$?
check_eq "stop" $rc 0
check "the server is gone" eval '! kill -0 $pid 2>/dev/null'
check_has "status: off" "$(lotus ai server status)" "off (port $port)"
check "stopped: the terminal sees it is off" test ! -e $LOTUS_STATE/ai-server.now
check_has "lotus ai stats: the web chat is off" "$(lotus ai stats 2>&1)" "off · lotus ai server start"
check_eq "the port is free again" "$($bin --port-check $port)" free
kill $fake 2>/dev/null
