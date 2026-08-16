#!/usr/bin/env bash
# Mitigate the CUDA "illegal memory access" faults seen during the think-on arm.
# Run with: sudo bash revision/scripts/fix_cuda_faults.sh
#
# Evidence: granite4.1:8b (a 5 GB dense model) failed 0/27 with thinking off and
# 9/9 with thinking on, on a box with 61 GB. Memory exhaustion cannot explain
# that. The trigger is generation LENGTH, and the two settings that make long
# generations take a non-default kernel path are the quantized KV cache and
# flash attention -- on a build whose CUDA architectures ollama reported it
# could not verify for sm_87.
#
# Two changes, both of which also improve the benchmark independently:
#   KV cache q8_0 -> f16   removes the suspect kernel path, and removes a
#                          confound: quantizing the KV cache changes model
#                          output, which is a variable you do not want in a
#                          study measuring model behaviour.
#   MAX_LOADED_MODELS 2->1 one model resident at a time, so every model is
#                          measured under identical conditions instead of
#                          sometimes sharing the GPU with a leftover.
set -euo pipefail

OVERRIDE=/etc/systemd/system/ollama.service.d/override.conf
BACKUP=/media/anton/disk1/ollama/dist/v0.32.5/override.conf.pre-cuda-fix

echo "==> current config"
grep -E "KV_CACHE|MAX_LOADED|FLASH" "$OVERRIDE" || true

[ -f "$BACKUP" ] || cp -a "$OVERRIDE" "$BACKUP"
echo "==> backed up to $BACKUP"

sed -i 's/OLLAMA_KV_CACHE_TYPE=q8_0/OLLAMA_KV_CACHE_TYPE=f16/' "$OVERRIDE"
sed -i 's/OLLAMA_MAX_LOADED_MODELS=2/OLLAMA_MAX_LOADED_MODELS=1/' "$OVERRIDE"

echo "==> new config"
grep -E "KV_CACHE|MAX_LOADED|FLASH" "$OVERRIDE"

systemctl daemon-reload
systemctl restart ollama
sleep 8
systemctl is-active ollama && echo "==> ollama restarted"

echo
echo "Revert with:"
echo "  sudo cp -a $BACKUP $OVERRIDE && sudo systemctl daemon-reload && sudo systemctl restart ollama"
