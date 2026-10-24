# The progress screen (lib/bg/progress.zsh): real progress in bytes or in pieces (bg_ui_count, used by plugins
# such as SLESTO: "12 / 80 segments"), and every new stage starts without the last one's numbers.
source $LOTUS_ROOT/lib/core.zsh
source $LOTUS_ROOT/lib/ui.zsh
lotus_load
source $LOTUS_ROOT/lib/bg/progress.zsh
bg_ui_begin Test "one|The first step|One" "two|The second step|Two" 2>/dev/null
frame() {   # one frame as plain text (the screen is drawn as if it were live, 80 × 24)
  BGU_LIVE=1 COLUMNS=80 LINES=24
  REPLY=$(bg_ui_frame 2>/dev/null)
  REPLY=${REPLY//$'\e'\[[0-9;?]#[A-Za-z]/}
  BGU_LIVE=0
}

bg_ui_stage one 2>/dev/null
bg_ui_count 12 80 segments
check_eq "a count keeps its unit" "$BGU_DONE $BGU_TOTAL $BGU_UNIT" "12 80 segments"
frame
check_has "the bar says how many of what" "$REPLY" "15% · 12 / 80 segments"
bg_ui_note "Nova"
frame
check_has "the note comes after it" "$REPLY" "12 / 80 segments · Nova"
bg_ui_count 3 4
check_eq "without a unit: done" "$BGU_UNIT" done

bg_ui_progress $(( 5 * 1048576 )) $(( 20 * 1048576 ))
check_eq "bytes have no unit" "$BGU_UNIT" ""
bg_ui_note ""
frame
check_has "bytes are shown in MB as before" "$REPLY" "25% · 5 / 20 MB"

bg_ui_count 7 9 files
bg_ui_stage two 2>/dev/null
check_eq "a new stage starts without numbers" "$BGU_DONE $BGU_TOTAL $BGU_UNIT" "0 0 "
bg_ui_end 2>/dev/null
