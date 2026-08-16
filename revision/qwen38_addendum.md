# qwen3.8:27b addendum — draft prose for the writeup

Draft only. Not inserted into `writeup/writeup.md` or `writeup_GR.md` — that
placement is the user's call (see the open decisions in `PROGRESS.md`).

Status of the three pieces:
- Generational comparison — **settled**, data complete.
- Truncation finding — **settled** for the no-plan cells seen so far; final
  counts pending the think-on arm.
- Budget ablation — **pending**, runs queued behind the think-on arm.

---

## For Methods, appended to *Inference settings*

(The *Inference settings* subsection is already in both writeup files. This
sentence belongs at the end of its third paragraph once the ablation lands.)

> To quantify that sensitivity we re-ran the no-plan condition for the model
> most affected by it at 2× and 4× the standard budget (Results, *A newer model
> does not move the cliff*).

---

## For Results — new subsection

Suggested placement: after *Plan granularity has high impact*, before
*qwen3.6:27b is the winner*, since it tests the same claim with a model that
did not exist when the plans were written.

### A newer model does not move the plan-detail cliff

`qwen3.8:27b` was released on 14 August 2026, after the plans and the scoring
pipeline for this study were fixed. It is therefore an out-of-sample test of
the central claim in a sense the rest of the matrix is not: no aspect of the
experimental design could have been tuned to it. We added it under identical
conditions to the twelve other local implementers — same 4-bit quantization,
same Ollama configuration, same seeds, same 16,384-token budget — and it pairs
directly with `qwen3.6:27b`, which matches it in parameter count and
quantization and differs only by one model generation.

The cliff does not move. Both models fail at score ≈ 0 without a plan and both
require roughly v1g-level detail before they produce a working script. Two
single-column differences appear — `qwen3.6:27b` succeeds at v1 where
`qwen3.8:27b` fails, and the reverse holds at v1.25 — but they point in
opposite directions, sit at n = 3, and are exactly the kind of cell-level
variation the seed analysis below shows to be unreliable at that sample size.
We do not interpret either. What replicates is the threshold: a model
generation newer than the experiment reproduces the same requirement for
literal command syntax, and the accuracy gains its release advertises do not
translate into tolerance for vaguer instructions.

[TABLE: qwen3.6:27b vs qwen3.8:27b, mean score by plan column, reasoning off]

### Reasoning budget can masquerade as capability

`qwen3.8:27b` is the only implementer of the thirteen tested that exhausts the
generation budget while reasoning. With reasoning enabled and no plan, it
produced roughly 16,000 tokens of deliberation and returned no script at all;
across the 270 cells of the reasoning-enabled matrix for the other models,
this outcome never occurred, and `qwen3.6:27b` completed every one of its
reasoning-enabled cells within the same budget at a median of about 1,000
seconds.

The scores are zero either way, but the reason differs and only one of the two
is a statement about capability. A model that produces a broken script has
failed the task; a model still deliberating when the budget ends has not
finished attempting it. Because we record the outcome class of every
generation alongside its score (Methods, *Inference settings*), the two remain
separable in the released data.

We measured that directly. Holding the model, plan (v1g), seeds and hardware
fixed and varying only the budget, with reasoning enabled throughout:

| budget | produced a script | scored 1.00 | reasoning emitted |
|---|---|---|---|
| 16,384 | 0/3 | 0/3 | truncated at the cap |
| 32,768 | 0/3 | 0/3 | truncated at the cap |
| 65,536 | 3/3 | **1/3** | 140–220k characters, self-terminated |
| *16,384, reasoning disabled* | *3/3* | ***3/3*** | *none* |

Two things follow, and they pull in opposite directions.

The budget was genuinely binding. At 65,536 tokens the model stops of its own
accord after roughly 35,000–55,000 tokens of deliberation — two to three times
the study's standard budget, and more than 32,768 as well. The zeros at the two
smaller budgets are therefore artifacts of the ceiling and say nothing about
capability, which is precisely the distinction the outcome classification in
Methods (*Inference settings*) exists to preserve.

But relieving the ceiling does not recover the result. Given room to finish,
the reasoning-enabled configuration is correct on one seed of three, against
three of three with reasoning disabled, and takes 7,395–12,974 s per generation
against approximately 130 s. On this task, at this plan detail, reasoning is
expensive and worse even when it is given everything it asks for.

We do not claim a mechanism. The reasoning-enabled scripts are consistently
larger than their reasoning-disabled counterparts (2,197–2,984 vs 1,401–1,624
bytes) and consistently add incremental-build logic the plan does not request,
but the most elaborate of the three is the one that succeeded, so that
elaboration cannot be what causes the failures. Three seeds cannot separate
"reasoning enlarges the surface on which errors occur" from "these two seeds
were unlucky", and we report the effect without asserting the cause.

This matters beyond one model. A fixed token budget is an experimental
parameter that can convert a verbose reasoner into an apparent failure, and
the direction of travel in model training is toward longer reasoning. Any
benchmark of this kind should report its budget and, where a result depends on
it, show sensitivity to it.

---

## Caveats to preserve if this prose is edited

1. Do not describe the v1/v1.25 flips as a capability difference. They are
   n = 3, single-column, and opposite in sign.
2. Do not write that qwen3.8 "cannot" do the no-plan task. It ran out of
   budget; that is a different claim and the data distinguishes them.
3. The model cutoff date (2026-08-14) should appear wherever the model list
   does, so the boundary reads as a decision rather than an accident.
