# How Anton Nekrutenko Writes

## Scope and evidence

This report describes the prose style of fourteen published papers from the
Nekrutenko lab, comprising 2,392 sentences and roughly 56,000 words. The corpus
spans four genres: methods and tools papers (Du Novo 2016 and 2020, KegAlign
2025, Planemo 2023), primary analyses (plasmid evolution 2019, orf1ab 2021,
error profiles 2021, protein prediction 2023), platform and vision papers
(BRC-analytics 2025, BRC RNA-seq 2025, Galaxy/Jupyter 2017, SARS-CoV-2
infrastructure 2021), and opinion pieces (the MBE editorial of 2018 and the
Taylor memorial of 2020). Every statistic below was counted over the whole
corpus; every quoted passage is verbatim from one of the papers, with the
source named.

Two papers are stylistic outliers and should be treated as controls rather than
models: the protein prediction paper (Guerler first author) has zero em-dashes,
one semicolon, and twelve uses of "novel", and the Planemo paper is a large
multi-author Genome Research manuscript with smoother, longer periodic
sentences. The observations here draw predominantly from the remaining twelve,
where the voice is consistent enough to be described as one voice.

The single most useful number in this report is the mean sentence length: 22.8
words, with a median of 21 and a 90th percentile of 36. Eleven percent of
sentences run past 35 words and four percent past 45. This is not terse prose.
It is not, however, difficult prose, and the gap between those two facts is
what this report is about. He achieves plainness through explanation, not
through compression.

---

## 1. Sentence architecture

The default long sentence is a main clause followed by rightward accumulation,
not a nested construction with the verb held back. He states the thing, then
appends the facts that qualify it, in coordinated clauses, in parentheses, or
after a dash. The three-verb spine is his signature shape:

> "Variants at ten sites implicated in plasmid copy number control emerged
> almost immediately, tracked consistently across the experiment's time points,
> and faded below detectable frequencies toward the end." (plasmid 2019,
> Abstract)

> "We then filtered out single-ended and non-Illumina datasets, ordered the list
> to prefer a diversity of sequencing platforms and submitting groups, and
> prioritized runs that were the most likely to have the most read overlap."
> (error profiles 2021, Methods)

> "This plasmid contains a well understood ColE1 replication origin, has copy
> number of 15–20 per cell in nutritionally unconstrained conditions (Twigg and
> Sherratt 1980; Plotka et al. 2017) and carries three protein coding genes: a
> replication mediator rom and two antibiotic-resistance factors represented by
> a β-lactamase and a tetracycline efflux pump." (plasmid 2019, Results)

The last of these runs 54 words. It is readable because every clause hangs off
the same subject, because no clause interrupts another, and because the colon
hands the reader a list at exactly the moment the sentence stops adding
predicates.

The colon is his main long-sentence hinge, and it does two jobs: it introduces
the specific instance of a general claim, and it introduces the explanation of
the claim in plainer words than the claim itself. Colons appear 124 times per
1,000 sentences, more often than semicolons (63) or em-dashes (48).

> "There were two primary reasons for this: the use of MAFFT aligner and
> inadequate parallelization strategy for executing multiple consensus
> generating jobs." (Du Novo 2020)

> "The high R2 was an artifact: genes with coincidentally similar fold changes
> were matched, not the same genes." (BRC RNA-seq 2025)

> "The speed of this recovery can be used as a relative fitness estimate: the
> steeper the slope, the fitter the cells." (plasmid 2019)

> "we can use this assumption to identify barcodes containing sequencing errors:
> barcodes that differ from each other by just a few nucleotides are likely
> descendants of the same original sequence" (Du Novo 2020)

Note what happens after the colon in each case. The post-colon clause is never
a restatement in the same register; it is the same fact in shorter words, or the
mechanism behind the fact, or the concrete case of the abstraction. This is a
teaching device disguised as punctuation.

Em-dashes do exactly two jobs, and never a third. They gloss the noun that
precedes them, or they carry the verdict clause at the end of a sentence. They
are never used for a dramatic pause and never in breathless triads.

Gloss:

> "we then drew population samples at regular intervals and subjected them to
> duplex sequencing—a technique specifically designed for identification of
> low-frequency mutations." (plasmid 2019, Abstract)

> "Authors of the two papers we re-analyze here have deposited sequencing data
> into NCBI SRA and were given a BioProject identifier—an entity grouping
> related sequencing runs from a single study." (BRC RNA-seq 2025)

> "A significantly improved derivative of BLASTZ—lastZ [8]—is now used as the
> primary local-alignment engine" (KegAlign 2025)

Verdict:

> "Therefore, the spread of chromosomal change to fixation will obliterate
> plasmid variation in the short term—the exact dynamics observed in our
> experiment." (plasmid 2019)

> "The error was undetectable from the output alone—only independent validation
> against authoritative sources (NCBI official mappings, confirmed by protein
> sequence identity) revealed the problem." (BRC RNA-seq 2025)

> "This strategy comes at a cost—sequencing the same molecule multiple times
> increases dynamic range but significantly diminishes coverage" (Du Novo 2020,
> Abstract)

Semicolons are rare and narrow. In the plasmid paper, all 43 semicolons sit
inside parentheses, separating citation strings or condition lists: "short term
(60 h; replicates R1 and R2)", "(supplementary fig. S4, Supplementary Material
online; black dots)". Where a semicolon does join two independent clauses in
running prose, the two clauses are of equal weight and the second completes the
first:

> "These not only lead to an increased runtime; they also cause the GPU to idle
> for long periods of time" (KegAlign 2025)

> "nearly all lastZ executions are completed in less than 10 min; however, the
> longest execution takes over 27 h" (KegAlign 2025)

Short sentences appear at three positions only: the pivot, the verdict, and
the hand-off. They are not a rhythm device sprinkled at random. The plasmid
paper contains 94 sentences of eight words or fewer, and each one is doing one
of these three jobs.

> "But measuring error is a theoretically difficult task." (error profiles 2021
> — opens a paragraph)

> "Despite its power DS is a complex technique." (Du Novo 2020 — seven words
> opening a paragraph, followed by long elaboration)

> "No linkage between any SNVs was observed." (plasmid 2019 — verdict)

> "Both comparisons yielded strong validation metrics." (BRC RNA-seq 2025 —
> verdict before the numbers)

> "Results of this analysis are shown in Fig. 6." (BRC-analytics 2025 —
> hand-off)

> "Thus, a fundamentally different approach to partitioning is necessary."
> (KegAlign 2025 — hand-off to the next section)

Enumeration is inline, never bulleted. Across the primary-analysis and
opinion papers there are zero markdown bullets and zero bold spans. Lists live
inside sentences, numbered with bare "1)" or spelled out with "First… Second…":

> "Numerically (10−3 vs. 10−5), a chromosomal mutation is 1) more probable and
> 2) will likely occur at the wild-type plasmid background leaving the latter to
> appear unchanged after the sweep is complete." (plasmid 2019)

> "involves three steps: (1) generation of pairwise local alignments, (2)
> filtering and ordering of local alignment blocks, and (3) generation of
> multiple alignment blocks" (KegAlign 2025)

Parentheticals are load-bearing. They hold data, defaults, accessions,
arithmetic, and hedged asides — and they are stacked without apology.

> "requiring a user-specified number of reads to produce a consensus (three by
> default)" (Du Novo 2016)

> "(the remaining 6,921,891 − 2,083,140 = 4,838,751 were represented by families
> with less than three reads and were omitted; see Additional file 2: Figure S2)"
> (Du Novo 2016)

> "Depending on how (individual tool, or Snakemake, Nextflow, or Galaxy
> workflows) and where (one's laptop, an institutional cluster, a cloud, a
> Galaxy instance) this is done, the results may be more or less reproducible."
> (BRC-analytics 2025)

> "(the genome is circular but its textual representation is not)" (Du Novo 2016,
> Methods)

---

## 2. How he explains technical material

The canonical pattern is: name the thing, give the mechanism in one plain
sentence, walk the steps in temporal order, and only then attach the acronyms.
The duplex sequencing explanation is the clearest instance in the corpus, and he
has written it three times in three papers without ever leading with the
jargon:

> "It is based on using unique sequence tags to label individual molecules of
> the input DNA prior to preparation of Illumina sequencing libraries. During
> the amplification steps of library preparation, each of these molecules gives
> rise to multiple descendants. After sequencing, the descendants of each
> original DNA fragment are identified and grouped together using tags—that is,
> one simply sorts tags in sequencing reads lexicographically, and all reads
> containing the same tag are bundled into families. These families (usually
> with at least three members) form single-strand consensus sequences (SSCS) for
> the forward or the reverse strand, respectively. Complementary SSCS are then
> grouped to produce duplex consensus sequences (DCS). A true sequence variant
> is present in all reads within a family forming a duplex. In contrast,
> sequencing and amplification errors will manifest themselves as
> 'polymorphisms' within a family, and so they can be identified and reliably
> removed." (plasmid 2019, Introduction)

Three things are worth naming here. First, "that is, one simply sorts tags in
sequencing reads lexicographically" converts an abstract grouping operation into
a physical action the reader can picture. Second, SSCS and DCS arrive after the
mechanism has already been described, so the acronym is a label for something
the reader already understands rather than a thing to be understood. Third, the
passage ends on an opposition — a true variant behaves one way, an error behaves
the other — which is his standard closing move for a mechanism.

Every term of art is defined at the moment of first use, in the same sentence,
by dash, parenthesis, quotation marks, or appositive. He does not write a
background sentence and then use the term; the definition rides along with the
term.

> "we normalize the order of the concatenation to produce a 'canonical barcode'
> (a concatenated string consisting of α and β tags), which will be identical
> for both strands" (Du Novo 2016)

> "straddling alignments (additional and duplicate alignments which are caused
> by violating dependencies when partitioning)" (KegAlign 2025)

> "In the above prompt we specifically mentioned 'Collection #244'—a Galaxy
> artifact containing read counts for all samples described in this study" (BRC
> RNA-seq 2025)

> "It is built around the concept of Jupyter notebook—a web application allowing
> the combining of executable programming language code with visualization and
> explanatory annotations into a single 'live' document." (Galaxy/Jupyter 2017)

New coinages arrive in scare quotes and are then used bare: "flickering sites",
"what we call tail latency", "a 'keg'—compressed tar archive containing
partition files".

The worked toy example with round numbers is his strongest teaching device.
It is introduced by an imperative to the reader, the arithmetic is shown inline
in parentheses, and the result is then restated in English. He does the number
twice, once as math and once as a sentence.

> "To illustrate this point, envision a bacterial cell with a 106 nucleotide
> chromosome carrying 10 copies of a 1,000 nucleotide plasmid. Assuming a
> mutation rate of 10−9 per site per generation (as in E. coli; …), the rate per
> genome and per plasmid will be 10−3 (10−9×106) and 10−5 (10−9×1000×10),
> respectively. In other words, in a given generation 1 out 1,000 cells is
> expected to incur a chromosomal mutation, while for the plasmid this number is
> 1 out of 100,000 molecules." (plasmid 2019)

> "Now, suppose in a hypothetical duplex experiment ten initial fragments of DNA
> were ligated with α and β adapters (a unique α and β for each of the ten
> fragments) and the subsequent PCR amplification and Illumina sequencing
> process produced 100 read pairs (10 pairs per original fragment). If there are
> no errors, these 100 read pairs should be recognized as members of ten duplex
> families during the analysis stage. If we now factor in the erroneous barcode
> rate of ~52 % calculated above, one would observe 62 total families: ten real
> families and 52 artifactual families consisting of a single read pair." (Du
> Novo 2016)

The same device is used to demolish a competing method, with the competitor's
own numbers, and it produces one of the two exclamation marks in the corpus:

> "For example, San Millan et al. (2014) used 2 ml of the overnight bacterial
> culture … This volume conservatively contains ∼108 cells. Considering the mean
> estimated pNUK73 copy number of 11 (San Millan et al. 2014), this amount of
> cells contains ∼109 plasmid molecules. Thus, a variant detection threshold of
> ∼1% will miss all variants present in fewer than ∼107 plasmids!" (plasmid 2019)

Alternatives are walked through and killed one at a time, each with its own
named failure mode. He does not dismiss a rival approach with an adjective; he
describes what it would do and where it would break.

> "Some have taken a simple approach, aligning reads to a reference and calling
> variants as errors (6). But real variants will then be misclassified as errors
> as well. Instead, one could first perform variant calling, assuming the
> majority allele at any position is correct and any minor alleles are errors.
> This will work well for samples that are known to be highly homogeneous, but
> otherwise there may be true minor alleles which would be mistaken for errors
> (8)." (error profiles 2021)

The counter-scenario is his other teaching device: he narrates the reader's
current painful workflow as a story with a protagonist, then contrasts it with
the new one.

> "Suppose a student in a lab performs a re-analysis of published surveillance
> datasets. These datasets—fastq files from the sequence read archive (SRA) such
> as NCBI or EBI—are first downloaded to local computers. Next, these data need
> to be mapped against the suitable reference genome for the pathogen in
> question. For this the reference also needs to be located and downloaded. …
> The entire process is usually condensed into a version of '…analyzed using a
> collection of custom Python scripts' found in tens of thousands of
> manuscripts." (BRC-analytics 2025)

Design decisions always carry their rationale, in one attached clause. The
reason is never deferred to a discussion section.

> "We chose E. coli because of its relatively compact genome, making sequence
> alignment simpler." (error profiles 2021)

> "We specifically chose tetracycline over ampicillin because β-lactamase … can
> diffuse into the medium and provide 'collateral' resistance to plasmid-free
> cells (Vega and Gore 2014)." (plasmid 2019)

> "Since the median family size for an ideal duplex experiment is only around a
> dozen reads, Kalign2's advantage is significant and we chose it as the default
> alignment engine for Du Novo." (Du Novo 2020)

Complexity is framed as a tradeoff between two named failure modes, and the
paragraph then makes a choice.

> "Too much DNA results in small family sizes and makes variant identification
> impossible, while too little creates very large families at the expense of
> sequencing coverage." (Du Novo 2020)

> "When setting a stringent edit distance threshold of 1, erroneous corrections
> (false positives) occurred only five times… But the tradeoff was that Du Novo
> was only able to catch and correct 67.28% of barcodes containing errors." (Du
> Novo 2020)

---

## 3. Paragraph craft

The dominant shape is claim, evidence, consequence. The first sentence
asserts; the middle sentences supply instances and numbers; the last sentence
states what follows. Openers are declarative verdicts, not orientation.

> [claim] "Despite tool convergence, reference genome usage remains
> inconsistent." → [evidence] "While 60% of published studies use B8441
> (GCA_002759435 family), annotation versions vary—some cite only 'B8441'
> without version, others specify GCA_002759435.2 or GCA_002759435.3." →
> [parallel case] "Similarly, tool version reporting is frequently incomplete or
> absent…" → [verdict] "Without precise version information, reproducing
> published results becomes guesswork." (BRC RNA-seq 2025)

Results paragraphs are narrated experiments in three parts: motivation,
result, interpretation. The compact canonical unit runs three sentences:

> "Because the distance between SNVs located within the replication origin is
> shorter than the length of the duplex reads, we examined our data for evidence
> of linkage. No linkage between any SNVs was observed. This is not unexpected
> because …" (plasmid 2019)

Longer ones open with the analysis rather than the finding, and put the numbers
bare and immediately:

> "Both comparisons yielded strong validation metrics. For the first
> (tnSWI1/AR0382_WT) comparison, we successfully mapped 203 differentially
> expressed genes and obtained R2 = 0.94 with 99% direction agreement. The
> second comparison (AR0382_WT/AR0387_WT) mapped 165 genes with R2 = 0.89 and
> 97% direction agreement." (BRC RNA-seq 2025)

Paragraph endings do interpretive work. They are consequences, decisions,
or forward pointers, never restatements of the paragraph's own topic sentence.

> "The fact that these mutations increase growth rate with or without plasmid
> indicate that they are likely involved in adaptation to the growth conditions
> rather than to the presence of the plasmid." (plasmid 2019)

> "In the end, the commonality between these two clusters was the group (GEO),
> not the experiment type. This shows the power of the metadata to test
> hypotheses." (error profiles 2021)

> "We are currently developing a family reconstruction approach that would allow
> mismatches in tags and is expected to significantly reduce the number of
> single read families." (Du Novo 2016)

> "Thus, the allele frequency estimates were essentially identical between the
> two approaches." (Du Novo 2016)

A paragraph may open with the question the previous paragraph raised, and then
answer it in the next sentence. The corpus contains very few question marks —
four in one paper of 14,000 words, three in another — and none of them is
decorative.

> "These results raised a question on how to explain the discrepancy between
> growth rates of plasmid-containing and cured R6 and R7 isolates listed in
> table 1: why is the growth rate of plasmid containing R6-S27 twice that of
> R7-S27, while cured R6-S27 and R7-S27 have largely identical growth rates? The
> answer is in the fact that for plasmid-containing isolates the growth rate was
> measured for the population of cells, while for plasmid-free growth rates are
> for individual clones picked as single colonies…" (plasmid 2019)

The concession-then-salvage close is a recurring ending. He admits the
limitation and then states what survives it, in the same sentence.

> "While this was only a simulation and the above calculations make a number of
> simplifying assumptions, they nevertheless highlight the significance of
> sequencing errors within tags as one of the main causes of data loss." (Du
> Novo 2016)

> "While our diagonal partitioning scheme does not completely eliminate
> straddling alignments, it reduces them to a negligible number, as shown
> below." (KegAlign 2025)

---

## 4. Section conventions

Abstract. Four to six sentences, one paragraph, no in-prose headings. The
order is fixed: a flat statement of the field or the problem, the cost or gap,
"Here we describe / develop / introduce / demonstrate", the findings in the
order they occur in Results, and — in tool papers — availability with a URL as
the literal last element.

> "Duplex sequencing was originally developed to detect rare nucleotide
> polymorphisms normally obscured by the noise of high-throughput sequencing.
> Here we describe a new, streamlined, reference-free approach… We show the
> approach performs well on simulated data and precisely reproduces previously
> published results… Finally, we provide all necessary tools as stand-alone
> components as well as integrate them into the Galaxy platform. All analyses
> performed in this manuscript can be repeated exactly as described at
> http://usegalaxy.org/duplex." (Du Novo 2016)

Abstracts state the surprises and the limits, not only the wins: "But we also
discovered that there is great variation within each platform"; "Contrary to
expectations based on the underlying chemistry, HiSeq X Ten and NovaSeq 6000
share notable exceptions to the preceding-base bias." In the plasmid paper the
abstract's last sentence is reused verbatim as the Discussion's last sentence.

Introduction. Sentence one is a flat declarative about the object of study,
with a citation and no hook.

> "Bacterial plasmids are self-replicating genetic elements that are
> fundamentally important to the evolution and adaptability of their hosts."
> (plasmid 2019)

> "Coronaviruses have large 26–32 kbp positive-strand RNA genomes." (orf1ab 2021)

> "Trees, rivers, and the analysis of next generation sequencing (NGS) data are
> examples of branching systems so ubiquitous in nature [1]."
> (Galaxy/Jupyter 2017)

By sentence two or three the field statement is punctured with a "However" or a
"Yet":

> "The term 'genetic variation' is often used to imply allelic combinatorics
> within a diploid organism such as humans or Drosophila. Yet the majority of
> organisms in the biosphere are not diploid" (Du Novo 2016)

> "International efforts such as the Earth BioGenome Project aim to produce
> reference genomes for all ~ 1.8 million known eukaryotic species over the next
> decade [1–4]… However, a sequenced genome is just a file with little utility
> on its own." (KegAlign 2025)

The arc from there is fixed: what the thing is, what is known, what limits the
known, what is newly possible, what we did. The limitation paragraph is
signposted plainly — "One potential limitation of the previous studies is low
resolution of methods used to detect sequence variants" — and the Introduction
closes on a one-sentence goal or contribution statement:

> "Our goal was to reconcile these predictions by tracing plasmid mutations as
> they emerge during a coevolution experiment using duplex sequencing." (plasmid
> 2019)

> "Our goal was to make pairwise genome alignment universally accessible by
> optimizing it such that it can be performed on a single compute node within
> several hours." (KegAlign 2025)

In the platform papers the goal statement is followed by a roadmap paragraph
listing, in order, what the reader will see.

Results subsection titles are full findings or task labels, not category
words. "Du Novo reliably identifies very low frequency variants"; "Barcode
errors result in lost data"; "Emergence of Variation Followed by Crash";
"Variants Are Restricted to Copy Number Control Elements"; "Smarter
parallelization improves speed"; "The CPU underutilization problem". Where the
paper is a walkthrough rather than a study, titles become gerund task labels:
"Selecting genome: Using NCBI Datasets for reference data"; "Making sense of
variants: Combining LLMs and JupyterLite".

Subsections open either with the figure pointer, with the goal restated in one
sentence, or with the general fact the analysis tests.

> "Our goal is to perform a variant identification analysis: sequence data
> (reads) are mapped against a reference genome and mismatches between the reads
> and the genome are evaluated to identify likely changes." (BRC-analytics 2025)

> "The workflow described above produced a list of variants observed in each
> sample. Such a list by itself does not provide any valuable biological
> insights." (BRC-analytics 2025)

> "Figure 2 shows the range of error rates in samples from different platforms."
> (error profiles 2021)

Discussion does positioning, failure analysis, and future work — never
re-summary. Three moves recur. He reconciles his result with other groups'
data by name ("Results from other groups support this conclusion. In a recent
work, San Millan et al. (2016) …"). He dissects his own failures in a titled
section, phrased as open questions rather than boilerplate limitations:

> "Although our model captures the underlying dynamics well, there are a number
> of discrepancies and unknowns. If it is so difficult to maintain a balance
> between the benefit of increased copy number and related metabolic burden,
> then how does the mutation we observed reach even these low but still
> detectable frequencies? … Answering these questions will require assessing the
> validity of our assumptions and considering new experiments." (plasmid 2019)

> "Our analysis provides a cautionary tale about AI-assisted research. Initially,
> Claude Code Agent proposed an alternative approach to gene ID mapping … To the
> untrained eye this suggestion sounded 'scientific'. … However, subsequent
> comparison against the official NCBI old_locus_tag mapping revealed that only
> 1% (2 of 203) of LFC-matched gene pairs were correct." (BRC RNA-seq 2025)

And he argues against a named rival system, then argues against himself in the
following paragraph: "However, capable AI agents partially flatten these
distinctions. … Once researchers adopt CLI-based AI tools, the barrier to
Nextflow drops as well."

Methods are prose. They narrate in past tense for experiments and present
tense for algorithms, they carry catalog numbers, version strings, and flags
inline, and they interleave the rationale that a bullet list could not hold.

> "Then it indexes them, along with their reversed (b + a) versions, with
> bowtie-build and aligns them to the index with bowtie -v 3 --best -a." (Du
> Novo 2020)

> "Paired-end Illumina reads were first quality-filtered and adapter-trimmed
> with fastp v1.0.1 [18] using default parameters. When an amplicon primer
> scheme was provided, primer sequences were removed with iVar trim v1.4.4 [19]."
> (BRC-analytics 2025)

> "If it was in different bins in the two reads, we took the greatest of the two
> (the bin furthest toward the 3′-end of the read). This is because the main
> purpose of binning is to reduce the effect of errors increasing toward the end
> of reads." (error profiles 2021)

The word "Briefly," is the compression marker: it appears when the same material
exists at higher density elsewhere, either in a prior publication or in the
paper's own Methods. "For a detailed workflow description see Methods. Briefly,
reads are first quality- and adapter-trimmed with fastp…"

Data availability is written as instructions to a person, not as a
boilerplate statement: "The sample directories should be placed in a 'runs'
directory—the parent of runs will be the MAIN_DIR in Jupyter. The rest is
explained in the Github README.md."

---

## 5. Voice

First person plural, active, everywhere. "We" appears in about 18% of all
sentences in the corpus and "our" in about 5%; passive constructions in Methods
run at 8 per 1,000 sentences. "We" is the agent of physical and procedural
verbs — "we trimmed barcodes off of all sequencing reads", "we colored Figure 2
by lab group", "we scoped our survey to only this manufacturer", "we simply
redirected these outputs to an intermediate buffer stored on disk" — and it is
also the agent of decisions and hopes: "we chose it as the default alignment
engine", "we hope to reach a wide audience". First person singular never
appears; where a co-authored piece needs it, the author names himself
parenthetically: "James worked closely with me (Anton Nekrutenko)".

The reader is addressed as "one", never as "you". This is his substitute for
second person and it appears whenever a generic analyst is doing something.

> "one simply sorts tags in sequencing reads lexicographically"
> "One could simply perform a two-way alignment of each pair of mates to each
> other."
> "These studies are useful when one is deciding on an instrument to use."
> "Clearly, the majority of these sites are false-positives but how does one
> know for certain?"

Inclusive imperatives do the rest of the reader-steering: "Let us look at these
challenges in more detail"; "Consider transcriptome analysis as an example";
"To illustrate this point, envision a bacterial cell with…".

Criticism is direct, aimed at methods and systems rather than people, and
always attached to a stated mechanism or number.

> "However, lastZ was not built for speed" (KegAlign 2025)

> "we discovered that SegAlign does not utilize hardware resources effectively.
> Specifically, often all hardware resources—both CPU and GPU—wait for a few
> long-running CPU threads to complete their work." (KegAlign 2025)

> "Unfortunately, the SRA metadata schema is far from complete, and there are
> some important features of a sequencing experiment which are not captured."
> (error profiles 2021)

> "Without precise version information, reproducing published results becomes
> guesswork." (BRC RNA-seq 2025)

> "This presented a less exciting picture: only three tools contained enough
> information (documentation and/or tutorials) to actually be easily installed
> and used." (MBE editorial 2018)

Opinion is flagged and then stated flatly. He does not disguise a judgment
as a finding, and he does not soften it once flagged: "In our opinion, this has
the potential to streamline the ways in which biomedical data analysis is
performed"; "Before describing our computational setup, we emphasize that any
results produced by LLMs must always be verified"; "stand-alone web applications
have limited utility".

Hedging vocabulary is a small closed set, used singly. likely, may, might,
can, could be, appears to, seems to, suggests, potentially, expected to, it is
unlikely that, not unexpected, we cannot rule out. Hedges cluster on biological
interpretation and disappear on engineering claims.

> "which likely represent neutral variants lost due to genetic drift"
> "There seem to be two categories of platforms"
> "This could be because of the higher overhead in the more complicated
> parallelization algorithm, or other changes between 0.4 and 2.15"
> "it is unlikely if RecA has any direct effect on the pattern observed here"

Speculation is given its own sentence and names a specific mechanism: "One
explanation could be that users of these machines spend more time optimizing
their runs, since a low-quality run would be a much more expensive loss."

He also intensifies without hedging when the data warrant it: "There is a
striking abundance of combinations that appear only once"; "prohibitively
expensive"; "formidable coverage"; "superb sensitivity".

Color is sparse, physical, and always tied to the argument.

> "Still, this is only the tip of the iceberg, with the majority of variants
> remaining below the surface." (plasmid 2019)
> "they linger but never fix" (plasmid 2019)
> "Even researchers choosing technologies for their own data may find it useful
> to know how much their mileage may vary." (error profiles 2021)
> "Luckily, information like this is captured in SRA metadata." (error profiles
> 2021)
> "the infrastructure suitable for computing alignments is provided as well!"
> (KegAlign 2025)
> "their two classical Genetics papers contained all (!) data in the main text"
> (MBE editorial 2018)
> "What does it take to convert a heap of sequencing data into a publishable
> result?" (Galaxy/Jupyter 2017 — "heap", not "volume")

---

## 6. Word choice

Verbs are plain, transitive, and physical. emerged, tracked, faded, crashed,
purged, obliterated, lingered, swept, incurred, drew, forced, scoped, colored,
harbors, envision, recall, slice, reshape, untangle, bind, pool, bracket,
flatten, examine, evaluate, assess, employ, generate, produce, reduce,
circumvent, overcome. "This is performed by…" and "This was done by…" are his
standard mechanism-explainers.

Connectives are few and repeated. Per 1,000 sentences the corpus contains 21
"however", 15 "thus", 8 "in addition", 6 "therefore", and 2 "furthermore". His
contrastive workhorse is "However,"; his pivots are "Yet," and "Still,"; his
consequence markers are "Thus," "Therefore," "As a result," and "In the end,".
"For example," precedes nearly every abstraction. "In other words," introduces
the plain-English restatement of something just given as math. "Briefly,"
compresses. In the plainest of the papers, sentence-initial "But", "And", and
"So" are used freely as a deliberate speech register: "But real variants will
then be misclassified as errors as well."

Quantities are exact, unrounded, and immediately re-expressed in an intuitive
unit.

> "It took 58× more time than MAFFT at 10 reads, and 427× more at 40 reads." (Du
> Novo 2020)
> "the number of DSC increased from 77,164 to 89,513" (Du Novo 2020)
> "only 1 in 163,267 of these newly formed families are artifactual" (Du Novo
> 2020)
> "These vary from 0.087% in HiSeq X Ten to 0.613% in MiniSeq." (error profiles
> 2021)
> "So in MiniSeq, G substitutions follow G 3mers about three times more often
> than if substitutions were distributed randomly." (error profiles 2021)
> "Of 64 BioProjects, 20 (31%) had linked manuscripts" (BRC RNA-seq 2025)
> "reproducing the standard UCSC multiZ alignment of 100 vertebrates using the
> human genome as the reference would take around ~ 30 CPU years" (KegAlign 2025)

Comparisons are stated as X versus Y with both values adjacent: "SCF1 exhibited
LFC of 8.61 (paper) versus 8.67 (our analysis) in vitro". Approximation is
marked with "~", "around", or "about", never with a vague intensifier.

Figures are referenced two ways only: appended parenthetically to a claim
("(red dots in Fig. 1)", "(supplementary fig. S3A and B, Supplementary Material
online)"), or as the grammatical subject of a hand-off sentence ("Figure 2 shows
the range of error rates in samples from different platforms."). He never writes
"As shown in Figure 3, …" as a sentence opener. He points at specific columns
when it helps: "(the two 'Count' columns in table 1)".

Words he does not reach for. Across the corpus: "importantly" and "notably"
appear twice each in 56,000 words, and neither is ever a paragraph opener;
"crucially" appears once, in a multi-author section; "interestingly" appears
twice. Absent entirely: arguably, delve, landscape as metaphor, realm, paradigm,
myriad, plethora, tapestry, testament as filler, holistic, showcase, seamless
without a mechanism attached, cutting-edge, state-of-the-art, robust as praise,
"it is worth noting that", "it should be emphasized that", "In conclusion,",
"Overall,", "To summarize,", "Firstly/Secondly". "Novel" appears zero times in
the primary analyses and three times in the platform papers, always next to a
concrete referent.

---

## 7. Two contrasts

### 7a. Against generic LLM prose

The differences are structural, not decorative. Six of them matter.

Emphasis is carried by content, not by adverbs. Generic model prose dresses
a claim with "Importantly," or "Notably," before stating it. He instead makes
the sentence itself carry the weight: "This increase in yield—the most important
consequence of error correction—was substantial." The corpus contains two
instances of "importantly" in 56,000 words, and neither opens a paragraph.

Structure lives in sentences, not in typography. There are zero bold spans
and zero bulleted stacks in the primary papers. Where a model would produce a
"Speed: …" list, he produces "1) … and 2) …" inside one sentence, or
"First, … Second, …" across two. Bullets appear only in availability sections
listing genuinely enumerable things, and even those are written as full
sentences: "KegAlign—g3.medium node at https://jetstream-cloud.org/. The node
provides eight CPUs and one A100 GPU…"

Lists are of concrete things, never triads of abstract nouns. No
"scalability, reproducibility, and transparency". Instead: "sizes, replication
strategies, and transmission modes"; "PCR errors, cloning polymorphisms, DNA
damage or other library preparation errors"; "It is written in Python, C, AWK,
and Bash."

Every tradeoff ends in a decision. The generic form — "While X has
advantages, it also has drawbacks" — never appears without resolution. His
tradeoff paragraphs close with "we chose it as the default alignment engine for
Du Novo" or "we instead chose to take advantage of new NVIDIA GPU features".

Rhetorical questions are never transitions. The corpus contains seven
question marks in total. Two are answered in the next sentence ("So why use it?
The key advantage of lastZ is its ability to find alignments between highly
divergent sequences."), one is answered two sentences later, and the rest are
genuine open problems posed in a self-critique section.

Hedges are specific, not stacked. He never writes "this may potentially
suggest that it could be possible". A hedged claim carries one hedge and names
the mechanism it is uncertain about: "This could be because of the higher
overhead in the more complicated parallelization algorithm, or other changes
between 0.4 and 2.15."

Two further absences are worth naming because they are the tells: he does not
close with "In conclusion, X represents a significant advance" — his Conclusions
state what was done and where to get it — and he does not claim novelty as an
adjective. Merit adjectives are earned and specific: "superb sensitivity",
"formidable coverage", "a convenient single tool".

### 7b. Against choppy over-simplified prose

The opposite failure is more tempting, because it looks like plain writing. It
is not. Prose written at a mean of 15 words per sentence, one fact per sentence,
reads as a list of assertions with the connective tissue removed, and the
connective tissue is where the explanation lives.

His corpus settles at 22.8 words per sentence, with 11% of sentences past 35
words. He is not compressing. Consider what happens if the plasmid Results
sentence is broken up:

> Original (54 words): "This plasmid contains a well understood ColE1
> replication origin, has copy number of 15–20 per cell in nutritionally
> unconstrained conditions (Twigg and Sherratt 1980; Plotka et al. 2017) and
> carries three protein coding genes: a replication mediator rom and two
> antibiotic-resistance factors represented by a β-lactamase and a tetracycline
> efflux pump."

> Choppy rewrite: "This plasmid contains a ColE1 replication origin. The origin
> is well understood. Copy number is 15–20 per cell. This holds under
> nutritionally unconstrained conditions. The plasmid carries three protein
> coding genes. One is a replication mediator, rom. Two are
> antibiotic-resistance factors. These are a β-lactamase and a tetracycline
> efflux pump."

The rewrite is shorter per sentence and harder to read. Nothing tells the reader
that the three genes are the elaboration of "three protein coding genes" rather
than four new facts; the colon did that work in the original. Nothing subordinates
"the origin is well understood" to the origin; the relative clause did that.
Eight sentences of equal weight give the reader no signal about which fact is
the claim and which are its qualifiers, so the reader must hold all eight and
sort them out afterwards.

The corpus does contain short sentences — 94 of eight words or fewer in one
paper alone — but they are placed, not distributed. "No linkage between any SNVs
was observed." works because it lands after a 34-word sentence explaining why
linkage was looked for. Take away the long sentence and the short one has
nothing to be short against.

The rule the corpus supports is this: length should track the number of facts
that belong together, and plainness should come from defining terms, naming
mechanisms, and choosing concrete verbs. A 45-word sentence is safe when it has
one subject, coordinated predicates, and its qualifications appended rightward.
It is unsafe when the reader must hold an unresolved clause across the main
verb, or when it contains a term that was never defined. Both failures are
fixable without shortening anything.

---

## 8. What the style comes down to

Say the thing first, in a full sentence, with the subject a concrete noun and
the verb a physical action. Attach the qualifications rightward, using a colon
for the specific case and an em-dash for the gloss. Define every term at the
moment you first use it. Give a worked example with small round numbers, show
the arithmetic, and then restate the answer in English. Put the number in, with
its denominator. Say who did it: we. Say why you chose it, in the same sentence
as the choice. When you criticize, name the mechanism that fails and attach a
figure. When you hedge, hedge once and say what you are uncertain about. End the
paragraph on the consequence, and end the section by handing off to the next
one.
