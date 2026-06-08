---
geometry: margin=1in
fontsize: 11pt
---

\begin{flushright}
Anton Nekrutenko\\
Department of Biochemistry and Molecular Biology\\
Penn State University\\
University Park, PA 16802\\
\href{mailto:anton@nekrut.org}{anton@nekrut.org}\\
May 13, 2026
\end{flushright}

\vspace{1em}

Editor\
*Genome Research*\
Cold Spring Harbor Laboratory Press

\vspace{1em}

Dear Editor,

I am submitting the enclosed manuscript, **"Evaluating open LLMs for agentic analysis orchestration in a typical biomedical lab"**, for consideration in *Genome Research*.

Within the next few years, a substantial fraction of routine biological data analysis will run inside agentic tools — software environments where a large language model plans the work, calls external tools, executes code, and iterates on the result. The shift is well underway in software engineering and is now arriving at the bench. The per-call inference cost of the frontier models that drive this shift is already prohibitive for laboratories that re-run the same workflow against new data many times per week. The work submitted here addresses that cost directly.

We tested whether a free, locally-runnable open-weight model could take over the repetitive execution steps of a real bioinformatics workflow at frontier accuracy. claude-opus-4-7 authored plans of increasing detail for per-sample mtDNA variant calling, and six 2026-release open-weight implementer LLMs ran those plans on a desktop GPU. qwen3.6:27b — a 17 GB Apache-2.0 model — reproduced frontier accuracy on every plan and matched Opus cell-for-cell on a 36-cell PATH-shim error-injection matrix across the NVIDIA Jetson AGX Orin, MacBook Pro M4 Pro, and 2× RTX A5000 platforms. A sub-\$2,000 NVIDIA Jetson AGX Orin Developer Kit or Apple Mac Mini sufficed for the implementer side.

Two features distinguish this work from the existing benchmark literature on LLMs in bioinformatics. First, we separate the recipe — the natural-language plan a frontier model writes once — from the implementer — the local model that executes that recipe many times; this split maps directly onto the model-swap features of OpenCode, Aider, Continue, the upcoming Galaxy Orbit Agent, and similar tools that an increasing share of laboratories will adopt. Second, because the open-weight model landscape evolves on the order of months, the specific implementer we recommend here will be superseded; we therefore release the plans, harness, scoring code, and per-cell artifacts under MIT at \href{https://github.com/nekrut/LLM-eval-paper}{https://github.com/nekrut/LLM-eval-paper} as a framework for re-evaluating any future model on the same task.

The manuscript fits *Genome Research*'s Methods scope: it presents both an evaluation of a tool class that is rapidly entering routine genomics work and a re-runnable framework that the community can apply to subsequent generations of models. The work is original, has not been published elsewhere, and is not under consideration by another journal. The sole author has approved the submission and declares no competing interests.

Thank you for considering this manuscript. I look forward to your editorial decision.

\vspace{1em}

Sincerely,

\vspace{2em}

Anton Nekrutenko
