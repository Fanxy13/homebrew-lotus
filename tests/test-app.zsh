# /app: the apps of the system, found by name (typos included) and started. Linux: the desktop entries of
# ~/.local/share/applications, the system's folders and Flatpak/Snap; macOS has its own list (tests/test-apps… not here).
source $LOTUS_ROOT/lib/core.zsh
source $LOTUS_ROOT/lib/ui.zsh
source $LOTUS_ROOT/lib/fuzzy.zsh
lotus_load
lotus() { $LOTUS_ROOT/bin/lotus "$@" }
plain() { sed $'s/\e\\[[0-9;?]*[a-zA-Z]//g' | tr -d '\r' }
onlyon linux "the desktop entries of Linux" || return 0

zf_mkdir -p $HOME/.local/share/applications $HOME/bin
cat >| $HOME/bin/fakefox <<'X'
#!/bin/sh
printf '%s\n' "$@" > "$HOME/launched"
X
chmod +x $HOME/bin/fakefox
cat >| $HOME/.local/share/applications/fakefox.desktop <<X
[Desktop Entry]
Type=Application
Name=Fire Fox Browser
Exec=$HOME/bin/fakefox --new-window %U
X
cat >| $HOME/.local/share/applications/secret.desktop <<X
[Desktop Entry]
Type=Application
Name=Hidden Helper
NoDisplay=true
Exec=$HOME/bin/fakefox hidden
X
cat >| $HOME/.local/share/applications/link.desktop <<X
[Desktop Entry]
Type=Link
Name=Just A Link
URL=https://example.com
X

lotus_os_apps
check_has "the app is in the list" "${(k)LOTUS_APPS}" "Fire Fox Browser"
check "an entry with NoDisplay is not" eval '(( ! ${+LOTUS_APPS[Hidden Helper]} ))'
check "a link is not an app" eval '(( ! ${+LOTUS_APPS[Just A Link]} ))'

out=$(lotus app "fire fox" 2>&1 | plain)
check_has "it opens by its name" "$out" "Opening Fire Fox Browser"
for i in {1..30}; do [[ -s $HOME/launched ]] && break; sleep 0.1; done
check "and the program started" test -s $HOME/launched
check_has "with its own arguments" "$(<$HOME/launched)" "--new-window"
check "the field code %U is gone" eval '[[ $(<$HOME/launched) != *%U* ]]'
rm -f $HOME/launched
out=$(lotus app "firfox browsr" 2>&1 | plain)
check_has "typos are fine" "$out" "Opening Fire Fox Browser"
out=$(lotus app "qqqzzzxxx" 2>&1 | plain); rc=$?
check_has "an app that is not there: said so" "$out" 'No app found for "qqqzzzxxx"'
out=$(lotus app 2>&1 | plain)
check_has "no name: asked for" "$out" "Which app?"
