#!/usr/bin/env python3
"""The narrator of the Lotus for Windows video: Kokoro-82M (Apache-2.0), a neural voice that runs here, offline.

    python3 voice.py <lines.json> <out-dir>     lines.json: [{"id": "install", "text": "…"}, …]
                                                → <out-dir>/<id>.wav (48 kHz, mono) and <out-dir>/lines.json with the lengths

The model and the voices are not in the repository (90 MB). get-voice.sh puts them into render/kokoro/ (or point
KOKORO_DIR elsewhere): kokoro-q8.onnx, Kokoro's 8-bit ONNX export, and voices.npz, its voices. The runtime is the
kokoro-onnx package (pip install kokoro-onnx soundfile).
"""
import json
import os
import subprocess
import sys

import numpy as np
import soundfile as sf
from kokoro_onnx import Kokoro

HERE = os.path.dirname(os.path.abspath(__file__))
VOICE = os.environ.get('LOTUS_VIDEO_VOICE', 'af_heart')       # Kokoro's warmest voice
SPEED = float(os.environ.get('LOTUS_VIDEO_VOICE_SPEED', '1.04'))


def main(lines_path, out_dir):
    folder = os.environ.get('KOKORO_DIR', os.path.join(HERE, 'kokoro'))
    kokoro = Kokoro(os.path.join(folder, 'kokoro-q8.onnx'), os.path.join(folder, 'voices.npz'))
    os.makedirs(out_dir, exist_ok=True)
    done = []
    for line in json.load(open(lines_path, encoding='utf-8')):
        audio, sr = kokoro.create(line['text'], voice=line.get('voice', VOICE), speed=line.get('speed', SPEED), lang='en-us')
        audio = np.asarray(audio, dtype=np.float32)
        nz = np.flatnonzero(np.abs(audio) > 0.01)                 # no silence before and after the words
        if len(nz):
            audio = audio[max(0, nz[0] - int(0.03 * sr)):nz[-1] + int(0.12 * sr)]
        raw = os.path.join(out_dir, f"{line['id']}.24k.wav")
        sf.write(raw, audio, sr)
        out = os.path.join(out_dir, f"{line['id']}.wav")
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', raw, '-ar', '48000', '-ac', '1', out], check=True)
        os.remove(raw)
        done.append({**line, 'file': out, 'seconds': round(len(audio) / sr, 3)})
        print(f"{len(audio) / sr:5.2f} s  {line['id']}: {line['text']}", flush=True)
    json.dump(done, open(os.path.join(out_dir, 'lines.json'), 'w', encoding='utf-8'), indent=1)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
