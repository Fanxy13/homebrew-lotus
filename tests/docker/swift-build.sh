#!/bin/sh
# Compiles the AI program (lib/ai/*.swift) on Linux in the official Swift image and lists the errors:
#   tests/docker/swift-build.sh [errors|build]      "build" keeps the binary in tests/docker/.build/lotus-ai-linux-<arm64|x86_64>
#   (the tests find it through LOTUS_PREBUILT_DIR; a release carries the same file, pinned in data/vendor.tsv)
root=$(cd "$(dirname "$0")/../.." && pwd)
mode=${1:-errors}
mkdir -p "$root/tests/docker/.build"
if [ "$mode" = build ]; then
  exec docker run --rm -v "$root":/lotus:ro -v "$root/tests/docker/.build":/out swift:6.1-noble sh -c \
    'case $(uname -m) in aarch64) a=arm64 ;; *) a=x86_64 ;; esac; cd /tmp && swiftc -O -parse-as-library -swift-version 5 -o /out/lotus-ai-linux-$a /lotus/lib/ai/*.swift 2>&1 | grep -E "error|warning: unre" | head -40'
fi
docker run --rm -v "$root":/lotus:ro swift:6.1-noble sh -c \
  'cd /tmp && swiftc -Onone -parse-as-library -swift-version 5 -o /tmp/lotus-ai /lotus/lib/ai/*.swift 2>&1 | grep -E "error:" | sed "s|/lotus/lib/ai/||" | sort -u | head -${LOTUS_ERRORS:-60}'
