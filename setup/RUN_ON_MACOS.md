# Running LLM-eval-paper on a MacBook Air M4 (24 GB)

This file is a self-contained recipe for an agent (or a person) starting fresh on a MacBook Air M4 with 24 GB unified RAM. Two scoped recipes are provided: a **quick single-model check** for `qwen3.6:27b` (the manuscript's protagonist), and the **full overnight error-handling matrix** that adds Apple silicon as a third hardware platform.

## Quick single-model check — `qwen3.6:27b` on v2 (≤ 30 min wall time if it fits)

The MacBook Air M4 has 24 GB unified RAM. `qwen3.6:27b` at 4-bit quantization needs ~17 GB resident, leaving ~6–7 GB for macOS — which is the tightest configuration the manuscript reports. The MacBook Pro M4 Pro (48 GB) ran each generation in ~92 s; the Air may sit a few times slower or, in the worst case, OOM. Use this decision tree:

1. **One-time setup.** Run *Prerequisites* and *Setup the repo* (below). Then `ollama pull qwen3.6:27b` — about 17 GB on disk; takes 5–10 min on a fast connection.
2. **Close other apps.** Quit Chrome/Slack/Spotify/Photos and anything else with high "Memory" pressure in Activity Monitor before starting. Aim for the *Memory Pressure* graph to be solid green.
3. **Run three seeds, one at a time, foreground:**

    ```bash
    for seed in 42 43 44; do
        time python3 harness/run_one.py \
            --model qwen3.6:27b --track A --think off --seed $seed
    done
    python3 score/aggregate.py
    ```

    Watch Activity Monitor's *Memory Pressure* graph and the *Swap Used* number. Healthy: pressure stays green/yellow, swap < 2 GB.

4. **Decision tree on the first generation:**

    | Symptom | Diagnosis | Action |
    |---|---|---|
    | First generation completes in < 10 min, M3 = 1.000 | Model fits in unified memory; the Air is just slower than the Pro M4. | Continue with seeds 43 + 44. Report the per-seed wall time. |
    | First generation completes but takes 10–60 min and Memory Pressure stays red | Ollama is spilling to swap; the model technically fits but constantly pages. | Continue if you have time; expect 5–10× the M4 Pro's wall time per seed. The result is still a valid finding ("qwen3.6:27b runs on a 24 GB Air at the cost of constant paging"). |
    | First generation hangs > 90 min with no progress in `runs/qwen3.6_27b_*/raw_response.txt` | Likely live-locked on swap. | `kill` the run and the `ollama runner` process. Free more memory, retry once. If it hangs again, fall back to a smaller model (next row). |
    | Run dies with an Ollama error like "model requires more system memory than is available" or kernel OOM kills `ollama runner` | The model does not fit. | Fall back to one of: `qwen3:14b` (~9 GB, dense, fits comfortably), `qwen3.6:35b-a3b` (~6 GB active per token from a 23 GB MoE — fits if Ollama only resident-pins active experts; borderline on 24 GB), or `granite4` (~2 GB, fastest, but defensive-scripting floor — won't pass v1 on its own per Results 2 of the manuscript). Re-run the same loop with `--model <fallback>`. |

5. **Report back.** For whichever model ran end-to-end, note (a) per-seed mean variant-overlap score (target = 1.000 on the v2 plan), (b) per-seed wall_seconds_generation from `meta.json`, (c) peak Memory Pressure / swap usage during the run, (d) which model you ended up using if you fell back from `qwen3.6:27b`.

The manuscript's headline finding is that `qwen3.6:27b` reproduces frontier accuracy on every platform tested. If it OOMs on the 24 GB Air but `qwen3:14b` reaches the same M3 = 1.000, that is itself a useful data point — `qwen3:14b` becomes the implementer of choice for the 24 GB tier.

---

## Full error-handling matrix (overnight)

The experiment matrix is 5 models × 7 injection patterns × 1–2 target tools × 2 recipe variants × 3 seeds = ≈ 390 cells per model class. We'll run 3 Anthropic models + 4 fitting open-weight models, in parallel, overnight.

## Prerequisites (one-time, ~10 min)

```bash
xcode-select --install                                # if not already installed
brew install git curl ollama
npm install -g @anthropic-ai/claude-code              # the `claude` CLI used by the harness
```

After install: run `ollama serve &` (or trust that brew installed it as a launchd service — `ollama list` should return without error). Then `claude` once interactively to log in.

Verify:

```bash
git --version
curl --version | head -1
ollama --version
claude --version
```

All four should print versions. If `claude` errors with "not authenticated", run plain `claude` to start the login flow.

## Setup the repo (~5 min)

```bash
git clone https://github.com/nekrut/LLM-eval-paper && cd LLM-eval-paper
bash setup/install.sh                       # detects Darwin + arm64, pulls Miniforge3-MacOSX-arm64.sh, creates the bench env
bash setup/fetch_data.sh                    # 9 files, ~838 KB
bash ground_truth/canonical.sh              # produces ground_truth/results/
```

`install.sh` was patched to detect Darwin in commit `cb03333`. The conda env `bench` includes bwa 0.7.18, samtools 1.21, bcftools 1.21, lofreq 2.1.5, all native arm64 builds from bioconda. The fetch and ground-truth steps are platform-agnostic.

After ground truth: `ls ground_truth/results/` should show four `.vcf.gz` files plus their `.tbi` indexes.

## Pull ollama models (~15–25 min, ~70 GB disk)

24 GB unified RAM has to hold macOS, Ollama's runtime, and the model. macOS background processes occupy roughly 5–6 GB resident; that leaves ~18–19 GB for the model itself. Five models, ordered by priority:

```bash
ollama pull qwen3.6:27b            # 17 GB — the only local model that solved v1 (lean) at M3=1.000 in §2.1
ollama pull granite4               # 2.1 GB — fastest passer; defensive-scripting floor
ollama pull qwen3:14b              # 9 GB — clean dense fit
ollama pull qwen3-coder:30b        # 18 GB — borderline; partial-offload territory
ollama pull qwen3.6:35b-a3b        # 23 GB — MoE; the data point unique to unified memory
```

Why `qwen3.6:27b` is first: §2.1 of the README found that on the RTX 5080, only this dense model reached v2 levels on the v1 (lean) recipe — every other tested open-weight model scored M3 ∈ {0, 0.33} on v1. Confirming that result on M4 makes §2.1 a three-platform finding. It also fits more comfortably in 24 GB than the 18 GB or 23 GB cases below it.

The 23 GB MoE (`qwen3.6:35b-a3b`) is the borderline case. If macOS swaps so badly that cells time out at 900 s, run `ollama rm qwen3.6:35b-a3b` and exclude it from the ollama matrix below — its absence is a finding too. Don't pull anything 30 GB+ dense.

## Sanity check (~2 min)

Before the long run, confirm the harness end-to-end:

```bash
mkdir -p runs_smoke_m4
python3 harness/run_one.py \
    --model granite4 --track A --seed 42 \
    --plan plan/PLAN.md \
    --runs-dir runs_smoke_m4 \
    --think off
python3 score/score_run.py runs_smoke_m4/granite4* | head -20
```

Expect `M1=1, M3=1.0`. The cell wall should be ~15–30 s.

If `M3=0.0`, check:

1. `runs_smoke_m4/granite4*/exec.log` — most likely error is conda env activation (`source $HOME/miniforge3/etc/profile.d/conda.sh && conda activate bench`). Run that command directly and see what it says.
2. `ground_truth/results/` exists and has VCFs.
3. `runs_smoke_m4/granite4*/results/` has the model's output VCFs.

If the harness errors with a path it can't find under `/home/anton/...`, that's a regression of commit `cb03333`. Re-pull main.

## Run the matrix (~6–10 h overnight)

Two parallel background processes, one Anthropic, one Ollama. The Anthropic side hits the API and won't compete for compute; the ollama side saturates the GPU.

```bash
nohup python3 -u harness/error_matrix.py \
    --models claude-opus-4-7 claude-sonnet-4-6 claude-haiku-4-5 \
    --plans v2 v2_defensive --include-baseline \
    --log error_matrix_anthropic_m4.jsonl \
    > /tmp/error_matrix_anthropic_m4.log 2>&1 &
echo "anthropic pid: $!"

nohup python3 -u harness/error_matrix.py \
    --models qwen3.6:27b granite4 qwen3:14b qwen3-coder:30b qwen3.6:35b-a3b \
    --plans v2 v2_defensive --include-baseline \
    --log error_matrix_ollama_m4.jsonl \
    > /tmp/error_matrix_ollama_m4.log 2>&1 &
echo "ollama pid: $!"
```

Cell count: 234 (Anthropic) + 390 (5 ollama models × 78 cells) = ~624. Estimated wall: ~8–12 h.

If the 35b-a3b MoE doesn't fit, drop it from the `--models` list — the matrix becomes 312 ollama cells and the wall drops to ~6–10 h.

Watch progress:

```bash
wc -l error_matrix_anthropic_m4.jsonl error_matrix_ollama_m4.jsonl
tail -5 /tmp/error_matrix_*_m4.log
```

Spot-check a cell that finished:

```bash
python3 -c "
import json
r = [json.loads(l) for l in open('error_matrix_anthropic_m4.jsonl')]
print(f'{len(r)} cells; last 5:')
for x in r[-5:]:
    print(f'  {x[\"cell\"]:<70} {x.get(\"m_handle\",\"-\"):<10} M3={x.get(\"M3\",\"-\")}')
"
```

The Anthropic spend will be roughly the same as on the Jetson run (~$15 across the 234 Anthropic cells with prompt caching).

## When it's done — push results back

```bash
git checkout -b m4-results
git add error_matrix_anthropic_m4.jsonl error_matrix_ollama_m4.jsonl
# Don't add runs_inject/ — large and gitignored. The jsonl logs have everything needed.
git status --short
git commit -m "M4 error-handling matrix: $(wc -l < error_matrix_anthropic_m4.jsonl) Anthropic + $(wc -l < error_matrix_ollama_m4.jsonl) Ollama cells"
git push -u origin m4-results
```

After push, the original author can pull the results from another machine, regenerate Figure 6 with the third platform stacked in, and update `README.md` §2.6.

## Things that might trip you up

1. **`claude` not authenticated.** Run `claude` once interactively. The harness inherits the login.
2. **macOS bash 3.2 vs the model's bash 5.** `/bin/bash` is bash 3.2 on macOS; the harness wraps with `bash -c "source ... && conda activate bench && bash run.sh"`. The outer bash 3.2 handles only `source` and `&&` (both work). The model's `run.sh` runs inside conda's bash 5 (`$HOME/miniforge3/envs/bench/bin/bash`). So 5-only features in the model's script are fine.
3. **Disk pressure.** ~52 GB ollama blobs + ~3 GB conda env + ~5 GB run artifacts. Free ≥ 70 GB before starting.
4. **Memory pressure on `qwen3.6:35b-a3b`.** macOS will swap aggressively to disk. If cells time out at 900 s, drop the model.
5. **Ollama on macOS uses Metal/MPS, not CUDA.** Same HTTP API, same model tags — the harness sees no difference.
6. **Activity Monitor.** `WindowServer` and other macOS background processes will show ~3–5 GB resident; account for that when picking models.

## What the existing repo has (for context)

- `README.md` — full paper, includes §2.6 which is the experiment we're replicating
- `harness/error_matrix.py` — the driver
- `harness/error_shims/shim.py` — the PATH shim that injects failures
- `score/score_run.py` — computes M1/M2/M3/M5 plus the error-handling triple `m_handle`/`m_recover`/`m_diagnose`
- `plan/PLAN.md` — the v2 happy-path recipe
- `plan/PLAN_v2_defensive.md` — the v2_defensive recipe (Opus-authored)
- `error_matrix_anthropic.jsonl` / `error_matrix_ollama.jsonl` — the existing Jetson results, for cross-reference

The Jetson + RTX 5080 numbers are already in the repo. The M4 run adds a third hardware column to the existing tables and Figure 6.
