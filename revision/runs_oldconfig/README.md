# Runs discarded from the analysis — superseded by a configuration change

400 local-model runs produced 2026-08-04/05 under:

    OLLAMA_FLASH_ATTENTION=true
    OLLAMA_KV_CACHE_TYPE=q8_0
    OLLAMA_MAX_LOADED_MODELS=2

Superseded because that configuration was changed mid-matrix while chasing
CUDA "illegal memory access" faults. The final configuration is:

    OLLAMA_FLASH_ATTENTION=false     <- the fault; flash-attention kernels on
                                        an sm_87 build ollama could not verify
    OLLAMA_KV_CACHE_TYPE=f16         <- q8_0 is lossy and alters model output
    OLLAMA_MAX_LOADED_MODELS=1       <- identical conditions for every model

Kept, not deleted, for two reasons: the q8_0-vs-f16 pair is a ready-made
ablation on whether KV-cache quantization changes benchmark outcomes, and the
fault pattern itself documents which model architectures are unstable on
JetPack 5 (laguna-xs-2.1, qwen3.6:35b-a3b, qwen3.5:4b, gpt-oss:20b,
glm-4.7-flash faulted; gemma4, nemotron-3-nano, qwen3.6:27b did not).

Logs: revision/logs/oldconfig/
