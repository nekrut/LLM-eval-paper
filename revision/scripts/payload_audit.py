#!/usr/bin/env python3
"""Deny-list audit of the outbound payloads sent to the commercial API (R1.4).

The first version of this manuscript asserted that the planner-executor split
keeps local identity off the wire, and said the audit "was not run". This runs
it.

What is and is not auditable. `provider_envelope.json`, archived for each of the
81 frontier cells, is the *response* envelope: it carries usage, cost and stop
reason and no request body. The request body is not archived. It is, however,
deterministically reconstructable, because `harness/run_one.py` builds it as
`prompts/system.txt` plus a template whose only substitutions are the plan file
and the stdout of `setup/verify_env.sh`. This script rebuilds every payload that
was sent and scans it, so the count below is over reconstructed payloads rather
than over captured ones. Benchmark 2's MCP traffic is not reconstructable and is
excluded; that is stated in the manuscript.

Usage: python3 revision/scripts/payload_audit.py
"""
import re, subprocess, socket, os, pathlib, collections

REPO = pathlib.Path(__file__).resolve().parent.parent.parent
HOST = socket.gethostname()
HOME = os.path.expanduser("~")

TOKENS = {
    "host name":     re.compile(re.escape(HOST), re.I) if HOST else None,
    "$HOME":         re.compile(re.escape(HOME)),
    "conda prefix":  re.compile(r"(miniforge3|miniconda3|anaconda3|/envs/)"),
    "absolute path": re.compile(r"(?<![\w.])/(?!dev/|usr/bin/env|bin/bash|bin/sh)[A-Za-z][\w./-]*"),
    "credential":    re.compile(r"(api[_-]?key|sk-[A-Za-z0-9]{16,}|BEARER|token\s*=)", re.I),
    "subject label": re.compile(r"M117C?1?-(bl|ch)"),
}

def scan(text):
    return {k: len(rx.findall(text)) for k, rx in TOKENS.items() if rx}

def inventory():
    p = subprocess.run([str(REPO/"setup"/"verify_env.sh")], capture_output=True, text=True)
    m = re.search(r"^TOOL_INVENTORY.*?^OK$", p.stdout, re.S | re.M)
    return m.group(0).rsplit("\n", 1)[0] if m else ""

INV = inventory()
SYS = (REPO/"prompts"/"system.txt").read_text()

def user(tmpl, plan=None):
    t = (REPO/"prompts"/tmpl).read_text().replace("{TOOL_INVENTORY}", INV)
    if "{PLAN}" in t:
        t = t.replace("{PLAN}", (REPO/"plan"/plan).read_text())
    return t

ARMS = collections.OrderedDict()
ARMS["planner calls"] = [
    (f, (REPO/"plan"/f).read_text())
    for f in ("PLANNER_PROMPT.md", "PLANNER_PROMPT_v2.md", "PLANNER_PROMPT_v2_defensive.md")
]
grad = []
for plan in ("PLAN_v1.md", "PLAN_v1g.md", "PLAN_v1p25.md", "PLAN_v1p5.md", "PLAN.md"):
    grad += [(f"A/{plan}", SYS + user("track_a_user.tmpl", plan))] * 9      # 3 models x 3 seeds
grad += [("B", SYS + user("track_b_user.tmpl"))] * 27
grad += [("v0.5", SYS + user("track_b_with_order_user.tmpl"))] * 9
ARMS["frontier executor gradient"] = grad
# 3 API executors x 39 cells x 2 plans = 234 generations (error_matrix_anthropic.jsonl)
ARMS["frontier error matrix"] = [
    (f"A/{p}", SYS + user("track_a_user.tmpl", p)) for p in ("PLAN.md", "PLAN_v2_defensive.md")
] * 117
ARMS["benchmark 2 MCP traffic"] = []

print(f"host name matched: {HOST!r};  $HOME: {HOME!r}\n")
print(f"{'arm':30s}{'payloads':>9}  " + "  ".join(f"{k:>13s}" for k in TOKENS))
for arm, payloads in ARMS.items():
    if not payloads:
        print(f"{arm:30s}{'not archived':>9}")
        continue
    tot = collections.Counter()
    for _, txt in payloads:
        for k, n in scan(txt).items():
            if n: tot[k] += 1          # payloads with >= 1 hit
    print(f"{arm:30s}{len(payloads):9d}  " + "  ".join(f"{tot[k]:13d}" for k in TOKENS))

print("\n--- absolute-path and subject-label hits, verbatim ---")
seen = set()
for arm, payloads in ARMS.items():
    for name, txt in payloads:
        for k in ("absolute path", "subject label"):
            for m in TOKENS[k].findall(txt):
                s = m if isinstance(m, str) else m[0]
                if (arm, k, s) in seen: continue
                seen.add((arm, k, s))
                print(f"  {arm:28s} {k:14s} {s}")
