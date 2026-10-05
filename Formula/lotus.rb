class Lotus < Formula
  desc "Pretty terminal start screen with system info and live now-playing"
  homepage "https://github.com/Fanxy13/homebrew-lotus"
  url "https://github.com/Fanxy13/homebrew-lotus/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"

  depends_on "fastfetch"
  depends_on :macos

  def install
    libexec.install "bin", "lib", "logos"
    bin.install_symlink libexec/"bin/lotus"
  end

  def caveats
    <<~EOS
      Einmal ausführen, damit lotus beim Öffnen des Terminals startet:
        lotus setup
    EOS
  end

  test do
    assert_equal version.to_s, shell_output("#{bin}/lotus version").strip
  end
end
