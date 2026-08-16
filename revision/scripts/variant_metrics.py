#!/usr/bin/env python3
"""
Conventional variant-calling metrics for the revision (R3.4, R2.11).

R3.4 asked for "precision, recall, false-positives/negatives, allele frequency
error in addition to Jaccard overlap". R2.11 separately objected that Jaccard
is a poor fit when there are only a handful of truth variants.

Both criticisms share a root cause worth stating plainly in the paper: the
tolerant Jaccard used for M3 **conflates detection with quantification**. A
variant called at exactly the right position but with an allele frequency off
by 0.03 is scored identically to a variant that was never called at all. Those
are different failure modes -- one is a missed variant, the other is a slightly
mis-estimated heteroplasmy -- and collapsing them loses the distinction a
reader most wants.

This script separates them:

  Detection    TP / FP / FN, precision, recall, F1 on (CHROM, POS, REF, ALT),
               ignoring AF entirely.
  Quantification  AF error over the true positives only: mean absolute error,
               RMSE, and max, plus the count exceeding the +/-0.02 tolerance.

Reported per run and aggregated per (model, plan column). Uses the same VCF
parsing and PASS-filter convention as score/score_run.py so the numbers are
directly comparable to the published M3.

Usage:
  python3 revision/scripts/variant_metrics.py --arm off
  python3 revision/scripts/variant_metrics.py --arm off --per-model
"""
from __future__ import annotations
import argparse
import collections
import json
import math
import statistics as st
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
GT = REPO / "ground_truth" / "results"
SAMPLES = ["M117-bl", "M117-ch", "M117C1-bl", "M117C1-ch"]
AF_TOL = 0.02
BCFTOOLS = Path.home() / "miniforge3" / "envs" / "bench" / "bin" / "bcftools"

PLAN_LABEL = {"jetson_b": "B", "jetson_v0p5": "v0.5", "jetson_v1": "v1",
              "jetson_v1g": "v1g", "jetson_v1p25": "v1.25",
              "jetson_v1p5": "v1.5", "jetson_v2": "v2"}
COLS = ["B", "v0.5", "v1", "v1g", "v1.25", "v1.5", "v2"]


def parse_variants(vcf: Path) -> list[tuple] | None:
    """(chrom,pos,ref,alt,af) for PASS/'.' records. None if unreadable."""
    try:
        p = subprocess.run(
            [str(BCFTOOLS), "query", "-f", "%FILTER\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n", str(vcf)],
            capture_output=True, text=True, timeout=120)
    except Exception:
        return None
    if p.returncode != 0:
        return None
    out = []
    for line in p.stdout.strip().split("\n"):
        if not line:
            continue
        parts = line.split("\t")
        if len(parts) < 6:
            continue
        flt, chrom, pos, ref, alt, af = parts[:6]
        if flt not in ("PASS", "."):
            continue
        try:
            af_f = float(af) if af not in (".", "") else 0.0
        except ValueError:
            af_f = 0.0
        out.append((chrom, int(pos), ref, alt, af_f))
    return out


def score_run(run_dir: Path) -> dict | None:
    """Detection counts pooled over the four samples, plus AF errors on TPs."""
    tp = fp = fn = 0
    af_err: list[float] = []
    any_sample = False
    for s in SAMPLES:
        model = run_dir / "results" / f"{s}.vcf.gz"
        canon = GT / f"{s}.vcf.gz"
        c = parse_variants(canon)
        if c is None:
            continue
        cm = {(x[0], x[1], x[2], x[3]): x[4] for x in c}
        if not model.exists():
            fn += len(cm)          # whole sample missed
            continue
        m = parse_variants(model)
        if m is None:
            fn += len(cm)
            continue
        any_sample = True
        mm = {(x[0], x[1], x[2], x[3]): x[4] for x in m}
        for k in set(cm) | set(mm):
            if k in cm and k in mm:
                tp += 1
                af_err.append(abs(cm[k] - mm[k]))
            elif k in mm:
                fp += 1
            else:
                fn += 1
    if not any_sample and tp == 0 and fp == 0:
        # nothing produced at all: still a real FN result, keep it
        pass
    prec = tp / (tp + fp) if (tp + fp) else 0.0
    rec = tp / (tp + fn) if (tp + fn) else 0.0
    f1 = 2 * prec * rec / (prec + rec) if (prec + rec) else 0.0
    return {
        "tp": tp, "fp": fp, "fn": fn,
        "precision": prec, "recall": rec, "f1": f1,
        "af_mae": st.mean(af_err) if af_err else None,
        "af_rmse": math.sqrt(sum(e * e for e in af_err) / len(af_err)) if af_err else None,
        "af_max": max(af_err) if af_err else None,
        "af_over_tol": sum(1 for e in af_err if e > AF_TOL),
        "n_af": len(af_err),
    }


def column(plan_dir: str, run_name: str) -> str:
    if plan_dir == "jetson_v0p5":
        return "v0.5"
    if "_track-B" in run_name:
        return "B"
    return PLAN_LABEL[plan_dir]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--arm", choices=["off", "on"], default="off")
    ap.add_argument("--per-model", action="store_true")
    ap.add_argument("--limit", type=int, default=0, help="cap runs (for a quick look)")
    args = ap.parse_args()

    if not BCFTOOLS.exists():
        raise SystemExit(f"bcftools not found at {BCFTOOLS}")

    tag = f"_think-{args.arm}_"
    rows = []
    for plan_dir in PLAN_LABEL:
        d = REPO / "revision" / "runs" / plan_dir
        if not d.is_dir():
            continue
        for run in sorted(d.iterdir()):
            if not run.is_dir() or tag not in run.name:
                continue
            m = score_run(run)
            if m is None:
                continue
            m["model"] = run.name.split("_think")[0]
            m["col"] = column(plan_dir, run.name)
            rows.append(m)
            if args.limit and len(rows) >= args.limit:
                break
        if args.limit and len(rows) >= args.limit:
            break

    if not rows:
        raise SystemExit("no runs matched")

    out = REPO / "revision" / f"variant_metrics_think{args.arm}.json"
    out.write_text(json.dumps(rows, indent=2))

    tp = sum(r["tp"] for r in rows); fp = sum(r["fp"] for r in rows); fn = sum(r["fn"] for r in rows)
    p = tp / (tp + fp) if (tp + fp) else 0
    rc = tp / (tp + fn) if (tp + fn) else 0
    errs = [r["af_mae"] for r in rows if r["af_mae"] is not None]
    print(f"think-{args.arm}: {len(rows)} runs   ->  {out.name}")
    print(f"  pooled TP={tp}  FP={fp}  FN={fn}")
    print(f"  precision={p:.3f}  recall={rc:.3f}  F1={2*p*rc/(p+rc) if (p+rc) else 0:.3f}")
    if errs:
        print(f"  AF error (mean of per-run MAE) = {st.mean(errs):.4f}   "
              f"runs with any AF beyond ±{AF_TOL}: "
              f"{sum(1 for r in rows if r['af_over_tol'])}/{len(rows)}")

    if args.per_model:
        print()
        agg = collections.defaultdict(lambda: [0, 0, 0])
        for r in rows:
            a = agg[(r["model"], r["col"])]
            a[0] += r["tp"]; a[1] += r["fp"]; a[2] += r["fn"]
        models = sorted({k[0] for k in agg})
        print("F1 by model x plan column (pooled over seeds/samples)")
        print(f"{'model':<32}" + "".join(f"{c:>8}" for c in COLS))
        for mdl in models:
            cells = []
            for c in COLS:
                a = agg.get((mdl, c))
                if not a:
                    cells.append("-".rjust(8)); continue
                t, f_, n = a
                pr = t / (t + f_) if (t + f_) else 0
                rr = t / (t + n) if (t + n) else 0
                f1 = 2 * pr * rr / (pr + rr) if (pr + rr) else 0
                cells.append(f"{f1:.2f}".rjust(8))
            print(f"{mdl:<32}" + "".join(cells))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
