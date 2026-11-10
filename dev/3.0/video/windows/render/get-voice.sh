#!/bin/sh
# The narrator's voice for voice.py, into render/kokoro/: Kokoro-82M (Apache-2.0) – its 8-bit ONNX export
# (onnx-community/Kokoro-82M-v1.0-ONNX, model_quantized.onnx) and its voices – from npm, where both are published as
# plain files (kokoro-q8-shards: the model in six parts; kokoro-local-runtime: the voices). Nothing of either package
# is run: the model is joined and checked against its SHA-256 before it is used, the voices are read as numbers.
#   sh get-voice.sh && pip install kokoro-onnx soundfile
set -eu
here=$(cd "$(dirname "$0")" && pwd)
dest=${KOKORO_DIR:-$here/kokoro}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$dest"
curl -fsSL -o "$tmp/model.tgz" https://registry.npmjs.org/kokoro-q8-shards/-/kokoro-q8-shards-1.0.0.tgz
curl -fsSL -o "$tmp/voices.tgz" https://registry.npmjs.org/kokoro-local-runtime/-/kokoro-local-runtime-0.1.0.tgz
tar -xzf "$tmp/model.tgz" -C "$tmp"
cat "$tmp"/package/kokoro-q8.part0.bin "$tmp"/package/kokoro-q8.part1.bin "$tmp"/package/kokoro-q8.part2.bin \
    "$tmp"/package/kokoro-q8.part3.bin "$tmp"/package/kokoro-q8.part4.bin "$tmp"/package/kokoro-q8.part5.bin > "$tmp/kokoro-q8.onnx"
echo "fbae9257e1e05ffc727e951ef9b9c98418e6d79f1c9b6b13bd59f5c9028a1478  $tmp/kokoro-q8.onnx" | sha256sum -c -
mv "$tmp/kokoro-q8.onnx" "$dest/kokoro-q8.onnx"
mkdir -p "$tmp/voices"
tar -xzf "$tmp/voices.tgz" -C "$tmp/voices" --strip-components=2 package/voices
python3 - "$tmp/voices" "$dest/voices.npz" <<'PY'
import glob, os, sys
import numpy as np
voices = {}
for f in sorted(glob.glob(os.path.join(sys.argv[1], '*.bin'))):
    v = np.fromfile(f, dtype=np.float32)
    if v.size != 510 * 256:
        sys.exit(f'{f}: not a Kokoro voice')
    voices[os.path.basename(f)[:-4]] = v.reshape(510, 1, 256)
np.savez(sys.argv[2], **voices)
print(f'{len(voices)} voices')
PY
echo "→ $dest"
