# Galaxy demonstration — methods

A companion to the plan-gradient matrix: the same question (does plan sufficiency,
rather than model capability, set the ceiling?) asked once on a real analysis with a
real server, rather than on a synthetic task.

## Target analysis

Re-quantification of the *Candidozyma auris* RNA-seq data of Santana et al.
(BioProject PRJNA904261), six paired-end runs SRR22376027–SRR22376032. This
reproduces the analysis of the Galaxy Project post of 2026-06-09, in which eight
frontier models acted as both planner and executor on usegalaxy.org at a reported
cost of $2.82–$131.83 per run.

Here the roles are split: the plan is authored once by a frontier model
(supervised and repeatedly corrected by a human — see the defect ledger), and the
executor is a **local, free, quantised model on a single Jetson AGX Orin 64 GB**.
Marginal cost of an executor run is electricity only.

## Executors

| role | model | quantisation | resident size |
|---|---|---|---|
| dense | `qwen3.8:27b` | q4_K_M | 19.6 GB |
| MoE | `qwen3.6:35b-a3b` | q4_K_M | 23.9 GB |

Reasoning was suppressed in both. `ollama`'s `/api/chat` honours `think: false`, but
the `/v1` OpenAI-compatible shim silently drops it, so requests were routed through a
LiteLLM proxy using the `ollama_chat/` provider, which forwards the flag. Context was
pinned at 65536 via a Modelfile; left at the model default, `ollama` reserves the full
262144-token context and allocates 53 of 61 GB.

## Agent harness

`galaxyproject/loom` (Pi-based), with `notebook.md` as durable inter-session state and
Galaxy reached over MCP. The plan is a router: a 50-line `PLAN.md` index plus seven
step files, so the model loads only the step it is on.

## Workflow

IWC `rnaseq-pe` v1.5 (fastp → STAR → featureCounts), imported by TRS id
`#workflow/github.com/iwc-workflows/rnaseq-pe/main`. Reference `GCA_002759435.3`
(*C. auris* B8441 V3), server-side indexed. Annotation is the NCBI **GTF** — the GFF3
for this assembly lacks `gene_id` and makes featureCounts abort after STAR has already
succeeded.

## Histories and invocations (usegalaxy.org)

| arm | history | invocation |
|---|---|---|
| human validation | `bbd44e69cb8906b5f5780eb6446f04a2` | `c4feccdd2dea35cf` |
| dense | `bbd44e69cb8906b5ee8b03fb2be6678d` | `a3d45688bcecb223` |
| MoE | `bbd44e69cb8906b5da3b1e414a8938d2` | `c2802ffa5af8cfa2` |

## Verification discipline

No claim in this section is taken from an agent's own report. Every state, parameter
and count was read back from the Galaxy API or from the dataset contents. This is not
pedantry: one executor produced a fully-formed failure report for an event that never
occurred (see Results), and the only thing that distinguished it from a true report
was the API.

For the same reason the Step 7 verification file states **no expected values**. An
earlier version listed them, which would let a model that never opened a dataset
produce a perfect report by reciting the plan. Any agent benchmark that puts the
expected answer in the task description cannot distinguish execution from recitation.
