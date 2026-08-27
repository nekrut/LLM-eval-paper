#!/usr/bin/env python3
"""
Collect the reproducibility metadata Reviewer 3 asked for (R3.16): exact model
identifiers, digests, quantization formats, architectures, declared
capabilities, per-model default decoding parameters, inference-engine version,
and analysis tool versions.

Model family names are not sufficient for long-term reproducibility: two pulls
of the same tag can differ, and `ollama show` reports each model's *own*
default `top_k`/`top_p`, which the harness does not override. Those defaults
are not uniform across models, so the decoding configuration is not uniform
across the matrix unless stated explicitly -- which is exactly the kind of
detail that has to be in the methods rather than assumed.

Writes revision/repro_metadata.json and prints a markdown table for the
supplement.

Usage: python3 revision/scripts/collect_repro_metadata.py [--markdown]
"""
from __future__ import annotations
import argparse
import json
import re
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
OUT = REPO / "revision" / "repro_metadata.json"

MODELS = [
    "laguna-xs-2.1:q4_K_M", "qwen3.6:35b-a3b-q4_K_M", "gemma4:26b-a4b-it-q4_K_M",
    "nemotron-3-nano:30b-a3b-q4_K_M", "gpt-oss:20b", "glm-4.7-flash:q4_K_M",
    "qwen3.6:27b-q4_K_M", "gemma4:31b-it-q4_K_M", "granite4.1:30b-q4_K_M",
    "granite4.1:8b-q4_K_M", "qwen3.5:4b-q4_K_M", "nemotron-3-nano:4b",
    # The two models absent from the first version of this table: the
    # benchmark-2 dense arm and the throughput-measurement model.
    "qwen3.8:27b-q4_K_M", "gemma4:12b",
]

# Keys may contain single spaces ("context length"), so the key is everything
# up to a run of 2+ spaces rather than a single \S+ token.
FIELD = re.compile(r"^\s{4}(\S+(?:\s\S+)*?)\s{2,}(.+?)\s*$")


def sh(cmd: list[str]) -> str:
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=60).stdout.strip()
    except Exception as e:
        return f"<error: {e}>"


def show(model: str) -> dict:
    txt = sh(["ollama", "show", model])
    out: dict = {"model": model, "capabilities": [], "defaults": {}, "info": {}}
    section = None
    for line in txt.splitlines():
        s = line.strip()
        if not s:
            continue
        if not line.startswith(" " * 4):
            section = s.lower()
            continue
        # Capabilities are single-word lines. Check the section before the
        # key/value regex: trailing whitespace lets `(.+?)` match a blank
        # "value", so a bare capability would otherwise be filed as a field.
        if section == "capabilities":
            out["capabilities"].append(s)
            continue
        m = FIELD.match(line)
        if m:
            k, v = m.group(1), m.group(2)
            if section == "parameters":
                out["defaults"][k] = v
            elif section == "model":
                # Only the "Model" block describes the model itself. A
                # multimodal tag also carries a "Projector" block with its own
                # architecture/parameters/embedding length keys; filing those
                # under info silently overwrites the model's own values with
                # the vision tower's (e.g. qwen3.8:27b -> "clip", "460.73M").
                out["info"][k] = v
    return out


def digests() -> dict:
    """sha256 blob id per tag, from `ollama list`."""
    out = {}
    for line in sh(["ollama", "list"]).splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 2:
            out[parts[0]] = parts[1]
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--markdown", action="store_true")
    args = ap.parse_args()

    dg = digests()
    meta = {
        "engine": {
            "ollama": sh(["ollama", "--version"]).replace("ollama version is ", ""),
            "jetpack_l4t": (REPO / "/etc/nv_tegra_release").read_text().strip()
            if Path("/etc/nv_tegra_release").exists() else sh(["cat", "/etc/nv_tegra_release"]),
            "cuda_driver": "11.4 (JetPack 5.1.2)",
            "device": "NVIDIA Jetson AGX Orin 64GB, compute capability 8.7",
        },
        "ollama_env": {
            "OLLAMA_FLASH_ATTENTION": "false",
            "OLLAMA_KV_CACHE_TYPE": "f16",
            "OLLAMA_MAX_LOADED_MODELS": "1",
            "OLLAMA_NUM_PARALLEL": "1",
        },
        "harness_overrides": {
            "temperature": 0.2, "num_predict": 16384, "num_ctx": 16384,
            "note": "top_k / top_p are NOT overridden; each model's own defaults apply",
        },
        "models": [],
    }

    for m in MODELS:
        d = show(m)
        d["digest"] = dg.get(m, "<not found>")
        meta["models"].append(d)

    OUT.write_text(json.dumps(meta, indent=2))

    if args.markdown:
        print("| Model | Digest | Arch | Params | Quant | Ctx | thinking? | top_k | top_p |")
        print("|---|---|---|---|---:|---:|:---:|---:|---:|")
        for d in meta["models"]:
            i = d["info"]
            print(f"| `{d['model']}` | `{d['digest']}` | {i.get('architecture','?')} | "
                  f"{i.get('parameters','?')} | {i.get('quantization','?')} | "
                  f"{i.get('context length','?')} | "
                  f"{'yes' if 'thinking' in d['capabilities'] else 'NO'} | "
                  f"{d['defaults'].get('top_k','—')} | {d['defaults'].get('top_p','—')} |")
    else:
        print(f"wrote {OUT}")
        tk = {d["defaults"].get("top_k") for d in meta["models"]}
        tp = {d["defaults"].get("top_p") for d in meta["models"]}
        print(f"distinct default top_k across models: {sorted(x for x in tk if x)}")
        print(f"distinct default top_p across models: {sorted(x for x in tp if x)}")
        nothink = [d["model"] for d in meta["models"] if "thinking" not in d["capabilities"]]
        print(f"models without a thinking capability: {nothink}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
