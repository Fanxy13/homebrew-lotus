cask "lotus" do
  version "1.1.4"
  sha256 "a405237a46b0b599f7d6800e07b3773b4f5a02146c726a777a35514d3a2c7152"

  url "https://github.com/Fanxy13/homebrew-lotus/archive/refs/tags/v#{version}.tar.gz"
  name "lotus"
  desc "Terminal start screen with system info and live now playing"
  homepage "https://fanxy13.github.io/homebrew-lotus/"

  depends_on formula: "fastfetch"

  binary "homebrew-lotus-#{version}/bin/lotus"

  # Hook lotus into ~/.zshrc right away, so one command is enough
  postflight_steps do
    run "homebrew-lotus-#{version}/bin/lotus",
        base:           :staged_path,
        args:           ["setup"],
        env:            { "LOTUS_FOR_USER" => "{{user}}" },
        print_stdout:   true,
        writable_paths: [".zshrc", ".config/lotus", ".cache/lotus"],
        writable_base:  :home
  end

  # Take the ~/.zshrc lines out again when lotus is uninstalled
  uninstall_preflight_steps do
    run "homebrew-lotus-#{version}/bin/lotus",
        base:           :staged_path,
        args:           ["unhook"],
        env:            { "LOTUS_FOR_USER" => "{{user}}" },
        print_stdout:   true,
        writable_paths: [".zshrc"],
        writable_base:  :home
  end

  zap trash: [
    "~/.cache/lotus",
    "~/.config/lotus",
  ]
end
