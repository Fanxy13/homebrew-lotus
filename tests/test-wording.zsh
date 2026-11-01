# The texts were written on a Mac. On another system "this Mac" and "Finder" become what that system calls them –
# in every language, in the UI functions and in the texts of the languages (LOTUS_L).
source $LOTUS_ROOT/lib/core.zsh
source $LOTUS_ROOT/lib/ui.zsh
lotus_load
plain() { sed $'s/\e\\[[0-9;?]*[a-zA-Z]//g' }

out=$(ui_text "Works on this Mac, shown in Finder" | plain)
info=$(ui_info "Let your Mac sleep" | plain)
err=$(ui_error "Not on this Mac" "the Mac says no" "in Finder" 2>&1 | plain)
if [[ $LOTUS_OS == macos ]]; then
  check_has "a Mac: the text stays" "$out" "Works on this Mac, shown in Finder"
  check_has "a Mac: ui_info too" "$info" "Let your Mac sleep"
else
  check_has "elsewhere: this Mac is this computer" "$out" "Works on this computer"
  check_has "elsewhere: Finder is the file manager" "$out" "shown in the file manager"
  check_has "elsewhere: your Mac is your computer" "$info" "Let your computer sleep"
  check "elsewhere: no Mac left in an error" eval '[[ $err != *Mac* && $err != *Finder* ]]'
fi

# the texts of the languages (LOTUS_L): the English one of the keep-awake question, the German one of its answer
LOTUS_LANG=en; lotus_lang
if [[ $LOTUS_OS == macos ]]; then check_has "a Mac: the English text" "$LOTUS_L[caf_stop_q]" "your Mac"
else check_has "elsewhere: the English text" "$LOTUS_L[caf_stop_q]" "your computer"; fi
LOTUS_LANG=de; lotus_lang
if [[ $LOTUS_OS == macos ]]; then check_has "a Mac: the German text" "$LOTUS_L[caf_on]" "Dein Mac"
else check_has "elsewhere: the German text" "$LOTUS_L[caf_on]" "Dein Computer"; fi
# a text in a group of its own is changed the same way
lotus_lang_group bg
LOTUS_LANG=en; lotus_lang; lotus_lang_group bg
check "no text of the bg group names the Mac elsewhere" eval '[[ $LOTUS_OS == macos || ${(j: :)${(v)LOTUS_L}} != *"this Mac"* ]]'
