#!/usr/bin/env bash
#SBATCH --job-name=km_cuda_k
#SBATCH --partition=gpu_p100
#SBATCH --nodes=1
#SBATCH --gpus-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err
#SBATCH --time=00:45:00
#SBATCH --ntasks=1

source slurm/common.sh
need_bins "$BIN_SERIAL" "$BIN_OMP" "$BIN_CUDA"
ensure_datasets

init_cuda_csv "sweep_k"
BEST_THREADS="${BEST_THREADS:-256}"

for k in $K_LIST; do
	run_timed_cuda "baseline_serial" "$BIN_SERIAL" 1 "serial" "$k"
	run_timed_cuda "baseline_omp8" "$BIN_OMP" 8 "omp" "$k"
	for mode in $CUDA_MODES; do
		run_timed_cuda "cuda_k" "$BIN_CUDA" "$BEST_THREADS" "$mode" "$k"
	done
done

echo "Results in $CSV"
