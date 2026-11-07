# The contract between the zsh engine and Lotus for Windows (tests/contract): the answers in tests/contract/expected
# have to be what this zsh engine makes of the cases – win/tests/Contract.Tests.ps1 holds PowerShell to the same answers.
# After a change to the zsh engine that changes them on purpose:  zsh tests/contract/zsh.zsh tests/contract/expected

local out=$HOME/contract
zsh $ROOT/tests/contract/zsh.zsh $out >/dev/null 2>&1
check "the contract cases ran" test -s $out/sgr.tsv

local f rel
for f in $ROOT/tests/contract/expected/**/*(.N); do
  rel=${f#$ROOT/tests/contract/expected/}
  if [[ $rel == art.tsv && $TEST_OS != linux ]]; then
    # the logos are mixed in floating point: macOS' libm may round a last digit another way than glibc and PowerShell
    continue
  fi
  check_eq "zsh still makes $rel" "$(<$out/$rel)" "$(<$f)"
done
local -a made=($out/**/*(.N)) want=($ROOT/tests/contract/expected/**/*(.N))
check_eq "no answer is missing or new" ${#made} ${#want}

# Settings written by the other engine are read back as they were written: several shortcuts (zsh writes them in its
# own order, PowerShell by name), quotes inside values
local conf=$HOME/.config/lotus
mkdir -p $conf
print -r -- "LOTUS_NAME='O'\\''Brien'
typeset -gA LOTUS_SHORTCUTS=('gh' 'url|https://github.com|on' 'notes' 'path|/tmp/my notes|off' 'yt' 'url|https://youtube.com/results?search_query={q}|on')" >| $conf/settings.zsh
(
  source $ROOT/lib/core.zsh
  lotus_load
  check_eq "a name with an apostrophe" "$LOTUS_NAME" "O'Brien"
  check_eq "three shortcuts" ${#LOTUS_SHORTCUTS} 3
  check_eq "a shortcut with a space and off" "$LOTUS_SHORTCUTS[notes]" "path|/tmp/my notes|off"
  check_eq "a shortcut with ? and { }" "$LOTUS_SHORTCUTS[yt]" "url|https://youtube.com/results?search_query={q}|on"
)
