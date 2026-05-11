# LLM-eval-paper

Source repository for the manuscript **"Open-weight LLMs as bioinformatics implementers: per-sample mtDNA variant calling on commodity hardware"**.

Manuscript: [`writeup/writeup.md`](writeup/writeup.md) · PDF: [`writeup/writeup.pdf`](writeup/writeup.pdf)

## What this repository contains

The manuscript tests whether a recipe authored once by a frontier LLM (`claude-opus-4-7`) can be executed end-to-end by a free, locally-runnable open-weight implementer (`qwen3.6:27b`) at frontier accuracy, on commodity lab hardware. The task is per-sample mtDNA variant calling on four paired-end Illumina samples; the implementer writes `run.sh` from the supplied recipe, the harness executes it, and a single variant-overlap (Jaccard) score grades the output against a hand-written canonical workflow.

| Directory | Purpose |
|---|---|
| `writeup/` | Manuscript source (`writeup.md`), PDF, build Makefile, and the cited literature PDFs (`papers/`). |
| `plan/` | The seven Opus-authored plans referenced in Table 4 and reproduced in the Supplement. |
| `prompts/` | Prompt templates (Track A, Track B, v0.5 tool-order condition). |
| `data/` | The four paired-end FASTQ samples and the chrM reference. |
| `ground_truth/` | Hand-written canonical workflow plus its reference VCFs. |
| `harness/` | Orchestration code for the runs, including the PATH-shim error-injection harness. |
| `score/` | Per-run scoring code (`score_run.py`) and the aggregator (`aggregate.py`). |
| `scripts/` | Figure-generation script (`make_figures.py`) for the manuscript figures. |
| `figures/` | The three figure PNGs embedded in the manuscript. |
| `runs_5080_v2/` | Per-run artifacts for the v2 plan on RTX 5080 — used by the scoring aggregator and figure generator. |
| `results.csv` | Aggregate score table over the plan-gradient sweep on RTX 5080. |
| `error_matrix_*.jsonl` | Per-cell summary logs from the error-injection matrix on Jetson, M4 Pro, and 2× A5000. |

## Reproducing the figures

```bash
# Variant-overlap score heatmap (Fig. 2 of the manuscript)
# and qwen3.6:27b vs claude-opus-4-7 error-injection panel (Fig. 3)
python3 scripts/make_figures.py --manuscript
```

The script reads `results.csv` and the `error_matrix_*.jsonl` files; per-run directories under `runs_5080_v2/` are used where present and JSONL summaries fill in the rest.

## Building the PDF

```bash
cd writeup && make
```

Requires `pandoc`, `pdflatex` (with `texlive-latex-extra` for `newunicodechar`), Python 3, and `npx` (only on first build, to render the Mermaid workflow diagram in Methods).

## Re-running the experiment on a new model

When a new open-weight model is released, the existing harness can score it against the same plan gradient and error-injection matrix without code changes. The scoring metric, ground-truth VCFs, plans, and prompt templates are all data; the harness is generic over the implementer.

### One-time setup

```bash
# 1. Install the conda environment that pins bwa, samtools, lofreq, bcftools,
#    bgzip, tabix to the same versions used in the manuscript.
bash setup/install.sh

# 2. Fetch the four mtDNA samples + chrM reference (Zenodo 5119008).
bash setup/fetch_data.sh

# 3. Verify the conda environment is sane and the tool inventory is what
#    the harness expects.
bash setup/verify_env.sh

# 4. Local LLMs run via Ollama; install it once
#    (https://ollama.com/download) and confirm `ollama list` works.
```

### Score a single new model

The minimum reproducible unit is one (model, plan, seed) cell. To score a new model on the v2 plan with three seeds:

```bash
for seed in 42 43 44; do
    python3 harness/run_one.py \
        --model NEW_MODEL_TAG \
        --track A \
        --seed $seed
done
# Each cell writes to runs/<run_id>/{exec.json, meta.json, raw_response.txt,
# run.sh, usage.json}; nothing is scored yet.

# Score every run dir under runs/
for d in runs/NEW_MODEL_TAG_*; do
    python3 score/score_run.py --run "$d"
done

# Re-aggregate into the headline CSV. The aggregator picks up every scored
# run dir under runs/ and runs_*/ and folds them into results.csv.
python3 score/aggregate.py
```

`NEW_MODEL_TAG` is whatever Ollama identifier the model ships under (e.g. `qwen3.7:30b`, `llama4:scout`, `gemma5:32b`). For Anthropic API models, use the public model identifier (e.g. `claude-opus-4-8`); the harness auto-detects the provider.

### Score a new model across the full plan gradient

To reproduce the manuscript's main figure on a new model, sweep all seven plans (no-plan + v0.5 + v1 + v1g + v1.25 + v1.5 + v2):

```bash
for plan in track_b v0p5 v1 v1g v1p25 v1p5 v2; do
    for seed in 42 43 44; do
        python3 harness/run_one.py \
            --model NEW_MODEL_TAG \
            --track A \
            --plan $plan \
            --seed $seed
    done
done
```

(For Track B / v0.5, the `--track B` flag substitutes the no-plan prompt template from `prompts/`.)

### Score a new model on the error-injection matrix

```bash
python3 harness/error_matrix.py \
    --model NEW_MODEL_TAG \
    --plan v2_defensive \
    --seeds 42 43 44
# Writes one cell per (pattern × tool × seed); appends to
# error_matrix_<provider>.jsonl at the repo root.
```

### Regenerate manuscript figures

```bash
python3 scripts/make_figures.py --manuscript
# -> figures/ms_fig2_5080_gradient.png  (heatmap)
# -> figures/ms_fig4_qwen3p6_27b_error.png  (error-handling matrix)
```

To add the new model to a manuscript figure, edit `LINEUP_5080` (Fig. 2) or the model filter in `fig_qwen3p6_27b_error_per_platform()` (Fig. 3) inside `scripts/make_figures.py`.

### Hardware notes

The sweep is set up for a single-GPU desktop with `ollama serve` running locally. For multi-GPU machines (A5000 etc.), set `CUDA_VISIBLE_DEVICES` and Ollama's `OLLAMA_SCHED_SPREAD=1` per the [Ollama docs](https://github.com/ollama/ollama/blob/main/docs/faq.md#how-can-i-use-ollama-with-multiple-gpus). For Apple Silicon, `setup/RUN_ON_MACOS.md` documents the path used in the manuscript's MacBook Pro M4 Pro runs. Models that exceed VRAM at 4-bit (the manuscript's qwen3.6:27b on the 16 GB RTX 5080 at ~17 GB) fall back to system RAM through Ollama; expect a 5–10× wall-time penalty.

## License

MIT (see `LICENSE`).
