# install.sh from start to end (macOS and Linux): it needs nothing but sh, installs into ~/.local, puts the lines into the
# startup file of the shell you log in with, can be run again, and `lotus uninstall --yes` takes everything away again.
# LOTUS_SRC makes the script copy this checkout instead of downloading one; fastfetch is already installed in the test images.
source $LOTUS_ROOT/lib/core.zsh
source $LOTUS_ROOT/lib/ui.zsh
lotus_load
plain() { sed $'s/\e\\[[0-9;?]*[a-zA-Z]//g' | tr -d '\r' }

check "install.sh is plain sh" sh -n $LOTUS_ROOT/install.sh
(( $+commands[dash] )) && check "and dash reads it too" dash -n $LOTUS_ROOT/install.sh
if ! (( $+commands[fastfetch] )); then print -r -- "  - fastfetch is not installed here; the installer would download it – skipped"; return 0; fi
want=$(LOTUS_ROOT=$LOTUS_ROOT $LOTUS_ROOT/bin/lotus version)

# ── a first install; the shell you log in with is bash ──
out=$(SHELL=/bin/bash LOTUS_SRC=$LOTUS_ROOT sh $LOTUS_ROOT/install.sh </dev/null 2>&1 | plain)
check_has "install: it names the system" "$out" "·"
check_has "install: fastfetch is there already" "$out" "fastfetch is already installed"
check "install: Lotus is in ~/.local/share/lotus" test -x $HOME/.local/share/lotus/bin/lotus
check "install: and linked in ~/.local/bin" test -L $HOME/.local/bin/lotus
check "install: logos and data came along" eval '[[ -d $HOME/.local/share/lotus/logos && -r $HOME/.local/share/lotus/data/commands.tsv ]]'
check "install: no tests or docs were copied" eval '[[ ! -e $HOME/.local/share/lotus/tests && ! -e $HOME/.local/share/lotus/docs ]]'
check_eq "install: the installed copy runs" "$(env -u LOTUS_ROOT $HOME/.local/bin/lotus version)" "$want"
check_has "install: ~/.bashrc has the lines of Lotus" "$(<$HOME/.bashrc)" "lib/init.bash"
check_has "install: with the PATH for ~/.local/bin" "$(<$HOME/.bashrc)" 'export PATH="$HOME/.local/bin:$PATH"'
check "install: ~/.zshrc was not touched (bash is the login shell)" test ! -e $HOME/.zshrc

# ── a second time: the same, nothing doubled ──
out=$(SHELL=/bin/bash LOTUS_SRC=$LOTUS_ROOT sh $LOTUS_ROOT/install.sh </dev/null 2>&1 | plain)
check_eq "again: the lines are in ~/.bashrc once" "$(grep -c '# >>> lotus >>>' $HOME/.bashrc)" 1
check_eq "again: and Lotus still runs" "$(env -u LOTUS_ROOT $HOME/.local/bin/lotus version)" "$want"

# ── the hook of the installed Lotus starts a real bash ──
print -r -- "echo from-the-rc" >| $HOME/.bash_profile
check_has "a login shell of bash loads Lotus without an error" "$(env -u LOTUS_ROOT HOME=$HOME PATH=$HOME/.local/bin:$PATH bash -ic 'type -t lotus' 2>&1)" "function"

# ── with zsh as the login shell ──
rm -f $HOME/.bashrc
out=$(SHELL=/bin/zsh LOTUS_SRC=$LOTUS_ROOT sh $LOTUS_ROOT/install.sh </dev/null 2>&1 | plain)
check_has "zsh login: the lines are in ~/.zshrc" "$(<$HOME/.zshrc)" "lib/init.zsh"
check "zsh login: ~/.bashrc was not made" test ! -e $HOME/.bashrc

# ── uninstall takes it all away ──
out=$(env -u LOTUS_ROOT SHELL=/bin/zsh $HOME/.local/bin/lotus uninstall --yes 2>&1 </dev/null | plain)
check "uninstall: the program is gone" test ! -e $HOME/.local/share/lotus
check "uninstall: and the link" test ! -e $HOME/.local/bin/lotus
check "uninstall: the lines are gone from ~/.zshrc" eval '[[ ! -e $HOME/.zshrc || $(<$HOME/.zshrc) != *lotus* ]]'
check "uninstall: the settings are gone" test ! -e $HOME/.config/lotus

# ── no zsh: the installer says so and stops, it installs nothing on its own ──
if [[ $LOTUS_OS == linux ]]; then
  zf_mkdir -p $HOME/nozsh
  for t in sh uname id mktemp rm mkdir cp ln chmod ls head cut awk tar find dirname basename curl true cat tr sed grep apt-get dnf pacman zypper apk sudo; do
    [[ -x ${commands[$t]} ]] && ln -sf ${commands[$t]} $HOME/nozsh/$t
  done
  out=$(PATH=$HOME/nozsh LOTUS_SRC=$LOTUS_ROOT $HOME/nozsh/sh $LOTUS_ROOT/install.sh </dev/null 2>&1 | plain); rc=$?
  check_has "no zsh: it says Lotus needs it" "$out" "which is not installed here"
  check_has "no zsh: and shows the command, it does not run it" "$out" "The command:"
  check "no zsh: nothing was installed" test ! -e $HOME/.local/share/lotus/bin/lotus
fi
