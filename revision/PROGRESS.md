# Revision progress

Running log for GENOME/2026/282393. **Nothing is committed.** Review the diff
before committing anything.

## Read this first

**Diff is small and contained** — 105 insertions across 4 tracked files, plus a
new `revision/` directory:

| File | Change |
|---|---|
| `harness/run_one.py` | +92 lines: classify generation outcomes; catch provider faults |
| `writeup/writeup.md` | Table 6 dispersion figures; seed/determinism paragraph |
| `writeup/writeup_GR.md` | the same, plus figure renumbering (1/2/3) |
| `writeup/Makefile` | mermaid regex generalized (backup: `Makefile.bak`) |

`run_one.py`'s CLI is unchanged, so `harness/matrix_5080.py` and
`sweep_local.py` still work.

**Three decisions are waiting for you** (details in the sections below):
1. Rebuild `writeup_GR.pdf` where pandoc exists and confirm figures print 1/2/3.
   I verified the source logic but this box has no LaTeX.
2. `top_k`/`top_p` are **not uniform** across models. Pin them and re-run
   (~20 h), or report the per-model defaults as-is. Both defensible.
3. The cost argument does not hold at this task size (break-even 76,424 runs).
   Reframing the abstract is your call; I did not touch it.

**Three findings cut against the current manuscript.** None is fatal, and two
turn into arguments for the extension the reviewers asked for:
- Cost: "per-call inference cost is the bottleneck" is false at $0.066/call.
- Error handling: real recovery rate is 12%, not the 42% a pooled reading gives.
- Metrics: precision and AF-error are degenerate *by construction*, so adding
  them satisfies R3.4 without adding information — which is itself the argument
  for R3.3's richer benchmark.

**Two near-misses worth knowing about**, both caught before they reached you:
- A convincing but false table showing "the most detailed plan performs worst"
  (caused by pooling Track-B no-plan runs into the v1/v2 columns).
- A wrong CUDA diagnosis: I attributed the faults to generation length on the
  strength of a Granite result that was actually a different bug entirely.

**Reproduce any number here** with the scripts in `revision/scripts/`; each
carries a docstring explaining what it does and the traps it avoids.

Last updated: 2026-08-05 (Wed), autonomous session.

---

## Reviewer response plan

`writeup/revision_plan.md` — all 31 reviewer points sorted into consensus items,
Tier 0 (factual defects), Tier 1 (writing), Tier 2 (re-analysis), Tier 3 (new
experiments), plus points worth pushing back on.

---

## Done

### Table 6 corrected — three of five dispersion figures were wrong (Tier 0, R3.12)

Reviewer 3 caught that the 2× A5000 median (29 s) sat outside its stated IQR
[3–10]. Recomputing every row from the archived per-run data found two further
errors. **All five medians were correct**; only the dispersion figures were
mis-entered, so the table's conclusions are unaffected.

| Platform | n | Median | Was | Now |
|---|---|---|---|---|
| 2× RTX A5000 | 36 | 29 | [3–10] | **[24–31]** |
| MacBook Pro M4 Pro | 36 | 92 | [91–136] | **[91–108]** |
| Jetson AGX Orin | 36 | 105 | [98–107] | [98–107] (correct) |
| RTX 5080 | 6 | 302 | [288–322] | **[219–405]** |
| MacBook Air M4 | 3 | 518 | [276–4,345] | [276–4,345] (correct, full range) |

Applied to `writeup/writeup.md` and `writeup/writeup_GR.md`, with the caption
now stating the quartile method and pointing at the generator.

Table 6 had no generator — it was hand-entered, which is why the errors were
possible. `revision/scripts/table6.py` now derives it from source and
**asserts the median lies within its IQR**, so this class of error cannot
recur silently. No hardware needed: all timings are archived.

Two source conventions worth knowing (both preserved from the original
analysis; the Jetson and M4 Air rows reproduce exactly under them, which is
what pins them down):
- `error_matrix_*.jsonl` carry `wall_s`
- `quick_check_*.jsonl` and `runs_*/meta.json` carry `wall_seconds_generation`
- **`error_matrix_ollama_m4.jsonl` is a trap** — reduced schema, `wall_s` there
  is ~2 s and means something else entirely. The M4 Pro row comes from
  `error_matrix_ollama_m4_r2.jsonl`. Anyone regenerating from the
  obvious-looking filename gets nonsense. Belongs in the reproducibility notes.

### Harness: generation outcomes are now classified (Tier 0, methods)

`harness/run_one.py` previously read only `message.content` and had no error
handling on the provider call. Both produced silent, wrong results. It now
records five distinct outcomes in `meta.json`:

| status | meaning |
|---|---|
| `ok` | script produced |
| `truncated_in_thinking` | model still reasoning when it hit `num_predict` — a budget artifact, **not** a capability result |
| `truncated` | hit the ceiling with no reasoning captured |
| `empty_content` | genuine empty response |
| `provider_error` | infrastructure fault (HTTP 5xx, CUDA crash) |
| `refusal` | Claude-side policy decline |

Reasoning text is persisted to `raw_thinking.txt`; the Claude JSON envelope to
`provider_envelope.json`.

This is load-bearing, not cosmetic. ollama ≥0.32 splits reasoning into a
separate `thinking` field; the old code read only `content`, so any model that
spent its budget reasoning returned an empty script and scored as a total
failure. Caught in the wild twice — `gpt-oss:20b` produced 47,606 and 60,523
characters of reasoning **with `think: false`** and never reached the script.


### Figure numbering corrected — the bug is in the GR variant only (Tier 0, R3.14)

Reviewer 3 reported the plan-gradient heatmap labelled Figure 1 but cited as
Figure 2, etc. Checking the rendered PDFs: **`writeup.pdf` is correct**
(workflow=1, gradient=2, error=3, matching its prose). The defect is in
**`writeup_GR.pdf`** — the version actually submitted.

Cause: the GR layout puts Methods *after* Results, so the workflow figure moved
to the end with it, but the figure numbers did not follow. Pandoc numbers by
document position — which is also the journal convention, order of first
citation — so the renderer was right and the prose was stale:

| Rendered as | Prose called it | Now |
|---|---|---|
| Figure 1 = plan-gradient heatmap | Fig. 2 | **Fig. 1** |
| Figure 2 = error-injection panel | Fig. 3 | **Fig. 2** |
| Figure 3 = workflow DAG | Fig. 1 | **Fig. 3** |

Also fixed the underlying fragility: `writeup/Makefile` hard-coded
`**Figure 1.**` in the regex that swaps the mermaid block for the pre-rendered
PNG (4 occurrences). Renumbering the legend would have silently broken the
substitution and produced a figure with an empty caption. The regex now matches
`**Figure \d+.**`. Backup at `writeup/Makefile.bak`.

**Not yet verified in print** — this box has no pandoc/pdflatex, so the GR PDF
could not be rebuilt. Source-level consistency was confirmed by simulating the
build substitution and recomputing pandoc's positional numbering. **Rebuild
`writeup_GR.pdf` on a machine with the toolchain and eyeball it before
submitting.**


### Seed / determinism language corrected (Tier 0, C4 — R2.6 and R3.9)

Reviewer 3 guessed the mechanism exactly: "If the value is only being used as a
run identifier for the API models, it should not be described as controlling
reproducible sampling." Verified in `harness/run_one.py`:

- `call_ollama` passes `seed` with `temperature = 0.2` (`top_k`/`top_p` left at
  Ollama defaults) — **the seed is real** for the local models.
- `call_claude` builds its command line with no seed argument at all — **the
  seed is a bare run label** for the Claude rows.

The old text claimed "the same prompt-and-seed pair produces reproducible
output" for all models. Replaced with a per-provider account that also states
the sampling parameters (R3.16) and notes that batched GPU inference does not
guarantee bitwise-identical results even with a fixed seed.

Note this is a *partial* concession, and the response letter should say so.
R2.6 asserted flatly that "LLM determinism is not controlled by the random seed
number. It is controlled by sampling parameters such as temperature, top p, top
k." That is not quite right — given fixed decoding parameters the seed does
select the trajectory. The corrected text makes both points: sampling behaviour
is a property of the decoding parameters, and the seed selects a path through
the distribution they define. R3.9's narrower version of the criticism was
correct and is fully accepted.


### Reproducibility metadata collected (Tier 0, R3.16)

`revision/scripts/collect_repro_metadata.py` → `revision/repro_metadata.json`,
plus a markdown table for the supplement (`--markdown`). Captures per model:
exact tag, blob digest, architecture, parameter count, quantization format,
context length, declared capabilities, and default decoding parameters; plus
engine version, JetPack/CUDA/device, and the ollama environment settings.

**It surfaced a confound that is not currently reported: decoding parameters
are not uniform across the matrix.** The harness overrides only `temperature`
(0.2) and leaves `top_k`/`top_p` unset, so each model runs under *its own*
defaults, and those differ:

- `top_k`: 20 (Qwen family), 64 (Gemma 4 family), unset (others)
- `top_p`: 0.95 (Qwen, Gemma 4, GLM), 1 (Nemotron), unset (others)

So models are being compared under different sampling configurations. This
partially vindicates R2.6, which is worth conceding in the letter: the reviewer
asserted that determinism is governed by "sampling parameters such as
temperature, top p, top k" — the specific claim about seeds was imprecise, but
the underlying point that these parameters were unreported *and non-uniform*
was correct.

**DECISION NEEDED.** Two defensible readings, and this is the user's call:
- *Leave as is* — each model runs at its publisher's recommended defaults,
  which is how a practitioner would actually deploy it. Arguably the more
  realistic comparison. Costs nothing; must be reported explicitly.
- *Pin `top_k`/`top_p` uniformly and re-run* — isolates the model as the only
  variable. Costs another full matrix (~20 h+) and is arguably less realistic.

Not re-run autonomously: it would discard the matrix currently in flight for a
methodological preference the user has not expressed.


### Arm 1 complete — first full plan gradient on the Jetson (new result)

323/324 cells in 7.8 h, **zero CUDA faults**, one classified failure
(`gpt-oss:20b` reasoning overrun, see Findings). This gradient has never
existed for the Jetson: the published Jetson data is a single-column screen at
plan v2, and the 7-column gradient existed only for the RTX 5080.

M3 (variant-set agreement with truth), think-off, mean over seeds:

```
model                              B   v0.5     v1    v1g  v1.25   v1.5     v2
gemma4_26b-a4b-it-q4_K_M        0.00   0.00   0.00   0.00   0.67   0.67   1.00
gemma4_31b-it-q4_K_M            0.00   0.00   0.00   1.00   1.00   1.00   1.00
glm-4.7-flash_q4_K_M            0.00   0.00   0.67   0.00   0.33   1.00   1.00
gpt-oss_20b                     0.33   0.00   0.00   0.00   0.33   1.00   1.00
granite4.1_30b-q4_K_M           0.00   0.00   0.67   0.67   0.67   1.00   1.00
granite4.1_8b-q4_K_M            0.00   0.00   0.00   0.00   0.00   0.67   1.00
laguna-xs-2.1_q4_K_M            0.00   0.33   0.00   0.00   0.00   1.00   1.00
nemotron-3-nano_30b-a3b-q4_K_M  0.00   0.00   0.67   0.33   0.67   1.00   1.00
nemotron-3-nano_4b              0.00   0.00   0.00   0.00   0.00   0.67   0.33
qwen3.5_4b-q4_K_M               0.00   0.00   0.00   0.00   0.00   0.00   1.00
qwen3.6_27b-q4_K_M              0.33   0.00   1.00   1.00   0.33   1.00   1.00
qwen3.6_35b-a3b-q4_K_M          0.00   0.00   0.00   0.00   1.00   1.00   1.00
```

Reproduce: `python3 revision/scripts/gradient.py [--metric M1] [--ci]`.

Observations:
- **11 of 12 models reach 1.00 at v2.** Replicates and extends the published
  claim (five of six on the 5080) onto different hardware with a newer lineup.
  The lone failure is the smallest model, `nemotron-3-nano:4b` (0.33).
- **Without a plan, essentially nothing works.** B and v0.5 are ~0 across the
  board. This is the paper's central claim, now with 12 models behind it.
- **The cliff sits between v1.5 and v2 for most models** — later than for the
  frontier reference, which saturates at v1g. Small local models need more
  spelled out than Opus/Sonnet/Haiku do. That contrast is the real story and
  it needs both rows to tell.
- `qwen3.6:27b` succeeds earliest (1.00 at v1 and v1g), consistent with the
  published finding that it is the strongest implementer.
- Several non-monotonic cells (e.g. `qwen3.6:27b` 1.00 at v1g but 0.33 at
  v1.25) are n=3 noise — precisely R3.8's objection, and the argument for the
  n=10 headline pass.

### ANALYSIS TRAP — read before touching these logs

v1 and v2 run on **both** tracks, and every Track-B run is a *no-plan* run
regardless of which plan file was passed (the Track-B template does not
substitute `{PLAN}`). Aggregating naively by plan folds no-plan runs into the
v1 and v2 columns and halves them — producing the very convincing but entirely
false conclusion that *the most detailed plan performs worst*. I generated that
exact wrong table before checking against `scripts/make_figures.py::col()`.

`revision/scripts/gradient.py` implements the correct mapping and documents it.
Use it rather than re-deriving.

### Confidence intervals (Tier 2, R3.8)

`gradient.py --ci` defaults to **Clopper-Pearson (exact)** because that is the
method the reviewer used — 3/3 gives [29%, 100%], matching the figure quoted in
the review. Wilson is available (`--ci-method wilson`) and gives [44%, 100%].
Using the reviewer's own method keeps the response letter arithmetically
consistent with their number.

| n | perfect score | exact 95% CI | width |
|---|---|---|---|
| 3 | 3/3 | [29%, 100%] | 71 pts |
| 5 | 5/5 | [48%, 100%] | 52 pts |
| 10 | 10/10 | [69%, 100%] | 31 pts |

This is the table that justifies the n=10 headline pass, and it also shows what
n=10 does *not* buy: even a perfect 10/10 cell only rules out true success
rates below ~69%.


### Variant metrics computed — and they reveal what the benchmark actually measures (Tier 2, R3.4 + R2.11)

`revision/scripts/variant_metrics.py` separates detection from quantification,
which the tolerant Jaccard conflates. Over all 324 think-off runs:

```
pooled   TP=1042   FP=0   FN=1874
precision = 1.000   recall = 0.357   F1 = 0.527
AF error on true positives = 0.0000
runs with any AF beyond ±0.02: 0/324
```

**Zero false positives in 324 runs. Allele-frequency error identically zero.**

Verified, not assumed:
- Truth is 9 variants per run (2+2+2+3 across the four samples).
  324 x 9 = 2916 = TP+FN exactly, so the accounting closes.
- A successful run's variant output is **byte-identical** to ground truth
  (md5 of `CHROM/POS/REF/ALT/AF` matches for the samples checked).

**What this means — the important part.** The benchmark does not measure
variant-calling accuracy. LoFreq is deterministic: if the model wires the
pipeline correctly, the output is *exactly* the canonical result; if it does
not, there is no output at all. The per-sample outcome is therefore binary, and
every accuracy metric computed on top of it degenerates to the same underlying
quantity: **did the model orchestrate the pipeline correctly?**

This reframes both metric criticisms and cuts in two directions, which the
response letter should say plainly:

- **Defends against R2.11 and R3.4.** Jaccard is not degenerate because it was
  chosen badly; it is degenerate because the task is deterministic downstream
  of the model. Adding precision/recall/F1/AF-error is worth doing for
  transparency (done), but they carry no information Jaccard did not — precision
  is exactly 1.000 and AF error exactly 0.0000 by construction, not by luck.
- **Concedes R3.3.** Making those metrics informative requires a task whose
  *accuracy* can vary continuously — spike-ins across allele frequencies,
  variable depth, a caller with tunable sensitivity. That is precisely the
  additional benchmark R3.3 asked for, and this analysis is the concrete
  argument for why it is needed rather than optional.

It is also the sharpest answer yet to **R3.2** ("what does the LLM contribute?").
The variant caller does the science; the model wires it up. What is being
measured is orchestration, and now there is a number for it rather than an
assertion.

Suggested primary metric going forward: **per-sample orchestration success
rate** (fraction of the 4 samples that produced canonical output), which is
what M3 already computes but states honestly.

F1 by model x plan column is in the log; `--per-model` regenerates it.
Per-run detail: `revision/variant_metrics_thinkoff.json`.


### Cost model — the cost argument does not survive at this task size (Tier 1, R3.13)

`revision/scripts/cost_model.py` (parameterised; run it to vary assumptions).

Measured: API $0.0662/run over 81 runs; Jetson 86.7 s/run (324 cells in 7.8 h);
power mode MAXN. Assumed: board watts, tariff, hardware price, staff time.

```
API cost/run              $0.0662   (measured)
Local marginal cost/run   $0.00016  (electricity)
Hardware + labour, 3 yr   $5,045
BREAK-EVEN                76,424 runs  =  15.3 years at 5,000 runs/yr
```

Electricity is a rounding error — 20 W vs 60 W changes break-even by 0.2%.
**Labour dominates**: $1,200 setup + $600/yr is $3,000 of the $5,045. The 16 h
setup estimate is if anything generous given this week (crash-looping service,
JetPack-5 flash-attention CUDA bug, mid-matrix config change).

**This contradicts the abstract**, which states that per-call inference cost "is
the bottleneck". At $0.066/run it is not.

But the break-even is dominated by API cost per run, which scales with task size:

| API $/run | break-even | yrs @ 5k/yr | |
|---|---|---|---|
| $0.07 | 76,625 | 15.3 | this study's task |
| $0.25 | 20,192 | 4.0 | ~4x larger prompt/output |
| $1.00 | 5,046 | 1.0 | multi-step agentic loop |
| $5.00 | 1,009 | 0.2 | long-context repo-scale |

**Suggested reframing (USER DECISION — not applied).** The honest version is
stronger than the current one: local hardware does not pay for itself on a task
this small; it pays for itself on the larger, agentic workloads R2 and R3 both
said the paper should be testing. That turns a weakness into an argument for
the very extension the reviewers asked for. The non-monetary reasons — data
governance (R1.4), no per-call metering, no vendor dependency — stand
independently and should carry more of the weight.

I have not edited the abstract or Discussion: the framing is the author's call.

**Queued for the user (needs root):** the INA3221 rails are 0600, so board draw
is the documented AGX Orin envelope, not a measurement. To make it empirical,
under load run:  `sudo tegrastats --interval 1000 | head -60`
then re-run the model with `--watts <measured>`.


### Figure/analysis pipeline ready (supports priority 2)

`revision/scripts/export_results.py` writes the revision matrix into the
published `results.csv` schema, so `scripts/make_figures.py` and any reader's
existing analysis work unchanged instead of needing a parallel implementation.
Output: `revision/results_revision.csv` (425 rows, 424 scored).

`plan_version` is emitted as `rev_<arm>_<plan>` with **three** arms —
`api` (Anthropic), `off`, `on`. The api arm exists because Anthropic runs carry
no `think` value; labelling them "off" pooled them with local think-off runs
under one key, which is the silent pooling the naming scheme exists to prevent.
Caught on the first run and fixed.

`make_figures.py::PLAN_MAP` has no entries for `rev_*`, so revision rows cannot
be accidentally mixed into published figures — plotting them requires adding
entries deliberately.

Verified by round-trip: reconstructing the gradient from the CSV reproduces
`gradient.py`'s numbers cell-for-cell.

Two schema gotchas found and handled:
- `score.json` stores **internal** key names (`m1_executes`, `m3_jaccard`, ...);
  the short `M1`/`M3` labels exist only on `score_run.py`'s *stdout*. Reading
  the file for "M3" silently yields nothing — 425 rows, 0 scored.
- `cost_usd` lives inside the `m4` sub-object in `score.json`.

The CSV also carries a `generation_status` column that the published schema
lacks, so a plumbing failure (`truncated_in_thinking`, `provider_error`) can
never be mistaken downstream for a capability score of 0.


### Error suite recategorized — a third of it does not inject an error (Tier 2, R3.7)

R3.7: "a tool that sleeps and then succeeds is not necessarily an error, while a
tool producing extensive warnings but correct output is more a robustness or
logging test than a recovery test." Reading `harness/error_shims/shim.py`
confirms this exactly — both patterns **delegate to the real tool and succeed**:

| pattern | what the shim does | class |
|---|---|---|
| `flake_first_call` | exit 1 once, then succeeds | true error |
| `one_sample_fails` | exit 1 for one sample | true error |
| `missing_lib_error` | exit 127, hard failure | true error |
| `silent_truncation` | succeeds, output truncated | true error |
| `wrong_format_output` | succeeds, output mangled | true error |
| `slow_tool` | sleeps 30 s, **then succeeds** | NOT an error |
| `stderr_warning_storm` | 200 warnings, **then succeeds** | NOT an error |

8 true-error cells, 4 non-error cells: **33% of the injected matrix injects no
error.** Splitting qwen3.6:27b on the v2 plan:

```
true-error cells (n=24)   crash 15, propagate 6, recover 3   -> 12% recovered
non-error cells  (n=12)   recover 12                          -> 100% (trivially)
control          (n=3)    recover 3                           -> 100%
```

Pooled, that reads as 42% "recover". On cells where something actually went
wrong it is **12%**. The non-error cells score 100% because the tool succeeded —
they measure nothing.

**The paper's actual claim survives; its framing does not.** claude-opus-4-7 on
the same split gives an *identical* distribution — `{crash 15, propagate 6,
recover 3}`, 12% — so "qwen3.6:27b matches claude-opus-4-7 cell-for-cell" is
exactly right, and is if anything strengthened by holding on the harder subset.
What must change is any impression that the models handle injected failures
well: on real errors, both crash 62% of the time.

Recommended for the revision:
- Report the two classes separately; never pool them into one rate.
- Rename the non-error cells for what they test — latency tolerance and log-noise
  tolerance — and keep them, since both are legitimate robustness checks.
- The 12% recovery rate on genuine errors is a strong motivator for the
  bounded-repair arm (R3.1): these runs had no opportunity to retry.


### Arm 2 failure modes — three distinct classes, two of them harness limits

All three are `qwen3.5:4b` on Track-B (no-plan / lean) columns; no other model
has failed. 3/55 as of writing.

| class | done_reason | thinking | meaning |
|---|---|---|---|
| `truncated_in_thinking` (x2) | `length` | 61,000 / 56,890 chars | ran out of token budget mid-reasoning — a **budget artifact** |
| `empty_content` (x1) | **`stop`** | 45,328 chars | reasoned at length, stopped **voluntarily**, produced no script — a genuine **capability failure** |

The distinction matters and is the reason the classifier exists. The first two
must not be scored as capability results; the third must. `done_reason`
separates them, and `thinking_chars` in `meta.json` preserves the detail either
way, so the analysis can distinguish "gave up after reasoning" from "returned
nothing at all" without a code change mid-run.

Pattern: failures concentrate on one small model in the leanest columns, which
is the expected direction — less plan means more reasoning required. It also
means think-on no-plan cells partly measure token budget rather than
capability. State as a limitation; do not fix mid-matrix.

**Update (138/270): a third class appeared — generation timeout.**
`glm-4.7-flash` on v1g think-on hit the 2700 s `GEN_TIMEOUT_THINK` on two
seeds (both exactly 2702 s), recorded as `provider_error`. The model did not
fail; the harness stopped waiting. Whether it would have finished is unknown.

Running tally at 138/270: `truncated_in_thinking` 9, `provider_error` 3,
`empty_content` 1.

**Caveat for the think-on arm, to state in the methods.** Two of the three
classes are *harness* limits — the 16,384-token `num_predict` ceiling and the
2700 s wall-clock timeout — not model failures. About 9% of arm 2 cells are
bounded by the harness; arm 1 (think-off) had 0.3%. Reasoning is expensive on
constrained hardware, and the think-on arm therefore measures
"model + budget" rather than model capability alone.

Deliberately **not** raising the timeout mid-run: it would make cells
incomparable, the same error corrected yesterday over the KV-cache config.
If the arm is re-run, raise `GEN_TIMEOUT_THINK` and `num_predict` together
and re-run the whole arm, not a subset.


### BOTH ARMS COMPLETE — the reasoning/plan-detail tradeoff (headline result)

```
think-off:  324 cells,  1 failed (0.3%),   7.8 h
think-on:   270 cells, 18 failed (6.7%),  29.1 h
zero CUDA faults across 37 h
```

Restricted to the **10 models runnable in both arms** (Granite excluded — cannot
think), with truncations scored 0 rather than dropped (dropping them flatters
think-on; both framings give the same picture):

| plan column | think-off | think-on | delta |
|---|---|---|---|
| B (no plan) | 0.07 | 0.09 | +0.02 |
| v0.5 | 0.03 | 0.10 | +0.07 |
| **v1** | 0.23 | 0.40 | **+0.17** |
| v1g | 0.23 | 0.27 | +0.03 |
| **v1.25** | 0.43 | 0.67 | **+0.23** |
| v1.5 | 0.83 | 0.90 | +0.07 |
| **v2** | 0.93 | 0.73 | **-0.20** |

**Reasoning substitutes for plan detail in the middle of the gradient and
actively harms once the plan is nearly executable.** At v1/v1.25 it buys ~0.2;
at v2 it costs 0.2.

Not an outlier effect — at v2 Track A, **4 of 10 models regress, 0 improve,
6 unchanged**:

```
gemma4_26b-a4b      1.00 -> 0.67
glm-4.7-flash       1.00 -> 0.67
gpt-oss_20b         1.00 -> 0.67
qwen3.5_4b          1.00 -> 0.00
(others unchanged)
```

**Why this matters.** R2 and R3 both asked whether the model performs meaningful
orchestration or merely transcribes a specified workflow. The answer now has a
shape: there is a band where reasoning does real work, and past it more
reasoning is worse than none. "All you need is a plan" holds in a stronger and
more specific sense than originally claimed — a sufficiently detailed plan does
not merely make reasoning unnecessary, it makes reasoning counterproductive.

Reproduce: `python3 revision/scripts/gradient.py --arm on` (and `--arm off`).

Caveat to state: the think-on arm carries a 6.7% harness-bounded failure rate
(token budget, wall-clock timeout) against 0.3% for think-off, so it measures
"model + budget". The v2 regression is not a budget artifact — those cells
completed and scored.


### n=10 headline pass — R3.8 vindicated empirically, not just theoretically

83/84 cells, 1.9 h. v2 Track A think-off now at **n=10** (seeds 42-51).

| model | n=3 said | n=10 says | exact 95% CI at n=10 |
|---|---|---|---|
| 9 of 12 models | 1.00 | **1.00** (10/10) | [0.69, 1.00] |
| gpt-oss:20b | 1.00 | 0.90 (9/10) | [0.55, 1.00] |
| **qwen3.5:4b** | **1.00** | **0.70 (7/10)** | [0.35, 0.93] |
| nemotron-3-nano:4b | 0.33 | 0.10 (1/10) | [0.00, 0.45] |

Pooled: **107/120 perfect, 95% CI [0.82, 0.94]**.

**`qwen3.5:4b` scored a perfect 3/3 at n=3 and 7/10 at n=10.** At three seeds it
looked indistinguishable from a 27B model; at ten it is clearly not. This is
R3.8's objection demonstrated with data from this study rather than argued from
first principles — and it is the strongest possible support for the reviewer's
point, because it changes a claim the paper would otherwise have made.

Revised headline claim for v2:
- ~~"11 of 12 models reach 1.00"~~ (n=3)
- **"9 of 12 reach 10/10; gpt-oss 9/10; qwen3.5:4b 7/10; nemotron-3-nano:4b
  1/10"** (n=10)

Note the direction: every shift is *downward*. Small n did not add noise
symmetrically — it flattered the weakest models, because a model that succeeds
70% of the time has a 34% chance of going 3/3. Any benchmark reporting n=3
perfect scores is systematically overstating its weakest entries.

Reproduce: logs `matrix_jetson_thinkoff.jsonl` + `matrix_jetson_n10_v2.jsonl`.


---

## Findings that belong in the paper

1. **`think: false` is a request, not a guarantee.** `gpt-oss:20b` reasons
   anyway. The reasoning on/off axis is clean for most models, *unavailable*
   for both Granite models (ollama rejects the parameter outright — HTTP 400,
   "does not support thinking"), and *unreliable* for gpt-oss. Three states,
   not two.
2. **MoE beats dense on bandwidth-limited hardware, measured directly.**
   `gemma4:12b` (dense, 7.6 GB) → 14.4 tok/s; `qwen3.6:35b-a3b` (MoE, 23 GB,
   3 B active) → 30.7 tok/s. Three times larger, 2.1× faster. This is the
   MoE/KV-cache explanation R2 asked for, backed by own measurement.
3. **Opus 5 thinks by default**, unlike Opus 4.7 — so the Claude rows are not a
   like-for-like generational swap. Per-run cost and latency are now variable
   (35 s–124 s on identical prompts differing only by seed).
4. **Per-token price and per-task cost diverge.** Sonnet 5 cost more per run
   ($0.075) than Opus 5 ($0.057) despite being 2.5× cheaper per token — Opus
   needed fewer tokens. Worth a sentence in the cost section.
5. **Flash attention is unusable on this JetPack 5 build** (below). Five of
   twelve models faulted; seven were clean. That is a hardware-practical
   result of the kind R1 praised.

---

## Results in hand

**Claude reference gradient — complete.** 81/81 cells, 0 failures, 0 refusals,
1.9 h, **$5.36**. Models: `claude-opus-5`, `claude-sonnet-5`,
`claude-haiku-4-5` (Haiku 4.5 is still current — no Haiku 5 — so that row is
directly comparable to the published data).

M3 (variant-set agreement with truth):

**CORRECTED 2026-08-26.** The table below was produced by the naive
per-plan-file aggregation this project warns against: it does NOT collapse
Track B, so no-plan runs were folded into the v1 and v2 columns. The corrected
table, computed with `column(plan, track)` from `revision/scripts/gradient.py`,
is given second and is the one the manuscript uses.

WRONG (uncollapsed — do not reuse):
```
model                      B    v0.5      v1     v1g   v1.25    v1.5      v2
claude-opus-5           0.63    0.78    0.83    1.00    1.00    1.00    0.97
claude-sonnet-5         0.65    0.96    0.98    1.00    1.00    1.00    0.99
claude-haiku-4-5        1.00    0.67    0.97    1.00    1.00    1.00    0.83
```

CORRECT (Track B collapsed; B pools 9 cells per model, others 3):
```
model                      B    v0.5      v1     v1g   v1.25    v1.5      v2
claude-opus-5          0.743   0.778   1.000   1.000   1.000   1.000   1.000
claude-sonnet-5        0.861   0.959   1.000   1.000   1.000   1.000   1.000
claude-haiku-4-5       0.870   0.667   1.000   1.000   1.000   1.000   1.000
```

Two observations: the gradient **saturates at v1** — v1g, v1.25 and v1.5 buy
nothing for frontier models; and from v1 onward Haiku is indistinguishable
from Opus, which strengthens the cost argument. Two cells run backwards
(Haiku 1.00 at B but 0.67 at v0.5; Opus 0.97 at v2) — almost certainly n=3
noise, and prime candidates for the n=10 pass.

**Local matrix — in progress.** See below.

---

## Infrastructure: what changed and why

`ollama` 0.21.2 → **0.32.5** (JetPack 5 build; upstream still ships a
`jetpack5` variant, so **no reflash was required**). The service had been
crash-looping 2,832 times — `OLLAMA_MODELS` pointed at `/media/anton/ssd/...`
after the drive was remounted at `/media/anton/disk1`. Model stores merged;
12 models pulled.

### CUDA faults — root cause: flash attention

Symptom: `CUDA error: an illegal memory access was encountered`, 22 in six
hours, intermittent. ollama warns at startup that it **cannot verify its
compiled CUDA architectures for sm_87**; the flash-attention kernels for
certain attention variants are miscompiled.

Faulted: `laguna-xs-2.1`, `qwen3.6:35b-a3b`, `qwen3.5:4b`, `gpt-oss:20b`,
`glm-4.7-flash`. Clean: `gemma4` (both), `nemotron-3-nano` (both),
`qwen3.6:27b`, `granite4.1` (both). Neither size nor family predicts it.

Final config (`/etc/systemd/system/ollama.service.d/override.conf`):

```
OLLAMA_FLASH_ATTENTION=false   <- the actual fix
OLLAMA_KV_CACHE_TYPE=f16       <- was q8_0; lossy, and it alters model output
OLLAMA_MAX_LOADED_MODELS=1     <- identical conditions for every model
```

Backup of the previous config:
`/media/anton/disk1/ollama/dist/v0.32.5/override.conf.pre-cuda-fix`

**400 local runs were discarded** and archived to `revision/runs_oldconfig/`
(with README). They were produced under `q8_0` KV cache; everything since uses
`f16`, and quantized KV cache changes model output — mixing them would give a
matrix whose cells are not comparable, which is exactly what R3.16 asks you to
pin down. They remain useful as a KV-quantization ablation and as documentation
of which architectures are unstable on JetPack 5. The 81 Claude runs are
unaffected (API calls).

---

## Compute: all finished

| Pass | Cells | Wall | Failures | Log |
|---|---|---|---|---|
| Claude reference | 81 | 1.9 h | 0 | `logs/matrix_jetson_anthropic.jsonl` |
| Arm 1, think-off | 324 | 7.8 h | 1 | `logs/matrix_jetson_thinkoff.jsonl` |
| Arm 2, think-on | 270 | 29.1 h | 18 | `logs/matrix_jetson_thinkon.jsonl` |
| n=10 headline (v2 Track A, 7 extra seeds) | 83 | 1.9 h | 1 | `logs/matrix_jetson_n10_v2.jsonl` |
| qwen3.8 think-off | 27 | 0.7 h | 0 | `logs/matrix_jetson_qwen38_off.jsonl` |
| qwen3.8 think-on @16k | 27 | 17.4 h | **27 truncated** | `logs/matrix_jetson_qwen38_on.jsonl` |
| budget ablation @32k | 3 | 4.6 h | 3 truncated | `logs/ablation_32768.jsonl` |
| budget ablation @64k | 3 | 7.9 h | 0 (1/3 correct) | `logs/ablation_65536.jsonl` |
| *(discarded: attempt-1 timeout)* | 2 | 2.5 h | — | `runs_ablation_discarded/` |

Grand total this revision: **900 cells, ~93 h GPU.** The last 30 h bought one
defensible sentence about reasoning budgets and two retractions of my own
earlier claims.

Zero CUDA faults across ~41 h since `OLLAMA_FLASH_ATTENTION=false`. All cells
resumable (any cell with `score.json` is skipped), so `run_full_matrix.sh` can
be re-run at any time to fill gaps.

Matrix: 12 local models × **9 (plan file, track) cells** × 3 seeds = 324.
The 9 cells collapse to 7 plan columns (B, v0.5, v1, v1g, v1.25, v1.5, v2) at
analysis, because Track B occupies three of them (plan b; plan v1 Track B;
plan v2 Track B). CORRECTED 2026-08-26: this line previously read "12 × 7 × 3",
which is 252, not 324. **This gradient has never existed for the Jetson** — the published
Jetson data is a single-column screen at plan v2 only; the 7-column gradient
exists only for the RTX 5080. New work, not a reproduction.

---

## Figures — `revision/figures/`

Generated by `revision/scripts/make_revision_figures.py` (re-runnable; nothing
is hand-edited).

| File | What it shows |
|---|---|
| `rev_fig1_gradient_thinkoff.png` | Plan gradient, reasoning off, 12 models, n=3 |
| `rev_fig2_gradient_thinkon.png` | Plan gradient, reasoning on, 10 models, n=3 |
| `rev_fig3_reasoning_delta.png` | **on minus off** — the headline |
| `rev_fig4_n3_vs_n10.png` | What n=3 got wrong (answers R3.8 with data) |

Fig 1 reproduces the paper's central claim on 12 models it has never been
tested on: no plan → 0.00 almost everywhere, v1.5/v2 → 1.00 almost everywhere.

Fig 3 is the new result. Reasoning effect by plan column, over the 10 models
runnable in both arms:

```
B   +0.02   v0.5 +0.07   v1 +0.17   v1g +0.03   v1.25 +0.23   v1.5 +0.07   v2 -0.20
```
(CORRECTED 2026-08-26. This block previously read v1 +0.20 / v1g +0.10, which
conflicted with the table above it and reproduced under neither truncation
convention. Recomputed from `matrix_jetson_thinkon.jsonl` and
`matrix_jetson_thinkoff.jsonl` over the 10 both-arm models, scoring truncated
generations 0 and retaining them — the convention the manuscript states.
Dropping truncated cells instead gives +0.03 / +0.08 / +0.23 / +0.07 / +0.26 /
+0.07 / -0.20.)

Reasoning substitutes for plan detail in the middle of the gradient and
**hurts once the plan is already near-executable** — at v2, 4 of 10 models
regress and none improve. The mechanism is visible in the run artifacts:
think-on runs at v2 re-derive steps the plan already specifies, and the ones
that fail do so by exhausting the token budget mid-reasoning.

Fig 4 answers R3.8 empirically instead of with an interval. Pooling the
original 3 seeds with 7 new ones at v2 Track A think-off, **every model that
moved, moved down**:

```
qwen3.5:4b          1.00 -> 0.70
nemotron-3-nano:4b  0.33 -> 0.10
gpt-oss:20b         1.00 -> 0.90
(9 others unchanged at 1.00)     pooled 107/120 perfect, 95% CI [0.82, 0.94]
```

That asymmetry is the point: small *n* does not scatter evenly, it flatters
the weakest models. A model that succeeds 70% of the time goes 3/3 about a
third of the time; one that already scores 1.00 cannot go up. So n=3
systematically overstates exactly the entries a reader is most sceptical of.

**Two analysis traps that bit during this work — both now guarded in code:**
1. Every Track-B run is a no-plan run regardless of which plan file was passed.
   Aggregating by plan alone folds them into v1/v2 and makes the most detailed
   plan look worst. (`gradient.py`, `make_revision_figures.py::load`)
2. The extra-seed pass ran 7 **new** seeds, not a fresh 10. Plotting those 7
   alone understates every model the first 3 seeds got right. Now pooled, with
   an `assert` that each model has exactly 10.

---

## Addendum: qwen3.8:27b (added 2026-08-14, mid-revision)

Qwen3.8-27B went to open weights on 2026-08-14 15:00 UTC. Added because it
pairs exactly with `qwen3.6:27b-q4_K_M` already in the matrix — same parameter
count, same quantization, same inference engine, one generation apart. That is
a cleaner generational contrast than anything else in the paper.

**Model cutoff is 2026-08-14 and is stated in `matrix_jetson.py`.** This is one
model added because it landed during the revision, not a policy of tracking
releases. A reviewer can reasonably ask where the line is, so the line is
written down.

**Not run through vLLM, deliberately** — three reasons, in increasing order of
importance:
1. Impossible here: JetPack 5 (R35.4.1) means CUDA 11.4 and there is no torch
   installed. vLLM aarch64 needs CUDA 12.x / JetPack 6, and recent vLLM needs
   torch >= 2.4 against JetPack 5's ceiling of 2.2. That is a reflash.
2. Unnecessary: `config.json` reports `model_type: qwen3_5`, the architecture
   ollama 0.32.5 already runs. ggml-org's Q4_K_M loads directly.
3. **Would confound engine with model.** All 758 existing cells ran through one
   ollama config. A vLLM row differs in scheduler, attention kernel and sampler,
   so a score difference could not be attributed to the model. This is the
   reason that would still hold even if the first two were solved.

Provenance:
```
ollama pull hf.co/ggml-org/Qwen3.8-27B-GGUF:Q4_K_M   # ollama lowercases -> :q4_K_M
ollama cp   hf.co/ggml-org/Qwen3.8-27B-GGUF:q4_K_M qwen3.8:27b-q4_K_M
```

Capability probe (run before the matrix, because Granite silently 400s on
`think` and mistaking that for a capability result cost a wrong diagnosis
earlier in this revision):

| probe | result |
|---|---|
| `think: false` | works, content `OK` |
| `think: true` | works, `thinking` field populated |
| throughput | 7.3 tok/s (dense 27B on 204.8 GB/s) |

So both arms apply: 9 plan×track combos × 3 seeds × 2 arms = **54 cells**.

Runtime, estimated from `qwen3.6:27b` actuals rather than the cross-model mean
(the cross-model mean is misleading here — dense 27B think-on is far above it):

| arm | qwen3.6:27b actual | qwen3.8 expectation |
|---|---|---|
| think-off | 27 cells, 1.0 h, median 128 s/cell | ~1 h |
| think-on | 27 cells, 7.6 h, median 1013 s/cell | ~8 h |

Logs: `revision/logs/matrix_jetson_qwen38_{off,on}.jsonl`. Pass `--log` a bare
filename — the script already prefixes `revision/logs/`, so a relative path
nests (`revision/logs/revision/logs/...`).

### think-off arm: done — 27/27, 0 failures, 0.7 h

Generational comparison. Same 27B parameter count, same q4_K_M quantization,
same ollama config, same seeds, one generation apart:

| plan | qwen3.6:27b | qwen3.8:27b |
|---|---|---|
| B | 0.33 | 0.00 |
| v0.5 | 0.00 | 0.00 |
| v1 | **1.00** | **0.00** |
| v1g | 1.00 | 1.00 |
| v1.25 | **0.33** | **1.00** |
| v1.5 | 1.00 | 1.00 |
| v2 | 1.00 | 1.00 |
| mean | 0.67 | 0.57 |

**Read this cautiously.** The two flips (v1, v1.25) are single-column, n=3, and
they point in opposite directions — which is the signature of sampling noise,
not of a capability change. Fig 4 exists precisely to warn against reading a
3/3 or 0/3 cell as a property of the model. Confirming either would need the
n=10 treatment; neither is worth that on its own.

What is stable, and is the point worth making: **a newer, higher-benchmarking
model did not move the plan-detail cliff.** Both models fail without a plan and
both need roughly v1g-level detail before they work at all. The generational
improvement Qwen advertises does not show up as tolerance for vaguer
instructions. That supports the paper's central claim from a direction the
paper does not currently have — a model released after the experiments were
designed.

---

### think-on arm: running — and it is failing in a way no other model did

Cell 1 (`track-B`, no plan, seed 42) returned `truncated_in_thinking` after
2400 s: 57 KB of reasoning, `done_reason: length`, no script ever emitted. It
hit the token cap, not the wall clock.

**This is the only model of 13 to do this.** Across all 270 cells of the main
think-on arm there were zero `truncated_in_thinking` outcomes, and the direct
comparator `qwen3.6:27b` completed all 27 of its think-on cells with status
`ok` at a median of ~1000 s — including all 12 no-plan cells.

The budget is identical for every model (`num_predict: 16384`, `num_ctx:
16384`, set in `harness/run_one.py`), so this is a like-for-like comparison.
qwen3.8 simply reasons far more verbosely and exhausts a budget the other
twelve finish inside. The tail of its thinking shows it still weighing bash
array edge cases under `set -u` when it ran out.

**How to state this in the paper — the distinction matters:**
- Defensible: *at a fixed 16k token budget, this model does not converge on
  this task without a plan.*
- NOT defensible: *this model cannot do this task.* It never got to try; it
  was still deliberating when the budget ended.

This is exactly the distinction the `generation_status` classification added
during this revision exists to preserve (see the six outcome classes in
`run_one.py`). Scoring these cells 0 is correct — no script was produced — but
the reason is a budget, and a reader must be able to see that. The data
carries it; the prose has to as well.

It is also a concrete argument for R3.16-style reporting: a single
`num_predict` applied uniformly across models is itself an experimental
choice that can decide a result, and it belongs in the methods.

**Revised runtime.** 12 of 27 cells are no-plan. If they all truncate at
~2400 s that is 8 h for those alone, plus ~4 h for the 15 plan cells, so
**12–16 h rather than the 7.6 h estimated from qwen3.6**. Left running: cutting
it short would make this row non-comparable with the other twelve models, which
all received the full 27 cells.

### Where the 16k budget came from (answer: nobody decided it)

Asked 2026-08-14: who set the token budget and why 16k? Traced it rather than
assumed. The answer belongs in the methods section.

- `git log -S"16384" -- harness/run_one.py` returns exactly one commit: the
  initial commit. There is no commit introducing or justifying the value, no
  explanatory comment, and no other file in the repo sets it.
- The manuscript never mentions it. `writeup.md` has no match for `num_ctx`,
  `num_predict`, `16384`, `16k`, or "context window". The only "token budget"
  hit is rhetorical, in the abstract, about API cost.
- The models natively support **262,144** tokens. We run at **16,384** — 1/16
  of capability. ollama's own default is lower (4k), so 16k was an explicit
  choice someone typed once, just never a recorded one.

**Defensible:** uniform across all 13 models, so the comparison is fair;
generous for the task (the target is a ~100-line bash script, a few hundred
tokens); and forced by memory — KV cache at 16k already costs ~6 GB on top of a
19 GB model on a 64 GB board shared with the OS.

**Not defensible:** it is undocumented, so a reader cannot tell a budget-bound
result from a capability result. And it *decided* a result — qwen3.8 scores 0
on no-plan think-on cells because of a number nobody deliberately chose.

**It will get worse.** Models are increasingly trained toward long reasoning. A
fixed budget silently reclassifies "verbose reasoner" as "failed the task", so
1-of-13 hitting the ceiling today could be 5-of-13 on the next model refresh.
Any benchmark of this kind needs to report the budget and, ideally, show
sensitivity to it — which is what the ablation below does.

**Action for the paper:** state `num_predict`/`num_ctx` in the methods, report
`generation_status` breakdowns rather than bare scores, and cite the ablation
as the sensitivity check. This is an R3.16 item.

### THE v1g REVERSAL (confirmed 3/3, 2026-08-14 23:34)

The decisive comparison from the think-on arm, on the condition where the plan
is already sufficient:

The reversal is not confined to one plan. It holds at **every plan level that
succeeds without reasoning** (all Track A, mean over seeds):

| plan | reasoning OFF | reasoning ON | think-on gen time |
|---|---|---|---|
| v1g | **1.00** (3/3) | truncated (3/3) | 2220–2229 s |
| v1.25 | **1.00** (3/3) | truncated (3/3) | 2261–2275 s |
| v1.5 | **1.00** (3/3) | truncated (3/3) | 2326–2331 s |
| v2 (headline plan) | **1.00** (3/3) | truncated (3/3) | 2184–2193 s |

**12/12 decisive cells.** Four plan levels × three seeds, no exceptions.

**A complete reversal, every seed, same model, same plans, same budget.** With
reasoning off the model writes a perfect script in ~130 s. With reasoning on it
spends ~2200 s deliberating and emits nothing. It does not degrade — it stops
producing output entirely.

That it holds at v2 matters most: v2 is the paper's headline plan, the most
detailed recipe in the gradient, and the condition under which every other
model succeeds. Reasoning does not fail only on lean plans; it fails hardest
where the instructions are most complete.

Every think-on cell in the arm has come back `truncated_in_thinking`. Across
27 cells, not one produced a script.

**What this does and does not license saying.** Two explanations fit these data
and they are not the same claim:

1. *Reasoning is harmful here.* The plan already contains the answer; enabling
   reasoning makes the model re-derive it and talk itself out of a result it
   had for free.
2. *16k is too small to both reason and write.* The model's reasoning style
   needs more headroom than this budget allows, and the failure is the
   budget's, not the model's.

**The 16k arm alone cannot separate these**, and the paper must not pretend
otherwise. The budget ablation is what distinguishes them, which upgrades it
from a nice-to-have to the load-bearing experiment:

- If a larger budget lets v1g complete with reasoning on → explanation 2, and
  the honest finding is about a budget interacting with a verbose reasoner.
- If v1g still fails with reasoning on at 2x/4x budget while succeeding
  instantly with reasoning off → explanation 1, and the finding is that
  reasoning actively destroys a secured result.

**Ablation scope revised because of this.** Originally scoped to no-plan cells
only. It must now also cover **v1g track A**, which is where the reversal
appears; no-plan cells cannot distinguish the two explanations because the
model fails there with reasoning off as well.

### Early-stop criterion proposed, then withdrawn (2026-08-15 00:35)

I had proposed stopping the think-on arm once v1g and v1.25 both truncated
across all six cells, on the grounds that the remaining nine were confirmatory.
**That reasoning was wrong and the arm was left to run.**

Six of those nine are v1.5 and v2 track A — conditions where reasoning-off
scores 1.00. They do not confirm the v1g result, they establish how far the
reversal extends. v2 in particular is the paper's headline plan, so "does this
also happen at v2?" is the first question a reviewer asks, and skipping it
would have left exactly that hole.

Only the last three cells (v2 track B, no plan) are genuinely redundant, worth
~2 h of the remaining ~7 h. Not enough to justify reporting a partial row.

No cells were skipped. The arm ran 27/27.

### Ablation attempt 1 failed on a timeout I set too short (2026-08-15 09:07)

The first ablation run lost its opening cell to
`provider_error: timed out` after 5400 s with `thinking_chars: 0` — a wasted
90 minutes that measured nothing. Cause: I set `--gen-timeout 5400` by scaling
the 16k timing linearly, and **generation does not scale linearly with
context**. At 16k the model exhausted its budget in ~37 min; at 32k it was
still generating at 90 min, because per-token cost rises as the context fills.

The distinction matters for the data, not just the schedule:
`truncated_in_thinking` means the model spent its token budget and is a
result; `provider_error` means the harness gave up first and is an
infrastructure failure. Erring long costs wall-clock, erring short costs the
experiment. The run was killed, the two affected cells quarantined in
`revision/runs_ablation_discarded/`, and the logs deleted so nothing partial
can be mistaken for data.

**Attempt 2 (running) changes three things:**
1. **Timeouts generous** — 8 h at 64k, 4 h at 32k.
2. **64k runs first.** It is the decisive test at 4x the original budget. If
   the model still truncates there, 32k cannot change the conclusion; if it
   completes there, 32k becomes a refinement rather than a prerequisite.
3. **Scope cut to v1g Track A, 3 seeds.** v2 was dropped — it would double the
   runtime and the schedule cannot absorb it, and v1g already answers the
   question. Stated here so the narrowing is a recorded decision, not a
   silent one.

Worst case 24 h (3 cells x 8 h at 64k), finishing Sunday morning; faster if
the model converges rather than filling the budget.

### ABLATION, first 64k cell: a third outcome, and the mechanism (n=1)

`v1g` Track A, seed 42, reasoning ON, `num_ctx = num_predict = 65536`:

```
generation_status = ok        gen 12974 s (3.6 h)
thinking          = 219,856 chars
M1 (executes)     = 0
M3 (vs truth)     = 0.00
```

**It did not truncate.** Given 4x the budget the model finished reasoning and
emitted a script. The script is wrong. The same cell with reasoning OFF scores
1.00 in ~130 s.

So more budget does not rescue it — and the failure mode changed rather than
disappeared: 16k produced *no* script, 64k produced a *broken* one.

**Why it broke — this is the useful part.** The run died at:

```
[tabix] the index file exists. Please use '-f' to overwrite.
```

Under `set -euo pipefail` that non-zero exit killed the run after the first
sample. Comparing the two scripts for the identical cell:

| | reasoning OFF (1.00) | reasoning ON @64k (0.00) |
|---|---|---|
| size | 1536 B | 2314 B |
| `tabix` call sites | 1 | 2 |
| control flow | linear | `needs_update()` staleness checker |

The extra reasoning invented an **incremental-rebuild system that nobody asked
for** — a make-style `needs_update()` comparing input/output timestamps so
finished stages could be skipped. That feature introduces a second `tabix` call
site, neither site passes `-f`, and one of them re-indexes an existing file.

The model did not fail at the task. It failed at a feature it added to the
task. Reasoning did not produce a worse variant-calling pipeline; it produced a
*more ambitious* one, and the ambition is what broke.

> **CORRECTION (2026-08-15 17:19).** Everything below this line up to the next
> CORRECTION marker was written at n=2 and **overstates the case**. Seed 44
> then succeeded (M3 = 1.00) with the *most* elaborate script of the three,
> which refutes the causal claim that the elaboration is what breaks the runs.
> The corrected reading is in "ABLATION, final result" further down. The
> superseded text is kept so the reasoning error is visible rather than edited
> away.

**Seed 43 (n=2): the mechanism repeats, the specific break does not.**

```
seed 43: ok, 7961 s (2.2 h), 152,755 chars thinking, M1=0, M3=0.00
```

| seed | script size on/off | staleness machinery on/off | how it broke |
|---|---|---|---|
| 42 | 2314 / 1536 B | **6 / 0** | second `tabix` call site, no `-f` |
| 43 | 2197 / 1624 B | **5 / 0** | piped `lofreq` to stdout, unsupported |

Both reasoning-ON scripts invent incremental-build machinery that appears
**zero** times in either reasoning-OFF script. Both are ~40% larger. But they
fail differently: seed 42 double-indexes, seed 43 writes

```bash
lofreq call-parallel --pp-threads 4 --ref "$ref" "$bam" | bcftools view -O z -o "$vcfgz" -
```

against a tool that does not support stdout ("VCF output file not set ...
stdout is not supported").

**The common thread is the finding, and it lands directly on the paper's
thesis.** The paper argues that the active ingredient in a plan is the
*literal command syntax* — v1.25 and v1.5 recover performance precisely because
they supply the exact `lofreq call-parallel ...` invocation, and v1g fails for
other models because the same command arrives wrapped in Galaxy macro context.

Reasoning makes the model **paraphrase that literal command instead of copying
it**. Seed 42 restructured the indexing step around a cache check; seed 43
restructured the call step into a pipeline. Neither departure is unreasonable
as engineering; both destroy the one thing that makes the plan work.

So the mechanism is not "reasoning degrades code quality". It is: *reasoning
causes the model to treat the plan as a specification to improve upon rather
than a command to execute*, and the paper's whole result rests on it being
executed.

Seed 44 still running. n=2 is enough to state the pattern with the seeds
reported; do not upgrade the language beyond "in both cases" until it is in.

---

### ABLATION, final result at 64k — CORRECTION to the above

All three seeds in. **Seed 44 succeeded**, which changes the conclusion:

| seed | M3 | script on/off | staleness helpers on/off | specific bug |
|---|---|---|---|---|
| 42 | 0.00 | 2314 / 1536 B | 6 / 0 | `tabix` twice, no `-f` |
| 43 | 0.00 | 2197 / 1624 B | 5 / 0 | piped `lofreq` to stdout |
| 44 | **1.00** | **2984** / 1401 B | **8** / 0 | none |

**What survives, and what does not:**

- **Survives (3/3):** reasoning makes the model write substantially more
  elaborate scripts — 2197–2984 B against 1401–1624 B without it, and it
  invents incremental-build/staleness machinery (5–8 occurrences) that appears
  **zero** times in any reasoning-off script. That difference is perfectly
  consistent.
- **Refuted:** that the elaboration is what breaks the runs. Seed 44 elaborated
  *most* — the largest script and the most staleness machinery of all three —
  and produced a correct result. Elaboration is compatible with success.
- **Refuted:** my earlier n=2 claim that "the budget explanation is dead".
  Raising 16k → 64k moved v1g Track A from **0/3** (all truncated, no script
  at all) to **1/3 correct**. The budget was genuinely part of the problem.

**The defensible statement:**

> With reasoning enabled, qwen3.8 needs far more than the 16k budget merely to
> finish; at 64k it finishes every time but is correct only 1/3, against 3/3
> with reasoning disabled at 16k. The reasoning-on scripts are consistently
> larger and add machinery the plan did not ask for; that machinery is not
> itself fatal, but it enlarges the surface on which bugs appear — here a
> duplicate `tabix` call and an unsupported `lofreq` pipe.

So reasoning is not budget-starved *only*, and it is not over-engineering
*only*. It costs ~8x the wall-clock (7395–12974 s vs ~130 s) and still lands
at one third the accuracy. That is the claim the data supports, and it is
weaker and more useful than the one I wrote at n=2.

**Method note worth keeping:** at n=2 the two failures shared an obvious story
and it was tempting to write the mechanism up as settled. The third seed
falsified it. The 3-seed minimum is doing real work here, which is itself
evidence for the R3.8 point about small n — this time against my own
conclusion rather than the paper's.

---

### ABLATION COMPLETE — the full 16k / 32k / 64k curve

`qwen3.8:27b`, plan v1g, Track A, reasoning ON, 3 seeds per budget. Reasoning
OFF at 16k scores **3/3 correct in ~130 s** and is the reference line.

| budget | truncated | completed | **correct** | reasoning emitted | wall/cell |
|---|---|---|---|---|---|
| 16k | 3/3 | 0/3 | **0/3** | hit cap | ~2200 s |
| 32k | 3/3 | 0/3 | **0/3** | ~114k chars (cap) | ~5480 s |
| 64k | 0/3 | 3/3 | **1/3** | 140–220k chars (*self-terminated*) | 7395–12974 s |
| — reasoning OFF, 16k — | 0/3 | 3/3 | **3/3** | none | ~130 s |

**The quantitative finding.** At 64k the model is no longer budget-bound: it
stops on its own at 140–220k characters, roughly **35–55k tokens**. That is
this model's natural reasoning length for this task — 2–3x the 16k budget the
whole study uses, and more than 32k as well. Below that length it cannot finish
at all; the 16k and 32k rows are pure budget artifacts and carry no information
about capability.

**What this settles.**
1. *The budget was genuinely too small.* 16k and 32k truncate 6/6. Any claim
   about reasoning drawn from those rows alone would have been an artifact —
   which is exactly why `generation_status` exists and why the ablation was
   worth 30 h of GPU time.
2. *But budget is not the whole story.* Given enough room to finish, reasoning
   still lands at **1/3 correct against 3/3 without it**, at 57–100x the wall
   clock (7395–12974 s vs ~130 s). More thinking, correctly accommodated, is
   still worse here than no thinking.
3. *The mechanism remains open.* All three 64k scripts are larger than their
   reasoning-off counterparts and invent build machinery the plan never asked
   for, but the most elaborate one is the one that worked. Elaboration widens
   the bug surface; it does not determine the outcome. n=3 cannot separate
   those, and I am not going to pretend otherwise.

**For the paper.** The defensible sentence is roughly: *"Enabling reasoning on
this model requires a token budget 2–3x larger merely to produce output, and
even when that budget is supplied it reduces accuracy from 3/3 to 1/3 while
increasing wall-clock cost by two orders of magnitude."* Anything stronger
about *why* needs more seeds than this revision can afford.

**Cost of this experiment:** 6 cells, ~14 h GPU, on top of the 17.4 h think-on
arm. Recorded so the ratio of compute-to-conclusion is visible: ~31 h to
convert one ambiguous result into one defensible sentence and two retractions.

### Original ablation design (EXECUTED — see "ABLATION COMPLETE" above for results)

`harness/run_one.py` now takes `--num-predict` and `--num-ctx`, **both
defaulting to 16384**, so every existing run stays valid and nothing already
measured is invalidated. Both values are now recorded in `meta.json`:
`truncated_in_thinking` is meaningless without the budget it hit.

The two interact and this is easy to get wrong: the prompt (~2.4k tokens) is
charged against `num_ctx`, so with both at 16384 the usable thinking budget is
~14k, not 16k. Raising `num_predict` alone changes nothing once `num_ctx` binds.

**The budget was deliberately NOT raised for the running arm.** All 12 other
models ran at 16k. Giving qwen3.8 a bigger budget would make its row
incomparable and would convert the actual finding — it is the only model of 13
to exhaust the budget — into a configuration artifact.

Instead, once the 16k arm completes, run a separate ablation on the no-plan
cells only, logged separately, to answer:

> **Does more reasoning budget substitute for a plan?**

- If 64k rescues the no-plan cells, the plan is buying *compute* — a model with
  enough thinking budget reaches the same place unaided.
- If 64k still fails, the plan supplies something reasoning cannot generate,
  however long it runs.

Either result is publishable, and it is a sharper form of the paper's central
claim than anything currently in it. Cost: 3 seeds x 2 budgets ~= 6 cells, ~2 h.

Memory: measured at all three budgets, and **the linear projection I made from
the 16k figure was wrong**. Recorded because the error is instructive.

| context | projected | measured (`ollama ps`) | GPU |
|---|---|---|---|
| 16k | 25 GB | **25 GB** | 100% |
| 32k | 31 GB | **27 GB** | 100% |
| 64k | 43 GB | **31 GB** | 100% |

I assumed 19 GB of weights plus a 6 GB KV cache at 16k, scaling linearly. The
real numbers imply a ~23 GB base and only ~2 GB of KV at 16k — quadrupling the
context adds 6 GB, not 18. This model's attention is far more KV-efficient than
naive scaling suggests (grouped-query attention will account for most of it).

Consequence: **both 32k and 64k are fully GPU-resident**, so the ablation runs
at both and the "drop to 32k" contingency was never needed. The probe was still
worth building — it verified residency instead of trusting the projection, and
the projection was the thing that turned out to be wrong.

Sequencing chosen by the user (2026-08-14): finish the 16k arm first, then
ablate. The alternative was to interrupt the arm (it is resumable) and ablate
tonight.

### Draft prose ready: `revision/qwen38_addendum.md`

Written while the think-on arm runs. Two Results subsections drafted — *A newer
model does not move the plan-detail cliff* and *Reasoning budget can masquerade
as capability* — plus one sentence to append to Methods/*Inference settings*
once the ablation lands. The ablation paragraph is marked `[PENDING]` rather
than guessed at.

Not inserted into either writeup file: where it goes, and whether the
truncation finding is a Results subsection or a Discussion paragraph, is a
judgement call left for you.

The file ends with three caveats to preserve under editing — chiefly, do not
let the v1/v1.25 flips be described as a capability difference (n=3,
single-column, opposite in sign), and do not let "ran out of budget" become
"cannot do the task".

**Methods change already applied to both writeup files** (2026-08-14, at your
request): new *Inference settings* subsection documenting `temperature`,
`top_k`/`top_p`, and `num_ctx = num_predict = 16384`, why 16k binds, and the
budget-vs-capability distinction. Placed after *Hardware*. It describes memory
as the binding constraint rather than claiming a rationale nobody recorded.

---

## Queued for your return

**ALL COMPUTE IS FINISHED.** 900 cells, ~93 h. Nothing is running; the box is
idle. Everything below is judgement, not work.

**New decisions created by the qwen3.8 addendum:**

A. **Does the reasoning result go in the paper at all?** It is the strongest
   new finding in the revision — a model released after the experiments were
   designed, reversing completely with reasoning enabled, plus a budget curve
   that explains part of it. But no reviewer asked for it, it is one model, and
   it opens a topic (reasoning vs plan detail) the paper currently does not
   discuss. Options: full Results subsection / one Discussion paragraph /
   supplement only / omit.
B. **How hard to state the reasoning claim.** Draft prose in
   `revision/qwen38_addendum.md` deliberately stops at "we report the effect
   without asserting the cause". If you want a mechanism claim, it needs more
   seeds — roughly 10 at 64k, about 20 h.
C. **Whether Fig 3 gets regenerated for print.** Adding qwen3.8 deepened the
   v2 reasoning penalty from −0.20 to −0.27 and flattened v1g/v1.5 to ~0. The
   figure is current; the numbers in any prose written before 2026-08-15 are
   not.
D. **`num_predict` in the methods.** The *Inference settings* subsection is
   already in both writeup files. The ablation now gives it a citable
   sensitivity result — worth one added sentence, which is drafted in the
   addendum.

**Pre-existing decisions (unchanged):**
1. **Where the revision figures go.** They can replace Fig. 1, or land as a
   supplement. Fig. 3 is arguably a second paper-level claim rather than a
   response to a reviewer point, and that changes the framing of the abstract.
2. **`top_k`/`top_p`.** Pin them uniformly (costs a full re-run, ~40 h) or
   report the per-model defaults as collected
   (`collect_repro_metadata.py`). Reporting as-is is defensible and is what
   the metadata file currently supports.
3. **The abstract's cost argument.** Break-even is 76,424 runs — 15.3 years at
   5k runs/yr — which contradicts "cost is the bottleneck" at $0.066/call. The
   economics only work at agentic scale (~$1/run → 5,046 runs). This needs
   rewording, not more data.
4. **`gpt-oss:20b` in the think-off arm** — it reasons regardless of the flag.
5. **n=10 on the Claude rows** — costs real money, so not run.

**Needs a machine that isn't this one:**
- Rebuild `writeup_GR.pdf` to confirm figures print as 1/2/3. This box has
  neither pandoc nor pdflatex.

**Needs sudo:**
- Optional: real board power for the cost model. The INA3221 rails are
  root-only. `sudo tegrastats --interval 1000 | head -60` under load, then
  `python3 revision/scripts/cost_model.py --watts <measured>`. Electricity is
  a negligible term, so this changes the break-even by very little — it is a
  credibility fix, not a numbers fix.

**Not done, deliberately:**
- No `git commit`, no `git push`, no branch changes.
- No Anthropic API spend beyond the completed 81-cell run.
- No ollama service config changes.

---

## Context-distance hypothesis: tested, inconclusive (2026-08-16)

**Question.** Why is accuracy worse with reasoning enabled? Proposed mechanism:
the script is emitted after thousands of tokens of chain-of-thought, so the
plan text is far back in context when the model finally copies a command, and
literal-copy fidelity decays with distance.

**A prior claim of mine that did not survive contact with the data.** I had
described reasoning-on scripts as systematically more elaborate — inventing
build machinery, paraphrasing rather than copying. That is true of
`qwen3.8:27b` and **does not generalise**. Median reasoning-on/off script-size
ratio at v2 across the other ten models is **1.00x**. Same length, more bugs.

**What the reasoning-on failures at v2 actually are** (30/33 cells produced a
script; 8 scored zero) — ordinary bad bash, not over-engineering:

```
run.sh: line 45: syntax error: unexpected end of file
run.sh: line 22: syntax error in conditional expression
samtools sort: failed to read header from "-"      (x3, malformed pipe)
[main] unrecognized command 'bgzip'                (hallucinated subcommand)
[E::fai_build_core] Format error, unexpected "c"
```

**The test I first proposed was unsound.** Repeating the plan at the end of the
prompt does not shorten the relevant gap: the prompt is consumed in full before
generation starts, and what intervenes between plan and script is the model's
own thinking. Prompt layout cannot manipulate it.

**The test that was available.** If distance causes errors, then within a
single (model, plan) cell the seeds that think longer should fail more. Track-B
conditions must be collapsed first — Track B ignores the plan file, so with a
fixed seed the b/v1/v2 Track-B "cells" are byte-identical repeats, not
independent observations (this is the fourth time that trap has appeared).

| | |
|---|---|
| independent mixed cells | 23 |
| failing seed thought longer | **16 / 23** |
| one-sided binomial p | 0.047 |
| **two-sided p** | **0.093** |

**Verdict: not supported, not refuted.** Directionally consistent, statistically
marginal. Reported as inconclusive because (a) the hypothesis was generated from
this same data, so the one-sided test is illegitimate and 0.093 is the honest
figure; and (b) causal direction is unidentified — longer thinking may be a
symptom of a seed wandering into a confused trajectory rather than the cause of
the resulting errors.

**What would settle it.** An intervention, not an observation: vary reasoning
length directly at fixed prompt and seed (e.g. `gpt-oss:20b` exposes a
reasoning-effort control) and see whether error rate tracks it. Until then the
paper should continue to report the effect without a mechanism, which is what
the drafted Results text already does.

---

## Effort experiment: context-distance REFUTED, and a caveat for the paper

**Design.** `gpt-oss:20b` exposes a reasoning-effort control (ollama accepts
`think: "low"|"medium"|"high"`). Prompt, seed, plan, model and hardware held
fixed; only effort varies. 3 plans x 3 seeds x 3 levels. Low/medium ran at
num_ctx 32768; the high arm was re-run at 131072 (the model's native ceiling,
30 GB / 100% GPU) after truncating at 32k — that first high arm measured the
budget, not reasoning, and was discarded.

**Manipulation check:** mean thinking 480 / 10,053 / 139,705 chars. A 290x
range from one parameter.

| effort | thinking | v1 | v1.25 | v2 | mean M3 |
|---|---|---|---|---|---|
| low | 480 | 0/3 | 0/3 | 3/3 | 0.33 |
| medium | 10,053 | 0/3 | **2/3** | 3/3 | **0.56** |
| high | 139,705 | 0/3 | 0/3 | 3/3 | 0.33 |

**1. The context-distance hypothesis is refuted.** It predicted that longer
reasoning degrades literal-command fidelity, so v2 should break at high effort.
At 290x the reasoning length, v2 is still 3/3. Distance from plan to script
does not cause the errors.

**2. The plan dominates; reasoning length is second-order.** Sufficient plan
(v2): perfect at every effort. Insufficient plan (v1): fails at every effort.
Reasoning only moves the result in the narrow band between (v1.25), and there
non-monotonically — an inverted U, with medium beating both ends. This is a
*strengthening* of the paper's central claim, arrived at from the opposite
direction: not even a 290x swing in reasoning substitutes for plan detail.

**3. CAVEAT FOR THE DRAFTED RESULTS SUBSECTION.** The main matrix recorded
gpt-oss:20b at v2 as 3/3 reasoning-off and 2/3 reasoning-on (num_ctx 16384),
one of the observations behind "reasoning fails hardest where the instructions
are most complete". At generous budget it is **3/3 at every effort level**.
The penalty did not reproduce.

Stated carefully in both directions: 2/3 vs 3/3 is a single seed and this does
not establish the 16k result was an artifact — noise fits equally well. But the
v2 penalty is **not robust** for this model, and the drafted paragraph leans on
it. The qwen3.8 result is unaffected: that model truncated even at 64k and was
1/3 correct when it did finish, which is a different and much larger effect.

**Action:** before submission, either (a) soften the v2 generalisation to name
qwen3.8 specifically, or (b) re-run the reasoning-on v2 cells for the other
models at a generous budget to see whether any v2 penalty survives. (b) is
~12 cells and would settle it.
