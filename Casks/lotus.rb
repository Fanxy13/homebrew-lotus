cask "lotus" do
  version "1.1.1"
  sha256 "92cd80b9898ef8a6d78424f83037bde421083382debe19b583a795455e54d3e4"

  url "https://github.com/Fanxy13/homebrew-lotus/archive/refs/tags/v#{version}.tar.gz"
  name "lotus"
  desc "Terminal start screen with system info and live now playing"
  homepage "https://fanxy13.github.io/homebrew-lotus/"

  depends_on formula: "fastfetch"

  binary "homebrew-lotus-#{version}/bin/lotus"

  # Hook lotus into ~/.zshrc right away, so one command is enough
  postflight do
    system_command "#{staged_path}/homebrew-lotus-#{version}/bin/lotus",
                   args:         ["setup"],
                   print_stdout: true
  end

  # Take the ~/.zshrc lines out again when lotus is uninstalled
  uninstall_preflight do
    system_command "#{staged_path}/homebrew-lotus-#{version}/bin/lotus",
                   args:         ["unhook"],
                   print_stdout: true
  end

  zap trash: [
    "~/.cache/lotus",
    "~/.config/lotus",
  ]
end
