#!/bin/sh
# Builds the AI program (lib/ai/*.swift) as ONE static file that runs on any Linux (musl, no Swift runtime needed) –
# the file a release carries for Linux:   tests/docker/swift-static.sh [arm64|x86_64]
# The Swift 6.1 "Static Linux SDK" comes from download.swift.org; its sha256 is the one swift.org publishes for 6.1.
# Result: tests/docker/.build/lotus-ai-linux-<arch>
root=$(cd "$(dirname "$0")/../.." && pwd)
arch=${1:-$(uname -m)}
case $arch in arm64|aarch64) arch=arm64; triple=aarch64-swift-linux-musl; plat= ;; *) arch=x86_64; triple=x86_64-swift-linux-musl; plat="--platform linux/amd64" ;; esac
sdk=${LOTUS_SWIFT_SDK_DIR:-$HOME/.local/share/lotus-dev/swift-sdk}
if [ -z "$(docker images -q lotus-swift-static)" ]; then
  [ -f "$sdk/swift-6.1-RELEASE_static-linux-0.0.1.artifactbundle.tar.gz" ] || curl -fL -o "$sdk/swift-6.1-RELEASE_static-linux-0.0.1.artifactbundle.tar.gz" \
    https://download.swift.org/swift-6.1-release/static-sdk/swift-6.1-RELEASE/swift-6.1-RELEASE_static-linux-0.0.1.artifactbundle.tar.gz
  cat > "$sdk/Dockerfile" <<'D'
FROM swift:6.1-noble
COPY swift-6.1-RELEASE_static-linux-0.0.1.artifactbundle.tar.gz /tmp/sdk.tar.gz
RUN echo "111c6f7d280a651208b8c74c0521dd99365d785c1976a6e23162f55f65379ac6  /tmp/sdk.tar.gz" | sha256sum -c - && swift sdk install /tmp/sdk.tar.gz && rm /tmp/sdk.tar.gz
D
  docker build -q -t lotus-swift-static "$sdk" >/dev/null || exit 1
fi
mkdir -p "$root/tests/docker/.build"
exec docker run --rm $plat -v "$root":/lotus:ro -v "$root/tests/docker/.build":/out lotus-swift-static sh -c '
set -e
mkdir -p /tmp/pkg/Sources/lotus-ai && cp /lotus/lib/ai/*.swift /tmp/pkg/Sources/lotus-ai/
cat > /tmp/pkg/Package.swift <<P
// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "lotus-ai", targets: [.executableTarget(name: "lotus-ai", path: "Sources/lotus-ai")])
P
cd /tmp/pkg
swift build -c release --swift-sdk '"$triple"' 2>&1 | grep -E "error|Compiling|Build complete" | grep -vE "^\[[0-9]+/" | head -40
strip .build/release/lotus-ai 2>/dev/null || true
cp .build/release/lotus-ai /out/lotus-ai-linux-'"$arch"'
ls -la /out/lotus-ai-linux-'"$arch"'
'
