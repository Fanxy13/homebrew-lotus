#!/bin/zsh
# Lotus tests: zsh tests/run.zsh [name …]
# Every tests/test-*.zsh runs in its own empty home (nothing of yours is read or changed) and
# reports with check / check_eq. Exit status 1 when a check failed.
emulate -L zsh
setopt extendedglob
typeset -g ROOT=${0:A:h:h}
typeset -gi PASSED=0 FAILED=0

check() {   # <what> <command…> – passes when the command succeeds
  local what=$1; shift
  if "$@" >/dev/null 2>&1; then (( PASSED++ )); print -r -- "  ✓ $what"
  else (( FAILED++ )); print -r -- "  ✗ $what"; fi
}
check_eq() {   # <what> <got> <want>
  if [[ $2 == $3 ]]; then (( PASSED++ )); print -r -- "  ✓ $1"
  else (( FAILED++ )); print -r -- "  ✗ $1"$'\n'"      got:  ${2[1,300]}"$'\n'"      want: ${3[1,300]}"; fi
}
check_has() {   # <what> <text> <part>
  if [[ $2 == *"$3"* ]]; then (( PASSED++ )); print -r -- "  ✓ $1"
  else (( FAILED++ )); print -r -- "  ✗ $1"$'\n'"      missing: $3"$'\n'"      in: ${2[1,400]}"; fi
}

local file
local -a files=($ROOT/tests/test-*.zsh(N))
(( $# )) && files=(${^@:/(#m)*/$ROOT/tests/test-$MATCH.zsh})
for file in $files; do
  print -r -- "${file:t:r}"
  local home=$(mktemp -d "${TMPDIR:-/tmp}/lotus-test.XXXXXX")
  (
    export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
    export HOME=$home XDG_CONFIG_HOME= XDG_CACHE_HOME= XDG_STATE_HOME= XDG_DATA_HOME= LOTUS_ROOT=$ROOT
    PASSED=0 FAILED=0          # this file's own count
    source $file
    print -r -- "$PASSED $FAILED" >| $home/.result
  )
  local -a r=($(<$home/.result))
  (( PASSED += r[1], FAILED += r[2] ))
  rm -rf -- "${home:?}"
done
print
print -r -- "$PASSED passed, $FAILED failed"
(( FAILED == 0 ))
