#!/usr/bin/env python3
"""Galaxy demonstration figure: what the two local executors actually produced.

Left  -- assigned fragments per sample, both arms overlaid. They coincide exactly,
         which is the point: two different models, two histories, identical counts.
Right -- assignment rate against the uniquely-mapped denominator (what the published
         ~92% refers to) and against all fragments. SRR22376029 and SRR22376030 fall
         only on the second, because they multi-map more -- a property of the data,
         not of the agent.
"""
import csv, pathlib
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

HERE = pathlib.Path(__file__).resolve().parent
rows = list(csv.DictReader(open(HERE / "featurecounts_summary.csv")))
samples = sorted({r["sample"] for r in rows})
by = {(r["arm"], r["sample"]): r for r in rows}

x = np.arange(len(samples))
fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(10.5, 3.9))

for arm, mk, sz, col in (("dense", "o", 70, "#2166ac"), ("moe", "x", 90, "#b2182b")):
    y = [int(by[(arm, s)]["assigned"]) / 1e6 for s in samples]
    ax1.scatter(x, y, marker=mk, s=sz, color=col, zorder=3,
                label=f"{arm} ({'qwen3.8:27b' if arm=='dense' else 'qwen3.6:35b-a3b'})")
ax1.set_xticks(x); ax1.set_xticklabels([s[-2:] for s in samples])
ax1.set_xlabel("SRR223760__", fontsize=9)
ax1.set_ylabel("assigned fragments (millions)", fontsize=9)
ax1.set_title("Both executors, identical counts", fontsize=10)
ax1.grid(axis="y", alpha=0.25, linestyle=":")
ax1.legend(fontsize=8, loc="lower right", framealpha=0.9)

u = [float(by[("dense", s)]["pct_assigned_unique"]) for s in samples]
a = [float(by[("dense", s)]["pct_assigned_all"]) for s in samples]
ax2.bar(x - 0.2, u, 0.4, color="#4393c3", label="of uniquely-mapped")
ax2.bar(x + 0.2, a, 0.4, color="#d6604d", label="of all fragments")
ax2.axhline(92, color="#333333", lw=1.1, linestyle="--")
ax2.text(len(samples) - 0.45, 92.9, "published ~92%", fontsize=7.5,
         ha="right", color="#333333")
ax2.set_xticks(x); ax2.set_xticklabels([s[-2:] for s in samples])
ax2.set_xlabel("SRR223760__", fontsize=9)
ax2.set_ylabel("percent assigned", fontsize=9)
ax2.set_ylim(0, 100)
ax2.set_title("Assignment rate depends on the denominator", fontsize=10)
ax2.legend(fontsize=8, loc="lower left", framealpha=0.9)
ax2.grid(axis="y", alpha=0.25, linestyle=":")

fig.tight_layout()
out = HERE / "galaxy_demo_counts.png"
fig.savefig(out, dpi=160)
print("wrote", out)
