#!/usr/bin/env python3
"""
Honest cost accounting: local hardware vs frontier API (R3.13).

R3.13: "Local execution avoids an API charge, but it is not literally free. The
manuscript should distinguish 'no marginal API fee' from zero cost. A fair
comparison needs hardware purchase, depreciation, electricity usage, staff time
for maintenance, model validation, API token costs, etc."

Measured inputs (this study, not estimates):
  - Jetson throughput   : 324 cells in 7.8 h wall  -> 86.7 s/run
  - Claude API cost     : $5.36 over 81 runs       -> $0.0662/run
                          (opus-5 $0.057, sonnet-5 $0.075, haiku-4.5 $0.066)
  - Power mode          : MAXN (nvpmodel -q)

Assumed inputs (flagged; override on the command line):
  - Board power under sustained inference. The INA3221 rails on this unit are
    root-only, so this is the documented AGX Orin 64GB envelope rather than a
    measurement. To measure it for real, run under load:
        sudo tegrastats --interval 1000 | head -60
    or read /sys/bus/i2c/drivers/ina3221/1-004*/hwmon/hwmon*/curr*_input
  - Electricity tariff, hardware price, depreciation horizon, staff time.

The break-even is deliberately reported as *runs*, not months: it is the only
form that does not depend on how busy a particular lab is.

Usage:
  python3 revision/scripts/cost_model.py
  python3 revision/scripts/cost_model.py --watts 40 --tariff 0.17 --hardware 2000
"""
from __future__ import annotations
import argparse

# --- measured in this study -------------------------------------------------
JETSON_S_PER_RUN = 7.8 * 3600 / 324      # 86.7 s
API_USD_PER_RUN = 5.36 / 81              # $0.0662, mean over the 3 Claude models
API_BY_MODEL = {"claude-opus-5": 1.54 / 27,
                "claude-sonnet-5": 2.04 / 27,
                "claude-haiku-4-5": 1.79 / 27}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--watts", type=float, default=40.0,
                    help="board draw under sustained inference (default: AGX Orin 64GB "
                         "MAXN typical; NOT measured — see docstring)")
    ap.add_argument("--idle-watts", type=float, default=10.0)
    ap.add_argument("--tariff", type=float, default=0.17,
                    help="USD per kWh (default: 2026 US commercial average)")
    ap.add_argument("--hardware", type=float, default=2000.0,
                    help="board + storage + PSU, USD")
    ap.add_argument("--depreciation-years", type=float, default=3.0)
    ap.add_argument("--staff-hours-setup", type=float, default=16.0,
                    help="one-time: install, driver/CUDA debugging, model validation")
    ap.add_argument("--staff-hours-year", type=float, default=8.0,
                    help="recurring: updates, re-validation after model releases")
    ap.add_argument("--staff-rate", type=float, default=75.0, help="USD/hour loaded")
    ap.add_argument("--runs-per-year", type=float, default=5000.0,
                    help="only affects the amortised view, not the break-even")
    args = ap.parse_args()

    kwh_per_run = args.watts / 1000 * (JETSON_S_PER_RUN / 3600)
    elec_per_run = kwh_per_run * args.tariff

    print("=" * 66)
    print("MARGINAL COST PER RUN")
    print("=" * 66)
    print(f"  Local (electricity only)      ${elec_per_run:.5f}"
          f"   [{args.watts:.0f} W x {JETSON_S_PER_RUN:.0f} s @ ${args.tariff}/kWh]")
    for m, c in API_BY_MODEL.items():
        print(f"  {m:<28} ${c:.4f}")
    print(f"  {'API mean':<28} ${API_USD_PER_RUN:.4f}")
    print(f"\n  Marginal saving per run       ${API_USD_PER_RUN - elec_per_run:.4f}")

    # One-time and recurring overheads the "free" framing omits.
    setup = args.hardware + args.staff_hours_setup * args.staff_rate
    annual_staff = args.staff_hours_year * args.staff_rate
    idle_kwh_yr = args.idle_watts / 1000 * 8760
    annual_idle = idle_kwh_yr * args.tariff
    annual = annual_staff + annual_idle
    horizon_total = setup + annual * args.depreciation_years

    print("\n" + "=" * 66)
    print("WHAT 'FREE' OMITS")
    print("=" * 66)
    print(f"  Hardware (one-time)           ${args.hardware:,.0f}")
    print(f"  Setup labour                  ${args.staff_hours_setup * args.staff_rate:,.0f}"
          f"   [{args.staff_hours_setup:.0f} h @ ${args.staff_rate}/h]")
    print(f"  Maintenance labour / yr       ${annual_staff:,.0f}")
    print(f"  Idle power / yr               ${annual_idle:,.0f}"
          f"   [{args.idle_watts:.0f} W continuous]")
    print(f"  Total over {args.depreciation_years:.0f} yr           "
          f"${horizon_total:,.0f}")

    saving = API_USD_PER_RUN - elec_per_run
    be_setup = setup / saving
    be_total = horizon_total / saving
    print("\n" + "=" * 66)
    print("BREAK-EVEN (runs)")
    print("=" * 66)
    print(f"  vs hardware + setup only      {be_setup:>10,.0f} runs")
    print(f"  vs full {args.depreciation_years:.0f}-yr cost of ownership  "
          f"{be_total:>10,.0f} runs")
    print(f"\n  At {args.runs_per_year:,.0f} runs/yr that is "
          f"{be_total / args.runs_per_year:.1f} years to break even.")

    print("\n  Sensitivity to board power (negligible — electricity is not the story):")
    for w in (20, 30, 40, 60):
        e = w / 1000 * (JETSON_S_PER_RUN / 3600) * args.tariff
        print(f"    at {w:>2} W board draw:  {horizon_total / (API_USD_PER_RUN - e):>10,.0f} runs")

    # The dominant term is API cost per run, which scales with task size. This
    # study's task is small (~2.4k prompt tokens, a ~2 KB script). A realistic
    # production analysis -- larger context, longer output, multi-step agentic
    # loops with tool results fed back -- costs far more per call, and that is
    # what decides whether owning hardware pays for itself.
    print("\n  Sensitivity to API cost per run (this is the story):")
    print(f"    {'API $/run':>10}  {'break-even':>12}   {'yrs @ 5k/yr':>11}   comment")
    for api, note in ((0.066, "this study's task (small)"),
                      (0.25, "~4x larger prompt/output"),
                      (1.00, "multi-step agentic loop"),
                      (5.00, "long-context repo-scale task")):
        be = horizon_total / (api - elec_per_run)
        print(f"    ${api:>9.2f}  {be:>12,.0f}   {be / 5000:>11.1f}   {note}")

    print("\n  NOTE: the local column is *marginal* cost. It excludes the wall-clock")
    print("  penalty — a Jetson run takes ~87 s against a few seconds for the API —")
    print("  which is a real cost when a human is waiting, and free when they are not.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
