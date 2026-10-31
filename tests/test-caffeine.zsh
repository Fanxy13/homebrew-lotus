# Keep awake: on, status, off – only Lotus' own process is ever stopped (macOS: caffeinate, Linux: an inhibitor lock)
source $LOTUS_ROOT/lib/core.zsh
source $LOTUS_ROOT/lib/ui.zsh
lotus_load
source $LOTUS_ROOT/lib/cmd/caffeine.zsh
if [[ $TEST_OS == linux ]]; then
  # a container has no login manager: this stands in for systemd-inhibit and runs the command it is given
  zf_mkdir -p $HOME/bin
  print -r -- '#!/bin/sh
while [ $# -gt 0 ]; do case $1 in --*) shift ;; *) break ;; esac; done
exec "$@"' >| $HOME/bin/systemd-inhibit
  chmod +x $HOME/bin/systemd-inhibit
  path=($HOME/bin $path); rehash
  LOTUS_PKG= LOTUS_SESSION=x11
fi

out=$(lotus_caffeine_status)
check_has "off at first" "$out" "off"
lotus_caffeine_on 2 >/dev/null
check "it starts" lotus_caffeine_state
pid=$CAF_PID
check "a real process of Lotus runs" eval 'lotus_os_awake_is $pid'
check "with a time limit of 2 minutes" eval '(( CAF_END - CAF_START == 120 ))'
check_has "status: on, with the time left" "$(lotus_caffeine_status)" "2 min"
lotus_caffeine_on 1 >/dev/null
check "starting again replaces the old one" eval '! kill -0 $pid 2>/dev/null'
pid=$CAF_PID
lotus_caffeine_off >/dev/null
check "off stops it" eval '! kill -0 $pid 2>/dev/null'
check "and forgets it" eval '[[ ! -e $LOTUS_STATE/caffeine ]]'

# a stale state file that points at someone else's process is never acted on
zf_mkdir -p $LOTUS_STATE
sleep 30 &
other=$!
print -r -- "$other $EPOCHSECONDS 0" >| $LOTUS_STATE/caffeine
check "a process that is not Lotus' own is not taken for it" eval '! lotus_caffeine_state'
lotus_caffeine_off quiet
check "and is not stopped" kill -0 $other
kill $other 2>/dev/null

check "minutes must be a number" eval '! lotus_caffeine_on abc 2>/dev/null'
check "at most 24 hours" eval '! lotus_caffeine_on 5000 2>/dev/null'
