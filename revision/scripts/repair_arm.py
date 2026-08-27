#!/usr/bin/env python3
"""Bounded repair arm on the perturbed condition (T3.1 / C1).

One-shot execution is the paper's stated limitation. This arm gives each
executor what an operator at a terminal would see, and nothing more:

  attempt 1: same prompt as the perturbed condition (plan v2 verbatim,
             reference moved, prompt states the real path)
  on nonzero exit: a follow-up message with the failed script, the exit
             code, and the tail of the execution log. Ask for a fixed
             script. At most 3 attempts total.

The retry signal is the exit code only. A script that exits 0 with wrong
output gets no retry, because the executor has no signal to act on. The
score is computed after the loop and is never shown to the model.

All attempts run in one sandbox per cell, like a real operator rerunning
in place. Each attempt's script and log are archived in the cell dir.

Usage:
  python3 revision/scripts/repair_arm.py --dry-run
  python3 revision/scripts/repair_arm.py
"""
from __future__ import annotations
import argparse, json, shutil, subprocess, sys, time
from pathlib import Path

BENCH = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(BENCH / "harness"))
sys.path.insert(0, str(BENCH / "revision" / "scripts"))
import run_one                                     # noqa: E402
from matrix_jetson import LOCAL_MODELS             # noqa: E402

PLAN = BENCH / "plan" / "PLAN.md"                  # v2, verbatim
LOG = BENCH / "revision" / "logs" / "matrix_jetson_repair.jsonl"
RUNS = BENCH / "revision" / "runs_repair"
MAX_ATTEMPTS = 3
LOG_TAIL = 40                                      # lines of exec.log shown back


def feedback(script: str, exit_code: int, exec_log: str) -> str:
    tail = "\n".join(exec_log.splitlines()[-LOG_TAIL:])
    return (
        "Your script failed.\n\n"
        f"Exit code: {exit_code}\n\n"
        "Last lines of the execution log:\n"
        "```\n" + tail + "\n```\n\n"
        "The script you submitted:\n"
        "```bash\n" + script + "\n```\n\n"
        "Produce a corrected version of the complete script. "
        "Same output format: a single bash script, no markdown fences, no commentary."
    )


def run_cell(model: str, seed: int) -> dict:
    cell = f"{model.replace(':', '_')}_repair_seed-{seed}"
    run_dir = RUNS / cell
    if (run_dir / "score.json").exists():
        return {"cell": cell, "skipped": True,
                "score": json.loads((run_dir / "score.json").read_text())}
    if run_dir.exists():
        shutil.rmtree(run_dir)
    run_one.setup_sandbox(run_dir, "data_shifted")

    system_text = (run_one.PROMPTS / "system.txt").read_text()
    user0 = run_one.build_user_message("A", PLAN, "track_a_shifted_user")
    messages = [("user", user0)]
    attempts = []

    for attempt in range(1, MAX_ATTEMPTS + 1):
        # replay the conversation as a single user turn per exchange
        if len(messages) == 1:
            user_text = user0
        else:
            # fold the history into one user message; the harness API is
            # single-turn, and the models here have no server-side state
            user_text = user0 + "\n\n" + "\n\n".join(m[1] for m in messages[1:])
        gen = run_one.call_ollama(model, False, system_text, user_text, seed)
        script = run_one.strip_fences(gen.get("script", "") or "")
        rec = {"attempt": attempt,
               "gen_secs": gen.get("gen_secs"),
               "provider_error": gen.get("provider_error"),
               "script_chars": len(script)}
        if not script:
            rec["outcome"] = "no_script"
            attempts.append(rec)
            break
        ex = run_one.execute(run_dir, script)
        rec["exit_code"] = ex.get("exit_code")
        (run_dir / f"attempt_{attempt}.sh").write_text(script)
        log_text = (run_dir / "exec.log").read_text() if (run_dir / "exec.log").exists() else ""
        (run_dir / f"attempt_{attempt}.log").write_text(log_text)
        if ex.get("exit_code") == 0:
            rec["outcome"] = "exit0"
            attempts.append(rec)
            break
        rec["outcome"] = "failed"
        attempts.append(rec)
        messages.append(("user", feedback(script, ex.get("exit_code"), log_text)))

    # score_run.py reads meta.json, exec.json and usage.json from the run dir;
    # run_one writes them in its own main(), which this driver bypasses.
    last_exit = attempts[-1].get("exit_code") if attempts else None
    (run_dir / "meta.json").write_text(json.dumps(
        {"model": model, "seed": seed, "plan": "v2_perturbed_repair",
         "inject_pattern": "none", "inject_target": None,
         "wall_seconds_generation": sum(a.get("gen_secs") or 0 for a in attempts)}))
    (run_dir / "exec.json").write_text(json.dumps(
        {"exit_code": last_exit, "wall_seconds": None}))
    (run_dir / "usage.json").write_text(json.dumps({"cost_usd": 0.0}))

    subprocess.run([sys.executable, str(BENCH / "score" / "score_run.py"), str(run_dir)],
                   capture_output=True, text=True)
    score = {}
    if (run_dir / "score.json").exists():
        score = json.loads((run_dir / "score.json").read_text())
    return {"cell": cell, "model": model, "seed": seed,
            "attempts": attempts, "n_attempts": len(attempts),
            "score": score}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", default="42,43,44")
    ap.add_argument("--models", default="")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    models = [m for m in a.models.split(",") if m] or list(LOCAL_MODELS)
    seeds = [int(s) for s in a.seeds.split(",")]
    cells = [(m, s) for m in models for s in seeds]
    print(f"repair arm: {len(models)} models x {len(seeds)} seeds, "
          f"max {MAX_ATTEMPTS} attempts", file=sys.stderr)
    if a.dry_run:
        for m, s in cells:
            print(f"  {m} seed-{s}")
        return 0
    RUNS.mkdir(parents=True, exist_ok=True)
    LOG.parent.mkdir(parents=True, exist_ok=True)
    for i, (m, s) in enumerate(cells, 1):
        t0 = time.time()
        rec = run_cell(m, s)
        rec["wall_secs"] = round(time.time() - t0, 1)
        with LOG.open("a") as fh:
            fh.write(json.dumps(rec) + "\n")
        m3 = (rec.get("score") or {}).get("m3_jaccard")
        print(f"[{i}/{len(cells)}] {rec['cell']} attempts={rec.get('n_attempts')} "
              f"M3={m3} ({rec['wall_secs']}s)", file=sys.stderr)
    print("done", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
