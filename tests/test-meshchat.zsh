# MeshChat (lib/meshchat, lotus meshchat – part of Lotus, a plugin before): nothing to install. On every system: the
# command and its feature, and the old plugin going away – this Mac's identity, the name and the history come along.
# On a Mac: built once inside MeshChat's sandbox (it reads only lib/meshchat, writes only its data folder, no network),
# its protocol tests (a simulated radio: packets, signatures, relays as far as the hop limit, duplicates, fragments,
# broken and hostile packets, floods, out of range and back), one chat for everyone and no rooms, the data in its data
# folder only and private, the chat in a terminal (the demo: two simulated people, one of them a relay away) and the
# terminal given back as it was. Bluetooth itself needs Macs with Bluetooth: the test with three of them is in
# lib/meshchat/README.md.
source $LOTUS_ROOT/lib/core.zsh
source $LOTUS_ROOT/lib/ui.zsh
lotus_load
lotus() { $LOTUS_ROOT/bin/lotus "$@" }
plain() { sed $'s/\e\\[[0-9;?]*[a-zA-Z]//g' | tr -d '\r' }
D=$LOTUS_DATA/meshchat

# ── nothing to install: it is part of Lotus ──
check_eq "a command of Lotus' own: the cheatsheet lists it" "$(grep -c "^Chat	/meshchat	meshchat	" $LOTUS_ROOT/data/commands.tsv)" "1"
check_eq "a feature of its own" "$(grep -c "^meshchat	MeshChat	meshchat	" $LOTUS_ROOT/data/features.tsv)" "1"
check "no plugin of that name in plugins/ any more" test ! -e $LOTUS_ROOT/plugins/meshchat
check_has "a plugin cannot take its name" "$(lotus plugin new meshchat 2>&1 | plain)" "\"meshchat\" is one of Lotus' own commands"
lotus features meshchat off >/dev/null 2>&1
check_has "a feature that is off explains itself" "$(lotus meshchat help 2>&1 </dev/null | plain)" "MeshChat is turned off"
lotus features meshchat on >/dev/null 2>&1
if [[ $TEST_OS != macos ]]; then
  check_has "elsewhere it says that it is for macOS" "$(lotus meshchat help 2>&1 </dev/null | plain)" "MeshChat runs on macOS only"
  check "  – and makes no data folder" test ! -e $D
fi

# ── it was a plugin before: the old one goes, and this Mac's identity, the name and the history come along ──
P=$LOTUS_CONF/plugins O=$LOTUS_DATA/plugins/meshchat
ID=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef ID2=fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210
mkold() {   # <author>
  zf_mkdir -p $P/meshchat $O/rooms/k7q2m9ab $O/bin $LOTUS_DATA/plugins/todo
  print -r -- $'name        = meshchat\ntitle       = MeshChat\nauthor      = '$1$'\ndescription = old\naccess      = limited\nnetwork     = no\nos          = macos\ncommand meshchat = meshchat.zsh' >| $P/meshchat/plugin.conf
  print -r -- 'print old' >| $P/meshchat/meshchat.zsh
  print -r -- $ID >| $O/identity
  print -r -- $'NICKNAME=Ada\nLINKS=3' >| $O/settings
  print -r -- '{"v":1,"id":"00000000000000aa","t":1761570000000,"rx":1761570000000,"nick":"Bob","fp":"k3f9","text":"see you at the bridge","hops":2,"me":false}' >| $O/history.jsonl
  print -r -- '{"format":1,"name":"Bike trip"}' >| $O/rooms/k7q2m9ab/room.json
  print -r -- 'https://github.com/Fanxy13/homebrew-lotus#plugins/meshchat' >| $LOTUS_DATA/plugins/.meshchat-source
  chmod 700 $O; chmod 600 $O/identity $O/settings $O/history.jsonl
  print -r -- $'todo\ton\tlimited\tabc\nmeshchat\ton\tlimited\tdef' >| $LOTUS_CONF/plugins.tsv
}
tty() { tpty zsh -fc "$LOTUS_ROOT/bin/lotus version" 2>&1 | plain }
mkold Somebody
out=$(tty)
check "a plugin of someone else with that name stays" test -e $P/meshchat/plugin.conf
check "  – and its data" test -r $O/identity
check "  – nothing is taken from it" test ! -e $D
lines=("${(@f)out}")      # an array – one line of output is still a list, not a word to take a letter from
check_eq "  – and Lotus says nothing" "${lines[-1]//[[:space:]]/}" "$LOTUS_VERSION"
check "  – (not a word about a plugin)" eval '[[ $out != *plugin* ]]'
rm -rf $P/meshchat $LOTUS_DATA/plugins
mkold Lotus
out=$(tty)
check "Lotus' own old plugin is gone" test ! -e $P/meshchat
check "  – its data folder, and where it was installed from" eval '[[ ! -e $O && ! -e $LOTUS_DATA/plugins/.meshchat-source ]]'
check_has "  – it says so" "$out" "MeshChat is part of Lotus now – the old meshchat plugin was removed; your name, identity and history came along."
check_eq "  – this Mac's identity came along: Macs nearby know it by its fingerprint" "$(<$D/identity)" $ID
check_eq "  – and it is still yours alone" "$(fmode $D) $(fmode $D/identity)" "700 600"
check_eq "  – the name and the settings" "$(<$D/settings)" $'NICKNAME=Ada\nLINKS=3'
check_has "  – the history" "$(<$D/history.jsonl)" "see you at the bridge"
check "  – and the rooms of MeshChat 1, for the doctor to name" test -r $D/rooms/k7q2m9ab/room.json
check_eq "  – its entry is gone, the others stay" "$(<$LOTUS_CONF/plugins.tsv)" $'todo\ton\tlimited\tabc'
check "  – other plugins' data stays" test -d $LOTUS_DATA/plugins/todo
out=$(tty)
check "  – and nothing is said the next time" eval '[[ $out != *"part of Lotus now"* ]]'
# both there – the old plugin came back (an older Lotus for a while): what MeshChat keeps stays, the rest comes along
rm -rf $LOTUS_DATA/plugins
mkold Lotus
print -r -- $ID2 >| $D/identity
rm -f $D/history.jsonl
tty >/dev/null
check_eq "both there: the identity MeshChat has stays" "$(<$D/identity)" $ID2
check_has "  – what it did not have comes along" "$(<$D/history.jsonl)" "see you at the bridge"
check "  – and the old plugin is gone" eval '[[ ! -e $P/meshchat && ! -e $O ]]'

onlyon macos "MeshChat uses CoreBluetooth and runs on macOS only" || return 0
if ! lotus_can_swift; then print -r -- "  – no Command Line Tools: building and the chat are skipped"; return 0; fi
rm -rf $D      # from here on, this Mac's own MeshChat – not the identity of the old plugin above

# ── built once, inside MeshChat's sandbox ──
out=$(lotus meshchat version 2>&1 | plain)
check_has "built in its sandbox, it runs" "$out" "MeshChat 2.2.0 – protocol 2, crypto CryptoKit"
check "the program is in its data folder" eval '[[ -n $(print -l $D/bin/meshchat-<->(N)) ]]'
check "nothing is built into Lotus' own folder" eval '[[ ! -e $LOTUS_ROOT/lib/meshchat/bin && -z $(print -l $LOTUS_ROOT/lib/meshchat/meshchat-*(N)) ]]'
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
check_has "how far someone is, on the simulated radio" "$out" "✓ how far on the simulated radio"
check_has "out of range and back" "$out" "✓ out of range and back"
check_has "all of them pass" "$out" " passed, 0 failed"
[[ $out == *" passed, 0 failed"* ]] || print -r -- "${(F)${(M)${(f)out}:#*✗*}}"
sum=(${(M)${(f)out}:#* passed, * failed})
print -r -- "    (the selftest on this Mac: $sum[1])"

# ── one chat with everyone nearby: no rooms, no codes ──
check_has "help: it is public" "$(lotus meshchat help 2>&1 | plain)" "It is public: anyone nearby can read it"
check_has "help: but for /tell, sealed for one person" "$(lotus meshchat help 2>&1 | plain)" "Except /tell <name> <message>: sealed for that one person"
check_has "the room commands of MeshChat 1 say what changed" "$(lotus meshchat join MC1-AAAAA-BBBBB 2>&1 | plain)" "MeshChat has no rooms any more"
check_has "create too" "$(lotus meshchat create "Bike trip" 2>&1 | plain)" "Everyone nearby with MeshChat is in one chat"
check_has "nick" "$(lotus meshchat nick Tester 2>&1 | plain)" "You are Tester in the chat"
check_has "set links" "$(lotus meshchat set links 3 2>&1 | plain)" "At most 3 Bluetooth links"
check_has "links over 8 are refused" "$(lotus meshchat set links 9 2>&1 | plain)" "a number from 1 to 8"
check_has "hops are no setting: every message goes as far as it can" "$(lotus meshchat set hops 3 2>&1 | plain)" "as far as the mesh reaches"
check_has "the settings file" "$(<$D/settings)" "LINKS=3"

# ── its data: in its data folder, readable by you only ──
check_eq "the settings are readable by you only" "$(fmode $D/settings)" 600
check_eq "the data folder too" "$(fmode $D)" 700
check "nothing of it outside its data folder" eval '[[ -z $(print -l $HOME/*meshchat*(N)) && ! -e $HOME/Library/Preferences/io.github.fanxy13.lotus.meshchat.plist && ! -e $LOTUS_DATA/plugins/meshchat ]]'

# ── the chat in a terminal: the demo, with keys typed into it ──
out=$( (sleep 4; print -rn -- "hello mesh"; sleep 0.4; print -rn -- $'\r'; sleep 5; print -rn -- "/who"$'\r'; sleep 1.5; print -rn -- $'\x03'; sleep 2) \
  | tpty zsh -fc "COLUMNS=100 $LOTUS_ROOT/bin/lotus meshchat demo" 2>&1)
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

# ── the rooms of MeshChat 1: named by the doctor, left alone ──
zf_mkdir -p $D/rooms/k7q2m9ab
print -r -- '{"format":1,"name":"Bike trip"}' >| $D/rooms/k7q2m9ab/room.json

# ── the doctor: the build, then Bluetooth (a Mac without Bluetooth, like a CI runner, says so) ──
out=$(lotus meshchat doctor 2>&1 | plain)
check_has "doctor: macOS and Swift" "$out" "Swift        "
check_has "doctor: the build is ready" "$out" "Build        ready"
check_has "doctor: it gets to the end, whatever Bluetooth says" "$out" "History      1 message"
check_has "doctor: the data folder is Lotus' own" "$out" ".local/share/lotus/meshchat/history.jsonl"
check_has "doctor: MeshChat 1's rooms are named" "$out" "the rooms of MeshChat 1 are still in"
check "and left as they are" test -r $D/rooms/k7q2m9ab/room.json
# what CoreBluetooth answered inside MeshChat's sandbox – for the log (a Mac without Bluetooth answers too)
lines=(${(M)${(f)out}:#*(Permission|Bluetooth|Advertising) *})
lines=(${lines//  #/ })
print -r -- "    (in the sandbox:${(j: ·:)lines})"
