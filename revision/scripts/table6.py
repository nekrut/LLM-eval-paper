#!/usr/bin/env python3
"""
Regenerate Table 6 (qwen3.6:27b wall-clock time per generation, by platform).

Table 6 was originally hand-entered and three of its five dispersion figures
were wrong -- most visibly the 2x A5000, whose stated IQR [3-10] did not
contain its own median of 29. This script derives the table from the archived
per-run data so the numbers are reproducible and the method is explicit.

Two source conventions, both preserved from the original analysis:
  - error_matrix_*.jsonl carry `wall_s`   (generation time; the only field present)
  - quick_check_*.jsonl and runs_*/meta.json carry `wall_seconds_generation`
The Jetson and MacBook Air rows reproduce the published values exactly under
these conventions, which is what pins them down.

Quartiles use linear interpolation (numpy/pandas `.quantile()` default). The
MacBook Air row reports the full range, not an IQR: with n=3 an interquartile
range is not meaningful.

Usage: python3 revision/scripts/table6.py [--markdown]
"""
from __future__ import annotations
import argparse
import glob
import json
import os
import statistics as st
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
MODEL = "qwen3.6_27b"      # run_id prefix
MODEL_CELL = "qwen3.6:27b"  # cell prefix


def percentile(xs: list[float], p: float) -> float:
    """Linear-interpolation percentile, matching numpy/pandas default."""
    k = (len(xs) - 1) * p
    f = int(k)
    c = min(f + 1, len(xs) - 1)
    return xs[f] + (k - f) * (xs[c] - xs[f])


def from_error_matrix(fname: str) -> list[float]:
    """v2-plan generation times, excluding the uninjected `none@` control.
    12 injected patterns x 3 seeds = n=36."""
    out = []
    for line in open(REPO / fname):
        r = json.loads(line)
        cell = r.get("cell", "")
        rid = r.get("run_id", "")
        if not (rid.startswith(MODEL) or cell.startswith(MODEL_CELL)):
            continue
        if "/v2/" not in cell:
            continue
        if cell.split("/")[2].startswith("none@"):
            continue
        if r.get("wall_s"):
            out.append(r["wall_s"])
    return sorted(out)


def from_quick_check(fname: str) -> list[float]:
    return sorted(r["wall_seconds_generation"]
                  for r in (json.loads(l) for l in open(REPO / fname))
                  if r.get("wall_seconds_generation"))


def from_run_dirs(pattern: str) -> list[float]:
    out = []
    for d in glob.glob(str(REPO / pattern)):
        p = os.path.join(d, "meta.json")
        if os.path.exists(p):
            v = json.load(open(p)).get("wall_seconds_generation")
            if v:
                out.append(v)
    return sorted(out)


PLATFORMS = [
    ("2x RTX A5000",           "48 GB total VRAM (fits)",
     lambda: from_error_matrix("error_matrix_ollama_a5000.jsonl"), "iqr"),
    ("MacBook Pro M4 Pro",     "48 GB unified (fits)",
     lambda: from_error_matrix("error_matrix_ollama_m4_r2.jsonl"), "iqr"),
    ("NVIDIA Jetson AGX Orin", "64 GB unified (fits)",
     lambda: from_error_matrix("error_matrix_ollama.jsonl"), "iqr"),
    ("RTX 5080 desktop",       "16 GB VRAM (spills to RAM)",
     lambda: from_run_dirs("runs_5080_v2/qwen3.6_27b*"), "iqr"),
    ("MacBook Air M4",         "24 GB unified (tight; swap-sensitive)",
     lambda: from_quick_check("quick_check_m4_air_qwen3.6_27b.jsonl"), "full"),
]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--markdown", action="store_true")
    args = ap.parse_args()

    rows = []
    for name, mem, loader, disp in PLATFORMS:
        xs = loader()
        if not xs:
            print(f"WARNING: no data for {name}")
            continue
        med = st.median(xs)
        if disp == "iqr":
            lo, hi = percentile(xs, 0.25), percentile(xs, 0.75)
            bracket = f"[{lo:,.0f}–{hi:,.0f}] (IQR)"
            assert lo <= med <= hi, f"{name}: median {med} outside IQR [{lo}, {hi}]"
        else:
            bracket = f"[{min(xs):,.0f}–{max(xs):,.0f}] (full)"
        rows.append((name, mem, med, bracket, len(xs)))

    if args.markdown:
        print("| Platform | VRAM/UMA | Median wall time (s) | Range (s) | n |")
        print("|---|---|---:|---:|---:|")
        for name, mem, med, bracket, n in rows:
            print(f"| {name.replace('2x', '2×')} | {mem} | {med:,.0f} | {bracket} | {n} |")
    else:
        print(f"{'platform':<24}{'n':>4}{'median':>9}   dispersion")
        for name, mem, med, bracket, n in rows:
            print(f"{name:<24}{n:>4}{med:>9,.0f}   {bracket}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
