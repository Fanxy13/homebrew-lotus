#!/bin/zsh
# Install lotus:
#   curl -fsSL https://raw.githubusercontent.com/Fanxy13/homebrew-lotus/main/install.sh | zsh

say()  { print -P "%F{green}🪷%f $*" }
fail() { print -P "%F{red}✗%f $*" >&2; exit 1 }

# Everything in one function, so "curl … | zsh" reads the whole script first
main() {
  setopt local_options err_exit
  local repo=${LOTUS_REPO:-Fanxy13/homebrew-lotus}
  local root=$HOME/.local/share/lotus bin=$HOME/.local/bin
  local tmp src arch

  [[ $OSTYPE == darwin* ]] || fail "lotus only runs on macOS."
  tmp=$(mktemp -d)
  trap "rm -rf ${(q)tmp}" EXIT

  # 1. lotus itself
  if [[ -n $LOTUS_SRC ]]; then
    src=$LOTUS_SRC
  else
    say "Downloading lotus …"
    curl -fsSL https://github.com/$repo/archive/refs/heads/main.tar.gz | tar -xz -C $tmp \
      || fail "Download failed."
    src=($tmp/*(/[1]))
  fi
  mkdir -p $root $bin
  rm -rf $root/bin $root/lib $root/logos
  cp -R $src/bin $src/lib $src/logos $root/
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
    arch=aarch64
    [[ $(uname -m) == x86_64 ]] && arch=amd64
    curl -fsSL https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-macos-$arch.tar.gz \
      | tar -xz -C $tmp || fail "fastfetch download failed."
    mkdir -p $root/vendor
    cp $tmp/fastfetch-macos-$arch/usr/bin/fastfetch $root/vendor/fastfetch
    xattr -d com.apple.quarantine $root/vendor/fastfetch 2>/dev/null || true
  fi

  # 3. Add to ~/.zshrc
  $root/bin/lotus setup
}

main "$@"
