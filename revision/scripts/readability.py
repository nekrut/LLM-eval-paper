#!/usr/bin/env python3
"""Measure sentence length and flag jargon in a markdown manuscript.

Run before and after the language pass so the claim "it is now plain" is a
measurement rather than an opinion.

Targets: mean sentence length near 18 words, max near 35, no banned terms.
"""
import re, sys, statistics as st, pathlib

BANNED = [
    "gate", "gating", "gated", "trap", "ceiling", "binding constraint", "unlocks",
    "collapses into", "load-bearing", "cuts against", "carries the effect", "delta",
    "non-negotiable", "surface", "leverage", "robust", "novel", "paradigm",
    "underscores", "highlights", "sheds light", "it is worth noting", "notably",
    "crucially", "importantly", "arguably", "in essence", "at the end of the day",
]

def sentences(text):
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    text = re.sub(r"```.*?```", "", text, flags=re.S)
    text = "\n".join(l for l in text.splitlines()
                     if not l.strip().startswith(("|", "#", ">", "-", "*")))
    return [s.strip() for s in re.split(r"(?<=[.!?])\s+", text) if len(s.split()) > 2]

def main(path):
    text = pathlib.Path(path).read_text()
    s = sentences(text)
    w = [len(x.split()) for x in s]
    if not w:
        print(f"{path}: no prose found"); return
    over = [x for x in s if len(x.split()) > 35]
    print(f"\n=== {path} ===")
    print(f"  sentences {len(w)}   mean {st.mean(w):.1f}   median {st.median(w)}   max {max(w)}")
    print(f"  over 35 words: {len(over)} ({100*len(over)/len(w):.0f}%)")
    low = text.lower()
    hits = [(b, low.count(b)) for b in BANNED if low.count(b)]
    if hits:
        print("  banned terms: " + ", ".join(f"{b}={n}" for b, n in sorted(hits, key=lambda x: -x[1])))
    else:
        print("  banned terms: none")
    for x in sorted(over, key=lambda y: -len(y.split()))[:3]:
        print(f"    [{len(x.split())}w] {x[:150]}...")

if __name__ == "__main__":
    for p in sys.argv[1:]:
        if pathlib.Path(p).exists():
            main(p)
