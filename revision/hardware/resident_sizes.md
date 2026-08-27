# Measured resident size (`ollama ps`) on the Jetson AGX Orin 64 GB

Engine: ollama 0.32.5, `OLLAMA_FLASH_ATTENTION=false`, `OLLAMA_KV_CACHE_TYPE=f16`,
`OLLAMA_MAX_LOADED_MODELS=1`, `OLLAMA_NUM_PARALLEL=1`. Residency is the `SIZE`
column of `ollama ps` with the model resident at 100% GPU, i.e. weights plus the
key-value cache allocated for the pinned context, plus graph buffers.

| model | quantisation | pinned `num_ctx` | resident | source |
|---|---|---|---|---|
| `qwen3.6:35b-a3b` | q4_K_M | 16,384 | 23.9 GB | `revision/galaxy_demo/METHODS.md` |
| `qwen3.6:35b-a3b` | q4_K_M | 65,536 | 31 GB | `ollama ps`, 2026-08-26 |
| `qwen3.8:27b` | q4_K_M | 65,536 | 19.6 GB | `revision/galaxy_demo/METHODS.md` |
| `qwen3.6:27b` | q4_K_M | 16,384 | ~17 GB | this study's hardware notes |
| `gemma4:12b` | q4_K_M | 16,384 | 7.6 GB | this study's hardware notes |

Not measured: the remaining ten benchmark-1 models (twelve in the benchmark-1
set, of which `qwen3.6:27b` and `qwen3.6:35b-a3b` were measured; `qwen3.8:27b` is
the out-of-sample addition and `gemma4:12b` was used for throughput only). Filling the column requires
loading each model in turn on the board, which evicts whatever model server is
resident and costs roughly six minutes of cold load per model; it was not done.
On-disk weight size for every model is in `ollama list` output and the declared
parameter count and context length for every model are in
`revision/repro_metadata.json`.
