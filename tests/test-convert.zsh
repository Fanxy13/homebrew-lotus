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
