# lotus – /convert: save a video as MP3 or MP4 with yt-dlp and ffmpeg.
# Only for content you have the right to download. Lotus does not bypass DRM,
# paywalls, logins or private content – yt-dlp is used with its default behavior.

typeset -g LOTUS_DOWNLOADS=${LOTUS_DOWNLOADS:-~/Downloads/Lotus}
typeset -g LOTUS_LOG_COMP=convert
typeset -gi LOTUS_YTDLP_OLD=60    # days – sites change often, an older yt-dlp is the usual cause of failures
typeset -gi LOTUS_CONVERT_PAUSE=2 # seconds before the second try – YouTube often fails once and then works

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
  local -a args=(--no-playlist --newline --progress)
  local tpl="$LOTUS_DOWNLOADS/%(title).150B.%(ext)s"
  local fps= ext=mp3

  if (( want == 1 )); then
    args+=(-x --audio-format mp3 --audio-quality 0)
  else
    ext=mp4
    local -a res=(360 480 720 1080 best)
    ui_choose "Resolution" 360p 480p 720p 1080p "Best available" || return 0
    local h=$res[REPLY]
    if [[ $h == best ]]; then
      args+=(-f 'bv*[ext=mp4]+ba[ext=m4a]/bv*+ba/b')
    else
      # the last "/b" covers plain video files without size information
      args+=(-f "bv*[height<=$h][ext=mp4]+ba[ext=m4a]/bv*[height<=$h]+ba/b[height<=$h]/b")
    fi
    args+=(--merge-output-format mp4 --remux-video mp4)
    local -a fpss=(source 24 30 60)
    ui_choose "Frames per second" "Keep the original" "24 FPS" "30 FPS" "60 FPS" || return 0
    fps=${fpss[REPLY]:#source}
    [[ -n $fps ]] && ui_dim "Changing the frame rate re-encodes the video, which takes a while."
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

  ui_blank
  ui_info "Saving to ${file/#$HOME/~}"
  # yt-dlp's own messages stay visible here; a copy of them tells Lotus what went wrong
  local -i try=1
  while ! yt-dlp --no-update "${args[@]}" -o "$tpl" -- "$link" 2> >(tee $errs >&2); do
    lotus_convert_failed $errs $try download || return 1
    (( try++ ))
    ui_blank
    ui_info "Trying again …"
  done
  [[ $ext == mp4 && -e $file ]] && lotus_convert_finish "$file" "$fps"
  ui_blank
  ui_success "Done: ${file/#$HOME/~}"
  lotus_pet_react done
  ui_confirm "Show it in Finder?" y && open -R "$file"
}

# MP4 that plays everywhere: new frame rate if asked, AAC audio (QuickTime cannot play Opus in MP4)
lotus_convert_finish() {   # <file.mp4> [fps]
  local file=$1 fps=$2
  local acodec=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$file" 2>/dev/null)
  local -a ff=()
  [[ -n $fps ]] && ff+=(-r $fps) || ff+=(-c:v copy)
  [[ $acodec == (aac|mp3|) ]] && ff+=(-c:a copy) || ff+=(-c:a aac -b:a 192k)
  [[ -z $fps && $acodec == (aac|mp3|) ]] && return 0
  if [[ -n $fps ]]; then ui_step "Converting to $fps FPS …"; else ui_step "Making the audio QuickTime-friendly …"; fi
  ffmpeg -hide_banner -loglevel error -stats -i "$file" $ff -y "${file:r}.tmp.mp4" && zf_mv -f "${file:r}.tmp.mp4" "$file" \
    || { rm -f "${file:r}.tmp.mp4"; ui_error "Conversion failed" "The downloaded video was kept as it is."; return 1 }
}

# Asks yt-dlp what the file will be called – the first look at the video → REPLY = file name.
# Its messages go to <errs> instead of the screen; when it fails they say why (lotus_convert_failed).
lotus_convert_probe() {   # <errs> <link> <template> <yt-dlp arguments…>
  local errs=$1 link=$2 tpl=$3
  shift 3
  local -i try=1
  ui_step "Checking the video …"
  until REPLY=$(yt-dlp --no-update "$@" -o "$tpl" --print filename --skip-download -- "$link" 2>$errs | tail -1); [[ -n $REPLY ]]; do
    lotus_convert_failed $errs $try check || return 1
    (( try++ ))
    ui_step "Checking the video again …"
  done
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
    # (while downloading, yt-dlp's messages are on screen already)
    [[ $kind == outdated || $what == download ]] || ui_warn "yt-dlp: ${first:-it stopped without a reason} – trying once more"
    sleep $LOTUS_CONVERT_PAUSE
    return 0
  fi
  [[ $kind == outdated ]] || ui_error $title "${first:-yt-dlp stopped without a reason.}"
  ui_dim "  If it still fails: check that the video plays in your browser, or try again later."
  ui_blank
  return 1
}

# Version, age (days, in REPLY) and how yt-dlp was installed: brew, pipx, pip or self
lotus_ytdlp_info() {
  setopt localoptions extendedglob
  local v=$(yt-dlp --version 2>/dev/null) bin=${commands[yt-dlp]:A} how=self when
  case $bin in
    */Cellar/*|*/homebrew/*) how=brew ;;
    */pipx/*)                how=pipx ;;
    *) [[ $(head -c 2 $bin 2>/dev/null) == '#!' ]] && how=pip ;;
  esac
  reply=($v $how)
  REPLY=
  if [[ $v == (#b)(<->).(<->).(<->)* ]]; then
    strftime -r -s when %Y-%m-%d "$match[1]-$match[2]-$match[3]" 2>/dev/null && REPLY=$(( (EPOCHSECONDS - when) / 86400 ))
  fi
}

# Before a download: an old yt-dlp gets an offer to update
lotus_ytdlp_check() {
  lotus_ytdlp_info
  local -i age=${REPLY:--1}
  (( age > LOTUS_YTDLP_OLD )) || return 0
  lotus_log INFO convert "yt-dlp $reply[1] is $age days old"
  ui_warn "Your yt-dlp is $age days old ($reply[1]). Old versions often fail on YouTube."
  ui_has_tty || return 0
  ui_confirm "Update yt-dlp first?" y || { ui_blank; return 0 }
  lotus_ytdlp_update
  ui_blank
}

# Updates yt-dlp the way it was installed
lotus_ytdlp_update() {
  lotus_ytdlp_info
  local was=$reply[1] how=$reply[2] bin=${commands[yt-dlp]:A}
  ui_step "Updating yt-dlp …"
  local -i ok=0
  case $how in
    brew) env -u HOMEBREW_NO_AUTO_UPDATE brew upgrade yt-dlp && ok=1 ;;
    pipx) pipx upgrade yt-dlp && ok=1 ;;
    pip)  local py=$(head -1 $bin); py=${${py#\#!}%% *}
          "$py" -m pip install --upgrade yt-dlp && ok=1 ;;
    *)    yt-dlp -U && ok=1 ;;
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
    *)    ui_error "yt-dlp could not be updated" "" "Try: yt-dlp -U" ;;
  esac
  return 1
}

lotus_convert_deps() {
  local -a missing=()
  (( $+commands[yt-dlp] )) || missing+=(yt-dlp)
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
