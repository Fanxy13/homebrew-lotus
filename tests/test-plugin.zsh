# Plugins (lib/cmd/plugin.zsh): make one, install one (it asks), run its command and its AI tools, the sandbox of a
# limited plugin (no files of yours, no internet unless it says so, no keychain, no API keys), full access that has
# to be allowed again after a change, the start screen line, the AI's list of tools, on/off and remove.
source $LOTUS_ROOT/lib/core.zsh
source $LOTUS_ROOT/lib/ui.zsh
lotus_load
lotus() { $LOTUS_ROOT/bin/lotus "$@" }
plain() { sed $'s/\e\\[[0-9;?]*[a-zA-Z]//g' | tr -d '\r' }
# a question answered on a keyboard: script gives it a terminal, the answer comes when it waits
answer() { (sleep 1.5; print -rn -- $1; sleep 0.5) | script -q /dev/null zsh -fc "$2" 2>&1 | plain }
P=$LOTUS_CONF/plugins

check_has "none at first" "$(lotus plugin 2>&1 | plain)" "No plugins yet"

# ── a new one ──
out=$(lotus plugin new demo 2>&1 | plain)
check_has "lotus plugin new: made" "$out" 'Your plugin "demo" is ready'
check "with a plugin.conf and its programs" eval '[[ -r $P/demo/plugin.conf && -r $P/demo/demo.zsh && -r $P/demo/tool.zsh ]]'
check_eq "its command runs" "$(lotus demo one two 2>&1 | plain)" "Hello from demo – you gave me: one two"
check_eq "its AI tool runs" "$(lotus plugin-tool demo hello Ada)" "Hello, Ada!"
check_has "it is in the list" "$(lotus plugin 2>&1 | plain)" "lotus demo · 1 AI tool · a start screen line · limited – only its own folder · on"
check_has "and fine" "$(lotus plugin check demo 2>&1 | plain)" "plugin.conf is fine"
check_has "a name of Lotus' own: refused" "$(lotus plugin new weather 2>&1 | plain)" "one of Lotus' own commands"
check_has "a wrong name: refused" "$(lotus plugin new Bad_Name 2>&1 | plain)" "A plugin needs a name"
lotus nosuchthing >/dev/null 2>&1; check_eq "a word no plugin has is still unknown" $? 1

# a broken plugin.conf: check names it, the command does not run
print -r -- "command broken = missing.zsh" >> $P/demo/plugin.conf
check_has "check finds the problem" "$(lotus plugin check demo 2>&1 | plain)" "missing.zsh is not a file in the plugin's folder"
check_has "and it does not run" "$(lotus demo 2>&1 | plain)" "has a problem in its plugin.conf"
sed -i '' '/command broken/d' $P/demo/plugin.conf

# ── the sandbox of a limited plugin ──
print -r -- "secret" >| $HOME/secret.txt
cat >| $P/demo/demo.zsh <<'EOF'
cat $HOME/secret.txt >/dev/null 2>&1 && print "home: READ" || print "home: blocked"
print x > $HOME/written.txt 2>/dev/null && print "write home: WRITTEN" || print "write home: blocked"
print x > $LOTUS_PLUGIN_DATA/mine.txt && print "own data: written"
cat $LOTUS_PLUGIN_DIR/plugin.conf >/dev/null && print "own folder: read"
[[ -r $LOTUS_CONF/settings.zsh ]] && print "settings: READ" || print "settings: hidden"
/usr/bin/security list-keychains >/dev/null 2>&1 && print "keychain: OPEN" || print "keychain: blocked"
/usr/bin/osascript -e 1 >/dev/null 2>&1 && print "apple events: OPEN" || print "apple events: blocked"
env | grep -q -e sk-test-secret -e GITHUB_TOKEN && print "keys: VISIBLE" || print "keys: none"
[[ -n $LOTUS_PWD ]] && print "folder: SHOWN" || print "folder: hidden"
python3 -c "import socket,sys; s=socket.create_connection(('127.0.0.1', int(sys.argv[1])), 3); print('network: OPEN')" $(<$LOTUS_PLUGIN_DIR/port) 2>/dev/null || print "network: blocked"
EOF
# a local server, so the internet test needs no internet
zmodload zsh/net/tcp
typeset -i port=0 p
for (( p = 40100 + RANDOM % 500; p < 40900; p++ )); do ztcp -l $p 2>/dev/null && { port=p; ztcp -c $REPLY; break }; done
python3 -m http.server $port --bind 127.0.0.1 >/dev/null 2>&1 &
srv=$!
for p in {1..30}; do curl -s -m 1 -o /dev/null http://127.0.0.1:$port/ && break; sleep 0.1; done
print -r -- $port >| $P/demo/port      # the plugin sees only its own folder: the port goes there
_plg_net() { sed -i '' "s/^network .*/network     = $1/" $P/demo/plugin.conf }
out=$(LOTUS_AI_CLAUDE_KEY=sk-test-secret GITHUB_TOKEN=x lotus demo 2>&1 | plain)
check_has "limited: your files cannot be read" "$out" "home: blocked"
check_has "nor written" "$out" "write home: blocked"
check "and nothing was written" test ! -e $HOME/written.txt
check_has "its own data folder can be written" "$out" "own data: written"
check_has "its own folder read" "$out" "own folder: read"
check_has "Lotus' settings are hidden" "$out" "settings: hidden"
check_has "no keychain" "$out" "keychain: blocked"
check_has "no controlling other apps" "$out" "apple events: blocked"
check_has "the AI's API keys never reach a plugin" "$out" "keys: none"
check_has "nor the folder it was called in" "$out" "folder: hidden"
check_has "no network unless it says so" "$out" "network: blocked"
check "a local server for the network test" eval '(( port > 0 ))'
_plg_net yes
check_has "network = yes: it may connect" "$(lotus demo 2>&1 | plain)" "network: OPEN"
check_has "and the list says so" "$(lotus plugin 2>&1 | plain)" "limited – its own folder and the internet"
kill $srv 2>/dev/null
# a file the AI gives a tool (a path parameter): a limited plugin may read that one file – and no other
cat >> $P/demo/plugin.conf <<'EOF'
tool show = show.zsh
tool show.level = read
tool show.description = Shows a file.
tool show.param file = path, required, The file
EOF
print -r -- 'cat $LOTUS_ARG_FILE 2>/dev/null || print "given: blocked"; cat $HOME/other.txt >/dev/null 2>&1 && print "other: READ" || print "other: blocked"' >| $P/demo/show.zsh
print -r -- "the given one" >| $HOME/given.txt
print -r -- "another one" >| $HOME/other.txt
out=$(lotus plugin-tool demo show $HOME/given.txt 2>&1)
check_has "a path given to a tool: that file can be read" "$out" "the given one"
check_has "but no other" "$out" "other: blocked"

# ── installing: what it brings, and a question ──
out=$(answer y "$LOTUS_ROOT/bin/lotus plugin install $LOTUS_ROOT/plugins/todo")
check_has "install shows what it may do" "$out" "limited – only its own folder"
check_has "and what it brings" "$out" "AI tool"
check_has "and asks" "$out" 'Install the plugin "todo"? [y/N] yes'
check_has "installed" "$out" 'The plugin "todo" is installed'
check_has "a to-do" "$(lotus todo add Milk 2>&1 | plain)" "Added: Milk (1 open)"
check_has "listed" "$(lotus todo 2>&1 | plain)" "1  Milk"
check_has "the AI tool adds one" "$(lotus plugin-tool todo add 'Call Ada')" "Added: Call Ada (2 open)"
check_has "the AI tool lists them" "$(lotus plugin-tool todo list)" "2  Call Ada"
check_has "and ticks one off" "$(lotus plugin-tool todo done 1)" "Done: Milk (1 open)"
check_has "its data stays in its data folder" "$(<$LOTUS_DATA/plugins/todo/todo.txt)" "Call Ada"
out=$(answer n "$LOTUS_ROOT/bin/lotus plugin install $LOTUS_ROOT/plugins/hello")
check_has "full access is named before it is installed" "$out" "full access – your files, the internet, Lotus' settings"
check_has "no: not installed" "$out" "Not installed"
check "nothing of it is there" test ! -e $P/hello

# ── full access: allowed once, again after a change ──
out=$(answer y "$LOTUS_ROOT/bin/lotus plugin install $LOTUS_ROOT/plugins/hello")
check_has "yes: installed with full access" "$out" 'The plugin "hello" is installed'
check_has "it uses Lotus' own functions and settings" "$(lotus hello 2>&1 | plain)" "This plugin read Lotus' settings"
print -r -- "# a change" >> $P/hello/hello.zsh
out=$(lotus hello 2>&1 | plain)
check_has "changed after you allowed it: it does not run" "$out" "changed since you allowed it"
check "and its output is not there" eval '[[ $out != *"read Lotus'"'"' settings"* ]]'
check_has "allowed again: it asks" "$(answer y "$LOTUS_ROOT/bin/lotus plugin allow hello")" 'Allow "hello" full access to your Mac and Lotus? [y/N] yes'
check_has "and it runs" "$(lotus hello 2>&1 | plain)" "This plugin read Lotus' settings"

# ── the AI's list ──
source $LOTUS_ROOT/lib/cmd/aitools.zsh
lotus_ai_toolkit
kit=$(<$REPLY)
check_has "the plugins' tools are in the AI's list" "$kit" '"name":"todo_add"'
check_has "run as plugin-tool, with the value of each parameter" "$kit" '"argv":["plugin-tool","todo","done","{number}"]'
check_has "with its type" "$kit" '"name":"number","type":"int","required":true'
check_has "a read tool runs without a question" "$kit" '"name":"todo_list","feature":"plugins","level":"read"'
check_has "an act tool asks first" "$kit" '"name":"todo_add","feature":"plugins","level":"act"'
cat >> $P/hello/plugin.conf <<'EOF'
tool hi = hello.zsh
tool hi.level = read
tool hi.description = Says hi.
EOF
answer y "$LOTUS_ROOT/bin/lotus plugin allow hello" >/dev/null
lotus_ai_toolkit
check_has "a tool of a full plugin always asks first" "$(<$REPLY)" '"name":"hello_hi","feature":"plugins","level":"act"'
lotus plugin off todo >/dev/null
lotus_ai_toolkit
check "a plugin turned off: its tools are gone" eval '[[ "$(<$REPLY)" != *todo_add* ]]'
check_has "and its command says so" "$(lotus todo 2>&1 | plain)" 'The plugin "todo" is turned off'
lotus plugin on todo >/dev/null

# ── the AI calls a plugin tool (the test model of tests/fake-openai.py) ──
if lotus_can_swift && (( $+commands[python3] )); then
  typeset -i mport=0
  for (( p = 40900 + RANDOM % 500; p < 41700; p++ )); do ztcp -l $p 2>/dev/null && { mport=p; ztcp -c $REPLY; break }; done
  python3 $LOTUS_ROOT/tests/fake-openai.py $mport &
  fake=$!
  for p in {1..50}; do curl -s -m 1 -o /dev/null http://127.0.0.1:$mport/ && break; sleep 0.1; done
  LOTUS_AI_PROVIDER=openai LOTUS_AI_URL=http://127.0.0.1:$mport/v1 LOTUS_AI_MODEL=test-model LOTUS_AI_PERM_MODE=auto
  lotus_save
  out=$(cd $HOME && LOTUS_AI_KEY=sk-lotus-test lotus ai "please put bread on my todo list" 2>&1 | plain)
  check_has "/ai: the AI uses the plugin's tool" "$out" "To-do"
  check_has "and the plugin did it" "$(<$LOTUS_DATA/plugins/todo/todo.txt)" "bread"
  kill $fake 2>/dev/null
fi

# ── under the start screen ──
startup() { script -q /dev/null zsh -fc "source $LOTUS_ROOT/lib/core.zsh; source $LOTUS_ROOT/lib/ui.zsh; lotus_load; lotus_plugin_startup" </dev/null 2>&1 | plain }
startup >/dev/null
for p in {1..40}; do [[ -s $LOTUS_DATA/plugins/todo/.startup-line ]] && break; sleep 0.1; done
check_has "a plugin's start screen line" "$(startup)" "To-do · 2 open – lotus todo"

# ── on, off, remove ──
lotus features plugins off >/dev/null 2>&1
lotus_load
check "the feature can be turned off" eval '! lotus_feature_on plugins'
lotus todo >/dev/null 2>&1; check_eq "plugins turned off: their commands are gone" $? 1
lotus features plugins on >/dev/null 2>&1
lotus_load
out=$(answer y "$LOTUS_ROOT/bin/lotus plugin remove todo")
check_has "remove asks" "$out" 'Remove the plugin "todo" and its data?'
check "removed, with its data" eval '[[ ! -e $P/todo && ! -e $LOTUS_DATA/plugins/todo ]]'
check "and gone from the list" eval '[[ "$(<$LOTUS_CONF/plugins.tsv)" != todo* ]]'
