#!/usr/bin/env bash
# Reasoning-budget ablation for qwen3.8:27b.  (v2 — see REVISION HISTORY)
#
# WHY THIS EXISTS
# The 16k think-on arm produced 27/27 truncated_in_thinking. At every plan
# level that scores 1.00 with reasoning OFF (v1g, v1.25, v1.5, v2), turning
# reasoning ON yields no script. Two explanations fit and the 16k arm cannot
# distinguish them:
#
#   (1) Reasoning is harmful here. The plan already contains the answer, so
#       reasoning makes the model re-derive it and never converge.
#   (2) 16k is simply too small for this model to reason AND write.
#
# This ablation discriminates: same model, same plan, same seeds, reasoning ON
# throughout; only the budget changes.
#
#   Cells COMPLETE at 64k  -> explanation (2). 16k was the problem.
#   Cells still truncate at 64k -> explanation (1). The model expands its
#       reasoning to fill whatever budget it is given, and no realistic budget
#       fixes it.
#
# REVISION HISTORY
# v1 ran 32k first with --gen-timeout 5400 and lost its first cell to
# `provider_error: timed out` after 90 min with thinking_chars=0 — a wasted
# cell that measured nothing. Generation does NOT scale linearly with context:
# at 16k the model exhausted its budget in ~37 min, but at 32k it was still
# generating at 90 min, because per-token cost rises as the context fills.
# Two changes follow from that:
#   - Timeouts are now generous (8 h at 64k). A timeout produces
#     `provider_error`, which is an infrastructure failure and answers nothing;
#     a budget exhaustion produces `truncated_in_thinking`, which is data.
#     Erring long costs wall-clock; erring short costs the experiment.
#   - 64k runs FIRST. It is the decisive test — 4x the original budget. If the
#     model still truncates there, 32k cannot change the conclusion, and if it
#     completes there, 32k becomes a refinement rather than a prerequisite.
#
# SCOPE. v1g Track A only, 3 seeds. v1g has a clean 1.00 reasoning-off
# baseline to lose, which is what makes it informative. v2 was dropped from
# the ablation: it would double the runtime and the schedule cannot absorb it,
# and v1g already answers the question. No-plan cells are excluded because the
# model fails those with reasoning off too, so they cannot discriminate.
#
# ISOLATION. Results go to revision/runs_ablation/ and
# revision/logs/ablation_*.jsonl. These runs use a non-default num_ctx and must
# never be pooled with the 16k matrix — ARM_LOGS in make_revision_figures.py
# deliberately does not name them.
#
# MEMORY (measured, not projected): 25 GB at 16k, 27 GB at 32k, 31 GB at 64k,
# all 100% GPU on the 61 GB board. The probe below re-verifies residency
# anyway, because a CPU spill would make a number incomparable rather than
# merely slow.
#
# Usage: bash revision/scripts/budget_ablation.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
REPO=$PWD
MODEL="qwen3.8:27b-q4_K_M"
SEEDS="42 43 44"
COND="v1g"
PLAN="$REPO/plan/PLAN_v1g.md"     # NB: plan filenames do not match condition
                                  # labels elsewhere (the v2 plan is plain
                                  # PLAN.md). v1g is one of the few that does.
OUT="$REPO/revision/runs_ablation"
mkdir -p "$OUT"
[ -f "$PLAN" ] || { echo "FAIL: missing plan file $PLAN"; exit 1; }

# budget:timeout_seconds — 64k first (decisive), then 32k (refinement).
BUDGET_SPEC="65536:28800 32768:14400"

probe_gpu() {   # $1 = num_ctx ; echoes "ok" only if fully GPU-resident
  curl -s http://localhost:11434/api/chat -d "{\"model\":\"$MODEL\",
    \"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"think\":false,
    \"stream\":false,\"options\":{\"num_ctx\":$1,\"num_predict\":8}}" >/dev/null 2>&1
  sleep 3
  local ps; ps=$(ollama ps 2>/dev/null | grep -i qwen3.8 || true)
  echo "    ollama ps: ${ps:-<not loaded>}" >&2
  [[ "$ps" == *"100% GPU"* ]] && echo ok || echo degraded
}

for spec in $BUDGET_SPEC; do
  ctx=${spec%%:*}; tmo=${spec##*:}
  echo "=========================================================="
  echo "== num_ctx=$ctx  timeout=${tmo}s ($((tmo/3600))h)"
  echo "=========================================================="
  if [ "$(probe_gpu "$ctx")" != ok ]; then
    echo "  NOT fully GPU-resident — SKIPPING $ctx (would not be comparable)"
    continue
  fi
  LOG="$REPO/revision/logs/ablation_${ctx}.jsonl"
  : > "$LOG"
  for seed in $SEEDS; do
    echo "-- ctx=$ctx $COND seed=$seed  (started $(date +%H:%M))"
    python3 "$REPO/harness/run_one.py" \
      --model "$MODEL" --track A --seed "$seed" --plan "$PLAN" \
      --runs-dir "$OUT/${COND}_ctx${ctx}" \
      --think on --num-ctx "$ctx" --num-predict "$ctx" \
      --gen-timeout "$tmo" 2>&1 | tail -3
    d=$(find "$OUT/${COND}_ctx${ctx}" -maxdepth 1 -type d -name "*seed-${seed}_*" \
          -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
    if [ -n "$d" ]; then
      python3 "$REPO/score/score_run.py" "$d" >/dev/null 2>&1 || true
      python3 - "$d" "$COND" "$seed" "$ctx" "$LOG" <<'PY'
import json,sys,os
d,cond,seed,ctx,log=sys.argv[1:6]
m=json.load(open(os.path.join(d,"meta.json")))
try: s=json.load(open(os.path.join(d,"score.json")))
except Exception: s={}
rec={"model":"qwen3.8:27b-q4_K_M","plan":cond,"track":"A","seed":int(seed),
     "num_ctx":int(ctx),"run_id":os.path.basename(d),
     "generation_status":m.get("generation_status"),
     "provider_error":m.get("provider_error"),
     "gen_secs":m.get("wall_seconds_generation"),
     "thinking_chars":m.get("thinking_chars"),
     "score":{"M3":s.get("m3_jaccard"),"M1":s.get("m1_executes")}}
open(log,"a").write(json.dumps(rec)+"\n")
print(f"   -> {m.get('generation_status')}  {m.get('wall_seconds_generation',0):.0f}s"
      f"  thinking={m.get('thinking_chars')}  M3={s.get('m3_jaccard')}")
PY
    fi
  done
  echo "-- summary for ctx=$ctx --"
  python3 - "$LOG" <<'PY'
import json,sys,collections
rows=[json.loads(l) for l in open(sys.argv[1])]
st=collections.Counter(r["generation_status"] for r in rows)
m3=[r["score"]["M3"] for r in rows if r["score"]["M3"] is not None]
print("  ",dict(st),"meanM3=",(sum(m3)/len(m3) if m3 else "n/a"))
if st.get("provider_error"):
    print("   WARNING: provider_error cells are timeouts, not results — raise --gen-timeout")
PY
done
echo "== ablation done =="
