#!/usr/bin/env bash
# High-effort arm of the context-distance test, re-run at 128k.
#
# WHY A RE-RUN. The first pass gave every arm num_ctx = 32768, chosen to stop
# the high arm truncating. It was not enough: high effort emitted ~121,700
# characters (~30k tokens) and truncated, so those cells measured the budget,
# not reasoning length -- the same confound that killed the first budget
# ablation, one level up. Sizing was done against medium-effort behaviour
# without probing high on the real task first.
#
# 131072 is gpt-oss:20b's native context (gptoss.context_length), so this is
# the model's ceiling rather than an arbitrary larger number. Probed at 30 GB
# and 100% GPU on this board before launching.
#
# The low and medium arms are NOT re-run: both completed every cell without
# truncation at 32k, so they are already valid and comparable. Only the high
# arm was invalid.
#
# PRE-REGISTERED PREDICTION (unchanged): if thinking length causes errors,
# mean M3 at high should fall below medium (0.56) and low (0.33). If high
# matches or exceeds medium, the context-distance hypothesis is refuted across
# the full 250x range of reasoning length the control can produce.
set -uo pipefail
cd "$(dirname "$0")/../.."
REPO=$PWD
MODEL="gpt-oss:20b"
OUT="$REPO/revision/runs_effort"
LOG="$REPO/revision/logs/effort_gptoss_high128k.jsonl"
mkdir -p "$OUT"; : > "$LOG"

for cond in v1 v1p25 v2; do
  case $cond in
    v1)    PLAN="$REPO/plan/PLAN_v1.md" ;;
    v1p25) PLAN="$REPO/plan/PLAN_v1p25.md" ;;
    v2)    PLAN="$REPO/plan/PLAN.md" ;;   # NB: the v2 plan is plain PLAN.md
  esac
  [ -f "$PLAN" ] || { echo "FAIL: missing $PLAN"; exit 1; }
  for seed in 42 43 44; do
    echo "-- high@128k $cond seed=$seed ($(date +%H:%M))"
    python3 "$REPO/harness/run_one.py" \
      --model "$MODEL" --track A --seed "$seed" --plan "$PLAN" \
      --runs-dir "$OUT/${cond}_high128k" \
      --think high --num-ctx 131072 --num-predict 131072 \
      --gen-timeout 21600 2>&1 | tail -2
    d=$(find "$OUT/${cond}_high128k" -maxdepth 1 -type d -name "*seed-${seed}_*" \
          -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
    [ -n "$d" ] || continue
    python3 "$REPO/score/score_run.py" "$d" >/dev/null 2>&1 || true
    python3 - "$d" "$cond" "$seed" "$LOG" <<'PY'
import json,sys,os
d,cond,seed,log=sys.argv[1:5]
m=json.load(open(os.path.join(d,"meta.json")))
try: s=json.load(open(os.path.join(d,"score.json")))
except Exception: s={}
rec={"model":"gpt-oss:20b","plan":cond,"seed":int(seed),"effort":"high",
     "num_ctx":131072,"run_id":os.path.basename(d),
     "generation_status":m.get("generation_status"),
     "thinking_chars":m.get("thinking_chars"),
     "gen_secs":m.get("wall_seconds_generation"),
     "M1":s.get("m1_executes"),"M3":s.get("m3_jaccard")}
open(log,"a").write(json.dumps(rec)+"\n")
print(f"   -> {m.get('generation_status')} think={m.get('thinking_chars')} "
      f"{m.get('wall_seconds_generation',0):.0f}s M3={s.get('m3_jaccard')}")
PY
  done
done
echo "== high@128k done =="
