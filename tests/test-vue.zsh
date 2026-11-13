# Vue 3 in the Live Server (macOS): the Vue files of Lotus are the ones THIRD_PARTY.md names, and Vue's compiler – through the program that
# carries it, the way the Live Server asks it – makes the modules a browser runs. On a Mac that program is lotus-vue (lib/live/Vue.swift,
# JavaScriptCore, built here once), so the CI Macs test what the Live Server really starts; elsewhere Node plays its part
# (tests/live/vue-host.js) where there is one. No network: the server around it is tests/test-vueserver.zsh.
# With Playwright and Node, a Vue app runs in Chromium through the Live Server (tests/live/vue_ui.test.js).
source $LOTUS_ROOT/lib/core.zsh
source $LOTUS_ROOT/lib/ui.zsh
lotus_load
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
if (( ! $+commands[python3] )); then print -r -- "  – no python3: skipped"; return 0; fi

suite "the Vue files of Lotus" python3 -B $LOTUS_ROOT/tests/live/vendor_test.py

host=
if [[ $LOTUS_OS == macos ]]; then
  if lotus_swift_build lotus-vue $LOTUS_ROOT/lib/live/Vue.swift > /dev/null 2>&1; then host=$REPLY
  else print -r -- "  · lotus-vue could not be built here (Command Line Tools?): the compiler is not tested"; fi
elif (( $+commands[node] )); then host="node $LOTUS_ROOT/tests/live/vue-host.js"
else print -r -- "  · this is not a Mac and there is no Node: the compiler is not tested"; fi
if [[ -n $host ]]; then
  suite "the compiler" env LOTUS_VUE_HOST=$host python3 -B $LOTUS_ROOT/tests/live/vue_compile_test.py
fi

if (( $+commands[node] )) && node -e "require('playwright')" 2>/dev/null; then
  suite "a Vue app in a browser" node $LOTUS_ROOT/tests/live/vue_ui.test.js
else
  print -r -- "  · no Playwright for Node here: a Vue app is not driven in a browser (node tests/live/vue_ui.test.js does it where there is)"
fi
