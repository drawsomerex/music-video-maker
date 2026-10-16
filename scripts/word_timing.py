#!/usr/bin/env python3
"""Word-level timestamps from the user's own Parakeet model, run with oMLX's bundled Python/MLX runtime.
usage: word_timing.py <audio file> <model dir> [start_sec end_sec]   → JSON [{"text","start","end"}, ...] on stdout
"""
import sys, os, json, glob

app = os.environ.get("OMLX_APP", "/Applications/oMLX.app")
for sp in glob.glob(os.path.join(app, "Contents/Resources/Python/*/lib/python3.*/site-packages")):
    sys.path.insert(0, sp)

import mlx.core as mx
from mlx_audio.stt.models.parakeet import Model
from mlx_audio.stt.utils import load_audio

path, model_dir = sys.argv[1], sys.argv[2]
model = Model.from_pretrained(model_dir)
sr = model.preprocessor_config.sample_rate
audio = load_audio(path, sr, dtype=mx.bfloat16)
offset = 0.0
if len(sys.argv) >= 5:
    a, b = float(sys.argv[3]), float(sys.argv[4])
    audio = audio[int(a * sr): int(b * sr)]; offset = a

res = model.generate(audio, chunk_duration=120.0, overlap_duration=15.0)
words, cur = [], None
for sent in res.sentences:
    for t in sent.tokens:
        txt = t.text
        if cur is None or txt.startswith(" "):
            if cur: words.append(cur)
            cur = {"text": txt.strip(), "start": float(t.start) + offset, "end": float(t.end) + offset}
        else:
            cur["text"] += txt; cur["end"] = float(t.end) + offset
if cur: words.append(cur)
json.dump([w for w in words if w["text"]], sys.stdout)
