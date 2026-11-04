#!/usr/bin/env bash
# Shared helpers, sourced by every .slurm script. Edit the defaults here.
set -euo pipefail

# Project root = parent of slurm/ (works under sbatch, where $0 is a spool copy)
if [[ -n "${SLURM_SUBMIT_DIR:-}" ]]; then ROOT="${PROJECT_ROOT:-$SLURM_SUBMIT_DIR}"; else ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"; fi
cd "$ROOT"

# ---- tunables (override with e.g. `sbatch --export=ALL,DATASET=... script.slurm`) ----
DATASET="${DATASET:-datasets/100000x5.csv}"
DEBUG_DATASET="${DEBUG_DATASET:-datasets/mouse_500x2.csv}"
K="${K:-10}"
REPS="${REPS:-20}"
SEED="${SEED:-1337}"
RUNS="${RUNS:-3}"                       # repeats per configuration for timing
THREAD_LIST="${THREAD_LIST:-1 2 4 8 16}"
MAX_THREADS="${MAX_THREADS:-${SLURM_CPUS_PER_TASK:-16}}"

BIN_SERIAL="$ROOT/build/bin/kmeans_serial"    # built WITHOUT -fopenmp
BIN_OMP="$ROOT/build/bin/kmeans_omp"          # built WITH -fopenmp -DHAVE_OMP
RESULTS="$ROOT/results"
OUT="$ROOT/output"
mkdir -p "$RESULTS" "$OUT" "$ROOT/logs" "$ROOT/build/bin"

# Environment for reproducible OpenMP behaviour
export OMP_PROC_BIND="${OMP_PROC_BIND:-close}"
export OMP_PLACES="${OMP_PLACES:-cores}"

# Optional: load modules here if your cluster needs them, e.g.
# module load GCC/12.3.0 Python/3.11
if command -v module >/dev/null 2>&1 && [[ -n "${MODULES:-}" ]]; then module load $MODULES; fi

need_bins() {
  for b in "$@"; do
    [[ -x "$b" ]] || { echo "Missing $b - run: sbatch slurm/00_build.slurm first" >&2; exit 1; }
  done
}

ensure_datasets() {
  if [[ ! -f "$DATASET" || ! -f "$DEBUG_DATASET" ]]; then
    echo "Datasets missing, generating synthetic ones (python3 slurm/gen_datasets.py)"
    python3 slurm/gen_datasets.py
  fi
}

# run_timed <label> <bin> <threads> <mode> [extra args...]
# Appends one row to $RESULTS/<csvname> (set CSV before calling).
# Row: label,mode,threads,run,bestdist,seconds,steps
run_timed() {
  local label="$1" bin="$2" threads="$3" mode="$4"; shift 4
  local run out stdout steps
  for run in $(seq 1 "$RUNS"); do
    out="$OUT/${label}_${mode}_t${threads}_r${run}.csv"
    stdout=$("$bin" --input "$DATASET" --output "$out" --repetitions "$REPS" \
             --k "$K" --seed "$SEED" --threads "$threads" --mode "$mode" "$@" 2>>"$RESULTS/stderr_${label}.log" | tail -n1)
    # stdout: type,blocks,threads,file,seed,clusters,reps,bestdist,seconds
    IFS=',' read -r _ _ _ _ _ _ _ dist secs <<<"$stdout"
    steps=$(head -n1 "$out" | sed 's/# Steps: *//; s/,/;/g')
    echo "$label,$mode,$threads,$run,$dist,$secs,$steps" >> "$CSV"
    echo "[$label] mode=$mode threads=$threads run=$run -> ${secs}s (best dist $dist)"
  done
}

init_csv() { # init_csv <name>
  CSV="$RESULTS/$1.csv"
  echo "label,mode,threads,run,bestdist,seconds,steps" > "$CSV"
}
