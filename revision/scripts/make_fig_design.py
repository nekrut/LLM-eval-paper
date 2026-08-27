#!/usr/bin/env python3
"""Figure 1: two-benchmark study design schematic (R2.12, R3.16, R1.2)."""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

fig, ax = plt.subplots(figsize=(10.5, 5.6))
ax.set_xlim(0, 100); ax.set_ylim(0, 62); ax.axis("off")

def box(x, y, w, h, text, fc="#ffffff", ec="#333333", fs=8.5, weight="normal", ls="-"):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.6",
                                fc=fc, ec=ec, lw=1.1, linestyle=ls))
    ax.text(x + w / 2, y + h / 2, text, ha="center", va="center",
            fontsize=fs, fontweight=weight, linespacing=1.35)

def arrow(x1, y1, x2, y2, ls="-", color="#333333"):
    ax.add_patch(FancyArrowPatch((x1, y1), (x2, y2), arrowstyle="-|>",
                                 mutation_scale=11, lw=1.1, color=color, linestyle=ls))

# planner
box(2, 44, 26, 12,
    "PLANNER  (frontier model,\ncommercial API, off the executor machine)\n"
    "sees: workflow description, tool inventory,\ngeneric paths, de-identified labels",
    fc="#eef3f8", fs=8.0)
ax.text(15, 58.5, "authored once", ha="center", fontsize=8.5, style="italic")

# plan artifact
box(32, 45, 19, 10, "PLAN\n8 conditions, from no plan\nto near-executable",
    fc="#fdf6e3", fs=8.0, weight="bold")
arrow(28, 50, 32, 50)

# benchmark 1
box(56, 34, 42, 22, "", fc="#fbfbfb", ec="#999999", ls="--")
ax.text(77, 54.2, "BENCHMARK 1 — single pass, private board",
        ha="center", fontsize=9.5, fontweight="bold")
box(58, 43, 12, 7, "prompt\n(plan slot)", fs=7.5)
box(72, 43, 12, 7, "one bash\nscript", fs=7.5)
box(86, 43, 10, 7, "execute\n+ score", fs=7.5)
arrow(70, 46.5, 72, 46.5); arrow(84, 46.5, 86, 46.5)
ax.text(77, 38.5,
        "12 local executors x 9 (plan, track) cells x 3 seeds = 324\n"
        "3 frontier executors x 9 x 3 = 81  •  no observation, no retry",
        ha="center", fontsize=7.6, linespacing=1.4)
arrow(51, 50, 56, 50)

# benchmark 2
box(56, 4, 42, 26, "", fc="#fbfbfb", ec="#999999", ls="--")
ax.text(77, 28.2, "BENCHMARK 2 — tool-using loop, usegalaxy.org",
        ha="center", fontsize=9.5, fontweight="bold")
box(58, 18, 11, 7, "tool call\n(MCP)", fs=7.5)
box(72, 18, 11, 7, "observe\njob state", fs=7.5)
box(86, 18, 10, 7, "durable\nnotebook", fs=7.5)
arrow(69, 21.5, 72, 21.5); arrow(83, 21.5, 86, 21.5)
ax.add_patch(FancyArrowPatch((91, 17.4), (63.5, 17.4), connectionstyle="arc3,rad=-0.32",
                             arrowstyle="-|>", mutation_scale=11, lw=1.1, color="#333333"))
ax.text(77, 12.6, "repair / re-poll", ha="center", fontsize=7.4, style="italic")
ax.text(77, 8.0,
        "2 local executors, 1 invocation each + 1 human comparator arm\n"
        "30-step IWC rnaseq-pe workflow, 6 RNA-seq runs  •  case study, no replicates",
        ha="center", fontsize=7.6, linespacing=1.4)
arrow(41.5, 45, 41.5, 21.5); arrow(41.5, 21.5, 56, 21.5)

# governance boundary
ax.plot([53, 53], [2, 60], color="#b03030", lw=1.2, ls=":")
ax.text(53, 1.0, "governance boundary as used here (not enforced by the harness);\n"
                 "the frontier executor arms cross it — they transmit the dataset manifest",
        ha="center", fontsize=7.2, color="#b03030", linespacing=1.35)

fig.tight_layout()
fig.savefig("revision/figures/rev_fig0_design.png", dpi=200, bbox_inches="tight")
print("wrote revision/figures/rev_fig0_design.png")
