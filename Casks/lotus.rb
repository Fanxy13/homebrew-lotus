cask "lotus" do
  version "2.4.4"
  sha256 "c21948c8c1fdbd8fe9a2eff1ba37fee08c4a8ba135f1bf0b2d0991bd1a1cc29d"

  url "https://github.com/Fanxy13/homebrew-lotus/archive/refs/tags/v#{version}.tar.gz"
  name "lotus"
  desc "Terminal start screen and command center: apps, weather, AI, Homebrew and more"
  homepage "https://fanxy13.github.io/homebrew-lotus/"

  depends_on formula: "fastfetch"

  binary "homebrew-lotus-#{version}/bin/lotus"

  # Hook lotus into ~/.zshrc right away, so one command is enough
  postflight_steps do
    run "homebrew-lotus-#{version}/bin/lotus",
        base:           :staged_path,
        args:           ["setup", "--hook"],
        env:            { "LOTUS_FOR_USER" => "{{user}}" },
        print_stdout:   true,
        writable_paths: [".zshrc", ".config/lotus", ".cache/lotus", ".local/state/lotus"],
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
    "~/.local/share/lotus/models",
    "~/.local/share/lotus/runtime",
    "~/.local/state/lotus",
  ]
end
