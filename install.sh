#!/bin/zsh
# Install Lotus:
#   curl -fsSL https://raw.githubusercontent.com/Fanxy13/homebrew-lotus/main/install.sh | zsh

say()  { print -P "  %F{green}lotus%f  $*" }
note() { print -P "  %F{242}·%f      $*" }
fail() { print -P "  %F{red}✗%f      $*" >&2; exit 1 }

# Everything in one function, so "curl … | zsh" reads the whole script first
main() {
  setopt local_options err_exit
  local repo=${LOTUS_REPO:-Fanxy13/homebrew-lotus}
  local root=$HOME/.local/share/lotus bin=$HOME/.local/bin
  local tmp src arch macos

  # 0. What kind of Mac is this?
  [[ $OSTYPE == darwin* ]] || fail "Lotus runs on macOS only."
  macos=$(sw_vers -productVersion)
  arch=$(uname -m)
  (( ${macos%%.*} >= 11 )) || fail "Lotus needs macOS 11 or newer (this Mac: $macos)."
  say "macOS $macos · ${${arch/arm64/Apple silicon}/x86_64/Intel} · zsh $ZSH_VERSION"
  [[ ${SHELL:t} == zsh ]] || note "Your login shell is ${SHELL:t}. Lotus lives in zsh – switch with: chsh -s /bin/zsh"

  tmp=$(mktemp -d)
  trap "rm -rf ${(q)tmp}" EXIT

  # 1. Lotus itself
  if [[ -n $LOTUS_SRC ]]; then
    src=$LOTUS_SRC
  else
    say "Downloading Lotus …"
    curl -fsSL https://github.com/$repo/archive/refs/heads/main.tar.gz | tar -xz -C $tmp \
      || fail "Download failed. Check your internet connection."
    src=($tmp/*(/[1]))
  fi
  mkdir -p $root $bin
  rm -rf $root/bin $root/lib $root/logos $root/data
  cp -R $src/bin $src/lib $src/logos $src/data $root/
  chmod +x $root/bin/lotus
  ln -sf $root/bin/lotus $bin/lotus

  # 2. fastfetch (provides the system info)
  if (( $+commands[fastfetch] )) || [[ -x $root/vendor/fastfetch ]]; then
    say "fastfetch is already installed."
  elif (( $+commands[brew] )) && [[ -O $(brew --prefix) ]]; then   # only your own Homebrew
    say "Installing fastfetch via Homebrew …"
    brew install --quiet fastfetch || fail "brew install fastfetch failed."
  else
    say "Downloading fastfetch …"
    local farch=aarch64
    [[ $arch == x86_64 ]] && farch=amd64
    curl -fsSL https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-macos-$farch.tar.gz \
      | tar -xz -C $tmp || fail "fastfetch download failed."
    mkdir -p $root/vendor
    cp $tmp/fastfetch-macos-$farch/usr/bin/fastfetch $root/vendor/fastfetch
    xattr -d com.apple.quarantine $root/vendor/fastfetch 2>/dev/null || true
  fi

  # 3. Optional helpers – Lotus works without them, single commands use them
  (( $+commands[brew] )) || note "Homebrew not found – /brew and /install need it: https://brew.sh"
  (( $+commands[jq] ))   || note "jq not found – some commands need it on macOS 14 and older: brew install jq"

  # 4. Setup wizard (first install) and the ~/.zshrc lines
  if { true < /dev/tty } 2>/dev/null; then
    $root/bin/lotus setup --first < /dev/tty
  else
    $root/bin/lotus setup --hook
  fi
}

main "$@"
