# lotus – /img edit: one picture in the image editor, in the browser (lib/edit/editor.py and the page in lib/edit/web).
#   /img                       the editor: drop a picture into the window (an empty ⏎ takes the clipboard)
#   /img edit <image>          the editor for this picture
# This file is only the glue of macOS and Linux: it finds the picture, makes sure the system's image engine is there
# (macOS: lotus-img, built once; Linux: ImageMagick) and starts the server – the editor itself (the page, the server, the
# geometry of the crop) is the same on every system and knows no operating system. Windows has its own glue
# (win/Public/img.ps1) and starts the same server.

img_edit() {
  local a
  ui_hero "Image editor" "Crop, straighten and convert – in your browser, on $LOTUS_THIS"

  # Python 3 (the server is its standard library, nothing to install)
  if (( ! $+commands[python3] )); then
    lotus_pkg_hint python3
    [[ $LOTUS_OS == macos ]] && REPLY="xcode-select --install   (Apple's Command Line Tools bring it)"
    ui_error "The editor needs Python 3" "" "$REPLY"
    return 1
  fi

  # the picture
  local -a paths=("$@")
  if (( ! ${#paths} )); then
    ui_has_tty || { ui_error "Which picture?" "" "/img edit <picture>"; return 1 }
    img_ask edit || return 0
    paths=("${reply[@]}")
    ui_blank
  fi
  img_collect "${paths[@]}"
  for a in $IMG_MISSING; do ui_warn "Not found: $a"; done
  if (( ! ${#IMG_IN} )); then
    ui_error "No picture to edit" "" "Pictures: ${(j:, :)${(U)IMG_EXT[1,12]}} …"
    return 1
  fi
  local -a folders=(${(u)IMG_FROM:#(|clipboard)})
  if (( ${#folders} )); then
    ui_error "The editor opens one picture at a time" "" "A whole folder: /img convert <folder>"
    return 1
  fi
  (( ${#IMG_IN} > 1 )) && ui_dim "  ${#IMG_IN} pictures – the editor opens the first, ${IMG_IN[1]:t}. All of them at once: /img convert"

  # the image engine of this system
  local tool=
  if [[ $LOTUS_OS == macos ]]; then
    if ! img_tool; then
      ui_step "Getting the converter ready – once, about half a minute"
      lotus_swift_build lotus-img $LOTUS_ROOT/lib/img/Convert.swift > /dev/null 2>&1 ||
        { ui_error "The editor needs Apple's Command Line Tools" "" "xcode-select --install"; return 1 }
      ui_blank
    fi
    img_tool; tool=$REPLY
  elif (( ! $+commands[magick] && ! ($+commands[convert] && $+commands[identify]) )); then
    lotus_pkg_hint magick
    ui_error "The editor needs ImageMagick" "" "$REPLY"
    return 1
  fi

  # a picture from the clipboard has no folder: the new one goes to Downloads/Lotus
  local image=$IMG_IN[1] downloads=${LOTUS_DOWNLOADS/#\~/$HOME} outdir=
  [[ $IMG_FROM[1] == clipboard ]] && outdir=$downloads
  zf_mkdir -p $LOTUS_CACHE/img 2>/dev/null
  lotus_log INFO img "editor: ${image:t}"
  env PYTHONDONTWRITEBYTECODE=1 LOTUS_IMG_TOOL=$tool LOTUS_CWEBP=${commands[cwebp]:-} \
    LOTUS_LANG=$LOTUS_LANG LOTUS_THIS=$LOTUS_THIS LOTUS_FILES_APP=$LOTUS_FILES_APP \
    LOTUS_EDIT_DATA=$LOTUS_CACHE/img/edit LOTUS_IMG_LAST=$LOTUS_STATE/img-last LOTUS_DOWNLOADS=$downloads \
    LOTUS_COLOR_KEY=$LOTUS_C[key] LOTUS_COLOR_ACCENT=$LOTUS_C[accent] LOTUS_COLOR_DIM=$LOTUS_C[dim] \
    python3 -B $LOTUS_ROOT/lib/edit/editor.py "$image" ${outdir:+--out-dir "$outdir"}
  local -i rc=$?
  (( rc == 130 )) && rc=0                  # Ctrl-C is how it is closed, not a failure
  lotus_log INFO img "editor closed ($rc)"
  return $rc
}
