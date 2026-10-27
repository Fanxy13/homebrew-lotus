# Installing plugins (lib/cmd/plugin.zsh): several at once, a folder of plugins, packs (pack.conf) with their
# settings, the drag-and-drop installer, a pack made from your plugins – and what the pets know about it all.
source $LOTUS_ROOT/lib/core.zsh
source $LOTUS_ROOT/lib/ui.zsh
lotus_load
lotus() { $LOTUS_ROOT/bin/lotus "$@" }
plain() { sed $'s/\e\\[[0-9;?]*[a-zA-Z]//g' | tr -d '\r' }
# keys typed on a keyboard: script gives Lotus a terminal, the keys come when it waits
answer() { (sleep 1.5; print -rn -- $1; sleep 0.8) | script -q /dev/null zsh -fc "$2" 2>&1 | plain }
P=$LOTUS_CONF/plugins D=$LOTUS_DATA/plugins
# the installer looks at the clipboard – never the real one in a test
zf_mkdir -p $HOME/bin
print -r -- $'#!/bin/sh\necho "nothing to see"' >| $HOME/bin/pbpaste && chmod +x $HOME/bin/pbpaste

# ── sources ──
source $LOTUS_ROOT/lib/cmd/plugin.zsh
_plg_child_src https://github.com/you/pack todo;         check_eq "a folder of a git pack" "$REPLY" "https://github.com/you/pack#todo"
_plg_child_src "https://github.com/you/repo#packs/a" ./x; check_eq "in a folder of a repository" "$REPLY" "https://github.com/you/repo#packs/a/x"
_plg_child_src https://github.com/you/pack .;            check_eq "the pack's own folder" "$REPLY" "https://github.com/you/pack"
_plg_child_src $HOME/pack todo;                          check_eq "a folder on this Mac: nothing to remember" "$REPLY" ""
check_has "a folder that leaves the repository: refused" "$(lotus plugin install 'https://github.com/you/x#../y' 2>&1 | plain)" "Not a folder in the repository"
check_has "neither a folder nor a link" "$(lotus plugin install nothing-here 2>&1 | plain)" "Not a folder or a git URL"

# ── a pack: plugins of its own, one turned off, settings and files ──
K=$HOME/my-pack
zf_mkdir -p $K/files/todo
cp -R $LOTUS_ROOT/plugins/todo $K/todo
cp -R $LOTUS_ROOT/plugins/github $K/github
print -r -- "from the pack" >| $K/files/todo/hello.txt
cat >| $K/pack.conf <<'EOF'
# a test pack
name        = starter
title       = Starter pack
version     = 1.0
author      = Tester
description = A to-do list and GitHub   # a comment after a value
plugin = ./todo
plugin = ./github off
set todo.SORT    = newest
set github.WHERE = ~/stars
set github.DATA  = {data}/cache
files todo       = ./files/todo
EOF
check_has "check: a pack is fine" "$(lotus plugin check $K 2>&1 | plain)" "pack.conf is fine – 2 plugins, settings for 2 of them"
out=$(answer $'\ry' "$LOTUS_ROOT/bin/lotus plugin install $K")
check_has "the pack is shown" "$out" "Starter pack  pack 1.0 · by Tester"
check_has "a comment after a value is not part of it" "$out" "A to-do list and GitHub"$'\n'
check_has "each plugin, with what it may do" "$out" "limited – its own folder and the internet"
check_has "the settings it brings" "$out" "setting SORT = newest"
check_has "a choice of which ones" "$out" "Which ones? All are chosen."
check_has "one question for all" "$out" 'Install the pack "Starter pack" – 2 plugins? [y/N] yes'
check_has "installed" "$out" 'The pack "Starter pack" is installed – 2 plugins'
check_has "turned on" "$(<$LOTUS_CONF/plugins.tsv)" $'todo\ton\tlimited'
check_has "or off, as the pack says" "$(<$LOTUS_CONF/plugins.tsv)" $'github\toff\tlimited'
check_eq "a setting in the plugin's settings file" "$(<$D/todo/settings)" "SORT=newest"
check_has "~ is the home folder" "$(<$D/github/settings)" "WHERE=$HOME/stars"
check_has "{data} is the plugin's data folder" "$(<$D/github/settings)" "DATA=$D/github/cache"
check_eq "its files are in the data folder" "$(<$D/todo/hello.txt)" "from the pack"
check "a pack from a folder: no source to update from" test ! -e $D/.todo-source
check "nothing is left behind" eval '[[ -z $(print -l $P/.lotus-plugin-*(N)) ]]'
print -r -- "OTHER=mine" >> $D/todo/settings
answer $'\ry' "$LOTUS_ROOT/bin/lotus plugin install $K" >/dev/null
check_eq "again: the pack's settings replace theirs, the others stay" "$(<$D/todo/settings)" $'OTHER=mine\nSORT=newest'

# a pack that is not right
B=$HOME/bad-pack
zf_mkdir -p $B
cat >| $B/pack.conf <<EOF
name = Bad Pack
plugin = ../todo
plugin = $LOTUS_ROOT/plugins/todo
plugin = ./missing maybe
set todo = x
files todo = ../
EOF
out=$(lotus plugin check $B 2>&1 | plain)
check_has "check: a wrong name" "$out" "name must be"
check_has "no description" "$out" "a description is missing"
check_has "a folder outside the pack" "$out" "plugin = ../todo: not a plugin folder of the pack"
check_has "a folder of this Mac" "$out" "plugin = $LOTUS_ROOT/plugins/todo: not a plugin folder of the pack"
check_has "on or off only" "$out" "then on or off"
check_has "a setting without its name" "$out" "set todo: write set <plugin>.<SETTING> = <value>"
check_has "files from outside the pack" "$out" "files todo = ../: it must be a folder of the pack"
out=$(answer y "$LOTUS_ROOT/bin/lotus plugin install $B")
check_has "and it is not installed" "$out" "This pack cannot be installed"

# ── a folder with plugins in it: choose which ones ──
answer y "$LOTUS_ROOT/bin/lotus plugin remove todo" >/dev/null
answer y "$LOTUS_ROOT/bin/lotus plugin remove github" >/dev/null
out=$(answer $' \ry' "$LOTUS_ROOT/bin/lotus plugin install $LOTUS_ROOT/plugins")
check_has "all of them are shown" "$out" "● Hello"
check_has "space leaves one out, the question names the full ones" "$out" 'Install 4 plugins, hello, liveserver with full access to your Mac and Lotus? [y/N] yes'
check "the one left out is not installed" test ! -e $P/github
check "the others are" eval '[[ -r $P/hello/plugin.conf && -r $P/liveserver/plugin.conf && -r $P/meshchat/plugin.conf && -r $P/todo/plugin.conf ]]'
out=$(answer $'\rn' "$LOTUS_ROOT/bin/lotus plugin install $LOTUS_ROOT/plugins/github $LOTUS_ROOT/plugins/todo")
check_has "two given: both shown, one question" "$out" "Install 2 plugins? [y/N] no"
check "no: nothing installed" test ! -e $P/github

# ── the installer: drag folders in ──
out=$(answer "$LOTUS_ROOT/plugins/github $HOME/no\\ such\\ folder"$'\ryq' "PATH=$HOME/bin:\$PATH COLUMNS=80 $LOTUS_ROOT/bin/lotus plugin installer")
check_has "installer: a drop zone" "$out" "Drag plugin folders here"
check_has "installer: what was not found" "$out" "Not found: $HOME/no such folder"
check_has "installer: the dropped plugin is shown and asked for" "$out" 'Install the plugin "github"? [y/N] yes'
check "installer: installed" test -r $P/github/plugin.conf
cp -R $LOTUS_ROOT/plugins/hello "$HOME/My Hello"
answer y "$LOTUS_ROOT/bin/lotus plugin remove hello" >/dev/null
out=$(answer "$HOME/My Hello"$'\ryq' "PATH=$HOME/bin:\$PATH $LOTUS_ROOT/bin/lotus plugin installer")
check_has "installer: a path with spaces, dragged without quotes" "$out" 'Install "hello" with full access to your Mac and Lotus? [y/N] yes'
check_has "installer: Enter alone ends it" "$(answer $'\r' "PATH=$HOME/bin:\$PATH $LOTUS_ROOT/bin/lotus plugin installer")" "Enter alone: done"
check_has "installer: without a terminal it says what to do" "$(lotus plugin installer </dev/null 2>&1 | plain)" "lotus plugin install <folder, git URL or pack>"

# ── a pack of your plugins ──
lotus plugin off github >/dev/null
zf_mkdir -p $D/todo
print -r -- "SORT=oldest"$'\n'"FILE=$D/todo/list.txt" >| $D/todo/settings
out=$(cd $HOME && lotus plugin pack my-setup 2>&1 | plain)
check_has "pack: made" "$out" 'Your pack "my-setup" is ready'
conf=$(<$HOME/my-setup/pack.conf)
check_has "your own plugins are copied in" "$conf" "plugin = ./todo"
check "with their files" test -r $HOME/my-setup/todo/plugin.conf
check_has "one that is off stays off" "$conf" "plugin = ./github off"
check_has "with their settings" "$conf" "set todo.SORT = oldest"
check_has "a path in its data folder becomes {data}" "$conf" "set todo.FILE = {data}/list.txt"
check_has "and the pack is right" "$(lotus plugin check $HOME/my-setup 2>&1 | plain)" "pack.conf is fine – 5 plugins"
check_has "a pack needs a name" "$(lotus plugin pack 2>&1 | plain)" "A pack needs a name"

# ── what the pets know ──
lotus_load
zf_mkdir -p $LOTUS_CONF
print -r -- $'Mochi\tcat\t\t'$EPOCHSECONDS >| $LOTUS_CONF/pets.tsv
lotus plugin on github >/dev/null
source $LOTUS_ROOT/lib/cmd/pets.zsh
_pet_knowledge
check_has "pets know the plugin installer" "$REPLY" "/plugin installer"
check_has "and plugin packs" "$REPLY" "A plugin pack is a GitHub repository"
check_has "and the web chat's code panel" "$REPLY" "code panel"
check_has "and the plugins you have" "$REPLY" "lotus todo: A small to-do list"
lotus features weather off >/dev/null 2>&1; lotus_load; unset PET_KNOW
_pet_knowledge
check "a feature that is off: they do not talk about it" eval '[[ $REPLY != *"/weather"* ]]'
lotus features weather on >/dev/null 2>&1; lotus_load
_pet_commands
check_has "/help knows the commands of your plugins" "${(F)PET_CMDS}" $'/repo\tplugin\t/repo'
_pet_rank "how do I install a plugin pack"
hits=; for i in $reply; do hits+=$PET_CMDS[i]$'\n'; done
check_has "and finds packs" "$hits" "plugin pack"
_pet_tip; check_eq "a tip works (broken from 2.3 to 2.16)" $? 0

# ── uninstalling ──
out=$(answer y "$LOTUS_ROOT/bin/lotus plugin uninstall HELLO")
check_has "uninstall: a name in capitals, what goes, and a question" "$out" 'Remove the plugin "hello"'
check_has "uninstalled" "$out" 'The plugin "hello" is uninstalled'
check "its folder and its entry are gone" eval '[[ ! -e $P/hello && "$(<$LOTUS_CONF/plugins.tsv)" != *hello* ]]'
out=$(answer n "$LOTUS_ROOT/bin/lotus plugin uninstall nope todo github")
check_has "a name that is not there" "$out" 'There is no plugin "nope"'
check_has "several at once: one question" "$out" "Uninstall 2 plugins and their data? [y/N] no"
check "no: they stay" eval '[[ -r $P/todo/plugin.conf && -r $P/github/plugin.conf ]]'
out=$(answer $' \ry' "$LOTUS_ROOT/bin/lotus plugin uninstall")
check_has "without a name: a list to choose from" "$out" "uninstall – choose the ones that go"
check "the one chosen is gone, the other stays" eval '[[ ! -e $P/github && -r $P/todo/plugin.conf ]]'
check_has "without a terminal it asks for a name" "$(lotus plugin uninstall </dev/null 2>&1 | plain)" "lotus plugin uninstall <name>"
answer y "$LOTUS_ROOT/bin/lotus plugin remove todo" >/dev/null
check "remove is the same" eval '[[ ! -e $P/todo && ! -e $D/todo ]]'
