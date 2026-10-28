# lotus – /convert: save a video as MP3 or MP4 with yt-dlp and ffmpeg – while the lotus blooms.
# Only for content you have the right to download. Lotus does not bypass DRM,
# paywalls, logins or private content – yt-dlp is used with its default behavior.

typeset -g LOTUS_DOWNLOADS=${LOTUS_DOWNLOADS:-~/Downloads/Lotus}
typeset -g LOTUS_LOG_COMP=convert
typeset -gi LOTUS_YTDLP_OLD=30    # days behind the newest yt-dlp – then /convert offers it (sites change often)
typeset -gi LOTUS_YTDLP_QUIET=7   # days without asking again after a "no" or an update that could not be done
typeset -gi LOTUS_CONVERT_PAUSE=2 # seconds before the second try – YouTube often fails once and then works
# Lotus' own yt-dlp – made when the one on this Mac cannot be updated (Homebrew of another macOS user)
typeset -g LOTUS_YTDLP_OWN=$LOTUS_DATA/runtime/yt-dlp/yt-dlp
typeset -g LOTUS_CONVERT_TITLE= LOTUS_CONVERT_LEN= LOTUS_CONVERT_FILE= LOTUS_CONVERT_WARN=
typeset -gi LOTUS_CONVERT_STOP=0 LOTUS_CONVERT_PID=0

lotus_cmd_convert() {
  shift
  source $LOTUS_ROOT/lib/cmd/web.zsh
  local link=$1
  ui_header Convert "MP3 or MP4"
  if [[ -z $link ]]; then
    ui_input "Link" || return 1
    link=$REPLY
  fi
  if ! lotus_as_url "$link"; then
    ui_error "That is not a valid link" "$link" "Example: /convert https://www.youtube.com/watch?v=…"
    return 1
  fi
  link=$REPLY
  lotus_convert_deps || return 1
  lotus_ytdlp_check

  ui_dim "Only download videos you have the right to save (your own, licensed or free to use)."
  ui_dim "Lotus does not bypass DRM, paywalls or private videos."
  ui_blank
  ui_choose "What do you want?" "MP3 – audio only" "MP4 – video" || return 0
  local -i want=$REPLY
  local -a args=(--no-playlist)
  local tpl="$LOTUS_DOWNLOADS/%(title).150B.%(ext)s"
  local fps= ext=mp3 quality="best quality"

  if (( want == 1 )); then
    args+=(-x --audio-format mp3 --audio-quality 0)
  else
    ext=mp4
    local -a res=(360 480 720 1080 best)
    ui_choose "Resolution" 360p 480p 720p 1080p "Best available" || return 0
    local h=$res[REPLY]
    if [[ $h == best ]]; then
      args+=(-f 'bv*[ext=mp4]+ba[ext=m4a]/bv*+ba/b')
      quality="best resolution"
    else
      # the last "/b" covers plain video files without size information
      args+=(-f "bv*[height<=$h][ext=mp4]+ba[ext=m4a]/bv*[height<=$h]+ba/b[height<=$h]/b")
      quality=${h}p
    fi
    args+=(--merge-output-format mp4 --remux-video mp4)
    local -a fpss=(source 24 30 60)
    ui_choose "Frames per second" "Keep the original" "24 FPS" "30 FPS" "60 FPS" || return 0
    fps=${fpss[REPLY]:#source}
    [[ -n $fps ]] && { quality+=" · $fps FPS"; ui_dim "Changing the frame rate re-encodes the video, which takes a while." }
  fi

  zf_mkdir -p $LOTUS_DOWNLOADS $LOTUS_CACHE
  # yt-dlp's own messages are kept: when something fails, they say why
  local errs=$LOTUS_CACHE/convert-errors.txt
  lotus_convert_probe $errs "$link" "$tpl" $args || return 1
  local file=${REPLY:r}.$ext
  if [[ -e $file ]]; then
    ui_choose "${file:t} already exists" "Keep both (new name)" "Replace it" "Cancel" || return 0
    case $REPLY in
      1) local base=${file:r} n=2
         while [[ -e "$base ($n).$ext" ]]; do (( n++ )); done
         tpl="${base//\%/%%} ($n).%(ext)s"; file="$base ($n).$ext" ;;
      2) args+=(--force-overwrites) ;;
      3) return 0 ;;
    esac
  fi

  lotus_convert_download $errs "$link" "$tpl" $ext "$fps" "$quality" $args || return 1
  [[ -e $LOTUS_CONVERT_FILE ]] && file=$LOTUS_CONVERT_FILE
  [[ -n $LOTUS_CONVERT_WARN ]] && ui_warn "$LOTUS_CONVERT_WARN"
  local -a st
  local size=
  if zstat -A st +size -- "$file" 2>/dev/null; then
    if (( st[1] < 1048576 )); then size="$(( (st[1] + 512) / 1024 )) KB"; else printf -v size '%.1f MB' $(( st[1] / 1048576.0 )); fi
  fi
  ui_success "Done: ${file/#$HOME/~}${size:+  ($size)}"
  lotus_pet_react done
  ui_confirm "Show it in Finder?" y && open -R "$file"
}

# yt-dlp: Lotus' own copy when there is one, else the one on the PATH
_ytdlp() { if [[ -x $LOTUS_YTDLP_OWN ]]; then "$LOTUS_YTDLP_OWN" "$@"; else command yt-dlp "$@"; fi }

# ── The download, while the lotus blooms ──────────────────────

# The steps on the progress screen (lib/bg/progress.zsh) in the theme's colors, with the video's title on top and
# what it becomes, how long it is and how fast it comes below. A failed try is explained (lotus_convert_failed) and
# tried once more. → LOTUS_CONVERT_FILE (where it is), status 1 = failed or stopped (ctrl-c)
lotus_convert_download() {   # <errs> <link> <template> <mp3|mp4> <fps or ""> <quality> <yt-dlp arguments…>
  local errs=$1 link=$2 tpl=$3 ext=$4 fps=$5 quality=$6
  shift 6
  setopt localoptions localtraps
  source $LOTUS_ROOT/lib/bg/progress.zsh
  lotus_lang_group bg
  # ctrl-c: the trap only sets the flag and ends yt-dlp (kill is built in) – the loop cleans up
  trap 'LOTUS_CONVERT_STOP=1; (( LOTUS_CONVERT_PID )) && kill -TERM $LOTUS_CONVERT_PID 2>/dev/null' INT
  _bg_cancel() { LOTUS_CONVERT_STOP=1 BG_CANCEL=0 }
  local -a stages
  if [[ $ext == mp3 ]]; then
    stages=("sound|Downloading the sound|Sound" "mp3|Making the MP3|MP3")
  else
    stages=("video|Downloading the video|Video" "audio|Downloading the sound|Sound" "merge|Putting it together|MP4")
    [[ -n $fps ]] && stages+=("fps|Converting to $fps FPS|$fps FPS")
  fi
  local -i try=1 rc
  LOTUS_CONVERT_WARN=
  while :; do
    LOTUS_CONVERT_STOP=0 BG_CANCEL=0
    bg_ui_begin Convert $stages
    bg_ui_sub "$LOTUS_CONVERT_TITLE"
    bg_ui_info format "${(U)ext} · $quality"
    [[ -n $LOTUS_CONVERT_LEN ]] && bg_ui_info length "$LOTUS_CONVERT_LEN"
    bg_ui_info site "${${${link#*://}#www.}%%/*}"
    # until yt-dlp's first bytes: the first step, and who is being asked
    bg_ui_stage ${stages[1]%%|*}
    bg_ui_note "Asking ${${${link#*://}#www.}%%/*} for it …"
    lotus_convert_live $errs "$link" "$tpl" $ext "$@"; rc=$?
    if (( rc == 0 && ! LOTUS_CONVERT_STOP )); then
      [[ $ext == mp4 && -e $LOTUS_CONVERT_FILE ]] && lotus_convert_finish "$LOTUS_CONVERT_FILE" "$fps"
      if (( ! LOTUS_CONVERT_STOP )); then bg_ui_complete; bg_ui_end; return 0; fi
    fi
    bg_ui_end
    if (( LOTUS_CONVERT_STOP )); then
      lotus_log INFO convert "Stopped"
      ui_info "Stopped – yt-dlp picks up where it was the next time."
      return 1
    fi
    lotus_convert_failed $errs $try download || return 1
    (( try++ ))
  done
}

# yt-dlp with its progress for the lotus: bytes, speed and time left move the bar, whether a video or a sound
# stream is coming picks the step, its other lines go to <errs> → LOTUS_CONVERT_FILE, status = yt-dlp's
lotus_convert_live() {   # <errs> <link> <template> <mp3|mp4> <yt-dlp arguments…>
  local errs=$1 link=$2 tpl=$3 ext=$4 line note
  shift 4
  local -a w
  local -i fd rc=1 more
  : >| $errs
  LOTUS_CONVERT_FILE= LOTUS_CONVERT_PID=0 _BG_BUF=
  exec {fd}< <(
    _ytdlp --no-update "$@" --newline --progress \
      --progress-template 'download:LOTUS %(progress.downloaded_bytes)s %(progress.total_bytes,progress.total_bytes_estimate)s %(progress.speed)s %(progress.eta)s %(info.vcodec)s' \
      --progress-template 'postprocess:LOTUS-PP %(progress.status)s %(progress.postprocessor)s' \
      --print after_move:filepath -o "$tpl" -- "$link" 2>&1 </dev/null &
    print -r -- "LOTUS-PID $!"
    wait $!
    print -r -- "LOTUS-EXIT $?"
  )
  while :; do
    bg_read_lines $fd 0.08; more=$?
    for line in $reply; do
      case $line in
        "LOTUS-PID "<->)  LOTUS_CONVERT_PID=${line#* } ;;
        "LOTUS-EXIT "<->) rc=${line#* } ;;
        "LOTUS "*)
          w=(${=line})
          if [[ $ext == mp3 ]]; then bg_ui_stage sound
          elif [[ $w[6] == none ]]; then bg_ui_stage audio
          else bg_ui_stage video; fi
          [[ $w[2] == <-> && $w[3] == <-> ]] && (( w[3] > 0 )) && bg_ui_progress $w[2] $w[3]
          note=
          [[ $w[4] == <->(|.<->) ]] && printf -v note '%.1f MB/s' $(( w[4] / 1048576.0 ))
          if [[ $w[5] == <-> ]] && (( w[5] > 0 )); then
            printf -v REPLY '%d:%02d left' $(( w[5] / 60 )) $(( w[5] % 60 ))
            note+="${note:+ · }$REPLY"
          fi
          bg_ui_note "$note" ;;
        "LOTUS-PP started "*)
          case $line in
            *ExtractAudio*)                          bg_ui_stage mp3 ;;
            *(Merger|VideoRemuxer|VideoConvertor)*)  bg_ui_stage merge ;;
          esac
          bg_ui_progress 0 0; bg_ui_note "" ;;
        "LOTUS-PP "*) ;;
        /*) [[ -e $line ]] && LOTUS_CONVERT_FILE=$line ;;    # where it ended up
        *) [[ -n ${line//[[:space:]]/} ]] && print -r -- "$line" >> $errs ;;
      esac
    done
    bg_ui_frame
    (( more == 0 && ! LOTUS_CONVERT_STOP )) || break
  done
  if (( LOTUS_CONVERT_STOP && LOTUS_CONVERT_PID )); then
    pkill -TERM -P $LOTUS_CONVERT_PID 2>/dev/null       # its ffmpeg
    kill -TERM $LOTUS_CONVERT_PID 2>/dev/null
  fi
  exec {fd}<&-
  LOTUS_CONVERT_PID=0
  (( LOTUS_CONVERT_STOP )) && return 1
  return rc
}

# MP4 that plays everywhere: new frame rate if asked, AAC audio (QuickTime cannot play Opus in MP4) – a step of
# the lotus with ffmpeg's real progress. A failure keeps the downloaded video and says so (LOTUS_CONVERT_WARN).
lotus_convert_finish() {   # <file.mp4> [fps]
  local file=$1 fps=$2 line
  local acodec=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$file" 2>/dev/null)
  local -a ff=()
  [[ -n $fps ]] && ff+=(-r $fps) || ff+=(-c:v copy)
  [[ $acodec == (aac|mp3|) ]] && ff+=(-c:a copy) || ff+=(-c:a aac -b:a 192k)
  [[ -z $fps && $acodec == (aac|mp3|) ]] && return 0
  if [[ -n $fps ]]; then bg_ui_stage fps
  else bg_ui_add_stage "aac|Making the sound QuickTime-friendly|AAC"; bg_ui_stage aac; fi
  local -F secs=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$file" 2>/dev/null) frac
  local -i fd more us=0 bytes=0 rc=1
  bg_ui_progress 0 0
  exec {fd}< <(ffmpeg -hide_banner -loglevel error -nostats -progress pipe:1 -i "$file" $ff -y "${file:r}.tmp.mp4" 2>&1 </dev/null &
               print -r -- "LOTUS-PID $!"; wait $!; print -r -- "LOTUS-EXIT $?")
  _BG_BUF=
  while :; do
    bg_read_lines $fd 0.08; more=$?
    for line in $reply; do
      case $line in
        "LOTUS-PID "<->)  LOTUS_CONVERT_PID=${line#* } ;;
        "LOTUS-EXIT "<->) rc=${line#* } ;;
        out_time_us=<->)  us=${line#*=} ;;
        total_size=<->)   bytes=${line#*=} ;;
        progress=*)
          (( secs > 0 && us > 0 )) || continue
          (( frac = us / 1e6 / secs, frac > 1 ? (frac = 1) : 0 ))
          # the bytes written are real; the whole size is where they are heading at this pace
          (( frac > 0.02 && bytes > 0 )) && bg_ui_progress $bytes $(( int(bytes / frac) ))
          printf -v REPLY '%d:%02d of %d:%02d' $(( us / 60000000 )) $(( us / 1000000 % 60 )) $(( int(secs) / 60 )) $(( int(secs) % 60 ))
          bg_ui_note $REPLY ;;
      esac
    done
    bg_ui_frame
    (( more == 0 && ! LOTUS_CONVERT_STOP )) || break
  done
  (( LOTUS_CONVERT_STOP && LOTUS_CONVERT_PID )) && kill -TERM $LOTUS_CONVERT_PID 2>/dev/null
  exec {fd}<&-
  LOTUS_CONVERT_PID=0
  if (( rc == 0 && ! LOTUS_CONVERT_STOP )) && [[ -s ${file:r}.tmp.mp4 ]]; then
    zf_mv -f "${file:r}.tmp.mp4" "$file" && return 0
  fi
  rm -f "${file:r}.tmp.mp4"
  (( LOTUS_CONVERT_STOP )) && return 1
  LOTUS_CONVERT_WARN="The conversion did not work – the downloaded video was kept as it is."
  lotus_log WARN convert "ffmpeg failed on ${file:t} (status $rc)"
  return 1
}

# Asks yt-dlp what the file will be called – the first look at the video → REPLY = file name, LOTUS_CONVERT_TITLE
# and LOTUS_CONVERT_LEN for the progress screen. Its messages go to <errs> instead of the screen; when it fails
# they say why (lotus_convert_failed).
lotus_convert_probe() {   # <errs> <link> <template> <yt-dlp arguments…>
  local errs=$1 link=$2 tpl=$3 out
  shift 3
  local -i try=1
  local -a lines
  ui_step "Checking the video …"
  until out=$(_ytdlp --no-update "$@" -o "$tpl" --print '%(title)s' --print '%(duration_string)s' --print filename \
                     --skip-download -- "$link" 2>$errs); lines=("${(@f)out}"); REPLY=$lines[-1]; [[ -n $REPLY ]]; do
    lotus_convert_failed $errs $try check || return 1
    (( try++ ))
    ui_step "Checking the video again …"
  done
  LOTUS_CONVERT_TITLE= LOTUS_CONVERT_LEN=
  if (( ${#lines} >= 3 )); then
    LOTUS_CONVERT_TITLE=${lines[-3]:#NA} LOTUS_CONVERT_LEN=${lines[-2]:#NA}
    [[ $LOTUS_CONVERT_LEN == <-> ]] && printf -v LOTUS_CONVERT_LEN '0:%02d' $LOTUS_CONVERT_LEN   # 19 → 0:19
  fi
  return 0
}

# What went wrong – in yt-dlp's own words – and what helps. Status 0 = try again.
#   lotus_convert_failed <file with yt-dlp's messages> <attempt> <check|download>
# A video that is private or gone ends it. A newer yt-dlp is offered when the site changed;
# anything else (YouTube refusing once, the network) gets one more try by itself.
lotus_convert_failed() {
  local errs=$1 what=$3 why= first= kind=other
  local -i try=$2
  [[ -s $errs ]] || sleep 0.2      # the copy may still be on its way
  [[ -r $errs ]] && why=$(<$errs)
  local -a lines=("${(@f)why}")                    # an array: one line alone stays a line, not letters
  local -a errors=(${(M)lines:#ERROR:*})
  first=${errors[1]:-$lines[-1]}                     # no ERROR line: its last words
  first=${first#ERROR: }
  case $why in
    *(ideo unavailable|ideo is unavailable|rivate video|video is private|been removed|members-only|Join this channel|confirm your age|age-restricted|copyright|not available in your country|not made this video available)*) kind=gone ;;
    *(Unsupported URL)*) kind=unsupported ;;
    *(HTTP Error 403|HTTP Error 429|Sign in to confirm|not a bot|nsig extraction|n challenge|Signature extraction|Unable to extract|Precondition check failed|Requested format is not available|PO Token)*) kind=outdated ;;
  esac
  local title="The download did not finish"
  [[ $what == check ]] && title="yt-dlp cannot read this link"
  lotus_log ERROR convert "yt-dlp failed ($what, try $try, $kind): ${first:-no message}"
  case $kind in
    gone)        ui_error $title "$first" "The video is private, removed, age-restricted or not available here."; return 1 ;;
    unsupported) ui_error $title "$first" "yt-dlp does not know this site."; return 1 ;;
    outdated)
      lotus_ytdlp_info
      local -i age=${REPLY:--1}
      ui_error $title "$first" \
        "YouTube and other sites change how they deliver videos – yt-dlp needs updates to keep up." \
        "Your yt-dlp: ${reply[1]:-unknown}${${(M)age:#<0->}:+ ($age days old)}"
      if (( try == 1 )) && ui_has_tty && ui_confirm "Update yt-dlp and try again?" y; then
        lotus_ytdlp_update && return 0
      fi ;;
  esac
  if (( try == 1 )); then
    [[ $kind == outdated ]] || ui_warn "yt-dlp: ${first:-it stopped without a reason} – trying once more"
    sleep $LOTUS_CONVERT_PAUSE
    return 0
  fi
  [[ $kind == outdated ]] || ui_error $title "${first:-yt-dlp stopped without a reason.}"
  ui_dim "  If it still fails: check that the video plays in your browser, or try again later."
  ui_blank
  return 1
}

# ── Keeping yt-dlp up to date ─────────────────────────────────

# Version, age (days, in REPLY), how it was installed – brew, pipx, pip, self or lotus (Lotus' own copy) – and
# whether this macOS user can update it: reply=(version how ok|<the user it belongs to>)
lotus_ytdlp_info() {
  setopt localoptions extendedglob
  local bin how=self can=ok v dir
  local -a st
  if [[ -x $LOTUS_YTDLP_OWN ]]; then bin=$LOTUS_YTDLP_OWN how=lotus
  else bin=${commands[yt-dlp]:A}; fi
  v=$($bin --version 2>/dev/null)
  if [[ $how != lotus ]]; then
    case $bin in
      */Cellar/*|*/homebrew/*) how=brew ;;
      */pipx/*)                how=pipx ;;
      *) [[ $(head -c 2 $bin 2>/dev/null) == '#!' ]] && how=pip ;;
    esac
  fi
  # Homebrew changes its folder for yt-dlp, the others the folder the program is in
  dir=${bin:h}
  [[ $bin == */Cellar/* ]] && dir=${bin%%/Cellar/*}/Cellar/yt-dlp
  if [[ -n $bin && -e $dir && ! -w $dir ]]; then
    zstat -A st -s +uid -- $dir 2>/dev/null
    can=${st[1]:-another user}
  fi
  reply=("$v" $how "$can")
  REPLY=
  _ytdlp_epoch $v && REPLY=$(( (EPOCHSECONDS - REPLY) / 86400 ))
}

# A yt-dlp version ("2026.10.21") → REPLY = the day it came out (epoch), status 1 when it is no date
_ytdlp_epoch() {
  setopt localoptions extendedglob
  [[ $1 == (#b)(<->).(<->).(<->)* ]] || return 1
  strftime -r -s REPLY %Y-%m-%d "$match[1]-$match[2]-$match[3]" 2>/dev/null
}

# The newest yt-dlp – from its release page on GitHub, at most once a day → REPLY ("2026.10.21"), status 1 when
# it is not known (offline – then Lotus looks again in an hour)
lotus_ytdlp_latest() {
  local f=$LOTUS_CACHE/ytdlp-latest url
  local -a st
  if [[ -r $f ]] && zstat -A st +mtime -- $f 2>/dev/null; then
    REPLY=$(<$f)
    if [[ -n $REPLY ]]; then (( EPOCHSECONDS - st[1] < 86400 )) && return 0
    else (( EPOCHSECONDS - st[1] < 3600 )) && return 1; fi
  fi
  url=$(curl -fsSI -m 4 -o /dev/null -w '%{redirect_url}' https://github.com/yt-dlp/yt-dlp/releases/latest 2>/dev/null)
  REPLY=${url##*/}
  [[ $REPLY == <->.<->.<->(|.<->) ]] || REPLY=
  { zf_mkdir -p $LOTUS_CACHE && print -r -- $REPLY >| $f } 2>/dev/null
  [[ -n $REPLY ]]
}

# How far yt-dlp is behind the newest → REPLY = days (0: it is the newest), reply=(yours newest how can);
# without the newest (offline): REPLY = its own age, and the newest is empty
lotus_ytdlp_behind() {
  lotus_ytdlp_info
  local have=$reply[1] how=$reply[2] can=$reply[3] newest=
  local -i behind=${REPLY:--1} e
  if lotus_ytdlp_latest; then
    newest=$REPLY behind=0
    if [[ $newest != $have ]] && _ytdlp_epoch $newest; then
      e=$REPLY
      _ytdlp_epoch $have && (( behind = (e - REPLY) / 86400, behind < 0 ? (behind = 0) : 0 ))
    fi
  fi
  reply=("$have" "$newest" $how "$can")
  REPLY=$behind
}

# Before a download: a yt-dlp a month behind the newest gets an offer to update. Not again for a week after a "no"
# or an update that could not be done – and never when it is the newest, however old that is.
lotus_ytdlp_check() {
  lotus_ytdlp_behind
  local -i behind=$REPLY asked=0
  local have=$reply[1] newest=$reply[2]
  if [[ -n $newest ]]; then (( behind >= LOTUS_YTDLP_OLD )) || return 0
  else (( behind > 60 )) || return 0; fi
  [[ -r $LOTUS_STATE/ytdlp-asked ]] && asked=$(<$LOTUS_STATE/ytdlp-asked)
  (( EPOCHSECONDS - asked < LOTUS_YTDLP_QUIET * 86400 )) && return 0
  lotus_log INFO convert "yt-dlp $have is $behind days behind ${newest:-today}"
  if [[ -n $newest ]]; then ui_warn "A newer yt-dlp is out: $newest – yours is $behind days older ($have)."
  else ui_warn "Your yt-dlp is $behind days old ($have)."; fi
  ui_dim "  Old versions often fail on YouTube."
  ui_has_tty || return 0
  if ui_confirm "Update yt-dlp first?" y && lotus_ytdlp_update; then ui_blank; return 0; fi
  # a "no", or it could not be done: a week of quiet
  { zf_mkdir -p $LOTUS_STATE && print $EPOCHSECONDS >| $LOTUS_STATE/ytdlp-asked } 2>/dev/null
  ui_dim "  /convert asks again in $LOTUS_YTDLP_QUIET days – or when a download fails because of it."
  ui_blank
  return 0
}

# Updates yt-dlp the way it was installed. When it belongs to another macOS user (their Homebrew), Lotus offers its
# own copy instead – it cannot change their files, and it never uses sudo for this.
lotus_ytdlp_update() {
  lotus_ytdlp_info
  local was=$reply[1] how=$reply[2] can=$reply[3] bin=${commands[yt-dlp]:A}
  [[ $how == lotus ]] && bin=$LOTUS_YTDLP_OWN
  if [[ $can != ok ]]; then
    lotus_log INFO convert "yt-dlp ($how) belongs to $can – $USER cannot update it"
    if [[ $how == brew ]]; then ui_warn "Homebrew on this Mac belongs to the macOS user $can."
    else ui_warn "yt-dlp is in a folder of the macOS user $can."; fi
    ui_dim "  As $USER, Lotus cannot update it. It can keep its own yt-dlp for you:"
    ui_dim "  the official macOS build from github.com/yt-dlp, checked against its checksum."
    ui_dim "  Only /convert uses it, and it updates itself."
    ui_has_tty && ui_confirm "Get the newest yt-dlp just for you?" y || return 1
    lotus_ytdlp_own
    return
  fi
  ui_step "Updating yt-dlp …"
  local -i ok=0
  case $how in
    brew)  env -u HOMEBREW_NO_AUTO_UPDATE brew upgrade yt-dlp && ok=1 ;;
    pipx)  pipx upgrade yt-dlp && ok=1 ;;
    pip)   local py=$(head -1 $bin); py=${${py#\#!}%% *}
           "$py" -m pip install --upgrade yt-dlp && ok=1 ;;
    *)     $bin -U && ok=1 ;;
  esac
  rehash
  lotus_ytdlp_info
  # The new version decides: Homebrew can report a problem with another package and still update yt-dlp
  if [[ -n $reply[1] && $reply[1] != $was ]]; then
    lotus_log INFO convert "yt-dlp updated: $was → $reply[1]"
    ui_success "yt-dlp $reply[1]"
    (( ok )) || ui_dim "  $how reported a problem with something else (see above) – yt-dlp itself is up to date."
    return 0
  elif (( ok )); then
    ui_info "yt-dlp $reply[1] is already the newest version."
    return 0
  fi
  case $how in
    brew) ui_error "yt-dlp could not be updated" "Homebrew's message is shown above." "Try: brew upgrade yt-dlp" ;;
    pipx) ui_error "yt-dlp could not be updated" "" "Try: pipx upgrade yt-dlp" ;;
    pip)  ui_error "yt-dlp could not be updated" "" "Try: python3 -m pip install --upgrade yt-dlp" ;;
    *)    ui_error "yt-dlp could not be updated" "" "Try: ${bin/#$HOME/~} -U" ;;
  esac
  return 1
}

# Lotus' own yt-dlp: the official macOS build of the newest release from github.com/yt-dlp, checked against the
# release's SHA2-256SUMS before it is used. Nothing outside Lotus' folder changes.
lotus_ytdlp_own() {
  setopt localoptions extendedglob
  local dir=${LOTUS_YTDLP_OWN:h} ver want sum tmp v
  lotus_ytdlp_latest || { ui_error "The newest yt-dlp could not be found" "github.com did not answer." "Try again later."; return 1 }
  ver=$REPLY
  local base=https://github.com/yt-dlp/yt-dlp/releases/download/$ver
  zf_mkdir -p $dir 2>/dev/null || { ui_error "Cannot write to ${dir/#$HOME/~}"; return 1 }
  tmp=$dir/yt-dlp.download
  want=$(curl -fsSL -m 30 $base/SHA2-256SUMS 2>/dev/null | awk '$2 == "yt-dlp_macos" { print $1 }')
  [[ $want == [0-9a-f](#c64) ]] || { ui_error "yt-dlp $ver could not be checked" "Its checksums did not come from github.com." "Try again later."; return 1 }
  lotus_ytdlp_fetch $base/yt-dlp_macos $tmp $ver $want
  case $? in
    0) ;;
    2) rm -f $tmp
       lotus_log ERROR convert "yt-dlp $ver: the checksum does not match"
       ui_error "yt-dlp $ver was not installed" "The downloaded file is not the one github.com lists – it was deleted."
       return 1 ;;
    *) rm -f $tmp
       (( LOTUS_CONVERT_STOP )) || ui_error "yt-dlp could not be downloaded" "github.com did not send it." "Try again later."
       return 1 ;;
  esac
  chmod 755 $tmp && zf_mv -f $tmp $LOTUS_YTDLP_OWN
  v=$($LOTUS_YTDLP_OWN --version 2>/dev/null)
  if [[ -z $v ]]; then
    rm -f $LOTUS_YTDLP_OWN
    ui_error "yt-dlp $ver does not start on this Mac" "Lotus keeps using the one you have."
    return 1
  fi
  lotus_log INFO convert "Lotus' own yt-dlp: $v in $dir"
  ui_success "yt-dlp $v – Lotus' own, for /convert"
  ui_dim "  yt-dlp in your shell stays as it is."
  return 0
}

# Downloads <url> to <file> while the lotus blooms – real bytes from the file's size – and checks its SHA-256.
# Status 1 = failed or stopped, 2 = not the file that was promised.
lotus_ytdlp_fetch() {   # <url> <file> <version> <sha256>
  local url=$1 file=$2 ver=$3 want=$4 sum
  setopt localoptions localtraps
  source $LOTUS_ROOT/lib/bg/progress.zsh
  lotus_lang_group bg
  trap 'LOTUS_CONVERT_STOP=1' INT
  _bg_cancel() { LOTUS_CONVERT_STOP=1 BG_CANCEL=0 }
  LOTUS_CONVERT_STOP=0 BG_CANCEL=0
  # the size from GitHub's answer: the bar shows real bytes, never a guess
  local -i total=$(curl -fsIL -m 15 $url 2>/dev/null | awk 'tolower($1) == "content-length:" { n = $2 } END { print n + 0 }') pid rc=1
  local -a st
  bg_ui_begin yt-dlp "download|Downloading yt-dlp $ver|Download" "check|Checking it|Checksum"
  bg_ui_sub "github.com/yt-dlp"
  bg_ui_info format "the official macOS build"
  bg_ui_stage download
  curl -fsSL -m 900 -o $file $url 2>/dev/null &
  pid=$!
  while kill -0 $pid 2>/dev/null && (( ! LOTUS_CONVERT_STOP )); do
    zstat -A st +size -- $file 2>/dev/null && (( total > 0 )) && bg_ui_progress $st[1] $total
    bg_ui_frame
    bg_ui_tick 8
  done
  if (( LOTUS_CONVERT_STOP )); then
    kill -TERM $pid 2>/dev/null; wait $pid 2>/dev/null
    bg_ui_end; ui_info "Stopped."
    return 1
  fi
  wait $pid; rc=$?
  if (( rc == 0 )); then
    bg_ui_stage check
    bg_ui_progress 0 0
    bg_ui_frame
    sum=$(shasum -a 256 $file 2>/dev/null)
    if [[ ${sum%% *} == $want ]]; then bg_ui_complete; else rc=2; fi
  fi
  bg_ui_end
  return rc
}

lotus_convert_deps() {
  local -a missing=()
  (( $+commands[yt-dlp] )) || [[ -x $LOTUS_YTDLP_OWN ]] || missing+=(yt-dlp)
  (( $+commands[ffmpeg] )) || missing+=(ffmpeg)
  (( ${#missing} )) || return 0
  ui_error "Missing tools: ${(j:, :)missing}" "/convert uses yt-dlp to download and ffmpeg to convert." \
    "Both are free and open source and come from Homebrew."
  source $LOTUS_ROOT/lib/cmd/brew.zsh
  lotus_need_brew || return 1
  ui_confirm "Install ${(j: and :)missing} with Homebrew?" y || return 1
  HOMEBREW_NO_AUTO_UPDATE=1 brew install $missing || { ui_error "Installation failed" "Homebrew's message is shown above."; return 1 }
  rehash
}
