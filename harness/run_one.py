#!/usr/bin/env python3
"""
Run one benchmark cell: (model_id, track, seed) -> runs/<run_id>/

Steps:
  1. Build the user message from prompts/<track>_user.tmpl, substituting
     {TOOL_INVENTORY} and {PLAN}.
  2. Generate the script via the model (claude CLI for Anthropic; ollama HTTP
     for qwen3.6).
  3. Set up sandbox: runs/<run_id>/ with data/ symlinked, results/ empty.
  4. Execute the generated script with a 600 s wall-clock budget.
  5. Persist script.sh, usage.json, meta.json, exec.json under the run dir.

Scoring is NOT done here; see score/score_run.py.

Usage:
  python3 run_one.py --model claude-haiku-4-5 --track A --seed 42
  python3 run_one.py --model qwen3.6:35b --think on --track A --seed 42
"""
from __future__ import annotations
import argparse
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
import urllib.request
import uuid
from pathlib import Path

BENCH = Path(__file__).resolve().parent.parent
PROMPTS = BENCH / "prompts"
PLAN_FILE = BENCH / "plan" / "PLAN.md"
RUNS = BENCH / "runs"


def tool_inventory() -> str:
    p = subprocess.run(
        [str(BENCH / "setup" / "verify_env.sh")],
        capture_output=True, text=True, check=True,
    )
    out = p.stdout
    m = re.search(r"^TOOL_INVENTORY.*?^OK$", out, re.S | re.M)
    if not m:
        raise RuntimeError("verify_env.sh did not return expected block")
    return m.group(0).rsplit("\n", 1)[0]  # drop trailing "OK"


def build_user_message(track: str, plan_path: Path, track_template: str | None = None) -> str:
    tmpl_name = track_template or f"track_{track.lower()}_user"
    tmpl = (PROMPTS / f"{tmpl_name}.tmpl").read_text()
    inv = tool_inventory()
    out = tmpl.replace("{TOOL_INVENTORY}", inv)
    if "{PLAN}" in out:
        out = out.replace("{PLAN}", plan_path.read_text())
    return out


def strip_fences(s: str) -> str:
    s = s.strip()
    m = re.match(r"^```(?:bash|sh)?\s*\n(.*?)\n```\s*$", s, re.S)
    if m:
        return m.group(1).strip()
    return s


def call_claude(model: str, system_text: str, user_text: str) -> dict:
    cmd = [
        "claude", "-p",
        "--model", model,
        "--system-prompt", system_text,
        "--output-format", "json",
        "--no-session-persistence",
        "--disallowedTools", "*",
        "--max-budget-usd", "5",
    ]
    t0 = time.time()
    p = subprocess.run(cmd, input=user_text, capture_output=True, text=True)
    elapsed = time.time() - t0
    if p.returncode != 0:
        raise RuntimeError(f"claude failed (exit {p.returncode}):\n{p.stderr[:2000]}")
    try:
        d = json.loads(p.stdout)
    except json.JSONDecodeError:
        raise RuntimeError(f"claude returned non-JSON:\n{p.stdout[:2000]}")
    # Current Claude models can decline a request: the CLI exits 0 and returns a
    # normal payload carrying a refusal rather than a script. Left undetected
    # that scores as a total capability failure, when it is a policy outcome.
    # The exact payload shape isn't contractually stable, so keep every
    # non-result field for post-hoc inspection and flag the obvious cases.
    envelope = {k: v for k, v in d.items() if k != "result"}
    refused = bool(d.get("is_error")) or "refus" in str(d.get("subtype", "")).lower()
    return {
        "provider": "anthropic",
        "model": model,
        "script": strip_fences(d.get("result", "")),
        "thinking": "",          # not exposed by `claude -p --output-format json`
        "done_reason": d.get("subtype"),
        "refused": refused,
        "envelope": envelope,
        "usage": d.get("usage", {}),
        "cost_usd": d.get("total_cost_usd", d.get("cost_usd")),
        "duration_ms": d.get("duration_ms"),
        "wall_seconds": elapsed,
        "raw_response_preview": d.get("result", "")[:400],
    }


def call_ollama(model: str, think: bool, system_text: str, user_text: str, seed: int,
                gen_timeout: int = 900, num_predict: int = 16384, num_ctx: int = 16384) -> dict:
    # num_predict/num_ctx default to 16384 because that is the budget every
    # published and revision cell ran under -- changing the default would
    # silently invalidate comparisons against them. Override only for a
    # deliberate budget ablation, and keep those runs in their own log.
    #
    # Note the two interact: the prompt is charged against num_ctx, so with
    # both at 16384 the usable thinking budget is ~14k tokens, not 16k.
    # Raising num_predict alone does nothing once num_ctx is the binding limit.
    # /no_think is a Qwen-family control token; other model families use the
    # `think` payload field instead and treat the prefix as literal user text.
    if not think and model.lower().startswith("qwen"):
        user_text = "/no_think\n" + user_text
    payload = {
        "model": model,
        "stream": False,
        "messages": [
            {"role": "system", "content": system_text},
            {"role": "user", "content": user_text},
        ],
        "think": think,
        "options": {
            "temperature": 0.2,
            "seed": seed,
            "num_predict": num_predict,
            "num_ctx": num_ctx,
        },
    }
    req = urllib.request.Request(
        "http://localhost:11434/api/chat",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    t0 = time.time()
    # The provider can fail mid-request (e.g. a CUDA fault surfaces as HTTP 500).
    # Letting that propagate kills the process before the run dir exists, which
    # leaves the caller with no artifacts and no way to tell an infrastructure
    # fault from a model failure. Capture it as a first-class outcome instead.
    try:
        with urllib.request.urlopen(req, timeout=gen_timeout) as r:
            d = json.loads(r.read())
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")[:2000]
        return {
            "provider": "ollama", "model": model, "think": think,
            "script": "", "thinking": "", "done_reason": None,
            "provider_error": f"HTTP {e.code}: {body}",
            "usage": {}, "cost_usd": 0.0,
            "duration_ms": int((time.time() - t0) * 1000),
            "wall_seconds": time.time() - t0, "raw_response_preview": "",
        }
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        return {
            "provider": "ollama", "model": model, "think": think,
            "script": "", "thinking": "", "done_reason": None,
            "provider_error": f"{type(e).__name__}: {e}",
            "usage": {}, "cost_usd": 0.0,
            "duration_ms": int((time.time() - t0) * 1000),
            "wall_seconds": time.time() - t0, "raw_response_preview": "",
        }
    elapsed = time.time() - t0
    msg = d.get("message", {})
    content = msg.get("content", "")
    # ollama >= 0.32 splits reasoning output into its own field. Reading only
    # `content` makes a model that spent its num_predict budget thinking look
    # like it returned nothing at all, which scores as a total failure even
    # though the model may have been reasoning correctly. Capture both, plus
    # done_reason, so the two cases can be told apart downstream.
    thinking = msg.get("thinking") or ""
    return {
        "provider": "ollama",
        "model": model,
        "think": think,
        "script": strip_fences(content),
        "thinking": thinking,
        "done_reason": d.get("done_reason"),
        "usage": {
            "prompt_eval_count": d.get("prompt_eval_count"),
            "eval_count": d.get("eval_count"),
            "prompt_eval_duration_ns": d.get("prompt_eval_duration"),
            "eval_duration_ns": d.get("eval_duration"),
            "total_duration_ns": d.get("total_duration"),
        },
        "cost_usd": 0.0,
        "duration_ms": int(elapsed * 1000),
        "wall_seconds": elapsed,
        "raw_response_preview": content[:400],
    }


def setup_sandbox(run_dir: Path) -> None:
    run_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / "data").symlink_to(BENCH / "data")
    (run_dir / "results").mkdir(exist_ok=True)


SHIMS_DIR = BENCH / "harness" / "error_shims"
# Resolve the conda env's bin/ portably. Override with EVAL_REAL_BIN_DIR.
CONDA_BIN = os.environ.get("EVAL_REAL_BIN_DIR",
                           str(Path.home() / "miniforge3" / "envs" / "bench" / "bin"))
INJECT_PATTERNS = {
    "none", "flake_first_call", "one_sample_fails", "silent_truncation",
    "stderr_warning_storm", "slow_tool", "wrong_format_output", "missing_lib_error",
}


def setup_inject(run_dir: Path, pattern: str, target: str) -> dict:
    """Prepare per-run shim bin/ and return env-var overrides for execute()."""
    bin_dir = run_dir / "_eval_bin"
    bin_dir.mkdir(exist_ok=True)
    state_dir = run_dir / "_eval_state"
    state_dir.mkdir(exist_ok=True)
    # Symlink wrapper scripts for both shimmed tools so the shim is always
    # in front of conda's bin/, regardless of which tool the model invokes.
    for tool in ("bwa", "lofreq"):
        link = bin_dir / tool
        if link.exists() or link.is_symlink():
            link.unlink()
        link.symlink_to(SHIMS_DIR / tool)
    return {
        "EVAL_INJECT_PATTERN": pattern,
        "EVAL_INJECT_TARGET": target,
        "EVAL_INJECT_STATE": str(state_dir),
        "EVAL_REAL_BIN_DIR": CONDA_BIN,
        "_PATH_PREFIX": str(bin_dir),
    }


def execute(run_dir: Path, script: str, budget_s: int = 600, inject_env: dict | None = None) -> dict:
    script_path = run_dir / "run.sh"
    script_path.write_text(script)
    script_path.chmod(0o755)
    log_path = run_dir / "exec.log"
    t0 = time.time()
    # Conda's `activate` prepends the env's bin/ to PATH, so any custom PATH
    # prefix we set BEFORE activate gets pushed back behind conda's bin/.
    # Inject the shim path AFTER conda activate so the shim wins.
    env = os.environ.copy()
    path_prefix = ""
    if inject_env:
        path_prefix = inject_env.pop("_PATH_PREFIX", "")
        env.update(inject_env)
    inject_path_cmd = f'export PATH="{path_prefix}:$PATH" && ' if path_prefix else ""
    activate = (
        "source $HOME/miniforge3/etc/profile.d/conda.sh && "
        "conda activate bench && "
        + inject_path_cmd
        + "exec bash run.sh"
    )
    try:
        with log_path.open("wb") as logf:
            p = subprocess.run(
                ["bash", "-c", activate],
                cwd=str(run_dir),
                stdout=logf, stderr=subprocess.STDOUT,
                timeout=budget_s,
                env=env,
            )
        return {
            "exit_code": p.returncode,
            "wall_seconds": time.time() - t0,
            "timed_out": False,
        }
    except subprocess.TimeoutExpired:
        return {"exit_code": -1, "wall_seconds": time.time() - t0, "timed_out": True}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--track", choices=["A", "B"], required=True)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--think", choices=["on", "off"], default="on",
                    help="Only meaningful for ollama models")
    ap.add_argument("--run-id", default=None)
    ap.add_argument("--plan", default=str(PLAN_FILE),
                    help="Path to PLAN.md (defaults to plan/PLAN.md)")
    ap.add_argument("--runs-dir", default=str(RUNS),
                    help="Directory to write run output (default runs/)")
    ap.add_argument("--num-predict", type=int, default=16384,
                    help="max tokens to generate (default 16384 = every published "
                         "and revision cell; change only for a budget ablation)")
    ap.add_argument("--num-ctx", type=int, default=16384,
                    help="context window (default 16384). The prompt is charged "
                         "against this, so it, not --num-predict, is usually the "
                         "binding limit on thinking length.")
    ap.add_argument("--gen-timeout", type=int, default=900,
                    help="Ollama HTTP timeout in seconds (default 900)")
    ap.add_argument("--track-template", default=None,
                    help="Override template stem (default: track_<a|b>_user). "
                         "E.g. 'track_b_with_order_user' for the v0.5 condition.")
    ap.add_argument("--inject", default="none", choices=sorted(INJECT_PATTERNS),
                    help="Error-injection pattern (default: none).")
    ap.add_argument("--inject-target", default="lofreq", choices=["bwa", "lofreq"],
                    help="Tool the injection targets (default: lofreq).")
    args = ap.parse_args()

    runs_root = Path(args.runs_dir)
    plan_path = Path(args.plan)

    # Anthropic model ids start with "claude-"; everything else is local (ollama).
    is_ollama = not args.model.startswith("claude-")
    cell_tag = args.model.replace("/", "_").replace(":", "_")
    if is_ollama:
        cell_tag += f"_think-{args.think}"
    run_id = args.run_id or f"{cell_tag}_track-{args.track}_seed-{args.seed}_{uuid.uuid4().hex[:6]}"
    run_dir = runs_root / run_id

    if run_dir.exists():
        print(f"[run_one] {run_dir} exists — removing for clean run", file=sys.stderr)
        shutil.rmtree(run_dir)

    system_text = (PROMPTS / "system.txt").read_text()
    user_text = build_user_message(args.track, plan_path, args.track_template)

    print(f"[run_one] generating script via {args.model} (track {args.track}, seed {args.seed})", file=sys.stderr)
    if is_ollama:
        gen = call_ollama(args.model, args.think == "on", system_text, user_text, args.seed,
                          gen_timeout=args.gen_timeout,
                          num_predict=args.num_predict, num_ctx=args.num_ctx)
    else:
        gen = call_claude(args.model, system_text, user_text)

    setup_sandbox(run_dir)

    # Distinguish "the model produced no script" from "the model never got to
    # the script because it used its whole token budget reasoning". Both look
    # like an empty script, but only the first is a model failure; the second
    # is a generation-budget artifact and must not be scored as a capability
    # result. See call_ollama() on the ollama >= 0.32 thinking/content split.
    if gen.get("provider_error"):
        # Infrastructure fault, not a capability result. Must never be scored
        # as a model failure — see the CUDA illegal-memory-access faults that
        # long generations trigger on this JetPack 5 build.
        generation_status = "provider_error"
    elif gen.get("refused"):
        generation_status = "refusal"
    elif gen["script"]:
        generation_status = "ok"
    elif gen.get("thinking") and gen.get("done_reason") == "length":
        generation_status = "truncated_in_thinking"
    elif gen.get("done_reason") == "length":
        generation_status = "truncated"
    else:
        generation_status = "empty_content"

    meta = {
        "run_id": run_id,
        "model": args.model,
        "track": args.track,
        "seed": args.seed,
        "think": args.think if is_ollama else None,
        "provider": gen["provider"],
        "generation_status": generation_status,
        "done_reason": gen.get("done_reason"),
        "provider_error": gen.get("provider_error"),
        "thinking_chars": len(gen.get("thinking") or ""),
        # Recorded so a run is self-describing: a budget-ablation run is
        # otherwise indistinguishable from a default one after the fact, and
        # `truncated_in_thinking` means nothing without the budget it hit.
        "num_predict": args.num_predict if is_ollama else None,
        "num_ctx": args.num_ctx if is_ollama else None,
        "wall_seconds_generation": gen["wall_seconds"],
        "duration_ms_generation": gen["duration_ms"],
        "plan_path": str(plan_path),
        "plan_name": plan_path.stem,
        "inject_pattern": args.inject,
        "inject_target": args.inject_target if args.inject != "none" else None,
    }
    (run_dir / "meta.json").write_text(json.dumps(meta, indent=2))
    (run_dir / "usage.json").write_text(json.dumps({
        "usage": gen["usage"],
        "cost_usd": gen["cost_usd"],
    }, indent=2))
    (run_dir / "raw_response.txt").write_text(gen["raw_response_preview"])
    if gen.get("thinking"):
        (run_dir / "raw_thinking.txt").write_text(gen["thinking"])
    if gen.get("envelope"):
        (run_dir / "provider_envelope.json").write_text(
            json.dumps(gen["envelope"], indent=2, default=str))

    if not gen["script"]:
        print(f"[run_one] EMPTY script returned ({generation_status}, "
              f"done_reason={gen.get('done_reason')}, "
              f"thinking={len(gen.get('thinking') or '')} chars); aborting before exec",
              file=sys.stderr)
        if generation_status == "truncated_in_thinking":
            print("[run_one] NOTE: model was still reasoning when it hit num_predict. "
                  "This is a generation-budget artifact, not a model capability result.",
                  file=sys.stderr)
        (run_dir / "exec.json").write_text(json.dumps(
            {"exit_code": None, "skipped": "empty_script",
             "generation_status": generation_status}, indent=2))
        return 2

    inject_env = None
    if args.inject != "none":
        inject_env = setup_inject(run_dir, args.inject, args.inject_target)
        print(f"[run_one] error injection: pattern={args.inject} target={args.inject_target}", file=sys.stderr)

    print(f"[run_one] executing run.sh in {run_dir} (budget 600s)", file=sys.stderr)
    exec_res = execute(run_dir, gen["script"], budget_s=600, inject_env=inject_env)
    (run_dir / "exec.json").write_text(json.dumps(exec_res, indent=2))

    print(f"[run_one] done: {run_dir}  exit={exec_res['exit_code']}  exec_wall={exec_res['wall_seconds']:.1f}s", file=sys.stderr)
    print(run_id)  # stdout = run_id for matrix.py
    return 0 if exec_res["exit_code"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
