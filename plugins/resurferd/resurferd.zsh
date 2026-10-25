# Subway Surfers Resurferd on this Mac – a plugin for Lotus with full access (plugin.conf).
#   lotus surf                      play – the first time it gets the game (it asks first)
#   lotus surf play --fullscreen    or --window
#   lotus surf update               a newer release or a newer source: the game again
#   lotus surf build                built from the source with Unity, even when a release has a Mac build
#   lotus surf install <zip|app>    a Mac build you downloaded yourself
#   lotus surf status               where it is, where it came from, what it needs
#   lotus surf log                  what Unity said in the last build
#   lotus surf remove               the game and its source go (asks) – your progress in the game stays
# The game is a Unity 2019.4 project. Its Mac build either comes from its GitHub releases (made on Linux by its CI:
# not executable, not signed) or Unity builds it here. Either way Lotus makes it run on macOS: the program
# executable, out of quarantine, signed for this Mac. Unity 2019 builds for Intel Macs – Apple silicon runs it
# with Rosetta 2.
# In the data folder ($LOTUS_PLUGIN_DATA):
#   Subway Surfers Resurferd.app    the game
#   source/                         the Unity project (git), with Unity's Library – a second build is much quicker
#   game.info                       where the game came from: FROM=release|source|file, VERSION, DATE
#   build.log                       what Unity said in the last build
#   settings                        yours, KEY=value: REPO=owner/name (a fork), GET=auto|release|build (how the
#                                   game comes the first time), UNITY=<Unity.app> (one Unity Hub does not know),
#                                   GIT=<git URL> and RELEASES=<GitHub API link> (the source and releases from elsewhere)
source $LOTUS_ROOT/lib/core.zsh && source $LOTUS_ROOT/lib/ui.zsh && lotus_load || exit 1
setopt extendedglob
zmodload -F zsh/stat b:zstat 2>/dev/null
zmodload zsh/datetime 2>/dev/null
LOTUS_LOG_COMP=resurferd
[[ $LOTUS_PLUGIN_DATA == /?* ]] || { print -u2 -r -- "lotus: resurferd runs as a Lotus plugin: lotus surf"; exit 1 }

# KEY=value lines of a file → KV (read line by line, never sourced)
_rs_kv() {
  typeset -gA KV=()
  local line
  [[ -r $1 ]] || return 0
  for line in "${(@f)$(<$1)}"; do
    line=${line//$'\r'/}
    [[ $line == [A-Z][A-Z0-9_]#=* ]] && KV[${line%%=*}]=${line#*=}
  done
  return 0
}

typeset -g D=$LOTUS_PLUGIN_DATA NAME="Subway Surfers Resurferd"
typeset -g APP="$D/$NAME.app" SRC=$D/source LOG=$D/build.log INFO=$D/game.info
typeset -gA cfg=() game=()
_rs_kv $D/settings; cfg=("${(@kv)KV}")
typeset -g REPO=${cfg[REPO]:-cyberillcbutsmarter/subway-surfers-resurferd}
[[ $REPO == [A-Za-z0-9_.-]##/[A-Za-z0-9_.-]## ]] || REPO=cyberillcbutsmarter/subway-surfers-resurferd
typeset -g GIT=${cfg[GIT]:-https://github.com/$REPO.git}
[[ $GIT == -* ]] && GIT=https://github.com/$REPO.git
typeset -g RELEASES=${cfg[RELEASES]:-https://api.github.com/repos/$REPO/releases?per_page=30}
typeset -g GET=${cfg[GET]:-auto} UVER= UCS=
[[ $GET == (auto|release|build) ]] || GET=auto

_rs_save_info() {   # <release|source|file> <version>
  print -r -- "FROM=$1"$'\n'"VERSION=$2"$'\n'"DATE=$(strftime %Y-%m-%d $EPOCHSECONDS)" >| $INFO
}

_rs_apple_silicon() { [[ $(sysctl -n hw.optional.arm64 2>/dev/null) == 1 ]] }   # also when zsh runs as Intel
_rs_rosetta() { arch -x86_64 /usr/bin/true 2>/dev/null }

# Downloads and installs only with a yes – without a keyboard (scripts) it is a no
_rs_ask() {   # <question>
  ui_has_tty || { ui_dim "  $1 – no keyboard to ask, so no."; return 1 }
  ui_confirm "$1" y
}

# ── The app ───────────────────────────────────────────────────

# The program of a Mac app → REPLY ("" and status 1 when it is no Mac app)
_rs_exe() {   # <app>
  local app=$1 exe
  REPLY=
  [[ -r $app/Contents/Info.plist ]] || return 1
  exe=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' $app/Contents/Info.plist 2>/dev/null)
  if [[ -z $exe || $exe == */* || ! -f $app/Contents/MacOS/$exe ]]; then
    local -a f=($app/Contents/MacOS/*(.N))
    exe=${f[1]:t}
  fi
  [[ -n $exe ]] || return 1
  REPLY=$app/Contents/MacOS/$exe
}

# What a program is made for → REPLY: universal, apple, intel or ""
_rs_arch() {   # <program>
  case $(file -b $1 2>/dev/null) in
    *arm64*x86_64*|*x86_64*arm64*) REPLY=universal ;;
    *arm64*)                       REPLY=apple ;;
    *x86_64*)                      REPLY=intel ;;
    *)                             REPLY= ;;
  esac
}

# What a Mac build from Linux (the game's CI) or from a download needs before macOS opens it: its program
# executable, no quarantine (and no Finder data, which breaks a signature), an ad-hoc signature for this Mac
_rs_fix() {   # <app>
  _rs_exe $1 || return 1
  chmod -R u+rwX $1 2>/dev/null
  chmod +x $1/Contents/MacOS/*(.N) 2>/dev/null
  xattr -cr $1 2>/dev/null
  codesign --force --deep --sign - $1 >/dev/null 2>&1 || lotus_log WARN resurferd "codesign could not sign ${1:t}"
  return 0
}

# How much room a file or folder takes, like 312M → REPLY
_rs_size() {   # <path>
  local s=$(du -sh $1 2>/dev/null)
  REPLY=${s%%[[:space:]]*}
}

# A new app takes the old one's place – the old one comes back when that fails
_rs_place() {   # <new app>
  local old=$D/.old.app
  rm -rf -- $old
  [[ -d $APP ]] && mv -- $APP $old
  if mv -- $1 $APP; then rm -rf -- $old; return 0; fi
  [[ -d $old ]] && mv -- $old $APP
  return 1
}

# The Mac app in an unpacked folder, the one closest to the top → REPLY
_rs_find_app() {   # <folder>
  local a
  local -a apps=($1/{,*/,*/*/}*.app(/N))
  for a in ${apps:#*/__MACOSX/*}; do
    _rs_exe $a && { REPLY=$a; return 0 }
  done
  REPLY=
  return 1
}

# Unpacks a zip (ditto keeps what macOS needs; unzip when ditto cannot) → REPLY = the Mac app in it
_rs_unpack() {   # <zip> <folder>
  rm -rf -- $2; mkdir -p $2
  ditto -x -k $1 $2 2>/dev/null || unzip -qo $1 -d $2 >/dev/null 2>&1 || return 1
  _rs_find_app $2
}

# ── Ready Mac builds: the game's GitHub releases ─────────────

# The newest release with a Mac build (an asset like …-StandaloneOSX.zip) → REL (tag link size digest name)
# Status 1: no release has one, 2: GitHub could not be asked
_rs_release() {
  typeset -ga REL=()
  local json line
  json=$(curl -fsSL -m 20 -H 'Accept: application/vnd.github+json' -- "$RELEASES" 2>/dev/null) || return 2
  line=$(print -r -- $json | lotus_jq -r '
    [ .[]? | select(.draft | not) | .tag_name as $t | .assets[]?
      | select((.name | test("\\.zip$"; "i")) and (.name | test("osx|macos|[^a-z]mac[^a-z]"; "i")))
      | [$t, .browser_download_url, (.size | tostring), (.digest // ""), .name] | join("\t") ]
    | first // empty') || return 2
  [[ -n $line ]] || return 1
  REL=("${(@ps:\t:)line}")
  # only from where the releases are: GitHub over https (a file:// list may point to files)
  [[ $REL[2] == https://* || ( $RELEASES == file://* && $REL[2] == file://* ) ]] || return 1
  [[ $REL[3] == <-> ]] || REL[3]=0
  return 0
}

# The Mac build of the release in REL, while the lotus blooms: downloaded (real bytes), checked against the SHA-256
# GitHub gives, unpacked and made to run on macOS. Status 1 = failed, 2 = stopped
_rs_download() {
  local tag=$REL[1] url=$REL[2] digest=${REL[4]#sha256:} asset=$REL[5] sum
  local part=$D/download.zip.part work=$D/.unpack why=
  local -i total=$REL[3] pid rc=1
  local -a st
  setopt localoptions localtraps
  source $LOTUS_ROOT/lib/bg/progress.zsh
  lotus_lang_group bg
  typeset -gi RS_STOP=0
  trap 'RS_STOP=1' INT
  _bg_cancel() { RS_STOP=1 BG_CANCEL=0 }
  BG_CANCEL=0
  bg_ui_begin Resurferd "download|Downloading the Mac build|Download" "check|Checking it|Checksum" \
    "unpack|Unpacking the app|Unpack" "macos|Making it run on macOS|macOS"
  bg_ui_sub "github.com/$REPO · $tag"
  bg_ui_info file $asset
  bg_ui_stage download
  rm -f -- $part
  curl -fsSL -m 1800 -o $part -- "$url" 2>/dev/null &
  pid=$!
  while kill -0 $pid 2>/dev/null && (( ! RS_STOP )); do
    zstat -A st +size -- $part 2>/dev/null && (( total > 0 )) && bg_ui_progress $st[1] $total
    bg_ui_frame
    bg_ui_tick 8
  done
  if (( RS_STOP )); then
    kill -TERM $pid 2>/dev/null; wait $pid 2>/dev/null
    bg_ui_end; rm -f -- $part
    ui_info "Stopped."
    return 2
  fi
  wait $pid && rc=0 || why="The download did not finish."
  if (( rc == 0 )) && [[ -n $digest ]]; then
    bg_ui_stage check; bg_ui_progress 0 0; bg_ui_frame
    sum=$(shasum -a 256 $part 2>/dev/null)
    [[ ${sum%% *} == ${(L)digest} ]] || { rc=1 why="It is not the file GitHub promised (its SHA-256 differs)." }
  fi
  local new=
  if (( rc == 0 )); then
    bg_ui_stage unpack; bg_ui_frame
    _rs_unpack $part $work && new=$REPLY || { rc=1 why="There is no Mac app in $asset." }
  fi
  if (( rc == 0 )); then
    bg_ui_stage macos; bg_ui_frame
    _rs_fix $new && _rs_place $new || { rc=1 why="The app could not be put in place." }
  fi
  rm -rf -- $part $work
  if (( rc == 0 )); then
    _rs_save_info release $tag
    lotus_log INFO resurferd "Mac build of $tag installed"
    bg_ui_complete; bg_ui_end
    ui_success "Ready: $NAME, $tag"
    return 0
  fi
  bg_ui_end
  ui_error "The Mac build of $tag did not work out" "$why" "lotus surf build builds the game from the source instead"
  return 1
}

# ── Built here: the source and Unity ──────────────────────────

# The game's source in source/ (git, only the newest commit): cloned the first time, brought up to date later –
# Unity's Library in it stays, so the next build is quick → REPLY = the commit
_rs_source() {
  if ! git --version >/dev/null 2>&1; then
    ui_error "git is missing" "" "xcode-select --install installs it, with Apple's Command Line Tools"
    return 1
  fi
  if [[ -d $SRC/.git ]]; then
    ui_step "Bringing the source up to date – github.com/$REPO …"
    git -C $SRC remote set-url origin $GIT 2>/dev/null
    git -C $SRC fetch --depth 1 --progress origin HEAD && git -C $SRC reset -q --hard FETCH_HEAD \
      || { ui_error "git could not bring the source up to date" "$GIT" "Are you online?"; return 1 }
  else
    ui_step "Getting the source – github.com/$REPO, about 120 MB …"
    rm -rf -- $SRC.part
    if ! git clone --depth 1 --progress -- $GIT $SRC.part; then
      rm -rf -- $SRC.part
      ui_error "git could not get the source" "$GIT" "Are you online?"
      return 1
    fi
    mv -- $SRC.part $SRC
  fi
  REPLY=$(git -C $SRC rev-parse --short HEAD 2>/dev/null)
}

# The Unity version the project is made with → UVER, UCS (its changeset: Unity Hub needs it for older versions)
_rs_project_version() {
  local f=$SRC/ProjectSettings/ProjectVersion.txt line
  UVER= UCS=
  [[ -r $f ]] || return 1
  for line in "${(@f)$(<$f)}"; do
    case $line in
      m_EditorVersion:\ *)                 UVER=${${line#*: }//[[:space:]]/} ;;
      m_EditorVersionWithRevision:*\(*\)*) UCS=${${line##*\(}%%\)*} ;;
    esac
  done
  [[ $UVER == <->.<->.<->[abfp]<-> ]]
}

# Unity <version> on this Mac: UNITY in the settings, else where Unity Hub puts it (also a folder of your
# choice in the Hub) → REPLY = the Unity program
_rs_unity() {   # <version>
  local p more="$HOME/Library/Application Support/UnityHub/secondaryInstallPath.json"
  local -a apps=()
  [[ -n $cfg[UNITY] ]] && apps+=(${cfg[UNITY]/#\~/$HOME})
  apps+=(/Applications/Unity/Hub/Editor/$1/Unity.app)
  if [[ -r $more ]]; then
    p=$(<$more); p=${${p//[\"\\]/}//[[:space:]]##(#e)/}     # a JSON string: "/Volumes/Disk/Unity"
    [[ $p == /* ]] && apps+=($p/$1/Unity.app)
  fi
  for p in $apps; do
    p=${p%/Contents/MacOS/Unity}
    [[ -x $p/Contents/MacOS/Unity ]] && { REPLY=$p/Contents/MacOS/Unity; return 0 }
  done
  REPLY=
  return 1
}

_rs_hub() {   # Unity Hub's program → REPLY
  local p
  for p in "/Applications/Unity Hub.app" "$HOME/Applications/Unity Hub.app"; do
    [[ -x "$p/Contents/MacOS/Unity Hub" ]] && { REPLY="$p/Contents/MacOS/Unity Hub"; return 0 }
  done
  REPLY=
  return 1
}

# Is there a Unity license on this Mac? Unity Hub writes one when you sign in and add the free personal license.
_rs_license() {
  local -a f=("/Library/Application Support/Unity/Unity_lic.ulf"(N)
              "/Library/Application Support/Unity/licenses/"*(N) $HOME/Library/Unity/licenses/*(N))
  (( ${#f} ))
}

# Unity UVER with Unity Hub, the Hub from Homebrew when it is missing – asks first → REPLY = the Unity program
_rs_get_unity() {
  ui_info "The game is built with Unity $UVER – it is not on this Mac yet."
  ui_dim "  Unity Hub installs it: free with a Unity account (Personal), several GB."
  if ! _rs_hub; then
    if (( $+commands[brew] )) && _rs_ask "Install Unity Hub with Homebrew (brew install --cask unity-hub)?"; then
      ui_step "Installing Unity Hub …"
      if ! brew install --cask unity-hub >| $D/hub.log 2>&1 || ! _rs_hub; then
        ui_error "Homebrew could not install Unity Hub" "" "Its log: $D/hub.log" "Or get it from unity.com/download – then: lotus surf build"
        return 1
      fi
      ui_success "Unity Hub is installed"
    else
      ui_error "Unity Hub is needed for Unity $UVER" "" "brew install --cask unity-hub, or unity.com/download – then: lotus surf build"
      return 1
    fi
  fi
  local hub=$REPLY line
  _rs_ask "Install Unity $UVER with Unity Hub now?" || return 1
  local -a args=(-- --headless install --version $UVER)
  [[ -n $UCS ]] && args+=(--changeset $UCS)
  [[ $UVER == 20(1[0-9]|20|21.1)* ]] && _rs_apple_silicon && args+=(--architecture x86_64)   # no Apple silicon Unity before 2021.2
  ui_step "Unity Hub installs Unity $UVER – this takes a while …"
  : >| $D/hub.log
  "$hub" $args 2>&1 </dev/null | while IFS= read -r line; do
    print -r -- $line >> $D/hub.log
    [[ -t 1 && -n ${line//[[:space:]]/} ]] && print -rn -- $'\r\e[K'"    ${${line//[[:cntrl:]]/}[1,COLUMNS-8]}"
  done
  [[ -t 1 ]] && print -rn -- $'\r\e[K'
  if ! _rs_unity $UVER; then
    # older Hubs know no --architecture, some want you signed in first: then the Hub's own window does it
    open "unityhub://$UVER/$UCS" 2>/dev/null
    ui_error "Unity $UVER is not installed yet" "Unity Hub opened with it – install it there, then: lotus surf build" "What the Hub said: $D/hub.log"
    return 1
  fi
  ui_success "Unity $UVER is installed"
}

# Moves the build screen to a later step (never back – Unity compiles again while it builds the player)
typeset -gi RS_AT=1
typeset -ga RS_KEYS=(open import compile player macos)
_rs_step() {
  local -i i=${RS_KEYS[(i)$1]}
  (( i > RS_AT )) || return 0
  RS_AT=i
  bg_ui_stage $1; bg_ui_progress 0 0; bg_ui_note ""
}

# Unity builds the Mac app, while the lotus blooms. Its log tells the steps: the assets it imports (real bytes of
# the project's files), the scripts it compiles, the player it builds. Status 1 = failed, 2 = stopped
_rs_unity_build() {   # <unity program> <commit>
  local unity=$1 commit=$2 out=$D/.build line f
  setopt localoptions localtraps
  source $LOTUS_ROOT/lib/bg/progress.zsh
  lotus_lang_group bg
  typeset -gi RS_STOP=0 RS_PID=0
  typeset -ga RS_ERRS=()
  typeset -g RS_WHY=
  trap 'RS_STOP=1; (( RS_PID )) && kill -TERM $RS_PID 2>/dev/null' INT
  _bg_cancel() { RS_STOP=1 BG_CANCEL=0; (( RS_PID )) && kill -TERM $RS_PID 2>/dev/null }
  BG_CANCEL=0
  # the project's files and their sizes: what the import has done, in bytes
  local -A size=()
  local -a st files=($SRC/Assets/**/*~*.meta(.ND))
  local -i total=0 got=0 imported=0 rc=1 fd more i
  for f in $files; do
    zstat -A st +size -- $f 2>/dev/null || continue
    size[${f#$SRC/}]=$st[1]; (( total += st[1] ))
  done
  rm -rf -- $out; mkdir -p $out
  : >| $LOG
  RS_AT=1
  bg_ui_begin Resurferd "open|Opening the project in Unity|Unity" "import|Importing the assets|Assets" \
    "compile|Compiling the scripts|Scripts" "player|Building the Mac app|Mac app" "macos|Making it run on macOS|macOS"
  bg_ui_sub "github.com/$REPO · $commit"
  bg_ui_info unity "Unity $UVER"
  bg_ui_info assets "${#files} assets"
  bg_ui_stage open
  bg_ui_note "Unity starts without a window …"
  _BG_BUF=
  exec {fd}< <(
    "$unity" -batchmode -quit -projectPath $SRC -buildTarget OSXUniversal \
      -buildOSXUniversalPlayer "$out/$NAME.app" -logFile - 2>&1 </dev/null &
    print -r -- "LOTUS-PID $!"
    wait $!
    print -r -- "LOTUS-EXIT $?"
  )
  while :; do
    bg_read_lines $fd 0.1; more=$?
    for line in $reply; do
      case $line in
        "LOTUS-PID "<->)  RS_PID=${line#* }; continue ;;
        "LOTUS-EXIT "<->) rc=${line#* }; continue ;;
      esac
      print -r -- $line >> $LOG
      case $line in
        *"Start importing "*" using Guid"*)
          f=${${line#*Start importing }%% using Guid*}
          _rs_step import
          (( imported++, got += ${size[$f]:-0}, got > total ? (got = total) : 0 ))
          (( total > 0 )) && bg_ui_progress $got $total
          bg_ui_note "$imported assets · ${f:t}" ;;
        (#i)*starting\ compile*|(#i)*compiling\ scripts*)
          _rs_step compile
          bg_ui_note "${${${line##*/}%%[[:space:]]#}[1,60]}" ;;
        *": error CS"<->*)
          [[ $line == *Assets/* ]] && line=Assets/${line#*Assets/}
          (( ${#RS_ERRS} < 4 )) && RS_ERRS+=("${line[1,150]}") ;;
        *"DisplayProgressbar: "*)
          [[ $line == (#i)*(build|player|shader|scene|resources)* ]] && _rs_step player
          bg_ui_note "${${line#*DisplayProgressbar: }[1,60]}" ;;
        *"Compiling shader \""*)
          _rs_step player
          bg_ui_note "Shader ${${line#*Compiling shader \"}%%\"*}" ;;
        (#i)*(no\ valid\ unity*licen|not\ been\ activated|editor.headless|failed\ to\ activate|licen[cs]e\ is\ not\ active|invalid\ licen)*)
          RS_WHY=license ;;
        (#i)*another\ unity\ instance\ is\ running*)
          RS_WHY=open ;;
      esac
    done
    bg_ui_frame
    (( more == 0 && ! RS_STOP )) || break
  done
  exec {fd}<&-
  if (( RS_STOP )); then
    for (( i = 0; i < 100 && RS_PID; i++ )); do kill -0 $RS_PID 2>/dev/null || break; sleep 0.1; done
    bg_ui_end; rm -rf -- $out
    ui_info "Stopped – the next build goes on from what Unity has imported so far."
    return 2
  fi
  local new="$out/$NAME.app"
  if (( rc == 0 )) && _rs_exe $new; then
    _rs_step macos; bg_ui_frame
    _rs_fix $new && _rs_place $new || rc=1
  else
    rc=1
  fi
  rm -rf -- $out
  if (( rc == 0 )); then
    _rs_save_info source $commit
    lotus_log INFO resurferd "Built $commit with Unity $UVER"
    bg_ui_complete; bg_ui_end
    ui_success "Ready: $NAME, built from $commit"
    return 0
  fi
  bg_ui_end
  _rs_build_failed
  return 1
}

# Why Unity did not build it, in words – from its log
_rs_build_failed() {
  local -i w=$(( ${COLUMNS:-80} > 40 ? ${COLUMNS:-80} - 6 : 74 ))
  case $RS_WHY in
    license)
      ui_error "Unity has no license on this Mac" "Unity needs one even to build – the free Personal license is enough." \
        "Open Unity Hub, sign in, then Preferences → Licenses → Add → Get a free personal license" "Then: lotus surf build" ;;
    open)
      ui_error "Another Unity has the project open" "Close it, then: lotus surf build" ;;
    *)
      local -a said=() l
      if (( ${#RS_ERRS} )); then
        for l in $RS_ERRS; do said+=(${l[1,w]}); done
        ui_error "The game's scripts did not compile with Unity $UVER" "Unity says:" $said "All of it: lotus surf log"
      else
        for l in ${(f)"$(grep -iE 'error|failed|exception|abort' $LOG 2>/dev/null | tail -n 4)"}; do said+=(${l[1,w]}); done
        ui_error "Unity could not build the Mac app" "Its last words:" ${said:-"(nothing)"} "All of it: lotus surf log"
      fi ;;
  esac
  lotus_log ERROR resurferd "Unity build failed${RS_WHY:+ ($RS_WHY)}"
}

# ── The commands ──────────────────────────────────────────────

rs_build() {
  _rs_source || return 1
  local commit=$REPLY
  _rs_project_version || { ui_error "The source is no Unity project" "ProjectSettings/ProjectVersion.txt is missing" "Is REPO in $D/settings right?"; return 1 }
  _rs_unity $UVER || _rs_get_unity || return 1
  local unity=$REPLY
  _rs_arch $unity
  if [[ $REPLY == intel ]] && _rs_apple_silicon && ! _rs_rosetta; then
    ui_info "Unity $UVER is made for Intel Macs – this Mac runs it with Rosetta 2, Apple's translator."
    _rs_ask "Install Rosetta 2 now?" || return 1
    if ! softwareupdate --install-rosetta --agree-to-license >| $D/rosetta.log 2>&1 || ! _rs_rosetta; then
      ui_error "Rosetta 2 could not be installed" "" "sudo softwareupdate --install-rosetta --agree-to-license"
      return 1
    fi
    ui_success "Rosetta 2 is installed"
  fi
  _rs_license || ui_warn "No Unity license on this Mac yet – sign in to Unity Hub and add the free personal license (Preferences → Licenses), or Unity cannot build."
  ui_dim "  The first build takes a while: Unity imports every asset once. Later builds are much quicker."
  _rs_unity_build $unity $commit
}

# A ready Mac build from the releases, or built from the source – as GET says
_rs_get_any() {
  local -i r=1
  if [[ $GET != build ]]; then
    ui_step "Looking for a Mac build in the releases of github.com/$REPO …"
    _rs_release; r=$?
    (( r == 0 )) && { _rs_download; return }
    if [[ $GET == release ]]; then
      if (( r == 2 )); then ui_error "GitHub could not be asked for the releases" "" "Are you online? GitHub also limits how often – try again later"
      else ui_error "No release has a Mac build" "github.com/$REPO/releases" "lotus surf build builds one from the source"; fi
      return 1
    fi
    if (( r == 2 )); then ui_info "GitHub could not be asked for the releases – Lotus builds the game from the source."
    else ui_info "No release has a Mac build – Lotus builds one from the source with Unity."; fi
  fi
  rs_build
}

# The first time: what happens, asked once
rs_get() {
  ui_header "$NAME" "github.com/$REPO"
  ui_text "The game is not on this Mac yet. Lotus gets it for you:"
  case $GET in
    release) ui_dim "  the Mac build of its newest GitHub release" ;;
    build)   ui_dim "  built from its source with Unity" ;;
    *)       ui_dim "  the Mac build of its newest GitHub release – or, when there is none, built from its source with Unity" ;;
  esac
  ui_dim "  Then it makes the app run on macOS, and starts it."
  ui_blank
  _rs_ask "Get it now?" || return 1
  _rs_get_any
}

_rs_launch() {   # [arguments for the game]
  _rs_exe $APP || return 1
  [[ -x $REPLY ]] || _rs_fix $APP
  _rs_arch $REPLY
  [[ $REPLY == intel ]] && _rs_apple_silicon && ! _rs_rosetta \
    && ui_info "It is an Intel app: macOS asks to install Rosetta 2 the first time – say yes."
  if (( $# )); then open $APP --args "$@"; else open $APP; fi || return 1
  lotus_log INFO resurferd "Started"
}

rs_play() {   # [--fullscreen | --window]
  local -a args=()
  case $1 in
    -f|--fullscreen) args=(-screen-fullscreen 1) ;;
    -w|--window)     args=(-screen-fullscreen 0) ;;
    '')              ;;
    *)               ui_error "Unknown: lotus surf play $1" "" "lotus surf play --fullscreen, or --window"; return 2 ;;
  esac
  if ! _rs_exe $APP; then
    rs_get || return 1
    _rs_exe $APP || return 1
  fi
  _rs_launch $args || { ui_error "macOS could not open the game" "$APP" "lotus surf status says more"; return 1 }
  ui_success "$NAME is starting"
  ui_kv Lanes "← → or A D"
  ui_kv Jump "↑ or W"
  ui_kv Roll "↓ or S"
  ui_kv Hoverboard "Space or a click, twice"
}

rs_update() {
  _rs_kv $INFO; game=("${(@kv)KV}")
  _rs_exe $APP || { rs_get; return }
  local -i r
  case $game[FROM] in
    release)
      ui_step "Looking for a newer Mac build …"
      _rs_release; r=$?
      if (( r == 2 )); then ui_error "GitHub could not be asked for the releases" "" "Are you online? GitHub also limits how often – try again later"; return 1; fi
      if (( r == 1 )); then ui_info "No release has a Mac build any more – yours ($game[VERSION]) stays. lotus surf build builds the newest source."; return 0; fi
      [[ $REL[1] == $game[VERSION] ]] && { ui_success "Up to date – $REL[1] is the newest release with a Mac build"; return 0 }
      ui_info "$REL[1] is out – you have $game[VERSION]"
      _rs_download ;;
    source)
      local head=$(git ls-remote $GIT HEAD 2>/dev/null)
      head=${head[1,7]}
      [[ -n $head ]] || { ui_error "git could not ask github.com/$REPO" "" "Are you online?"; return 1 }
      [[ $head == ${game[VERSION][1,7]} ]] && { ui_success "Up to date – $head is the newest commit"; return 0 }
      ui_info "The source changed: $game[VERSION] → $head"
      rs_build ;;
    *)
      ui_info "This one came from your file${game[VERSION]:+ ($game[VERSION])} – Lotus gets the newest instead."
      _rs_get_any ;;
  esac
}

rs_install_file() {   # <zip|app>
  local p=${1/#\~/$HOME} work=$D/.unpack
  [[ -n $p ]] || { ui_error "Which Mac build?" "" "lotus surf install ~/Downloads/Subway-Surfers-Resurferd-StandaloneOSX.zip"; return 2 }
  [[ $p == /* ]] || p=${LOTUS_PWD:-$PWD}/$p
  p=${p%/}
  [[ -e $p ]] || { ui_error "There is no $1"; return 1 }
  case $p in
    (#i)*.zip) _rs_unpack $p $work ;;
    (#i)*.app) rm -rf -- $work; mkdir -p $work && { ditto $p $work/${p:t} 2>/dev/null || cp -R $p $work/ } && _rs_find_app $work ;;
    *)         ui_error "A Mac build is a .zip or an .app" "${p:t}"; return 2 ;;
  esac
  local -i bad=$?
  local new=$REPLY
  if (( bad )) || ! _rs_fix $new || ! _rs_place $new; then
    rm -rf -- $work
    ui_error "There is no Mac app in it" "${p:t}" "A Mac build of a Unity game has a .app (StandaloneOSX)"
    return 1
  fi
  rm -rf -- $work
  _rs_save_info file ${p:t}
  lotus_log INFO resurferd "Installed from ${p:t}"
  ui_success "Ready: $NAME, from ${p:t} – lotus surf starts it"
}

rs_status() {
  _rs_kv $INFO; game=("${(@kv)KV}")
  ui_header "$NAME" "github.com/$REPO"
  if _rs_exe $APP; then
    local kind from
    _rs_arch $REPLY
    case $REPLY in
      universal) kind="Universal – Apple silicon and Intel" ;;
      apple)     kind="Apple silicon" ;;
      intel)     kind=Intel
                 _rs_apple_silicon && { _rs_rosetta && kind+=" – runs with Rosetta 2" || kind+=" – needs Rosetta 2 (macOS offers it)" } ;;
      *)         kind= ;;
    esac
    case $game[FROM] in
      release) from="the release $game[VERSION]" ;;
      source)  from="built from the source, $game[VERSION]" ;;
      file)    from="your file $game[VERSION]" ;;
      *)       from="?" ;;
    esac
    ui_kv Game "ready – lotus surf starts it"
    ui_kv From "$from${game[DATE]:+ · $game[DATE]}"
    ui_path $APP; ui_kv Where "$REPLY"
    _rs_size $APP; ui_kv Size "$REPLY"
    [[ -n $kind ]] && ui_kv Kind "$kind"
  else
    ui_kv Game "not on this Mac yet – lotus surf gets it"
  fi
  if [[ -d $SRC/.git ]]; then
    _rs_size $SRC
    ui_kv Source "$(git -C $SRC rev-parse --short HEAD 2>/dev/null) · $REPLY with Unity's Library"
    if _rs_project_version; then
      if _rs_unity $UVER; then ui_path ${REPLY%/Contents/MacOS/Unity}; ui_kv Unity "$UVER · $REPLY"
      else ui_kv Unity "$UVER – not on this Mac (lotus surf build installs it)"; fi
      _rs_license && ui_kv License "there is one" || ui_kv License "none yet – sign in to Unity Hub, add the free personal license"
    fi
  fi
  ui_blank
}

rs_log() {
  [[ -s $LOG ]] || { ui_info "No build yet – lotus surf build"; return 0 }
  ui_path $LOG; ui_dim "$REPLY"
  tail -n 40 $LOG
}

rs_remove() {
  local -a what=()
  [[ -d $APP ]] && what+=($APP)
  [[ -d $SRC ]] && what+=($SRC)
  (( ${#what} )) || { ui_info "There is nothing to remove – the game is not on this Mac."; return 0 }
  ui_header "$NAME" "remove"
  local p
  if [[ -d $APP ]]; then ui_path $APP; p=$REPLY; _rs_size $APP; ui_kv Game "$REPLY · $p"; fi
  if [[ -d $SRC ]]; then ui_path $SRC; p=$REPLY; _rs_size $SRC; ui_kv Source "$REPLY · $p, with Unity's Library"; fi
  ui_dim "  Your progress in the game stays – macOS keeps it apart from the app. Unity and Unity Hub stay too."
  ui_blank
  ui_confirm "Remove them?" n || return 1
  rm -rf -- $what $INFO $LOG $D/.build $D/.unpack $D/download.zip.part
  lotus_log INFO resurferd "Removed"
  ui_success "Removed – lotus surf gets the game again"
}

# For the AI (tool play): plain words, status 3 when the user has to get the game first
rs_tool_play() {
  if ! _rs_exe $APP; then
    print -r -- "$NAME is not on this Mac yet. The user gets it with: lotus surf – it downloads or builds the game and asks first."
    return 3
  fi
  _rs_launch >/dev/null || { print -r -- "macOS could not open the game ($APP)."; return 1 }
  print -r -- "Started $NAME. Controls: arrow keys or WASD, Space or a click twice for the hoverboard."
}

rs_help() {
  ui_header "$NAME" "on this Mac"
  print -r -- "  lotus surf                      play – the first time it gets the game (it asks first)
  lotus surf play --fullscreen    or --window
  lotus surf update               a newer release or a newer source: the game again
  lotus surf build                build it from the source with Unity, even when a release has a Mac build
  lotus surf install <zip|app>    a Mac build you downloaded yourself
  lotus surf status               where it is, where it came from, what it needs
  lotus surf log                  what Unity said in the last build
  lotus surf remove               the game and its source go – your progress stays"
  ui_blank
  ui_path $D/settings
  ui_dim "  Settings in $REPLY: REPO=owner/name (a fork), GET=auto|release|build, UNITY=<Unity.app>"
  ui_blank
}

mkdir -p $D
case ${1:-play} in
  play|start)                  rs_play "${@:2}" ;;
  -f|--fullscreen|-w|--window) rs_play "$@" ;;
  update|upgrade)              rs_update ;;
  build|rebuild)               rs_build ;;
  install|add)                 rs_install_file "$2" ;;
  status|info)                 rs_status ;;
  log|logs)                    rs_log ;;
  remove|uninstall|rm)         rs_remove ;;
  tool-play)                   rs_tool_play ;;
  help|-h|--help)              rs_help ;;
  *)                           ui_error "Unknown: lotus surf $1" "" "lotus surf help shows what it can do"; exit 2 ;;
esac
