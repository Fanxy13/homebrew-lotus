# lotus – /bg remove: remove image backgrounds on this Mac (BiRefNet or InSPyReNet, local only).
#   /bg remove <image|folder>…     cut out, then: open, show in Finder, refine by hand
#   /bg remove --edit <image>      open "Draw what you want to keep" right after the AI
#   /bg remove                     drop an image into the window (an empty ⏎ takes the clipboard)
#   /bg paste                      the image or files in the clipboard (also: /bg remove --clipboard)
#   /bg models · /bg output · /bg setup · /bg help
# Images are read and written locally. Nothing is uploaded; models are downloaded once, after a yes.

source $LOTUS_ROOT/lib/bg/runtime.zsh
source $LOTUS_ROOT/lib/bg/progress.zsh
source $LOTUS_ROOT/lib/bg/manage.zsh
lotus_lang_group bg
typeset -g LOTUS_LOG_COMP=bg
typeset -g BG_SESSION= BG_SESSION_LOG=$LOTUS_CACHE/bg/worker.log
typeset -ga BG_ERR=() BG_DONE=() BG_SKIP=() BG_WARN=()
typeset -gi BG_ERR_LOGGED=0     # the worker already wrote this error (with its details) to the log
typeset -gA BG_INFO=()
typeset -ga BG_EXT=(png jpg jpeg webp heic heif avif tif tiff bmp gif)

lotus_cmd_bg() {
  shift   # "bg"
  case $1 in
    ''|help|-h|--help)  bg_help ;;
    remove|rm|cut)      shift; bg_remove "$@" ;;
    edit)               shift; bg_remove --edit "$@" ;;
    paste|clipboard)    shift; bg_remove --clipboard "$@" ;;
    setup|install)      lotus_bg_first_use ;;
    models|model|cache) bg_models_screen ;;
    output|folder)      ui_hero $LOTUS_L[bg_title] $LOTUS_L[bg_q_output]; lotus_bg_pick_output && lotus_save && ui_success $LOTUS_L[saved] ;;
    doctor)             ui_hero "$LOTUS_L[bg_title] · Doctor"; bg_doctor_rows; ui_blank ;;
    *)  if [[ -e ${1/#\~/$HOME} || $1 == file://* ]]; then bg_remove "$@"
        else ui_error "$LOTUS_L[bg_unknown]" "$1" "/bg remove <image>   ·   /bg help"; return 1; fi ;;
  esac
}

bg_help() {
  ui_hero $LOTUS_L[bg_title] $LOTUS_L[bg_tagline]
  local k=$'\e['"$LOTUS_C[key]m" d=$'\e['"$LOTUS_C[dim]m" r
  local -a rows=(
    "/bg remove <image>|$LOTUS_L[bg_h_remove]"
    "/bg remove <folder>|$LOTUS_L[bg_h_folder]"
    "/bg remove --edit <image>|$LOTUS_L[bg_h_edit]"
    "/bg remove|$LOTUS_L[bg_h_drop]"
    "/bg paste|$LOTUS_L[bg_h_paste]"
    "/bg models|$LOTUS_L[bg_h_models]"
    "/bg output|$LOTUS_L[bg_h_output]")
  for r in $rows; do print -r -- "    ${k}${(r:28:)${r%%|*}}${_UI_R}${r#*|}"; done
  ui_blank
  ui_section $LOTUS_L[bg_h_examples]; ui_blank
  print -r -- "    ${d}/bg remove ~/Pictures/photo.png${_UI_R}"
  print -r -- "    ${d}/bg remove \"~/Desktop/My Photos/beach.heic\"${_UI_R}"
  print -r -- "    ${d}/bg remove --edit portrait.jpg${_UI_R}"
  ui_blank
  ui_dim "  $LOTUS_L[bg_h_local]"
  lotus_bg_model_label $LOTUS_BG_MODEL; local m=$REPLY
  if [[ $LOTUS_BG_OUTPUT == @source ]]; then REPLY=$LOTUS_L[bg_o_source]; else ui_path "${LOTUS_BG_OUTPUT/#\~/$HOME}"; fi
  ui_dim "  $LOTUS_L[bg_model]: $m · $LOTUS_L[bg_output]: $REPLY"
  ui_blank
}

# ── Paths ─────────────────────────────────────────────────────

# One path as typed or dropped → REPLY (absolute). file:// links and ~ work, nothing is executed.
bg_clean_path() {
  setopt localoptions extendedglob
  local p=${1##[[:space:]]##}
  p=${p%%[[:space:]]##}
  if [[ $p == file://* ]]; then
    p=${p#file://}; p=${p#localhost}
    p=${(g::)${p//\%/\\x}}
  fi
  [[ $p == '~' || $p == '~/'* ]] && p=$HOME${p#\~}
  [[ $p == /* ]] || p=$PWD/$p
  REPLY=${p:a}
}

# Arguments → reply (existing paths). Paths typed with spaces but without quotes are put back together.
# Folders become the images inside them. Not found → BG_MISSING.
bg_collect() {
  local -a in=("$@") out=()
  typeset -ga BG_MISSING=()
  local -i i=1 j found
  while (( i <= ${#in} )); do
    bg_clean_path "${in[i]}"
    if [[ -e $REPLY ]]; then out+=($REPLY); (( i++ )); continue; fi
    found=0
    for (( j = i + 1; j <= ${#in}; j++ )); do
      bg_clean_path "${(j: :)in[i,j]}"
      if [[ -e $REPLY ]]; then out+=($REPLY); (( i = j + 1 )); found=1; break; fi
    done
    (( found )) || { BG_MISSING+=("${in[i]}"); (( i++ )) }
  done
  local p
  reply=()
  for p in $out; do
    if [[ -d $p ]]; then
      local -a imgs=($p/*.(#i)(${(j:|:)~BG_EXT})(N.on))
      reply+=(${imgs:#*_no_bg(_<->|).png})
    else
      reply+=($p)
    fi
  done
}

# Drag and drop: a drop zone in the theme colors. Finder types the path into the window,
# Lotus reads it without running anything.
#
#    ╭╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╮
#    ┆                  ┃                   ┆
#    ┆                ━━╋━━                 ┆
#    ┆                  ┃                   ┆
#    ┆            Drop images here          ┆
#    ┆    PNG · JPG · WebP · HEIC · folders ┆
#    ╰╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╯
#    › (the dropped path)
bg_ask_paths() {
  ui_hero $LOTUS_L[bg_title] $LOTUS_L[bg_tagline]
  local -i W=${COLUMNS:-80}
  (( W > 20 )) || W=80
  if (( W >= 44 )); then
    _bg_drop_zone $(( W - 8 > 60 ? 60 : W - 8 ))
  else
    ui_text $LOTUS_L[bg_drop]
    ui_dim "  $LOTUS_L[bg_drop_hint]"
  fi
  # an image or files in the clipboard: an empty line takes them
  bg_clipboard_peek
  local clip=$REPLY
  if [[ $clip == image\ * ]]; then
    print -r -- "    "$'\e['"$LOTUS_C[key]m✓"$_UI_R" ${LOTUS_L[bg_clip_image]//\%s/${${clip#image }/x/ × }}"
  elif [[ $clip == files\ * ]]; then
    print -r -- "    "$'\e['"$LOTUS_C[key]m✓"$_UI_R" ${LOTUS_L[bg_clip_files]//\%s/${clip#files }}"
  fi
  # the keys above the prompt, so a long dropped path has room to wrap below
  if [[ $clip == none ]]; then ui_dim "  $LOTUS_L[bg_drop_keys]"; else ui_dim "  $LOTUS_L[bg_drop_keys_clip]"; fi
  ui_blank
  print -rn -- "    "$'\e['"$LOTUS_C[accent]m›"$_UI_R" "
  local line
  read -r line < /dev/tty || return 1
  if [[ -z ${line//[[:space:]]/} || ${(L)line} == (v|paste|clipboard) ]]; then
    [[ $clip == none ]] && return 1
    bg_clipboard_take
    return
  fi
  # (z) splits like the shell would, (Q) removes the quotes and backslashes – no expansion, no commands
  reply=(${(Q)${(z)line}})
  (( ${#reply} ))
}

# ── Clipboard ─────────────────────────────────────────────────
# Read with macOS' own JavaScript for Automation (lib/bg/clipboard.js) – no extra tools.

# What the clipboard holds → REPLY: "files <n>", "image <w>x<h>" or "none"
bg_clipboard_peek() {
  REPLY=$(osascript -l JavaScript $LOTUS_ROOT/lib/bg/clipboard.js peek 2>/dev/null)
  [[ -n $REPLY ]] || REPLY=none
}

# The clipboard as input → reply (paths): copied files as they are, an image saved as PNG
# in ~/.cache/lotus/bg/clipboard (removed after a day). Status 1 when there is nothing to use.
bg_clipboard_take() {
  local dir=$LOTUS_CACHE/bg/clipboard stamp
  zf_mkdir -p $dir && chmod 700 $dir
  rm -f $dir/*(N.mh+24)
  strftime -s stamp '%Y-%m-%d %H.%M.%S' $EPOCHSECONDS
  reply=(${(f)"$(osascript -l JavaScript $LOTUS_ROOT/lib/bg/clipboard.js save "$dir/Clipboard $stamp.png" 2>/dev/null)"})
  reply=(${reply:#})
  (( ${#reply} )) || return 1
  lotus_log INFO bg "From the clipboard: ${#reply} item(s)"
}

# The dashed frame with a plus in the middle.  _bg_drop_zone <width>
_bg_drop_zone() {
  local -i w=$1 inner=$(( $1 - 2 ))
  local b=$'\e['"$LOTUS_C[border]m" k=$'\e[1;'"$LOTUS_C[key]m" d=$'\e['"$LOTUS_C[dim]m" B=$'\e[1m' R=$_UI_R
  local dash=${${(l:inner::x:)}//x/╌}
  _row() {   # <plain text> [<colored text>] – centered between the side lines
    local plain=$1 shown=${2:-$1}
    local -i left=$(( (inner - ${#plain}) / 2 ))
    print -r -- "    ${b}┆${R}${(l:left:)}${shown}${(l:inner - left - ${#plain}:)}${b}┆${R}"
  }
  local title=$LOTUS_L[bg_drop_here] types=$LOTUS_L[bg_drop_types]
  (( ${#types} > inner - 2 )) && types="${types[1,inner-3]}…"
  print -r -- "    ${b}╭${dash}╮${R}"
  _row ""
  _row "  ┃  " "  ${k}┃${R}  "
  _row "━━╋━━" "${k}━━╋━━${R}"
  _row "  ┃  " "  ${k}┃${R}  "
  _row ""
  _row "$title" "${B}${title}${R}"
  _row "$types" "${d}${types}${R}"
  _row ""
  print -r -- "    ${b}╰${dash}╯${R}"
  unfunction _row
}

# ── Running the worker ────────────────────────────────────────

bg_session_new() {
  zf_mkdir -p $LOTUS_CACHE/bg && chmod 700 $LOTUS_CACHE/bg
  rm -rf $LOTUS_CACHE/bg/session.*(N/mh+24)    # left over from a crash
  BG_SESSION=$(mktemp -d $LOTUS_CACHE/bg/session.XXXXXX) || return 1
  : >| $BG_SESSION_LOG
}

bg_session_end() {
  [[ -n $BG_SESSION && $BG_SESSION == $LOTUS_CACHE/bg/session.* ]] && rm -rf $BG_SESSION
  BG_SESSION=
}

# Runs one worker command and turns its events into the progress screen. Status = worker status.
bg_worker() {
  BG_ERR=() BG_DONE=() BG_SKIP=() BG_WARN=() BG_INFO=() BG_ERR_LOGGED=0
  bg_python
  local -a cmd=($reply $LOTUS_ROOT/lib/bg/worker.py "$@")
  local line
  local -a f
  local -i rc=0
  # The worker is a plain background process writing its events into a named pipe – no shell
  # around it, so none of Lotus' traps run in it. Its last event is "end <status>"; if it dies
  # without one, the pipe closes and read returns at once.
  local fifo=$BG_SESSION/events
  rm -f $fifo; mkfifo -m 600 $fifo || { BG_ERR=(BG-011 "Lotus could not talk to the background remover." "mkfifo $fifo"); return 1 }
  env LOTUS_LOG=$LOTUS_LOG LOTUS_LOG_LEVEL=$LOTUS_LOG_LEVEL LOTUS_VERBOSE=$LOTUS_VERBOSE \
      PYTHONDONTWRITEBYTECODE=1 HF_HUB_OFFLINE=1 $cmd > $fifo 2>>$BG_SESSION_LOG &
  typeset -gi BG_WORKER_PID=$!
  local -i fd
  exec {fd}< $fifo
  lotus_log DEBUG bg "Worker: ${1} (pid $BG_WORKER_PID)"
  local -i open=1
  rc=-1
  _BG_BUF=
  while (( open )); do
    bg_read_lines $fd 0.08 || open=0
    for line in $reply; do
      f=("${(@ps:\t:)line}")
      case $f[1] in
        end)   rc=$f[2] ;;
        stage) bg_ui_stage $f[2] ;;
        info)  BG_INFO[$f[2]]=$f[3]
               [[ $f[2] == (model|backend|resolution) ]] && bg_ui_info $f[2] $f[3] ;;
        image) bg_ui_batch $f[2] $f[3]
               if (( f[3] > 1 )); then bg_ui_sub "$f[2] / $f[3] · ${f[4]:t}"; bg_ui_reset_from load_image; fi
               bg_ui_info image ${f[4]:t} ;;
        done)  BG_DONE+=("$f[2]" "$f[3]" "$f[4]") ;;
        skip)  BG_SKIP+=("$f[2]" "$f[4]") ;;
        warn)  BG_WARN+=("$f[2]" "$f[3]"); lotus_log WARN bg "$f[3]" ;;
        error) BG_ERR=("$f[2]" "$f[3]" "$f[4]"); BG_ERR_LOGGED=1 ;;
      esac
    done
    bg_ui_frame
  done
  exec {fd}<&-
  rm -f $fifo
  bg_ui_check
  local -i st
  wait $BG_WORKER_PID 2>/dev/null; st=$?
  (( rc < 0 )) && rc=st
  BG_WORKER_PID=0
  (( rc && ! ${#BG_ERR} && rc != 130 )) && BG_ERR=(BG-011 "The background remover stopped unexpectedly (status $rc)." "$(tail -3 $BG_SESSION_LOG 2>/dev/null)")
  (( ${#BG_ERR} )) && return 1
  return rc
}

# ctrl-c: the trap only stops the worker (kill is built in) and sets a flag. A signal can arrive
# in the middle of output, so starting programs from the trap itself could hang – the loops see
# the flag and clean up in _bg_cancel.
typeset -gi BG_CANCEL=0
_bg_interrupt() {
  trap '' INT TERM HUP
  BG_CANCEL=1
  (( BG_WORKER_PID )) && kill -TERM $BG_WORKER_PID 2>/dev/null
  return 0
}

_bg_cancel() {
  bg_ui_end
  bg_session_end
  lotus_log INFO bg "Cancelled"
  print -r -- ""
  ui_info $LOTUS_L[cancelled]
  exit 130
}

# ── Errors ────────────────────────────────────────────────────

# bg_error_screen <code> <reason> [detail] – what happened, why, what helps; details stay in the log
bg_error_screen() {
  [[ -t 1 ]] || { _bg_error_screen "$@" >&2; return }
  _bg_error_screen "$@"
}

_bg_error_screen() {
  local code=${1:-BG-011} reason=$2 detail=$3
  (( BG_ERR_LOGGED )) || lotus_log ERROR bg "$code ${reason}${detail:+ – $detail}"
  BG_ERR_LOGGED=0
  local -i cols=${COLUMNS:-100}
  (( cols > 20 )) || cols=100
  local d=$'\e['"$LOTUS_C[dim]m" e=$'\e[1;38;5;203m'
  ui_hero $LOTUS_L[bg_failed]
  print -r -- "    ${_UI_B}${LOTUS_L[bg_e_$code]:-$LOTUS_L[bg_e_BG-011]}${_UI_R}"
  ui_blank
  if [[ -n $reason ]]; then
    ui_section $LOTUS_L[bg_reason]
    print -r -- "    $reason"
    [[ -n $detail ]] && print -r -- "    ${d}${${detail//$HOME/~}[1,cols-8]}${_UI_R}"
    ui_blank
  fi
  local tips=${LOTUS_L[bg_t_$code]} t
  ui_section $LOTUS_L[bg_try]
  for t in ${(s:|:)tips} $LOTUS_L[bg_t_doctor]; do print -r -- "    • $t"; done
  ui_blank
  print -r -- "    ${d}${LOTUS_L[bg_error_id]}: ${_UI_R}${e}${code}${_UI_R}${d}   ·   ${LOTUS_L[bg_details]}: /lotus log${_UI_R}"
  ui_blank
}

# After a failure: offer what is likely to work (another backend or another installed model).
# → REPLY = "backend cpu" or "model <id>", status 1 when there is nothing to offer or the answer is no.
bg_fallback() {
  local code=$1 model=$2 backend=$3 id
  ui_has_tty || return 1
  if [[ $code == (BG-013|BG-007) && $backend != cpu ]]; then
    ui_confirm "$LOTUS_L[bg_fb_cpu]" y && { REPLY="backend cpu"; return 0 }
    return 1
  fi
  if [[ $code == (BG-004|BG-009) ]]; then
    for id in birefnet inspyrenet birefnet-lite; do
      [[ $id == $model ]] && continue
      bg_model_state $id; [[ $REPLY == ok ]] || continue
      bg_model_field $model 3; local from=$REPLY
      bg_model_field $id 3
      ui_confirm "${${LOTUS_L[bg_fb_model]//\%1/$from}//\%2/$REPLY}" y && { REPLY="model $id"; return 0 }
      return 1
    done
  fi
  return 1
}

# ── /bg remove ────────────────────────────────────────────────

bg_remove() {
  local model= backend=$LOTUS_BG_BACKEND out=
  local -i edit=0 next=0 clip=0
  local -a args=()
  while (( $# )); do
    case $1 in
      -e|--edit)      edit=1 ;;
      -m|--model)     model=$2; shift ;;
      --model=*)      model=${1#*=} ;;
      -b|--backend)   backend=$2; shift ;;
      --backend=*)    backend=${1#*=} ;;
      --cpu)          backend=cpu ;;
      -o|--out)       out=$2; shift ;;
      --out=*)        out=${1#*=} ;;
      --next-to-source|--here) next=1 ;;
      -c|--clipboard|--paste) clip=1 ;;
      -h|--help)      bg_help; return 0 ;;
      --)             shift; args+=("$@"); break ;;
      *)              args+=("$1") ;;
    esac
    shift
  done
  [[ -n $model ]] && { bg_registry; [[ $model == auto || -n ${BG_MODEL_ROW[$model]} ]] || { ui_error "$LOTUS_L[bg_bad_model]" "$model" "auto · ${(j: · :)BG_MODEL_IDS}"; return 1 } }
  [[ $backend == (auto|mps|cpu) ]] || { ui_error "$LOTUS_L[bg_bad_backend]" "$backend" "auto · mps · cpu"; return 1 }

  if (( clip )); then
    bg_clipboard_take || { ui_error $LOTUS_L[bg_clip_none] "" "$LOTUS_L[bg_clip_none_hint]"; return 1 }
    args+=("${reply[@]}")
  elif (( ! ${#args} )); then
    if ! { [[ -t 1 ]] && ui_has_tty }; then ui_error $LOTUS_L[bg_which] "" "/bg remove <image>   ·   /bg paste"; return 1; fi
    bg_ask_paths || { ui_info $LOTUS_L[cancelled]; return 1 }
    args=("${reply[@]}")
  fi
  bg_collect "${args[@]}"
  local -a images=("${reply[@]}")
  local m
  for m in $BG_MISSING; do ui_error $LOTUS_L[bg_notfound] "$m" "$LOTUS_L[bg_notfound_hint]"; done
  if (( ! ${#images} )); then
    (( ${#BG_MISSING} )) || ui_error $LOTUS_L[bg_noimages] "${(j:, :)args}" "$LOTUS_L[bg_types]"
    return 1
  fi
  lotus_log INFO bg "Remove BG requested for ${#images} image(s)"

  # First use, or something missing (runtime or model)
  if (( ! LOTUS_BG_READY )); then
    ui_has_tty && [[ -t 1 ]] || { bg_error_screen BG-014 "$LOTUS_L[bg_e_notty]" ""; return 1 }
    lotus_bg_first_use || return 1
  fi
  bg_resolve_model $model; model=$REPLY
  _bg_missing $model
  if (( reply[1] || reply[2] )); then
    lotus_bg_install $model || return 1
  fi

  # Where the PNGs go
  local -a dest=()
  local -i only_clip=1
  for m in $images; do [[ $m == $LOTUS_CACHE/bg/clipboard/* ]] || only_clip=0; done
  if (( ! only_clip )) && { (( next )) || [[ -z $out && $LOTUS_BG_OUTPUT == @source ]] }; then
    dest=(--next-to-source)
  else
    # an image from the clipboard has no folder of its own: it goes to the Lotus folder in Pictures
    local dir=${out:-$LOTUS_BG_OUTPUT}
    [[ $dir == @source ]] && dir='~/Pictures/Lotus/Background Removed'
    bg_clean_path ${dir/#\~/$HOME}; dir=$REPLY
    if ! zf_mkdir -p $dir 2>/dev/null || [[ ! -w $dir ]]; then
      bg_error_screen BG-006 "$LOTUS_L[bg_o_nowrite]" "$dir"; return 1
    fi
    dest=(--out $dir)
  fi

  bg_session_new || return 1
  trap _bg_interrupt INT TERM HUP
  local -i tries=0
  while :; do
    bg_model_field $model 3
    bg_ui_begin $LOTUS_L[bg_title] "load_model|${LOTUS_L[bg_s_load]//\%s/$REPLY}" \
      "load_image|$LOTUS_L[bg_s_image]" "segment|$LOTUS_L[bg_s_segment]" "refine|$LOTUS_L[bg_s_refine]" "write|$LOTUS_L[bg_s_write]"
    (( ${#images} > 1 )) && bg_ui_sub "${#images} $LOTUS_L[bg_images]"
    if bg_worker run --model $model --models-dir $BG_MODELS --backend $backend $dest --session $BG_SESSION -- "${images[@]}"; then
      bg_ui_complete
      bg_ui_end
      break
    fi
    bg_ui_end
    (( ${#BG_DONE} )) && break    # some images done before the error: show them
    bg_error_screen "${BG_ERR[@]}"
    (( tries++ < 2 )) && bg_fallback "$BG_ERR[1]" $model $backend || { bg_session_end; trap 'exit 130' INT; trap - TERM HUP; return 1 }
    case ${REPLY%% *} in
      backend) backend=${REPLY#* } ;;
      model)   model=${REPLY#* } ;;
    esac
    lotus_log INFO bg "Trying again with ${REPLY}"
  done

  if (( ${#images} == 1 && ${#BG_DONE} )); then
    bg_result $edit
  else
    bg_batch_summary ${#images}
  fi
  (( ${#BG_DONE} )) && lotus_pet_react done
  bg_session_end
  trap 'exit 130' INT; trap - TERM HUP
  return 0
}

# ── Results ───────────────────────────────────────────────────

bg_result() {
  local -i edit=$1 refined=0
  local input=$BG_DONE[1] output=$BG_DONE[2] secs=$BG_DONE[3]
  if ! { [[ -t 1 ]] && ui_has_tty }; then print -r -- $output; return 0; fi
  (( LOTUS_BG_PREVIEW )) && qlmanage -p $output >/dev/null 2>&1 &!
  (( edit )) || [[ $LOTUS_BG_REFINE == always ]] && { bg_refine $input && refined=1 && output=$BG_DONE[2] && secs=$BG_DONE[3] }
  local d=$'\e['"$LOTUS_C[dim]m" k=$'\e['"$LOTUS_C[key]m"
  print -n $'\e[?1049h'
  while :; do
    print -n $'\e[H\e[2J'
    ui_hero $LOTUS_L[bg_removed_title]
    ui_path $input
    [[ $input == $LOTUS_CACHE/bg/clipboard/* ]] && REPLY=$LOTUS_L[bg_clip_input]
    ui_kv $LOTUS_L[bg_i_input] $REPLY
    if [[ -e $output ]]; then ui_path $output; ui_kv $LOTUS_L[bg_i_output] $REPLY
    else ui_kv $LOTUS_L[bg_i_output] "${d}$LOTUS_L[bg_discarded]${_UI_R}"; fi
    ui_blank
    ui_kv $LOTUS_L[bg_i_model] "${BG_INFO[model]:-$BG_LAST_MODEL}"
    ui_kv $LOTUS_L[bg_i_backend] "${BG_INFO[backend]:-$BG_LAST_BACKEND}"
    ui_kv $LOTUS_L[bg_i_resolution] "$BG_INFO[resolution]"
    ui_kv $LOTUS_L[bg_i_time] "${secs}s"
    (( refined )) && ui_kv $LOTUS_L[bg_i_marks] $LOTUS_L[bg_marks_used]
    ui_blank
    if [[ -e $output ]]; then
      ui_success $LOTUS_L[bg_png_ok]
      [[ $BG_WARN[1] == BG-W01 ]] && ui_warn $LOTUS_L[bg_w_empty]
    fi
    ui_blank
    print -r -- "    ${k}o${_UI_R} ${LOTUS_L[bg_k_open]}   ${k}f${_UI_R} ${LOTUS_L[bg_k_finder]}   ${k}r${_UI_R} ${LOTUS_L[bg_k_refine]}   ${k}d${_UI_R} ${LOTUS_L[bg_k_discard]}   ${k}q${_UI_R} ${LOTUS_L[bg_k_done]}"
    BG_LAST_MODEL=${BG_INFO[model]:-$BG_LAST_MODEL} BG_LAST_BACKEND=${BG_INFO[backend]:-$BG_LAST_BACKEND}
    local res=$BG_INFO[resolution]
    ui_keyx
    case $REPLY in
      o|O)  [[ -e $output ]] && open -- $output ;;
      f|F)  [[ -e $output ]] && open -R -- $output || open -- ${output:h} ;;
      r|R)  if bg_refine $input; then refined=1 output=$BG_DONE[2] secs=$BG_DONE[3]; fi
            BG_INFO[resolution]=${BG_INFO[resolution]:-$res} ;;
      d|D)  [[ -e $output ]] || continue
            print
            if ui_confirm "$LOTUS_L[bg_discard_q]" n; then
              rm -f -- $output && lotus_log INFO bg "Discarded $output"
            fi ;;
      q|Q|esc|enter) break ;;
    esac
    bg_ui_check
  done
  print -n $'\e[?1049l'
  # What stays in the terminal afterwards
  if [[ -e $output ]]; then
    ui_success "$LOTUS_L[bg_png_ok]  "$'\e['"$LOTUS_C[dim]m${BG_LAST_MODEL} · ${BG_LAST_BACKEND} · ${secs}s"$_UI_R
    ui_path $output; ui_dim "  $REPLY"
  else
    ui_info $LOTUS_L[bg_discarded]
  fi
  ui_blank
}

# "Draw what you want to keep" → refine with the marks. Status 0 = a new result was written.
bg_refine() {
  local input=$1
  [[ -r $BG_SESSION/meta.json ]] || return 1
  ui_blank
  if ! lotus_can_swift; then
    bg_error_screen BG-010 "$LOTUS_L[bg_e_noswift]" ""; ui_dim "  $LOTUS_L[back]"; ui_key; return 1
  fi
  local src=$LOTUS_ROOT/lib/bg/Editor.swift sum=$(cksum < $LOTUS_ROOT/lib/bg/Editor.swift)
  [[ -x $LOTUS_CACHE/bin/lotus-bg-editor-${sum%% *} ]] || ui_step $LOTUS_L[bg_editor_prep]
  if ! lotus_swift_build lotus-bg-editor $src; then
    bg_error_screen BG-010 "$LOTUS_L[bg_e_editor_build]" "$LOTUS_CACHE/lotus-bg-editor-build.log"; ui_dim "  $LOTUS_L[back]"; ui_key; return 1
  fi
  local editor=$REPLY
  local -a rgb=(${(s:;:)${${=LOTUS_THEMES[$LOTUS_THEME]}[3]}})
  local ui= k
  for k in title hint brush eraser size undo redo clear reset invert preview apply cancel; do ui+="$k=${LOTUS_L[bg_ed_$k]}"$'\x1f'; done
  ui_step $LOTUS_L[bg_editor_open]
  lotus_log INFO bg "Editor opened"
  LOTUS_BG_UI=$ui LOTUS_BG_ACCENT=${(j:,:)rgb} $editor --image $BG_SESSION/work.png --alpha $BG_SESSION/alpha.png \
    --keep $BG_SESSION/keep.png --title ${input:t} 2>>$BG_SESSION_LOG
  local -i rc=$?
  if (( rc != 0 )); then
    lotus_log INFO bg "Editor closed without changes (status $rc)"
    return 1
  fi
  lotus_log INFO bg "KEEP marks applied"
  bg_ui_begin $LOTUS_L[bg_title] "load_image|$LOTUS_L[bg_s_image]" "refine|$LOTUS_L[bg_s_marks]|$LOTUS_L[bg_ss_marks]" "write|$LOTUS_L[bg_s_write]"
  local ok=1
  bg_worker refine --session $BG_SESSION --keep $BG_SESSION/keep.png || ok=0
  (( ok )) && bg_ui_complete
  bg_ui_end
  if (( ! ok )); then bg_error_screen "${BG_ERR[@]}"; ui_dim "  $LOTUS_L[back]"; ui_key; return 1; fi
  return 0
}

bg_batch_summary() {
  local -i n=$1 i ok=$(( ${#BG_DONE} / 3 ))
  local -F secs=0
  for (( i = 3; i <= ${#BG_DONE}; i += 3 )); do (( secs += BG_DONE[i] )); done
  if ! [[ -t 1 ]]; then
    for (( i = 2; i <= ${#BG_DONE}; i += 3 )); do print -r -- $BG_DONE[i]; done
    for (( i = 1; i <= ${#BG_SKIP}; i += 2 )); do print -r -- "skipped: $BG_SKIP[i] – $BG_SKIP[i+1]" >&2; done
    return 0
  fi
  local k=$'\e['"$LOTUS_C[key]m" d=$'\e['"$LOTUS_C[dim]m"
  ui_hero $LOTUS_L[bg_batch_title] "$ok / $n · $(printf '%.1f' $secs)s · ${BG_INFO[model]} · ${BG_INFO[backend]}"
  for (( i = 1; i <= ${#BG_DONE}; i += 3 )); do
    print -r -- "    ${k}✓${_UI_R} ${(r:28:)${BG_DONE[i]:t}[1,28]} ${d}→${_UI_R} ${BG_DONE[i+1]:t}"
  done
  for (( i = 1; i <= ${#BG_SKIP}; i += 2 )); do
    print -r -- "    "$'\e[1;'"$LOTUS_C[key2]m!${_UI_R} ${(r:28:)${BG_SKIP[i]:t}[1,28]} ${d}${BG_SKIP[i+1]}${_UI_R}"
  done
  if (( ${#BG_ERR} )); then ui_blank; bg_error_screen "${BG_ERR[@]}"; fi
  ui_blank
  if (( ok )); then
    ui_path ${BG_DONE[2]:h}; ui_kv $LOTUS_L[bg_i_output] $REPLY
    ui_blank
    print -r -- "    ${k}f${_UI_R} ${LOTUS_L[bg_k_finder]}   ${k}q${_UI_R} ${LOTUS_L[bg_k_done]}"
    ui_has_tty || return 0
    ui_keyx
    [[ $REPLY == (f|F) ]] && open -- ${BG_DONE[2]:h}
  fi
  ui_blank
}
