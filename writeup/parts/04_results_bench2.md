### A tool-using agent loop on a second workflow class and a production server

Given the plan and a live MCP connection to the public usegalaxy.org server, both local executors imported the 30-step IWC `rnaseq-pe` workflow by TRS identifier, located and verified the six paired-end inputs, resolved the annotation, and submitted a parameter-correct invocation: 2 of 2 inputs and 8 of 8 parameters (paired collection; GTF annotation; `GCA_002759435.3`; `stranded - reverse`; featureCounts enabled; empty adapter fields; Cufflinks and StringTie disabled). Job-level outcomes, read back from the Galaxy API rather than from either model's report, were 90 ok / 56 skipped / 0 error for the dense arm and 88 ok / 56 skipped / 1 error / 1 paused for the mixture-of-experts (MoE) arm, against 96 ok / 56 skipped / 0 error for the human validation arm. <!-- addresses: C1, C2, R2.10, R3.1, R3.3 -->

The invocations reproduced the published quantification. Both arms yielded 5,594 genes, an exact match verified by downloading and counting the counts table rather than by accepting a reported figure. Assigned fragments ranged from 15.7 to 25.3 M per sample at 93.1-93.6% of uniquely mapped fragments (76.6-85.2% of all fragments); the published ~92% corresponds to the uniquely mapped denominator (Table [[NEEDS-NUMBER: number for the per-sample featureCounts table]]). Sample SRR22376029 falls below the published floor at 15.72 M assigned, but it is the sample the original analysis flagged as the low-unique-mapping outlier and is the worst multi-mapper here at 17.9%, so the anomaly reproduces. The two arms produced byte-identical values in all four featureCounts categories from twelve distinct dataset identifiers. That agreement is expected by construction from a deterministic server-side workflow on identical inputs: it shows both parameterisations were identical and correct, and is not independent replication of model behaviour. <!-- addresses: C2, R3.3, R3.5 -->

The result carries an end-to-end caveat that must accompany it wherever it is claimed. Both executors submitted a parameter-correct invocation and the workflow produced benchmark-matching counts, but neither executor completed the final reporting step. In dedicated verification runs the MoE arm made 22 tool calls over 54 min and reported the gene count only; the dense arm made 26 tool calls over 24 min and reported nothing. None of the six true per-sample values appears in either arm's output, and the values published here were read out of Galaxy by a human. "Both executors succeeded" is true at the invocation level and false end to end. <!-- addresses: C1, R2.10, R1.3 -->

This is a loop in the sense that benchmark 1 is not: the executor issued tool calls, read back live invocation and job state, discovered and corrected a wrong identifier, and carried state across session boundaries in a durable notebook. We use "agentic" only for this benchmark and in that sense only. The successful invocation cost 38 tool calls and 44 min (dense) and 19 tool calls and 22 min (MoE) on one Jetson AGX Orin at electricity-only marginal cost, against $2.82-$131.83 per run for eight frontier models acting as both planner and executor on the same data (Galaxy Project 2026). Supervised wall time across the whole exercise was far larger - roughly 4.4 h of agent sessions for the dense arm and 5.3 h for the MoE arm, several ended by their time budget rather than by stopping. Throughput, not correctness, bound the dense arm, at one point 15 tool calls in 57 min, and reasoning was suppressed in both models because with it enabled one arm spends about 11 min per turn (roughly 4,800 tokens at 7.2 tok/s). This benchmark says nothing about these models with reasoning on. <!-- addresses: C1, C2, R3.2, R3.13 -->

One residue is reported because neither model, and none of our own earlier write-ups, caught it: the MoE arm's final invocation carries one errored `bedtools` job (exit 255, a missing container path on the Galaxy node) and one job paused in consequence. This is server-side infrastructure rather than model or plan, and featureCounts outputs are unaffected, but neither executor noticed that its invocation was not clean. <!-- addresses: C1, R2.7 -->

Two design limits bound the section. One invocation per arm reached counts, with two models, no replicates and no frontier-model control, so nothing here establishes whether the behaviour is size-dependent; and the executors were handed a plan a human had already corrected eleven times. A reviewer may reasonably read benchmark 2 as a case study rather than a controlled experiment, and we do not claim otherwise. <!-- addresses: R3.3, R3.5, T3.1, T3.3, T3.4 -->

### The plan, not the executor, was the binding constraint

Eleven defects had to be corrected before either model completed a clean run. All eleven were authored on the planner side and none originated with an executor; two genuine executor errors occurred in the whole exercise, and one further defect was a harness error attributable to the supervisor (Table 6). Each of the eleven first presented as a model failure and was resolved only by executing the failing step by hand against the live API. <!-- addresses: R3.5, R3.2, C2 -->

The most expensive defect is the clearest instance. A GFF3 annotation was staged where featureCounts requires a GTF carrying `gene_id`. Six fastp and six STAR jobs ran correctly for approximately 2 h, after which all six counting jobs aborted with `failed to find the gene identifier attribute in the 9th column`. The IWC workflow hard-codes the `exon`/`gene_id` pair and exposes neither as an input, so the GFF3 could not have worked at any parameterisation. The defect stayed invisible until the last stage of a two-hour workflow, which is what made it expensive rather than merely wrong. <!-- addresses: R3.5, R3.preamble -->

Five defect classes are worth naming for anyone writing plans for executors: omitted structural keys in an API call; a step saying "record the output id" without saying which of three available identifiers; a rule forbidding one fallback but not the others, so a transport error produced 30 min of retries; matching a file by name rather than by type; and a verification step that states its own expected answer. <!-- addresses: R3.5 -->

The two executor errors are instructive by contrast. One was a transcription slip: the plan supplied a 32-character hexadecimal identifier and the model sent 30, dropping two mid-string, which Galaxy rejected. Literal commands copy reliably because they are lexically structured; opaque identifiers do not, and a two-character elision still looks right. The other was the fabricated report below. <!-- addresses: R3.2 -->

On a different workflow class, on infrastructure we do not control, with a different harness and failure surface, the constraint determining success was again the specification rather than the model. That confirms the model-selection rule frozen from benchmark 1, but not plan sufficiency itself: the plan was corrected eleven times while benchmark 2 ran, so plan sufficiency was established during the experiment rather than tested by it, and the eleven corrections are data about plan authoring rather than a validated protocol. <!-- addresses: R3.5, C2, T3.3 -->

**Table 6.** Defect ledger for benchmark 2, attributing each defect to the party that authored it.

| Class | n | Attribution | Example |
|---|---|---|---|
| Plan defects | 11 | Planner (human) | GFF3 staged where featureCounts requires a GTF with `gene_id` |
| Executor errors | 2 | Model | Two characters dropped from a 32-hex identifier; one fabricated report |
| Harness error | 1 | Supervisor | Two runner processes alive in one workspace, truncating and appending to the same files |

### Failure modes visible only in the agentic setting

Three failure modes appeared in benchmark 2 that a single-pass benchmark cannot produce, and all three cut against the headline result.

First, neither executor completed the final reporting step. The MoE arm's last output is deliberation about how to interpret the invocation state; the dense arm emitted two assistant messages, the last reporting a transient timeout and a retry, and then the session ended. Neither notebook records the reporting step at all. A scorer reading only the invocation would record two clean successes. <!-- addresses: C1, R2.10, R1.3 -->

Second, neither model could escape its own bad durable state. One arm re-read its notebook, found the annotation identifier it had faithfully recorded before the GFF3 was replaced, and re-invoked the doomed workflow, losing approximately 2 h of correct upstream compute at the last stage. A human had to mark the notebook entry superseded before it could proceed. Durable memory, which is what makes multi-session work possible at all, amplifies a stale fact as readily as a correct one, and neither model had any mechanism for doubting its own notes. <!-- addresses: C1, R2.7 -->

Third, the zero-tool-call empty turn is a recurring mode rather than a one-off. In the fabrication study below, 3 of 9 launched MoE cells made zero tool calls, ran about a minute, emitted a single malformed pseudo-citation, and stopped with a normal stop reason. Their token telemetry is structurally identical to the fabrication session (roughly 26,000 input tokens, tens to hundreds of output tokens, no tool-execution events). A turn that declines to act is a distinct failure class from a wrong answer, and it is invisible to any scorer that reads only the answers produced. <!-- addresses: R2.7, R1.3 -->

None of the three can occur in benchmark 1: a single-pass script generator cannot fail to report, cannot poison its own state, and cannot decline to act. They are the concrete argument for evaluating executors in a loop rather than on one-shot generation. <!-- addresses: C1, R2.10, R3.1 -->

### Fabrication is a scaffold failure and is bounded, not absent

One fabrication incident occurred. In a resumed session an executor emitted a fluent, specific failure report - a named trimming tool failing on a named sample at a named error rate, with a retry and a decision to stop - having made zero tool calls, while its own invocation was healthy with 48 jobs `ok` and progressing. Every element was false: the plan has seven steps and no step 25, no plan variant of the name cited exists, and the workflow contains no such tool. The tool name was harvested from the harness's own injected system context, where it appears in two lists of tool names, and the sample identifier it borrowed was the one the benchmark flags as anomalous. This was not stale session state: it reproduced in a fresh session with zero tool-execution events, one assistant message and a normal stop reason. <!-- addresses: R1.1, R3.7 -->

A controlled study then measured the rate across three conditions (blind, leaky, blocked), two models and several seeds against known ground truth: 0 fabrications in 90 sample-level judgements. In the blocked condition, where two of six dataset identifiers do not exist and `UNAVAILABLE` is the only correct answer, both models wrote `UNAVAILABLE` for exactly those two every time and reported the other four correctly with identifiers cited. In the leaky condition, neither recited the expected range it had been handed. We report this as an upper bound and avoid the word "never": 0/90 gives a 95% upper bound of about 3.3% by the rule of three. <!-- addresses: R3.7 -->

Two limitations belong here rather than in the supplement. The scored denominator excludes cells that produced no answer file - a third of the MoE launches, and precisely the zero-tool-call class the original incident belongs to - so the bound holds only conditional on an answer being produced. And twelve abstentions arose from a network outage that made the server unreachable: creditable behaviour, but not evidence about evidence-handling under a working tool path. <!-- addresses: R1.1, R3.7 -->

We offer the interpretation as a hypothesis. The incident required four conditions at once: a resumed session carrying roughly 27,000 tokens of prior work, no reachable tool path by which to verify it, a task implying an obligation to report on it, and no sanctioned way to say "I do not know". A scaffold that demands an answer while denying the means to obtain one appears to manufacture confabulation from a model that otherwise does not confabulate. The study does not test this, since it manipulated none of those factors and its cells are single-shot tasks with a reachable path. One methodological point generalises: any agent evaluation that places the expected answer in the task description cannot distinguish execution from recitation. Our own verification step originally did exactly that and had to be rewritten. <!-- addresses: R1.1, R3.7 -->

### Accuracy is platform-independent; throughput is not

Across the five platforms, accuracy on the sufficient plan is unchanged and only wall-clock time varies, by roughly two orders of magnitude, driven by memory residency and bandwidth (Table 7). Three of the five dispersion ranges in the submitted table were mis-entered, including the one that placed a median outside its own stated interval; all five medians were correct. The table is now produced by a generator that asserts the median lies within the reported interval. <!-- addresses: R3.12 -->

The premise that identical weights must produce identical output across hardware does not hold here. These are not the same build of the same weights: the Apple platforms run 4-bit MLX under a different runtime, the CUDA platforms run GGUF q4_K_M under ollama, and batching and attention kernels differ. Divergence across platforms is expected, and per-platform engine and quantisation are now reported in the hardware table and the metadata supplement. <!-- addresses: R2.3, R3.11 -->

Throughput on the bandwidth-limited platform favours sparsity over size: a 7.6 GB dense model reached 14.4 tok/s while a 23.9 GB MoE model with 3B active parameters reached 30.7 tok/s - three times larger, 2.1 times faster. On hardware of this class, active parameters rather than resident size set throughput. We did not run a standardised fixed-prompt, fixed-output, fixed-repetition throughput benchmark across all five machines; the timings here come from this study's own mixed workload and are labelled as such. <!-- addresses: R2.3, R3.11, T3.7 -->

**Table 7.** Median wall time per run on the sufficient plan, by platform, recomputed from archived per-run data. Brackets give the interquartile range, except the final row, where n = 3 and the full range is given.

| Platform | n | Median (s) | Dispersion |
|---|---|---|---|
| 2x RTX A5000 | 36 | 29 | [24-31] |
| MacBook Pro M4 Pro | 36 | 92 | [91-108] |
| Jetson AGX Orin | 36 | 105 | [98-107] |
| RTX 5080 | 6 | 302 | [219-405] |
| MacBook Air M4 | 3 | 518 | [276-4,345] |

### Cost: local hardware does not pay for itself on a task this small

The cost accounting contradicts this study's own original motivation, and we report it as such. Measured API cost was $0.0662 per run over 81 runs; measured local runtime was 86.7 s per run, a marginal electricity cost of $0.00016 per run. Against hardware plus labour of $5,045 over three years, break-even arrives at 76,424 runs, or 15.3 years at 5,000 runs per year (Table 8). The submitted abstract claimed that per-call inference cost is the bottleneck; at $0.066 per run it is not, and that claim has been removed. "Free" has been replaced throughout by "no marginal API fee". <!-- addresses: R3.13, R3.15 -->

Most of the money is labour: $1,200 of setup plus $600 per year accounts for $3,000 of the $5,045, and the 16 h setup estimate is generous given the infrastructure incidents documented here. Electricity is a rounding error - moving board power from 20 W to 60 W changes break-even by 0.2%. Board wattage is also the weakest input, being the documented hardware envelope rather than a rail measurement, because that measurement requires privileges unavailable on the test unit; the model is released as a parameterised script so a reader can substitute a measured value along with their own tariff, salary and workload. <!-- addresses: R3.13 -->

The argument survives only by task size. Break-even falls to 20,192 runs at $0.25 per run, 5,046 at $1.00 per run - the scale of a multi-step agent loop - and 1,009 at $5.00 per run; the frontier comparator on the Galaxy task sits in that upper range at $2.82-$131.83 per run. The economic case for a local executor is therefore made by agentic workloads, not by the single-pass task this paper originally rested on. The non-monetary reasons - data governance, no per-call metering, independence from a vendor's model lifecycle - stand apart from the break-even figure but are argued rather than measured; we return to them in the Discussion. <!-- addresses: R3.13, R3.15, R1.4 -->

**Table 8.** Cost model. Measured inputs are marked as such; the remainder are assumptions exposed as parameters in the released script.

| Quantity | Value | Source |
|---|---|---|
| API cost per run | $0.0662 | measured, 81 runs |
| Local runtime per run | 86.7 s | measured, 324 cells |
| Local marginal cost per run | $0.00016 | electricity only |
| Hardware plus labour, 3 years | $5,045 | $3,000 of it labour |
| Break-even | 76,424 runs | 15.3 years at 5,000 runs/year |
| Break-even at $0.25 per run | 20,192 runs | sensitivity sweep |
| Break-even at $1.00 per run | 5,046 runs | sensitivity sweep |
| Break-even at $5.00 per run | 1,009 runs | sensitivity sweep |
