#!/usr/bin/env bash
# Wait for the qwen3.8 pull, retag to the local naming scheme, then probe
# whether it accepts `think`. The probe matters: Granite silently 400s on
# `think`, and mistaking that for a capability result cost a wrong diagnosis
# earlier in this revision. Cheap to check, expensive to assume.
set -uo pipefail
SRC="hf.co/ggml-org/Qwen3.8-27B-GGUF:Q4_K_M"
DST="qwen3.8:27b-q4_K_M"

echo "== waiting for pull to finish =="
for i in $(seq 1 240); do
  pgrep -f "ollama pull" >/dev/null || break
  sleep 15
done
if pgrep -f "ollama pull" >/dev/null; then echo "FAIL: pull still running after 60 min"; exit 1; fi

ollama list | grep -q "Qwen3.8-27B-GGUF" || { echo "FAIL: source model not present after pull"; exit 1; }

echo "== retagging =="
ollama cp "$SRC" "$DST" || { echo "FAIL: cp"; exit 1; }
ollama list | grep -E "qwen3.8|Qwen3.8"

echo
echo "== capability probe: think off =="
curl -s http://localhost:11434/api/chat -d "{\"model\":\"$DST\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly: OK\"}],\"think\":false,\"stream\":false,\"options\":{\"num_predict\":32}}" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print('  error:',d['error']) if 'error' in d else print('  content:',repr(d['message'].get('content','')[:60]),'| done_reason:',d.get('done_reason'))"

echo "== capability probe: think on =="
curl -s http://localhost:11434/api/chat -d "{\"model\":\"$DST\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly: OK\"}],\"think\":true,\"stream\":false,\"options\":{\"num_predict\":128}}" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print('  error:',d['error']) if 'error' in d else print('  content:',repr(d['message'].get('content','')[:60]),'| thinking:',repr((d['message'].get('thinking') or '')[:60]),'| done_reason:',d.get('done_reason'))"

echo
echo "== throughput (dense 27B; expect ~10 tok/s on 204.8 GB/s) =="
curl -s http://localhost:11434/api/chat -d "{\"model\":\"$DST\",\"messages\":[{\"role\":\"user\",\"content\":\"Count from 1 to 100, comma separated.\"}],\"think\":false,\"stream\":false,\"options\":{\"num_predict\":300}}" \
  | python3 -c "
import sys,json; d=json.load(sys.stdin)
n=d.get('eval_count') or 0; t=(d.get('eval_duration') or 1)/1e9
print(f'  {n} tokens in {t:.1f}s = {n/t:.1f} tok/s')"
echo "== prep done =="
