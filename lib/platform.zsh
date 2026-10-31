# lotus – the platform layer: what system is this, and the functions that differ between systems.
#
# Commands never call osascript, open, pbcopy, caffeinate, sips or security directly: they call the lotus_os_* and
# lotus_pkg_* functions below, and this file loads the implementations of the system Lotus runs on
# (lib/platform/macos.zsh, lib/platform/linux.zsh; Windows has its own module in win/).
#
# A function that a system cannot offer returns status 2 and prints nothing. The caller says in words what is
# not possible here – nothing is silently skipped, nothing is faked. dev/3.0/ARCHITECTURE.md has the contract.
#
# Detection is cheap (no program is started for the common values) because the shell loads this at every start.

typeset -g  LOTUS_OS= LOTUS_OS_VERSION= LOTUS_DISTRO= LOTUS_DISTRO_FAMILY= LOTUS_ARCH= LOTUS_PKG= LOTUS_PKG_EXTRA=
typeset -g  LOTUS_DESKTOP= LOTUS_SESSION= LOTUS_FILES_APP=the\ file\ manager     # how texts name the file manager
typeset -g  LOTUS_THIS='this computer' LOTUS_THE='the computer'                  # "this Mac" and "the Mac" on a Mac
typeset -gi LOTUS_WSL=0

lotus_platform_detect() {
  setopt localoptions extendedglob
  case ${OSTYPE:-$(uname -s)} in
    darwin*) LOTUS_OS=macos ;;
    linux*)  LOTUS_OS=linux ;;
    *)       LOTUS_OS=other ;;
  esac
  # CPUTYPE is set when zsh runs (MACHTYPE is the machine zsh was built on: x86_64 in Apple's universal zsh)
  case ${CPUTYPE:-$(uname -m)} in
    arm64|aarch64*) LOTUS_ARCH=arm64 ;;
    x86_64|amd64)   LOTUS_ARCH=x86_64 ;;
    *)              LOTUS_ARCH=${CPUTYPE:-unknown} ;;
  esac
  if [[ $LOTUS_OS == macos ]]; then
    LOTUS_DISTRO=macos LOTUS_DISTRO_FAMILY=macos LOTUS_DESKTOP=aqua LOTUS_SESSION=aqua LOTUS_FILES_APP=Finder
    LOTUS_THIS='this Mac' LOTUS_THE='the Mac'
    (( $+commands[brew] )) && LOTUS_PKG=brew
  elif [[ $LOTUS_OS == linux ]]; then
    local f line id= like= ver=
    for f in /etc/os-release /usr/lib/os-release; do
      [[ -r $f ]] || continue
      for line in "${(@f)$(<$f)}"; do
        case $line in
          ID=*)         id=${(Q)line#ID=} ;;
          ID_LIKE=*)    like=${(Q)line#ID_LIKE=} ;;
          VERSION_ID=*) ver=${(Q)line#VERSION_ID=} ;;
        esac
      done
      break
    done
    LOTUS_DISTRO=${id:-linux} LOTUS_OS_VERSION=$ver
    case " $id $like " in
      *\ (debian|ubuntu|linuxmint|pop|raspbian|kali)\ *)  LOTUS_DISTRO_FAMILY=debian ;;
      *\ (fedora|rhel|centos|rocky|almalinux|ol|amzn)\ *) LOTUS_DISTRO_FAMILY=rhel ;;
      *\ (arch|manjaro|endeavouros|garuda|cachyos)\ *)    LOTUS_DISTRO_FAMILY=arch ;;
      *\ (suse|opensuse*|sles)\ *)                        LOTUS_DISTRO_FAMILY=suse ;;
      *\ alpine\ *)                                       LOTUS_DISTRO_FAMILY=alpine ;;
      *)                                                  LOTUS_DISTRO_FAMILY=other ;;
    esac
    # WSL: Linux inside Windows. Supported as Linux; the native Windows port is win/ (PowerShell)
    [[ -n $WSL_DISTRO_NAME || -n $WSL_INTEROP ]] && LOTUS_WSL=1
    # the package manager of the system comes first, Homebrew on Linux is only a fallback
    local -a pk=()
    (( $+commands[apt-get] )) && pk+=(apt)
    (( $+commands[dnf] ))     && pk+=(dnf)
    (( $+commands[pacman] ))  && pk+=(pacman)
    (( $+commands[zypper] ))  && pk+=(zypper)
    (( $+commands[apk] ))     && pk+=(apk)
    (( ${#pk} == 0 && $+commands[brew] )) && pk+=(brew)
    LOTUS_PKG=${pk[1]}
    local -a ex=()
    (( $+commands[flatpak] )) && ex+=(flatpak)
    (( $+commands[snap] ))    && ex+=(snap)
    (( ${#pk} && $+commands[brew] )) && ex+=(brew)
    LOTUS_PKG_EXTRA=${(j: :)ex}
    LOTUS_DESKTOP=${${XDG_CURRENT_DESKTOP:-none}:l}
    LOTUS_DESKTOP=${LOTUS_DESKTOP%%:*}
    if   [[ -n $WAYLAND_DISPLAY ]]; then LOTUS_SESSION=wayland
    elif [[ -n $DISPLAY ]];         then LOTUS_SESSION=x11
    else                                 LOTUS_SESSION=tty; fi
  fi
}

# The version of the system (macOS: the product version – one program is started, so only when asked)
lotus_os_version() {
  if [[ -z $LOTUS_OS_VERSION && $LOTUS_OS == macos ]]; then
    local f=$LOTUS_CACHE/macos v
    if [[ -r $f ]]; then v=$(<$f)
    else v=$(sw_vers -productVersion 2>/dev/null); zf_mkdir -p $LOTUS_CACHE 2>/dev/null; print -r -- $v >| $f 2>/dev/null; fi
    LOTUS_OS_VERSION=$v
  fi
  REPLY=$LOTUS_OS_VERSION
}

# "macOS 26.0 · Apple silicon", "Ubuntu 24.04 · x86_64" → REPLY
lotus_os_describe() {
  lotus_os_version
  case $LOTUS_OS in
    macos) REPLY="macOS $REPLY · ${${LOTUS_ARCH/arm64/Apple silicon}/x86_64/Intel}" ;;
    linux) local name=${(C)LOTUS_DISTRO}
           REPLY="$name${REPLY:+ $REPLY} · $LOTUS_ARCH${${LOTUS_WSL:#0}:+ · WSL}" ;;
    *)     REPLY="${OSTYPE:-unknown} · $LOTUS_ARCH" ;;
  esac
}

lotus_platform_detect
if [[ -r $LOTUS_ROOT/lib/platform/common.zsh ]]; then
  source $LOTUS_ROOT/lib/platform/common.zsh
  [[ -r $LOTUS_ROOT/lib/platform/$LOTUS_OS.zsh ]] && source $LOTUS_ROOT/lib/platform/$LOTUS_OS.zsh
  source $LOTUS_ROOT/lib/platform/pkg.zsh
fi
