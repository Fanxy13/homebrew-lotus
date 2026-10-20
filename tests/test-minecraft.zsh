# The Minecraft control center (lib/mc): a server in the background with a console to write to, what the
# log says about players and the server, server.properties, the pages drawn into the window's size,
# the little world, plugins from Modrinth (checked, with dependencies) and dragged in, the LotusBridge plugin.
# A fake server (a zsh script that talks like one) stands in for Minecraft, a fake Modrinth for the real one.
source $LOTUS_ROOT/lib/core.zsh
source $LOTUS_ROOT/lib/ui.zsh
lotus_load
LOTUS_COLORS=truecolor; lotus_colors
source $LOTUS_ROOT/lib/mc/control.zsh
lotus_lang_group mc
strip() { REPLY=${1//$'\e'\[[0-9;?]#[A-Za-z]/} }
widest() {   # the widest line of the array out → REPLY
  local l; local -i w=0
  for l in "${out[@]}"; do strip "$l"; (( ${#REPLY} > w )) && w=${#REPLY}; done
  REPLY=$w
}
wait_for() {   # <seconds> <condition…>
  local -F end=$(( EPOCHREALTIME + $1 )); shift
  while (( EPOCHREALTIME < end )); do "$@" && return 0; sleep 0.1; done
  return 1
}

# ── a server that talks like Minecraft ──
S=$HOME/Minecraft/paper-1.21.4
mkdir -p $S
cat > $S/fake.zsh <<'X'
ts() { print -r -- "[$(date +%H:%M:%S) INFO]: $*" }
ts "Starting minecraft server version 1.21.4"
ts "Preparing spawn area: 40%"
ts 'Done (1.234s)! For help, type "help"'
ts "Steve joined the game"
ts "<Steve> hello there"
while read -r line; do
  case $line in
    stop) ts "Stopping server"; exit 0 ;;
    crash) exit 3 ;;
    *) ts "got: $line" ;;
  esac
done
X
print -r -- '#!/bin/zsh
cd "${0:A:h}"
exec /bin/zsh ./fake.zsh
exec "/nowhere/bin/java" -Xms3G -Xmx3G -jar server.jar nogui' > $S/start.command
chmod +x $S/start.command
print "eula=true" > $S/eula.txt
print -r -- $'motd=A Lotus Minecraft server\nmax-players=8\nserver-port=25565' > $S/server.properties
mkdir -p $S/.lotus; print -r -- $'type=vanilla\nversion=1.21.4' > $S/.lotus/server.conf

_mcc_init $S
check_eq "type and version from server.conf" "$MCC_TYPE $MCC_VER" "vanilla 1.21.4"
check_eq "memory from start.command" $MCC_XMX 3072
check_eq "server.properties read" "${MCC_PROP[max-players]}" 8

# ── start, the console, stop ──
_mcc_probe
check_eq "not running at first" $MCC_STATE stopped
_mcc_start
check "start: the console pipe is there" test -p $S/.lotus/console
ready() { _mcc_probe; _mcc_log_poll; _mcc_probe; [[ $MCC_STATE == running ]] }
check "the server runs and is ready" wait_for 5 ready
check "the server got its own session (Ctrl-C does not reach it)" eval '[[ $(ps -o sid= -p $MCC_PID | tr -d " ") != $(ps -o sid= -p $$ | tr -d " ") ]]'
check_eq "a player who joined is online" "$MCC_PORDER" Steve
check_has "events: ready, join, chat" "${(j:|:)MCC_EVENTS}" "join"$'\t'"Steve joined"
check_has "the chat line is an event" "${(j:|:)MCC_EVENTS}" "<Steve> hello there"
check_eq "spawn progress read, then done" $MCC_PROGRESS 100
_mcc_send "say hi"
got() { _mcc_log_poll; [[ ${MCC_LOG[-1]} == *"got: say hi" ]] }
check "a command reaches the server's console" wait_for 3 got
check_has "the command is in the log too" "${(F)MCC_LOG}" "[Lotus] > say hi"
_mcc_sample
check "memory of the running server" test $MCC_RSS -ge 0
# opened again (another control center): the running server is found, its log read from the start
pid=$MCC_PID
MCC_MODE= MCC_PID=0 MCC_WRAP=0 MCC_STATE=stopped
_mcc_probe; _mcc_log_poll; _mcc_probe
check_eq "opened again: the same server, running" "$MCC_PID $MCC_STATE" "$pid running"
check_eq "opened again: players from the log" "$MCC_PORDER" Steve
_mcc_stop
stopped() { _mcc_probe; _mcc_log_poll; [[ $MCC_STATE == stopped ]] }
check "stop: the server stops" wait_for 5 stopped
check_eq "stopped: nobody online" "${#MCC_PORDER}" 0
check_eq "stopped: exit code 0" "$(<$S/.lotus/exit)" 0
# a crash is told apart from a stop
_mcc_start
check "started again" wait_for 5 ready
_mcc_send crash
crashed() { _mcc_probe; [[ $MCC_STATE == crashed ]] }
check "a server that dies is shown as crashed" wait_for 5 crashed
# no EULA: asked first, nothing starts
print "eula=false" > $S/eula.txt
_mcc_start
check_eq "without the EULA: asked first" "$MCC_ASK $MCC_PROBLEM" "eula eula"
check "and nothing started" eval '[[ ! -r $S/.lotus/wrapper ]]'
MCC_ASK=eula; _mcc_ask_key y
check_eq "accepted: eula.txt says so" "$(<$S/eula.txt)" "eula=true"
check "accepted: the server starts" wait_for 5 ready
_mcc_stop; wait_for 5 stopped

# started some other way (double-clicked start.command): found by its folder, its own log read, stopped with SIGTERM
if (( $+commands[lsof] )); then
  ln -sf ${commands[zsh]} $S/java
  mkdir -p $S/logs
  ( cd $S && exec ./java ./fake.zsh < <(sleep 15) > $S/logs/latest.log 2>&1 ) &
  ext=$!
  sleep 0.5
  MCC_MODE=stopped MCC_T5=0 MCC_STATE=stopped
  _mcc_probe; _mcc_log_poll
  check_eq "started elsewhere: found, shown as running" "$MCC_MODE $MCC_STATE $MCC_PID" "external running $ext"
  check_eq "started elsewhere: players from logs/latest.log" "$MCC_PORDER" Steve
  check "started elsewhere: no commands" eval '! _mcc_send "say hi"'
  _mcc_probe
  check_eq "started elsewhere: still running a second later" "$MCC_STATE $MCC_PID" "running $ext"
  _mcc_stop
  gone() { ! kill -0 $ext 2>/dev/null }
  check "started elsewhere: stopped with SIGTERM" wait_for 5 gone
  wait $ext 2>/dev/null
  _mcc_probe
  check_eq "started elsewhere: then stopped" $MCC_STATE stopped
  rm -f $S/java
fi

# ── the log: Vanilla and Paper lines ──
_mcc_log_open /dev/null
_mcc_line '[10:00:01] [Server thread/INFO]: Alex joined the game'
_mcc_line '[10:00:02 INFO]: Sam joined the game'
_mcc_line '[10:00:03] [Server thread/INFO]: [Not Secure] <Alex> hi'
_mcc_line '[10:00:04] [Server thread/INFO]: Sam has made the advancement [Stone Age]'
_mcc_line '[10:00:05] [Server thread/INFO]: Alex lost connection: Disconnected'
_mcc_line '[10:00:05] [Server thread/INFO]: Alex left the game'
check_eq "joins from both formats, a leave" "$MCC_PORDER" Sam
check_has "an advancement" "${(j:|:)MCC_EVENTS}" "Sam reached [Stone Age]"
check_eq "one leave event, not two" "${#${(@M)MCC_EVENTS:#*leave*}}" 1
_mcc_line '[10:00:06] [Server thread/ERROR]: **** FAILED TO BIND TO PORT!'
check_eq "a taken port is noticed" $MCC_PROBLEM port
_mcc_line $'\e[33m[10:00:07 WARN]: colored\e[0m'
check_eq "colors are taken out of the log" "${MCC_LOG[-1]}" "[10:00:07 WARN]: colored"
MCC_PROBLEM=
_mcc_online_for "$(date +%H:%M:%S)"
check_eq "online for: just now" $REPLY 0s

# ── server.properties ──
_mcc_prop_set motd "Grüße 😀 \\ ok"
bs='\'
java="Gr${bs}u00FC${bs}u00DFe ${bs}uD83D${bs}uDE00 ${bs}${bs} ok"
check_has "non-ASCII written the Java way" "$(<$S/server.properties)" "motd=$java"
check_eq "and read back" "${MCC_PROP[motd]}" "$java"
_mcc_motd
check_eq "the description as Minecraft shows it" "$REPLY" "Grüße 😀 \\ ok"
check_has "other settings stay" "$(<$S/server.properties)" "max-players=8"
_mcc_prop_set white-list true
check_has "a missing setting is added" "$(<$S/server.properties)" "white-list=true"
_mcc_prop_set motd $'§aGreen §lbold'
_mcc_motd
check_eq "color codes are left out of the preview" "$REPLY" "Green bold"

# ── the pages fit into the window ──
_mcc_start; wait_for 5 ready
for size in "60 18" "80 24" "100 30" "160 45"; do
  MCC_W=${size% *} MCC_H=${size#* }
  for page in 1 2 3; do
    MCC_PAGE=$page
    raw=$(_mcc_draw)
    out=("${(@f)${raw//$'\e[K'/}}")
    widest
    check "page $page at $MCC_W × $MCC_H: no line wider than the window" test $REPLY -le $MCC_W
    check "page $page at $MCC_W × $MCC_H: no more lines than the window" test ${#out} -le $MCC_H
  done
done
MCC_W=100 MCC_H=30 MCC_PAGE=1
strip "$(_mcc_draw)"
check_has "stats: the player online" "$REPLY" "Steve"
check_has "stats: Vanilla tells no ping" "$REPLY" "only Paper servers"
MCC_PAGE=3
strip "$(_mcc_draw)"
check_has "log: the console lines" "$REPLY" "<Steve> hello there"
_mcc_line '[10:00:07 WARN]: something is off'
MCC_FILTER=warn
strip "$(_mcc_draw)"
check "log filter: only warnings" eval '[[ $REPLY != *"hello there"* && $REPLY == *"something is off"* ]]'
MCC_FILTER=all MCC_PAGE=2
strip "$(_mcc_draw)"
check_has "settings: how friends see the server" "$REPLY" "Green bold"
MCC_W=40
check_has "a window too small says so" "$(_mcc_draw)" "bigger"
MCC_W=100
_mcc_stop; wait_for 5 stopped

# keys: tab through the pages, typing a command, the quit question
MCC_PAGE=1
_mcc_handle tab; check_eq "tab: next page" $MCC_PAGE 2
_mcc_handle btab; check_eq "shift-tab: back" $MCC_PAGE 1
_mcc_handle 3; check_eq "3: the log" $MCC_PAGE 3
_mcc_handle q; check_eq "q with the server stopped: leave at once" $? 9
MCC_MODE=ours MCC_STATE=running
_mcc_handle q; check_eq "q while it runs: asks first" "$MCC_ASK" quit
_mcc_handle esc; check_eq "esc: stays" "$MCC_ASK" ""
MCC_STATE=stopped MCC_MODE=stopped

# ── the little world ──
for t in 0 30 75 100; do
  MCW_T=$t MCW_LAST=0
  _mcw_frame 40 10 2 0
  out=("${reply[@]}")
  widest
  check_eq "world at ${t}s: 10 rows" ${#reply} 10
  check_eq "world at ${t}s: 40 columns" $REPLY 40
done
check "world: grass, stone and bedrock in the theme's colors" eval '[[ ${(j::)reply} == *${MCW_FG[g]}* && ${(j::)reply} == *${MCW_FG[b]}* ]]'
LOTUS_THEME=ocean; lotus_colors; MCW_THEME=
_mcw_frame 40 10 0 1
check_eq "another theme, other colors" "${MCW_FG[g]}" "38;2;${${(s: :)LOTUS_THEMES[ocean]}[2]}"
LOTUS_THEME=matcha; lotus_colors; MCW_THEME=
_mcw_icon
check_eq "the grass block icon: 6 rows" ${#reply} 6

# ── plugins: Modrinth ──
port=$(( 20000 + RANDOM % 20000 ))
export FAKE_LOG=$HOME/modrinth.log
python3 $LOTUS_ROOT/tests/fake-modrinth.py $port &
fake=$!
sleep 0.8
MCP_API=http://127.0.0.1:$port/v2 MCP_CDN=http://127.0.0.1:$port/files/
_mcp_search_url "luck perms" 1.21.4 30
check_has "search: the words" "$REPLY" "query=luck+perms"
check_has "search: only plugin loaders, only this version" "$REPLY" "%22categories%3Apaper%22"
check_has "search: the version" "$REPLY" "%22versions%3A1.21.4%22"
check_has "empty search: most downloaded first" "$(_mcp_search_url '' 1.21.4 0; print $REPLY)" "index=downloads"
f=$HOME/search.out
_mcp_search_start "" 1.21.4 0 $f
check "a search in the background" wait_for 5 test -e $f
lines=("${(@f)$(<$f)}")
check_eq "total, then one line per plugin" "${lines[1]}" 42
check_eq "a result: id, slug, title, downloads, author, description" "${lines[2]}" $'good\tgood-plugin\tGood Plugin\t1234567\tsomeone\tDoes good things well'
check_has "Modrinth learns who asks" "$(<$FAKE_LOG)" "homebrew-lotus"
_mcp_count 1234567; check_eq "big numbers short" $REPLY 1.2M
_mcp_count 4000; check_eq "thousands" $REPLY 4k
P=$HOME/Minecraft/paper-1.21.4
MCP_DONE=()
check "install: a release, checked" _mcp_install $P good good-plugin "Good Plugin" 1.21.4
check_eq "the file is in plugins/" "$(<$P/plugins/good.jar)" "jar of good.jar"
check_eq "the release, not the beta" "$MCP_DONE" "Good Plugin 1.5"
check_has "noted as installed by Lotus" "$(<$P/.lotus/plugins.tsv)" $'good\tgood-plugin\tGood Plugin\t1.5\tgood.jar'
check "a wrong checksum: refused" eval '! _mcp_install $P broken broken Broken 1.21.4'
check_has "  and said so" "$MCP_ERR" "checksum"
check "  nothing stays behind" eval '[[ ! -e $P/plugins/broken.jar && -z $P/plugins/.*.part(#qN) ]]'
MCP_DONE=()
_mcp_install $P needsdep needs-dep "Needs Dep" 1.21.4
check "a required dependency comes along" test -f $P/plugins/dep.jar
check "an id that is no id: refused" eval '! _mcp_install $P "../x" x x 1.21.4'
MCP_CDN=https://cdn.modrinth.com/
check "only from Modrinth's own download server" eval '! _mcp_install $P good good-plugin Good 1.21.4'
MCP_CDN=http://127.0.0.1:$port/files/
kill $fake 2>/dev/null

# dragged in, listed, removed
cd $HOME
mkdir -p jars
print -r -- $'name: "Own Plugin"\nversion: 0.9\nmain: a.B' > plugin.yml && zip -q "jars/Own Plugin.jar" plugin.yml
print -r -- '{}' > fabric.mod.json && zip -q jars/mod.jar fabric.mod.json
print -r -- 'x' > readme.txt && zip -q jars/nothing.jar readme.txt
cd $LOTUS_ROOT
check "a dragged plugin is added (a name with a space)" _mcp_drop $P "$HOME/jars/Own\\ Plugin.jar"
check "  into plugins/" test -f "$P/plugins/Own Plugin.jar"
check "a Fabric mod is refused" eval '! _mcp_drop $P $HOME/jars/mod.jar'
check_has "  and named" "$MCP_ERR" "Fabric mod"
check "a jar without plugin.yml is refused" eval '! _mcp_drop $P $HOME/jars/nothing.jar'
_mcp_installed $P
check_has "installed: name and version from plugin.yml" "${(j:|:)reply}" $'Own Plugin.jar\tOwn Plugin\t0.9\town'
check_has "installed: Modrinth's title" "${(j:|:)reply}" $'good.jar\tGood Plugin\t1.5\tmodrinth'
_mcp_remove $P good.jar
check "removed" test ! -e $P/plugins/good.jar
check "  and no longer noted" eval '[[ $(<$P/.lotus/plugins.tsv) != *good.jar* ]]'
check "a path is not a plugin file" eval '! _mcp_remove $P ../server.properties'

# ── LotusBridge: built with javac against the server's API (here a small stand-in) ──
if (( $+commands[javac] )); then
  api=$HOME/api
  mkdir -p $api/org/bukkit/entity $api/org/bukkit/plugin/java $api/org/bukkit/scheduler
  print -r -- 'package org.bukkit; public final class Bukkit { public static org.bukkit.scheduler.BukkitScheduler getScheduler() { return null; } public static java.util.Collection<? extends org.bukkit.entity.Player> getOnlinePlayers() { return null; } }' > $api/org/bukkit/Bukkit.java
  print -r -- 'package org.bukkit; public interface World { String getName(); }' > $api/org/bukkit/World.java
  print -r -- 'package org.bukkit; public enum GameMode { SURVIVAL, CREATIVE }' > $api/org/bukkit/GameMode.java
  print -r -- 'package org.bukkit.entity; public interface Player { String getName(); org.bukkit.World getWorld(); double getHealth(); org.bukkit.GameMode getGameMode(); int getLevel(); }' > $api/org/bukkit/entity/Player.java
  print -r -- 'package org.bukkit.plugin; public interface Plugin {}' > $api/org/bukkit/plugin/Plugin.java
  print -r -- 'package org.bukkit.plugin.java; public abstract class JavaPlugin implements org.bukkit.plugin.Plugin { public java.io.File getDataFolder() { return null; } public void onEnable() {} public void onDisable() {} }' > $api/org/bukkit/plugin/java/JavaPlugin.java
  print -r -- 'package org.bukkit.scheduler; public interface BukkitScheduler { Object runTaskTimer(org.bukkit.plugin.Plugin p, Runnable r, long a, long b); Object runTaskAsynchronously(org.bukkit.plugin.Plugin p, Runnable r); }' > $api/org/bukkit/scheduler/BukkitScheduler.java
  mkdir -p $api/classes
  javac -d $api/classes $api/org/bukkit/**/*.java(.) >/dev/null 2>&1
  B=$HOME/Minecraft/bridge-test
  mkdir -p $B/libraries/stub $B/.lotus
  (cd $api/classes && jar cf $B/libraries/stub/api.jar .)
  print -r -- x > $B/server.jar
  print -r -- $'type=paper\nversion=1.21.4' > $B/.lotus/server.conf
  print -r -- "#!/bin/zsh
cd \"\${0:A:h}\"
exit 0
exec \"${commands[javac]:A:h}/java\" -Xmx1G -jar server.jar nogui" > $B/start.command
  chmod +x $B/start.command
  mkfifo $B/.lotus/console; : > $B/.lotus/console.log
  zsh $LOTUS_ROOT/lib/mc/run.zsh $B
  check "LotusBridge is built for a Paper server" test -s $B/plugins/LotusBridge.jar
  check_has "  with its plugin.yml and class" "$(unzip -l $B/plugins/LotusBridge.jar 2>/dev/null)" "lotus/bridge/LotusBridge.class"
  check_has "  and says so in the log" "$(<$B/.lotus/console.log)" "LotusBridge ready"
  stamp=$(<$B/.lotus/bridge)
  zsh $LOTUS_ROOT/lib/mc/run.zsh $B
  check_eq "  built once, not on every start" "$(<$B/.lotus/bridge)" "$stamp"
fi

# the bridge's file → ping, TPS and who is online
MCC_DIR=$S MCC_PID=$$ MCC_BR_AT=0
mkdir -p $S/plugins/LotusBridge
print -r -- $'time\t1\ntps\t19.8\t4.2\nplayer\tAlex\t35\tworld\t20\tsurvival\t3' > $S/plugins/LotusBridge/status.tsv
MCC_PLAYERS=() MCC_PORDER=(Steve)
MCC_PLAYERS[Steve]=10:00:00
_mcc_bridge
check_eq "bridge: TPS and tick time" "$MCC_TPS $MCC_MSPT" "19.8 4.2"
check_eq "bridge: who is online (Steve left, Alex was there before the log)" "$MCC_PORDER" Alex
check_eq "bridge: ping, world, health, mode" "${MCC_BR[Alex]}" $'35\tworld\t20\tsurvival\t3'
_mcc_ping_bars 35; strip $REPLY; check_eq "good ping: four bars" $REPLY ▂▄▆█
_mcc_ping_bars 400; strip $REPLY; check_eq "bad ping: one bar" $REPLY ▂···

# no terminal: one line
check_eq "no terminal: the state in one line" "$(lotus_mcc $S < /dev/null 2>&1)" "paper-1.21.4: stopped"
