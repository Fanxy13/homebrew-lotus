# Downloads for lotus ai local: the progress line counts what came over the network, not only what is on
# disk – Hugging Face's Xet storage writes the files in blocks, so the folder alone grows in jumps and a
# speed taken from it shoots up and falls to zero again and again.
# A stand-in for lib/ai/download.py (no network): it reports 10 MB received every half second and
# writes the model only at the end, the way Xet does.
source $LOTUS_ROOT/lib/core.zsh
source $LOTUS_ROOT/lib/ui.zsh
lotus_load

zf_mkdir -p $HOME/rt/bin
cat >| $HOME/rt/bin/python <<'EOF'
#!/bin/zsh
# python download.py <repo> <revision> <folder> <progress file>
dir=$4 prog=$5
mkdir -p $dir
for i in {1..8}; do print "$(( i * 10000000 )) 0" >| $prog; sleep 0.5; done
print '{}' >| $dir/config.json
head -c 80000000 /dev/zero >| $dir/model.safetensors
print "80000000 80000000" >| $prog
EOF
chmod +x $HOME/rt/bin/python

cat >| $HOME/run.zsh <<EOF
setopt extendedglob
source $LOTUS_ROOT/lib/core.zsh; source $LOTUS_ROOT/lib/ui.zsh; lotus_load; source $LOTUS_ROOT/lib/cmd/ai.zsh
zmodload zsh/zselect
LLM_RUNTIME=$HOME/rt LLM_MODELS=$HOME/models
_llm_token() { return 1 }
curl() { return 1 }       # no network: the size comes from the catalog
_llm_fetch test/model main test-model "Test model" 0.08
print "rc=\$?"
EOF
script -q $HOME/screen.txt zsh $HOME/run.zsh </dev/null >/dev/null 2>&1
screen=$(sed $'s/\e\\[[0-9;?]*[a-zA-Z]//g' $HOME/screen.txt | tr '\r' '\n')
speeds=(${(f)"$(print -r -- $screen | grep -oE '[0-9]+ MB/s' | grep -oE '^[0-9]+')"})
check_has "the download finishes" "$screen" "rc=0"
check_has "at 100 %" "$screen" "100 %"
check "the model is there" test -r $HOME/models/test-model/config.json
check "a speed is shown while nothing is written yet" eval '(( ${#speeds} >= 2 ))'
check "the speed is what comes in – about 20 MB/s – and does not jump" eval '(( ${speeds[(I)<0-9>]} == 0 && ${speeds[(I)<31->]} == 0 ))'
