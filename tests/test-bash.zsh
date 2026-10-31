# bash: lib/init.bash – the settings zsh hands over (lotus bash-init), the lines in ~/.bashrc, and a real bash in a pseudo
# terminal: Enter rewrites /commands, the history keeps what was typed, the prompt takes the theme's color.
source $LOTUS_ROOT/lib/core.zsh
source $LOTUS_ROOT/lib/ui.zsh
lotus_load
lotus() { $LOTUS_ROOT/bin/lotus "$@" }
plain() { sed $'s/\e\\[[0-9;?]*[a-zA-Z]//g' | tr -d '\r' }

# a Lotus that is set up, with a shortcut /ck (it runs /caffeine) and the prompt in the theme's color
LOTUS_CONFIGURED=1 LOTUS_STARTUP=0 LOTUS_PROMPT=1
LOTUS_SHORTCUTS[ck]="lotus|/caffeine|on"
lotus_save quiet
lotus_load

# ── what zsh says to bash ──
code=$(lotus bash-init)
check_has "bash-init: the start screen setting" "$code" "__LOTUS_STARTUP=0"
check_has "bash-init: the prompt color" "$code" "__LOTUS_ACCENT='38;"
check_has "bash-init: the commands of Lotus" "$code" "[/weather]='weather'"
check_has "bash-init: /lotus alone shows the start screen" "$code" "[/lotus]=''"
check_has "bash-init: your shortcuts" "$code" "[/ck]='run ck'"
check "bash-init: it is valid bash" bash -n <(print -r -- "$code")

# ── the lines in the startup files ──
LOTUS_RC=$HOME/.zshrc LOTUS_RC_BASH=$HOME/.bashrc
source $LOTUS_ROOT/lib/cmd/system.zsh
LOTUS_SHELLS=bash
lotus_hook >/dev/null 2>&1
check_has "bash: the block is in ~/.bashrc" "$(<$HOME/.bashrc)" "lib/init.bash"
check "bash only: ~/.zshrc was not touched" test ! -e $HOME/.zshrc
LOTUS_SHELLS="zsh bash"
lotus_hook >/dev/null 2>&1
check_has "both: ~/.zshrc has its block" "$(<$HOME/.zshrc)" "lib/init.zsh"
check_eq "both: ~/.bashrc has its block once" "$(grep -c '# >>> lotus >>>' $HOME/.bashrc)" 1
lotus_unhook >/dev/null 2>&1
check "unhook: gone from ~/.bashrc" eval '[[ $(<$HOME/.bashrc) != *lotus* ]]'
check "unhook: gone from ~/.zshrc" eval '[[ $(<$HOME/.zshrc) != *lotus* ]]'
LOTUS_SHELLS=
SHELL=/bin/bash lotus_shells; check_eq "no choice made: the login shell (bash)" "$reply" "bash"
SHELL=/usr/bin/fish lotus_shells; check_eq "no choice made, an unknown shell: zsh, the engine" "$reply" "zsh"
LOTUS_SHELLS="fish zsh zsh"; lotus_save quiet; lotus_load; check_eq "only zsh and bash are kept, each once" "$LOTUS_SHELLS" "zsh"

# ── a real bash ──
if ! (( $+commands[bash] )); then print -r -- "  - bash is not installed – skipped"; return 0; fi
typeset -i bv=$(bash -c 'echo $((BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1]))')
if (( bv < 404 )); then print -r -- "  - this bash is older than 4.4 (READLINE_LINE, local -) – the /commands are skipped"; return 0; fi
zf_mkdir -p $HOME/.local/bin
ln -sf $LOTUS_ROOT/bin/lotus $HOME/.local/bin/lotus
print -r -- ". $LOTUS_ROOT/lib/init.bash" >| $HOME/.bashrc
session() {   # <lines to type…> → what the terminal showed
  ( sleep 2; local l; for l in "$@"; do print -rn -- "$l"$'\r'; sleep 1; done; print -rn -- $'exit\r'; sleep 0.5 ) |
    PATH=$HOME/.local/bin:$PATH tpty bash -i 2>&1 | plain
}
zf_mkdir -p $HOME/glob && : >| $HOME/glob/a.txt && : >| $HOME/glob/b.txt
cd $HOME/glob
want=$(lotus version)
ckline=$(lotus caffeine status 2>&1 | plain | grep -v '^[[:space:]]*$' | head -1)
ckline=${ckline##[[:space:]]#}
out=$(session 'lotus version' '/caffeine status' '/nosuchword abc' 'echo PS1=[$PS1] FLAGS=[$-]' 'echo ok-after')
check_has "bash: the lotus command runs" "$out" "$want"
check_has "bash: /caffeine status ran lotus caffeine status" "$out" "$ckline"
check_has "bash: an unknown /word gets a suggestion" "$out" "Command not found"
check_has "bash: the prompt has the theme's color" "$out" 'PS1=[\[\e[38;'
flags=$(print -r -- "$out" | grep -o 'FLAGS=\[[a-zA-Z]*\]' | tail -1)
check "bash: pathname expansion is on again after a rewritten line" eval '[[ -n $flags && $flags != *f* ]]'
check_has "bash: and the shell goes on" "$out" "ok-after"
# what was typed is in the history – not the line that was made of it
hist=$(<$HOME/.bash_history)
check_has "bash: the history keeps what was typed" "$hist" "/caffeine status"
check "bash: and not the rewritten line" eval '[[ $hist != *"lotus caffeine status"* ]]'
check_has "bash: unknown words too" "$hist" "/nosuchword abc"
