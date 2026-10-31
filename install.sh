#!/bin/sh
# Install Lotus on macOS or Linux:
#   curl -fsSL https://raw.githubusercontent.com/Fanxy13/homebrew-lotus/main/install.sh | sh
# (older Lotus versions pipe it to zsh – that works too: the script switches zsh to sh rules first)
# Windows has its own: install.ps1
#
# What it does: downloads Lotus into ~/.local/share/lotus, links ~/.local/bin/lotus, gets fastfetch (checked against the
# digest pinned in data/vendor.tsv), then starts the setup. Nothing is installed with administrator rights; zsh – which
# Lotus needs on Linux – is only installed after a yes, and the command is shown first.

[ -n "${ZSH_VERSION:-}" ] && emulate sh

say()  { printf '  \033[32mlotus\033[0m  %s\n' "$*"; }
note() { printf '  \033[90m·\033[0m      %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m      %s\n' "$*" >&2; exit 1; }

# A yes or no, asked on the terminal (the script itself may be read from a pipe). Default: no.
ask() {
  [ -r /dev/tty ] || return 1
  printf '  \033[36m?\033[0m      %s [y/N] ' "$1" > /dev/tty
  read answer < /dev/tty || return 1
  case $answer in y|Y|yes|YES|j|J) return 0 ;; *) return 1 ;; esac
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  elif command -v openssl >/dev/null 2>&1; then openssl dgst -sha256 -r "$1" | cut -d' ' -f1
  else return 1; fi
}

fetch() {   # <url> <file>
  if command -v curl >/dev/null 2>&1; then curl -fsSL -o "$2" "$1"
  elif command -v wget >/dev/null 2>&1; then wget -q -O "$2" "$1"
  else return 1; fi
}

# The package manager of this system → pm
detect_pm() {
  pm=
  for c in apt-get dnf pacman zypper apk; do
    if command -v "$c" >/dev/null 2>&1; then pm=$c; break; fi
  done
}

# The command that installs a package, with sudo or doas when it needs them → install_cmd (empty: no way)
install_cmd_for() {   # <package>
  case $pm in
    apt-get) install_cmd="apt install $1" ;;
    dnf)     install_cmd="dnf install $1" ;;
    pacman)  install_cmd="pacman -S $1" ;;
    zypper)  install_cmd="zypper install $1" ;;
    apk)     install_cmd="apk add $1" ;;
    *)       install_cmd= ;;
  esac
  if [ -n "$install_cmd" ] && [ "$(id -u)" != 0 ]; then
    if command -v sudo >/dev/null 2>&1; then install_cmd="sudo $install_cmd"
    elif command -v doas >/dev/null 2>&1; then install_cmd="doas $install_cmd"
    else install_cmd=; fi
  fi
}

# Everything in one function, so "curl … | sh" reads the whole script first
main() {
  repo=${LOTUS_REPO:-Fanxy13/homebrew-lotus}
  root=$HOME/.local/share/lotus
  bin=$HOME/.local/bin

  # 0. What kind of computer is this?
  case $(uname -s) in
    Darwin)
      os=macos
      osver=$(sw_vers -productVersion)
      [ "${osver%%.*}" -ge 11 ] 2>/dev/null || fail "Lotus needs macOS 11 or newer (this Mac: $osver)."
      osver="macOS $osver"
      ;;
    Linux)
      os=linux
      osver=Linux
      if [ -r /etc/os-release ]; then
        osver=$(. /etc/os-release; printf '%s' "${PRETTY_NAME:-$NAME}")
      fi
      ;;
    *) fail "This installer is for macOS and Linux. On Windows use install.ps1 (see the Lotus website)." ;;
  esac
  case $(uname -m) in
    arm64|aarch64) arch=arm64 ; ffarch=aarch64 ;;
    x86_64|amd64)  arch=x86_64; ffarch=amd64 ;;
    *) fail "Lotus supports 64-bit Intel/AMD and ARM computers (this one: $(uname -m))." ;;
  esac
  say "$osver · $arch"
  command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || fail "Lotus needs curl (or wget) to download itself. Install curl and run this again."

  tmp=$(mktemp -d "${TMPDIR:-/tmp}/lotus-install.XXXXXX")
  trap 'rm -rf "$tmp"' EXIT INT TERM

  # 1. zsh – Lotus' engine. macOS has it; Linux gets it after a yes.
  if ! command -v zsh >/dev/null 2>&1; then
    detect_pm
    install_cmd_for zsh
    note "Lotus runs on zsh, which is not installed here."
    if [ -n "$install_cmd" ]; then
      note "The command: $install_cmd"
      if ask "Install zsh now?"; then
        # the system's own question and password prompt stay visible; Lotus never sees a password
        $install_cmd < /dev/tty || fail "Installing zsh failed. Install zsh yourself and run this again."
      else
        fail "Without zsh Lotus cannot run. Install it ($install_cmd) and run this again."
      fi
    else
      fail "Install zsh with your package manager (as administrator), then run this again."
    fi
    command -v zsh >/dev/null 2>&1 || fail "zsh is still not there."
  fi
  if [ "$os" = macos ] && [ "$(basename "${SHELL:-zsh}")" != zsh ]; then
    note "Your login shell is $(basename "${SHELL:-}"). Lotus lives in zsh – switch with: chsh -s /bin/zsh"
  fi

  # 2. Lotus itself
  if [ -n "${LOTUS_SRC:-}" ]; then
    src=$LOTUS_SRC
  else
    say "Downloading Lotus …"
    fetch "https://github.com/$repo/archive/refs/heads/main.tar.gz" "$tmp/lotus.tar.gz" || fail "Download failed. Check your internet connection."
    tar -xzf "$tmp/lotus.tar.gz" -C "$tmp" || fail "The download could not be unpacked."
    src=$(ls -d "$tmp"/*/ | head -1)
    src=${src%/}
  fi
  [ -d "$src/lib" ] && [ -d "$src/bin" ] || fail "That does not look like Lotus ($src)."
  mkdir -p "$root" "$bin"
  rm -rf "$root/bin" "$root/lib" "$root/logos" "$root/data"
  cp -R "$src/bin" "$src/lib" "$src/logos" "$src/data" "$root/"
  chmod +x "$root/bin/lotus"
  ln -sf "$root/bin/lotus" "$bin/lotus"

  # 3. fastfetch (provides the system info and what plays): one that is there, else the pinned release, checked
  if command -v fastfetch >/dev/null 2>&1 || [ -x "$root/vendor/fastfetch" ]; then
    say "fastfetch is already installed."
  elif [ "$os" = macos ] && command -v brew >/dev/null 2>&1 && [ -O "$(brew --prefix 2>/dev/null)" ]; then
    say "Installing fastfetch via Homebrew …"
    brew install --quiet fastfetch || fail "brew install fastfetch failed."
  else
    plat=linux-$ffarch
    [ "$os" = macos ] && plat=macos-universal
    row=$(awk -F'\t' -v p="$plat" '$1 == "fastfetch" && $3 == p { print }' "$root/data/vendor.tsv")
    [ -n "$row" ] || fail "No fastfetch is pinned for $plat."
    url=$(printf '%s' "$row" | cut -f4)
    want=$(printf '%s' "$row" | cut -f5)
    say "Downloading fastfetch $(printf '%s' "$row" | cut -f2) …"
    fetch "$url" "$tmp/ff.tar.gz" || fail "The fastfetch download failed."
    have=$(sha256_of "$tmp/ff.tar.gz") || fail "Lotus cannot check the download: no sha256sum, shasum or openssl here."
    [ "$have" = "$want" ] || fail "The fastfetch download is not the file Lotus pinned – it was deleted, nothing was installed."
    mkdir -p "$tmp/ff" "$root/vendor"
    tar -xzf "$tmp/ff.tar.gz" -C "$tmp/ff" || fail "fastfetch could not be unpacked."
    ffbin=$(find "$tmp/ff" -type f -name fastfetch | head -1)
    [ -n "$ffbin" ] || fail "fastfetch is not in the download."
    cp "$ffbin" "$root/vendor/fastfetch"
    chmod +x "$root/vendor/fastfetch"
    if [ "$os" = macos ]; then xattr -d com.apple.quarantine "$root/vendor/fastfetch" 2>/dev/null; fi
  fi

  # 4. Optional helpers – Lotus works without them, single commands use them
  if [ "$os" = macos ]; then
    command -v brew >/dev/null 2>&1 || note "Homebrew not found – /brew and /install need it: https://brew.sh"
    command -v jq >/dev/null 2>&1   || note "jq not found – some commands need it on macOS 14 and older: brew install jq"
  else
    detect_pm
    [ -n "$pm" ] || note "No package manager found – /install and /brew need one."
    for tool in jq python3 git; do
      if ! command -v $tool >/dev/null 2>&1; then
        install_cmd_for $tool
        note "$tool not found – some commands need it${install_cmd:+: $install_cmd}"
      fi
    done
  fi

  # 5. Setup wizard (first install) and the line in your shell's startup file
  if { true < /dev/tty; } 2>/dev/null; then
    "$root/bin/lotus" setup --first < /dev/tty
  else
    "$root/bin/lotus" setup --hook
  fi
}

main "$@"
