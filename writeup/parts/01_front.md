# From plan-conditioned code generation to a tool-using agent loop: evaluating local open-weight LLMs on two genomic workflows

## Abstract

Small genomics laboratories process samples in batches through pipelines that are already written and already validated, and the recurring cost of that work is a person's attention rather than compute. We asked whether a free, locally hosted, 4-bit-quantised open-weight language model can occupy the *execution* role in such work when the plan is authored separately, on hardware a laboratory already owns. Two benchmarks were run. In the first, a frontier model authored plans of graded detail for per-sample mitochondrial variant calling and twelve local models generated a run script in a single pass across seven plan conditions and two reasoning settings (900 cells, ~93 h of GPU time). Plan detail, not model identity, set the ceiling: on the most detailed plan 9 of 12 models scored 10/10 across ten seeds (pooled 107/120, 95% CI 0.82–0.94), and the threshold did not move for a model released after the design was frozen. In the second, two local models drove a 30-step public Galaxy workflow (fastp → STAR → featureCounts) over six RNA-seq runs on usegalaxy.org. Both submitted a parameter-correct invocation (2/2 inputs, 8/8 parameters) and the workflow reproduced the published benchmark exactly (5,594 genes; 93.1–93.6% of uniquely mapped fragments assigned), but neither executor completed the final reporting step — a human read the per-sample counts out of Galaxy. Three findings cut against our original framing: where a tool genuinely fails, recovery is 12% for the local and the frontier model alike; the conventional accuracy metrics we added are degenerate by construction, because the variant caller is deterministic; and local hardware breaks even against API spend only after roughly 76,000 runs, so cost is not the argument for running locally, governance and metering are. What is demonstrated is plan-conditioned execution, not autonomous analysis: the Galaxy plan required eleven human corrections before either executor saw a clean run. Artifacts are at https://github.com/nekrut/LLM-eval-paper; the models named here will be superseded, and the design is meant to be re-run. <!-- addresses: R2.1, R3.15, R3.preamble, C1, C2, R3.13 -->

## Introduction

A laboratory that generates its own sequencing data does the same analysis many times. Samples arrive in batches of four, or six, or ninety-six; each batch goes through a pipeline that was settled months ago and is not in question. Nothing about that work is intellectually interesting, and none of it is free: someone has to bind the pipeline to this batch's file names, run it, notice which samples failed, and re-run them. In a laboratory with a dedicated bioinformatics engineer, that person absorbs the cost. In the many laboratories without one, it falls on a graduate student or a postdoc whose time was budgeted for something else.

This paper takes two concrete instances of that problem — per-sample mitochondrial DNA variant calling from paired-end Illumina reads, and per-sample RNA-seq quantification against a reference annotation on a shared public Galaxy server — and asks a narrow question about them. Given an analysis plan authored once, can a free open-weight language model running on hardware the laboratory already owns carry out the execution, reliably enough to be worth setting up? We do not ask whether a language model can design the analysis, and we do not report on what such systems will be able to do later. We report what two of them did, on two workflows, on five machines. <!-- addresses: R2.1, R3.15 -->

### Routine per-sample analysis is a human-time problem

The cost of routine per-sample analysis is easy to underestimate because it does not appear on any invoice. It is the half-hour spent re-deriving a `bwa mem` command line after a tool upgrade changed a default. It is discovering that three of twenty samples failed overnight for three unrelated reasons, and re-running each by hand. It is a collaborator asking for "the same thing you did last time, but with the new reference," and the translation of that sentence into a parameterised run taking longer than the run itself. Individually these are minutes; in aggregate, across a year of batches, they are the reason the analysis backlog in a small laboratory is measured in weeks.

This burden concentrates in exactly the laboratories least equipped to carry it. A core facility or a large consortium amortises pipeline maintenance across many projects and can justify a full-time engineer. A four-person laboratory sequencing its own samples cannot, so the work is done by whoever has the shell open, at whatever level of care the deadline permits. That is also where undocumented, unreproducible one-off command lines come from.

Any candidate remedy for this problem inherits three requirements from the setting, and these constrain the design of everything that follows. It has to be cheap enough per run that nobody rations it, because a tool that is metered is a tool that gets bypassed. It must not require exporting local directory layouts, sample identifiers, or system metadata to a third-party service, because much sequencing data carries consent and privacy conditions that make casual export unacceptable regardless of the vendor's terms. And it should run on hardware the laboratory already has or can buy once, rather than on a resource that must be requested, scheduled, and justified. <!-- addresses: R2.1, R1.4 -->

### Why an LLM at all, and when a saved script is better

The honest baseline deserves stating without hedging, because it wins more often than the recent literature implies. For any pipeline that is stable and repeatedly run, a validated shell script under version control, a Snakemake or Nextflow rule set, or a saved Galaxy workflow is simply better than a language model. It is deterministic, it is auditable, it fails the same way twice, it costs nothing to invoke, and it does not require a GPU. A laboratory whose analysis needs are covered by such a template should write the template. Nothing here argues otherwise, and we did not test a language model against a saved script on a task where the saved script applies, because the outcome is not in doubt. <!-- addresses: R3.2 -->

Where a language model can earn its keep is at the edges of that template. Four cases recur: analyses that are genuinely one-off, where writing and validating a reusable rule set costs more than the analysis; adaptation, when input layouts, reference builds or tool versions change and the template needs editing rather than invoking; a natural-language interface for laboratory members who can evaluate a result but do not write code; and, most relevant to what we measured, *binding* — taking a fixed, already-correct workflow and attaching it to a specific, messy set of local inputs.

Our second benchmark is the clearest instance of that last case, and it is arranged so the template sits on the model's side of the comparison rather than against it. The workflow is an existing, community-curated Galaxy workflow, a deterministic template by construction that we did not ask any model to write. What the executor supplied was the binding: six real sequencing runs assembled into a paired collection, a reference build, an annotation file of the correct format, and eight parameter settings. A human performed the identical binding manually on the same server, as an explicit deterministic comparator. <!-- addresses: R3.2 -->

The counter-evidence should be visible before any result is. On this study's own economics, the deterministic route is cheaper than a local model until roughly 76,000 runs, because the measured API cost of the task is $0.0662 per run and setup and maintenance labour, not electricity, dominates the local side. Cost was our original motivation, and the cost argument did not survive contact with the measurement. <!-- addresses: R3.13, R3.2 -->

### Planner-executor is an existing pattern

Separating a model that decides what to do from a model or process that carries it out is a standard construction in the language-model literature and is not a contribution of this paper. Plan-and-solve prompting elicits an explicit plan before execution and shows that the separation itself improves multi-step reasoning (Wang et al. 2023). Least-to-most prompting decomposes a problem into ordered subproblems before solving any of them (Zhou et al. 2023). ReAct interleaves reasoning traces with actions so that a model's decisions and its tool calls are distinguishable rather than fused (Yao et al. 2023). Hierarchical designs push the split across model boundaries: HuggingGPT has a controller model plan a task and dispatch each subtask to a specialised model (Shen et al. 2023), and LLM-compiler-style systems compile a plan into a dependency graph of tool calls dispatched by cheaper machinery (Kim et al. 2024). Reflexion adds the complementary piece, a feedback channel by which an executor revises after observing its own failures (Shinn et al. 2023). <!-- addresses: R1.2, C5 -->

We adopt this pattern; we do not propose it. The architecture evaluated here — one expensive model authors a plan once, a cheap local model executes it many times — is the plan-and-dispatch design named above, with the dispatch target set to a 4-bit-quantised open-weight model on a desktop or an embedded board. The contribution we claim is empirical and narrow: a measurement of that arrangement on genomic work, on hardware a laboratory can buy outright, with the detail of the plan varied systematically as the independent variable. <!-- addresses: R1.2, R3.1, C5 -->

That variation is the specific gap the prior literature leaves open for a laboratory. The papers above establish that decomposition helps, and they generally evaluate it with a capable model on both sides of the split. They do not answer the question a laboratory faces: how detailed the plan has to be before a small model that fits in 16 or 24 GB of memory can occupy the executor role at all, and whether that threshold is a property of the model, and so likely to fall with each release, or a property of the task, and so likely not to. <!-- addresses: R1.2, C5 -->

### Agent harnesses and bioinformatics agents

The execution side of a planner-executor system is supplied in practice by an *agent harness*: software that presents tools to a model, runs the resulting tool calls, feeds the outputs back, and decides when to stop. Several open-source harnesses were mature by mid-2026 and their capabilities overlap heavily (Table 1). What matters here is the capability they share and our first benchmark lacks.

**Table 1.** Open-source agent harnesses available as of May 2026, and the capabilities relevant to this study. Feature sets in this area change on a scale of weeks; the entries describe the harness class rather than a pinned release. The last row is the bespoke harness used for benchmark 1, included for contrast.

| Harness | Primary interface | Tool-call loop | Inspects tool output | Attempts repair | Durable cross-session state |
|---|---|---|---|---|---|
| Claude Code | terminal | yes | yes | yes | yes |
| OpenCode | terminal | yes | yes | yes | yes |
| Aider | terminal, git-native | yes | yes | yes | partial (via repository) |
| OpenHands | sandboxed workspace | yes | yes | yes | yes |
| Goose | terminal, MCP-extensible | yes | yes | yes | yes |
| Cline / Roo Code | editor extension | yes | yes | yes | partial |
| Continue | editor extension | yes | yes | yes | partial |
| Loom (benchmark 2) | headless, MCP-extensible | yes | yes | yes | yes (file-backed notebook) |
| *this study, benchmark 1* | *single generation* | *no* | *no* | *no* | *no* |

Benchmark 1's harness issues one prompt, receives one script, and executes it externally. It has no loop, shows the model no output, and gives it no opportunity to repair. That was a deliberate choice — it isolates plan detail as the only variable — but it is also precisely the limitation three reviewers of the first version of this manuscript identified, and they were right that the resulting system should not be called agentic. Benchmark 2 was added to supply the missing loop, using Loom, a headless harness that reaches Galaxy through an MCP tool server and keeps a file-backed notebook across sessions. <!-- addresses: R2.5, C1 -->

Within bioinformatics, the closest work evaluates open-ended tool-using research agents against task suites. Biomni couples a large tool and database inventory to a frontier model and scores it across a wide range of biomedical tasks, including ones requiring literature retrieval and experimental design (Huang et al. 2025); BixBench grades agents on Dockerised computational-biology scenarios (Mitchener et al. 2025); BioMaster wraps a plan/task/debug/check loop around retrieval-augmented generation for RNA-seq, ChIP-seq, scRNA-seq and Hi-C (Su et al. 2025); BioAgents fine-tunes small open-weight models for local execution (Mehandru et al. 2025); and end-to-end agents have been reported for GWAS and variant-effect workflows [[NEEDS-CITATION: end-to-end GWAS agent and variant-effect agent papers requested by R2.9; no verified reference was available in the project files]]. These systems ask how much of an open-ended analysis an agent can work out for itself. We hold the analysis fixed and vary the plan and the hardware, so a head-to-head against Biomni would compare systems optimised for different objectives on a task neither was built for. We state that as a reason rather than declining silently, and note it is a judgement a reader may reject. <!-- addresses: R2.9, C5, T3.8 -->

Two comparators were available instead, and both are used: a human executing the identical Galaxy workflow manually on the same server, and the Galaxy Project's published run of 9 June 2026, in which eight frontier models acted as both planner and executor on the same RNA-seq data at $2.82–$131.83 per run. <!-- addresses: R2.9, C1, C5 -->

### What a lab needs to know to size hardware

Two properties of current open-weight models determine whether one fits on a given machine, and neither is captured by parameter count alone.

The first is dense versus sparse mixture-of-experts (MoE) architecture. A dense model uses every weight on every token, so per-token compute scales with the full model size. An MoE model splits most of its weights into parallel expert sub-networks and routes each token to a small subset, so per-token compute scales with the *active* parameter count while memory residency still scales with the *total*. On a bandwidth-limited board this inverts the intuition that bigger is slower. Measured on the same Jetson AGX Orin, a dense `gemma4:12b` occupying 7.6 GB generated at 14.4 tokens/s, while the MoE `qwen3.6:35b-a3b` occupying 23.9 GB with 3 B active parameters generated at 30.7 tokens/s — three times the residency, 2.1 times the throughput. MoE models trade memory, which is cheap to buy once, for speed, which is what makes an interactive agent loop tolerable. <!-- addresses: R2.3 -->

The second is the key–value (KV) cache, which holds the attention state for every token in the context and therefore grows with context length rather than with model size. Sizing it by extrapolation is unreliable, and we got it wrong before measuring. Assuming 19 GB of weights and a 6 GB KV cache at 16k tokens, scaling linearly, we projected 25, 31 and 43 GB at 16k, 32k and 64k context for one 27 B model. Measured residency was 25, 27 and 31 GB. The real decomposition is roughly a 23 GB base and about 2 GB of KV cache at 16k, so quadrupling the context added 6 GB rather than 18; grouped-query attention, which shares key and value projections across attention heads, accounts for most of the difference. On models using grouped-query attention, long contexts are therefore far more affordable than a naive projection suggests, and a 64 GB board comfortably holds a 27 B model at 64k context. <!-- addresses: R2.3 -->

The third thing worth defining before the Results is the anatomy of the loop itself, because the two benchmarks exercise different amounts of it. A tool-using agent loop consists of a prompt, a tool call, an observation of that call's output, an update to persistent state, an optional repair attempt when the observation indicates failure, and a termination decision. Benchmark 1 exercises the first stage only: the model receives a prompt and emits a script, which is executed and scored without the model ever seeing the result. Benchmark 2 exercises all six, and its failure modes are concentrated in the last three. <!-- addresses: R2.3, C1 -->

**Table 2.** Models evaluated in this study. All local models were served by Ollama at `q4_K_M` 4-bit quantisation. The plan-gradient matrix ran on the Jetson AGX Orin 64 GB at a 16,384-token context; benchmark 2 pinned the context to 65,536 tokens. Model cutoff for inclusion was 14 August 2026. The full May-2026 catalogue of open-weight model families, with its tutorial legend, is Supplementary Table S1.

| Model | Architecture | Total params | Active params/token | Measured resident | Role |
|---|---|---|---|---|---|
| `gemma4:26b-a4b-it` | sparse MoE | 26 B | 4 B | — | benchmark 1 |
| `gemma4:31b-it` | dense | 31 B | 31 B | — | benchmark 1 |
| `glm-4.7-flash` | — | — | — | — | benchmark 1 |
| `gpt-oss:20b` | sparse MoE | 20 B | — | — | benchmark 1 |
| `granite4.1:30b` | dense | 30 B | 30 B | — | benchmark 1 |
| `granite4.1:8b` | dense | 8 B | 8 B | — | benchmark 1 |
| `laguna-xs-2.1` | — | — | — | — | benchmark 1 |
| `nemotron-3-nano:30b-a3b` | sparse MoE | 30 B | 3 B | — | benchmark 1 |
| `nemotron-3-nano:4b` | dense | 4 B | 4 B | — | benchmark 1 |
| `qwen3.5:4b` | dense | 4 B | 4 B | — | benchmark 1 |
| `qwen3.6:27b` | dense | 27 B | 27 B | ~17 GB | benchmark 1, cross-platform arm |
| `qwen3.6:35b-a3b` | sparse MoE | 35 B | 3 B | 23.9 GB | benchmark 1; benchmark 2 MoE arm |
| `qwen3.8:27b` | dense | 27 B | 27 B | 19.6 GB | out-of-sample addition; benchmark 2 dense arm |
| `gemma4:12b` | dense | 12 B | 12 B | 7.6 GB | throughput measurement only |

[[NEEDS-NUMBER: measured resident size (`ollama ps`) for the ten models in Table 2 currently marked "—", plus total and active parameter counts for `glm-4.7-flash` and `laguna-xs-2.1` and the active-parameter count for `gpt-oss:20b`]] <!-- addresses: R2.2, R2.3, TEN1 -->

### Scope, study design, and what each benchmark can and cannot show

Six workflow classes account for most routine per-sample work in a sequencing laboratory (Table 3). Two of them were run here. The other four are named so that the boundary of the evidence is visible rather than implied.

**Table 3.** Candidate workflow classes for plan-conditioned execution. Plan complexity and I/O footprint are qualitative judgements except where a measured value is given for a class actually run in this study.

| Workflow class | Steps | Plan complexity | I/O footprint per sample | Run here |
|---|---|---|---|---|
| Alignment and variant calling | 8 workflow stages, 9 plan steps | moderate | small (16,569 bp reference; deeply downsampled paired-end reads) | **yes** (benchmark 1) |
| RNA-seq quantification and DE | 30 workflow steps (quantification only; DE not run) | moderate–high | large (20.5–30.1 M counted fragments per sample) | **partly** (benchmark 2: quantification) |
| Single-cell RNA-seq | — | high | large | no |
| De novo assembly | — | high | very large | no |
| Metagenomic profiling | — | moderate | large (reference database dominates) | no |
| ChIP-seq / ATAC-seq peak calling | — | moderate | moderate | no |

[[NEEDS-NUMBER: representative step counts and I/O footprints for the four workflow classes not run, if Table 3 is to carry numeric rather than qualitative entries]] <!-- addresses: R2.4, C2 -->

The plan gradient in benchmark 1 is exploratory, and we declare it so. The most detailed plan condition was written after observing how the leaner conditions failed, so the gradient is partly fitted to the failure modes it then measures. What was frozen before benchmark 2 began was the executor-selection rule, the two models that rule selected, the reasoning-off setting, and the hardware; those aspects of benchmark 2 are confirmatory with respect to benchmark 1. Plan sufficiency itself is not, on either benchmark, because the Galaxy plan was corrected eleven times while benchmark 2 ran. <!-- addresses: R3.5, R3.preamble -->

One confound the design cannot remove should be stated before any result rather than after. At the detailed end of the gradient, the plan contains near-executable command syntax, so a model that succeeds there may be transcribing faithfully rather than orchestrating. Benchmark 2 narrows this: the executor had to bind live server state and real dataset identifiers that appear in no plan. It does not eliminate it, and in two specific ways. After a harness transport bug, the input collection and the annotation were pre-built by a human and the corresponding plan steps became verification-only; and the decisive invocation step supplied a literal JSON body, so "8/8 parameters correct" measures faithful transcription of a supplied call rather than derivation of one. The experiment that would resolve the confound is a planner comparison at matched detail level — an expert-written plan, a second frontier model's plan, and a plan assembled from tool documentation, all held at the same syntactic detail. We did not run it. <!-- addresses: R3.preamble, R3.6, T3.2, T3.3, C2 -->
