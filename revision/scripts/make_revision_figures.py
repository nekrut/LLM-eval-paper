#!/usr/bin/env python3
"""
Figures for the revision matrix -> revision/figures/.

Four panels:
  rev_fig1_gradient_thinkoff.png  plan gradient, reasoning off (12 models)
  rev_fig2_gradient_thinkon.png   plan gradient, reasoning on  (10 models)
  rev_fig3_reasoning_delta.png    think-on minus think-off -- the headline
  rev_fig4_n3_vs_n10.png          what n=3 got wrong (answers R3.8)

Panel 3 is the one that matters. It shows reasoning substituting for plan
detail in the middle of the gradient and *hurting* at v2, where the plan is
already near-executable. Diverging colour map centred on zero so the sign
change is the visually obvious feature.

Conventions that must not be broken (see revision/scripts/gradient.py):
  - every Track-B run is a no-plan run regardless of plan file -> column "B"
  - the delta panel uses only the 10 models runnable in both arms
  - truncations/give-ups score 0; infrastructure faults are excluded
  - panels 1-3 use the n=3 matrix ONLY. The n=10 v2 pass is deliberately kept
    out of them: folding it into the think-off v2 column alone would make the
    delta panel compare n=10 against n=3 in that one cell, so a column would
    move for a sampling reason rather than a reasoning one. The n=10 data is
    a separate result and gets its own panel.

Usage: python3 revision/scripts/make_revision_figures.py
"""
from __future__ import annotations
import collections
import json
import statistics as st
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

REPO = Path(__file__).resolve().parent.parent.parent
LOGS = REPO / "revision" / "logs"
FIGS = REPO / "revision" / "figures"
FIGS.mkdir(parents=True, exist_ok=True)

PLAN_LABEL = {"b": "B", "v0p5": "v0.5", "v1": "v1", "v1g": "v1g",
              "v1p25": "v1.25", "v1p5": "v1.5", "v2": "v2"}
COLS = ["B", "v0.5", "v1", "v1g", "v1.25", "v1.5", "v2"]
GRANITE = {"granite4.1_30b-q4_K_M", "granite4.1_8b-q4_K_M"}


def pretty(m: str) -> str:
    return m.replace("-q4_K_M", "").replace("_q4_K_M", "").replace("-it", "").replace("_", ":", 1)


# qwen3.8 was added after the main matrix had already run, so its cells live in
# their own logs rather than in matrix_jetson_think{off,on}.jsonl. They ran
# under identical settings (same quant, same ollama config, same seeds, same
# 16k budget), so they belong in the same panels -- but ONLY these. Budget
# ablation runs use a different num_ctx and must never be pooled here; they are
# kept in separate logs that this list deliberately does not name.
ARM_LOGS = {
    "off": ["matrix_jetson_thinkoff.jsonl", "matrix_jetson_qwen38_off.jsonl"],
    "on": ["matrix_jetson_thinkon.jsonl", "matrix_jetson_qwen38_on.jsonl"],
    "": [],
}


def load(arm: str, extra: list[str] | None = None) -> dict:
    agg = collections.defaultdict(list)
    files = ARM_LOGS[arm] + (extra or [])
    for fn in files:
        p = LOGS / fn
        if not p.exists():
            continue
        for line in open(p):
            r = json.loads(line)
            s = r.get("score") or {}
            cell = r["cell"]
            m = cell.split("_think")[0]
            track = "B" if "_track-B" in cell else "A"
            col = "v0.5" if r["plan"] == "v0p5" else ("B" if track == "B" else PLAN_LABEL[r["plan"]])
            if "M3" in s:
                agg[(m, col)].append(s["M3"])
            elif "provider_error" not in (r.get("error") or ""):
                agg[(m, col)].append(0.0)      # budget/give-up = real outcome
    return agg


def matrix(agg: dict, models: list[str]) -> np.ndarray:
    a = np.full((len(models), len(COLS)), np.nan)
    for i, m in enumerate(models):
        for j, c in enumerate(COLS):
            v = agg.get((m, c))
            if v:
                a[i, j] = st.mean(v)
    return a


def heatmap(a, models, title, fname, cmap="viridis", vmin=0, vmax=1, cbar_label="mean M3"):
    fig, ax = plt.subplots(figsize=(7.2, 0.42 * len(models) + 2.0))
    im = ax.imshow(a, cmap=cmap, vmin=vmin, vmax=vmax, aspect="auto")
    ax.set_xticks(range(len(COLS)))
    ax.set_xticklabels(COLS, rotation=30, ha="right", fontsize=9)
    ax.set_yticks(range(len(models)))
    ax.set_yticklabels([pretty(m) for m in models], fontsize=8)
    ax.set_xlabel("plan detail  (lean $\\rightarrow$ detailed)", fontsize=9)
    for i in range(a.shape[0]):
        for j in range(a.shape[1]):
            if np.isnan(a[i, j]):
                continue
            # pick a legible text colour for the cell's background
            rel = (a[i, j] - vmin) / (vmax - vmin) if vmax > vmin else 0.5
            col = "white" if (cmap == "viridis" and rel < 0.55) else "black"
            ax.text(j, i, f"{a[i, j]:.2f}", ha="center", va="center", fontsize=7, color=col)
    ax.set_title(title, fontsize=10)
    fig.colorbar(im, ax=ax, label=cbar_label, fraction=0.03, pad=0.02)
    fig.tight_layout()
    out = FIGS / fname
    fig.savefig(out, dpi=160)
    plt.close(fig)
    print(f"  wrote {out.name}")


def n3_vs_n10() -> None:
    """Panel 4: what the n=3 matrix claimed vs what 10 seeds actually show.

    R3.8 objected to reading 3/3 as robust success. This answers it with data
    rather than with an interval: for the same cells, every model that moved
    moved *down*. Small n does not scatter symmetrically here -- it flatters
    the weak models, because a model that succeeds 70% of the time still goes
    3/3 about a third of the time, while one that succeeds 100% cannot go up.
    """
    n3 = load("off")                                   # v2 Track A, seeds 42-44
    extra = load("", ["matrix_jetson_n10_v2.jsonl"])   # v2 Track A, seeds 45-51
    models = sorted(m for (m, c) in extra if c == "v2")
    if not models:
        print("  (no extra-seed data; skipping panel 4)")
        return
    # The extra pass ran 7 NEW seeds, not a fresh 10. n=10 is the two pooled --
    # plotting the 7 alone would understate every model that the original 3
    # seeds happened to get right.
    a = [st.mean(n3[(m, "v2")]) for m in models]
    b = [st.mean(n3[(m, "v2")] + extra[(m, "v2")]) for m in models]
    ns = {len(n3[(m, "v2")]) + len(extra[(m, "v2")]) for m in models}
    assert ns == {10}, f"expected 10 pooled seeds per model, got {sorted(ns)}"

    fig, ax = plt.subplots(figsize=(7.2, 0.42 * len(models) + 2.0))
    y = np.arange(len(models))
    for i, (x0, x1) in enumerate(zip(a, b)):
        if abs(x1 - x0) > 1e-9:
            ax.annotate("", xy=(x1, i), xytext=(x0, i),
                        arrowprops=dict(arrowstyle="->", color="#b2182b", lw=1.4))
    ax.scatter(a, y, s=42, color="#999999", zorder=3, label="n=3 (as published)")
    ax.scatter(b, y, s=42, color="#b2182b", zorder=3, label="n=10")
    ax.set_yticks(y)
    ax.set_yticklabels([pretty(m) for m in models], fontsize=8)
    ax.set_xlim(-0.04, 1.04)
    ax.set_xlabel("mean M3 at v2, Track A, reasoning off", fontsize=9)
    ax.set_title("More seeds only ever moved scores down\n"
                 "(n=3 cannot distinguish a 70%-reliable model from a perfect one)",
                 fontsize=10)
    ax.legend(fontsize=8, loc="lower left", framealpha=0.9)
    ax.grid(axis="x", alpha=0.25, linestyle=":")
    fig.tight_layout()
    out = FIGS / "rev_fig4_n3_vs_n10.png"
    fig.savefig(out, dpi=160)
    plt.close(fig)
    print(f"  wrote {out.name}")


def main() -> int:
    # n=3 matrix only -- see the module docstring on why the n=10 pass is
    # kept out of panels 1-3.
    off = load("off")
    on = load("on")

    models_off = sorted({k[0] for k in off})
    models_on = sorted({k[0] for k in on})
    common = sorted(set(models_off) & set(models_on) - GRANITE)

    print("figures ->", FIGS)
    heatmap(matrix(off, models_off), models_off,
            "Plan gradient, reasoning OFF (Jetson AGX Orin, n=3)",
            "rev_fig1_gradient_thinkoff.png")
    heatmap(matrix(on, models_on), models_on,
            "Plan gradient, reasoning ON (Jetson AGX Orin, n=3)",
            "rev_fig2_gradient_thinkon.png")

    d = matrix(on, common) - matrix(off, common)
    lim = float(np.nanmax(np.abs(d)))
    heatmap(d, common,
            "Effect of reasoning: ON minus OFF\n"
            "(positive = reasoning helps; negative = reasoning hurts)",
            "rev_fig3_reasoning_delta.png",
            cmap="RdBu_r", vmin=-lim, vmax=lim, cbar_label="$\\Delta$ mean M3")

    n3_vs_n10()

    # column means for the delta panel -- the quantitative headline
    print("\n  reasoning effect by column (10 models common to both arms):")
    for j, c in enumerate(COLS):
        col = d[:, j]
        col = col[~np.isnan(col)]
        if col.size:
            print(f"    {c:<6} {col.mean():+.2f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
