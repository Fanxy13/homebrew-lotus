class Lotus < Formula
  desc "Pretty terminal start screen with system info and live now-playing"
  homepage "https://github.com/Fanxy13/homebrew-lotus"
  url "https://github.com/Fanxy13/homebrew-lotus/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "de04cb09c09f2e0ddab3302ddc456b9bf88bc83de5c62a904ded9906a05c74d0"
  license "MIT"

  depends_on "fastfetch"
  depends_on :macos

  def install
    libexec.install "bin", "lib", "logos"
    bin.install_symlink libexec/"bin/lotus"
  end

  def caveats
    <<~EOS
      Run once so lotus starts with every new terminal:
        lotus setup
    EOS
  end

  test do
    assert_equal version.to_s, shell_output("#{bin}/lotus version").strip
  end
end
