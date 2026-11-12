#!/usr/bin/env python3
"""Speedup / efficiency / Amdahl analysis of results/*.csv written by the .slurm tests."""
import sys, os, glob, csv
import pandas as pd

res = sys.argv[1] if len(sys.argv) > 1 else "results"
try:
    import matplotlib; matplotlib.use("Agg"); import matplotlib.pyplot as plt
except ImportError:
    plt = None

def load_csv(path):
    rows = []
    with open(path, newline="") as fh:
        for r in csv.reader(fh):
            if not r or r[0].startswith("#") or r[0] in ("label", "Type"):
                continue
            if len(r) == 8:    # label,mode,threads,run,reps,bestdist,seconds,steps
                label, mode, threads, run, _, bestdist, seconds, steps = r
            elif len(r) == 7:  # label,mode,threads,run,bestdist,seconds,steps
                label, mode, threads, run, bestdist, seconds, steps = r
            elif len(r) == 6:  # label,threads,run,bestdist,seconds,steps (mode omitted)
                label, threads, run, bestdist, seconds, steps = r
                mode = label
            elif len(r) == 10: # raw kmeans stdout with submode
                label, mode, _, threads, _, _, _, _, bestdist, seconds = r
                run, steps = 1, ""
            elif len(r) == 9:  # raw kmeans stdout without submode
                label, _, threads, _, _, _, _, bestdist, seconds = r
                mode, run, steps = label, 1, ""
            else:
                continue
            rows.append({
                "label": label,
                "mode": mode or label,
                "threads": int(threads),
                "run": int(run),
                "bestdist": float(bestdist),
                "seconds": float(seconds),
                "steps": steps,
            })
    return pd.DataFrame(rows)

def mean_times(df):
    if "label" in df.columns and df["label"].nunique() > 1:
        df = df.assign(mode=df["label"].astype(str) + ":" + df["mode"].astype(str))
    return df.groupby(["mode", "threads"], as_index=False)["seconds"].mean()

def amdahl_fit(t, speedup, p_candidates=None):
    """Estimate parallel fraction p from the speedup at t threads: S = 1/((1-p)+p/t)."""
    if t <= 1 or speedup <= 0: return float("nan")
    return min(1.0, max(0.0, (1 - 1 / speedup) / (1 - 1 / t)))

f = os.path.join(res, "thread_scaling.csv")
if os.path.exists(f):
    df = load_csv(f); m = mean_times(df)
    serial_rows = m[m["mode"] == "serial"]
    if not serial_rows.empty:
        base = serial_rows["seconds"].iloc[0]
        m = m[m["mode"] != "serial"].copy()
    else:
        t1 = m[m["threads"] == 1]["seconds"]
        base = t1.iloc[0] if not t1.empty else m["seconds"].iloc[0]
        m = m.copy()
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
        df = load_csv(f); m = mean_times(df)
        print(f"\n== {name} ==\n{m.to_string(index=False)}")
        m.to_csv(os.path.join(res, name + "_summary.csv"), index=False)
        if plt and name == "parallel_levels":
            fig, ax = plt.subplots(figsize=(6, 4))
            for mode, g in m.groupby("mode"): ax.plot(g.threads, g.seconds, "o-", label=mode)
            ax.set(xlabel="threads", ylabel="seconds", title="Outer vs inner vs nested"); ax.legend(); ax.grid(alpha=.3)
            fig.tight_layout(); fig.savefig(os.path.join(res, "parallel_levels.png"), dpi=130)
