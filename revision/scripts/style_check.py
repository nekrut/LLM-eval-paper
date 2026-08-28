#!/usr/bin/env python3
"""Check a markdown file against the nekrutenko-style corpus targets."""
import re, sys, statistics as st, pathlib
BANNED=r'\b(Importantly|Notably|Crucially|Interestingly|Remarkably|arguably|delve|realm|paradigm|myriad|plethora|testament|holistic|showcase|seamless|cutting-edge|state-of-the-art)\b|It is worth noting|It should be emphasized|In conclusion,|To summarize,|Firstly|Secondly'
for path in sys.argv[1:]:
    t=pathlib.Path(path).read_text()
    t=re.sub(r'<!--.*?-->','',t,flags=re.S); t=re.sub(r'```.*?```','',t,flags=re.S)
    prose='\n'.join(l for l in t.splitlines() if not l.strip().startswith(('|','#','>','-','*','!')))
    sents=[x.strip() for x in re.split(r'(?<=[.!?])\s+(?=[A-Z“"(`])',prose) if len(x.split())>3]
    w=[len(x.split()) for x in sents]
    if not w: continue
    short=sum(1 for x in w if x<=10); runs=0; c=0
    for x in w:
        c = c+1 if x<12 else 0
        runs=max(runs,c)
    we=sum(1 for s in sents if re.search(r'\bwe\b',s,re.I))
    banned=re.findall(BANNED,t)
    print(f"=== {path}")
    print(f"  sentences {len(w)}  mean {st.mean(w):.1f} (target 20-23)  median {st.median(w):.0f} (21)  "
          f">35w {100*sum(1 for x in w if x>35)/len(w):.0f}% (~10)  max {max(w)}")
    print(f"  short(<=10w) {100*short/len(w):.0f}% (8-12)  longest run <12w: {runs} (max 2)  "
          f"'we' {100*we/len(w):.0f}% (~20)")
    print(f"  banned terms: {len([b for b in banned if any(b)])}")
