#!/usr/bin/env python3
"""Which constant shift best lines word starts up with acoustic vocal onsets? usage: lag_scan.py audio.wav words.json
Positive best shift = words should be shown LATER; negative = EARLIER. (numpy via oMLX's python)"""
import sys, json, glob, wave
for sp in glob.glob("/Applications/oMLX.app/Contents/Resources/Python/*/lib/python3.*/site-packages"): sys.path.insert(0, sp)
import numpy as np
w = wave.open(sys.argv[1]); sr = w.getframerate(); x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768
n, hop = 1024, 160
win = np.hanning(n); frames = (len(x) - n) // hop
S = np.abs(np.fft.rfft(np.stack([x[i*hop:i*hop+n] * win for i in range(frames)]), axis=1))
f = np.fft.rfftfreq(n, 1 / sr); band = (f >= 300) & (f <= 3500)
B = np.log1p(30 * S[:, band]); flux = np.maximum(0, B[1:] - B[:-1]).sum(axis=1); flux /= (np.median(flux) + 1e-9)
flux = np.convolve(flux, np.ones(3) / 3, mode="same")          # light smoothing
ws = json.load(open(sys.argv[2])); ws = ws["words"] if isinstance(ws, dict) else ws; st = np.array([a["start"] for a in ws if "start" in a])
res = []
for s in np.arange(-0.40, 0.401, 0.02):
    idx = ((st + s) * 100).astype(int); idx = idx[(idx > 3) & (idx < len(flux) - 3)]
    res.append((s, flux[idx].mean()))
best = max(res, key=lambda r: r[1])
for s, v in res: print(f"{s*1000:+5.0f} ms  {'█' * int(v * 6):<40} {v:.2f}")
print(f"best shift: {best[0]*1000:+.0f} ms over {len(st)} words")
