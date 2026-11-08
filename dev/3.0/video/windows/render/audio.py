#!/usr/bin/env python3
"""The sound track of the Lotus for Windows video. The music is made here from numbers – a drum machine, a bass, a pad,
an electric piano and a few bell notes, all synthesized (no samples, nobody else's music) – and the sounds come from
the take: a key for every key typed (asciicast input events), a swish where a scene begins, a soft chime when a ✓
appears, the typing of the install line on the end card.

    python3 audio.py <cues.json> <out.wav>          (cues.json: {"duration": s, "cues": [{"t", "k", "d"}]}, from render.mjs)
"""
import json
import sys
import wave

import numpy as np

SR = 48000
BPM = 100
BEAT = 60 / BPM
BAR = 4 * BEAT
rng = np.random.default_rng(11)


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def tsec(n):
    return np.arange(n) / SR


def add(buf, start_s, sig, gain=1.0, pan=0.0):
    """Mix a mono or stereo signal into the stereo buffer at a time (pan: -1 left … 1 right)."""
    i = int(round(start_s * SR))
    if i >= buf.shape[1] or i + len(sig if sig.ndim == 1 else sig[0]) <= 0:
        return
    if sig.ndim == 1:
        left, right = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
        sig = np.vstack([sig * left * 1.4142, sig * right * 1.4142])
    n = sig.shape[1]
    a, b = max(0, i), min(buf.shape[1], i + n)
    buf[:, a:b] += gain * sig[:, a - i:b - i]


def band(sig, lo, hi):
    """A band of a short signal (FFT): what lies between lo and hi Hz, with soft edges."""
    spec = np.fft.rfft(sig)
    f = np.fft.rfftfreq(len(sig), 1 / SR)
    w = np.ones_like(f)
    if lo:
        w *= 1 / (1 + (lo / np.maximum(f, 1)) ** 4)
    if hi:
        w *= 1 / (1 + (f / hi) ** 4)
    return np.fft.irfft(spec * w, len(sig))


# ── The drum machine ──────────────────────────────────────────

def kick():
    t = tsec(int(0.5 * SR))
    f = 46 + 90 * np.exp(-t / 0.035)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.12)
    click = band(rng.standard_normal(len(t)), 1500, 6000) * np.exp(-t / 0.004) * 0.25
    return np.tanh(1.6 * (body + click)) * 0.9


def snare():
    t = tsec(int(0.35 * SR))
    tone = (np.sin(2 * np.pi * 185 * t) + 0.5 * np.sin(2 * np.pi * 330 * t)) * np.exp(-t / 0.045)
    noise = band(rng.standard_normal(len(t)), 900, 7000) * np.exp(-t / 0.11)
    return 0.45 * tone + 0.55 * noise / np.max(np.abs(noise))


def hat(open_=False):
    t = tsec(int((0.3 if open_ else 0.08) * SR))
    n = band(rng.standard_normal(len(t)), 7000, 16000)
    return n / np.max(np.abs(n)) * np.exp(-t / (0.09 if open_ else 0.018))


# ── The tones ─────────────────────────────────────────────────

def bass(note, dur):
    t = tsec(int((dur + 0.15) * SR))
    f = midi(note)
    y = np.sin(2 * np.pi * f * t) + 0.3 * np.sin(4 * np.pi * f * t) + 0.08 * np.sin(6 * np.pi * f * t)
    env = np.minimum(1, t / 0.006) * np.exp(-t / 0.55) * np.clip((dur + 0.15 - t) / 0.15, 0, 1)
    return np.tanh(1.3 * y * env)


def pad(notes, dur):
    """A soft, wide chord: three slightly detuned voices per note, each a few harmonics that fall away."""
    t = tsec(int((dur + 1.0) * SR))
    env = np.minimum(1, t / 0.55) * np.clip((dur + 1.0 - t) / 1.0, 0, 1)
    out = np.zeros((2, len(t)))
    for note in notes:
        for cents, pan in ((-7, -0.6), (0, 0.0), (7, 0.6)):
            f = midi(note) * 2 ** (cents / 1200)
            ph = rng.uniform(0, 2 * np.pi)
            y = sum(np.sin(2 * np.pi * f * k * t + ph * k) / k ** 1.5 for k in range(1, 9))
            add(out, 0, y * env * 0.33, 1.0, pan)
    return out


def epiano(note, vel=1.0):
    t = tsec(int(1.6 * SR))
    f = midi(note)
    mod = 1.7 * np.exp(-t / 0.22) * np.sin(2 * np.pi * f * t)
    y = np.sin(2 * np.pi * f * t + mod) + 0.18 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t / 0.12)
    return y * np.minimum(1, t / 0.003) * np.exp(-t / 0.75) * vel


def bell(freq, dur=1.4):
    t = tsec(int(dur * SR))
    y = np.sin(2 * np.pi * freq * t) + 0.35 * np.sin(2 * np.pi * freq * 2.76 * t) * np.exp(-t / 0.18) \
        + 0.12 * np.sin(2 * np.pi * freq * 5.4 * t) * np.exp(-t / 0.07)
    return y * np.minimum(1, t / 0.002) * np.exp(-t / (dur / 3))


# ── The sounds of the take ────────────────────────────────────

def key_click(kind):
    t = tsec(int(0.09 * SR))
    if kind == 'enter':
        thock = np.sin(2 * np.pi * rng.uniform(150, 175) * t) * np.exp(-t / 0.028)
        snap = band(rng.standard_normal(len(t)), 2000, 9000) * np.exp(-t / 0.004)
        return 0.75 * thock + 0.5 * snap / np.max(np.abs(snap))
    ping = np.sin(2 * np.pi * rng.uniform(1800, 2800) * t) * np.exp(-t / 0.006)
    snap = band(rng.standard_normal(len(t)), 2500, 11000) * np.exp(-t / 0.0025)
    thud = np.sin(2 * np.pi * rng.uniform(110, 150) * t) * np.exp(-t / 0.012)
    return 0.35 * ping + 0.6 * snap / np.max(np.abs(snap)) + 0.35 * thud


def swish(dur=0.75):
    t = tsec(int(dur * SR))
    noise = rng.standard_normal(len(t))
    dark, bright = band(noise, 150, 1200), band(noise, 600, 7000)
    m = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 1.5
    y = (1 - m) * dark / np.max(np.abs(dark)) + m * bright / np.max(np.abs(bright))
    env = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 2
    out = np.zeros((2, len(t)))
    pan = np.linspace(-0.7, 0.7, len(t))
    out[0] = y * env * np.cos((pan + 1) * np.pi / 4) * 1.41
    out[1] = y * env * np.sin((pan + 1) * np.pi / 4) * 1.41
    return out


def reverb(sig, wet=0.25, length=1.8, decay=0.42):
    """A room: the signal convolved with fading noise, a little different left and right (overlap-add, block by block)."""
    n = int(length * SR)
    t = tsec(n)
    out = np.zeros_like(sig)
    for ch in range(2):
        ir = rng.standard_normal(n) * np.exp(-t / decay)
        ir[: int(0.012 * SR)] = 0
        ir /= np.sqrt(np.sum(ir ** 2))
        block = 1 << 18
        size = 1 << int(np.ceil(np.log2(block + n)))
        IR = np.fft.rfft(ir, size)
        x = sig[ch]
        y = np.zeros(len(x) + n)
        for s in range(0, len(x), block):
            seg = x[s:s + block]
            conv = np.fft.irfft(np.fft.rfft(seg, size) * IR, size)[: len(seg) + n]
            y[s:s + len(conv)] += conv
        out[ch] = y[: len(x)]
    return sig * (1 - wet) + out * wet * 2.2


# ── The music ─────────────────────────────────────────────────

CHORDS = [  # F△7 – G6 – Em7 – Am7, one a bar: (the bass's root, the pad's notes, the piano's notes)
    (41, [53, 57, 60, 64], [65, 69, 72, 76]),
    (43, [55, 59, 62, 64], [67, 71, 74, 76]),
    (40, [52, 55, 59, 62], [64, 67, 71, 74]),
    (45, [57, 60, 64, 67], [69, 72, 76, 79]),
]
ARP = [[0, 2, 1, 3, 2, 1, 3, 2], [0, 1, 2, 3, 3, 2, 1, 2], [3, 1, 2, 0, 2, 3, 1, 2]]


def music(duration):
    bars = int(np.ceil(duration / BAR)) + 1
    n = int((duration + 3) * SR)
    drums, bassb, padb, keys = (np.zeros((2, n)) for _ in range(4))
    swing = 0.09 * BEAT                            # the eighths a little late: it breathes
    mid = (bars // 2) // 4 * 4
    kicks = []
    for b in range(bars):
        t0 = b * BAR
        root, pad_notes, piano = CHORDS[b % 4]
        intro, outro = b < 2, b >= bars - 3
        breakdown = mid <= b < mid + 2
        add(padb, t0, pad(pad_notes, BAR), 0.11 if not breakdown else 0.15)
        pattern = ARP[(b // 8) % len(ARP)]
        for k, idx in enumerate(pattern):          # the piano: eighths through the chord
            t = t0 + k * BEAT / 2 + (swing if k % 2 else 0)
            vel = (0.95 if k % 2 == 0 else 0.7) * (0.6 if intro or outro else 1.0) * rng.uniform(0.9, 1.05)
            add(keys, t, epiano(piano[idx] + 12 + (12 if (b // 4) % 2 and k == 7 else 0), vel), 0.2, -0.25 + 0.5 * (idx / 3))
        if intro or outro:
            continue
        for beat in range(4):                      # the drums
            t = t0 + beat * BEAT
            if not breakdown and beat in (0, 2):
                add(drums, t, kick(), 0.55); kicks.append(t)
            if not breakdown and beat == 2 and b % 2 == 1:
                add(drums, t + BEAT / 2 + swing, kick(), 0.32); kicks.append(t + BEAT / 2 + swing)
            if beat in (1, 3) and not breakdown:
                add(drums, t, snare(), 0.36, 0.1)
            for h in range(2):
                ht = t + h * BEAT / 2 + (swing if h else 0)
                add(drums, ht, hat(open_=(beat == 3 and h == 1)), 0.13 if h else 0.17, -0.3)
        if not breakdown:                          # the bass: the root, and a push before the next bar
            add(bassb, t0, bass(root, BEAT * 1.5), 0.34)
            add(bassb, t0 + BEAT * 1.75 + swing, bass(root, BEAT * 0.6), 0.24)
            add(bassb, t0 + BEAT * 2.5 + swing, bass(root + 12, BEAT * 0.4), 0.17)
            add(bassb, t0 + BEAT * 3.0, bass(root + 7, BEAT * 0.9), 0.21)
        if (b // 8) % 2 == 1 and b % 4 == 0 and not breakdown:   # now and then, three bell notes on top
            for j, note in enumerate(piano[1:]):
                add(keys, t0 + BEAT * (2 + j * 0.5), bell(midi(note + 12)), 0.05, 0.3 - 0.3 * j)
    duck = np.ones(n)                              # the kick pushes the rest aside for a moment
    for t in kicks:
        i = int(t * SR); m = min(n, i + int(0.3 * SR))
        duck[i:m] = np.minimum(duck[i:m], 1 - 0.38 * np.exp(-tsec(m - i) / 0.11))
    tone = reverb(padb + keys, wet=0.32) * duck + bassb * duck
    mix = tone + reverb(drums, wet=0.12)
    return mix


def render(spec, out_path):
    duration = float(spec['duration'])
    n = int(round(duration * SR))
    mus = music(duration)[:, :n]
    mus /= np.sqrt(np.mean(mus ** 2)) / 0.11      # a bed: about −19 dB, under the sounds
    t = tsec(n)
    mus *= np.minimum(1, t / 0.4) * np.clip((duration - t) / 2.8, 0, 1)
    sfx = np.zeros((2, n))
    clicks = {k: [key_click(k) for _ in range(8)] for k in ('key', 'enter')}
    for c in spec['cues']:
        k, t0 = c['k'], c['t']
        if k == 'key':
            d = c.get('d', '')
            if d in ('\r', '\n'):
                add(sfx, t0, clicks['enter'][rng.integers(8)], 0.26, rng.uniform(-0.15, 0.15))
            elif len(d) > 3 and not d.startswith('\x1b'):     # pasted: Ctrl and V
                add(sfx, t0 - 0.09, clicks['key'][rng.integers(8)], 0.16)
                add(sfx, t0, clicks['key'][rng.integers(8)], 0.18)
            else:
                add(sfx, t0, clicks['key'][rng.integers(8)], rng.uniform(0.14, 0.2), rng.uniform(-0.2, 0.2))
        elif k == 'swish':
            add(sfx, t0 - 0.32, swish(), 0.16)
        elif k == 'chime':
            add(sfx, t0, bell(midi(88), 1.6), 0.07, 0.2)
            add(sfx, t0 + 0.07, bell(midi(95), 1.6), 0.05, -0.2)
        elif k == 'title':
            for j, note in enumerate((84, 88, 91, 96)):        # the title comes: four bell notes
                add(sfx, t0 + 1.05 + j * 0.09, bell(midi(note), 2.2), 0.06, -0.3 + 0.2 * j)
        elif k == 'end':
            add(sfx, t0 - 0.2, swish(0.9), 0.14)
            for j in range(80):                                 # the install line, typed on the card
                add(sfx, t0 + 1.2 + j / 46, clicks['key'][rng.integers(8)], 0.1, rng.uniform(-0.2, 0.2))
    sfx = reverb(sfx, wet=0.12, length=0.8, decay=0.12)
    # the narrator, in the middle; the music steps back while it speaks
    voice = np.zeros(n)
    for c in spec['cues']:
        if c['k'] != 'voice':
            continue
        with wave.open(c['file'], 'rb') as w:
            v = np.frombuffer(w.readframes(w.getnframes()), '<i2').astype(np.float64) / 32768
        i = int(round(c['t'] * SR)); j = min(n, i + len(v))
        voice[i:j] += v[: j - i]
    if np.any(voice):
        loud = np.abs(voice) > 0.01
        voice *= 0.16 / np.sqrt(np.mean(voice[loud] ** 2))     # the spoken parts at about −16 dB
        hop = int(0.01 * SR)                                    # how much it speaks, every 10 ms, held a little
        act = np.array([np.max(np.abs(voice[k:k + hop])) > 0.02 for k in range(0, n, hop)], dtype=float)
        env = np.zeros_like(act); e = 0.0
        for k, x in enumerate(act):
            e += (x - e) * (0.35 if x > e else 0.03)            # quick to duck, slow to come back
            env[k] = e
        env = np.repeat(env, hop)[:n]
        mus *= 1 - 0.55 * env
        sfx *= 1 - 0.25 * env
    mix = mus + sfx + voice
    mix = np.tanh(1.1 * mix) / np.tanh(1.1)
    mix *= 0.89 / max(1e-9, np.max(np.abs(mix)))
    pcm = (np.clip(mix, -1, 1).T * 32767).astype('<i2')
    with wave.open(out_path, 'wb') as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(pcm.tobytes())


if __name__ == '__main__':
    render(json.load(open(sys.argv[1], encoding='utf-8')), sys.argv[2])
