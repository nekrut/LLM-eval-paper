#!/usr/bin/env bash
# Full local Figure-1 matrix on the Jetson, run as two sequential arms.
#
# Why two arms instead of one interleaved pass: the driver's natural cell order
# alternates think-off and think-on per model, so an interrupted single pass
# leaves both arms half-finished and neither figure complete. Running think-off
# to completion first yields a publishable 7-column gradient in a fraction of
# the total time; think-on then adds the reasoning axis on top. Same total work,
# but a usable result much earlier and a cheaper failure if something is wrong.
#
# Both arms are resumable: any cell with a score.json is skipped, so this script
# can be killed and re-run without losing or duplicating work.
set -uo pipefail

cd /media/anton/disk1/git/LLM-eval-paper

REQUIRED=(laguna-xs-2.1:q4_K_M glm-4.7-flash:q4_K_M gemma4:31b-it-q4_K_M)

echo "=== waiting for outstanding model pulls ==="
while :; do
  missing=()
  for m in "${REQUIRED[@]}"; do
    ollama list 2>/dev/null | awk '{print $1}' | grep -qx "$m" || missing+=("$m")
  done
  [ ${#missing[@]} -eq 0 ] && break
  echo "  $(date +%H:%M:%S) still missing: ${missing[*]}"
  sleep 120
done
echo "all 12 local models present: $(date)"
echo

echo "=========================================================="
echo "ARM 1/2: think-off  ($(date))"
echo "=========================================================="
python3 revision/scripts/matrix_jetson.py --local-only --think off \
        --log matrix_jetson_thinkoff.jsonl
echo "arm 1 exit: $?  ($(date))"
echo

echo "=========================================================="
echo "ARM 2/2: think-on  ($(date))"
echo "=========================================================="
python3 revision/scripts/matrix_jetson.py --local-only --think on \
        --log matrix_jetson_thinkon.jsonl
echo "arm 2 exit: $?  ($(date))"

echo
echo "=== complete: $(date) ==="
echo "logs:  revision/logs/matrix_jetson_think{off,on}.jsonl"
echo "runs:  revision/runs/jetson_*/"
