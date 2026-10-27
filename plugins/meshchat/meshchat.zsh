# MeshChat – a plugin for Lotus (plugin.conf). The chat is a Swift program (Sources/*.swift: CoreBluetooth for the
# radio, CryptoKit for the encryption) that is built once on this Mac, like Lotus' own AI terminal, and kept in the
# plugin's data folder: $LOTUS_PLUGIN_DATA/bin/meshchat-<checksum> – built again when the sources change.
#   lotus meshchat …            the chat and its commands (lotus meshchat help)
#   lotus meshchat doctor       macOS, the Command Line Tools and the build – then Bluetooth and its permission
#   lotus meshchat selftest     the protocol tests (Tests/*.swift) on a simulated radio – no Bluetooth needed
#   lotus meshchat build        build it again now
# Nothing runs in the background: the chat is a program in this terminal and ends with it. Should it be ended by
# a signal, the terminal is put back as it was.
setopt extendedglob
here=${0:A:h}
data=${LOTUS_PLUGIN_DATA:?Lotus starts this: lotus meshchat}
bin=$data/bin
k=$'\e['${LOTUS_COLOR_KEY:-38;5;150}m a=$'\e['${LOTUS_COLOR_ACCENT:-38;5;218}m d=$'\e['${LOTUS_COLOR_DIM:-38;5;245}m
r=$'\e[38;5;203m' b=$'\e[1m' x=$'\e[0m'
[[ -t 1 ]] || k= a= d= r= b= x=

# The program built from the sources as they are now → REPLY (its name changes with them)
_mc_path() {   # <app|tests>
  local -a files=($here/Info.plist $here/Sources/*.swift(N))
  [[ $1 == tests ]] && files+=($here/Tests/*.swift(N))
  local sum=$(cat $files | cksum)
  REPLY=$bin/meshchat${${(M)1:#tests}:+-tests}-${sum%% *}
}

_mc_can_build() { xcode-select -p >/dev/null 2>&1 && xcrun --find swiftc >/dev/null 2>&1 }

# Builds the chat (app) or its tests once → REPLY = the program. Status 1 says why.
_mc_build() {   # <app|tests>
  local kind=$1 suffix=${${(M)1:#tests}:+-tests}
  _mc_path $kind
  [[ -x $REPLY ]] && return 0
  local out=$REPLY log=$data/build$suffix.log
  if ! _mc_can_build; then
    print -r -- "  ${r}✗ MeshChat is built once on this Mac – that needs Apple's Command Line Tools${x}"
    print -r -- "    ${d}Install them with: xcode-select --install   then: lotus meshchat${x}"
    return 1
  fi
  # one level at a time: in the sandbox even mkdir -p of a folder that exists fails at the home folder
  local dir
  for dir in $bin $data/build; do [[ -d $dir ]] || mkdir $dir || return 1; done
  rm -f -- $bin/*.tmp.*(N)
  local -a srcs=($here/Sources/*.swift(N)) extra=()
  if [[ $kind == tests ]]; then
    srcs=(${srcs:#*/App.swift} $here/Tests/*.swift(N))
  else
    # the Info.plist goes into the program: what macOS shows should it ever ask about MeshChat itself
    extra=(-Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker $here/Info.plist)
  fi
  local what=MeshChat
  [[ $kind == tests ]] && what="MeshChat's tests"
  [[ -t 1 ]] && print -rn -- "  ${d}… Building $what – one time, about a minute …${x}"
  local arch=$(uname -m) t0=$SECONDS
  if xcrun swiftc -Onone -parse-as-library -swift-version 5 -target $arch-apple-macos11.0 \
       -module-cache-path $data/build/cache $extra -o $out.tmp.$$ $srcs >| $log 2>&1; then
    mv -f -- $out.tmp.$$ $out
    local old
    for old in $bin/meshchat$suffix-<->(N); do [[ $old != $out ]] && rm -f -- $old; done
    [[ -t 1 ]] && print -rn -- $'\r\e[K'
    print -r -- "Built in $(( SECONDS - t0 )) s with $(xcrun swiftc --version 2>&1 | head -1)" >> $log
    REPLY=$out
    return 0
  fi
  rm -f -- $out.tmp.$$
  [[ -t 1 ]] && print -rn -- $'\r\e[K'
  print -r -- "  ${r}✗ MeshChat could not be built${x}"
  local -a errs=(${(f)"$(grep -E 'error:' $log | head -8)"})
  local e
  for e in $errs; do print -r -- "    ${d}${e#$here/}${x}"; done
  print -r -- "    ${d}All of it: ${log/#$HOME/~} · lotus meshchat doctor${x}"
  return 1
}

# Runs the program; when a signal ended it (not ctrl-c), the terminal comes back and the reason is named
_mc_run() {   # <program> [arguments…]
  local prog=$1 saved=
  shift
  [[ -t 0 ]] && saved=$(stty -g 2>/dev/null)
  trap 'true' INT       # ctrl-c belongs to the chat; this script only waits for it
  $prog "$@"
  local rc=$?
  trap - INT
  if (( rc > 128 && rc != 130 )); then
    [[ -n $saved ]] && stty $saved 2>/dev/null
    [[ -t 1 ]] && print -rn -- $'\e[?2004l\e[?25h\e[0m\e[?1049l'
    print -r -- "  ${r}✗ MeshChat was ended by signal $(( rc - 128 ))${x}"
    if (( rc == 134 || rc == 137 )); then
      print -r -- "    ${d}Right after the start that is usually macOS: the terminal app it runs in may not declare Bluetooth use.${x}"
    fi
    print -r -- "    ${d}lotus meshchat doctor says what is wrong${x}"
  fi
  return rc
}

_mc_doctor() {
  print -r -- ""
  print -r -- "  ${b}${a}lotus${x}${d} / ${x}${b}MeshChat${x}${d}  doctor – the build${x}"
  print -r -- ""
  local v=$(sw_vers -productVersion 2>/dev/null) problems=0
  if [[ -n $v ]]; then
    if (( ${v%%.*} >= 11 )); then print -r -- "    ${d}macOS        ${x}$v"
    else print -r -- "    ${d}macOS        ${x}${r}$v – MeshChat needs macOS 11 or newer${x}"; (( problems++ )); fi
  else
    print -r -- "    ${d}macOS        ${x}${r}not macOS – MeshChat needs a Mac${x}"; (( problems++ ))
  fi
  if _mc_can_build; then
    print -r -- "    ${d}Swift        ${x}$(xcrun swiftc --version 2>&1 | head -1)"
  else
    print -r -- "    ${d}Swift        ${x}${r}no Command Line Tools – install them: xcode-select --install${x}"; (( problems++ ))
  fi
  _mc_path app
  if [[ -x $REPLY ]]; then
    print -r -- "    ${d}Build        ${x}ready – ${REPLY/#$HOME/~}"
  elif (( ! problems )); then
    print -r -- "    ${d}Build        ${x}not built yet – building now"
    _mc_build app || (( problems++ ))
  fi
  if [[ -x $REPLY ]]; then
    _mc_run $REPLY doctor
    return
  fi
  print -r -- ""
  print -r -- "  ${r}✗${x} Fix the above first, then: lotus meshchat doctor"
  print -r -- ""
  return 1
}

case $1 in
  doctor|diagnose)
    _mc_doctor ;;
  selftest|test|tests)
    _mc_build tests || exit 1
    _mc_run $REPLY ;;
  build|rebuild)
    _mc_path app
    rm -f -- $REPLY
    _mc_build app || exit 1
    print -r -- "  ${b}${k}✓${x} MeshChat is built – ${d}${REPLY/#$HOME/~}${x}" ;;
  *)
    _mc_build app || exit 1
    _mc_run $REPLY "$@" ;;
esac
