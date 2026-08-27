#!/usr/bin/env python3
"""
Plan-gradient tables from the revision matrix logs, with binomial CIs.

Column assignment mirrors `scripts/make_figures.py::col()` exactly, and getting
it right is not optional: v1 and v2 are run on BOTH tracks, and every Track-B
run is a *no-plan* run regardless of which plan file was nominally passed
(the Track-B prompt template does not substitute {PLAN}). Aggregating naively
by plan therefore folds no-plan runs into the v1 and v2 columns and halves
them -- which looks exactly like "the most detailed plan performs worst".

    plan == v0.5  -> column "v0.5"   (its own designed Track-B variant)
    track == B    -> column "B"      (the no-plan column)
    otherwise     -> column = plan

Binomial confidence intervals are reported because R3.8 objected to reading
3/3 as robust success. The default is Clopper-Pearson (exact), which is the
method the reviewer used: 3/3 -> [29%, 100%]. Wilson is available via
--ci-method wilson and gives [44%, 100%] on the same data.

Usage:
  python3 revision/scripts/gradient.py                 # think-off
  python3 revision/scripts/gradient.py --arm on        # think-on
  python3 revision/scripts/gradient.py --metric M1     # execution success
  python3 revision/scripts/gradient.py --ci            # add 95% CIs (exact)
"""
from __future__ import annotations
import argparse
import collections
import json
import math
import statistics as st
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
LOGS = REPO / "revision" / "logs"

PLAN_LABEL = {"b": "B", "v0p5": "v0.5", "v1": "v1", "v1g": "v1g",
              "v1p25": "v1.25", "v1p5": "v1.5", "v2": "v2"}
COLS = ["B", "v0.5", "v1", "v1g", "v1.25", "v1.5", "v2"]


def column(plan: str, track: str) -> str:
    if plan == "v0p5":
        return "v0.5"
    if track == "B":
        return "B"
    return PLAN_LABEL[plan]


def clopper_pearson(k: int, n: int, alpha: float = 0.05) -> tuple[float, float]:
    """Exact (Clopper-Pearson) binomial interval.

    This is the method R3.8 used: for 3/3 it gives [29%, 100%], matching the
    "uncertainty ... remains very large" figure quoted in the review. Wilson
    gives [44%, 100%] for the same data. Reporting the exact interval keeps the
    response letter arithmetically consistent with the reviewer's own number.
    Implemented via the Beta quantile relation to avoid a scipy dependency.
    """
    if n == 0:
        return (0.0, 1.0)
    lo = 0.0 if k == 0 else _beta_ppf(alpha / 2, k, n - k + 1)
    hi = 1.0 if k == n else _beta_ppf(1 - alpha / 2, k + 1, n - k)
    return (lo, hi)


def _beta_ppf(p: float, a: float, b: float, iters: int = 200) -> float:
    """Beta quantile by bisection on the regularised incomplete beta function."""
    lo, hi = 0.0, 1.0
    for _ in range(iters):
        mid = (lo + hi) / 2
        if _betainc(a, b, mid) < p:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


def _betainc(a: float, b: float, x: float) -> float:
    """Regularised incomplete beta via its continued fraction."""
    if x <= 0:
        return 0.0
    if x >= 1:
        return 1.0
    lbeta = math.lgamma(a) + math.lgamma(b) - math.lgamma(a + b)
    front = math.exp(math.log(x) * a + math.log(1 - x) * b - lbeta) / a
    f, c, d = 1.0, 1.0, 0.0
    for i in range(200):
        m = i // 2
        if i == 0:
            num = 1.0
        elif i % 2 == 0:
            num = (m * (b - m) * x) / ((a + 2 * m - 1) * (a + 2 * m))
        else:
            num = -((a + m) * (a + b + m) * x) / ((a + 2 * m) * (a + 2 * m + 1))
        d = 1.0 + num * d
        d = 1e-30 if abs(d) < 1e-30 else d
        d = 1.0 / d
        c = 1.0 + num / c
        c = 1e-30 if abs(c) < 1e-30 else c
        f *= c * d
        if abs(1.0 - c * d) < 1e-12:
            break
    return front * (f - 1.0)


def wilson(k: int, n: int, z: float = 1.96) -> tuple[float, float]:
    """Wilson score interval for a binomial proportion. Handles k=0 and k=n,
    where the normal approximation degenerates."""
    if n == 0:
        return (0.0, 1.0)
    p = k / n
    d = 1 + z * z / n
    centre = (p + z * z / (2 * n)) / d
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (max(0.0, centre - half), min(1.0, centre + half))


def load(arm: str) -> list[dict]:
    """arm is 'off', 'on', or 'frontier'.

    'frontier' reads the Anthropic reference gradient. It goes through the same
    column() mapping as the local arms, which is the whole point: reporting the
    frontier row without collapsing Track B is the error that put "0.63 to 1.00
    at Track B" and "saturates at v1g" into the first version of the manuscript.
    Collapsed, Track B is 0.74-0.87 and saturation is at v1.
    """
    name = "matrix_jetson.jsonl" if arm == "frontier" else f"matrix_jetson_think{arm}.jsonl"
    p = LOGS / name
    if not p.exists():
        raise SystemExit(f"no log at {p}")
    return [json.loads(l) for l in open(p)]


def cellkey(r: dict) -> tuple[str, str]:
    """(model, column) for a log record, honouring the Track-B collapse rule."""
    cell = r["cell"]
    track = "B" if "_track-B" in cell else "A"
    # Local cells are <model>_think-<on|off>_track-<X>_seed-<n>; frontier API
    # cells are <model>_track-<X>_seed-<n> with no think segment.
    model = cell.split("_think")[0].split("_track-")[0]
    return model, column(r["plan"], track)


def delta_mode(truncation: str) -> int:
    """Per-plan reasoning delta (on minus off) over the models present in BOTH
    arms, under an explicit truncation convention (Q9/Q10).

      --truncation zero : cells with no M3 score 0 and are retained.  This is
                          the convention the manuscript states.
      --truncation drop : cells with no M3 are excluded.  This is what the rest
                          of this script does, and it moves the v1 delta by
                          0.06, which is why the convention has to be named.
    """
    def grid(arm):
        g = collections.defaultdict(list)
        for r in load(arm):
            s = r.get("score") or {}
            if "M3" in s:
                g[cellkey(r)].append(s["M3"])
            elif truncation == "zero":
                g[cellkey(r)].append(0.0)
        return g

    off, on = grid("off"), grid("on")
    models = sorted({k[0] for k in off} & {k[0] for k in on})
    print(f"reasoning delta (on minus off), truncation={truncation}, "
          f"{len(models)} models in both arms")
    print(f"{'column':>8} {'off':>8} {'on':>8} {'delta':>8}   n_off  n_on")
    for c in COLS:
        vo = [x for m in models for x in off[(m, c)]]
        vn = [x for m in models for x in on[(m, c)]]
        if not vo or not vn:
            continue
        mo, mn = st.mean(vo), st.mean(vn)
        print(f"{c:>8} {mo:8.3f} {mn:8.3f} {mn - mo:+8.3f}   {len(vo):5d} {len(vn):5d}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--arm", choices=["off", "on", "frontier"], default="off")
    ap.add_argument("--delta", action="store_true",
                    help="print the per-plan reasoning delta (on minus off) instead")
    ap.add_argument("--truncation", choices=["zero", "drop"], default="zero",
                    help="how --delta treats cells with no M3 (see delta_mode docstring)")
    ap.add_argument("--metric", default="M3", choices=["M1", "M3"])
    ap.add_argument("--ci", action="store_true", help="append 95%% CI")
    ap.add_argument("--ci-method", choices=["exact","wilson"], default="exact",
                    help="exact = Clopper-Pearson (matches R3.8); wilson = score interval")
    args = ap.parse_args()

    if args.delta:
        return delta_mode(args.truncation)

    agg = collections.defaultdict(list)
    skipped = 0
    for r in load(args.arm):
        s = r.get("score") or {}
        if args.metric not in s:
            skipped += 1
            continue
        agg[cellkey(r)].append(s[args.metric])

    models = sorted({k[0] for k in agg})
    width = 17 if args.ci else 8
    print(f"{args.metric} — think-{args.arm}"
          + (f"  (mean [95% CI, {args.ci_method}])" if args.ci else "  (mean)"))
    if skipped:
        print(f"  ({skipped} cells had no {args.metric} — excluded)")
    print(f"{'model':<32}" + "".join(f"{c:>{width}}" for c in COLS))
    for m in models:
        out = []
        for c in COLS:
            v = agg.get((m, c))
            if not v:
                out.append("-".rjust(width))
                continue
            mean = st.mean(v)
            if args.ci:
                k = sum(1 for x in v if x >= 0.999)
                lo, hi = (clopper_pearson(k, len(v)) if args.ci_method == "exact"
                          else wilson(k, len(v)))
                out.append(f"{mean:.2f} [{lo:.2f}-{hi:.2f}]".rjust(width))
            else:
                out.append(f"{mean:.2f}".rjust(width))
        print(f"{m:<32}" + "".join(out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
