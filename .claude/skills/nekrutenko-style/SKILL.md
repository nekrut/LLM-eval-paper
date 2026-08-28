---
name: nekrutenko-style
description: Write scientific prose in Anton Nekrutenko's voice — flowing sentences at ~22 words, every term defined at first use, we-led active voice, numbers with denominators, no LLM filler.
---

# Nekrutenko style

Apply these rules to any manuscript text for this project. They come from 14
published papers (2,392 sentences, ~56k words); the numbers are corpus
measurements, not preferences.

## 1. Sentence statistics — the targets
- Mean 20–23 words, median 21, over the document — not per sentence. About 10%
  of sentences may exceed 35 words and 4% may exceed 45. Do not cap length.
- Short sentences (≤10 words) are 8–12% of the text and must be placed, not
  sprinkled. Three legal positions: pivot opening a paragraph ("Despite its
  power DS is a complex technique."), verdict after evidence ("No linkage
  between any SNVs was observed."), hand-off ("Results of this analysis are
  shown in Fig. 6."). Never three consecutive sentences under 12 words.

A long sentence is safe when all four hold, and each is checkable by eye: 1) one
subject, stated early, with the main verb inside the first 12 words; 2) extra
facts appended rightward — coordinated predicates, a colon, a dash, parentheses
— never nested before the main verb; 3) no clause interrupting another clause
mid-phrase; 4) every term already defined, or defined inside the sentence. If a
long sentence fails one of these, fix the structure. Do not split it into
one-fact sentences: choppy prose at ~15 words removes the signals that tell the
reader which fact is the claim and which are its qualifiers.

## 2. Explanation-first rule

Every term of art is defined or exemplified at first use, in the same sentence,
by dash, parenthesis, appositive, or quotation marks. A reader who knows biology
but not this system must never meet an unexplained mechanism.

Mechanism before name: describe what happens in physical steps, then attach the
label — "the descendants of each original DNA fragment are identified and
grouped together using tags—that is, one simply sorts tags in sequencing reads
lexicographically" comes before SSCS and DCS are named.

Banned without a gloss: any noun compound naming a thing you built or ran
("bounded repair arm", "single-pass", "scaffold failure", "plan gradient",
"binder", "copier"). Define it at first use, or write what happened instead.

BEFORE (unpublishable — three undefined terms, no mechanism, 15 words):

> The perturbation above is single-pass, so a bounded repair arm re-ran it with
> feedback.

AFTER (his voice — the reader learns what was done):

> The moved-path test above gave each model one attempt: it wrote a script, the
> script ran, and that was the end of the trial. We then repeated the test
> allowing up to three attempts. After each failure the model was shown the
> script it had just written and the error message the script produced, and
> could submit a replacement.

Any rewrite of jargon must do the same four things: name the thing in the
reader's terms ("the moved-path test"), spell out the constraint instead of
labeling it, use a colon to unpack the claim, and say what the model actually
saw rather than naming the apparatus that showed it.

## 3. Paragraph shape
- Sentence 1 is the claim, as a declarative verdict — not orientation, not "In
  this section we". Middle sentences are evidence: instances, numbers, named
  mechanisms. The last sentence states a consequence, a decision, or a forward
  pointer, and never restates sentence 1.
- Results paragraphs run motivation → result → interpretation, and may be three
  sentences: "Because the distance between SNVs … is shorter than the length of
  the duplex reads, we examined our data for evidence of linkage. No linkage
  between any SNVs was observed. This is not unexpected because …"
- Tradeoff paragraphs end in a choice ("…and we chose it as the default
  alignment engine for Du Novo."); never leave both sides unresolved.
- Standard limitation close is concession-then-salvage: "While our diagonal
  partitioning scheme does not completely eliminate straddling alignments, it
  reduces them to a negligible number, as shown below."
- Chain sentences by anaphora: the previous sentence's object becomes the next
  sentence's subject (The/This/These openers).

## 4. Section openings

Abstract — one paragraph, 4–6 sentences, fixed order: flat statement of the
field or problem; the gap or its cost; "Here we describe/develop/demonstrate…";
findings in the order Results presents them; for tools, availability with the
URL as the literal last element. State the surprises and limits, not only wins.

Introduction — sentence 1 is a flat declarative about the object of study, with
a citation and no hook ("Bacterial plasmids are self-replicating genetic
elements that are fundamentally important to the evolution and adaptability of
their hosts."). By sentence 2–3 puncture it with "However," or "Yet". Then:
what is known → what limits it → what is newly possible → a one-sentence goal
("Our goal was to…"). A roadmap paragraph closes the Introduction of
platform/demo papers.

Results subsection titles are full findings ("Barcode error correction increases
yield") or task labels ("Selecting SRA data and launching workflow"), never
category words ("Performance", "Analysis"). Subsections open with the goal in
one sentence, with the state left by the previous subsection, or with the figure
pointer.

Discussion does positioning, failure dissection, and plans — never re-summary.
Name rival systems and compare against them, dissect your own failure in its own
paragraph ("Our analysis provides a cautionary tale…"), state limits flatly, and
argue against your own argument if it deserves it.

Methods are prose in past tense, one paragraph per stage, with versions, flags,
and catalog numbers inline and the rationale attached to each choice. Use
"Briefly," when the full version lives elsewhere.

## 5. Voice
- First person plural, active, for every action and every decision: "we
  trimmed", "we colored Figure 2 by lab group", "we chose it as the default".
  "we" should appear in roughly one sentence in five. Never "I".
- Passive is allowed in Methods for standard procedures ("Reads were aligned
  with bwa mem -M"), under ~1 sentence in 100 overall.
- The generic reader is "one", never "you": "one simply sorts tags…". Inclusive
  imperatives steer: "Let us look at these challenges in more detail".
- Every choice carries its reason in the same sentence: "We chose E. coli
  because of its relatively compact genome, making alignment simpler."
- Criticism is direct, aimed at methods rather than people, and attached to a
  mechanism or number: "However, lastZ was not built for speed:"; "only 1% (2 of
  203) of LFC-matched gene pairs were correct". Opinion is flagged once and then
  stated flatly: "In our opinion, …".
- Hedges, used singly, from this set only: likely, may, might, can, could be,
  appears to, seems to, suggests, potentially, expected to, it is unlikely that,
  not unexpected, we cannot rule out. Hedge biology, not engineering facts.
  Speculation gets its own sentence and names a mechanism. Intensify without
  hedging when the data warrant: "striking", "prohibitively expensive".

## 6. Vocabulary

Prefer these verbs: examine, evaluate, assess, employ, generate, produce,
reduce, increase, emerge, track, fade, purge, linger, sweep, incur, draw, scope,
color (a figure), slice, reshape, untangle, bind, pool, bracket, flatten,
circumvent, overcome, harbor, envision, recall. Mechanism-explainers: "This is
performed by…", "This was done by…".

Preferred connectives, corpus rate per 1,000 sentences: However (21), Thus (15),
In addition (8), Therefore (6). Also: Yet, Still, As a result, In contrast, In
the end, For example, Specifically, Briefly, In other words, First… Next…
Finally. Sentence-initial But/And/So are fine in plain-register passages.

Banned outright (corpus rate ≈ 0): Importantly, Notably, Crucially,
Interestingly, Remarkably, arguably, essentially as filler, delve, landscape as
metaphor, realm, paradigm, myriad, plethora, testament, holistic, showcase,
seamless without a mechanism, cutting-edge, state-of-the-art, robust as praise,
"It is worth noting that", "It should be emphasized that", "In conclusion,",
"Overall,", "To summarize,", "Firstly/Secondly", "represents a significant
advance", second-person "you", and marketing verbs (empowers, unlocks,
revolutionizes). "Novel": at most once per paper, next to a concrete referent.

No bold spans, no bullet stacks, no bold-led labels in prose sections. Enumerate
inline — "…for two reasons. First, … Second, …" or "1) … and 2) …" — and list
concrete distinct things, never triads of abstract nouns.

Numbers: exact, unrounded, with the denominator and percent in parentheses —
"only 1% (2 of 203)", "from 77,164 to 89,513". Comparisons put both values
adjacent: "8.61 (paper) versus 8.67 (our analysis)". Ratios over adjectives:
"58× more time than MAFFT at 10 reads". Approximate with "~", "around", "about".

Figures are referenced two ways only: appended parenthetically to a claim ("(red
dots in Fig. 1)"), or as the subject of a hand-off sentence ("Figure 2 shows the
range of error rates…"). Never "As shown in Figure 3, …" as an opener.

## 7. Punctuation
- Colon introduces the specific case, the cause, or the same fact in plainer
  words; it is the main long-sentence hinge, about 124 per 1,000 sentences.
- Em-dash does two jobs only: it glosses the noun immediately before it ("a
  BioProject identifier—an entity grouping related sequencing runs from a single
  study"), or carries the final verdict clause ("…in the short term—the exact
  dynamics observed in our experiment"). Never a pause, never a triad.
- Semicolon joins two independent clauses of equal weight where the second
  completes the first, or separates items inside a parenthesis; about 63 per
  1,000 sentences, and do not exceed that.
- Parentheses carry data, defaults, accessions, arithmetic, and asides; stacking
  them is fine. Scare quotes only for a term being coined or held at arm's
  length, used bare thereafter.
- Question marks are rare (about 7 in 56k words); each is answered in the next
  sentence or is a genuine open problem in a self-critique section.

## 8. Reviser's checklist — run over every paragraph
1. Does sentence 1 make a claim? If it orients or announces, delete it.
2. Does the last sentence add a consequence, decision, or pointer, rather than
   restate the first?
3. Is every term of art defined at first use, in that sentence? Find the nouns
   you invented and gloss each one.
4. Is any long sentence unsafe by §1 (buried verb, nested clause, undefined
   term)? Restructure it, do not chop it.
5. Are there three or more consecutive sentences under 12 words? Merge them.
6. Does every number carry its denominator, and every comparison both values?
7. Is "we" the subject of the actions, and is every choice paired with its
   reason in the same sentence?
8. Does any sentence open with Importantly, Notably, Interestingly, Crucially,
   Overall, In conclusion, or It is worth noting? Delete the opener and let the
   fact stand.
9. Any bold spans, bullet stacks, or abstract-noun triads? Convert to inline
   prose enumeration of concrete things.
10. Does each hedge stand alone and name what is uncertain, and does each
    tradeoff paragraph end in a decision?
