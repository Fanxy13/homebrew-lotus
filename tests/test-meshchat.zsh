# MeshChat (plugins/meshchat): installed with limited access and without internet, built once on this Mac inside the
# plugin's sandbox, its protocol tests (a simulated radio: packets, signatures, relays as far as the hop limit,
# duplicates, fragments, broken and hostile packets, floods, out of range and back), one chat for everyone and no
# rooms, the data in the plugin's data folder only and private, the chat in a terminal (the demo: two simulated
# people, one of them a relay away) and the terminal given back as it was. Bluetooth itself needs Macs with
# Bluetooth: the test with three of them is in plugins/meshchat/README.md.
source $LOTUS_ROOT/lib/core.zsh
source $LOTUS_ROOT/lib/ui.zsh
lotus_load
lotus() { $LOTUS_ROOT/bin/lotus "$@" }
plain() { sed $'s/\e\\[[0-9;?]*[a-zA-Z]//g' | tr -d '\r' }
answer() { (sleep 1.5; print -rn -- $1; sleep 0.8) | script -q /dev/null zsh -fc "$2" 2>&1 | plain }
D=$LOTUS_DATA/plugins/meshchat

# ── installed like any plugin: limited, no internet ──
check_has "plugin.conf is right" "$(lotus plugin check $LOTUS_ROOT/plugins/meshchat 2>&1 | plain)" "plugin.conf is fine – lotus meshchat"
out=$(answer y "$LOTUS_ROOT/bin/lotus plugin install $LOTUS_ROOT/plugins/meshchat")
check_has "install says what it may do: its own folder, no internet" "$out" "limited – only its own folder"
check_has "installed" "$out" 'The plugin "meshchat" is installed'
check_has "its command" "$(lotus plugin 2>&1 | plain)" "lotus meshchat · limited – only its own folder · on"

if ! lotus_can_swift; then print -r -- "  – no Command Line Tools: building and the chat are skipped"; return 0; fi

# ── built once, inside the plugin's sandbox ──
out=$(lotus meshchat version 2>&1 | plain)
check_has "built in the sandbox, it runs" "$out" "MeshChat 2.0.0 – protocol 2, crypto CryptoKit"
check "the program is in its data folder" eval '[[ -n $(print -l $D/bin/meshchat-<->(N)) ]]'
built=$(print -r -- $D/bin/meshchat-<->(N:t))
lotus meshchat version >/dev/null 2>&1
check_eq "built once: the second start uses the same program" "$(print -r -- $D/bin/meshchat-<->(N:t))" "$built"
check_has "help" "$(lotus meshchat help 2>&1 | plain)" "lotus meshchat history"
check_has "an unknown word" "$(lotus meshchat bogus 2>&1 | plain)" 'There is no "lotus meshchat bogus"'

# ── the protocol tests, with CryptoKit on this Mac ──
out=$(lotus meshchat selftest 2>&1 | plain)
check_has "the tests use CryptoKit" "$out" "crypto: CryptoKit"
check_has "RFC test vectors: CryptoKit gives the published results" "$out" "✓ SHA-256 and HKDF-SHA256 (RFC 5869) give the published results"
check_has "Ed25519 too" "$out" "✓ Ed25519 (RFC 8032)"
check_has "multi-hop on the simulated radio" "$out" "✓ multi-hop: A reaches C through B"
check_has "every Mac passes it on, 16 relays far" "$out" "✓ as far as it goes: every Mac passes a message on, 16 relays far"
check_has "one sender cannot flood everyone" "$out" "✓ one sender cannot flood everyone"
check_has "out of range and back" "$out" "✓ out of range and back"
check_has "all of them pass" "$out" " passed, 0 failed"
[[ $out == *" passed, 0 failed"* ]] || print -r -- "${(F)${(M)${(f)out}:#*✗*}}"
sum=(${(M)${(f)out}:#* passed, * failed})
print -r -- "    (the selftest on this Mac: $sum[1])"

# ── one chat with everyone nearby: no rooms, no codes ──
check_has "help: it is public" "$(lotus meshchat help 2>&1 | plain)" "It is public: anyone nearby can read it"
check_has "the room commands of MeshChat 1 say what changed" "$(lotus meshchat join MC1-AAAAA-BBBBB 2>&1 | plain)" "MeshChat has no rooms any more"
check_has "create too" "$(lotus meshchat create "Bike trip" 2>&1 | plain)" "Everyone nearby with MeshChat is in one chat"
check_has "nick" "$(lotus meshchat nick Tester 2>&1 | plain)" "You are Tester in the chat"
check_has "set links" "$(lotus meshchat set links 3 2>&1 | plain)" "At most 3 Bluetooth links"
check_has "links over 8 are refused" "$(lotus meshchat set links 9 2>&1 | plain)" "a number from 1 to 8"
check_has "hops are no setting: every message goes as far as it can" "$(lotus meshchat set hops 3 2>&1 | plain)" "as far as the mesh reaches"
check_has "the settings file" "$(<$D/settings)" "LINKS=3"

# ── its data: in its data folder, readable by you only ──
check_eq "the settings are readable by you only" "$(stat -f %Lp $D/settings)" 600
check_eq "the data folder too" "$(stat -f %Lp $D)" 700
check "nothing of it outside its data folder" eval '[[ -z $(print -l $HOME/*meshchat*(N)) && ! -e $HOME/Library/Preferences/io.github.fanxy13.lotus.meshchat.plist ]]'

# ── the chat in a terminal: the demo, with keys typed into it ──
out=$( (sleep 4; print -rn -- "hello mesh"; sleep 0.4; print -rn -- $'\r'; sleep 5; print -rn -- "/who"$'\r'; sleep 1.5; print -rn -- $'\x03'; sleep 2) \
  | script -q /dev/null zsh -fc "COLUMNS=100 $LOTUS_ROOT/bin/lotus meshchat demo" 2>&1)
text=$(print -r -- $out | plain)
check_has "the demo: the chat's screen" "$text" "lotus / MeshChat"
check_has "one chat: everyone nearby" "$text" "everyone nearby"
check_has "it says it is a demo" "$text" "DEMO"
check_has "and that it is simulated" "$text" "Simulated"
check_has "what you write is shown" "$text" "hello mesh"
check_has "Ada, a neighbour, answers" "$text" "Ada is here – a neighbour"
check_has "Grace is a relay away" "$text" "Grace is here – 1 relay away"
check_has "her messages come relayed" "$text" "⇢1"
check_has "/who: how each one is connected" "$text" "a neighbour: a direct Bluetooth link"
check_has "ctrl-c closes the chat" "$text" "That was the demo"
check_has "the terminal is given back: its own screen" "$out" $'\e[?1049l'
check_has "bracketed paste off again" "$out" $'\e[?2004l'
check "the demo keeps no history" eval '[[ ! -e $D/history.jsonl ]]'
check_has "the chat needs a terminal" "$(lotus meshchat </dev/null 2>&1 | plain)" "needs a terminal window"

# ── history: what is shown is made safe; damaged lines are skipped ──
print -r -- '{"v":1,"id":"00000000000000aa","t":1761570000000,"rx":1761570000000,"nick":"Bob","fp":"k3f9","text":"see you at \u001b[31mthe bridge","hops":2,"me":false}' >| $D/history.jsonl
print -r -- 'not json' >> $D/history.jsonl
out=$(lotus meshchat history 2>&1)
check_has "history: what was said" "$(print -r -- $out | plain)" "see you at [31mthe bridge ⇢2"
check "an escape code in a message never reaches the terminal" eval '[[ $out != *$'"'"'\e[31mthe'"'"'* ]]'
check_has "a damaged line is skipped" "$(print -r -- $out | plain)" "1 damaged line skipped"
check_eq "the history is readable by you only" "$(stat -f %Lp $D/history.jsonl)" 600

# ── the rooms of MeshChat 1: named by the doctor, left alone ──
zf_mkdir -p $D/rooms/k7q2m9ab
print -r -- '{"format":1,"name":"Bike trip"}' >| $D/rooms/k7q2m9ab/room.json

# ── the doctor: the build, then Bluetooth (a Mac without Bluetooth, like a CI runner, says so) ──
out=$(lotus meshchat doctor 2>&1 | plain)
check_has "doctor: macOS and Swift" "$out" "Swift        "
check_has "doctor: the build is ready" "$out" "Build        ready"
check_has "doctor: it gets to the end, whatever Bluetooth says" "$out" "History      1 message"
check_has "doctor: MeshChat 1's rooms are named" "$out" "the rooms of MeshChat 1 are still in"
check "and left as they are" test -r $D/rooms/k7q2m9ab/room.json
# what CoreBluetooth answered inside the plugin's sandbox – for the log (a Mac without Bluetooth answers too)
lines=(${(M)${(f)out}:#*(Permission|Bluetooth|Advertising) *})
lines=(${lines//  #/ })
print -r -- "    (in the sandbox:${(j: ·:)lines})"

# ── uninstalling ──
out=$(answer y "$LOTUS_ROOT/bin/lotus plugin uninstall meshchat")
check_has "uninstall asks" "$out" 'Remove the plugin "meshchat" and its data?'
check "uninstalled, with its data and its build" eval '[[ ! -e $LOTUS_CONF/plugins/meshchat && ! -e $D ]]'
