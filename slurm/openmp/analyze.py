#!/usr/bin/env python3
"""Speedup / efficiency / Amdahl analysis of results/*.csv written by the .slurm tests."""
import sys, os, glob
import pandas as pd

res = sys.argv[1] if len(sys.argv) > 1 else "results"
try:
    import matplotlib; matplotlib.use("Agg"); import matplotlib.pyplot as plt
except ImportError:
    plt = None

def mean_times(df):
    if df["label"].nunique() > 1:
        df = df.assign(mode=df["label"] + ":" + df["mode"])
    return df.groupby(["mode", "threads"], as_index=False)["seconds"].mean()

def amdahl_fit(t, speedup, p_candidates=None):
    """Estimate parallel fraction p from the speedup at t threads: S = 1/((1-p)+p/t)."""
    if t <= 1 or speedup <= 0: return float("nan")
    return min(1.0, max(0.0, (1 - 1 / speedup) / (1 - 1 / t)))

f = os.path.join(res, "thread_scaling.csv")
if os.path.exists(f):
    df = pd.read_csv(f); m = mean_times(df)
    base = m[m["mode"] == "serial"]["seconds"].iloc[0]
    m = m[m["mode"] != "serial"].copy()
    m["speedup"] = base / m["seconds"]
    m["efficiency"] = m["speedup"] / m["threads"]
    # Amdahl: use the max-thread run of each mode to estimate parallel fraction p
    for mode, g in m.groupby("mode"):
        g1 = g[g.threads == g.threads.max()].iloc[0]
        p = amdahl_fit(g1.threads, g1.speedup)
        m.loc[m["mode"] == mode, "amdahl_p"] = p
        m.loc[m["mode"] == mode, "amdahl_speedup"] = 1 / ((1 - p) + p / m.loc[m["mode"] == mode, "threads"])
    m["serial_s"] = base
    out = os.path.join(res, "thread_scaling_summary.csv"); m.to_csv(out, index=False)
    print(m.to_string(index=False))
    # NOTE: p is fitted at max threads, so the Amdahl curve passes through that point by
    # construction. For an independent theoretical value, measure the serial fraction
    # (e.g. time of file read + init + merge) and set p yourself.
    if plt:
        fig, ax = plt.subplots(1, 2, figsize=(11, 4))
        for mode, g in m.groupby("mode"):
            ax[0].plot(g.threads, g.speedup, "o-", label=mode)
            ax[0].plot(g.threads, g.amdahl_speedup, "--", alpha=.4)
            ax[1].plot(g.threads, g.efficiency, "o-", label=mode)
        mx = m.threads.max(); ax[0].plot([1, mx], [1, mx], "k:", label="ideal")
        ax[0].set(xlabel="threads", ylabel="speedup", title="Speedup (dashed = Amdahl fit)")
        ax[1].set(xlabel="threads", ylabel="efficiency", title="Efficiency")
        for a in ax: a.legend(); a.grid(alpha=.3)
        fig.tight_layout(); fig.savefig(os.path.join(res, "thread_scaling.png"), dpi=130)

for name in ["serial_vs_omp", "parallel_levels", "inner_first_vs_latest"]:
    f = os.path.join(res, name + ".csv")
    if os.path.exists(f):
        df = pd.read_csv(f); m = mean_times(df)
        print(f"\n== {name} ==\n{m.to_string(index=False)}")
        m.to_csv(os.path.join(res, name + "_summary.csv"), index=False)
        if plt and name == "parallel_levels":
            fig, ax = plt.subplots(figsize=(6, 4))
            for mode, g in m.groupby("mode"): ax.plot(g.threads, g.seconds, "o-", label=mode)
            ax.set(xlabel="threads", ylabel="seconds", title="Outer vs inner vs nested"); ax.legend(); ax.grid(alpha=.3)
            fig.tight_layout(); fig.savefig(os.path.join(res, "parallel_levels.png"), dpi=130)
