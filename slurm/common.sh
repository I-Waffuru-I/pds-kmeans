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
REPS="${REPS:-5}"
SEED="${SEED:-1337}"
RUNS="${RUNS:-3}" # repeats per configuration for timing
THREAD_LIST="${THREAD_LIST:-1 2 4 8 16 32}"
MAX_THREADS="${MAX_THREADS:-${SLURM_CPUS_PER_TASK:-32}}"

BIN_SERIAL="$ROOT/build/bin/kmeans_serial"
BIN_OMP="$ROOT/build/bin/kmeans_omp"
BIN_CUDA="$ROOT/build/bin/kmeans_cuda"

RESULTS="$ROOT/results"
OUT="$ROOT/output"
mkdir -p "$RESULTS" "$OUT" "$ROOT/logs" "$ROOT/build/bin"

# env for reproducible OMP behaviour
export OMP_PROC_BIND="${OMP_PROC_BIND:-close}"
export OMP_PLACES="${OMP_PLACES:-cores}"

if command -v module >/dev/null 2>&1 && [[ -n "${MODULES:-}" ]]; then module load $MODULES; fi

need_bins() {
	for b in "$@"; do
		[[ -x "$b" ]] || {
			echo "Missing $b - run: sbatch slurm/00_build.slurm first" >&2
			exit 1
		}
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
	local label="$1" bin="$2" threads="$3" mode="$4"
	shift 4
	local run out stdout steps
	for run in $(seq 1 "$RUNS"); do
		out="$OUT/${label}_${mode}_t${threads}_r${run}.csv"
		stdout=$("$bin" --input "$DATASET" --output "$out" --repetitions "$REPS" \
			--k "$K" --seed "$SEED" --threads "$threads" --mode "$mode" "$@" 2>>"$RESULTS/stderr_${label}.log" | tail -n1)
		# stdout: type,blocks,threads,file,seed,clusters,reps,bestdist,seconds
		IFS=',' read -r _ _ _ _ _ _ _ dist secs <<<"$stdout"
		steps=$(head -n1 "$out" | sed 's/# Steps: *//; s/,/;/g')
		echo "$label,$mode,$threads,$run,$dist,$secs,$steps" >>"$CSV"
		echo "[$label] mode=$mode threads=$threads run=$run -> ${secs}s (best dist $dist)"
	done
}

run_timed_with_k() {
	local label="$1" bin="$2" threads="$3" mode="$4" k="$5"
	shift 5
	local run out stdout steps
	for run in $(seq 1 "$RUNS"); do
		out="$OUT/${label}_${mode}_t${threads}_r${run}.csv"
		stdout=$("$bin" --input "$DATASET" --output "$out" --repetitions "$REPS" \
			--k "$k" --seed "$SEED" --threads "$threads" --mode "$mode" "$@" 2>>"$RESULTS/stderr_${label}.log" | tail -n1)
		# stdout: type,blocks,threads,file,seed,clusters,reps,bestdist,seconds
		IFS=',' read -r _ _ _ _ _ _ _ dist secs <<<"$stdout"
		steps=$(head -n1 "$out" | sed 's/# Steps: *//; s/,/;/g')
		echo "$label,$mode,$threads,$run,$dist,$secs,$k,$steps" >>"$CSV"
		echo "[$label] mode=$mode threads=$threads run=$run -> ${secs}s (best dist $dist)"
	done
}

# ---- CUDA-specific tunables & logging ----
BLOCK_LIST="${BLOCK_LIST:-32 64 128 256 512 1024}"
K_LIST="${K_LIST:-4 8 16 32 64 128}"
CUDA_MODES="${CUDA_MODES:-cuda}" # add e.g. "cuda cuda_shared" if you have multiple modes
CUDA_RESULTS="$RESULTS/cuda"
mkdir -p "$CUDA_RESULTS"

# run_timed_cuda <label> <bin> <threads_per_block> <mode> <k> [extra args...]
run_timed_cuda() {
	local label="$1" bin="$2" threads="$3" mode="$4" k="$5"
	shift 5
	local run out stdout steps ds_name gpu_name
	ds_name=$(basename "$DATASET")
	gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1 | tr ' ' '_' || echo "cpu")

	for run in $(seq 1 "$RUNS"); do
		out="$OUT/${label}_${mode}_t${threads}_k${k}_r${run}.csv"
		stdout=$("$bin" --input "$DATASET" --output "$out" --repetitions "$REPS" \
			--k "$k" --seed "$SEED" --threads "$threads" --mode "$mode" "$@" \
			2>>"$CUDA_RESULTS/stderr_${label}.log" | tail -n1)
		# stdout: type,blocks,threads,file,seed,clusters,reps,bestdist,seconds
		IFS=',' read -r _ actual_blocks actual_threads _ _ _ _ dist secs <<<"$stdout"
		steps=$(head -n1 "$out" | sed 's/# Steps: *//; s/,/;/g')
		echo "$label,$gpu_name,$ds_name,$mode,$actual_blocks,$actual_threads,$k,$run,$dist,$secs,$steps" >>"$CSV"
		echo "[$label] gpu=$gpu_name ds=$ds_name mode=$mode blocks=$actual_blocks threads=$actual_threads k=$k run=$run -> ${secs}s"
	done
}

init_csv() { # init_csv <name>
	CSV="$RESULTS/$1.csv"
	echo "label,mode,threads,run,bestdist,seconds,steps" >"$CSV"
}
init_csv_k() { # init_csv <name>
	CSV="$RESULTS/$1.csv"
	echo "label,mode,threads,run,bestdist,seconds,k,steps" >"$CSV"
}
init_cuda_csv() { # init_cuda_csv <name>
	CSV="$CUDA_RESULTS/$1.csv"
	echo "label,gpu,dataset,mode,blocks,threads,k,run,bestdist,seconds,steps" >"$CSV"
}
