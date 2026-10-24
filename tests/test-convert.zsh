# /convert: when yt-dlp cannot read a link, Lotus says why (in yt-dlp's words), tries once more by
# itself and offers a newer yt-dlp when the site changed – a fake yt-dlp plays the failures
source $LOTUS_ROOT/lib/core.zsh
source $LOTUS_ROOT/lib/ui.zsh
lotus_load
source $LOTUS_ROOT/lib/cmd/convert.zsh
ui_has_tty() { false }      # never ask (the tests may run in a terminal)
LOTUS_CONVERT_PAUSE=0
zf_mkdir -p $HOME/bin $LOTUS_CACHE
# The fake: FAILS = how many calls fail, with the message in WHY; then it prints the file name
cat > $HOME/bin/yt-dlp <<'FAKE'
#!/bin/zsh
[[ $1 == --version ]] && { print 2026.08.19; exit 0 }
n=$(( $(cat $HOME/calls 2>/dev/null || print 0) + 1 )); print $n > $HOME/calls
if (( n <= ${FAILS:-0} )); then print -u2 -- "WARNING: [youtube] something"; print -u2 -- "ERROR: $WHY"; exit 1; fi
print -- "$HOME/Downloads/Song.webm"
FAKE
chmod +x $HOME/bin/yt-dlp
path=($HOME/bin $path); rehash
errs=$LOTUS_CACHE/convert-errors.txt
probe() {   # <fails> <message> → REPLY, out (what the user sees), status
  print 0 >| $HOME/calls
  FAILS=$1 WHY=$2
  export FAILS WHY
  out=$(lotus_convert_probe $errs https://youtu.be/abc '%(title)s.%(ext)s' -x 2>&1; print "status=$? file=$REPLY")
  calls=$(<$HOME/calls)
}

probe 0 ""
check_has "it works: the file name" "$out" "status=0 file=$HOME/Downloads/Song.webm"
check_eq "it works: one look" $calls 1

probe 1 "[youtube] abc: Unable to download webpage: <urlopen error [Errno 8] nodename nor servname provided>"
check_has "fails once: tried again by itself" "$out" "status=0 file=$HOME/Downloads/Song.webm"
check_eq "fails once: two looks" $calls 2
check_has "fails once: yt-dlp's reason on screen" "$out" "nodename nor servname provided"
check_has "fails once: the reason in the log" "$(<$LOTUS_STATE/lotus.log)" "yt-dlp failed (check, try 1, other): [youtube] abc: Unable to download webpage"

probe 5 "something new went wrong"
check_has "fails twice: stops" "$out" "status=1"
check_eq "fails twice: no third look" $calls 2
check_has "fails twice: says so" "$out" "yt-dlp cannot read this link"
check_has "fails twice: in yt-dlp's words, not a guess" "$out" "something new went wrong"

probe 5 "[youtube] abc: Private video. Sign in if you've been granted access to this video"
check_has "a private video: stops at once" "$out" "status=1"
check_eq "a private video: no second look" $calls 1
check_has "a private video: says what it is" "$out" "private, removed, age-restricted or not available here"

probe 5 "[youtube] abc: This video is unavailable"
check_eq "a video that is gone: no second look" $calls 1

probe 5 "[youtube] abc: Sign in to confirm you're not a bot"
check_has "YouTube refuses: a newer yt-dlp is suggested" "$out" "yt-dlp needs updates to keep up"
check_has "YouTube refuses: with its version and age" "$out" "Your yt-dlp: 2026.08.19"
check_eq "YouTube refuses: still tried once more" $calls 2

probe 5 "Unsupported URL: https://example.com/x"
check_has "a site yt-dlp does not know" "$out" "yt-dlp does not know this site"

# a download that fails is explained the same way (yt-dlp's messages are on screen already)
print -r -- "ERROR: [youtube] abc: HTTP Error 429: Too Many Requests" >| $errs
out=$(lotus_convert_failed $errs 2 download 2>&1; print "status=$?")
check_has "download: stops after the second try" "$out" "status=1"
check_has "download: the right title" "$out" "The download did not finish"
check_has "download: in yt-dlp's words" "$out" "HTTP Error 429: Too Many Requests"

# ── Keeping yt-dlp up to date: asked only when a newer one is a month ahead, not again for a week ──
print -r -- 2026.10.21 >| $LOTUS_CACHE/ytdlp-latest          # the newest, as if from GitHub today
lotus_ytdlp_behind
check_eq "behind: days to the newest" "$REPLY" 63
check_eq "behind: yours and the newest" "$reply[1] $reply[2]" "2026.08.19 2026.10.21"
rm -f $LOTUS_STATE/ytdlp-asked
out=$(lotus_ytdlp_check 2>&1)
check_has "two months behind: a newer one is offered" "$out" "A newer yt-dlp is out: 2026.10.21"
out=$(ui_has_tty() { true }; ui_confirm() { false }; lotus_ytdlp_check 2>&1)
check_has "a no: it says when it asks again" "$out" "asks again in 7 days"
check "and keeps a week of quiet" test -s $LOTUS_STATE/ytdlp-asked
out=$(ui_has_tty() { true }; lotus_ytdlp_check 2>&1)
check_eq "the next /convert: no question again" "$out" ""
rm -f $LOTUS_STATE/ytdlp-asked
print -r -- 2026.08.19 >| $LOTUS_CACHE/ytdlp-latest
out=$(lotus_ytdlp_check 2>&1)
check_eq "the newest, however old: nothing to offer" "$out" ""
print -r -- 2026.09.01 >| $LOTUS_CACHE/ytdlp-latest
out=$(lotus_ytdlp_check 2>&1)
check_eq "less than a month behind: not asked" "$out" ""

# another macOS user's yt-dlp (their Homebrew): Lotus says so and offers its own, never sudo
chmod 555 $HOME/bin
lotus_ytdlp_info
check_eq "a folder this user cannot change: whose it is" "$reply[3]" "$USER"
out=$(lotus_ytdlp_update 2>&1; print "status=$?")
check_has "cannot update it: says why" "$out" "is in a folder of the macOS user $USER"
check_has "and what Lotus can do instead" "$out" "the official macOS build from github.com/yt-dlp"
check_has "without a keyboard: nothing done" "$out" "status=1"
chmod 755 $HOME/bin
# Lotus' own copy wins once it is there
zf_mkdir -p ${LOTUS_YTDLP_OWN:h}
print -l '#!/bin/zsh' 'print 2026.10.21' >| $LOTUS_YTDLP_OWN; chmod 755 $LOTUS_YTDLP_OWN
lotus_ytdlp_info
check_eq "Lotus' own yt-dlp is the one used" "$reply[1] $reply[2]" "2026.10.21 lotus"
rm -f $LOTUS_YTDLP_OWN

# ── The download while the lotus blooms: yt-dlp's progress drives it, its other lines explain failures ──
cat > $HOME/bin/yt-dlp <<'FAKE'
#!/bin/zsh
[[ $1 == --version ]] && { print 2026.10.21; exit 0 }
print "LOTUS 1024 4096 2048.5 2 avc1.4d401e"
print "LOTUS 4096 4096 2048.5 0 avc1.4d401e"
print "LOTUS 2048 2048 1024 0 none"
print "LOTUS-PP started Merger"
print "LOTUS-PP finished Merger"
print -u2 "WARNING: [youtube] a warning yt-dlp gave"
print "$HOME/Downloads/Lotus/Clip.mp4"
exit ${FAKE_RC:-0}
FAKE
chmod 755 $HOME/bin/yt-dlp; rehash
zf_mkdir -p $HOME/Downloads/Lotus; : >| $HOME/Downloads/Lotus/Clip.mp4
source $LOTUS_ROOT/lib/bg/progress.zsh
lotus_lang_group bg
bg_ui_begin Convert "video|Downloading the video|Video" "audio|Downloading the sound|Sound" "merge|Putting it together|MP4" 2>/dev/null
out=$(lotus_convert_live $errs https://youtu.be/abc '%(title)s.%(ext)s' mp4 2>&1; print "status=$? file=$LOTUS_CONVERT_FILE")
check_has "the steps follow yt-dlp: the video" "$out" "Downloading the video"
check_has "then the sound" "$out" "Downloading the sound"
check_has "then putting it together" "$out" "Putting it together"
check_has "where the file ended up" "$out" "status=0 file=$HOME/Downloads/Lotus/Clip.mp4"
check_has "yt-dlp's other lines are kept for an explanation" "$(<$errs)" "a warning yt-dlp gave"
out=$(FAKE_RC=1 lotus_convert_live $errs https://youtu.be/abc '%(title)s.%(ext)s' mp4 2>&1; print "status=$?")
check_has "yt-dlp fails: so does the download" "$out" "status=1"
bg_ui_end
