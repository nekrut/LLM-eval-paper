# What the plan actually supplies: specific literal invocations, not prose

Two independent matrices agree. Track A, reasoning off; a "literal command line" is a
non-blank line inside a fenced block invoking a workflow tool or shell construct.

| plan | author | words | literal cmd lines | Jetson mean M3 | RTX 5080 mean M3 |
|---|---|---|---|---|---|
| v1    | claude-opus-4-7 | 422 | 0  | 0.250 (n=36) | 0.211 (n=38) |
| v1g   | **Galaxy IUC registry (mechanical, no LLM)** | 558 | 1 | 0.257 (n=35) | 0.189 (n=37) |
| v1.25 | claude-opus-4-7 | 413 | 1  | 0.417 (n=36) | 0.528 (n=36) |
| v1.5  | claude-opus-4-7 | 159 | 10 | 0.833 (n=36) | 0.892 (n=37) |
| v2    | claude-opus-4-7 | 660 | 8  | 0.944 (n=36) | 0.949 (n=39) |

Verbosity does not predict performance: v1.5 is the **shortest** plan in the set
(159 words) and the second-best; v2 is the longest and best; v1g is second-longest
and second-worst. Spearman on the Jetson set: +0.85 for command-line count, +0.10
for word count.

## The mechanism is copy-pasteability, not missing information

**This corrects an earlier reading in this file.** The first version of this analysis said
v1.25 works because it supplies an invocation the models cannot derive. That is false, and
the plan files show it.

| plan | contains the call-parallel invocation? | runnable as written? | score |
|---|---|---|---|
| v1    | yes, in prose: names `call-parallel`, `--pp-threads 4`, the reference and the input BAM | no | 9/36 |
| v1g   | yes, in a code block, **plus** an explicit note that the BAM is a positional argument at the end | **no** - six lines, no continuations, two valueless flags the plan says to omit | 9/36 |
| v1.25 | yes, as one line | **yes** | 15/36 |

v1g carries *more* information than v1.25. It states the exact detail a model is most likely
to get wrong. It scores the same as v1, which carries the same content in prose.

The variable that moves the score is whether the command can be transcribed verbatim.

This is a stronger concession to the transcription reading than the earlier version. What a
plan supplies is not knowledge the executor lacks. It is text the executor can copy.

**Statistical caution.** The v1g versus v1.25 contrast is Fisher p = 0.21, sign test p = 0.22.
It is not resolvable at three seeds. The only gradient step resolved at n = 3 is v1.25 to
v1.5 (15/36 to 30/36, Fisher p = 0.0005). State the mechanism as the reading the plan files
support, not as a measured contrast, unless the seed count is raised.

## Frontier models do not need any of this

Same task, same plans, API models (Track A):

| plan | local mean M3 | frontier mean M3 |
|---|---|---|
| v1    | 0.211 | 1.000 |
| v1g   | 0.189 | 0.667 |
| v1.25 | 0.528 | 1.000 |
| v1.5  | 0.892 | 1.000 |
| v2    | 0.949 | 1.000 |

The frontier model is flat near ceiling across the gradient; the local models show a
steep gradient. **Plan detail substitutes for model capability** — that is the
paper's thesis, stated as a measured contrast rather than an assertion.

## Consequences for the manuscript

**1. This supplies the planner comparison (R3.6 / T3.2) from data already collected.**
v1g has a different author and is not LLM-written, yet behaves as its content predicts
rather than as its authorship or length would. The plan-gradient result is not an
artifact of one planner's house style. The manuscript currently calls v1g a
"robustness check"; it is the documentation-authored arm of a planner comparison and
should be presented as such.

**2. It concedes R3's central objection and measures it.** If prose is inert and the
active ingredient is the specific literal invocation, then behaviour at the detailed
end of the gradient looks more like transcription than orchestration. The manuscript
should state this directly rather than defend against it. The honest claim — *a small
local model reliably produces a working pipeline when handed the invocations it cannot
derive, and explanation around them adds little* — is narrower, better supported, and
more useful to anyone writing plans.

## Limitations
- Five plans. A rank correlation on five points has a very wide interval; the
  v1.25-versus-v1g contrast carries the argument, not the coefficient.
- "Literal command line" is an operational definition and the count is sensitive to it.
- The frontier arm has n=9 per plan and no v1/v2 cells on the 5080 sheet; the v1g
  frontier value (0.667) rests on 9 runs and should not be over-read.
