#!/usr/bin/env python3
"""Transcription index over the archived emitted scripts (R3.6, R2.11).

The index is the token-level recall, in an emitted `run.sh`, of the literal
command tokens of a reference plan (v2 by default), after normalising the
sample placeholder and the thread count.

Two corrections to the first version of this script, both of which changed
numbers that reached the manuscript:

  1. Bucketing. `v0.5` runs use the Track-B prompt template, so the old rule
     `col = 'B' if track == 'B' else ...` silently folded every v0.5 script
     into the Track-B row -- the same aggregation error the Methods warn about.
     `plan == 'v0p5'` is now tested first, and v0.5 is its own row.
  2. Corpus size. This script skips reasoning-on cells, so it reads 514
     scripts, not the 766 that `script_audit.py` audits. The count is printed.

`--only-successful` conditions on M3 == 1.00 (read from each cell's
`score.json`). This matters because the unconditioned Track-B floor is
computed over scripts that mostly crashed, and a script that died early
mechanically has low token recall, so the unconditioned floor measures failure
rather than unaided derivation.

Usage:
  python3 revision/scripts/transcription_index.py [--only-successful]
                                                  [--exclude-qwen38]
"""
import argparse, collections, json, pathlib, random, re, statistics

ROOT = pathlib.Path('revision/runs')
PLANF = {'v1': 'plan/PLAN_v1.md', 'v1g': 'plan/PLAN_v1g.md',
         'v1p25': 'plan/PLAN_v1p25.md', 'v1p5': 'plan/PLAN_v1p5.md',
         'v2': 'plan/PLAN.md'}
COLS = ['B', 'v0.5', 'v1', 'v1g', 'v1p25', 'v1p5', 'v2']
TOOLS = ('bwa', 'samtools', 'lofreq', 'bcftools', 'bgzip', 'tabix', 'awk',
         'sort', 'mkdir', 'set', 'cat', 'printf', 'echo')


def norm(tok):
    t = tok.strip('`"\'|;')
    t = re.sub(r'\$?\{?sample\}?', 'SAMPLE', t, flags=re.I)
    t = re.sub(r'\$\{?THREADS\}?', 'THREADS', t)
    return re.sub(r'\b4\b', 'THREADS', t)


def plan_cmd_tokens(path):
    toks, infence = [], False
    for line in pathlib.Path(path).read_text().splitlines():
        if line.strip().startswith('```'):
            infence = not infence
            continue
        cand = [line.strip()] if (infence and line.strip()) else re.findall(r'`([^`]+)`', line)
        for c in cand:
            if not any(c.lstrip().startswith(t) for t in TOOLS) and not c.lstrip().startswith('-'):
                continue
            for t in c.split():
                n = norm(t)
                if n and not n.startswith('#'):
                    toks.append(n)
    return toks


def script_tokens(path):
    out = []
    for line in pathlib.Path(path).read_text(errors='replace').splitlines():
        for t in line.split('#')[0].split():
            n = norm(t)
            if n:
                out.append(n)
    return collections.Counter(out)


def recall(sc, ref):
    tot = sum(ref.values())
    return sum(min(c, sc.get(t, 0)) for t, c in ref.items()) / tot if tot else float('nan')


def boot(v, n=2000):
    random.seed(0)
    ms = sorted(statistics.mean(random.choices(v, k=len(v))) for _ in range(n))
    return ms[int(.025 * n)], ms[int(.975 * n)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--only-successful', action='store_true',
                    help='restrict to cells with M3 == 1.00')
    ap.add_argument('--exclude-qwen38', action='store_true',
                    help='drop qwen3.8:27b, which Table 9 excludes')
    a = ap.parse_args()

    plans = {k: collections.Counter(plan_cmd_tokens(v)) for k, v in PLANF.items()}
    for k, v in plans.items():
        print(f"plan {k}: {sum(v.values())} literal command tokens, {len(v)} distinct")
    ref = plans['v2']

    rows = []
    for p in sorted(ROOT.glob('jetson_*/*/run.sh')):
        plan = p.parent.parent.name.replace('jetson_', '')
        m = re.match(r'(.+?)_(think-(?:on|off)_)?track-([AB])_seed-(\d+)_[0-9a-f]+$', p.parent.name)
        if not m:
            continue
        mdl, think, track = m.group(1), (m.group(2) or 'api').strip('_'), m.group(3)
        if think == 'think-on':
            continue
        if a.exclude_qwen38 and mdl.startswith('qwen3.8'):
            continue
        sj = p.parent / 'score.json'
        m3 = json.loads(sj.read_text()).get('m3_jaccard') if sj.exists() else None
        if a.only_successful and m3 != 1.0:
            continue
        rows.append(dict(arm='frontier' if mdl.startswith('claude') else 'local',
                         col=('v0.5' if plan == 'v0p5' else ('B' if track == 'B' else plan)),
                         plan=plan, mdl=mdl, path=p, m3=m3))

    print(f"\nreasoning-off scripts entering the index: {len(rows)}"
          f" (of 766 archived under {ROOT}/; reasoning-on cells excluded)"
          f"{'  [only-successful]' if a.only_successful else ''}")
    print(f"  qwen3.8:27b scripts included: {sum(1 for r in rows if r['mdl'].startswith('qwen3.8'))}")

    print("\n=== recall of plan v2's literal command tokens ===")
    agg = collections.defaultdict(list)
    for r in rows:
        agg[(r['arm'], r['col'])].append(recall(script_tokens(r['path']), ref))
    for arm in ('local', 'frontier'):
        for col in COLS:
            v = agg[(arm, col)]
            if not v:
                continue
            if len(v) > 3:
                q = statistics.quantiles(v, n=4)
                iqr, ci = f"[{q[0]:.3f}-{q[2]:.3f}]", "[%.3f,%.3f]" % boot(v)
            else:
                iqr, ci = f"[{min(v):.3f}-{max(v):.3f}]", "n/a"
            print(f"  {arm:9s} {col:6s} n={len(v):4d} mean={statistics.mean(v):.3f} IQR={iqr} 95%CI={ci}")

    print("\n=== per-model recall of v2 tokens at v2, local arm ===")
    pm = collections.defaultdict(list)
    for r in rows:
        if r['arm'] == 'local' and r['col'] == 'v2':
            pm[r['mdl']].append(recall(script_tokens(r['path']), ref))
    for k in sorted(pm, key=lambda k: statistics.mean(pm[k])):
        print(f"  {k:34s} n={len(pm[k]):3d} mean={statistics.mean(pm[k]):.3f}")

    print("\n=== recall of each condition's own plan tokens ===")
    agg2 = collections.defaultdict(list)
    for r in rows:
        if r['col'] in ('B', 'v0.5') or r['plan'] not in plans:
            continue
        agg2[(r['arm'], r['plan'])].append(recall(script_tokens(r['path']), plans[r['plan']]))
    for arm in ('local', 'frontier'):
        for plan in ('v1', 'v1g', 'v1p25', 'v1p5', 'v2'):
            v = agg2[(arm, plan)]
            if v:
                print(f"  {arm:9s} {plan:6s} n={len(v):4d} mean={statistics.mean(v):.3f}")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
