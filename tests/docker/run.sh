#!/bin/sh
# Runs the Lotus tests in a Linux container:  tests/docker/run.sh <ubuntu|debian|fedora|arch> [test names …]
# The repository is mounted read-only; every test runs in its own empty home inside the container.
set -e
distro=${1:?usage: tests/docker/run.sh <ubuntu|debian|fedora|arch> [test names]}
shift
root=$(cd "$(dirname "$0")/../.." && pwd)
platform=
[ "$distro" = arch ] && platform="--platform linux/amd64"
image=lotus-test:$distro
if [ -z "$(docker images -q $image)" ] || [ -n "$LOTUS_REBUILD" ]; then
  docker build $platform -q -f "$root/tests/docker/$distro.Dockerfile" -t $image "$root" >/dev/null
fi
priv=; [ -n "$LOTUS_TEST_PRIV" ] && priv="--privileged -u root"
exec docker run --rm $platform $priv -v "$root":/lotus:ro $image zsh tests/run.zsh "$@"
