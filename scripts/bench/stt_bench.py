#!/usr/bin/env python3
"""Word-timing benchmark for speech models, run with oMLX's bundled MLX runtime (read-only use; writes only under --out).
usage: stt_bench.py <label> <kind: parakeet|whisper|aligner> <model dir> <audio.wav> <lyrics.txt> <out dir> [--bits N]
Prints one JSON line: label, size_gb (weights as loaded), load_s, run_s (steady state, 2nd run), rtf, peak_gb, words. Saves <out>/<label>.json = [{text,start,end}]."""
import sys, os, glob, time, json, re
for sp in glob.glob("/Applications/oMLX.app/Contents/Resources/Python/*/lib/python3.*/site-packages"): sys.path.insert(0, sp)
import mlx.core as mx, mlx.nn as nn
from mlx.utils import tree_flatten
from mlx_audio.stt.utils import load_audio, load_model

label, kind, mdir, audio_path, lyrics_path, out = sys.argv[1:7]
bits = int(sys.argv[sys.argv.index("--bits") + 1]) if "--bits" in sys.argv else None
os.makedirs(out, exist_ok=True)
peak = lambda: (mx.get_peak_memory() if hasattr(mx, "get_peak_memory") else mx.metal.get_peak_memory()) / 1e9
reset = lambda: (mx.reset_peak_memory() if hasattr(mx, "reset_peak_memory") else mx.metal.reset_peak_memory())
lyrics = " ".join(l.strip() for l in open(lyrics_path) if l.strip())

def quantize(model, bits):
    nn.quantize(model, group_size=64, bits=bits, class_predicate=lambda p, m: isinstance(m, nn.Linear) and m.weight.shape[-1] % 64 == 0)
    mx.eval(model.parameters())

reset(); t = time.time()
if kind == "parakeet":
    from mlx_audio.stt.models.parakeet import Model
    model = Model.from_pretrained(mdir)
elif kind == "whisper":
    model = load_model(mdir)
else:
    model = load_model(mdir)
if bits: quantize(model, bits)
mx.eval(model.parameters()); load_s = time.time() - t
size = sum(v.nbytes for _, v in tree_flatten(model.parameters())) / 1e9

def run():
    if kind == "parakeet":
        sr = model.preprocessor_config.sample_rate
        res = model.generate(load_audio(audio_path, sr, dtype=mx.bfloat16), chunk_duration=120.0, overlap_duration=15.0)
        words, cur = [], None
        for s in res.sentences:
            for tk in s.tokens:
                if cur is None or tk.text.startswith(" "):
                    if cur: words.append(cur)
                    cur = {"text": tk.text.strip(), "start": float(tk.start), "end": float(tk.end)}
                else: cur["text"] += tk.text; cur["end"] = float(tk.end)
        if cur: words.append(cur)
        return [w for w in words if w["text"]]
    if kind == "whisper":
        res = model.generate(audio_path, word_timestamps=True, language="en")
        words = []
        for seg in (res.segments or []):
            for w in seg.get("words", []) if isinstance(seg, dict) else getattr(seg, "words", []):
                g = (lambda k: w[k]) if isinstance(w, dict) else (lambda k: getattr(w, k))
                words.append({"text": g("word").strip(), "start": float(g("start")), "end": float(g("end"))})
        return [w for w in words if w["text"]]
    res = model.generate(audio_path, text=lyrics, language="English")
    return [{"text": i.text, "start": float(i.start_time), "end": float(i.end_time)} for i in res.items]

t = time.time(); words = run(); first_s = time.time() - t
t = time.time(); words = run(); run_s = time.time() - t
json.dump(words, open(f"{out}/{label}.json", "w"))
dur = len(load_audio(audio_path, 16000)) / 16000
print(json.dumps({"label": label, "size_gb": round(size, 3), "load_s": round(load_s, 1), "first_s": round(first_s, 1), "run_s": round(run_s, 1),
                  "rtf": round(dur / run_s), "peak_gb": round(peak(), 2), "words": len(words)}))
