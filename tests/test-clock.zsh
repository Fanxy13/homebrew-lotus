# /clock: the designs draw what they should, time zones are checked, no terminal → only the time
source $LOTUS_ROOT/lib/core.zsh
source $LOTUS_ROOT/lib/ui.zsh
lotus_load
source $LOTUS_ROOT/lib/cmd/clock.zsh
zmodload zsh/datetime
_clk_setup
strip() { REPLY=${1//$'\e'\[[0-9;]#m/} }
width_ok() {   # every line of reply as wide as CLK_W (lines may be shorter, never wider)
  local l
  for l in "${reply[@]}"; do strip "$l"; (( ${#REPLY} <= CLK_W )) || return 1; done
}

_clk_bigrows 12:34 2
check_eq "big digits: 7 rows" ${#reply} 7
check "big digits: all rows as wide" test ${#reply[1]} -eq ${#reply[7]}
check_has "big digits: drawn with blocks" "$reply[1]" "██"

for design in minimal big retro analog world; do
  case $design in
    minimal) _clk_minimal 12:34:56 "Saturday, 10 October 2026" ;;
    big)     _clk_big 12:34:56 "Saturday, 10 October 2026" 120 ;;
    retro)   _clk_retro 12:34:56 "Saturday, 10 October 2026" 120 ;;
    analog)  _clk_analog 30 110 1 "Saturday" ;;
    world)   _clk_world 1 110 ;;
  esac
  check "$design: draws something" test ${#reply} -gt 1
  check "$design: no line wider than the design" width_ok
done
_clk_matrix 12:34 30 100
check_eq "matrix: fills the window height" ${#reply} 26
_clk_big 12:34:56 x 60
check "big: one column per pixel when the window is narrow" test $CLK_W -le 56

_clk_zone_line Europe/London 0
check "a time zone: city and time" eval '[[ $REPLY == "London "[0-2][0-9]:[0-5][0-9]* ]]'
check "a zone that does not exist is refused" eval '! _clk_offset Mars/Olympus'
LOTUS_CLOCK_ZONES='../../etc/passwd Asia/Tokyo'
_clk_world 0 110
strip "${(j: :)reply}"
check "world: only real zone names" eval '[[ $REPLY != *passwd* && $REPLY == *Tokyo* ]]'

out=$(lotus_cmd_clock clock < /dev/null)
check "no terminal: only the time" eval '[[ $out == [0-2][0-9]:[0-5][0-9]:[0-5][0-9] ]]'
