#!/usr/bin/env python3
"""Runs the app's two real language-model jobs on a project with one model and records speed/memory/outputs.
usage: llm_bench.py <label> <model dir> <project.mvproj> <out dir>     (run with oMLX's bundled python; read-only use)"""
import sys, os, glob, time, json
for sp in glob.glob("/Applications/oMLX.app/Contents/Resources/Python/*/lib/python3.*/site-packages"): sys.path.insert(0, sp)
import mlx.core as mx
from mlx_lm import load, stream_generate
from mlx_lm.sample_utils import make_sampler

label, mdir, proj, out = sys.argv[1:5]; os.makedirs(out, exist_ok=True)
plan = json.load(open(proj)); title = plan["title"]
lines = [l["text"] for l in plan["lines"]]
secs = [{"id": -1, "lineIDs": []}] + [{"id": s["id"], "lineIDs": s["lineIDs"]} for s in plan["sections"]]
peak = lambda: (mx.get_peak_memory() if hasattr(mx, "get_peak_memory") else mx.metal.get_peak_memory()) / 1e9
(mx.reset_peak_memory() if hasattr(mx, "reset_peak_memory") else mx.metal.reset_peak_memory())

t0 = time.time(); model, tok = load(mdir); load_s = time.time() - t0
def gen(prompt, max_tokens):
    msgs = [{"role": "user", "content": prompt}]
    try: text = tok.apply_chat_template(msgs, add_generation_prompt=True, enable_thinking=False, tokenize=False)
    except TypeError: text = tok.apply_chat_template(msgs, add_generation_prompt=True, tokenize=False)
    s, res, t = "", None, time.time()
    for r in stream_generate(model, tok, prompt=text, max_tokens=max_tokens, sampler=make_sampler(temp=0.2)): s += r.text; res = r
    if "</think>" in s: s = s.split("</think>", 1)[1]
    return s.strip(), {"prompt_tokens": res.prompt_tokens, "prompt_tps": round(res.prompt_tps), "gen_tokens": res.generation_tokens, "gen_tps": round(res.generation_tps, 1), "secs": round(time.time() - t, 1)}

def looks_bad(s):
    l = s.lower(); return len(s) < 40 or l.startswith("the user") or "reply with only" in l or "3–5 sentences" in l or "3-5 sentences" in l

describe = f"""Song title: “{title}”

Lyrics:
{chr(10).join(lines)}

Write a description of this song that an illustrator could use to picture it. In 3–5 sentences cover: the concrete setting (place, era, landscape), the story or subject, the mood and emotional arc, and the recurring people/objects/images worth keeping consistent. Be specific and visual; do not quote the lyrics or list the verses. Reply with ONLY the description text."""
desc, st1 = gen(describe, 400)
if looks_bad(desc):
    plain = f"""Song: “{title}”
Lyrics:
{chr(10).join(lines)}

In four sentences, describe where and when this song is set, what happens in it, its mood, and the main objects and scenery that appear. Plain prose.

Description:"""
    desc, st1b = gen(plain, 350); st1["retry"] = True
if looks_bad(desc): desc = f"A song called “{title}”. It opens: {' '.join(lines[:6])} The imagery follows the story the lyrics tell, with a consistent setting, era and mood throughout."; st1["fallback"] = True

body = f"""Song: “{title}”.
Song description: {desc}

We are making a lyric music video. Use the song description below as the single source of truth for setting, era, mood and recurring subjects. A human will paste each prompt below into an AI image generator and load the pictures back in, so the images must look like they belong together.
1. Invent ONE visual style line that suits this song and keeps every image consistent: medium (e.g. cinematic photograph / oil painting / vintage illustration), colour palette, lighting, era, mood. 20–35 words.
2. For each numbered section write a vivid, concrete, self-contained image prompt (1–2 sentences, 25–45 words) depicting what that section's lyrics describe or evoke: setting, subject, composition (wide or medium shot, no close-ups of faces), time of day, weather. Keep places, era and recurring subjects consistent from section to section. If a section's lyrics repeat an earlier one (a chorus), show a different moment or camera angle of the same story beat. NO text, lettering, signs or logos in the image. Do not repeat the style line inside the prompts. Section -1 is the opening title-card background: an establishing scene for the whole song.
Reply with ONLY JSON: {{"style":"...","sections":[{{"i":-1,"prompt":"..."}},{{"i":0,"prompt":"..."}}, ...]}}

"""
for s in secs:
    t = "(instrumental break — an establishing scene for the song's setting)" if not s["lineIDs"] else " / ".join(lines[i] for i in s["lineIDs"])
    body += f"{s['id']}: {t}\n"
prompts, st2 = gen(body, 4000)
res = {"label": label, "load_s": round(load_s, 1), "peak_gb": round(peak(), 2), "describe": desc, "describe_stats": st1, "prompts_raw": prompts, "prompts_stats": st2,
       "total_gen_s": round(st1["secs"] + st2["secs"], 1)}
json.dump(res, open(f"{out}/{label}.json", "w"), indent=1)
print(json.dumps({k: res[k] for k in ("label", "load_s", "peak_gb", "total_gen_s")} | {"desc_tps": st1["gen_tps"], "json_tps": st2["gen_tps"], "json_tokens": st2["gen_tokens"]}))
