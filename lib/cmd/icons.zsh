# lotus – /icons: change the icon of the folders on your Desktop – one, a few or all of them
#   /icons                                      guided: choose the folders, drop a picture into the window, check, done
#   /icons <picture>                            the same with the picture already chosen
#   /icons set <picture> <folder…>|--all        without questions: this picture for these folders – a name on the Desktop, or a path
#   /icons reset [<folder…>|--all]              the normal icons again (without folders: choose them from a list)
#   /icons list                                 the folders on your Desktop, and which have a picture of their own
#   /icons check                                what it needs, and whether this computer has it
# What is inside a folder is never changed – only the picture of the folder. macOS keeps it in a hidden file called Icon in the
# folder (what Finder's "Get Info" does), GNOME, Cinnamon, MATE and XFCE in the attributes that GVfs keeps for the folder, KDE in a
# hidden .directory file. The system's part is in the platform layer (lotus_os_folder_icon_*); this file is the screens.

typeset -g LOTUS_LOG_COMP=icons
# What a picture may be called – the system decides in the end (macOS asks its image engine, Linux looks at the first bytes)
typeset -ga ICONS_EXT=(png jpg jpeg jpe heic heif avif gif tif tiff bmp icns webp svg ico)
typeset -ga ICONS_FOLDERS=() ICONS_PICS=() ICONS_MISSING=() ICONS_NOTDIR=()
typeset -g ICONS_WHY=
typeset -gi ICONS_DONE=0 ICONS_FAILED=0

lotus_cmd_icons() {
  shift   # "icons"
  case ${1:-} in
    '')                        if ui_has_tty && [[ -t 1 ]]; then icons_guided set; else icons_help; fi ;;
    set|change)                shift; icons_set_cmd "$@" ;;
    reset|undo|normal)         shift; icons_reset_cmd "$@" ;;
    list|ls)                   icons_list ;;
    check|needs|requirements)  icons_check ;;
    help|-h|--help)            icons_help ;;
    *)  # a picture on its own: /icons star.png – also a path with spaces that was typed without quotes (the words are joined)
        local -i k
        for (( k = 1; k <= $#; k++ )); do
          ui_clean_path "${(j: :)@[1,k]}"
          [[ -f $REPLY && ${ICONS_EXT[(Ie)${(L)REPLY:e}]} -gt 0 ]] && { icons_set_cmd "$@"; return }
        done
        ui_error "Unknown: /icons $1" "" "/icons   ·   /icons set <picture> <folders>   ·   /icons reset   ·   /icons check   ·   /icons help"
        return 1 ;;
  esac
}

icons_help() {
  ui_hero "Folder icons" "Change the icon of the folders on your Desktop – one, a few or all of them"
  local k=$'\e['"$LOTUS_C[key]m" d=$'\e['"$LOTUS_C[dim]m" r
  local -a rows=(
    "/icons|guided: choose the folders, drop a picture into the window, done"
    "/icons <picture>|the same with the picture already chosen"
    "/icons set <picture> <folders>|without questions – a folder is a name on the Desktop, or a path"
    "  --all|every folder on the Desktop"
    "/icons reset [<folders>]|the normal icons again – without folders: choose them from a list"
    "  --all|every folder on the Desktop that has a picture of its own"
    "/icons list|the folders on your Desktop, and which have a picture of their own"
    "/icons check|what it needs, and whether this computer has it")
  for r in $rows; do print -r -- "    ${k}${(r:32:)${r%%|*}}${_UI_R}${r#*|}"; done
  ui_blank
  ui_section "What it needs"; ui_blank
  case $LOTUS_OS in
    macos)
      ui_text "  macOS 11 or newer. Nothing to install, no administrator password."
      ui_text "  Your terminal must be allowed to use the Desktop folder – macOS asks once: choose Allow."
      ui_text "  A picture: PNG, JPEG, HEIC, ICNS, GIF or TIFF." ;;
    *)
      ui_text "  GNOME, Cinnamon, MATE, XFCE, Budgie: gio and GVfs – they come with the desktop."
      ui_text "  KDE Plasma, LXQt: nothing to install."
      ui_text "  A picture: PNG, JPEG, SVG or GIF; WebP, HEIC and TIFF with ImageMagick (optional)." ;;
  esac
  ui_dim "  /icons check shows what this computer has."
  ui_blank
  ui_section Examples; ui_blank
  print -r -- "    ${d}/icons${_UI_R}"
  print -r -- "    ${d}/icons ~/Pictures/star.png${_UI_R}"
  print -r -- "    ${d}/icons set ~/Pictures/star.png Projects Photos${_UI_R}"
  print -r -- "    ${d}/icons set ~/Pictures/star.png --all${_UI_R}"
  print -r -- "    ${d}/icons reset --all${_UI_R}"
  ui_blank
  ui_dim "  What is inside your folders stays as it is – only the picture of the folder changes. The original picture stays where it is."
  ui_blank
}

# Text in the window's width, every line indented: a long line that wraps on its own would start at the left edge
icons_wrap() {   # <indent> <text> [dim]
  local indent=$1 line= word
  local -a words=(${=2})
  local -i w=${COLUMNS:-80} max
  (( w > 30 )) || w=80
  (( max = w - ${#indent} - 2 ))
  local on= off=
  [[ $3 == dim ]] && { on=$'\e['"$LOTUS_C[dim]m"; off=$_UI_R }
  for word in $words; do
    if [[ -n $line ]] && (( ${#line} + ${#word} + 1 > max )); then print -r -- "$indent$on$line$off"; line=$word
    else line+="${line:+ }$word"; fi
  done
  [[ -n $line ]] && print -r -- "$indent$on$line$off"
  return 0
}

# ── What it needs ─────────────────────────────────────────────

# The list of what it needs, with a ✓ for what this computer has → status 0, or 1 when something is missing.
# A ! is something that is good to have; a ✗ has to be fixed first, and says how.
icons_needs() {
  local row mark label detail fix
  local -a f rows=()
  local -i W=${COLUMNS:-80} rc
  (( W > 40 )) || W=80
  lotus_os_folder_icon_needs; rc=$?
  rows=("${reply[@]}")
  lotus_os_folder_icon_types
  rows+=("ok|A picture|$REPLY|")
  local d=$'\e['"$LOTUS_C[dim]m"
  local -i lw=0 dw=0 wide
  for row in "${rows[@]}"; do
    f=("${(@s:|:)row}")
    (( ${#f[2]} > lw )) && lw=${#f[2]}
    (( ${#f[3]} > dw )) && dw=${#f[3]}
  done
  (( wide = lw + dw + 10 <= W ))        # the details in a column next to the labels – or under them when the window is narrow
  ui_section "What it needs"; ui_blank
  for row in "${rows[@]}"; do
    f=("${(@s:|:)row}")
    label=$f[2] detail=$f[3] fix=$f[4]
    case $f[1] in
      ok)   mark=$'\e[1;'"$LOTUS_C[key]m✓"$_UI_R ;;
      warn) mark=$'\e[1;'"$LOTUS_C[key2]m!"$_UI_R ;;
      *)    mark=$'\e[1;38;5;203m✗'$_UI_R ;;
    esac
    if (( wide )); then
      print -r -- "    $mark ${(r:lw:)label}${detail:+  ${d}$detail${_UI_R}}"
    else
      print -r -- "    $mark $label"
      [[ -n $detail ]] && icons_wrap "      " "$detail" dim
    fi
    [[ $f[1] != ok && -n $fix ]] && icons_wrap "      " "$fix" dim
  done
  return rc
}

icons_check() {
  ui_hero "Folder icons" "What it needs, and whether $LOTUS_THIS has it"
  if icons_needs; then
    ui_blank
    ui_success "Ready – run /icons"
    ui_blank
  else
    ui_blank
    ui_dim "  Fix what is marked ✗, then run /icons check again."
    ui_blank
    return 1
  fi
}

# ── Folders and pictures ──────────────────────────────────────

# The folders on the Desktop → reply (absolute paths, by name): no hidden ones, no links, no packages that look like one file
icons_desktop_folders() {
  setopt localoptions extendedglob
  reply=()
  lotus_os_desktop || return 1
  local p
  local -a found=()
  for p in $REPLY/*(N/); do
    [[ ${p:t} == *.(#i)(app|bundle|framework|photoslibrary|rtfd|xcodeproj|xcworkspace|playground|sparsebundle) ]] && continue
    found+=($p)
  done
  reply=(${(oi)found})
  (( ${#reply} ))
}

# What was typed, dropped or given → reply (absolute paths) and ICONS_MISSING (what is not there). A bare name is looked for in
# the base folder first (Projects → ~/Desktop/Projects), then as a path; a path with spaces that was not quoted is put together
# again from its words, the way the Finder types it into a window that does not quote it.
icons_paths() {   # <base folder or ""> <words…>
  local base=$1 t; shift
  local -a in=("$@") found=()
  local -i i=1 j ok
  ICONS_MISSING=()
  while (( i <= ${#in} )); do
    ok=0
    for (( j = i; j <= ${#in}; j++ )); do
      t=${(j: :)in[i,j]}
      if [[ -n $base && $t != */* && $t != \~* && $t != file://* && -e $base/$t ]]; then found+=(${base:a}/$t)   # (written as a typed path is: no //, so that one folder is one entry)
      else
        ui_clean_path "$t"
        [[ -e $REPLY ]] || continue
        found+=($REPLY)
      fi
      (( i = j + 1, ok = 1 ))
      break
    done
    (( ok )) || { ICONS_MISSING+=("${in[i]}"); (( i++ )) }
  done
  reply=("${found[@]}")
}

# Words → ICONS_FOLDERS (folders, each once) and ICONS_MISSING / ICONS_NOTDIR (what is not there, what is not a folder)
icons_folders_from() {
  local desk= p
  lotus_os_desktop && desk=$REPLY
  icons_paths "$desk" "$@"
  local -a paths=("${reply[@]}")
  ICONS_FOLDERS=() ICONS_NOTDIR=()
  for p in $paths; do
    if [[ -d $p ]]; then ICONS_FOLDERS+=($p); else ICONS_NOTDIR+=($p); fi
  done
  ICONS_FOLDERS=(${(u)ICONS_FOLDERS})
}

# Can this file be an icon? → status 0, or 1 with the reason in ICONS_WHY
icons_picture_ok() {
  local p=$1
  local -a st
  ICONS_WHY=
  if   [[ ! -e $p ]];  then ICONS_WHY="it is not there"
  elif [[ -d $p ]];    then ICONS_WHY="it is a folder – a picture is a file"
  elif [[ ! -r $p ]];  then ICONS_WHY="it cannot be read"
  elif (( ! ${ICONS_EXT[(Ie)${(L)p:e}]} )); then ICONS_WHY="it is not a picture file (PNG, JPEG, HEIC, GIF, SVG …)"
  elif ! zstat -A st +size -- $p 2>/dev/null || (( st[1] == 0 )); then ICONS_WHY="the file is empty"
  elif (( st[1] > 104857600 )); then ICONS_WHY="the file is over 100 MB"
  fi
  [[ -z $ICONS_WHY ]]
}

# How many things a folder holds, for the list: "12 items", "empty", plus "has a picture of its own"
icons_folder_note() {   # <folder> → REPLY
  local -a items=($1/*(N))
  items=(${items:#*/Icon$'\r'})              # (macOS keeps the picture in a hidden file called Icon: not one of the folder's own)
  local note
  if   (( ! ${#items} ));      then note=empty
  elif (( ${#items} == 1 ));   then note="1 item"
  else                              note="${#items} items"; fi
  lotus_os_folder_icon_has $1 && note+=" · has a picture of its own"
  REPLY=$note
}

# One picture for every folder of ICONS_FOLDERS → ICONS_PICS
icons_same_picture() {   # <picture>
  local -i i
  ICONS_PICS=()
  for (( i = 1; i <= ${#ICONS_FOLDERS}; i++ )); do ICONS_PICS+=($1); done
}

icons_list() {
  local where
  lotus_os_desktop; where="${REPLY/#$HOME/~}"
  ui_hero "Folder icons" "The folders on your Desktop${where:+ – $where}"
  if ! icons_desktop_folders; then
    ui_info "No folders on your Desktop"
    ui_blank
    return 0
  fi
  local p d=$'\e['"$LOTUS_C[dim]m"
  for p in "${reply[@]}"; do
    icons_folder_note $p
    print -r -- "    ${(r:26:)${p:t}[1,26]} ${d}$REPLY${_UI_R}"
  done
  ui_blank
}

# ── The screens ───────────────────────────────────────────────

icons_cancel() { ui_blank; ui_dim "  Nothing was changed."; ui_blank; return 0 }

# The drop zone: Finder types the path of what is dropped into the window, Lotus reads it without running anything
#   icons_drop <title> <types> <a line of what to do>… → reply (the words)   status 1: back (Esc, q) · 2: nothing was typed
icons_drop() {
  local title=$1 types=$2 line hint
  local -i W=${COLUMNS:-80}
  (( W > 20 )) || W=80
  shift 2
  if (( W >= 44 )); then ui_drop_zone $(( W - 8 > 60 ? 60 : W - 8 )) $title $types
  else ui_text $title; fi
  for hint in "$@"; do icons_wrap "  " "$hint" dim; done
  ui_blank
  ui_has_tty || return 1                       # (no keyboard: nobody can answer)
  print -rn -- "    "$'\e['"$LOTUS_C[accent]m›"$_UI_R" "
  read -r line < /dev/tty || return 1
  [[ $line == $'\e'* || ${(L)${line//[[:space:]]/}} == (q|quit|back|exit|cancel) ]] && return 1
  [[ -z ${line//[[:space:]]/} ]] && return 2
  reply=(${(Q)${(z)line}})        # split like the shell would, quotes removed – nothing is expanded or run
  (( ${#reply} )) || return 2
}

# Step 1 – the folders → ICONS_FOLDERS · status 1: back
icons_ask_folders() {   # <set|reset>
  local mode=$1 p note m
  local -a desk=() opts=() acts=() own=()
  local -i n i
  icons_desktop_folders && desk=("${reply[@]}")
  n=${#desk}
  for p in $desk; do lotus_os_folder_icon_has $p && own+=($p); done
  print -r -- "  ${_UI_B}Step 1 of 3 · Which folders?${_UI_R}"
  if [[ $mode == reset ]]; then
    if (( ${#own} > 1 )); then opts+=("All ${#own} folders that have a picture of their own|on the Desktop") acts+=(own)
    elif (( ${#own} == 1 )); then opts+=("${own[1]:t}|the one folder on the Desktop that has a picture of its own") acts+=(own)
    else ui_dim "  None of the folders on your Desktop has a picture of its own."; fi
    (( n )) && opts+=("Choose which ones|a list of the folders on your Desktop") acts+=(choose)
  else
    if (( n > 1 )); then opts+=("All $n folders on the Desktop|every folder you see there") acts+=(all)
    elif (( n == 1 )); then opts+=("${desk[1]:t}|the one folder on the Desktop") acts+=(all); fi
    (( n > 1 )) && opts+=("Choose which ones|a list of the folders on your Desktop") acts+=(choose)
  fi
  opts+=("Other folders|drop folders from anywhere into the window") acts+=(other)
  (( ! n )) && [[ $mode == set ]] && ui_dim "  There are no folders on your Desktop – drop the folders you want to change."
  while :; do
    if (( ${#opts} == 1 )); then REPLY=1
    else ui_select 1 "${opts[@]}" || return 1; fi
    case $acts[REPLY] in
      all)    ICONS_FOLDERS=("${desk[@]}"); return 0 ;;
      own)    ICONS_FOLDERS=("${own[@]}"); return 0 ;;
      choose) icons_toggle_folders $mode "${desk[@]}" && return 0 ;;
      other)
        while :; do
          icons_drop "Drop folders here" "one or several · from anywhere" "Drag the folders from ${LOTUS_FILES_APP} into this window, then press ⏎." "Or type a path. q goes back."
          case $? in
            1) (( ${#opts} == 1 )) && return 1        # nothing to go back to: leave
               break ;;
            2) ui_dim "  Drop a folder first – or type q to go back."; continue ;;
          esac
          icons_folders_from "${reply[@]}"
          for m in $ICONS_MISSING; do ui_warn "Not found: $m"; done
          for m in $ICONS_NOTDIR; do ui_warn "Not a folder: ${m:t}"; done
          (( ${#ICONS_FOLDERS} )) && return 0
        done ;;
    esac
  done
}

# The folders of the Desktop as a list to tick: Space ticks, A ticks all, ⏎ continues → ICONS_FOLDERS · status 1: back
icons_toggle_folders() {   # <set|reset> <folders…>
  local mode=$1 p; shift
  local -a folders=("$@") opts=()
  local -i i
  typeset -ga LOTUS_TOGGLES=()
  for p in $folders; do
    icons_folder_note $p
    opts+=("${p:t}|$REPLY")
    # to give the normal icon back, the folders that have a picture of their own start ticked
    [[ $mode == reset && $REPLY == *"of its own"* ]] && LOTUS_TOGGLES+=(1) || LOTUS_TOGGLES+=(0)
  done
  while :; do
    ui_has_tty || return 1
    ui_dim "  Tick the folders with Space – A ticks all of them."
    ui_toggles "${opts[@]}" || return 1
    ICONS_FOLDERS=()
    for (( i = 1; i <= ${#folders}; i++ )); do (( LOTUS_TOGGLES[i] )) && ICONS_FOLDERS+=($folders[i]); done
    (( ${#ICONS_FOLDERS} )) && return 0
    ui_warn "No folder is ticked – press Space on the ones you want."
  done
}

# Step 2 – the picture(s) → ICONS_PICS, one for each of ICONS_FOLDERS (empty: this folder is left as it is) · status 1: back
icons_ask_pictures() {
  local -i n=${#ICONS_FOLDERS} i
  local types pic first
  lotus_os_folder_icon_types; types=$REPLY
  local each=0
  ICONS_PICS=()
  print -r -- "  ${_UI_B}Step 2 of 3 · The picture${_UI_R}"
  if (( n > 1 )); then
    ui_dim "  One picture for all $n folders, or a different one for each?"
    ui_select 1 "The same picture for all $n folders|you drop one picture" "A different picture for each folder|you drop one picture per folder" || return 1
    (( REPLY == 2 )) && each=1
  fi
  if (( ! each )); then
    while :; do
      icons_drop "Drop the picture here" "$types" "Drag the picture from ${LOTUS_FILES_APP} into this window, then press ⏎." "Or type its path. q goes back."
      case $? in 1) return 1 ;; 2) ui_dim "  Drop a picture first – or type q to go back."; continue ;; esac
      icons_paths "" "${reply[@]}"
      (( ${#reply} > 1 )) && ui_dim "  ${#reply} pictures dropped – the first one is used."
      pic=${reply[1]}
      if [[ -z $pic ]]; then ui_warn "Not found: ${ICONS_MISSING[1]}"; continue; fi
      icons_picture_ok $pic || { ui_warn "${pic:t}: $ICONS_WHY"; continue }
      icons_same_picture $pic
      return 0
    done
  fi
  for (( i = 1; i <= n; i++ )); do
    while :; do
      ui_dim "  Folder $i of $n"
      icons_drop "Drop the picture for “${ICONS_FOLDERS[i]:t}”" "$types" "Drag the picture from ${LOTUS_FILES_APP} into this window, then press ⏎." "⏎ alone leaves this folder as it is. q goes back."
      case $? in
        1) return 1 ;;
        2) ICONS_PICS+=(""); break ;;
      esac
      icons_paths "" "${reply[@]}"
      pic=${reply[1]}
      if [[ -z $pic ]]; then ui_warn "Not found: ${ICONS_MISSING[1]}"; continue; fi
      icons_picture_ok $pic || { ui_warn "${pic:t}: $ICONS_WHY"; continue }
      ICONS_PICS+=($pic)
      break
    done
  done
  first=${(M)ICONS_PICS:#?*}
  [[ -n $first ]] || { ui_warn "No picture was dropped."; return 1 }
}

# Step 3 – what will happen, and the question → status 0: go
icons_confirm() {   # <set|reset>
  local mode=$1 d=$'\e['"$LOTUS_C[dim]m" name pic
  local -i n=${#ICONS_FOLDERS} i shown=0 todo=0
  print -r -- "  ${_UI_B}Step 3 of 3 · Check${_UI_R}"
  ui_blank
  for (( i = 1; i <= n; i++ )); do
    name=${ICONS_FOLDERS[i]:t}
    if [[ $mode == set ]]; then
      pic=$ICONS_PICS[i]
      [[ -n $pic ]] || continue
    fi
    (( todo++ ))
    (( shown >= 8 )) && continue
    (( shown++ ))
    if [[ $mode == set ]]; then print -r -- "    ${(r:24:)${name[1,24]}} ${d}→${_UI_R} ${pic:t}"
    else print -r -- "    ${name}"; fi
  done
  (( todo > shown )) && ui_dim "    … and $(( todo - shown )) more"
  ui_blank
  if [[ $mode == set ]]; then ui_confirm "Change the icon of $todo folder${${todo:#1}:+s}?" y
  else ui_confirm "Give $todo folder${${todo:#1}:+s} the normal icon back?" y; fi
}

# ── Doing it ──────────────────────────────────────────────────

# This system cannot do it at all (status 2 of the platform layer): say what is missing
icons_not_here() {
  ui_error "Folder icons do not work here yet" "$LOTUS_THIS is missing something this needs."
  icons_needs
  ui_blank
}

# ICONS_FOLDERS (and ICONS_PICS) → the icons are changed, one folder after the other → ICONS_DONE, ICONS_FAILED · status 1: not all
icons_apply() {   # <set|reset>
  local mode=$1 f name pic
  local -i i rc skipped=0
  local -A said=()
  local d=$'\e['"$LOTUS_C[dim]m"
  ICONS_DONE=0 ICONS_FAILED=0
  for (( i = 1; i <= ${#ICONS_FOLDERS}; i++ )); do
    f=$ICONS_FOLDERS[i] name=${ICONS_FOLDERS[i]:t}
    if [[ $mode == set ]]; then
      pic=$ICONS_PICS[i]
      [[ -n $pic ]] || { (( skipped++ )); continue }
      if [[ ! -d $f ]]; then LOTUS_OS_MSG=("Not a folder" "" ""); rc=1
      else lotus_os_folder_icon_set $f $pic; rc=$?; fi
    else
      if [[ ! -d $f ]]; then LOTUS_OS_MSG=("Not a folder" "" ""); rc=1
      else lotus_os_folder_icon_reset $f; rc=$?; fi
    fi
    case $rc in
      0) (( ICONS_DONE++ )); print -r -- "  "$'\e[1;'"$LOTUS_C[key]m✓"$_UI_R" $name" ;;
      2) icons_not_here; ICONS_FAILED=${#ICONS_FOLDERS}; return 1 ;;
      *) (( ICONS_FAILED++ ))
         print -r -- "  "$'\e[1;38;5;203m✗'$_UI_R" $name – ${LOTUS_OS_MSG[1]:-it did not work}"
         if [[ -z $said[${LOTUS_OS_MSG[1]}] ]]; then
           said[${LOTUS_OS_MSG[1]}]=1
           [[ -n ${LOTUS_OS_MSG[2]} ]] && print -r -- "      ${d}${LOTUS_OS_MSG[2]}${_UI_R}"
           [[ -n ${LOTUS_OS_MSG[3]} ]] && print -r -- "      ${d}${LOTUS_OS_MSG[3]}${_UI_R}"
         fi
         lotus_log WARN icons "${mode}: ${LOTUS_OS_MSG[1]:-failed}" ;;
    esac
  done
  ui_blank
  local what="$ICONS_DONE folder${${ICONS_DONE:#1}:+s}"
  if [[ $mode == set ]]; then
    (( ICONS_DONE )) && ui_success "$what ${${ICONS_DONE:#1}:+have}${${ICONS_DONE:#<2->}:+has} a new icon${${skipped:#0}:+ ($skipped left as they were)}"
  else
    (( ICONS_DONE )) && ui_success "$what ${${ICONS_DONE:#1}:+have}${${ICONS_DONE:#<2->}:+has} the normal icon again"
  fi
  (( ICONS_FAILED )) && ui_warn "${ICONS_FAILED} folder${${ICONS_FAILED:#1}:+s} could not be changed"
  lotus_log INFO icons "$mode: $ICONS_DONE done, $ICONS_FAILED failed, $skipped left out"
  if (( ICONS_DONE )); then
    if [[ $mode == set ]]; then ui_dim "  The normal icons are back any time: /icons reset"; fi
    [[ $LOTUS_OS == linux ]] && ui_dim "  A window that is open shows the change after you open the folder again."
    ui_blank
    lotus_pet_react done 2>/dev/null
  fi
  (( ICONS_FAILED == 0 && ICONS_DONE > 0 ))
}

# ── The commands ──────────────────────────────────────────────

# /icons, /icons <picture>, /icons reset – with questions, in a terminal
icons_guided() {   # <set|reset> [picture]
  local mode=$1 pic=${2:-}
  if [[ $mode == set ]]; then ui_hero "Folder icons" "Give the folders on your Desktop a new icon – one, a few or all of them"
  else ui_hero "Folder icons" "Give the folders on your Desktop their normal icon back"; fi
  icons_wrap "  " "What is inside your folders stays as it is – only the picture of the folder changes." dim
  ui_blank
  icons_needs || { ui_blank; ui_dim "  Fix what is marked ✗, then run /icons again."; ui_blank; return 1 }
  ui_blank
  if [[ $mode == set ]]; then
    ui_section "How it works"; ui_blank
    print -r -- "    1  Choose the folders – one, a few or all of them"
    if [[ -n $pic ]]; then print -r -- "    2  The picture: ${pic:t}"; else print -r -- "    2  Drop a picture into this window"; fi
    print -r -- "    3  Check it and press ⏎"
    ui_blank
  fi
  icons_ask_folders $mode || { icons_cancel; return 0 }
  ui_blank
  if [[ $mode == set ]]; then
    if [[ -n $pic ]]; then icons_same_picture $pic
    else
      icons_ask_pictures || { icons_cancel; return 0 }
      ui_blank
    fi
  fi
  icons_confirm $mode || { icons_cancel; return 0 }
  ui_blank
  icons_apply $mode
}

# /icons set <picture> <folders…>|--all
icons_set_cmd() {
  local w all=0
  local -a words=()
  for w in "$@"; do
    case $w in --all|-a) all=1 ;; *) words+=("$w") ;; esac
  done
  if (( ! ${#words} )); then
    ui_error "Which picture?" "" "/icons set <picture> <folders>   ·   /icons set <picture> --all   ·   /icons <picture>"
    return 1
  fi
  local desk= pic
  lotus_os_desktop && desk=$REPLY
  icons_paths "$desk" "${words[@]}"
  local -a paths=("${reply[@]}")
  for w in $ICONS_MISSING; do ui_warn "Not found: $w"; done
  (( ${#paths} )) || { ui_error "No picture found" "" "/icons set <picture> <folders>"; return 1 }
  pic=$paths[1]
  icons_picture_ok $pic || { ui_error "${pic:t} cannot be an icon" "$ICONS_WHY" "A picture: $(lotus_os_folder_icon_types; print -r -- $REPLY)"; return 1 }
  paths=("${paths[@]:1}")
  ICONS_FOLDERS=() ICONS_NOTDIR=()
  local p
  for p in $paths; do [[ -d $p ]] && ICONS_FOLDERS+=($p) || ICONS_NOTDIR+=($p); done
  for p in $ICONS_NOTDIR; do ui_warn "Not a folder: ${p:t}"; done
  if (( all )); then
    icons_desktop_folders || { ui_error "No folders on your Desktop" "" "Name the folders: /icons set <picture> <folders>"; return 1 }
    ICONS_FOLDERS+=("${reply[@]}")
  fi
  ICONS_FOLDERS=(${(u)ICONS_FOLDERS})
  if (( ! ${#ICONS_FOLDERS} )); then
    if ui_has_tty && [[ -t 1 ]]; then icons_guided set $pic; return; fi
    ui_error "Which folders?" "" "/icons set ${pic:t} <folders>   ·   /icons set ${pic:t} --all"
    return 1
  fi
  icons_same_picture $pic
  icons_apply set
}

# /icons reset [<folders…>|--all]
icons_reset_cmd() {
  local w all=0 p
  local -a words=()
  for w in "$@"; do
    case $w in --all|-a) all=1 ;; *) words+=("$w") ;; esac
  done
  ICONS_FOLDERS=()
  if (( ${#words} )); then
    icons_folders_from "${words[@]}"
    for w in $ICONS_MISSING; do ui_warn "Not found: $w"; done
    for p in $ICONS_NOTDIR; do ui_warn "Not a folder: ${p:t}"; done
  fi
  if (( all )); then
    icons_desktop_folders || { ui_error "No folders on your Desktop" "" "Name the folders: /icons reset <folders>"; return 1 }
    for p in "${reply[@]}"; do lotus_os_folder_icon_has $p && ICONS_FOLDERS+=($p); done
    ICONS_FOLDERS=(${(u)ICONS_FOLDERS})
    if (( ! ${#ICONS_FOLDERS} && ! ${#words} )); then ui_info "None of the folders on your Desktop has a picture of its own."; return 0; fi
  fi
  if (( ! ${#ICONS_FOLDERS} )); then
    if (( ${#words} )); then return 1; fi
    if ui_has_tty && [[ -t 1 ]]; then icons_guided reset; return; fi
    ui_error "Which folders?" "" "/icons reset <folders>   ·   /icons reset --all"
    return 1
  fi
  icons_apply reset
}
