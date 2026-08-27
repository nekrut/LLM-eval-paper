# Two experiments run 2026-08-26/27, after review cycle 2

Both address blocking findings from the adversarial review. Both are complete.
All numbers below were computed from the run logs named here. This file is
authoritative over any earlier estimate.

## 1. Seed extension (R2.24, R3.8)

Raised v1g, v1.25 and v1.5 from 3 to 10 seeds per model. 273 new cells.
Local models only, think off, Track A. Log: `revision/logs/matrix_jetson_seedext.jsonl`,
pooled with `matrix_jetson_thinkoff.jsonl`.

| plan | perfect runs | rate | 95% Wilson |
|---|---|---|---|
| v1g   | 31/126  | 0.246 | [0.179, 0.328] |
| v1.25 | 63/127  | 0.496 | [0.411, 0.582] |
| v1.5  | 109/127 | 0.858 | [0.787, 0.908] |

- v1.25 vs v1g: Fisher exact p = 0.00005. Resolved. At n=3 this was p = 0.21.
- v1.25 vs v1.5: p = 7.1e-10.

The copy-pasteability contrast is now a measured result. v1g carries the same
`lofreq call-parallel` invocation as v1.25, plus the one detail models most
often get wrong. Its command block cannot be pasted and run. It scores half of
v1.25. The abstract may now state this contrast.

## 2. Perturbed plan (R2.1 — the tautology objection)

Design: plan v2 verbatim. The sandbox holds the same reads, but the reference
sits at `data/ref/GRCh38_chrM/rCRS.fa`. The plan's literal path
`data/ref/chrM.fa` does not exist. The prompt's DATASET section states the real
path. A script that copies the plan's command lines fails. A script that binds
the plan to the stated inputs succeeds. Sandbox validated with a hand-written
copier (fails) and binder (works) before any model ran.

13 local models x 3 seeds = 39 cells, think off. Control: published v2, 34/36
perfect. Log: `revision/logs/matrix_jetson_perturbed.jsonl`; runs under
`revision/runs_perturbed/`.

**Result: 6/39 perfect. The outcome is bimodal by model. Every model is 3/3 or 0/3.**

| outcome | models |
|---|---|
| bound (3/3 perfect) | gemma4:31b, gpt-oss:20b |
| copied (0/3) | qwen3.6:27b, qwen3.8:27b, qwen3.6:35b-a3b, gemma4:26b-a4b, glm-4.7-flash, granite4.1:30b, granite4.1:8b, laguna-xs-2.1, nemotron-3-nano:30b-a3b, nemotron-3-nano:4b, qwen3.5:4b |

Verified from the scripts, not the scores: both survivors wrote
`data/ref/GRCh38_chrM/rCRS.fa`; all eleven failures wrote the plan's
`data/ref/chrM.fa` verbatim, several deriving index names `chrM.fa.fa` from it.
Failures die at the first step: `bwa_idx_build fail to open file`.

### What this does to the central claim

1. **For 11 of 13 local models, v2 success is transcription.** They copy the
   plan's command lines without reconciling them against the stated inputs.
   One path mismatch, stated in the prompt, sends 34/36 to 0.
2. **Binding exists in this model class but is rare.** Two models adjusted
   every path and produced the correct call set. Binding is therefore
   demonstrable, not hypothetical — but it is a property of 2 of 13 models,
   not of the class.
3. **The paper's original headline model, qwen3.6:27b, transcribes.** The
   model that binds, gpt-oss:20b, was the weakest on the unperturbed gradient
   (0.67 at v2, budget-limited). Gradient rank does not predict binding.
4. R2's objection is confirmed for most models and the confirmation is now a
   measurement. The claim that survives: a detailed plan makes most local
   models work only when its literal paths match the data. Robust execution
   under a stale plan requires either a binding-capable model or an exact plan.
5. No frontier control was run (no API spend authorized). Whether frontier
   models bind under the same perturbation is unknown.

### Required manuscript changes
- Abstract: replace "needed literal command lines" framing with the two-part
  result: literal lines are necessary for most local models AND most local
  models use them by transcription, shown by the perturbation.
- Title: must not say or imply binding for the class. "In a single pass" stays.
- Results: new subsection "A one-path perturbation separates transcription
  from binding" with the table above.
- Discussion: plan sufficiency for most local models means literal-and-current;
  a stale detailed plan is worse than a lean one for a transcriber because it
  fails silently at the first path.
- Limitations: n=3 per model in the perturbed condition; single perturbation
  type (path move); no frontier arm.
