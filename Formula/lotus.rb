class Lotus < Formula
  desc "Pretty terminal start screen with system info and live now-playing"
  homepage "https://github.com/Fanxy13/homebrew-lotus"
  url "https://github.com/Fanxy13/homebrew-lotus/archive/refs/tags/v1.1.0.tar.gz"
  sha256 "733f06fd9802b2e6fa955939d0e98389e02e93ff67658cd27a3a453a777dd426"
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
