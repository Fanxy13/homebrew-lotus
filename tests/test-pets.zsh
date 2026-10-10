# Pets: a reaction draws the whole pet – not only the row with its eyes (2.7 regression)
source $LOTUS_ROOT/lib/core.zsh
lotus_load
zf_mkdir -p $LOTUS_CONF
print -r -- $'Mochi\tcat\t\t'$EPOCHSECONDS >| $LOTUS_CONF/pets.tsv
source $LOTUS_ROOT/lib/cmd/pets.zsh

# the cat's drawing from its pet file
cat_rows=("${(@f)$(sed -n '/^\[idle\]/,/^\[/p' $LOTUS_ROOT/data/pets/cat.pet | sed '1d;$d')}")
strip() { print -r -- "${1//$'\e'\[[0-9;]#m/}" }

COLUMNS=100
out=$(strip "$(lotus_pet_react_now typo)")
for row in $cat_rows; do check_has "typo: drawing row '${row## #}'" "$out" "${row%% #}"; done
check_has "typo: the pet's name under the drawing" "$out" "Mochi"
check_has "typo: what happened" "$out" "tilts its head"
lines=("${(@f)out}")
check "typo: more than the row with the eyes" test ${#lines} -ge $(( ${#cat_rows} + 1 ))

out=$(strip "$(lotus_pet_react_now done)")
check_has "done: a speech bubble" "$out" "╭"
lines=("${(@f)out}")
check "done: the whole drawing" test ${#lines} -ge $(( ${#cat_rows} + 1 ))

COLUMNS=24
out=$(strip "$(lotus_pet_react_now typo)")
lines=("${(@f)out}")
check_eq "narrow window: one line with the name, no half drawing" "${#lines}" 1
check_has "narrow window: the name" "$out" "Mochi:"
