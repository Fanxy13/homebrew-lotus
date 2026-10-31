#!/bin/sh
# Runs every test file in its own container, four at a time, and prints one line per file and the total:
#   tests/docker/par.sh <ubuntu|debian|fedora|arch> [test names …]
distro=${1:?usage: tests/docker/par.sh <distro> [test names]}
shift
root=$(cd "$(dirname "$0")/../.." && pwd)
platform=
[ "$distro" = arch ] && platform="--platform linux/amd64"
if [ $# -gt 0 ]; then names="$*"; else names=$(cd "$root/tests" && ls test-*.zsh | sed 's/^test-//; s/\.zsh$//'); fi
out=${LOTUS_TEST_OUT:-$(mktemp -d)}
mkdir -p "$out"
priv=; [ -n "$LOTUS_TEST_PRIV" ] && priv="--privileged -u root"
export LOTUS_P="$platform $priv" LOTUS_R="$root" LOTUS_D="$distro" LOTUS_O="$out"
printf '%s\n' $names | xargs -P "${LOTUS_TEST_JOBS:-4}" -n1 sh -c \
  'docker run --rm $LOTUS_P -v "$LOTUS_R":/lotus:ro lotus-test:$LOTUS_D zsh tests/run.zsh "$1" > "$LOTUS_O/$1.log" 2>&1; echo $? > "$LOTUS_O/$1.status"' _
pass=0; fail=0
for n in $names; do
  line=$(grep -E '^[0-9]+ passed, [0-9]+ failed' "$out/$n.log" | tail -1)
  p=$(echo "$line" | awk '{print $1}'); f=$(echo "$line" | awk '{print $3}')
  printf '%-22s %s\n' "$n" "${line:-NO RESULT (see $out/$n.log)}"
  pass=$((pass + ${p:-0})); fail=$((fail + ${f:-0}))
done
echo "TOTAL $pass passed, $fail failed  (logs: $out)"
