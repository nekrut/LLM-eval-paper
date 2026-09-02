# Readability review of writeup_R2.md against the nekrutenko-style skill

Date: 2026-08-31. Method: mechanical metrics (revision/scripts/style_check.py) plus a paragraph-by-paragraph read of each section against the skill's ten-point checklist, with the reader test: would a biologist who has never seen this system understand each sentence on first read? Every proposed rewrite keeps every number and fact.

Mechanical result: 541 sentences, mean 21.4 words, median 21, 'we' in 17% of sentences, 0 banned terms, 0 bold spans in prose, 0 rhetorical questions. Sentence rhythm matches the corpus. Every finding below is therefore structural, a missing gloss, a buried verb, or a passage addressed to reviewers rather than readers.


# Abstract and Introduction

I've read the skill, the Abstract and Introduction (lines 1–35 of `/media/anton/disk1/git/LLM-eval-paper/writeup/writeup_R2.md`), and checked the Results and Methods only where I needed a fact to keep a rewrite honest. Findings are ranked by how hard a first-time biologist reader stumbles. Every rewrite keeps the numbers and facts as written; where a gloss draws on a fact stated elsewhere in the manuscript I say where.

## Verdict

The section reads as the author's own prose in rhythm and voice: 57 sentences at mean 22.4 words and median 21, "we" in 28% of sentences, colons doing the hinge work, limits stated flatly, and no banned openers. Where it fails the skill is section 2, explanation-first: the hardware paragraph and Table 1 are written for someone who already runs local models, and a biologist meets roughly fifteen undefined terms between them. The Abstract also runs 10 sentences against the skill's 4–6.

## Findings

**1. Intro para 5 (line 17), the whole paragraph — highest impact.**
Verbatim: "Key–value-cache memory grows linearly with context length and also depends on architectural quantities including layer count, key–value-head count, and head dimension; grouped- and multi-query attention reduce this cost relative to full multi-head attention (Table 1)."
Fails checklist 3 (eight undefined terms in one sentence: key–value cache, context length, layer, key–value head, head dimension, grouped-, multi-query, multi-head attention), checklist 2 (the paragraph ends on a fact with no consequence for the study), and the figure-pointer rule: Table 1 has no column for any of these quantities, so the pointer sends the reader to a table that cannot answer. Sentence 2 also uses "token", "experts", and "active parameters" without a gloss, and "open-weight" has never been defined. There is no bridge from the previous paragraph, so the reader does not know why hardware suddenly matters.
Rewrite:
> Whether an open-weight model — one whose weights can be downloaded and run on a machine of one's own — fits on a given machine depends on two properties that the parameter count alone does not capture. The first is how much of the model works on each token, the unit of text a model reads or writes one at a time. A mixture-of-experts (MoE) model is built from several sub-networks, its experts, and sends each token through only a few of them, so its compute per token is governed primarily by the parameters in the experts that fire (the active parameters), whereas weight residency — the memory the loaded weights occupy — is governed by the total parameters. The second is the key–value cache, the working memory in which the model keeps a record of every token in its context, that is, the text it has been given plus the text it has produced so far. This cache grows linearly with the length of that context and also depends on the model's architecture: how many layers it has, how many key–value heads each layer carries, and how wide each head is. The grouped- and multi-query variants of attention share key–value heads across query heads and so keep the cache smaller than full multi-head attention does. [Closing consequence needed; candidate for the author to confirm: These two quantities, rather than the headline parameter count, set which models fit in the Jetson's 64 GB of memory shared between CPU and GPU (Methods), and Table 1 lists the models on which we measured them.]

Drop "(Table 1)" after the attention sentence, or point to the supplementary table that actually tabulates architecture.

**2. Table 1 (lines 19–28): Role column and caption.**
Verbatim (Role column): "error matrix", "out-of-sample addition", "benchmark 2 dense arm", "MoE arm", "throughput measurement only", "frontier reference gradient". None of these labels has been defined anywhere before the table; "error matrix" first gets a meaning at line 240 of Results. Fails checklist 3 and 9 (label-code stack in place of prose).
Verbatim (caption): "the full list, with digests, declared context lengths, and per-model default decoding parameters" — to a biologist "digests" means restriction digests. "Local models were served by Ollama at 4-bit quantisation" — Ollama is unglossed, and "quantisation" is never tied to the Abstract's "compressed to 4-bit precision". "filling that column costs roughly six minutes of cold load per model" — refers to a column the previous sentence says does not exist, and "cold load" is undefined.
Also a factual inconsistency the reader will catch: the caption says "36.0 B (`qwen3.6:35b-a3b`)" while the table row for the same model says "35 B". I did not change either; the author needs to reconcile them.
Rewrite (caption):
> **Table 1.** The four local models on which we measured weight residency, plus the API models. The table is a selection, not a catalogue: fourteen local models appear in this study, and the full list — with file digests (checksums that identify the exact model file), declared context lengths, and each model's default decoding settings — is Supplementary Table S8. Ollama, the program that served the local models, ran every one of them at 4-bit quantisation (the 4-bit compression noted above), but in two formats: `gpt-oss:20b` ships in MXFP4, and every other local model in `q4_K_M`. The table carries no residency column because our own residency figures for one of these models do not reconcile; every residency measurement we made, with the discrepancy stated inline, is in Supplementary Table S4. We measured residency for four of the fourteen models and not for the other ten, because each measurement costs roughly six minutes to load the model from disk into memory (a cold load), and we neither ran those loads nor estimated a figure in their place. Declared parameter counts span 4.0 B (`nemotron-3-nano:4b`) to 36.0 B (`qwen3.6:35b-a3b`).

For the Role column, replace each code with the plain phrase the Introduction has already used, for the author to confirm the mapping: "benchmark 1 plan series; injected-failure runs" for "error matrix", "added after the main series; benchmark 2, dense model" for "out-of-sample addition; benchmark 2 dense arm", "benchmark 2, mixture-of-experts model" for "MoE arm", "speed measurement only" for "throughput measurement only", and "commercial reference set for benchmark 1" for "frontier reference gradient".

**3. Abstract, sentence 3, and the model count.**
Verbatim: "Twelve open-weight models, compressed to 4-bit precision so that they run on a single local machine, and three commercial API models each received one prompt and returned one shell script, with no feedback loop."
Fails section 1 rules 1 and 2: the subject is split by a nested participial clause and the main verb "received" arrives at word 22. "Open-weight" is undefined. Four sentences later the count becomes "eleven of thirteen local models" with no explanation; the thirteenth is `qwen3.8:27b`, the addition after the main series (line 134).
Rewrite:
> Twelve open-weight models — models whose weights can be downloaded and run locally — and three commercial API models each received one prompt and returned one shell script, with no feedback loop; the local models were compressed to 4-bit precision so that they run on a single local machine.
and later: "eleven of thirteen local models (the twelve above plus one added after the main series) copied the plan's stale path and failed".

**4. Intro para 7 (line 34): who wrote the detailed plan, and the name of the copying measure.**
Verbatim: "we wrote the most detailed plan after we had observed failures" followed by "The meta-prompt that produced it requests every flag". The reader is told we wrote the plan and then that a meta-prompt produced it; Methods (line 69) says a planner model wrote each plan from prompts we supplied. "Meta-prompt", "executor", and "transcription" are all undefined here. "A token-recall index gives an indirect measure" names a thing Results never call by that name; Results define "a transcription index: the token-level recall ... of the 90 literal command tokens of plan v2" (line 172). And "Two limits apply to all results" is followed by First, Second, and then a third item that is specific to benchmark 1, which is better as its own paragraph.
Rewrite (from "The detailed plan also"):
> The detailed plan also carries a confound of its own. A planner model wrote it from a prompt we supplied (the meta-prompt), and that prompt asks for every flag with its exact value and tells the planner that an executor — the model that turns the plan into a script — will copy the commands into a shell script; success with this plan can therefore include direct transcription, that is, copying the plan's commands verbatim. We measured transcription in two ways: indirectly, as the fraction of the plan's literal command tokens that reappear in each script, which we call the transcription index (Results, *How much of the plan the models copy*), and directly, by the moved-path test described above (Results, *Moving one path separates transcription from binding*). Results below present the plan series for benchmark 1, then the copying and repair tests, then the Galaxy case study.

Change "we wrote the most detailed plan" to "we had the most detailed plan written" (confirm against Methods).

**5. Intro para 4 (line 15): one paragraph doing three jobs, with jargon in each.**
Fails checklist 1–2 as a unit (harness definition, then benchmark 1 has no harness, then prior agent benchmarks, then benchmark 2 comparators; the last sentence has no relation to the first) and checklist 7 in two places. Specific stumbles:
- "nothing in our results is known to be harness-independent" (double negative). Rewrite: "We compared none of them, so we cannot say whether any result here would survive a change of harness."
- "For benchmark 2 we used `galaxyproject/loom`, for deployment reasons given in the Supplement." Unglossed name, reason deferred. Rewrite: "For benchmark 2 we used `galaxyproject/loom`, a harness through which the model reaches a Galaxy server, chosen for the deployment reasons given in the Supplement."
- "Benchmark 2 was added to supply the missing loop." Passive. Rewrite: "We added benchmark 2 to supply the missing loop."
- "evaluates open-ended tool-using research agents against task suites". Rewrite: "The closest bioinformatics work scores tool-using agents — models allowed to call software as they work — on suites of open-ended research tasks (Huang et al. 2025; Mitchener et al. 2025; Su et al. 2025; Mehandru et al. 2025)."
- "two external comparators, both used with their protocols stated" is opaque. Rewrite: "Benchmark 2 has two external points of comparison, and we state the protocol behind each."
- "eight frontier models" and "is not a frontier control". Rewrite: "Second, eight frontier models — the most capable commercial models available at the time — acting as both planner and executor on the same data cost $2.82–$131.83 per run (Nekrutenko 2026). That source is a post by the present author, with plans that were never published and no replicate runs; it bounds what the API route costs and is not a controlled comparison against those models."
Split the paragraph before "The closest bioinformatics work".

**6. Abstract, sentence 8.**
Verbatim: "Shown the failed script and its error message, with up to three attempts, three of the eleven copying models repaired the path in at least two of three seeded repetitions; eight never did."
Fails section 1 rule 1 (subject arrives after two fronted phrases) and checklist 3 ("copying models", "seeded repetitions" — a biologist does not know what a seed is here).
Rewrite:
> We then gave each of the eleven models that had copied the stale path up to three attempts, showing it after each failure the script it had written and the error the script produced: three of the eleven repaired the path in at least two of three repetitions (each started from a different random seed), and eight never did.

**7. Intro para 6 (line 32).**
Verbatim: "alignment and small-variant calling, at 7 measured plan steps, and RNA-seq quantification, at 30 measured workflow steps." Two different terms ("plan steps", "workflow steps") for what may be one concept, and "measured" is ambiguous (counted? scored?). The author should say what was measured and use one term if it is the same thing. Candidate: "alignment and small-variant calling, whose plan has 7 steps, and RNA-seq quantification, whose Galaxy workflow has 30 steps."
Verbatim: "Four further classes cover most of the remaining routine per-sample work—single-cell RNA-seq, de novo assembly, metagenomic profiling, and ChIP-seq or ATAC-seq peak calling—and we ran none of the four." The dash gloss is separated from the noun it glosses, so it briefly reads as a gloss of "work" (section 7). Rewrite: "Four further classes — single-cell RNA-seq, de novo assembly, metagenomic profiling, and ChIP-seq or ATAC-seq peak calling — cover most of the remaining routine per-sample work, and we ran none of the four."
Verbatim: "no invocation for an executor to transcribe" and "The plan-sufficiency result is therefore conditional". Three undefined compounds. Rewrite: "There is thus no canonical value for a plan to carry and no command line for an executor to copy. The finding that a sufficiently detailed plan lets the local models succeed is therefore conditional on tasks with no data-dependent parameter choices, and it may be in part a restatement of the criterion by which we selected the tasks (Supplementary Table S19)."

**8. Intro para 1 (line 9).**
Verbatim: "We tested fixed sets of models on one local machine, an NVIDIA Jetson AGX Orin, and through one commercial API." The appositive sits between two coordinated phrases, so the sentence reads as a three-item list, and a biologist does not know what a Jetson is. Rewrite (the 64 GB figure is from Methods, line 86): "We tested a fixed set of models in two settings: locally, on one NVIDIA Jetson AGX Orin, a compact computer with 64 GB of memory shared between its CPU and GPU, and remotely, through one commercial API."
Verbatim: "The study did not test analysis design and did not measure human time. Neither benchmark achieved unsupervised operation." Not we-led (checklist 7), and a benchmark cannot achieve operation. Rewrite: "We did not test whether a model can design an analysis, and we did not measure the human time involved; in neither benchmark did the models run the workflow unsupervised."
Minor, style only: section 4 asks for a citation on sentence 1 and a "However"/"Yet" puncture by sentence 2–3; the paragraph has neither.

**9. Intro para 2 (line 11), last two sentences.**
Verbatim: "Benchmark 2 tested some parts of binding (Results, *Case study*). A second test moved one reference path, described the move to the model, and thereby examined path binding directly". "A second test" collides with "benchmark 2" in the reader's count, the test is not we-led, and "path binding" is a new compound one sentence after "binding" was defined.
Rewrite: "Benchmark 2 exercised binding only in part (Results, *Case study*), so we also tested it directly: we moved one reference file, told the model where it now was, and checked whether the script used the new location, which two of thirteen local models did (Results, *Moving one path separates transcription from binding*)."

**10. Intro para 3 (line 13).**
Verbatim: "The separation we tested is the one workflow systems already embody." The separation has not been named. Rewrite: "The separation we tested — a plan written once, and its execution done separately against each new set of inputs — is the one workflow systems already embody."
Verbatim: "several methods built on the same split, including plan-and-solve prompting, least-to-most decomposition, ReAct, HuggingGPT, graph dispatch, and Reflexion". Six names with no shared gloss; "graph dispatch" is a description, not a method name, so the reader cannot even look it up. Rewrite: "several methods built on the same split between deciding what to do and doing it, including ...". Also "measure this design" → "measure how well this design works on genomic workflows".

**11. Abstract, sentences 4, 6 and 7.**
Sentence 4: "the API models succeeded with a short plan containing no commands, whereas the local models reached 34 of 36 correct runs" — checklist 6, one side of the comparison has no number. The v1 row of the Results table (line 162) reads 1.000 (n = 9) for the API column, so "succeeded in 9 of 9 runs" if the author confirms that is the intended cell.
Sentence 6: "the same command in a non-runnable form" — undefined, and Results never use the phrase; the plan row at line 80 says the command was "extracted mechanically from the Galaxy IUC tool registry". Rewrite: "a command written out so that the model could paste and run it raised success, whereas the same command copied mechanically from a tool registry, in a form the model could not run as written, did not; removing the explanatory prose changed nothing we could detect."
Sentence 7: purpose clause plus dash gloss delay "we moved" to word 19 (section 1 rule 2). Rewrite: "We also asked whether a model binds a plan — connects its commands to the inputs actually on disk — or merely copies it: we moved the reference genome to a new path, left the plan's old path in place, and stated the new path in the input listing, and eleven of thirteen local models copied the plan's stale path and failed while two used the stated path and succeeded."

**12. Title (line 1), lowest impact but first thing read.**
"most local 4-bit executors tested transcribe a detailed plan; two of thirteen bind it" — to a biologist "transcribe" is RNA synthesis and "bind" is molecular binding, and "executors" is undefined. If the author wants plain words: "In a single pass, most local 4-bit models copy a detailed plan; two of thirteen connect it to the files on disk."

## Things I checked and did not flag

No banned openers, no bold spans outside the table caption label, no three-consecutive-short-sentence runs, and hedges are single and name their uncertainty. Short sentences are 9 of 57 (16%, above the 8–12% band), but each sits in a legal position (pivot or verdict), so I did not count them as a problem. Numbers other than the 36.0 B / 35 B mismatch are internally consistent (12 gradient models × 9 = 108 runs; 12 × 3 seeds = 36; 11 + 2 = 13).

# Methods

I have everything I need; no further lookups are required. Here is the review.

# Readability review: `writeup_R2.md`, Methods (lines 36–123)

Sentence statistics for the 117 Methods sentences are on target (mean 22.3, median 22; 9 over 35 words, 1 over 45, 11 at or under 10 words, no run of three short sentences), so §1's numbers and checklist item 5 pass throughout. Items 8 and 9 also pass: no banned openers, no bold-led prose, no bullet stacks. The problems are almost all item 3 (undefined coined terms), item 4 (one nested gloss), item 7 (choices without reasons), item 1 (one announcing opener), and a class the checklist does not name but the reader test catches: revision-process language that means nothing to a reader of the published paper. Ranked by damage to a first-time reader:

## 1. "Track A" and "Track B" are used four times before they are defined (highest priority)

(a) Study design, para 2 (line 63); then line 69, Table 2 row 1, and line 84. The only gloss is at line 96, 33 lines later.

(b) "The nine combinations represent seven plan conditions, because Track B occurs three times."

(c) Item 3. "Track" is never defined at all; the reader meets "9 plan-file and track combinations" and then a sentence whose logic (why would a condition "occur three times"?) depends on knowing that Track B is a prompt template with no slot for a plan file, so three nominal plan files collapse to one condition. That mechanism is only stated at line 84, and even there the template mechanism is implied rather than said. The reader also has to reconcile 9 combinations, 7 conditions, and the "eight conditions" of line 69 with no help.

(d) Replace the first two sentences of the paragraph with:

> The initial benchmark-1 design comprised 324 local generations and 81 API generations: 12 local executors and 3 API executors, crossed with 9 combinations of plan file and track, at 3 seeds each. A track is the prompt template the executor received: under Track A the template carries the plan file, and under Track B it carries only the problem statement and the tool inventory, so a Track-B run is a no-plan run whichever plan file was named on the command line. Three plan files were named in Track-B runs, and the nine combinations therefore represent seven plan conditions: six plan files under Track A and one no-plan condition pooled from the three Track-B runs.

Line 96 then needs only "(plan v2, Track A, reasoning off)", which also removes finding 4.

## 2. Revision-process language addressed to reviewers, not readers

(a) Line 86 (hardware paragraph), line 96 (ten-seed paragraph), line 100 (moved-path paragraph).

(b) "so all claims of reproducible sampling have been removed"; "After the second review cycle we likewise raised the three discriminating conditions"; "We added one condition after the second review cycle to separate transcription from binding directly".

(c) Reader test. A biologist reading the published paper has never seen a review cycle and does not know what claims were "removed" from what. The sentence at line 96 also drops the reason for raising those three conditions (item 7); the Supplement (line 420) gives it: they carry the mechanism argument.

(d)

> Neither the local seed nor the API run identifier gives bitwise determinism, so we make no claim that any run can be reproduced bit for bit.

> We later raised three further conditions — v1g, v1.25 and v1.5, Track A, reasoning off — to ten seeds per model across thirteen local executors, because those three carry the mechanism argument and three seeds could not separate them.

> We added one further condition, after the gradient had been run, to separate transcription from binding directly: copying the plan's command lines as written, against binding them to the inputs stated in the prompt.

## 3. The counting paragraph uses seven nouns for overlapping units and leaves the 848 unexplained

(a) Study design, para 2 (line 63). Mean 17.9 words per sentence here, well under the document mean: a list of one-fact sentences of the kind §1 warns against.

(b) "Ten released logs contain 848 cells — a cell is one executor, plan condition and seed — and 75.27 h of generation. API calls account for 81 cells and 1.55 h (Supplementary Tables S1–S2). Three later passes, which sit outside the 848-cell ledger, add 351 local cells."

(c) Items 3 and 4, reader test. "Generations", "cells", "runs", "passes", "blocks", "logs" and "ledger" all appear within twelve sentences with no statement of how they relate. The design just described sums to 405, so the reader immediately asks what the other 443 cells are, and the paragraph never says; Supplementary Table S1 shows they are the reasoning-on arm, the v2 repeated-sampling seeds, the `qwen3.8:27b` runs, and the budget and effort sweeps, none of which Methods mentions. "Seed" is also never glossed; its only explanation is the negative one at line 86.

(d)

> Ten released logs contain 848 cells and 75.27 h of generation, a cell being one executor, one plan condition and one seed — the random-number setting that makes repeated draws from the same model differ. The 848 comprise these 405 gradient cells together with the reasoning-on, repeated-sampling, out-of-sample and budget and effort blocks itemised in Supplementary Table S1; API calls account for 81 cells and 1.55 h (Supplementary Tables S1–S2). Three later passes sit outside the 848-cell ledger and add 351 local cells.

Also in this paragraph, "The repair log has one duplicate skipped row" names the third pass by a label the reader has not been given; "The log of this three-attempt pass has one duplicate skipped row" is the same fact. And "We discarded 400 earlier runs because they used a `q8_0` key–value cache" gives a label as a reason (item 7); the Supplement's service environment shows the retained runs used `OLLAMA_KV_CACHE_TYPE=f16`, so: "because they were generated with the key–value cache quantised to 8 bits (`q8_0`) rather than the 16-bit cache used for every retained run".

## 4. Nested gloss inside a parenthesis, and "seeds per cell" contradicts the definition of a cell

(a) Ten-seed paragraph, line 96, sentences 1–2.

(b) "The full gradient was run at n = 3 seeds per cell. The headline condition (plan v2, Track A — the arm whose prompt carries the plan file, where Track B carries none — with reasoning off) was raised to n = 10 by adding seven seeds and pooling."

(c) Item 4 (§1 rule 3: a clause interrupting another clause mid-phrase — a dash pair inside a parenthesis, with a subordinate "where" clause inside the dashes) and item 3. Line 63 defined a cell as one executor, one condition and one seed, so "3 seeds per cell" is a contradiction on the paper's own terms; the reader who trusted the definition stops.

(d) With finding 1 applied:

> We ran the full gradient at three seeds per executor–condition pair, and raised the headline condition (plan v2, Track A, reasoning off) to ten seeds by adding seven and pooling.

## 5. "reasoning off" is never defined, and appears under three names

(a) First use line 92 ("reasoning-off"), then line 96 ("reasoning off"), line 110 ("reasoning suppressed"). The gloss exists only in Results at line 238 ("letting a model emit a chain of thought before its script").

(b) "On the 324 local reasoning-off cells it takes only 0.0 and 1.0; on the frontier arm it does not."

(c) Item 3. A biologist does not know that these models have a switchable chain-of-thought mode, and the three spellings read as three different settings.

(d) At line 92, reusing the document's own later gloss:

> On the 324 local cells run with reasoning off — the model's option to emit a chain of thought before writing its script disabled — M3 takes only the values 0.0 and 1.0; on the frontier arm it does not.

Then "reasoning off" everywhere, including line 110.

## 6. The error-injection paragraph names its apparatus without the mechanism, and has no claim

(a) Line 94, whole paragraph.

(b) "We injected tool failures with PATH shims applied only to the targeted tool, so the generated script saw nothing but ordinary exit codes, stderr and output files. Each executor–plan combination comprises 39 cells: 8 pattern–target combinations injecting a true error × 3 seeds, 4 injecting no error × 3 seeds, and 3 uninjected controls."

(c) Items 1, 3, 6, 7. "PATH shim", "pattern" and "target" are all undefined; the paragraph never says why failures were injected; the error matrix itself was never introduced in Study design; and "a third of the injected matrix" carries no denominator (the 12 never appears). The Supplement (line 150) has the mechanism.

(d)

> To test whether a generated script survives a tool failing beneath it, we injected failures with PATH shims: before each cell the harness wrote a short wrapper named `bwa` or `lofreq` into a directory placed first on `PATH`, so the shell ran the wrapper instead of the real tool, and the wrapper failed in a chosen pattern while the script saw nothing but ordinary exit codes, stderr and output files. Each executor–plan combination comprises 39 cells: 12 pattern–target combinations — a pattern is the failure behaviour, a target the tool the wrapper replaces — at 3 seeds each, of which 8 inject a true error and 4 do not, plus 3 uninjected controls. Two of the seven patterns do not inject an error at all — `slow_tool` sleeps 30 s and then succeeds, and `stderr_warning_storm` emits 200 warnings and then succeeds — so 4 of the 12 injected combinations (a third) test latency and log-noise tolerance, not recovery.

## 7. Benchmark 2 serving sentence: five stacked phrases, three undefined terms

(a) Line 110, sentence 1 and sentence 3.

(b) "Both executors ran on one Jetson AGX Orin 64 GB, with reasoning suppressed, under `galaxyproject/loom`, with Galaxy reached over MCP and `notebook.md` serving as durable inter-session state." / "Its seven steps ran from importing the workflow by TRS identifier to reporting the per-sample counts."

(c) Item 4 (§1 rule 4: undefined terms in a long sentence) and item 3. "MCP", "durable inter-session state" and "TRS identifier" are never glossed anywhere in the document.

(d)

> Both executors ran on one Jetson AGX Orin 64 GB with reasoning off, under the `galaxyproject/loom` harness, which reached Galaxy through MCP — the Model Context Protocol, a standard interface through which a model calls external tools — and kept a `notebook.md` file as the executor's memory from one session to the next.

> Its seven steps ran from importing the workflow by its identifier in the GA4GH Tool Registry Service (TRS) to reporting the per-sample counts.

## 8. The moved-path condition has four names, and the heading's name is wrong

(a) Heading at line 98 and paragraph at line 100; also line 63 and Table 7.

(b) "### The perturbed-plan condition" followed by "The plan is v2 verbatim, not one character changed." Elsewhere the same condition is "the moved-path condition" (line 63), "the moved-path test" (Introduction), and "the moved-reference condition" (Table 7).

(c) Item 3 and reader test. The heading says the plan was perturbed; the second sentence says it was not; the reader cannot tell whether this is the condition already described at line 63. In the same paragraph, "The sandbox holds the same four read pairs" uses "sandbox" two paragraphs after line 88 said the local arm has no sandboxing.

(d) Heading: "### The moved-path condition". Opening sentence as in finding 2. Replace "The sandbox holds" with "The working directory holds". Use "moved-path" in Table 7's caption as well.

## 9. An announcing opener

(a) Line 112, sentence 1.

(b) "One change belongs in Methods because it changed the design."

(c) Item 1: the sentence orients rather than claims.

(d)

> We rewrote the step-7 verification file while benchmark 2 ran, because its original version stated its own expected values and so let an executor that never opens a dataset verify by recitation. The rewritten file states no expected values and sanctions `UNAVAILABLE`. The general rule follows: any agent evaluation that places the expected answer in the task description cannot distinguish execution from recitation.

## 10. The cost model is never introduced, and "the model" flips meaning

(a) Line 118, sentences 1, 3 and 6.

(b) "Two of the cost model's eight inputs are measured." / "7.8 h recorded for the block at run time" / "The model reports a like-for-like annualised comparison".

(c) Items 1 and 3. Nothing before this paragraph says a cost model exists or what it compares; "the block" is unspecified; and "the model" has meant a language model in every other sentence of the paper.

(d)

> We built a cost model comparing annualised local and API spending from eight inputs, of which two are measured. […] The cost model uses 86.7 s per run — 7.8 h recorded at run time for the 324-cell local block, including model loading, execution and scoring — but that block figure was not archived and is carried as a stated input, not a verifiable measurement. […] The cost model reports a like-for-like annualised comparison, with an API-side labour term exposed rather than set to zero.

## 11. The data-governance boundary is never said in plain terms, and 315 appears from nowhere

(a) Line 120.

(b) "The plan-then-execute split also defines a data-governance boundary, and it was respected by the planner role only. The frontier executor arms — 315 API cells in all — transmitted the executor prompt".

(c) Items 3 and 6. The Figure 1 caption names the boundary but never says what may and may not cross it; the reader was told 81 API cells at line 63 and now meets 315 with no derivation (Supplementary Table S3 gives 81 + 234).

(d)

> The plan-then-execute split also defines a data-governance boundary — the plan may leave the machine, the sample data and subject labels may not — and only the planner role respected it. The frontier executor arms — 315 API cells in all, 81 in the reference gradient and 234 in the error matrix — transmitted the executor prompt, which carries the dataset manifest with this study's own subject labels.

## 12. Execution paragraph: an unnamed "five channels" and an undefined attack

(a) Line 88, last two sentences.

(b) "Attacker- or accident-controlled text reached the executor through at least five unsanitised channels. No indirect-prompt-injection test was run."

(c) Item 9's spirit (abstract count in place of concrete things) and item 3. The five are listed only in the Supplement (line 134); "indirect prompt injection" is never explained. "PATH-restricted inventory" earlier in the paragraph is also unglossed.

(d)

> Text that an attacker or an accident could control reached the executor through at least five channels that nothing sanitised, listed in the Supplement, and we ran no test of whether such text could steer the model — an indirect prompt injection.

And earlier: "only the wall-clock kill, the tool inventory restricted through `PATH` and the working directory are enforced".

## 13. Serving parameters glossed by name only, temperature without a reason

(a) Line 86.

(b) "served by Ollama 0.32.5 at `temperature = 0.2` with `num_ctx = num_predict = 16384`" and "leaving `top_k` and `top_p` at each model's own defaults".

(c) Items 3 and 7. `num_ctx`, `num_predict`, `top_k` and `top_p` are flags without meaning to a biologist, and 0.2 is a choice with no reason anywhere in the manuscript or Supplement; that reason has to come from the author.

(d) Gloss only, reason to be supplied:

> All local generations were served by Ollama 0.32.5 at `temperature = 0.2`, with the context window and the maximum output both set to 16,384 tokens (`num_ctx = num_predict = 16384`). […] the harness overrode only `temperature`, leaving `top_k` and `top_p` — the two settings that limit how many candidate tokens the sampler may draw from — at each model's own defaults.

## 14. Smaller stumbles, each a one-phrase fix

- Line 92: "the tolerant Jaccard overlap" — gloss once: "the Jaccard overlap (variants shared by call set and answer key, divided by the variants in either)".
- Line 96: "treating the missing cell as a failure gives 31/127 for v1g" — item 6, the counterpart is missing: "gives 31/127 rather than 31/126 for v1g".
- Line 108: "substituted at matched parameter count after the rule was fixed" — "fixed" reads as "repaired"; the Supplement (line 174) has the reason: "substituted at matched parameter count because it was released on 14 August 2026, after the rule was frozen and benchmark 1 was complete".
- Line 114: "The fabrication incident was a single observation" — tie it to the event the reader just met: "That fabricated failure report was a single observation". Same paragraph: "six, 20%, produced no answer" — "six of 30 (20%) produced no answer"; and "the excluded class is structurally the one the original incident belongs to" — "and the excluded class — launches that produced no answer — is the very class the original incident belongs to".
- Line 69: "the Galaxy IUC tool registry" — gloss: "the Galaxy community's tool-wrapper registry (IUC, tools-iuc commit `39e7456`)". Same paragraph, "prompt-template variants that substitute no plan file" is the only statement of the template mechanism; finding 1's rewrite makes it explicit.
- Line 67: "with nine truth variants per run" — "per sample" or "per run"? The reader cannot tell which; state the intended unit.
- Document-level, inherited from the Introduction (line 15): "frontier" is never glossed anywhere. One parenthesis at its first Methods use — "the frontier (commercial API) executor arms" — would close it.

**Verdict:** the Methods are already in the author's register and hit every sentence-length target, but a biologist meeting this system for the first time is stopped at least four times in the first two paragraphs by undefined coinages (track, cell, seed, the 848) and later by reviewer-facing phrases and three undefined interface terms; fixing findings 1–8 would make the section readable on first pass without changing a single number.

# Results

I have what I need: the skill, the pre-Results text (so I know which terms Methods already glosses), the Results section, and a mechanical pass. The mechanical numbers first, because they shape the verdict: 266 sentences, mean 20.3 words, median 20 (target 20–23); 12.8% of sentences at ≤10 words (target 8–12%, marginally high); no run of three consecutive sentences under 12 words; only 2.3% of sentences over 35 words (the allowance is 10%, so the prose is if anything on the short side, not the long side); one banned word ("essentially"); "we" leads about 14% of sentences (target ~20%). So the rhythm is already right. The failures are almost all rule §2 (explanation before naming) plus a handful of denominators, comparisons missing one side, and reviewer-facing asides that a reader of the final paper cannot parse.

Findings, ranked by how much they hurt a first-time reader. Every rewrite keeps the numbers and facts as written; where a gloss needs a fact I do not have, I bracket a note for the author.

## Tier 1 — the reader cannot follow without outside knowledge

**1. Injected-failure categories are never defined.** (Subsection *Injected failures*, para 1 sentence 2; para 2; Figure 4 caption.)
(b) "the 24 cells containing a true tool failure produced 15 crashes, 6 propagated errors, and 3 recoveries" — and later "recover 9 and partial 15", a fourth category never introduced.
(c) Checklist 3 / §2. "Crash", "propagated error", "recovery" and "partial" are the scorer's categories; nowhere in Methods or Results does the text say what the script did in each case. A biologist cannot tell a crash from a propagated error.
(d) "For `qwen3.6:27b` with plan v2, we sorted the 24 cells containing a true tool failure by what the script did when the tool failed: in 15 it crashed, stopping at the broken step with nothing produced downstream; in 6 it propagated the error, running on past the broken step so that later steps consumed a missing or malformed file; and in 3 it recovered, detecting the failure and still producing the correct call set (Figure 4)." [Author: check the three glosses against the scorer's definitions in Supplementary Table S6, and gloss "partial" at its first use in para 2.]

**2. "Seed" is never glossed anywhere in the manuscript, and Results leans on it from the first figure.** (Figure 2 caption "n = 3 seeds per cell"; then "3/3", "0/3", "three seeds per model", "8 of the 33 seeds" throughout.)
(c) Checklist 3. A biologist reads "seed" as a random-number seed at best, and has no way to know that one seed is one independent script from the same prompt — which is the whole meaning of "3/3".
(d) In *The two executor classes diverge* para 1, sentence 2: "We ran every executor against the plan gradient, from no plan at all to a plan spelling out every command, three times per condition with a different random seed each time, so that each 3/3 or 0/3 below is three independent scripts from the same prompt (Figure 2, Table 3)."

**3. Three unexpanded acronyms open the case study.** (*Case study*, para 2 sentence 1.)
(b) "Given the plan and a live MCP connection to usegalaxy.org, both local executors imported the 30-step IWC `rnaseq-pe` workflow by TRS identifier"
(c) Checklist 3. MCP, IWC and TRS are never expanded in the paper. Methods says only "with Galaxy reached over MCP".
(d) "Given the plan and a live connection to usegalaxy.org — made over MCP, the Model Context Protocol, which exposes the server's operations as tools the model can call — both local executors imported the 30-step `rnaseq-pe` workflow maintained by the Intergalactic Workflow Commission (IWC), fetching it by its Tool Registry Service (TRS) identifier, and both verified the six paired-end inputs and the annotation."

**4. Two sentences name a statistical mechanism instead of narrating it.** (*Injected failures*, para 2.)
(b) "The identical distribution obtained for the frontier executor is a degeneracy, not a parity finding." and "The model term is not zero everywhere."
(c) Checklist 3 and 4. "Degeneracy", "parity finding" and "model term" (ANOVA language, which collides with "model" meaning the language model) tell the reader nothing about what was observed.
(d) "The frontier executor produced exactly the same split, and that identity shows that the injected fault, not the executor, fixed the outcome; it does not show that the two executors are equally capable." and "The executor does matter under some plans."

**5. A subsection title built from three coinages, and an opening sentence that repeats them.** (*The conventional metrics are not degenerate*, title and para 2 sentence 1.)
(b) Title: "The conventional metrics are not degenerate: recall without the exit-status rule sits above run-level success". Para 2: "The recall curve computed without the exit-status rule sits above the run-level success curve at every lean condition, and the excess is real biology".
(c) §4 (titles are full findings in the reader's terms) and checklist 3. "Exit-status rule" is defined only in Methods and only as a property of `score_run.py`; "degenerate" and "lean condition" are house shorthand. The mechanism arrives only in para 2 sentence 6 ("a pipeline that exits non-zero has not finished").
(d) Title: "Per-variant recall exceeds the proportion of successful runs, because some failed runs called variants correctly". Para 2 opener: "When we count variants from the VCFs a run left on disk, ignoring the rule that a run exiting non-zero scores 0, recall at every thin-plan condition exceeds the proportion of runs scored as successes, and the excess is real biology: variants correctly called by runs the run-level metric scores 0."

**6. The transcription index is defined by its statistic, not its mechanism, and the word "directly" contradicts the Introduction.** (*How much of the plan the models copy*, para 1.)
(b) "To measure copying directly, we defined a transcription index: the token-level recall, in an emitted script, of the 90 literal command tokens of plan v2, after normalising the sample placeholder and the thread count."
(c) §2 mechanism before name; checklist 3 ("token-level recall", "sample placeholder", "normalising"). The Introduction says this index "gives an indirect measure" and the moved-path test "a direct measure", so "directly" here reverses the paper's own framing.
(d) "To measure copying, we split the command lines of plan v2 into their 90 literal tokens — tool names, flags, values and paths — and counted the fraction of them that reappear in each emitted script, treating any sample name as matching the plan's `{sample}` placeholder and any thread count as matching the plan's 4. We call this fraction the transcription index; it is an indirect measure, because it counts shared tokens and not whether they were used correctly."

**7. "Reasoning disabled/off" is used from Figure 2 onward but glossed only five subsections later.** (Figure 2 caption, Table 3 caption, Table 4 caption, and passim; the gloss "letting a model emit a chain of thought before its script" appears in *Enabling reasoning*.)
(c) Checklist 3.
(d) Figure 2 caption: "Plan gradient with reasoning disabled — the model writes its script directly, with no chain of thought first — on the Jetson AGX Orin, n = 3 seeds per cell."

**8. The generational comparison appears with no setup and in statistics shorthand, then closes with an editing note.** (*The n = 3 headline*, sentences 6–7.)
(b) "The out-of-sample pair `qwen3.8:27b` against `qwen3.6:27b` is underpowered rather than null: 8 of 27 matched cells are discordant, splitting 6 to 2 in favour of the *older* model (p = 0.29). We have therefore removed the generational framing from the abstract and the conclusion."
(c) Checklist 3 and 1. The reader has not been told that `qwen3.8:27b` is the newer release of `qwen3.6:27b`, so "generational" and "older" have no referent; "underpowered rather than null", "matched cells", "discordant" are unglossed; and the second sentence describes a manuscript edit, meaningless to a reader who never saw the earlier draft.
(d) "We had also asked whether `qwen3.8:27b`, the newer release of the same family, outperforms `qwen3.6:27b`. It does not on this evidence, and the evidence is thin rather than null: of 27 cells (plan condition × seed) run with both models, 19 gave the same outcome and 8 differed, and the older model won 6 of those 8 (p = 0.29). We therefore make no claim about model generation."

## Tier 2 — stumbles the reader can recover from, but should not have to

**9. Reviewer- and revision-facing sentences in the reader's text.** Five places; all fail checklist 1/2 because they describe the manuscript's history rather than a finding.
- *Moving one path*, para 3: "Reviewer 2's objection — that the headline result rewards pasting — is therefore confirmed for most of the model class, as a measurement rather than a concession." → "The headline result therefore rewards pasting for eleven of the thirteen models, and we say so as a measurement rather than a concession."
- *How much of the plan*, last sentence: "We ran that condition after the second review cycle; it is the next section." → "That condition is the next section."
- *Injected failures*, para 3: "replacing the claim that no destructive or escape behaviour was observed with a measurement" → "We also audited the 1,039 archived `run.sh` files word by word for destructive or sandbox-escaping actions, so that what follows is a count rather than an assurance."
- *Case study*, para 4: "That is why we use the count here and not in the Introduction, Discussion or Conclusion, which say 'repeated human correction' instead." → "We therefore give the count only here; elsewhere we say 'repeated human correction'."
- Figure 3 caption: "as originally published" → "from the full n = 3 gradient".

**10. Quantisation paragraph names its apparatus.** (*The two executor classes*, para 2.)
(b) "Quantisation in particular is a live alternative explanation for a model that cannot emit a correct `lofreq call-parallel` flagset. We did not run the decisive control: `qwen3.6:27b` at `q8_0` or fp16 against its own `q4_K_M`."
(c) Checklist 3: "flagset" is coined; `q8_0`, fp16 and `q4_K_M` are Ollama tags never mapped to bit widths.
(d) "The 4-bit compression in particular could explain why a model cannot write the correct set of flags for `lofreq call-parallel`. The decisive control would run one model, `qwen3.6:27b`, at 8-bit (`q8_0`) or full 16-bit (fp16) precision against its own 4-bit (`q4_K_M`) version, and we did not run it."

**11. "Second best" with no measure and no comparator; "code fences" unglossed.** (*Runnable command syntax*, para 1.)
(b) "Plan v1.5 is v2 with all prose stripped, leaving only code fences. It is the shortest plan in the set, at 159 words against v2's 660, and it is the second best."
(c) Checklist 6 (comparison missing its values) and 3.
(d) "Plan v1.5 is v2 with all prose stripped, leaving only the fenced code blocks — the command lines set off as code, with every explanatory sentence deleted. It is the shortest plan in the set, at 159 words against v2's 660, and the second best at producing the correct call set: 30 of 36 local runs, against 34 of 36 for v2."

**12. A paired comparison whose direction is unstated, followed by a remedy that does not address it.** (*Runnable command syntax*, para 2.)
(b) "Paired by model, 3 improved, 1 worsened and 8 were unchanged (two-sided sign-test p = 0.63). Because three seeds per cell leave that contrast underpowered, we later re-ran three conditions — v1g, v1.25 and v1.5 — at ten seeds per model".
(c) Checklist 6: improved from what to what? And the "contrast" is v1.5 versus v2, but v2 is not among the extended conditions, so the reader waits for a sharper prose contrast that never comes (the n = 10 v2 data exist in Table S11 but are never set against 109/127).
(d) "Comparing each model's v1.5 result with its own v2 result, 3 models did better without the prose, 1 did worse and 8 were unchanged (two-sided sign test, p = 0.63). Three seeds per cell leave that contrast underpowered, and the ten-seed extension below sharpens the syntax contrasts rather than this one, because v2 was not among the extended conditions." [Or report v1.5 at 109/127 against the pooled n = 10 v2 count from Table S11.]

**13. A nested sentence whose tail dangles.** (*Runnable command syntax*, para 3.)
(b) "This result is consistent with copy-pasteability — whether a command can be pasted and run without modification — rather than information content or verbosity alone, as the relevant plan property."
(c) §1 rule 3: "as the relevant plan property" completes "consistent with … rather than …" across two interruptions.
(d) "The plan property that matters, on this evidence, is whether a command can be pasted and run without modification, not how much information the plan carries or how long it is."

**14. "The registry's long-form style" and "planner-comparison arm".** (*Runnable command syntax*, para 3 and para 4; Table 4 caption.)
(b) "Plan v1g supplies a six-line block in the registry's long-form style, with two bare, valueless flags"; "The v1g plan is not a planner-comparison arm, because syntactic density was not matched".
(c) Checklist 3, both coined.
(d) "Plan v1g supplies the same invocation as a six-line block, laid out as the Galaxy tool registry writes it [author: one flag per line?], including two flags (`--sig`, `--bonf`) listed with no value that the plan itself says may be omitted." and "The v1g plan does not test whether a tool registry writes better plans than a model, because it differs from the model-written plans in how much command syntax it carries as well as in who wrote it."

**15. Table 3 and Table 4 contradict each other on presentation.** Table 3's caption argues at length that a local "mean M3" column would mislead and is therefore not reported; Table 4 then reports two "Local mean M3" columns. The values are the same counts (0.250 = 9/36, 0.417 = 15/36, 0.833 = 30/36, 0.944 = 34/36), so relabel the Table 4 columns "Local runs with the correct call set" and print the fractions.

**16. A number measured against a different reference than the index was defined on.** (*How much of the plan*, para 2, last sentence.)
(b) "Local scripts recovered 0.942 of the tokens in the code-only v1.5 plan (n = 130)."
(c) Checklist 6/3: the index was defined as recall of v2's 90 tokens; this figure is recall of v1.5's tokens, and the switch is unmarked.
(d) "Measured against plan v1.5's own command tokens rather than v2's, local scripts reproduced 0.942 of them (n = 130)." Also in the same paragraph "without plan conditioning … plan conditioning added" → "written without any plan … supplying the plan added".

**17. Subsection opener that orients.** (*Moving one path*, para 1.)
(b) "We detail the design in Methods."
(c) Checklist 1.
(d) "Briefly (the full design is in Methods), the plan is v2 verbatim, but the reference genome sits at `data/ref/GRCh38_chrM/rCRS.fa` instead of the plan's literal `data/ref/chrM.fa`, and the real path is stated in the prompt's DATASET section."

**18. Stacked appositives before both verbs.** (*Moving one path*, para 3, "Third".)
(b) "The paper's original headline model, `qwen3.6:27b`, 10/10 at unperturbed v2, copied, while `gpt-oss:20b`, one of only three models below 10/10 at the unperturbed headline condition (9/10), bound."
(c) §1 rules 2–3.
(d) "`qwen3.6:27b`, the paper's original headline model at 10/10 on unperturbed v2, copied the stale path; `gpt-oss:20b` bound the stated one, although it was one of only three models below 10/10 on that same condition (9/10)."

**19. The repair paragraph still names the apparatus.** (*Three attempts*, para 1.) This is the passage the author complained about; it is much improved but three phrases remain.
(b) "The perturbation above gave each model one attempt … After any nonzero exit the model saw its own script, the exit code and the last 40 lines of the execution log, and could submit a fix. The retry signal is the exit code only; the score is computed afterward and never shown."
(c) Checklist 3: "perturbation", "nonzero exit", "retry signal".
(d) "The moved-path test above gave each model one attempt: it wrote a script, the script ran, and that was the end of the trial. We therefore repeated the test with the same moved reference, allowing up to three attempts. After each failed run the model was shown the script it had just written, the exit code and the last 40 lines of the execution log, and could submit a replacement. Failure meant a nonzero exit code and nothing more: we computed the score afterward and never showed it to the model."

**20. "The expected direction" without the mechanism.** (*The n = 3 headline*, sentence 5.)
(b) "Every model that moved, moved down — the expected direction rather than symmetric noise — so we report n = 10 as the headline and treat every n = 3 cell as an interval."
(c) Checklist 3: why expected? "Treat as an interval" is also shorthand.
(d) "Every model that moved, moved down, which is the only direction a cell already at 3/3 can move [author: confirm every mover was at 3/3], so we report n = 10 as the headline and read every n = 3 cell as its wide interval rather than as a rate."

**21. Reasoning paragraph: differences in what, "budget", "the harness's own limits", no denominators.** (*Enabling reasoning*.)
(b) "The per-plan differences are +0.17 at v1, +0.23 at v1.25 and −0.20 at v2"; "needs a budget two to three times larger"; "ends at the harness's own limits in 6.7% of runs against 0.3% disabled".
(c) Checklist 6 and 3.
(d) "The per-plan differences in mean M3, reasoning on minus reasoning off, are +0.17 at v1, +0.23 at v1.25 and −0.20 at v2"; "needs an output-token budget two to three times larger merely to emit a script"; "also ends at the harness's own limits — the 16,384-token output cap or the 600 s kill — in 6.7% of runs (18 of 270) against 0.3% (1 of 324) with reasoning disabled" [author: confirm the counts and which limit].

**22. Injected-failure para 2: a comparison missing one side, an ambiguous model name, an unnamed set, and the one banned word.**
(b) "`qwen3.6:35b-a3b` resolves them to recover 3 and partial 21 with its mean M3 *falling* to 0.208"; "`granite4` produces 24 crashes"; "five of the six executors"; "essentially determined by the injected pattern".
(c) Checklist 6 (falling from what?), 3 (the reader has met `granite4.1:30b` and `granite4.1:8b`, never `granite4`; the six executors are never listed), 8 ("essentially" as filler).
(d) "with its mean M3 falling from [its v2 value] to 0.208"; name which granite; "five of the six executors in the matrix — `qwen3.6:27b`, `qwen3.6:35b-a3b`, `granite4…`, `claude-opus-4-7`, `claude-sonnet-4-6` and `claude-haiku-4-5` [author: confirm] — produce exactly crash 15 / propagate 6 / recover 3"; "is determined by the injected pattern".

**23. The script audit sits under a title it does not belong to.** (*Injected failures*, para 3.) The paragraph on package managers, `sudo` and `/tmp/` deletes is a separate finding; §4 wants a title that is that finding. Suggested subsection title: "No script escaped the sandbox, and two deleted files under /tmp".

**24. Case-study coinages and a miscounted enumeration.** (*Case study*, paras 2–3.)
(b) "after a harness transport fault"; "because the invocation step supplied a literal JSON body"; "Three caveats must accompany this result" followed by six distinct caveats (literal body, human pre-build, no reporting step, unlogged human time, reasoning suppressed, no job counts).
(c) Checklist 3 and 9.
(d) "after the harness lost its connection to the server [author: say what failed]"; "because the plan's invocation step supplied the parameter block verbatim, as JSON, for the model to submit"; either "Six caveats" or number the first three and move the remaining three to a sentence beginning "In addition,".

**25. "Durable state", "notebook", "design arithmetic".** (*Failure modes*, sentences 4–5 and last.)
(b) "neither model could escape its own bad durable state. One arm re-read its notebook"; "the empty-turn rate rests on design arithmetic rather than an instrumented count"; "6 of 30 fabrication-study launches".
(c) Checklist 3; the fabrication study is also a forward reference within Results.
(d) "neither model could escape a stale note it had written itself: `loom` keeps a notes file between sessions, and one arm re-read from it the annotation identifier recorded before the GFF3 was replaced, then re-invoked the doomed workflow, losing about 2 h of correct upstream compute"; "the empty-turn rate is the difference between launches and answer files (30 − 24 = 6), not a count of empty turns read from logs"; "6 of 30 launches in the controlled study described below".

**26. The standalone framing is the fabrication study, and the text never says so.** (*Framing, not capability*, para 1 last sentence; *One fabrication*, para 2.) The same 118 of 144 / 14 abstentions appear in both places as if from two experiments, and the framing paragraph drops the 12 `ABSENT` judgements. Also "This is the weakest of the three lines of evidence" never says which three.
(d) "The second framing was a standalone task — the controlled study reported in the next subsection — with six dataset identifiers: report `Assigned` for each and cite the identifier beside every number. Both models did that correctly and repeatedly: of 144 sample-level judgements, 118 were correct, 14 were correct abstentions, 12 were absent, and none was fabricated." And name the three lines of evidence.

**27. Cost paragraph calls a stated input a measurement, and two run-time figures are left unreconciled.** (*A local executor does not pay for itself*.)
(b) "measured local wall-clock time was 86.7 s per run" — Methods says this figure "was not archived and is carried as a stated input, not a verifiable measurement"; and para 1 gives a median of 105 s for v2 with no bridge to 86.7 s.
(c) Checklist 6/consistency; the reader who checks Methods stumbles.
(d) "while the local run time carried by the cost model is 86.7 s per run — recorded at run time but not archived (Methods; the verified 80.3 s changes the electricity term by 8%) — corresponding to $0.00016 of marginal electricity." And after the 105 s sentence: "That median is for plan v2 alone; the cost model below uses the 86.7 s mean over all 324 runs." Gloss "crossover" once: "the crossover — the number of runs per year at which local becomes cheaper than the API — is approximately 25,475".

## Tier 3 — small, worth fixing in the same pass

28. *Conventional metrics*, para 1: recall as decimals against success as fractions ("0.086 against 6/108") makes the reader convert; write "0.086 against a success rate of 0.056 (6/108) at Track B, 0.306 against 0.250 (9/36) at v1, 0.485 against 0.417 (15/36) at v1.25, and 0.886 against 0.833 (30/36) at v1.5". Give TP/FN their denominator: "of 2,916 truth variants (324 runs × 9)". "It re-expresses a binary" is cryptic; if the intent is that with precision fixed at 1.000 F1 is a monotone function of recall, say that. Para 2: "8% of runs by partial call sets, plus 2.5% by exit status" → "(26 of 324) … (8 of 324)".
29. Table 5: two bold cells with no key (checklist 9); say "bold marks the two values compared in the text" or drop the bold. "Omitted for width" → "omitted to keep the table legible".
30. Table 3 caption: "Track B pools three (plan file, track) cells, hence n = 108" → "Track B was run under three nominal plan files and we pool the three, hence n = 108 (12 models × 3 files × 3 seeds)".
31. *The two executor classes*, para 1: "frontier executors" first appears here unglossed; write "the three commercial API models — the frontier arm — produced it in 13 of 27 runs". The two opening sentences both orient; §4 allows one goal sentence, so merge: "To measure how much written guidance each executor class needs, we ran every executor against the plan gradient — from no plan at all to a plan spelling out every command (Figure 2, Table 3)."
32. *Injected failures*, para 1: "The other 12 cells did not contain a tool failure" — 24 + 12 ≠ the 39 cells Methods describes; write "The 12 cells that injected no error, and the 3 uninjected controls, contain no tool failure".
33. Figure 4 caption refers to "a green cell" without stating the colour key for crash / propagate / recover.
34. *One fabrication*: "12 were `ABSENT`" needs "(the answer file gave no value for that sample)", since the reader has just been told these 24 sessions all produced an answer file; "a reachable tool path" → "with the datasets it needed reachable through its tools"; "harvested from the harness's own injected system context" → "taken from the instructions the harness itself places in the model's prompt". Para 3 repeats the three limitations Methods already states almost verbatim; keep one copy.
35. *Runnable command syntax*, para 2: "exact sign-flip p" is unglossed — "(a permutation test that flips the sign of each paired difference)" at first use; "Because repeated seeds are clustered within models" → "Because the ten runs of one model are not independent of one another".
36. *A local executor*, para 1: "on the sufficient plan" → "on plan v2".

Verdict: the section's numbers are honest and its sentence rhythm already matches the corpus (mean 20.3 words, no staccato runs, few very long sentences), but it fails the explanation-first rule at roughly a dozen load-bearing points — seed, the crash/propagate/recover categories, degeneracy, the exit-status rule, MCP/IWC/TRS, the transcription index — and carries six reviewer-facing asides, so a biologist would lose the thread in the copying, repeated-sampling, conventional-metrics, injected-failure and case-study subsections until those glosses are written in.

# Discussion and Conclusion

I've finished the pass. The skill's numeric targets are met over the span (106 sentences, mean 21.7 words, median 21, 12% at ten words or under, five over 35, no run of three short sentences), so nothing below is a length problem; every finding is structural, a gloss, or a buried verb. Ranked by how much each hurts a first-time reader.

**1. "What was demonstrated and what was not", paragraph 1 — a Results re-summary with a buried verb, duplicated by the Conclusion**

(b) "Given a plan that supplies the literal invocations, free 4-bit open-weight models on a single sub-$2,000 board produced a working per-sample variant-calling pipeline in a single pass. Nine of twelve were perfect on all ten seeds… 6 of 108 no-plan runs were correct. The frontier models… 13 of 27… 9 of 9… We then moved the reference file on disk… Eleven of thirteen local models copied the stale path… while two re-bound every path…"

(c) §4 (Discussion never re-summarizes) and §1 rule 1. Nine of eleven sentences retell Results in narrative order ("We then moved…"), and all six numbers reappear a third time in the Conclusion. Sentence 1's main verb "produced" is word 18 behind a fronted "Given…" clause. The two positioning claims that belong here (the requirement concerns a class, not a model; success is transcription) sit at sentences 6 and 11. "The first finding is therefore the requirement for near-executable detail, not its absence" makes the reader work out what "its" is.

(d) "Two things were demonstrated. First, this class of executor requires near-executable detail and the frontier class does not. Free 4-bit open-weight models on a single sub-$2,000 board produced a working per-sample variant-calling pipeline in a single pass when the plan supplied the literal invocations, nine of twelve perfect on all ten seeds at the most detailed plan condition. Where the plan was thin the same models produced almost nothing, 6 of 108 no-plan runs correct, whereas the frontier models produced a correct call set in 13 of 27 no-plan runs and were 9 of 9 from the leanest plan file onwards. The contrast concerns a class of executor rather than model identity, because quantisation, size, vendor, serving stack and decoder all move together between the arms. Second, that detail works by transcription for most of the class. We moved the reference file on disk, left the detailed plan's path stale and stated the true path in the prompt: eleven of thirteen local models copied the stale path and failed at the first step in every seed, while two re-bound every path to the data's new location and stayed perfect. We call the eleven transcribers and the two binders. Binding therefore exists in this class, but as a property of two individual models rather than of the class, and for the transcribers a detailed plan works only while its paths match the disk." If the Conclusion keeps the numbers, this paragraph can drop all but the two class contrasts.

**2. Limitations, paragraph 1 — revision-history language a fresh reader cannot parse**

(b) "Three entries in the previous version of this table have since been run: … We ran the repair arm at the perturbed condition rather than at the lean plans, and all three are now Results."

(c) Reader test, checklist 3. "This table" has no referent yet (Table 8 arrives two sentences later), "the previous version" is the manuscript's own revision history, and "are now Results" names a section instead of telling the reader where to look.

(d) "Three experiments that an earlier draft listed as missing have since been run and are reported above: the additional seeds at the three discriminating conditions (v1g, v1.25 and v1.5), the moved-reference variant of the perturbed plan, and the repair arm, which we ran at that perturbed condition rather than at the lean plans." For a paper meant to be read fresh, delete both sentences; Table 8 already lists only what remains unrun.

**3. Limitations, "Three design gaps" — four experiments named as if known, none introduced, no salvage**

(b) "We did not run the planner comparison at matched syntactic density: v1g's density is not matched, and the human-expert and second-frontier-planner arms remain unrun. We also did not run the expanded error-injection suite as a designed matrix, and benchmark 2 carries no plan gradient."

(c) Checklist 3 and §3. "The planner comparison", "human-expert arm", "second-frontier-planner arm" and "expanded error-injection suite" occur nowhere else in the file (I grepped), so the definite articles point at nothing; "syntactic density" is defined only by a Table 4 column heading. The paragraph closes without a salvage.

(d) "Three design gaps have no cheap resolution. First, we never compared plan authors at a matched number of literal command lines: v1g, the registry-extracted plan, carries its one `lofreq` invocation in a six-line form that v1.25 states in one runnable line, and we wrote no plan by a human expert and ran no second frontier model as planner. What v1g does show is that a longer plan from a non-model author did no better than the lean plan, so length and authorship do not explain the gradient. Second, we did not expand the injected-failure matrix beyond its seven patterns and two plans into a designed matrix. Third, benchmark 2 carries no plan gradient, and a two-point gradient inside that loop is what would turn its illustration of plan sufficiency into a test." (Say what the expanded matrix would vary; the current text does not.)

**4. Conclusion — three sentences with the main verb past word 12**

(b) "On a 7-step per-sample variant-calling task with no data-dependent parameter choices, twelve free 4-bit open-weight models on a single sub-$2,000 board produced…" (verb at word 22); "Under a one-path perturbation of the detailed plan, with the true path stated in the prompt, eleven of thirteen local models — the original headline model among them — copied…" (52 words, two fronted phrases, a dash interruption, verb at word 27); "When the repair arm re-ran the perturbed condition with the error fed back, up to three attempts, two transcribers became perfect…" (verb at word 17, "up to three attempts" hangs).

(c) §1 rules 1 and 3, checklist 4.

(d) "Twelve free 4-bit open-weight models on a single sub-$2,000 board produced a working pipeline reliably only when the plan supplied the literal invocations, on a 7-step per-sample variant-calling task with no data-dependent parameter choices." / "We then moved one path in the detailed plan and stated the true path in the prompt: eleven of thirteen local models, the original headline model among them, copied the plan's stale path verbatim and failed at the first step in every seed, while two re-bound every path and stayed perfect." / "Two transcribers became perfect on the second attempt in every seed once the repair arm fed the error back and allowed up to three attempts."

**5. Conclusion closing — an announcer sentence, a dangling appositive, and a reason argued nowhere**

(b) "For a laboratory, the practical reading is this. Where a language model of this class is used as executor, the plan decides…"; "…short and literal enough to be a shell script, a comparison this study did not run."; "…are data governance and freedom from per-call metering, not cost."

(c) Checklist 1 (the 8-word sentence only announces); the fronted "Where" clause pushes "decides" to word 14; "a comparison" attaches to "shell script", which is not a comparison; and "freedom from per-call metering" appears for the first time in the paper's last clause, while the governance paragraph argued for custody of the data alone.

(d) "The practical reading for a laboratory is that the plan decides whether an executor of this class works, and that the plan must be kept exactly current, because a stale path defeats a transcriber outright." / "The leanest plan that works here is short and literal enough to be a shell script, and this study did not compare the models with one." / "At the task sizes measured here, the reason to run an executor locally is data governance, not cost." If metering stays, give it one sentence in "Local execution buys data governance" first.

**6. "Plan sufficiency is the engineering object", paragraph 2 — unglossed "deterministic template", an unresolved tradeoff, an orphan last sentence**

(b) "We did not compare the models with a deterministic template. … not an advantage over a deterministic template. A plan must also be tested with its executor: the defensive plan improved results for two executors…" and Table 8's "A deterministic ~20-line templater".

(c) Checklist 3, 10, 2. "Template"/"templater" is never glossed (these are its only uses); the model-versus-template tradeoff is opened and left open, though the Introduction already decided it ("a validated shell script… is a better choice"); the defensive-plan sentence is a different finding glued on with "also", so the paragraph ends off its own claim. Sentence 3 also restates 11/13 and 2/13 for the third time in the Discussion.

(d) "Plan v1.5 contains 159 words and ten command lines, and local scripts reproduced 0.942 of its tokens: this plan is close to a shell script. We did not compare the models with a deterministic template — a fixed script of about 20 lines that substitutes the sample names and paths into those same commands without a model. The two models that re-bound the moved path show path binding under one perturbation, not an advantage over such a template, and until that comparison is run the template remains the right default for a stable pipeline, with a model justified only where inputs move and the model has been shown to bind." Move "A plan must also be tested with the executor that will run it: the defensive plan improved results for two executors, reduced results for one, and caused all runs from another executor to fail" into paragraph 1 of this subsection, beside the other properties of a sufficient plan.

**7. Limitations, "Individual results carry their own limits" — three jargon compounds**

(b) "no residency number here should be provisioned against"; "the error-injection degeneracy claim rests on per-cell artifacts…"; "exact sign-flip p-values of 0.027 and 0.0039, but prose removal remains unresolved, so the size of the prose term is unknown."

(c) Checklist 3. "Provisioned against" is procurement jargon; "error-injection degeneracy claim" compresses a Results sentence into three nouns; "sign-flip" is not glossed even at its first use in Results (lines 154 and 156), and a biologist knows a sign test, not a sign-flip test; "prose removal" and "the prose term" are labels for the v2-versus-v1.5 contrast.

(d) "Our measurements of the memory the loaded weights occupy do not agree with one another for one model, so no memory figure here should be used to size a machine." / "And the claim that the injected pattern, not the model, set the outcome in the injected-failure matrix rests on per-cell artifacts that were not archived, so it cannot be checked." / "The two primary model-level syntax contrasts — v1.25 against v1g, and v1.5 against v1.25 — have exact p-values of 0.027 and 0.0039 from a sign-flip test, which permutes the sign of each model's paired difference; the effect of stripping prose from v2 remains unresolved, so the size of any prose effect is unknown." (Or gloss sign-flip once at line 154.)

**8. Limitations, "Three gaps concern the released artifacts" — verb at word 22, three gaps never counted off, two coined compounds**

(b) "The Galaxy plan files, the fabrication study's code and per-cell outcomes, the eleven-item defect ledger with its diffs, and the `loom` session logs are not in the repository."; "…so command-to-plan-revision provenance is not machine-checkable."

(c) §1 rule 1 (a four-item subject before "are"); §6 inline enumeration (the reader cannot tell whether the `FACTS.md` sentence is gap two or part of gap one); checklist 3.

(d) "Three gaps concern the released artifacts, and they are reproducibility failures rather than limitations of the evidence. First, four items are not in the repository: the Galaxy plan files, the fabrication study's code and per-cell outcomes, the eleven-item defect ledger with its diffs, and the `loom` session logs. Second, four sets of claims therefore rest on `FACTS.md` and are marked as such at every point of use: 1) … 4) …; the per-sample count table and the gene count can be verified independently. Third, per-cell records carry a plan file path but no plan revision, so one cannot check by script which revision of the plan produced a given command."

**9. Scope — an abstract subject with no destination, and a nested "and, for…, for…"**

(b) "One class of property is unlikely to transfer without testing, and it defines the boundary of every claim here: …"; "…whose plans are literal and current, and, for the two models shown to bind, for attaching such a plan to inputs that have moved."

(c) §1: "One class of property" cannot be pictured until the colon and "transfer" names no destination; the second sentence nests a qualifier between "and" and its "for attaching" (rule 3).

(d) "The boundary of every claim here is the task type: the plan-sufficiency result is conditional on tasks with no data-dependent parameter choices, and we expect it not to carry over to tasks that have them without a test." / "The results support the use of local executors for running pipelines whose plans are literal and current; for the two models shown to bind, they also support attaching such a plan to inputs that have moved."

**10. "Plan sufficiency is the engineering object", paragraph 1 — an interrupting clause, a dangling participle, a vanished eleventh model, and an evidence-only close**

(b) "The perturbation shows that for a transcriber, which is what eleven of thirteen local models here are, sufficiency means literal and current."; "…replaced the need for a current path, and shown the error once, both were perfect on the second attempt in every seed. For eight of the eleven transcribers feedback did not help…"; final two sentences ("…plan sufficiency governs the reporting channel as well as the execution channel. The same job… not one per-sample number as step 7 behind an unbounded monitoring step.").

(c) §1 rule 3 (relative clause splits "for a transcriber… sufficiency means"; "means literal and current" is elliptical); "and shown the error once" dangles after "and"; two plus eight is ten of eleven, so the partial repairer `laguna-xs-2.1`, counted among the "three" in the previous subsection, has silently disappeared; checklist 2 — the paragraph ends on evidence, not the decision Results already drew; "reporting channel"/"execution channel" name the thing before the mechanism.

(d) "The perturbation shows what sufficiency means for a transcriber, and eleven of thirteen local models here are transcribers: the plan must be literal and current." / "The repair arm qualifies that for some models. For `qwen3.6:27b` and `qwen3.8:27b`, one execute-and-retry round replaced the need for a current path: shown the error once, both were perfect on the second attempt in every seed, and `laguna-xs-2.1` was in two of three. For eight of the eleven transcribers feedback did not help, and they kept the dead path through three attempts." / "The fabrication result adds a measured corollary: a plan must make the reporting step sufficient, not only the execution steps. The same job, models and datasets produced 118 correct sample-level judgements out of 144 as a standalone task, and not one per-sample number as step 7 behind a monitoring step with no bound on its duration. A sufficient plan therefore gives reporting its own step and its own budget."

**11. "Five things were not demonstrated" — one coined hyphenation and a mis-signposted fourth item**

(b) "Third, frontier-equivalence on the second workflow class…"; "Fourth, the substitution of iteration for plan detail, which bounds the title directly. … We probed the constraint with a repair arm: … Three of the eleven transcribers fixed the stale path… The same feedback loop at the lean plans v1 and v1.25… was still not run."

(c) Checklist 3 ("frontier-equivalence" is used once, unglossed); the reader is told the substitution was not demonstrated, then reads what looks like its demonstration, and learns only at the end that the repair arm tested feedback against a stale path, not against a thin plan; "bounds the title directly" asks the reader to recall the title.

(d) "Third, that local executors match the frontier ones on the second workflow class, because we ran no frontier executor on it. Fourth, that iteration can substitute for plan detail, which is the constraint the title's 'single pass' names. Every trial above was single-pass: … We probed that constraint only against the stale path, with a repair arm: we re-ran the perturbed condition, feeding each failure's error back to the model and allowing up to three attempts, and three of the eleven transcribers fixed the path when shown the error while eight did not. The test that would settle the fourth point — the same feedback loop at the lean plans v1 and v1.25, feedback in place of specification — was not run."

**12. "Local execution buys data governance" — three glosses missing**

(b) "the annualised cost crossover sat above 25,000 runs per year"; "although this boundary was incomplete in our study"; "invalidate stale persistent state".

(c) Checklist 3. "Cost crossover" is defined nowhere in prose; "this boundary" has no antecedent in the paragraph; "stale persistent state" is what the case study described plainly as re-reading a notebook entry recorded before the annotation was replaced.

(d) "…and the annual run count above which owning the board becomes cheaper than paying per call sat above 25,000 even with API-side labour priced at zero." / "…it can keep data from an API vendor, although in our study that boundary — the line between what stays on the board and what leaves it — was incomplete." / "…verify state changes, expire saved notes that no longer match the server, and include a dataset or job identifier with each reported value."

**13. Minor unglossed labels (low)**

(b) "a wired pipeline from an unwired one" (Limitations ¶1); "the model the frozen rule returned" and "Two limitations concern the study as an object" (Limitations ¶5); the heading "Plan sufficiency is the engineering object".

(c) Checklist 3: "frozen rule" renames Methods' "executor-selection rule… fixed"; the other three are metaphors or abstractions with no gloss.

(d) "a pipeline whose steps are connected correctly from one whose steps are not"; "in place of the model that the executor-selection rule, fixed before benchmark 2 ran, had returned"; "Two limitations concern how the study itself changed while it ran."; heading: "The plan, not the model, is the thing to engineer".

What passed: "single-pass" and "repair arm" are glossed inline at their first Discussion use; Table 8's "Bounded repair" carries its gloss in the same cell; hedges are single and name their object; no banned openers, bold spans or bullet stacks; the Limitations section as a whole ends in a salvage ("we release the artifacts so the evaluation can be re-run").

Verdict: the Discussion already sounds like the house voice by the numbers, but a first-time reader stalls at its opening re-summary and at the Limitations' revision-history and never-introduced experiment names, and the Conclusion carries three buried-verb sentences; fix those and the gloss list above and the section passes.