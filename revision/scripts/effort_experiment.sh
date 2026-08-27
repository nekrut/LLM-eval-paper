#!/usr/bin/env bash
# Causal test of the context-distance hypothesis.
#
# QUESTION. Reasoning-enabled runs are less accurate than reasoning-disabled
# ones. Is the *length* of the chain of thought the cause, or merely a
# correlate? Observationally the failing seed thought longer in 16/23 mixed
# cells (two-sided p = 0.093) -- directionally consistent, and unidentified as
# to direction, because a seed that wanders into a confused trajectory would
# both think longer and produce worse code.
#
# DESIGN. Manipulate reasoning length directly instead of observing it.
# gpt-oss:20b exposes a reasoning-effort control that ollama accepts as
# think = "low" | "medium" | "high"; a probe confirmed it is monotonic
# (230 / 1591 / >>1591 chars of thinking on a fixed trivial prompt). Prompt,
# seed, plan, model, budget and hardware are all held fixed; only effort varies.
#
# PRE-REGISTERED PREDICTION. If thinking length causes the errors, mean M3
# falls monotonically low > medium > high. If accuracy is flat across effort
# levels, thinking length is a symptom and the hypothesis is refuted.
#
# CELLS. The three Track-A conditions where gpt-oss:20b showed mixed outcomes
# across seeds in the main think-on arm (v1, v1.25, v2) x 3 seeds x 3 levels
# = 27 runs.
#
# BUDGET. num_ctx = num_predict = 32768 for EVERY arm, deliberately generous.
# If a budget were tight, the high-effort arm would truncate more and the
# comparison would measure truncation rather than reasoning length. Any
# truncated_in_thinking here invalidates that cell and is flagged, not scored.
#
# NB plan filenames do not match condition labels: the v2 plan is plain
# PLAN.md. Mapping copied from matrix_jetson.py::PLAN_FILES.
set -uo pipefail
cd "$(dirname "$0")/../.."
REPO=$PWD
MODEL="gpt-oss:20b"
OUT="$REPO/revision/runs_effort"
LOG="$REPO/revision/logs/effort_gptoss.jsonl"
mkdir -p "$OUT"; : > "$LOG"

for lvl in low medium high; do
  for cond in v1 v1p25 v2; do
    case $cond in
      v1)    PLAN="$REPO/plan/PLAN_v1.md" ;;
      v1p25) PLAN="$REPO/plan/PLAN_v1p25.md" ;;
      v2)    PLAN="$REPO/plan/PLAN.md" ;;
    esac
    [ -f "$PLAN" ] || { echo "FAIL: missing $PLAN"; exit 1; }
    for seed in 42 43 44; do
      echo "-- effort=$lvl $cond seed=$seed ($(date +%H:%M))"
      python3 "$REPO/harness/run_one.py" \
        --model "$MODEL" --track A --seed "$seed" --plan "$PLAN" \
        --runs-dir "$OUT/${cond}_${lvl}" \
        --think "$lvl" --num-ctx 32768 --num-predict 32768 \
        --gen-timeout 7200 2>&1 | tail -2
      d=$(find "$OUT/${cond}_${lvl}" -maxdepth 1 -type d -name "*seed-${seed}_*" \
            -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
      [ -n "$d" ] || continue
      python3 "$REPO/score/score_run.py" "$d" >/dev/null 2>&1 || true
      python3 - "$d" "$cond" "$seed" "$lvl" "$LOG" <<'PY'
import json,sys,os
d,cond,seed,lvl,log=sys.argv[1:6]
m=json.load(open(os.path.join(d,"meta.json")))
try: s=json.load(open(os.path.join(d,"score.json")))
except Exception: s={}
rec={"model":"gpt-oss:20b","plan":cond,"seed":int(seed),"effort":lvl,
     "run_id":os.path.basename(d),
     "generation_status":m.get("generation_status"),
     "thinking_chars":m.get("thinking_chars"),
     "gen_secs":m.get("wall_seconds_generation"),
     "M1":s.get("m1_executes"),"M3":s.get("m3_jaccard")}
open(log,"a").write(json.dumps(rec)+"\n")
print(f"   -> {m.get('generation_status')} think={m.get('thinking_chars')} M3={s.get('m3_jaccard')}")
PY
    done
  done
done
echo "== effort experiment done =="
python3 - "$LOG" <<'PY'
import json,sys,collections,statistics as st
rows=[json.loads(l) for l in open(sys.argv[1])]
print(f"\n{'effort':<8}{'n':>4}{'mean thinking':>15}{'mean M3':>10}  truncated")
for lvl in ("low","medium","high"):
    v=[r for r in rows if r["effort"]==lvl]
    if not v: continue
    ok=[r for r in v if r["generation_status"]=="ok"]
    m3=[r["M3"] for r in ok if r["M3"] is not None]
    tr=sum(1 for r in v if r["generation_status"]=="truncated_in_thinking")
    print(f"{lvl:<8}{len(v):>4}{st.mean([r['thinking_chars'] or 0 for r in v]):>15.0f}"
          f"{(st.mean(m3) if m3 else float('nan')):>10.2f}  {tr}")
PY
