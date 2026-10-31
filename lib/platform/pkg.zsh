# lotus – package managers: what to install, and how (lotus_pkg_*). Behind /install, /brew, the setup and the hints
# that say "install jq with …". data/packages.tsv has the package that provides each program, for every manager.
#
# Rules: the exact command is shown before anything is installed and the user confirms; sudo is used only when the
# command needs it, in the open, so the system asks for the password itself – Lotus never reads or stores it and never
# runs sudo in the background; no package manager is forced on anyone.

typeset -gA LOTUS_PKG_ROW=()
typeset -gA _LOTUS_PKG_COL=(brew 2 apt 3 dnf 4 pacman 5 zypper 6 apk 7 winget 8 scoop 9)

_lotus_pkg_load() {
  (( ${#LOTUS_PKG_ROW} )) && return 0
  local line
  for line in "${(@f)$(<$LOTUS_ROOT/data/packages.tsv)}"; do
    [[ $line == \#* || -z $line ]] && continue
    LOTUS_PKG_ROW[${line%%$'\t'*}]=$line
  done
}

# The package that provides <program> for the package manager (default: this system's) → REPLY; status 1: none known
lotus_pkg_name() {
  _lotus_pkg_load
  local mgr=${2:-${LOTUS_PKG_USE:-$LOTUS_PKG}}
  local -a f=("${(@ps:\t:)LOTUS_PKG_ROW[$1]}")
  REPLY=${f[${_LOTUS_PKG_COL[$mgr]:-0}]}
  [[ -n $REPLY && $REPLY != - ]]
}

# How to get administrator rights for a package command → reply = the words to put in front (none for root)
# Status 1 when there is no way (no sudo, no doas): the command is then only shown.
_lotus_pkg_root() {
  reply=()
  (( EUID == 0 )) && return 0
  if   (( $+commands[sudo] ));   then reply=(sudo)
  elif (( $+commands[doas] ));   then reply=(doas)
  elif (( $+commands[pkexec] )); then reply=(pkexec)
  else return 1; fi
}

# The command that installs <packages> → reply = its words. Never runs it. Status 1: no package manager;
# status 3: it needs administrator rights and this system has no sudo or doas.
lotus_pkg_plan() {
  local mgr=${LOTUS_PKG_USE:-$LOTUS_PKG}
  local -a root=()
  [[ -n $mgr ]] || return 1
  if [[ $mgr != (brew|flatpak) ]]; then _lotus_pkg_root || { reply=(); return 3 }; root=("${reply[@]}"); fi
  case $mgr in
    brew)    reply=(brew install "$@") ;;
    apt)     reply=($root apt install "$@") ;;
    dnf)     reply=($root dnf install "$@") ;;
    pacman)  reply=($root pacman -S "$@") ;;
    zypper)  reply=($root zypper install "$@") ;;
    apk)     reply=($root apk add "$@") ;;
    flatpak) reply=(flatpak install flathub "$@") ;;
    *)       return 1 ;;
  esac
}

# What to type to install a program, for a message → REPLY ("sudo apt install jq")
lotus_pkg_hint() {
  local name
  lotus_pkg_name $1 && name=$REPLY || name=$1
  if lotus_pkg_plan $name; then REPLY="${reply[*]}"
  else REPLY="install the package \"$name\" with your package manager"; fi
}

# Is the package installed? (the manager's own database)
lotus_pkg_installed() {
  case ${LOTUS_PKG_USE:-$LOTUS_PKG} in
    apt)    [[ $(dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null) == ii* ]] ;;
    dnf|zypper) rpm -q "$1" >/dev/null 2>&1 ;;
    pacman) pacman -Q "$1" >/dev/null 2>&1 ;;
    apk)    apk info -e "$1" >/dev/null 2>&1 ;;
    brew)   brew list --formula "$1" >/dev/null 2>&1 || brew list --cask "$1" >/dev/null 2>&1 ;;
    *)      return 1 ;;
  esac
}

# Can the manager install it from the repositories it knows now? (Debian 12 and Ubuntu 24.04 have no fastfetch)
lotus_pkg_available() {
  case ${LOTUS_PKG_USE:-$LOTUS_PKG} in
    apt)    [[ -n $(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ && $2 != "(none)" { print $2 }') ]] ;;
    pacman) pacman -Si "$1" >/dev/null 2>&1 ;;
    dnf)    dnf -q --cacheonly list --available "$1" >/dev/null 2>&1 || dnf -q list --available "$1" >/dev/null 2>&1 ;;
    *)      return 0 ;;
  esac
}

# Runs the installation in the open – the manager's own output, questions and errors stay visible
lotus_pkg_run() {
  lotus_pkg_plan "$@" || return 1
  local -a cmd=("${reply[@]}")
  ui_blank
  ui_info "Running: ${cmd[*]}"
  (( EUID != 0 )) && [[ ${cmd[1]} == (sudo|doas|pkexec) ]] && ui_dim "Your system may ask for your password. Lotus never sees or stores it."
  ui_blank
  "${cmd[@]}"
}

# The programs of the list that are missing → reply
lotus_pkg_missing() {
  local p
  reply=()
  for p in "$@"; do (( $+commands[$p] )) || reply+=($p); done
  (( ${#reply} == 0 ))
}

# Makes sure the programs are there: shows what is missing and the exact command, asks, installs.
#   lotus_pkg_ensure <why> <program…>        status 0 when all are there afterwards
lotus_pkg_ensure() {
  local why=$1; shift
  lotus_pkg_missing "$@" && return 0
  local -a missing=("${reply[@]}") pkgs=() unknown=()
  local p
  for p in $missing; do
    if lotus_pkg_name $p; then pkgs+=($REPLY); else unknown+=($p); fi
  done
  ui_warn "$why needs: ${(j:, :)missing}"
  if (( ${#unknown} )) || (( ! ${#pkgs} )); then
    ui_dim "  Lotus does not know the package for: ${(j:, :)unknown:-$missing}"
    [[ -z $LOTUS_PKG ]] && ui_dim "  No package manager was found – install them yourself."
    (( ${#pkgs} )) || return 1
  fi
  lotus_pkg_plan $pkgs
  case $? in
    1) ui_dim "  No package manager was found. Install: ${(j: :)pkgs}"; return 1 ;;
    3) ui_dim "  This needs administrator rights and there is no sudo here. As root, run: ${LOTUS_PKG} install ${(j: :)pkgs}"; return 1 ;;
  esac
  ui_dim "  The command: ${reply[*]}"
  ui_has_tty && ui_confirm "Install ${(j:, :)pkgs} now?" n || return 1
  lotus_pkg_run $pkgs || return 1
  rehash
  lotus_pkg_missing "$@"
}
