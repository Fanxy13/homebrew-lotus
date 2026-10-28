# lotus – /img convert: images and whole folders into PNG, JPEG, HEIC, AVIF, WebP, TIFF, GIF, BMP, PDF or ICO.
#   /img convert                                drop images or a folder into the window (an empty ⏎ takes the clipboard)
#   /img convert <image|folder>… [--to <format>] [--quality <1–100>] [--max <pixels>]
#   /img formats                                what this Mac reads and writes
# With Apple's ImageIO (lib/img/Convert.swift, built once): it reads what Preview reads – HEIC, WebP, RAW, PSD,
# SVG, JPEG XL … Photos come out the right way up, smaller but never larger, with their camera data. The originals
# are never changed: single images get a new file next to them, a folder gets a folder for the new format inside.
# Nothing is uploaded. Without the Command Line Tools it falls back to macOS' sips.

typeset -g LOTUS_LOG_COMP=img
typeset -g LOTUS_DOWNLOADS=${LOTUS_DOWNLOADS:-~/Downloads/Lotus}
typeset -ga IMG_EXT=(png jpg jpeg jpe heic heif heics avif webp gif tif tiff bmp psd jp2 j2k jxl svg tga exr ico icns
                     dng cr2 cr3 nef nrw arw raf orf rw2 pef srw 3fr iiq)
# key | label | file extension | type identifier | lossy | what it is good for
typeset -ga IMG_FORMATS=(
  "jpeg|JPEG|jpg|public.jpeg|1|small, for photos and everywhere – no transparency"
  "png|PNG|png|public.png|0|lossless, keeps transparency – screenshots, graphics"
  "heic|HEIC|heic|public.heic|1|about half the size of JPEG – iPhone, Mac"
  "avif|AVIF|avif|public.avif|1|the smallest – modern browsers and apps"
  "webp|WebP|webp|org.webmproject.webp|1|small, for websites – keeps transparency"
  "tiff|TIFF|tiff|public.tiff|0|lossless and large – for print and editing"
  "gif|GIF|gif|com.compuserve.gif|0|256 colors – simple graphics"
  "bmp|BMP|bmp|com.microsoft.bmp|0|uncompressed – old programs"
  "pdf|PDF|pdf|com.adobe.pdf|0|a page for each image – to send or print"
  "ico|ICO|ico|com.microsoft.ico|0|an icon for websites (favicon) – square, at most 256 px"
)
typeset -ga IMG_IN=() IMG_OUT=() IMG_FROM=()
typeset -gi IMG_STOP=0

lotus_cmd_img() {
  shift   # "img"
  case $1 in
    convert|conv|c) shift; img_convert "$@" ;;
    formats)        img_formats ;;
    ''|help|-h|--help) img_help ;;
    *)  if [[ -e ${1/#\~/$HOME} || $1 == file://* ]]; then img_convert "$@"
        else ui_error "Unknown: /img $1" "" "/img convert <image|folder>   ·   /img help"; return 1; fi ;;
  esac
}

img_help() {
  ui_hero "Image converter" "PNG, JPEG, HEIC, AVIF, WebP, PDF and more – on this Mac"
  local k=$'\e['"$LOTUS_C[key]m" d=$'\e['"$LOTUS_C[dim]m" r
  local -a rows=(
    "/img convert|drop images or a folder into the window – or ⏎ for the clipboard"
    "/img convert <image|folder>|one or more images, every image in a folder"
    "  --to <format>|jpeg png heic avif webp tiff gif bmp pdf ico – no questions"
    "  --quality <1–100>|for JPEG, HEIC, AVIF and WebP (85 when not given)"
    "  --max <pixels>|at most this wide and high – never larger"
    "/img formats|what this Mac reads and writes")
  for r in $rows; do print -r -- "    ${k}${(r:30:)${r%%|*}}${_UI_R}${r#*|}"; done
  ui_blank
  ui_section Examples; ui_blank
  print -r -- "    ${d}/img convert ~/Desktop/IMG_2041.HEIC --to jpeg${_UI_R}"
  print -r -- "    ${d}/img convert ~/Desktop/shoot --to webp --max 1920${_UI_R}"
  ui_blank
  ui_dim "  The originals stay as they are. A folder gets a folder for the new format inside it."
  ui_blank
}

# ── Formats ───────────────────────────────────────────────────

# A format by its key or extension → REPLY (its row in IMG_FORMATS), status 1 when there is none
img_format() {
  local f k=${(L)1#.}
  [[ $k == (jpg|jpe) ]] && k=jpeg
  [[ $k == tif ]] && k=tiff
  for f in $IMG_FORMATS; do [[ ${f%%|*} == $k ]] && { REPLY=$f; return 0 }; done
  return 1
}

# What this Mac can write → reply (keys of IMG_FORMATS): ImageIO's list (the converter and sips share it), WebP
# with cwebp
img_writable() {
  local types f
  types=$(sips --formats 2>/dev/null | awk '$3 == "Writable" { print $1 }')
  reply=()
  for f in $IMG_FORMATS; do
    local -a p=("${(@s:|:)f}")
    if [[ $p[1] == webp ]]; then (( $+commands[cwebp] )) || [[ $types == *org.webmproject.webp* ]] || continue
    else [[ $types == *$p[4]* ]] || continue; fi
    reply+=($p[1])
  done
}

img_formats() {
  ui_hero "Image converter" "What this Mac reads and writes"
  img_writable
  local f k=$'\e['"$LOTUS_C[key]m" d=$'\e['"$LOTUS_C[dim]m"
  ui_section Writes; ui_blank
  for f in $IMG_FORMATS; do
    local -a p=("${(@s:|:)f}")
    if (( ${reply[(Ie)$p[1]]} )); then print -r -- "    ${k}✓${_UI_R} ${(r:6:)p[2]} ${d}$p[6]${_UI_R}"
    elif [[ $p[1] == webp ]]; then print -r -- "    ${d}· ${(r:6:)p[2]} needs cwebp: brew install webp${_UI_R}"
    else print -r -- "    ${d}· ${(r:6:)p[2]} not on this macOS${_UI_R}"; fi
  done
  ui_blank
  ui_section Reads; ui_blank
  ui_dim "  JPEG, PNG, HEIC, AVIF, WebP, GIF, TIFF, BMP, PSD, SVG, JPEG XL, JPEG 2000, ICO, ICNS, EXR,"
  ui_dim "  and RAW photos (DNG, CR2, CR3, NEF, ARW, RAF, ORF, RW2 …) – what Preview opens"
  ui_blank
}

# The converter (lib/img/Convert.swift) once it is built → REPLY = its path; status 1 before (img_run builds it)
img_tool() {
  local sum=$(cksum < $LOTUS_ROOT/lib/img/Convert.swift)
  REPLY=$LOTUS_CACHE/bin/lotus-img-${sum%% *}
  [[ -x $REPLY ]]
}

# ── Images in ─────────────────────────────────────────────────

# Arguments → IMG_IN (images), IMG_FROM (the folder each came from, or "" for an image on its own, or "clipboard")
img_collect() {
  local -a in=("$@") found=()
  local -i i=1 j ok
  typeset -ga IMG_MISSING=()
  IMG_IN=() IMG_FROM=()
  while (( i <= ${#in} )); do
    ui_clean_path "${in[i]}"
    if [[ -e $REPLY ]]; then found+=($REPLY); (( i++ )); continue; fi
    ok=0
    for (( j = i + 1; j <= ${#in}; j++ )); do       # a path with spaces that was not quoted
      ui_clean_path "${(j: :)in[i,j]}"
      if [[ -e $REPLY ]]; then found+=($REPLY); (( i = j + 1 )); ok=1; break; fi
    done
    (( ok )) || { IMG_MISSING+=("${in[i]}"); (( i++ )) }
  done
  local p q
  for p in $found; do
    if [[ -d $p ]]; then
      for q in $p/*.(#i)(${(j:|:)~IMG_EXT})(N.on); do IMG_IN+=($q) IMG_FROM+=($p); done
    elif [[ $p == $LOTUS_CACHE/img/clipboard/* ]]; then IMG_IN+=($p) IMG_FROM+=(clipboard)
    else IMG_IN+=($p) IMG_FROM+=(""); fi
  done
}

# The drop zone: Finder types the path of what is dropped into the window, Lotus reads it without running anything
img_ask() {
  local -i W=${COLUMNS:-80}
  (( W > 20 )) || W=80
  if (( W >= 44 )); then ui_drop_zone $(( W - 8 > 60 ? 60 : W - 8 )) "Drop images or a folder here" "HEIC · PNG · JPEG · WebP · RAW · folders"
  else ui_text "Drag images or a folder into this window"; fi
  local clip
  clip=$(osascript -l JavaScript $LOTUS_ROOT/lib/bg/clipboard.js peek 2>/dev/null)
  [[ -n $clip ]] || clip=none
  if [[ $clip == image\ * ]]; then
    print -r -- "    "$'\e['"$LOTUS_C[key]m✓"$_UI_R" An image in the clipboard (${${clip#image }/x/ × }) – ⏎ takes it"
  elif [[ $clip == files\ * ]]; then
    print -r -- "    "$'\e['"$LOTUS_C[key]m✓"$_UI_R" ${clip#files } copied file(s) in the clipboard – ⏎ takes them"
  fi
  ui_dim "  Drop, then ⏎ · or type a path · esc and ⏎ goes back"
  ui_blank
  print -rn -- "    "$'\e['"$LOTUS_C[accent]m›"$_UI_R" "
  local line
  read -r line < /dev/tty || return 1
  [[ $line == $'\e'* ]] && return 1
  if [[ -z ${line//[[:space:]]/} ]]; then
    [[ $clip == none ]] && return 1
    local dir=$LOTUS_CACHE/img/clipboard stamp
    zf_mkdir -p $dir && chmod 700 $dir
    rm -f $dir/*(N.mh+24)
    strftime -s stamp '%Y-%m-%d %H.%M.%S' $EPOCHSECONDS
    reply=(${(f)"$(osascript -l JavaScript $LOTUS_ROOT/lib/bg/clipboard.js save "$dir/Clipboard $stamp.png" 2>/dev/null)"})
    reply=(${reply:#})
    (( ${#reply} ))
    return
  fi
  reply=(${(Q)${(z)line}})        # split like the shell would, quotes removed – nothing is expanded or run
  (( ${#reply} ))
}

# ── Where the new files go ────────────────────────────────────

# Next to an image on its own; a folder gets "<folder>/<Format>"; an image from the clipboard goes to Downloads/Lotus.
# Never over an original or another new file: "name (2).ext". → IMG_OUT
img_plan() {
  local ext=$1 label=$2 dir name try
  local -i i n
  local -A taken=()
  IMG_OUT=()
  for (( i = 1; i <= ${#IMG_IN}; i++ )); do
    case $IMG_FROM[i] in
      '')        dir=${IMG_IN[i]:h} ;;
      clipboard) dir=${LOTUS_DOWNLOADS/#\~/$HOME} ;;
      *)         dir=$IMG_FROM[i]/$label ;;
    esac
    name=${IMG_IN[i]:t:r}
    try=$dir/$name.$ext n=2
    while [[ -e $try || -n $taken[$try] ]]; do try="$dir/$name ($n).$ext"; (( n++ )); done
    taken[$try]=1
    IMG_OUT+=($try)
  done
}

# ── /img convert ──────────────────────────────────────────────

img_convert() {
  local to= quality= max= a
  local -a paths=()
  while (( $# )); do
    case $1 in
      --to|-t)      to=$2; shift 2 ;;
      --quality|-q) quality=$2; shift 2 ;;
      --max|-m)     max=$2; shift 2 ;;
      --to=*)       to=${1#*=}; shift ;;
      --quality=*)  quality=${1#*=}; shift ;;
      --max=*)      max=${1#*=}; shift ;;
      *)            paths+=("$1"); shift ;;
    esac
  done
  ui_hero "Image converter" "PNG, JPEG, HEIC, AVIF, WebP, PDF and more – on this Mac"
  if (( ! ${#paths} )); then
    ui_has_tty || { ui_error "Which images?" "" "/img convert <image|folder> --to <format>"; return 1 }
    img_ask || return 0
    paths=("${reply[@]}")
    ui_blank
  fi
  img_collect "${paths[@]}"
  for a in $IMG_MISSING; do ui_warn "Not found: $a"; done
  if (( ! ${#IMG_IN} )); then
    ui_error "No images to convert" "" "Images: ${(j:, :)${(U)IMG_EXT[1,12]}} … – or a folder with them"
    return 1
  fi
  # what came in
  local -A kinds=()
  local -i bytes=0 i
  local -a st
  for a in $IMG_IN; do
    if img_format ${a:e}; then (( kinds[${${(s:|:)REPLY}[2]}]++ )); else (( kinds[${(U)a:e}]++ )); fi
    zstat -A st +size -- $a 2>/dev/null && (( bytes += st[1] ))
  done
  local what=
  for a in ${(k)kinds}; do what+="${what:+ · }$a $kinds[$a]"; done
  local -a folders=(${(u)IMG_FROM:#(|clipboard)})
  local where=
  (( ${#folders} == 1 )) && where=" in ${folders[1]:t}"
  print -r -- "  "$'\e[1;'"$LOTUS_C[key]m✓"$_UI_R" ${#IMG_IN} image${${#IMG_IN:#1}:+s}$where  "$'\e['"$LOTUS_C[dim]m($what · $(img_mb $bytes))"$_UI_R
  ui_blank

  # the format
  img_writable
  local -a can=($reply)
  local row last
  [[ -r $LOTUS_STATE/img-last ]] && last=$(<$LOTUS_STATE/img-last)
  if [[ -n $to ]]; then
    img_format $to || { ui_error "Unknown format: $to" "" "Formats: ${(j: :)can}"; return 1 }
    (( ${can[(Ie)${REPLY%%|*}]} )) || { ui_error "This Mac cannot write ${(U)to}" "" "Formats here: ${(j: :)can}"; return 1 }
    row=$REPLY
  else
    ui_has_tty || { ui_error "Into which format?" "" "--to ${(j:|:)can}"; return 1 }
    local -a opts=() keys=()
    local f
    for f in $IMG_FORMATS; do
      local -a p=("${(@s:|:)f}")
      (( ${can[(Ie)$p[1]]} )) || continue
      opts+=("$p[2]|$p[6]") keys+=($p[1])
    done
    local -i sel=${keys[(Ie)${${last%%|*}:-jpeg}]}
    print -r -- "  ${_UI_B}Into which format?${_UI_R}"
    ui_select ${sel:-1} "${opts[@]}" || return 0
    img_format $keys[REPLY]; row=$REPLY
  fi
  local -a fmt=("${(@s:|:)row}")      # key label ext type lossy about

  # the quality, for formats that make files smaller by leaving details out
  if (( fmt[5] )) && [[ -z $quality ]]; then
    if ui_has_tty; then
      print -r -- "  ${_UI_B}Quality${_UI_R}"
      local -a qs=(95 85 70 50)
      local -i qsel=${qs[(Ie)${${(s:|:)last}[2]:-85}]}
      ui_select ${qsel:-2} "Best – 95|almost no difference to the original, larger files" "High – 85|the usual choice: looks the same, much smaller" \
        "Medium – 70|for the web and messages" "Small – 50|as small as possible – details get soft" || return 0
      quality=$qs[REPLY]
    else
      quality=85
    fi
  fi
  [[ -z $quality ]] || [[ $quality == <1-100> ]] || { ui_error "The quality is a number from 1 to 100" "$quality"; return 1 }
  (( fmt[5] )) || quality=0

  # the size
  if [[ $fmt[1] == ico ]]; then max=256
  elif [[ -z $max ]]; then
    if ui_has_tty; then
      print -r -- "  ${_UI_B}Size${_UI_R}"
      local -a ms=(0 3840 2560 1920 1280 640)
      local -i msel=${ms[(Ie)${${(s:|:)last}[3]:-0}]}
      ui_select ${msel:-1} "Keep the size|as large as the original" "4K|at most 3840 px wide and high" "2560 px|for large screens" \
        "Full HD|at most 1920 px – the web, presentations" "1280 px|for messages and mail" "640 px|thumbnails" || return 0
      max=$ms[REPLY]
    else
      max=0
    fi
  fi
  [[ $max == <-> ]] || { ui_error "The size is a number of pixels" "$max" "--max 1920"; return 1 }
  { zf_mkdir -p $LOTUS_STATE && print -r -- "$fmt[1]|${quality:-85}|$max" >| $LOTUS_STATE/img-last } 2>/dev/null

  img_plan $fmt[3] $fmt[2]
  local -a dirs=(${(u)${IMG_OUT:h}})
  for a in $dirs; do zf_mkdir -p $a 2>/dev/null || { ui_error "Cannot write to ${a/#$HOME/~}"; return 1 }; done
  lotus_log INFO img "${#IMG_IN} image(s) → $fmt[2] (quality $quality, max $max)"
  img_run $fmt[2] $fmt[4] $quality $max $bytes || return 1
  img_result $fmt[2] $bytes
}

img_mb() {   # <bytes> → "312 MB", "820 KB"
  if (( $1 < 1048576 )); then print -r -- "$(( ($1 + 512) / 1024 )) KB"
  else printf '%.1f MB\n' $(( $1 / 1048576.0 )); fi
}

# ── The work, while the lotus blooms ──────────────────────────

typeset -gi IMG_DONE=0 IMG_BYTES_OUT=0
typeset -ga IMG_FAIL=()

# All images, several at a time – the flower opens with the bytes that are done → IMG_DONE, IMG_FAIL, IMG_BYTES_OUT
img_run() {   # <label> <type> <quality> <max> <bytes in>
  local label=$1 type=$2 line
  local -i quality=$3 max=$4 total=$5 n=${#IMG_IN} fd more done_bytes=0 i rc
  local -a w st
  setopt localoptions localtraps
  source $LOTUS_ROOT/lib/bg/progress.zsh
  lotus_lang_group bg
  trap 'IMG_STOP=1' INT
  _bg_cancel() { IMG_STOP=1 BG_CANCEL=0 }
  IMG_STOP=0 IMG_DONE=0 IMG_BYTES_OUT=0 IMG_FAIL=() BG_CANCEL=0
  local -i jobs=$(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null || sysctl -n hw.physicalcpu 2>/dev/null || print 4)
  (( jobs < 2 )) && jobs=2
  (( jobs > 8 )) && jobs=8
  local -a stages=()
  img_tool || stages+=("build|Getting the converter ready (once)|Ready")
  stages+=("convert|Converting ${n} image${${n:#1}:+s} to $label|$label")
  bg_ui_begin Images $stages
  bg_ui_info format "$label${${quality:#0}:+ · quality $quality}${${max:#0}:+ · at most $max px}"
  (( n > 1 )) && bg_ui_info jobs "$jobs at a time"
  # the converter, built once (about half a minute) – sips when it cannot be
  local tool=
  if img_tool; then tool=$REPLY
  else
    bg_ui_stage build
    bg_ui_note "With Apple's Swift – the next time it is ready at once"
    lotus_swift_build lotus-img $LOTUS_ROOT/lib/img/Convert.swift > /dev/null 2>&1 &
    local -i bpid=$!
    while kill -0 $bpid 2>/dev/null && (( ! IMG_STOP )); do bg_ui_frame; bg_ui_tick 8; done
    wait $bpid 2>/dev/null
    img_tool && tool=$REPLY
    (( IMG_STOP )) && { bg_ui_end; ui_info "Stopped – nothing was converted."; return 1 }
  fi
  bg_ui_stage convert
  bg_ui_progress 0 $total
  _BG_BUF=
  if [[ -n $tool ]]; then
    exec {fd}< <(for (( i = 1; i <= n; i++ )); do print -r -- "$IMG_IN[i]"$'\t'"$IMG_OUT[i]"$'\t'"$type"$'\t'"$quality"$'\t'"$max"; done |
                 LOTUS_CWEBP=${commands[cwebp]:-cwebp} $tool --jobs $jobs 2>/dev/null &
                 print -r -- "LOTUS-PID $!"; wait $!; print -r -- "LOTUS-EXIT $?")
  else
    exec {fd}< <(img_sips $type $quality $max; print -r -- "LOTUS-EXIT 0")
  fi
  local -i pid=0
  local -A sizes=()
  while :; do
    bg_read_lines $fd 0.08; more=$?
    for line in $reply; do
      w=(${=line})
      case $w[1] in
        LOTUS-PID)  pid=$w[2] ;;
        start)      bg_ui_sub "$w[2] / $n · ${IMG_IN[w[2]]:t}" ;;
        done)
          (( IMG_DONE++, done_bytes += w[3], IMG_BYTES_OUT += w[4] ))
          bg_ui_progress $done_bytes $total
          local dims="${w[5]/x/ × }"
          [[ $w[5] == $w[6] ]] || dims+=" → ${w[6]/x/ × }"
          bg_ui_note "${IMG_IN[w[2]]:t} · $dims · $(img_mb $w[3]) → $(img_mb $w[4])" ;;
        fail)
          IMG_FAIL+=("${IMG_IN[w[2]]:t} – ${w[3,-1]}")
          zstat -A st +size -- $IMG_IN[w[2]] 2>/dev/null && (( done_bytes += st[1] ))
          bg_ui_progress $done_bytes $total ;;
      esac
    done
    bg_ui_frame
    (( more == 0 && ! IMG_STOP )) || break
  done
  if (( IMG_STOP )); then
    (( pid )) && kill -TERM $pid 2>/dev/null
    exec {fd}<&-
    bg_ui_end
    # a stopped converter leaves only whole images – and maybe the half one it was writing
    for line in $IMG_OUT; do rm -f -- "$line.lotus-tmp" "$line.lotus-tmp.webp"; done
    lotus_log INFO img "Stopped after $IMG_DONE of $n"
    ui_info "Stopped – $IMG_DONE of $n converted, the rest was left out."
    return 1
  fi
  exec {fd}<&-
  bg_ui_complete
  bg_ui_end
  return 0
}

# Without the Command Line Tools: one image after another with sips (the orientation of photos is kept as a tag)
img_sips() {   # <type> <quality> <max>
  local type=$1 fmt in out
  local -i quality=$2 max=$3 i ww hh
  local -a args st
  fmt=${${type##*.}/microsoft./}
  case $type in
    public.jpeg) fmt=jpeg ;; public.png) fmt=png ;; public.heic) fmt=heic ;; public.avif) fmt=avif ;;
    public.tiff) fmt=tiff ;; com.compuserve.gif) fmt=gif ;; com.microsoft.bmp) fmt=bmp ;; com.adobe.pdf) fmt=pdf ;;
    com.microsoft.ico) fmt=ico ;; org.webmproject.webp) fmt=webp ;;
  esac
  for (( i = 1; i <= ${#IMG_IN}; i++ )); do
    in=$IMG_IN[i] out=$IMG_OUT[i]
    print -r -- "start $i"
    args=()
    if (( max )); then
      ww=$(sips -g pixelWidth -- $in 2>/dev/null | awk '/pixelWidth/ { print $2 }')
      hh=$(sips -g pixelHeight -- $in 2>/dev/null | awk '/pixelHeight/ { print $2 }')
      (( ww > max || hh > max )) && args+=(-Z $max)       # smaller, never larger
    fi
    if [[ $fmt == webp ]]; then
      sips -s format png $args -- $in --out $out.lotus-tmp.png >/dev/null 2>&1 &&
        cwebp -quiet -q ${quality:-85} $out.lotus-tmp.png -o $out.lotus-tmp >/dev/null 2>&1
      rm -f $out.lotus-tmp.png
    else
      (( quality )) && args+=(-s formatOptions $quality)
      sips -s format $fmt $args -- $in --out $out.lotus-tmp >/dev/null 2>&1
    fi
    if [[ -s $out.lotus-tmp ]] && zf_mv -f $out.lotus-tmp $out; then
      local -i a=0 b=0
      zstat -A st +size -- $in 2>/dev/null && a=$st[1]
      zstat -A st +size -- $out 2>/dev/null && b=$st[1]
      print -r -- "done $i $a $b ?x? ?x?"
    else
      rm -f $out.lotus-tmp
      print -r -- "fail $i sips could not convert it"
    fi
  done
}

# What came out, and where
img_result() {   # <label> <bytes in>
  local label=$1 a
  local -i bytes=$2 n=${#IMG_IN}
  local k=$'\e[1;'"$LOTUS_C[key]m" d=$'\e['"$LOTUS_C[dim]m" R=$_UI_R
  if (( IMG_DONE )); then
    local change=
    (( bytes > 0 && IMG_BYTES_OUT > 0 )) && change=" ($(( (IMG_BYTES_OUT - bytes) * 100 / bytes )) %)"
    [[ $change == " (-"* ]] || change=${change/\(/(+}
    print -r -- "  ${k}✓${R} ${IMG_DONE} image${${IMG_DONE:#1}:+s} → $label   ${d}$(img_mb $bytes) → $(img_mb $IMG_BYTES_OUT)$change${R}"
    local -a dirs=(${(u)${IMG_OUT:h}})
    if (( IMG_DONE == 1 && ${#IMG_OUT} == 1 )); then ui_dim "  Saved: ${IMG_OUT[1]/#$HOME/~}"
    elif (( ${#dirs} == 1 )); then ui_dim "  Saved in ${dirs[1]/#$HOME/~}"
    else
      ui_dim "  Saved in ${#dirs} places:"
      for a in ${dirs[1,4]}; do ui_dim "    ${a/#$HOME/~}"; done
      (( ${#dirs} > 4 )) && ui_dim "    … and $(( ${#dirs} - 4 )) more"
    fi
  fi
  if (( ${#IMG_FAIL} )); then
    ui_warn "${#IMG_FAIL} could not be converted:"
    for a in ${IMG_FAIL[1,8]}; do ui_dim "    $a"; done
    (( ${#IMG_FAIL} > 8 )) && ui_dim "    … and $(( ${#IMG_FAIL} - 8 )) more"
  fi
  lotus_log INFO img "Converted $IMG_DONE of $n to $label, ${#IMG_FAIL} failed"
  (( IMG_DONE )) || return 1
  lotus_pet_react done 2>/dev/null
  ui_has_tty || return 0
  ui_blank
  local first=
  for a in $IMG_OUT; do [[ -e $a ]] && { first=$a; break }; done
  [[ -n $first ]] && ui_confirm "Show ${${IMG_DONE:#1}:+them}${${IMG_DONE:#<2->}:+it} in Finder?" y && open -R -- "$first"
  return 0
}
