#!/usr/bin/env python3
"""Automatic quality checks on llm_bench outputs. usage: score_llm.py <out dir> — prints a table. Heuristic, tuned to the Caney River test song."""
import sys, json, re, glob, os
def jparse(s):
    s = s.replace("```json", "").replace("```", "")
    for a, b in (("{", "}"), ("[", "]")):
        i, j = s.find(a), s.rfind(b)
        if 0 <= i < j:
            try: return json.loads(s[i:j + 1])
            except Exception: pass
    return None
BAD_ERA = re.compile(r"\b(modern|contemporary|1997|20\d\d|digital|smartphone|futuristic)\b", re.I)
NELLIE_PERSON = re.compile(r"Nellie[^.]{0,70}\b(she|her|woman|lady|girl|daughter|stands|smiles|waves|hands)\b", re.I)
rows = []
for f in sorted(glob.glob(os.path.join(sys.argv[1], "*.json"))):
    r = json.load(open(f)); d = r["describe"]; sc_d = 0; notes = []
    low = d.lower()
    if not (low.startswith("the user") or "reply with only" in low) and len(d) > 40: sc_d += 10
    else: notes.append("echo/fallback")
    if r["describe_stats"].get("fallback"): sc_d -= 10; notes.append("fallback")
    if re.search(r"caney|bartlesville|oklahoma", d, re.I): sc_d += 6
    if re.search(r"1897|1890|nineteenth", d): sc_d += 8
    if BAD_ERA.search(d): sc_d -= 8; notes.append("wrong era")
    if re.search(r"derrick|oil", d, re.I): sc_d += 6
    n_sent = len(re.findall(r"[.!?](\s|$)", d)); sc_d += 5 if 3 <= n_sent <= 7 else 0
    if not re.search(r"^\s*[-*#\d]", d, re.M): sc_d += 5
    if NELLIE_PERSON.search(d): sc_d -= 6; notes.append("Nellie as person")
    sc_d = max(0, min(40, sc_d))
    o = jparse(r["prompts_raw"]); sc_p = 0; np_ = 0
    if isinstance(o, dict) and isinstance(o.get("sections"), list):
        sc_p += 15
        secs = {}
        for e in o["sections"]:
            try: secs[int(e.get("i"))] = str(e.get("prompt", ""))
            except Exception: pass
        want = set(range(-1, 13)); np_ = len(want & set(secs)); sc_p += round(15 * np_ / len(want))
        ps = [secs[i] for i in want if i in secs]
        if ps:
            wl = [len(p.split()) for p in ps]; sc_p += round(8 * sum(18 <= w <= 65 for w in wl) / len(ps))
            sc_p += round(6 * sum(not BAD_ERA.search(p) for p in ps) / len(ps))
            sc_p += round(6 * len(set(p.lower() for p in ps)) / len(ps))
            sc_p += round(6 * sum(bool(re.search(r"derrick|river|oil|well|cottonwood|pump|prairie|ranch|gusher", p, re.I)) for p in ps) / len(ps))
            if sum(bool(NELLIE_PERSON.search(p)) for p in ps): sc_p -= 6; notes.append("Nellie as person (prompts)")
            if sum(bool(re.search(r"close[- ]?up", p, re.I)) for p in ps) > 2: sc_p -= 3; notes.append("close-ups")
        st = str(o.get("style", "")); sc_p += 4 if 12 <= len(st.split()) <= 50 else 0
    else: notes.append("JSON unusable")
    sc_p = max(0, min(60, sc_p))
    rows.append((r["label"], sc_d, sc_p, sc_d + sc_p, np_, r["total_gen_s"], r["peak_gb"], "; ".join(notes)))
print(f"{'model':<26}{'desc/40':>8}{'prompts/60':>11}{'total':>7}{'secs':>6}{'sections':>9}{'peak GB':>9}  notes")
for x in sorted(rows, key=lambda r: -r[3]): print(f"{x[0]:<26}{x[1]:>8}{x[2]:>11}{x[3]:>7}{x[5]:>6}{x[4]:>7}/14{x[6]:>9}  {x[7]}")
