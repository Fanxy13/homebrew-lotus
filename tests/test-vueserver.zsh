# Vue 3 in the Live Server (lib/live/vuesfc.py, macOS): the server around the compiler, over HTTP, with a stand-in for the compiler
# (tests/live/stub-host.py speaks the lines the real program does – the real compiler and Vue itself are tests/test-vue.zsh). Like the
# Live Server's own tests it talks to 127.0.0.1, which a CI Mac does not let it do (the workflow leaves this file out there; it runs
# on a real Mac and in the Linux containers).
#   a page that has a module script knows where vue is (an import map) · a .vue file a script imports is the compiled module, the
#   source for a browser that opens it · what cannot be compiled is shown in the page and in the terminal · a stylesheet a script imports
#   becomes a <link> · './store' finds store.js · a Vue project answers /about with its index.html · other folders are as they were
source $LOTUS_ROOT/lib/core.zsh
source $LOTUS_ROOT/lib/ui.zsh
lotus_load
lotus() { $LOTUS_ROOT/bin/lotus "$@" }
plain() { sed $'s/\e\\[[0-9;?]*[a-zA-Z]//g' | tr -d '\r' }
if (( ! $+commands[python3] )); then print -r -- "  – no python3: skipped"; return 0; fi
zmodload zsh/net/tcp

# ── the program that carries the compiler: its lines, with no Vue in them ──
suite() {   # <what> <command…> – a test program whose ✓ and ✗ lines are checks of this file
  local what=$1 out; shift
  local -i rc
  out=$("$@" 2>&1); rc=$?
  print -r -- "$out"
  local -a lines=(${(f)out})
  (( PASSED += ${#${(@M)lines:#*✓*}} ))
  (( FAILED += ${#${(@M)lines:#*✗*}} ))
  (( rc == 0 )) || { (( FAILED++ )); print -r -- "  ✗ $what: exit status $rc" }
}
suite "the helpers of the Vue support" python3 -B $LOTUS_ROOT/tests/live/vuesfc_test.py

free_port() {
  local -i p
  for (( p = 42700 + RANDOM % 400; p < 43500; p++ )); do ztcp -l $p 2>/dev/null && { ztcp -c $REPLY; REPLY=$p; return }; done
  return 1
}
up() { local i; for i in {1..50}; do curl -s -m 1 -o /dev/null http://127.0.0.1:$1/ && return 0; sleep 0.1; done; return 1 }
code() { curl -s --path-as-is -o /dev/null -w '%{http_code}' "$@" }
script=(-H 'Sec-Fetch-Dest: script')

# a Vue project: an index.html with a module script, components, a stylesheet a script imports, a module without its extension
V=$HOME/vue
zf_mkdir -p $V/src/assets $V/src/store $V/pages
print -r -- '<!doctype html><html><head><title>Vue app</title></head><body><div id="app"></div><script type="module" src="/src/main.js"></script></body></html>' >| $V/index.html
print -r -- "import { createApp } from 'vue'
import App from './App.vue'
import './assets/main.css'
createApp(App).mount('#app')" >| $V/src/main.js
print -r -- '<template><h1>Grüezi</h1></template>
<script setup>
const a = 1
</script>' >| $V/src/App.vue
print -r -- '<template>BREAK</template>' >| $V/src/Broken.vue
print -r -- '<template>CRASH</template>' >| $V/src/Crash.vue
print -r -- '<template>secret</template>' >| $V/src/.hidden.vue
print -r -- 'body { margin: 0 }' >| $V/src/assets/main.css
print -r -- 'export const x = 1' >| $V/src/store/index.js
print -r -- 'export const y = 2' >| $V/src/util.js
print -r -- '<p>no script at all</p>' >| $V/pages/plain.html
print -r -- '<script type="importmap">{"imports":{"lodash":"https://cdn.example/lodash.js"}}</script><script type="module">import "lodash"</script>' >| $V/pages/map.html
print -r -- '<script type="importmap">{"imports":{"vue":"https://unpkg.com/vue@3/dist/vue.esm-browser.js"}}</script><script type="module">import "vue"</script>' >| $V/pages/cdn.html
print -r -- '{"dependencies": {"vue": "^3.5.0", "vue-router": "^4.0.0", "pinia": "^3.0.0"}}' >| $V/package.json
count=$HOME/stub-count

free_port; port=$REPLY B=http://127.0.0.1:$REPLY
export LOTUS_VUE_HOST="python3 -B $LOTUS_ROOT/tests/live/stub-host.py" LOTUS_STUB_COUNT=$count
(cd $V && lotus liveserver --no-open --local --port $port >| $HOME/vue.log 2>&1 &)
check "it answers" up $port
sleep 0.5
out=$(plain < $HOME/vue.log)
check_has "a folder of .vue files says that they are compiled here" "$out" "Vue 3       .vue files are compiled as the page asks for them – nothing to install"
check_has "and what a build step would have given that it has not" "$out" "Not available without a build step: vue-router, pinia – name them in an import map of the page"
check_has "the compiler is ready before the first page is" "$out" "✓ Vue compiler ready"

# ── the page ──
page=$(curl -s $B/)
check_has "a page with a module script: the import map for vue, in front of it" "$page" '<script type="importmap">{"imports":{"vue":"/__lotus/vue/vue.js"}}</script><script type="module" src="/src/main.js">'
check_has "and the reload script as ever" "$page" '<script src="/__lotus/reload.js"></script></body>'
check_eq "a page without a module script is as it was" "$(curl -s $B/pages/plain.html)" $'<p>no script at all</p>\n<script src="/__lotus/reload.js"></script>'
map=$(curl -s $B/pages/map.html)
check_has "a page with an import map of its own: vue is put into it" "$map" '{"imports": {"lodash": "https://cdn.example/lodash.js", "vue": "/__lotus/vue/vue.js"}}'
check "and there is still one import map" eval '[[ $(print -r -- $map | grep -o importmap | wc -l) -eq 1 ]]'
check "a page that names vue itself keeps its vue" eval '[[ $(curl -s $B/pages/cdn.html) == *unpkg.com/vue@3* && $(curl -s $B/pages/cdn.html) != *__lotus/vue* ]]'
check_has "Vue itself, for the import map" "$(curl -sI $B/__lotus/vue/vue.js)" "Content-Type: text/javascript; charset=utf-8"
check_eq "it is the file of Lotus" "$(curl -s $B/__lotus/vue/vue.js | wc -c | tr -d ' ')" "$(wc -c < $LOTUS_ROOT/lib/live/vue/vue.js | tr -d ' ')"
check_has "and may be kept for an hour" "$(curl -sI $B/__lotus/vue/vue.js)" "Cache-Control: public, max-age=3600"
check_eq "nothing else under /__lotus/vue/" "$(code $B/__lotus/vue/compiler-sfc.js)" 404

# ── a .vue file ──
mod=$(curl -s "${script[@]}" $B/src/App.vue)
check_has "a script's import of a .vue file is the compiled module" "$mod" 'export default { stub: "src/App.vue"'
check_has "as JavaScript, never from the cache" "$(curl -sI "${script[@]}" $B/src/App.vue)" "Content-Type: text/javascript; charset=utf-8"
check_has "never from the cache" "$(curl -sI "${script[@]}" $B/src/App.vue)" "Cache-Control: no-store"
check_has "a browser that opens it sees the source" "$(curl -s -H 'Accept: text/html,application/xhtml+xml' $B/src/App.vue)" "<template><h1>Grüezi</h1></template>"
check_has "a fetch() of it too" "$(curl -s -H 'Sec-Fetch-Dest: empty' $B/src/App.vue)" "const a = 1"
check_has "a browser that says nothing about what it wants gets the module (Accept: */*)" "$(curl -s $B/src/App.vue)" 'export default { stub:'
check_has "HEAD says what a GET would" "$(curl -sI "${script[@]}" $B/src/App.vue)" "Content-Type: text/javascript"
curl -s "${script[@]}" $B/src/App.vue >/dev/null; curl -s "${script[@]}" $B/src/App.vue >/dev/null
check_eq "what was compiled is kept: the compiler was asked once" "$(grep -c '^src/App.vue$' $count)" 1
sleep 1.1; print -r -- '<template><h1>Changed</h1></template>' >| $V/src/App.vue
check_has "a file that changed is compiled again" "$(curl -s "${script[@]}" $B/src/App.vue)" "<template><h1>Changed</h1></template>"
check_eq "so the compiler was asked twice" "$(grep -c '^src/App.vue$' $count)" 2
check_eq "no hidden .vue file" "$(code "${script[@]}" $B/src/.hidden.vue)" 404
check_eq "no .vue file that is not there" "$(code "${script[@]}" $B/src/Nothing.vue)" 404

# ── what cannot be compiled ──
err=$(curl -s "${script[@]}" $B/src/Broken.vue)
check_has "the page is told: the overlay of reload.js is called" "$err" 'globalThis.__lotusError({"file": "src/Broken.vue", "errors": [{"message": "BREAK in src/Broken.vue", "line": 2, "column": 3}]})'
check_has "and the import fails with what is wrong, where the console shows it" "$err" 'throw new Error("src/Broken.vue:2 – BREAK in src/Broken.vue")'
curl -s "${script[@]}" $B/src/Broken.vue >/dev/null
check_eq "the terminal says it once" "$(plain < $HOME/vue.log | grep -c '✗ src/Broken.vue:2  BREAK in src/Broken.vue')" 1
check_has "the overlay is in the script every page gets" "$(curl -s $B/__lotus/reload.js)" "window.__lotusError"
check_has "a compiler that ends is an error of the file" "$(curl -s "${script[@]}" $B/src/Crash.vue)" "did not answer"
check_has "and the next file is compiled again" "$(curl -s "${script[@]}" $B/src/App.vue)" "Changed"

# ── a stylesheet a script imports, a module without its extension, the router ──
css=$(curl -s "${script[@]}" $B/src/assets/main.css)
check_has "a stylesheet a script imports becomes a <link>" "$css" 'link.href = "/src/assets/main.css"'
check_eq "a <link> gets the stylesheet itself" "$(curl -s -H 'Sec-Fetch-Dest: style' -H 'Accept: text/css,*/*;q=0.1' $B/src/assets/main.css)" "body { margin: 0 }"
check_eq "and so does the swap of reload.js (?lotus=…)" "$(curl -s -H 'Accept: text/css,*/*;q=0.1' "$B/src/assets/main.css?lotus=1")" "body { margin: 0 }"
check_eq "a browser that opens it too" "$(curl -s -H 'Accept: text/html,*/*;q=0.8' $B/src/assets/main.css)" "body { margin: 0 }"
check_eq "import './util' finds util.js" "$(curl -s "${script[@]}" $B/src/util)" "export const y = 2"
check_eq "import './store' finds store/index.js" "$(curl -s "${script[@]}" $B/src/store)" "export const x = 1"
check_eq "a module that is not there is 404, not a page" "$(code "${script[@]}" $B/src/nothing)" 404
check_eq "without the script header a folder is what it was: sent to its /" "$(code $B/src/store)" 301
check_has "a page of the router (/about) is the index.html" "$(curl -s -H 'Accept: text/html' -H 'Sec-Fetch-Mode: navigate' $B/about/team)" '<div id="app">'
check_eq "a request that is not a page is 404 (an image, a script)" "$(code -H 'Accept: image/png' $B/logo.png)" 404
check_eq "so is one for anything else (/about asked for by anything)" "$(code $B/about)" 404
check_eq "and a file with an extension" "$(code -H 'Accept: text/html' -H 'Sec-Fetch-Mode: navigate' $B/about.html)" 404
check_eq "the secrets stay out as ever" "$(code $B/.env)" 404
pkill -f "liveserver.py --no-open --local --port $port" 2>/dev/null
for i in {1..30}; do plain < $HOME/vue.log | grep -q Stopped && break; sleep 0.1; done
check_has "it ends with the server" "$(plain < $HOME/vue.log)" "Stopped http://127.0.0.1:$port"
for i in {1..30}; do pgrep -f "stub-host.py" >/dev/null || break; sleep 0.1; done
check "and the compiler ends with it" eval '! pgrep -f "stub-host.py" >/dev/null'

# ── another folder is as it was ──
P=$HOME/plainsite
zf_mkdir -p $P/css
print -r -- '<!doctype html><title>Plain</title><p>plain</p>' >| $P/index.html
print -r -- '<!doctype html><script type="module">console.log(1)</script>' >| $P/mod.html
print -r -- 'body { color: red }' >| $P/css/style.css
free_port; port=$REPLY B=http://127.0.0.1:$REPLY
(cd $P && lotus liveserver --no-open --local --port $port >| $HOME/plain.log 2>&1 &)
check "a plain folder answers" up $port
check "it says nothing of Vue" eval '[[ $(plain < $HOME/plain.log) != *"Vue 3"* ]]'
check_eq "its stylesheet is the stylesheet, whatever asks (curl)" "$(curl -s $B/css/style.css)" "body { color: red }"
check_eq "a page that is not there is 404, not index.html" "$(code -H 'Accept: text/html' -H 'Sec-Fetch-Mode: navigate' $B/about)" 404
check_eq "a plain page is as it was" "$(curl -s $B/)" $'<!doctype html><title>Plain</title><p>plain</p>\n<script src="/__lotus/reload.js"></script>'
check_has "a page with a module script knows vue here too (it can only help)" "$(curl -s $B/mod.html)" '<script type="importmap">{"imports":{"vue":"/__lotus/vue/vue.js"}}</script><script type="module">'
check_eq "a stylesheet a script imports is a module when the browser says so, in any folder" "$(curl -s -H 'Sec-Fetch-Dest: script' $B/css/style.css | grep -c 'link.rel')" 1
pkill -f "liveserver.py --no-open --local --port $port" 2>/dev/null

# ── no compiler: a system that is not a Mac says so ──
if [[ $LOTUS_OS != macos ]]; then
  free_port; port=$REPLY B=http://127.0.0.1:$REPLY
  (cd $V && env -u LOTUS_VUE_HOST $LOTUS_ROOT/bin/lotus liveserver --no-open --local --port $port >| $HOME/nohost.log 2>&1 &)
  check "a folder of .vue files answers without a compiler" up $port
  check_has "the terminal says it" "$(plain < $HOME/nohost.log)" "Vue files are compiled on a Mac only – not here yet"
  check_has "so does the page: the .vue file is the error" "$(curl -s "${script[@]}" $B/src/App.vue)" "Vue files are compiled on a Mac only – not here yet"
  check_eq "the rest of the folder works" "$(code $B/src/util.js)" 200
  pkill -f "liveserver.py --no-open --local --port $port" 2>/dev/null
fi
