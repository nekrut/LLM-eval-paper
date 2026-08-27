#!/usr/bin/env python3
"""Perturbed-plan condition: does the executor bind the plan, or copy it?

Plan v2 is given verbatim. Its command lines name `data/ref/chrM.fa`. The
sandbox instead holds the same reference at `data/ref/GRCh38_chrM/rCRS.fa`,
and the prompt's DATASET section states that path. Nothing else changes.

  - a script that copies v2's literal command lines cannot find the reference
  - a script that binds v2's recipe to the stated inputs runs normally

The control arm is the published v2 cell, already collected. Reviewer 2's
objection is that plan detail is operationally "how much of the answer is
written down" while the outcome is "was the answer produced", which makes the
central result close to a tautology. This condition separates the two: the
answer is still written down, but it is written down wrong for this dataset.

Usage:
  python3 revision/scripts/perturbed_plan.py --dry-run
  python3 revision/scripts/perturbed_plan.py --seeds 42,43,44
"""
from __future__ import annotations
import argparse, json, subprocess, sys, time
from pathlib import Path

BENCH = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(BENCH / "revision" / "scripts"))
from matrix_jetson import LOCAL_MODELS

PLAN = BENCH / "plan" / "PLAN.md"          # v2, verbatim
LOG = BENCH / "revision" / "logs" / "matrix_jetson_perturbed.jsonl"
RUNS = BENCH / "revision" / "runs_perturbed"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", default="42,43,44")
    ap.add_argument("--models", default="")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    models = [m.strip() for m in a.models.split(",") if m.strip()] or list(LOCAL_MODELS)
    seeds = [int(s) for s in a.seeds.split(",")]
    cells = [(m, s) for m in models for s in seeds]

    print(f"perturbed-plan condition: {len(models)} models x {len(seeds)} seeds "
          f"= {len(cells)} cells", file=sys.stderr)
    if a.dry_run:
        for m, s in cells:
            print(f"  {m} seed-{s} [v2 plan, data_shifted]")
        return 0

    RUNS.mkdir(parents=True, exist_ok=True)
    LOG.parent.mkdir(parents=True, exist_ok=True)
    done = set()
    if LOG.exists():
        for line in LOG.read_text().splitlines():
            try:
                done.add(json.loads(line)["cell"])
            except Exception:
                pass

    for i, (model, seed) in enumerate(cells, 1):
        cell = f"{model.replace(':', '_')}_perturbed_track-A_seed-{seed}"
        if cell in done:
            print(f"[{i}/{len(cells)}] skip {cell}", file=sys.stderr)
            continue
        run_id = f"{cell}_{int(time.time())}"
        cmd = [
            sys.executable, str(BENCH / "harness" / "run_one.py"),
            "--model", model, "--track", "A", "--seed", str(seed),
            "--think", "off", "--plan", str(PLAN),
            "--data-dir", "data_shifted",
            "--track-template", "track_a_shifted_user",
            "--runs-dir", str(RUNS), "--run-id", run_id,
        ]
        t0 = time.time()
        print(f"[{i}/{len(cells)}] {cell}", file=sys.stderr)
        p = subprocess.run(cmd, capture_output=True, text=True)
        rec = {"cell": cell, "plan": "v2_perturbed", "model": model, "seed": seed,
               "run_id": run_id, "gen_secs": round(time.time() - t0, 1),
               "returncode": p.returncode}
        sp = RUNS / run_id / "score.json"
        if sp.exists():
            try:
                rec["score"] = json.loads(sp.read_text())
            except Exception as e:
                rec["score_error"] = str(e)
        else:
            rec["error"] = (p.stderr or "")[-400:]
        with LOG.open("a") as fh:
            fh.write(json.dumps(rec) + "\n")
    print("done", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
