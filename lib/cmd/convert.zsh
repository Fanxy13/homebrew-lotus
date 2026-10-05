# lotus – /convert: save a video as MP3 or MP4 with yt-dlp and ffmpeg.
# Only for content you have the right to download. Lotus does not bypass DRM,
# paywalls, logins or private content – yt-dlp is used with its default behavior.

typeset -g LOTUS_DOWNLOADS=${LOTUS_DOWNLOADS:-~/Downloads/Lotus}

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

  zf_mkdir -p $LOTUS_DOWNLOADS
  ui_step "Checking the video …"
  local file=$(yt-dlp "${args[@]}" -o "$tpl" --print filename --skip-download -- "$link" 2>/dev/null | tail -1)
  [[ -z $file ]] && { ui_error "yt-dlp cannot read this link" "$link" "The video may be private, removed or not supported."; return 1 }
  file=${file:r}.$ext
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
  if ! yt-dlp "${args[@]}" -o "$tpl" -- "$link"; then
    ui_error "The download did not finish" "yt-dlp's message is shown above."
    return 1
  fi
  [[ $ext == mp4 && -e $file ]] && lotus_convert_finish "$file" "$fps"
  ui_blank
  ui_success "Done: ${file/#$HOME/~}"
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
