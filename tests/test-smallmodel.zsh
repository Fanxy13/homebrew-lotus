# Apple Intelligence: the rules for a model with little room (lib/ai/Small.swift) – which tools a request gets and how
# briefly they are described, how much of the conversation fits beside them, the work log that carries a task from one
# session to the next, which steps should change something, and when a text goes in circles. They run on every system
# (lotus-ai --small-check); the model itself runs only on a Mac with Apple Intelligence, where its window is 4096 tokens.
source $LOTUS_ROOT/lib/core.zsh
source $LOTUS_ROOT/lib/ui.zsh
lotus_load

if ! { lotus_can_swift || [[ -x $LOTUS_PREBUILT_DIR/lotus-ai-$LOTUS_OS-$LOTUS_ARCH ]] }; then
  print -r -- "  - the checks need a Swift compiler (or a built AI program) – skipped"
  return 0
fi
source $LOTUS_ROOT/lib/cmd/ai.zsh
_ai_build 2>/dev/null
lotus_ai_helper
bin=$REPLY
check "the AI program builds" test -x $bin
sc() { $bin --small-check "$@" }

# ── the tools a request gets: each definition takes room, and fewer make fewer wrong calls ──
check_eq "a conversation gets no tools" "$(sc tools chat tell me a joke)" ""
check_eq "looking at files: list, read, search" "$(sc tools look what is in this folder)" "list_directory read_file search_files"
check_eq "a change: list, read, write, edit, run" "$(sc tools change rename the txt files to md)" "list_directory read_file write_file edit_file run_command"
check_eq "a web page: and view_page" "$(sc tools change make a website about cats)" "list_directory read_file write_file edit_file run_command view_page"
check_eq "  – in German too" "$(sc tools change baue eine Webseite über Katzen)" "list_directory read_file write_file edit_file run_command view_page"
check_eq "the internet: search and read" "$(sc tools web the newest version of node)" "web_search fetch_url"
check_eq "Lotus: its own tools" "$(sc tools lotus play some music)" "weather music"
out=$(sc brief)
check_has "the tools are described briefly" "$out" "write_file: Create a file, or replace a whole file."
t=(${=${(M)${(f)out}:#tokens *}})
check "  – in less than half the room the long descriptions take ($t[2] instead of $t[5] tokens)" eval '(( t[2] * 2 < t[5] ))'
sm=$(awk '/^## small$/{on=1} /^## browser$/{on=0} on' $LOTUS_ROOT/data/ai/system.md)
check "its instructions stay short too (${#sm} characters)" eval '(( ${#sm} > 500 && ${#sm} < 2600 ))'

# ── how much of the conversation fits ──
r=$(sc room 450 0 chat)
check "a conversation gets the room that is left: $r characters (it was 3200)" eval '(( r > 6400 ))'
r=$(sc room 900 700 work)
check "work keeps room for what the tools return: $r characters" eval '(( r >= 1200 && r < 3200 ))'
check_eq "never less than 1200 characters" "$(sc room 3500 900 work)" 1200
long=${(l:3000::x:)}
out=$(print -l "user: the first question" "assistant: $long" "user: the second question" "assistant: a short answer" | sc recent 2000)
check_has "the newest turns are there" "$out" "assistant: a short answer"
check_has "a long answer is cut" "$out" "[…]"
check_has "  – so the question before it still fits" "$out" "user: the first question"
out=$(print -l "assistant: an answer without its question" "user: hello" "assistant: hi" | sc recent 2000)
check "the conversation starts with the user" eval '[[ ${${(f)out}[1]} == "user: hello" ]]'

# ── a task across sessions: the work log ──
out=$(print -l -- "- read_file a.txt: one" "- write_file b.txt: two" "- run_command make: three" | sc log 40)
check_has "the work log keeps the newest" "$out" "- run_command make: three"
check_has "  – and says what it left out" "$out" "(2 earlier entries left out)"

# ── a step that should change something, or one that looks ──
check_eq "writing a file changes something" "$(sc changes Write index.html with the sections of the page)" changes
check_eq "  – in German" "$(sc changes Erstelle style.css mit den Farben)" changes
check_eq "  – running the tests" "$(sc changes Run the tests)" changes
check_eq "looking at the folder does not" "$(sc changes Look at the folder)" looks
check_eq "  – nor checking the page" "$(sc changes Check the page with view_page)" looks
check_eq "  – nor in German" "$(sc changes Prüfe die Seite im Browser)" looks

# ── going in circles ──
loop=$(print -rn -- 'Here is the plan for your website. '; repeat 4 print -rn -- 'I will now create the file index.html with a header and a footer for you. ')
out=$(print -rn -- $loop | sc circles)
check_has "a text that goes in circles is cut" "$out" "cut at"
check_eq "  – after the first time" "$(print -r -- $out | grep -o 'I will now create' | wc -l | tr -d ' ')" 1
check_has "  – what came before stays" "$out" "Here is the plan for your website."
song=$(for v in "Morning light on the river" "Evening wind across the hill" "Midnight stars above the town"; do
  print -r -- "$v, and we walk on."
  print -r -- "Oh the lotus, the lotus, it blooms where we go, it blooms where we go."
done)
check_eq "a refrain with other words in between is no circle" "$(print -r -- $song | sc circles)" no
li='<li class="item"><a href="#features">Features of the product</a></li>'
check_eq "three equal lines in a code block are no circle" "$(print -l '```html' $li $li $li | sc circles)" no
check_has "  – seven are" "$(print -l '```html' $li $li $li $li $li $li $li | sc circles)" "cut at"
check_eq "a rule of dashes is no circle" "$({ repeat 12 print -- '----------------------------------------' } | sc circles)" no
check_eq "a short text is never cut" "$(print -rn -- 'yes yes yes' | sc circles)" no
