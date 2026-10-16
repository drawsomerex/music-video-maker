#!/usr/bin/env python3
"""Compare a words.json with ground-truth word starts. usage: score_truth.py truth.json words.json"""
import sys, json, re, difflib, statistics as st
norm = lambda s: re.sub(r"[^a-z0-9']", "", s.lower())
truth = json.load(open(sys.argv[1])); got = json.load(open(sys.argv[2]))
sm = difflib.SequenceMatcher(None, [norm(w["text"]) for w in truth], [norm(w["text"]) for w in got], autojunk=False)
pairs = [(a + k, b + k) for a, b, n in sm.get_matching_blocks() for k in range(n)]
d = sorted(abs(truth[i]["start"] - got[j]["start"]) for i, j in pairs)
if not d: print("no matches"); sys.exit()
f = lambda x: f"{x*1000:.0f}"
print(f"matched {len(pairs)}/{len(truth)} ({100*len(pairs)//len(truth)}%) | start error ms: median {f(d[len(d)//2])}, p90 {f(d[int(len(d)*.9)])}, p99 {f(d[int(len(d)*.99)])} | within 100 ms: {100*sum(x<=.1 for x in d)//len(d)}%, within 250 ms: {100*sum(x<=.25 for x in d)//len(d)}%")
