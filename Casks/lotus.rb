cask "lotus" do
  version "3.2.0"
  sha256 "3f2d596fc61724f0cc933d70894289e5038fb8cf301cae348daff4d31bde2819"

  url "https://github.com/Fanxy13/homebrew-lotus/archive/refs/tags/v#{version}.tar.gz"
  name "lotus"
  desc "Terminal start screen and command center: apps, weather, AI, Homebrew and more"
  homepage "https://fanxy13.github.io/homebrew-lotus/"

  depends_on formula: "fastfetch"

  binary "homebrew-lotus-#{version}/bin/lotus"

  # Hook lotus into ~/.zshrc (and ~/.bashrc when bash is your login shell) right away, so one command is enough
  postflight_steps do
    run "homebrew-lotus-#{version}/bin/lotus",
        base:           :staged_path,
        args:           ["setup", "--hook"],
        env:            { "LOTUS_FOR_USER" => "{{user}}" },
        print_stdout:   true,
        writable_paths: [".zshrc", ".bashrc", ".config/lotus", ".cache/lotus", ".local/state/lotus"],
        writable_base:  :home
  end

  # Take the ~/.zshrc lines out again when lotus is uninstalled
  uninstall_preflight_steps do
    run "homebrew-lotus-#{version}/bin/lotus",
        base:           :staged_path,
        args:           ["unhook"],
        env:            { "LOTUS_FOR_USER" => "{{user}}" },
        print_stdout:   true,
        writable_paths: [".zshrc", ".bashrc"],
        writable_base:  :home
  end

  zap trash: [
    "~/.cache/lotus",
    "~/.config/lotus",
    "~/.local/share/lotus/models",
    "~/.local/share/lotus/runtime",
    "~/.local/state/lotus",
  ]
end
