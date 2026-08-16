#!/usr/bin/env python3
"""
Full Figure-1 plan-gradient matrix on the Jetson AGX Orin 64GB.

The published Jetson data is a single-column screen: 14 models at plan v2 only.
The 7-column gradient exists only on the RTX 5080. This driver produces the
first complete gradient on a second hardware platform, which is what makes the
plan-detail cliff attributable to the models rather than to one machine.

Design (mirrors harness/matrix_5080.py's stage/track logic exactly):
  - 7 plan columns: B, v0.5, v1, v1g, v1.25, v1.5, v2
  - both think arms for every local model (think-on costs ~5x generation time)
  - n=3 seeds across the matrix; re-run headline cells at n=10 separately
  - results land under revision/runs/<plan>/ so published runs stay untouched

Usage:
  python3 revision/scripts/matrix_jetson.py --dry-run       # print the plan
  python3 revision/scripts/matrix_jetson.py                 # everything
  python3 revision/scripts/matrix_jetson.py --plans v1,v2   # subset of columns
  python3 revision/scripts/matrix_jetson.py --models qwen3.6:35b-a3b-q4_K_M
  python3 revision/scripts/matrix_jetson.py --think off     # think-off arm only
  python3 revision/scripts/matrix_jetson.py --anthropic-only
  python3 revision/scripts/matrix_jetson.py --seeds 42,43,44,45,46  # n=10 pass
"""
from __future__ import annotations
import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
RUN_ONE = REPO / "harness" / "run_one.py"
SCORE = REPO / "score" / "score_run.py"
REVISION = REPO / "revision"

SEEDS = [42, 43, 44]

# Local models, q4_K_M throughout so quantization is one fixed variable.
# (gpt-oss ships MXFP4 only; nemotron-3-nano:4b has no q4 tag.)
#
# Model cutoff: 2026-08-14. qwen3.8:27b was released on that date, during the
# revision, and was added because it pairs exactly with qwen3.6:27b -- same
# parameter count, same quantization, same engine, one generation apart. It is
# not a policy of tracking releases; the cutoff is stated so the boundary is a
# documented choice rather than an accident of when the runs happened.
# It is pulled from ggml-org's GGUF and retagged to the local naming scheme:
#   ollama pull hf.co/ggml-org/Qwen3.8-27B-GGUF:Q4_K_M
#   ollama cp   hf.co/ggml-org/Qwen3.8-27B-GGUF:Q4_K_M qwen3.8:27b-q4_K_M
# (the hf.co/ name contains slashes, which would break run-directory names).
LOCAL_MODELS = [
    # --- MoE: small active param count, the fast tier on this box ---
    "laguna-xs-2.1:q4_K_M",              # 33B/3B, agentic-coding purpose-built
    "qwen3.6:35b-a3b-q4_K_M",            # 35B/3B, SWE-bench Verified 73.4%
    "gemma4:26b-a4b-it-q4_K_M",          # 26B/4B, Apache 2.0
    "nemotron-3-nano:30b-a3b-q4_K_M",    # 30B/3B, NVIDIA's own
    "gpt-oss:20b",                       # MoE, only model with a published AGX number
    "glm-4.7-flash:q4_K_M",              # continuity with the published runs

    # --- Dense: slow here on purpose; gives the dense-vs-MoE contrast ---
    "qwen3.6:27b-q4_K_M",                # pairs with qwen3.6:35b-a3b
    "qwen3.8:27b-q4_K_M",                # released 2026-08-14, mid-revision
    "gemma4:31b-it-q4_K_M",              # pairs with gemma4:26b-a4b
    "granite4.1:30b-q4_K_M",

    # --- Small dense: fast, strong tool callers ---
    "granite4.1:8b-q4_K_M",
    "qwen3.5:4b-q4_K_M",
    "nemotron-3-nano:4b",
]

# Latest generation. Haiku 4.5 is still current (there is no Haiku 5), so that
# row is directly comparable to the published data.
ANTHROPIC_MODELS = [
    "claude-opus-5",
    "claude-sonnet-5",
    "claude-haiku-4-5",
]

# Not every open model exposes a reasoning toggle. ollama rejects `think` on
# these with HTTP 400 ("does not support thinking"), so a think-on arm for them
# is not a failed experiment, it is an impossible one. Verified by probing all
# 12 models directly; this constrains the reasoning-vs-plan-detail axis and is
# a finding in its own right.
THINK_UNSUPPORTED = {
    "granite4.1:30b-q4_K_M",
    "granite4.1:8b-q4_K_M",
}

PLAN_FILES = {
    "b":     REPO / "plan" / "PLAN.md",        # no-plan Track B column
    "v0p5":  REPO / "plan" / "PLAN_v1.md",     # Track B template variant
    "v1":    REPO / "plan" / "PLAN_v1.md",
    "v1g":   REPO / "plan" / "PLAN_v1g.md",
    "v1p25": REPO / "plan" / "PLAN_v1p25.md",
    "v1p5":  REPO / "plan" / "PLAN_v1p5.md",
    "v2":    REPO / "plan" / "PLAN.md",
}
# Lean -> detailed, matching PLAN_COLS in scripts/make_figures.py.
PLAN_ORDER = ["b", "v0p5", "v1", "v1g", "v1p25", "v1p5", "v2"]

RUNS_DIRS = {k: REVISION / "runs" / f"jetson_{k}" for k in PLAN_FILES}

# Per-column track restrictions, identical to matrix_5080.py.
TRACKS_BY_EXP = {
    "b":     ["B"],
    "v0p5":  ["B"],
    "v1":    ["A", "B"],
    "v1g":   ["A"],
    "v1p25": ["A"],
    "v1p5":  ["A"],
    "v2":    ["A", "B"],
}
TRACK_TEMPLATE = {"v0p5": "track_b_with_order_user"}

# Think-on generates ~5x the tokens, so it needs a correspondingly longer budget.
GEN_TIMEOUT_NO_THINK = 900
GEN_TIMEOUT_THINK = 2700


def is_anthropic(model: str) -> bool:
    return model.startswith("claude-")


def cell_id(model: str, think: str, track: str, seed: int) -> str:
    tag = model.replace("/", "_").replace(":", "_")
    if not is_anthropic(model):
        tag += f"_think-{think}"
    return f"{tag}_track-{track}_seed-{seed}"


def already_scored(runs_dir: Path, cell: str) -> Path | None:
    """Resumability: a scored cell is never re-run, so the driver can be
    interrupted and restarted without losing or duplicating work."""
    if not runs_dir.exists():
        return None
    for d in runs_dir.glob(f"{cell}_*"):
        if (d / "score.json").exists():
            return d
    return None


def run_cell(model: str, think: str, track: str, seed: int, plan: str) -> dict:
    runs_dir = RUNS_DIRS[plan]
    plan_path = PLAN_FILES[plan]
    cell = cell_id(model, think, track, seed)

    existing = already_scored(runs_dir, cell)
    if existing:
        return {"cell": cell, "plan": plan, "skipped": True,
                "run_id": existing.name,
                "score": json.loads((existing / "score.json").read_text())}

    runs_dir.mkdir(parents=True, exist_ok=True)
    timeout = GEN_TIMEOUT_THINK if think == "on" else GEN_TIMEOUT_NO_THINK

    cmd = [
        sys.executable, str(RUN_ONE),
        "--model", model,
        "--track", track,
        "--seed", str(seed),
        "--plan", str(plan_path),
        "--runs-dir", str(runs_dir),
        "--gen-timeout", str(timeout),
    ]
    if not is_anthropic(model):
        cmd += ["--think", think]
    if plan in TRACK_TEMPLATE:
        cmd += ["--track-template", TRACK_TEMPLATE[plan]]

    t0 = time.time()
    p = subprocess.run(cmd, capture_output=True, text=True)
    gen_secs = time.time() - t0

    if p.returncode not in (0, 1):
        return {"cell": cell, "plan": plan, "error": p.stderr[-2000:],
                "gen_secs": gen_secs}

    # run_one prints the run_id as its last stdout line. If it died before that
    # (an unhandled provider fault used to do this), stdout is empty and the
    # naive parse yields "", making run_dir == runs_dir — which the scorer then
    # crashes on with a confusing traceback. Fail loudly on the real cause.
    run_id = p.stdout.strip().split("\n")[-1] if p.stdout.strip() else ""
    if not run_id:
        return {"cell": cell, "plan": plan, "gen_secs": gen_secs,
                "error": "run_one produced no run_id; stderr: " + p.stderr[-1500:]}
    run_dir = runs_dir / run_id
    if not (run_dir / "meta.json").exists():
        return {"cell": cell, "plan": plan, "gen_secs": gen_secs, "run_id": run_id,
                "error": f"run dir missing meta.json: {run_dir}"}

    s = subprocess.run([sys.executable, str(SCORE), str(run_dir)],
                       capture_output=True, text=True)
    score = json.loads(s.stdout) if s.returncode == 0 and s.stdout.strip() \
        else {"error": s.stderr[:500]}

    # Surface the generation_status added for the thinking/refusal split, so a
    # plumbing failure is visible in the log rather than only in meta.json.
    status = None
    meta_p = run_dir / "meta.json"
    if meta_p.exists():
        status = json.loads(meta_p.read_text()).get("generation_status")

    return {"cell": cell, "plan": plan, "run_id": run_id, "score": score,
            "gen_secs": gen_secs, "generation_status": status}


def build_worklist(plans, models, thinks, seeds, tracks) -> list[tuple]:
    work = []
    for plan in plans:
        for track in TRACKS_BY_EXP[plan]:
            if track not in tracks:
                continue
            for model in models:
                if is_anthropic(model):
                    arms = ["off"]
                else:
                    arms = [t for t in thinks
                            if not (t == "on" and model in THINK_UNSUPPORTED)]
                for think in arms:
                    for seed in seeds:
                        work.append((model, think, track, seed, plan))
    return work


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--plans", default=",".join(PLAN_ORDER),
                    help=f"comma-separated subset of {PLAN_ORDER}")
    ap.add_argument("--models", default=None,
                    help="comma-separated model subset (default: all local + Anthropic)")
    ap.add_argument("--think", choices=["on", "off", "both"], default="both")
    ap.add_argument("--seeds", default=",".join(str(s) for s in SEEDS))
    ap.add_argument("--tracks", default="A,B")
    ap.add_argument("--local-only", action="store_true")
    ap.add_argument("--anthropic-only", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    # Concurrent passes must not share a log: a line carrying a score payload
    # can exceed the 4 KB atomic-append boundary and interleave.
    ap.add_argument("--log", default="matrix_jetson.jsonl",
                    help="log filename under revision/logs/")
    args = ap.parse_args()

    plans = [p.strip() for p in args.plans.split(",") if p.strip()]
    bad = [p for p in plans if p not in PLAN_FILES]
    if bad:
        raise SystemExit(f"unknown plan(s): {bad}; valid: {PLAN_ORDER}")
    plans.sort(key=PLAN_ORDER.index)

    if args.models:
        models = [m.strip() for m in args.models.split(",") if m.strip()]
    elif args.anthropic_only:
        models = list(ANTHROPIC_MODELS)
    elif args.local_only:
        models = list(LOCAL_MODELS)
    else:
        models = LOCAL_MODELS + ANTHROPIC_MODELS

    thinks = ["off", "on"] if args.think == "both" else [args.think]
    seeds = [int(s) for s in args.seeds.split(",") if s.strip()]
    tracks = [t.strip().upper() for t in args.tracks.split(",") if t.strip()]

    work = build_worklist(plans, models, thinks, seeds, tracks)

    print(f"plans   : {plans}")
    print(f"models  : {len(models)}")
    print(f"think   : {thinks}")
    print(f"seeds   : {seeds}")
    print(f"cells   : {len(work)}")
    if args.dry_run:
        for w in work:
            print("   ", cell_id(w[0], w[1], w[2], w[3]), f"[{w[4]}]")
        return 0

    log_path = REVISION / "logs" / args.log
    log_path.parent.mkdir(parents=True, exist_ok=True)

    t_start = time.time()
    done = skipped = failed = 0
    with log_path.open("a") as log:
        for i, (model, think, track, seed, plan) in enumerate(work, 1):
            res = run_cell(model, think, track, seed, plan)
            log.write(json.dumps(res) + "\n")
            log.flush()

            if res.get("skipped"):
                skipped += 1
                tag = "skip"
            elif res.get("error"):
                failed += 1
                tag = "FAIL"
            else:
                done += 1
                tag = res.get("generation_status") or "ok"

            elapsed = time.time() - t_start
            rate = elapsed / i
            eta_h = (rate * (len(work) - i)) / 3600
            print(f"[{i}/{len(work)}] {tag:<22} {res['cell']} [{plan}] "
                  f"({res.get('gen_secs', 0):.0f}s)  eta {eta_h:.1f}h",
                  flush=True)

    print(f"\ndone={done} skipped={skipped} failed={failed}  "
          f"wall={(time.time() - t_start) / 3600:.1f}h")
    print(f"log: {log_path}")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
