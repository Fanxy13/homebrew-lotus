# Your own themes: lotus themes add (the line the Theme Studio on the website writes), remove,
# and that Lotus uses them at once
source $LOTUS_ROOT/lib/core.zsh
source $LOTUS_ROOT/lib/ui.zsh
lotus_load
source $LOTUS_ROOT/lib/cmd/help.zsh
LOTUS_COLORS=truecolor; lotus_colors
own=$LOTUS_CONF/themes.tsv

out=$(lotus_theme_add 'Sunrise Bay' ff8800 '#00aaff' 255,255,255 '10;20;30' 112233 445566 778899 aabbcc 2>&1)
check_has "add: says it" "$out" "Theme: Sunrise Bay"
check_eq "add: one line in your themes file" "$(<$own)" $'sunrise-bay\tSunrise Bay\t255;136;0\t0;170;255\t255;255;255\t10;20;30\t17;34;51\t68;85;102\t119;136;153\t170;187;204'
lotus_load
check_eq "add: it is the theme now" $LOTUS_THEME sunrise-bay
check_eq "add: Lotus paints with it" "$LOTUS_C[logo]" "38;2;255;136;0"
check "add: in the list of themes (settings, /lotus themes)" eval '(( ${LOTUS_THEME_NAMES[(Ie)sunrise-bay]} ))'
check_eq "add: with its name as typed" "$LOTUS_THEME_LABELS[sunrise-bay]" "Sunrise Bay"

lotus_theme_add 'Sunrise Bay' 000000 000000 000000 000000 000000 000000 000000 000000 >/dev/null 2>&1
check_eq "the same name again: replaced, not twice" "$(grep -c sunrise-bay $own)" 1
lotus_load
check_eq "…and a running shell sees the new colors" "$LOTUS_C[logo]" "38;2;0;0;0"

out=$(lotus_theme_add Matcha ff8800 ff8800 ff8800 ff8800 ff8800 ff8800 ff8800 ff8800 2>&1)
check_has "a built-in name is refused" "$out" "built-in theme"
out=$(lotus_theme_add Nope ff8800 ff8800 2>&1)
check_has "too few colors: says how" "$out" "8 colors"
out=$(lotus_theme_add Nope ff8800 ff8800 ff8800 ff8800 ff8800 ff8800 ff8800 orange 2>&1)
check_has "not a color: says which" "$out" "orange"
check "refused themes leave nothing behind" eval '! grep -q -i nope $own'

print -r -- $'matcha\tFake\t1;1;1\t1;1;1\t1;1;1\t1;1;1\t1;1;1\t1;1;1\t1;1;1\t1;1;1' >> $own
LOTUS_THEME=matcha; lotus_load
check "a built-in theme is never replaced from the file" eval '[[ $LOTUS_THEME_LABELS[matcha] == Matcha ]]'

LOTUS_THEME=sunrise-bay; lotus_save quiet
out=$(lotus_theme_remove 'sunrise bay' 2>&1)
check_has "remove: by its name, in any case" "$out" "Removed: Sunrise Bay"
lotus_load
check_eq "remove: back to Matcha when it was the theme" $LOTUS_THEME matcha
check "remove: gone from the list" eval '! (( ${LOTUS_THEME_NAMES[(Ie)sunrise-bay]} ))'
lotus_theme_add 'Night Sea' 9ab8ff 5ad1c8 8fe3da f0a6ff ffd6a5 7a8aa0 66748a 1ed760 >/dev/null 2>&1
out=$(lotus_theme_remove night sea 2>&1)
check_has "remove: the name as several words" "$out" "Removed: Night Sea"
out=$(lotus_theme_remove Ghost 2>&1)
check_has "remove: a theme that is not there" "$out" "No own theme called Ghost"
