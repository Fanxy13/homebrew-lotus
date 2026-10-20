#!/bin/zsh
# lotus – runs one Minecraft server in the background for the control center (lib/mc/control.zsh).
#   zsh run.zsh <server folder>
# The server reads its console from the pipe .lotus/console, which is opened here for reading and
# writing: the server never sees its end, and the control center can write commands into it at any
# time, also after it was closed and opened again. Everything the server prints goes to
# .lotus/console.log. Started with nohup, so closing the terminal window does not stop the server;
# caffeinate keeps the Mac awake while it runs (the display may still sleep).
# A Paper server first gets the LotusBridge plugin (ping and TPS), built here with the JDK's javac.
emulate -L zsh
setopt extendedglob
zmodload zsh/datetime
dir=${1:A} s=${1:A}/.lotus root=${0:A:h:h:h}
cd -- $dir 2>/dev/null || exit 1
[[ -p $s/console ]] || exit 1
exec 3<>$s/console || exit 1
print -r -- $$ >| $s/wrapper
print -r -- $EPOCHSECONDS >| $s/started
rm -f $s/exit $s/pid

note() { print -r -- "[Lotus] $*" >> $s/console.log }

# The java of start.command: exec "/…/bin/java" -Xms4G -Xmx4G -jar server.jar nogui
java_bin() {
  local line
  for line in "${(@f)$(<$dir/start.command)}"; do
    [[ $line == (#b)exec\ \"([^\"]##)\"* ]] && { REPLY=$match[1]; return 0 }
  done
  REPLY=java
}

# LotusBridge: built once per source and server version, kept in plugins/LotusBridge.jar
bridge() {
  local src=$root/lib/mc/bridge stamp=$s/bridge
  local want="$(cat $src/LotusBridge.java $src/plugin.yml | cksum) ${$(cksum < $dir/server.jar)[1]}"
  [[ -f $dir/plugins/LotusBridge.jar && -r $stamp && $(<$stamp) == $want ]] && return 0
  # it failed for this source and server before: not again on every start
  [[ -r $stamp && $(<$stamp) == "failed $want" ]] && return 1
  print -r -- "failed $want" >| $stamp
  java_bin; local java=$REPLY
  local jdk=${java:h} javac
  [[ $java == java ]] && jdk=${commands[java]:A:h}
  javac=$jdk/javac
  if [[ ! -x $javac ]]; then note "Ping and TPS need a JDK (javac) – skipped"; rm -f $stamp; return 1; fi
  # Paper keeps its API in libraries/ and versions/ once it has been unpacked – the first time, unpack it now
  if [[ -z $dir/libraries/**/*.jar(#qN[1]) && -z $dir/cache/*.jar(#qN[1]) ]]; then
    note "Preparing Paper for its first start …"
    $java -Dpaperclip.patchonly=true -jar server.jar >> $s/console.log 2>&1 < /dev/null
  fi
  local -a cp=($dir/libraries/**/*.jar(N) $dir/versions/**/*.jar(N) $dir/cache/*.jar(N))
  (( ${#cp} )) || { note "Ping and TPS: Paper's libraries are missing – skipped"; rm -f $stamp; return 1 }
  local tmp=$s/bridge-build
  rm -rf -- $tmp; mkdir -p $tmp/classes
  if ! $javac -nowarn -proc:none -encoding UTF-8 -d $tmp/classes -cp ${(j.:.)cp} $src/LotusBridge.java > $tmp/javac.log 2>&1; then
    note "Ping and TPS: the bridge plugin could not be built (see .lotus/bridge-build/javac.log)"
    return 1
  fi
  cp $src/plugin.yml $tmp/classes/
  mkdir -p $dir/plugins
  if [[ -x $jdk/jar ]]; then ( cd $tmp/classes && $jdk/jar cf ../LotusBridge.jar . ) >/dev/null 2>&1
  else ( cd $tmp/classes && zip -qr ../LotusBridge.jar . ) >/dev/null 2>&1; fi
  [[ -s $tmp/LotusBridge.jar ]] || { note "Ping and TPS: packing the bridge plugin failed"; return 1 }
  mv -f $tmp/LotusBridge.jar $dir/plugins/LotusBridge.jar
  print -r -- $want >| $stamp
  rm -rf -- $tmp
  note "LotusBridge ready – ping and TPS show in the control center"
}

[[ $(<$s/server.conf 2>/dev/null) == *type=paper* ]] && bridge

"$dir/start.command" <&3 >> $s/console.log 2>&1 &
pid=$!
print -r -- $pid >| $s/pid
(( $+commands[caffeinate] )) && caffeinate -i -w $pid >/dev/null 2>&1 &!
wait $pid
code=$?
print -r -- $code >| $s/exit
rm -f $s/pid $s/wrapper
note "The server stopped (exit code $code)"
