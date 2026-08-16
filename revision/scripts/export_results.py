#!/usr/bin/env python3
"""
Export revision run artifacts to the `results.csv` schema.

The published analysis pipeline (`scripts/make_figures.py`) consumes a flat CSV:

    run_id,plan_version,model,think,track,seed,M1,M2,M3,M5,cost_usd,gen_seconds,exec_seconds

Writing the revision matrix into the same shape means the existing figure code,
and any downstream analysis a reader already has, works unchanged rather than
needing a parallel implementation.

`plan_version` is emitted as `rev_<arm>_<plan>` (e.g. `rev_off_v2`,
`rev_on_v1g`) so revision rows can never be silently pooled with published
rows: `make_figures.py::PLAN_MAP` has no entry for these keys, so anything
consuming them must opt in deliberately. Add entries there to plot them, e.g.

    "rev_off_v2": ("v2", "jetson-rev"),

Track is recovered from the run directory name, and the B-column convention
from `make_figures.py::col()` still applies downstream (every Track-B run is a
no-plan run regardless of which plan file was passed) — see
`revision/scripts/gradient.py` for that mapping.

Usage:
  python3 revision/scripts/export_results.py                 # both arms
  python3 revision/scripts/export_results.py --arm off
"""
from __future__ import annotations
import argparse
import csv
import json
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
RUNS = REPO / "revision" / "runs"
PLAN_DIRS = {"jetson_b": "b", "jetson_v0p5": "v0p5", "jetson_v1": "v1",
             "jetson_v1g": "v1g", "jetson_v1p25": "v1p25",
             "jetson_v1p5": "v1p5", "jetson_v2": "v2"}
FIELDS = ["run_id", "plan_version", "model", "think", "track", "seed",
          "M1", "M2", "M3", "M5", "cost_usd", "gen_seconds", "exec_seconds",
          "generation_status"]


def parse_run(d: Path, plan: str) -> dict | None:
    meta_p, score_p = d / "meta.json", d / "score.json"
    if not meta_p.exists():
        return None
    meta = json.loads(meta_p.read_text())
    score = json.loads(score_p.read_text()) if score_p.exists() else {}

    name = d.name
    track = "B" if "_track-B" in name else "A"
    # Anthropic runs have no think setting. Labelling them "off" would pool them
    # with local think-off runs under the same plan_version -- the exact silent
    # pooling this scheme exists to prevent. Give them their own arm.
    provider = meta.get("provider")
    think = meta.get("think") or ""
    if provider == "anthropic":
        arm = "api"
    else:
        arm = think if think in ("on", "off") else "off"

    exec_s = None
    exec_p = d / "exec.json"
    if exec_p.exists():
        try:
            exec_s = json.loads(exec_p.read_text()).get("wall_seconds")
        except Exception:
            pass

    cost = 0.0
    if isinstance(score.get("m4"), dict):
        cost = score["m4"].get("cost_usd") or 0.0
    if not cost and (d / "usage.json").exists():
        try:
            cost = json.loads((d / "usage.json").read_text()).get("cost_usd") or 0.0
        except Exception:
            pass

    # score.json stores the internal names; the short M1/M2/M3/M5 labels only
    # exist on score_run.py's stdout. Read the file's own keys, and fall back to
    # the short names in case a future version writes those instead.
    def sc(long_key: str, short_key: str):
        v = score.get(long_key)
        return score.get(short_key) if v is None else v

    m3 = sc("m3_jaccard", "M3")
    return {
        "run_id": name,
        "plan_version": f"rev_{arm}_{plan}",
        "model": meta.get("model", "").replace(":", "_"),
        "think": think,
        "track": track,
        "seed": meta.get("seed"),
        "M1": sc("m1_executes", "M1"),
        "M2": sc("m2_schema", "M2"),
        "M3": round(m3, 3) if isinstance(m3, (int, float)) else m3,
        "M5": sc("m5_quality", "M5"),
        "cost_usd": cost,
        "gen_seconds": meta.get("wall_seconds_generation"),
        "exec_seconds": exec_s,
        # Not in the published schema; carried so a plumbing failure
        # (truncated_in_thinking / provider_error) is never mistaken downstream
        # for a capability result of 0.
        "generation_status": meta.get("generation_status"),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--arm", choices=["off", "on", "both"], default="both")
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    rows = []
    for plan_dir, plan in PLAN_DIRS.items():
        d = RUNS / plan_dir
        if not d.is_dir():
            continue
        for run in sorted(d.iterdir()):
            if not run.is_dir():
                continue
            if args.arm != "both":
                if f"_think-{args.arm}_" not in run.name and "claude" not in run.name:
                    continue
            r = parse_run(run, plan)
            if r:
                rows.append(r)

    out = Path(args.out) if args.out else REPO / "revision" / "results_revision.csv"
    with open(out, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        w.writeheader()
        w.writerows(rows)

    scored = sum(1 for r in rows if r["M3"] is not None)
    import collections
    print(f"wrote {out}  ({len(rows)} rows, {scored} scored)")
    print("  by plan_version:",
          dict(collections.Counter(r["plan_version"] for r in rows)))
    bad = collections.Counter(r["generation_status"] for r in rows
                              if r["generation_status"] not in ("ok", None))
    if bad:
        print("  non-ok generation_status:", dict(bad))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
