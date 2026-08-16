# GENOME/2026/282393 — Reviewer comments, sorted for revision

Decision: **Return for Revision** (22 Jul 2026). Three reviewers, 31 distinct
points. Item IDs (R1.1, R2.4, …) follow the order the comments appear in each
review so they can be mapped one-to-one onto a response letter.

Overall temperature: R1 is positive with additions; R3 is constructive but
substantial; R2 is the most negative and questions framing and design. No
reviewer rejects the premise. The two things all three converge on are
**(a) it is not actually agentic** and **(b) one workflow is not enough to
support the claims made**. Everything else is negotiable; those two are not.

---

## Consensus items (raised by ≥2 reviewers — these are non-negotiable)

| # | Issue | Raised by |
|---|-------|-----------|
| C1 | Single-pass `run.sh` generation is not an agentic loop; no inspection of intermediate output, no repair, no decision to add steps | R2.10, R3.1 |
| C2 | Scope is one small workflow; conclusions are broader than the evidence | R1.3, R2.4, R3.3, R3 preamble |
| C3 | Jaccard alone is the wrong metric; needs conventional measures and a defined pass/fail | R2.11, R3.4 |
| C4 | "Seed" does not control LLM determinism (sampling params do), and API seed semantics differ from local | R2.6, R3.9 |
| C5 | Missing related work / no baseline comparison (planner-executor prior art, Biomni, GWAS agents) | R1.2, R2.9, R3.1 |

---

## Tier 0 — Factual and internal-consistency defects (hours; do first)

These are unambiguous errors. Fix before anything else; they cost nothing and
each one currently reads as sloppiness to the reviewers.

- **R3.14 — Figure numbering is broken.** Plan-gradient heatmap labeled Fig 1
  but cited as Fig 2; error-injection panel labeled Fig 2 but cited as Fig 3;
  workflow DAG labeled Fig 3. Files on disk are `figures/fig1_workflow_dag.png`,
  `ms_fig2_5080_gradient.png`, `ms_fig3_qwen3p6_27b_error.png` — the file names
  imply the intended order; the labels in `writeup_GR.md` do not match. Audit
  every cross-reference in both `writeup.md` and `writeup_GR.md`.
- **R3.12 — Table 6: reported median for the 2×A5000 system lies outside the
  reported IQR.** Recompute from source; this is either a transcription error or
  a real bug in the summary script.
- **R3.10 — Figure 1 heatmap cells show n = 2, 3, 6 while the text says every
  condition was run three times.** Either the counts are wrong or the text is.
  Decide and state explicitly whether failed generations were dropped or reruns
  pooled; if runs were excluded, say on what pre-specified rule.
- **C4 / R2.6 / R3.9 — Rewrite all determinism language.** Report temperature,
  top-p, top-k, repeat penalty, and max tokens. If the integer was only a run
  identifier for the Anthropic runs, say so and stop calling it a sampling seed.
  Note that even fixed sampling params do not give bitwise determinism under
  batched GPU inference.
- **R3.16 — Reproducibility metadata.** Add exact model IDs and digests
  (`ollama show --modelfile` / manifest sha256), quantization format
  (Q4_K_M vs MLX 4-bit vs bf16), inference-engine versions (ollama, llama.cpp,
  MLX), tool versions (bwa, samtools, bcftools, …), and full command lines.
  Model family names alone are not enough. Most of this is already recoverable
  from `runs_5080_v2/` and `setup/` — surface it as a supplementary table.
- **R3.15 — De-promotionalize.** Remove/replace "qwen3.6:27b is the winner",
  "protagonist", "all you need is a plan", "pick the cheapest box", and similar.

---

## Tier 1 — Writing, framing, and structure (days; no new data)

### Framing (the R2 core complaint)

- **R2.1 — Reads as an implementation guide, not a paper.** Reframe the
  introduction around the genomics problem (routine per-sample analysis at scale
  in a small lab, the human-time cost of babysitting it) and only then introduce
  LLM orchestration as one candidate solution. Currently the LLM is the subject
  and genomics is the substrate; reviewers want that inverted.
- **R3 preamble + C2 — Narrow the claims to what a single mtDNA workflow
  supports.** Explicitly state, in Results and Discussion, that success at the
  detailed-plan end of the gradient may reflect transcription of near-executable
  syntax rather than orchestration — and that the experiment as designed cannot
  distinguish the two. Say it before the reviewers say it again.
- **R3.1 / R2.10 / C1 — Fix the word "agentic" in the title and throughout,**
  or earn it (see Tier 3, T3.1). If no iterative arm is added, the honest title
  is closer to "plan-conditioned code generation" than "agentic analysis
  orchestration". Recommend doing both: add a bounded-repair arm *and* retitle.
- **R3.2 — Answer "why an LLM at all?" head-on.** A lab can save the validated
  script, parameterize it, or write it in Snakemake/Nextflow/Galaxy. Needs a
  dedicated subsection arguing where the LLM earns its cost (novel or one-off
  workflows, adaptation under changing inputs, natural-language interface for
  non-programmers) and conceding where it does not (stable, repeated pipelines).
  A deterministic-template baseline in the framing costs nothing and pre-empts
  the objection.
- **R1.3 — Generalization and production.** Add a Discussion subsection on how
  the planner-executor split translates to other workflow classes and what
  changes when moving from a sandbox to a production/shared-cluster setting
  (scheduling, queueing, provenance, failure paging, multi-user isolation).
- **R2.4 — Task taxonomy.** Add a table or paragraph enumerating candidate
  workflow classes (alignment/variant calling, RNA-seq quantification/DE,
  single-cell, assembly, metagenomic profiling, ChIP/ATAC peak calling) with a
  rough estimate of plan complexity and I/O footprint for each — even though
  only one was run. Sets scope honestly and shows the framework generalizes in
  principle.

### New sections that require writing, not experiments

- **R1.1 — Security guardrails.** Currently absent and it is R1's first point.
  Document what actually constrains the executor: container/VM boundary,
  filesystem scope, network egress, no-sudo, resource limits, whether generated
  code was reviewed before execution, and what would stop a destructive or
  arbitrary-code path. If the harness runs unsandboxed, say so and state that
  sandboxing is a prerequisite for the production setting.
- **R1.4 — Data governance and privacy at the planning step.** How does a lab
  keep proprietary configs, local directory layouts, sample identifiers, and
  system metadata out of a commercial planner's context? Recommend documenting
  the abstraction boundary (planner sees a workflow description and generic
  paths; executor binds real paths locally) and noting that this is exactly what
  the planner-executor split buys you beyond cost — a genuinely good argument
  the manuscript is currently not making.
- **R1.4 (second half) — Planner instruction detail.** The text must describe
  how the planner is prompted, by category, including whether recipes carry
  explicit safety/validation checks. Pointing at GitHub is not sufficient;
  lift the prompt structure into the main text or a supplementary figure
  (source: `prompts/`).
- **R1.2 + C5 — Prior art for planner-executor.** Cite the pattern properly
  (planner-executor / plan-and-solve / hierarchical task decomposition,
  ReAct-style separation, LLM compiler-style approaches) and drop any language
  implying the design is novel. The contribution is the empirical evaluation on
  genomics work and hardware, not the architecture.
- **R2.9 / R3.1 / C5 — Related work section.** Must engage Biomni
  (Huang et al. 2025, bioRxiv) explicitly, plus end-to-end GWAS and
  variant-effect agent papers. At minimum a positioning discussion; a running
  comparison is Tier 3 (T3.5).
- **R2.5 — Survey of open-source harnesses** (Claude Code, OpenCode, Aider,
  OpenHands, Goose, Biomni) early in the draft, with what each does that this
  harness does not. Also does double duty against C1 by making the design
  choice explicit rather than apparently unaware.
- **R3.13 — Honest cost accounting.** Replace "free" with "no marginal API
  fee". Build a table: hardware capital cost, depreciation over 3 years,
  measured or estimated wall power × runtime × local electricity rate, staff
  time for setup/maintenance/model validation, versus per-run API cost at
  current token prices. Include a break-even run count. This is a strong
  addition — it is the practical question the intended readership actually has.

### Reorganization

- **R2.2 — Move Table 1 to the supplement.** Drop the "coding variant" and
  "reasoning" columns (all current models reason; this is not a coding
  benchmark). Keep a small main-text table with only the models actually
  evaluated and the parameters that matter for hardware fit.
- **R2.3 — Add the conceptual background reviewers do want in the main text:**
  MoE vs dense and what it means for VRAM residency, KV-cache scaling with
  context length and its effect on the memory budget, and the anatomy of an
  agentic loop. This is a swap with R2.2, not an addition.
- **R2.7 — Promote error handling from Methods to Results/main text** with a
  fuller description of the injection mechanism, what the executor sees, and
  how recovery was scored.

---

## Tier 2 — Re-analysis of existing data (days; no new runs)

Everything here can be done from `results.csv`, `error_matrix_*.jsonl`, and
`runs_5080_v2/` without regenerating anything.

- **R3.4 / C3 — Add conventional variant-calling metrics:** precision, recall,
  F1, TP/FP/FN counts against `ground_truth/`, and allele-frequency error
  (per-variant AF delta, MAE/RMSE, plus a scatter of called vs truth AF).
  Keep Jaccard as a secondary summary.
- **R2.11 — Jaccard is degenerate at this scale.** With ~5 truth variants it
  takes a handful of discrete values. Either report the underlying counts
  directly, or move to a per-variant confusion matrix visualization. Also state
  the pass/fail criterion explicitly and in one place: what exactly counts as a
  successful run (script generated? executed without error? VCF produced?
  variants matching truth at what threshold?).
- **R2.8 — Align scoring with published practice.** Map the custom rubric onto
  established measures where possible; cite the scoring schemes used by prior
  bioinformatics-agent evaluations and justify each place the rubric departs.
- **R3.8 — Statistical honesty at n = 3.** Replace "robust" with interval
  estimates: report Wilson or Jeffreys CIs on each success proportion (3/3 gives
  roughly a 29–100% CI — worth stating outright). Either add replicates (T3.6)
  or systematically soften every claim resting on three trials.
- **R3.7 (partial) — Recategorize the existing error suite.** A tool that
  sleeps then succeeds is a latency/patience test, not an error; a tool emitting
  warnings with correct output is a logging-robustness test. Relabel the
  categories along axes of *true failure* vs *noise tolerance* and rescore
  accordingly — this is a relabeling of existing data, not new runs.
- **R3.11 (partial) — Cross-platform framing.** The reviewer's premise ("same
  weights should produce equivalent output") deserves a direct answer: the
  builds are *not* identical across platforms (GGUF quant vs MLX, different
  kernels, different batching), which is precisely why outputs diverge. Say this
  explicitly; report the exact quant/engine per platform (overlaps R3.16). A
  standardized identical-config benchmark is Tier 3 (T3.7).

---

## Tier 3 — New experiments (weeks; scope decision required)

Ranked by return per unit effort. Not all of these are affordable — the
response letter should do a subset and argue the rest.

- **T3.1 (R3.1, R2.10, C1) — Bounded iterative repair arm. Highest priority.**
  Add a condition where the executor sees stdout/stderr and exit codes and gets
  N repair attempts (N ≤ 3), compared head-to-head with the current one-shot
  condition across the plan gradient. This single addition converts the paper's
  weakest claim into its most interesting result: *how much iteration
  substitutes for plan detail*. The harness already captures the logs needed.
- **T3.2 (R3.6) — Planner comparison.** Currently one frontier planner produces
  nearly every plan. Add (a) an expert-written human plan, (b) a second frontier
  model's plan, (c) a plan assembled from official tool documentation — held at
  matched detail level. Cheap relative to impact: plans are short, and it
  directly tests whether the result is about *the planner* or merely about *the
  presence of executable syntax*.
- **T3.3 (R3.5) — Exploratory vs confirmatory separation.** v2 was written after
  seeing v1 fail, so the gradient is partly fitted to observed failure modes.
  Minimum viable fix: declare the existing results exploratory, freeze plans and
  model-selection criteria, and run the frozen protocol on one held-out
  workflow. Even a single held-out workflow rescues the confirmatory claim.
- **T3.4 (R3.3, R3.2, C2) — Second biological benchmark with perturbations.**
  Options in rough order of cost: an additional dataset at varied depth and
  allele frequency (spike-in or simulated); a reference-genome swap; a tool
  version change; a workflow requiring an external API call. Note T3.3 and T3.4
  can be satisfied by the *same* second workflow if planned together — do that.
- **T3.5 (R3.7) — Expanded error suite.** Add: malformed FASTQ, missing input
  file, permission denied, disk-full, incompatible tool version, stale
  intermediate files, and syntactically valid but biologically implausible
  output. The last one is the most interesting scientifically — it tests whether
  the executor notices nonsense it cannot detect from an exit code.
- **T3.6 (R3.8) — More replicates.** Raise n from 3 to ≥10 for at least the
  headline conditions. Mechanically cheap, just slow; it retires R3.8 entirely.
- **T3.7 (R3.11) — Standardized cross-hardware benchmark.** Fixed prompt, fixed
  output length, fixed repetitions, matched model configuration on each machine,
  reported as tokens/s with dispersion. Replaces the current mixed-workload
  timing comparison.
- **T3.8 (R2.9, C5) — Run Biomni as a comparator.** Highest cost, weakest
  return: different scope, different task set, likely needs its own environment.
  Recommend positioning in related work (Tier 1) and arguing that a head-to-head
  is out of scope, noting R2's own concession that the design concerns "may not
  need to be in the scope of the article".

---

## Recommended minimal-viable revision

If the goal is one revision round rather than two:

1. All of Tier 0 and Tier 1. Non-optional; roughly two weeks of writing.
2. All of Tier 2. The metrics rewrite (R3.4/R2.11) is what makes R3 movable.
3. From Tier 3: **T3.1 + T3.2 + T3.6**, and **one** second workflow doing
   double duty for T3.3 and T3.4. Expand the error suite (T3.5) opportunistically
   on that second workflow.
4. Argue, don't run: T3.8 (Biomni head-to-head), and the fully generalized
   production deployment (R1.3 as discussion only).

## Points worth pushing back on (politely, in the letter)

- **R3.11's premise** that identical weights should give identical outputs
  across hardware — factually incomplete given quantization and kernel
  differences. Answer with data, not compliance.
- **R2.8's implication** that a published rubric exists and was ignored — no
  standard scoring exists for this task shape; justify the custom rubric while
  adding the conventional metrics R3 asked for.
- **T3.8 / Biomni comparison** — different problem framing (tool-using research
  agent vs plan-conditioned executor on fixed hardware); cite and position
  rather than benchmark.

## Tension between reviewers to resolve deliberately

R2 wants technical LLM detail *added* to the main text (MoE, KV cache) while
also wanting Table 1's model catalog *removed*. These are consistent if read as:
explain the concepts a reader needs to size hardware, drop the enumeration of
models the reader will not use. Resolve it that way and say so in the letter.
