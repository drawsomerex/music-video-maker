#!/usr/bin/env python3
"""Independent check on real music: how often do a model's word starts coincide with an acoustic onset in the vocal band (300–3500 Hz)?
usage: onset_support.py audio.wav words.json [words2.json ...]   (numpy needed; run with oMLX's python)"""
import sys, json, glob, wave
for sp in glob.glob("/Applications/oMLX.app/Contents/Resources/Python/*/lib/python3.*/site-packages"): sys.path.insert(0, sp)
import numpy as np
w = wave.open(sys.argv[1]); sr = w.getframerate(); x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768
n, hop = 1024, 160                                   # 64 ms window, 10 ms hop
win = np.hanning(n); frames = (len(x) - n) // hop
S = np.abs(np.fft.rfft(np.stack([x[i*hop:i*hop+n] * win for i in range(frames)]), axis=1))
f = np.fft.rfftfreq(n, 1 / sr); band = (f >= 300) & (f <= 3500)
B = np.log1p(30 * S[:, band]); flux = np.maximum(0, B[1:] - B[:-1]).sum(axis=1)       # spectral flux = onset novelty
flux = flux / (np.median(flux) + 1e-9)
def support(starts, shift=0.0):
    v = []
    for t in starts:
        i = int((t + shift) * 100)
        if 6 <= i < len(flux) - 6: v.append(flux[i - 5:i + 6].max())                    # strongest novelty within ±50 ms
    return np.array(v)
for p in sys.argv[2:]:
    ws = json.load(open(p)); st = [x["start"] for x in ws]
    a = support(st); b = np.concatenate([support(st, s) for s in (0.35, -0.35, 0.6, -0.6)])      # baseline: same words, shifted off their true positions
    print(f"{p.split('/')[-1][:-5]:<14} onset support {a.mean():5.2f} (baseline {b.mean():5.2f}, ratio {a.mean()/b.mean():.2f}) | words on a clear onset: {100*(a>2.5).mean():.0f}% (baseline {100*(b>2.5).mean():.0f}%)")
