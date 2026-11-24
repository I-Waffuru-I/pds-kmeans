#!/usr/bin/env bash
#SBATCH --job-name=km_cuda_datasets
#SBATCH --partition=gpu_p100
#SBATCH --nodes=1
#SBATCH --gpus-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err
#SBATCH --time=01:00:00
#SBATCH --ntasks=1

source slurm/common.sh
need_bins "$BIN_SERIAL" "$BIN_OMP" "$BIN_CUDA"

init_cuda_csv "sweep_datasets"
BEST_THREADS="${BEST_THREADS:-256}"
DATASET_LIST="${DATASET_LIST:-datasets/100000x5.csv datasets/500000x5.csv datasets/1000000x5.csv}"

for ds in $DATASET_LIST; do
	[[ -f "$ds" ]] || {
		echo "Skipping missing $ds"
		continue
	}
	export DATASET="$ds"
	run_timed_cuda "baseline_serial" "$BIN_SERIAL" 1 "serial" "$K"
	run_timed_cuda "baseline_omp8" "$BIN_OMP" 8 "omp" "$K"
	for mode in $CUDA_MODES; do
		run_timed_cuda "cuda_ds" "$BIN_CUDA" "$BEST_THREADS" "$mode" "$K"
	done
done

echo "Results in $CSV"
