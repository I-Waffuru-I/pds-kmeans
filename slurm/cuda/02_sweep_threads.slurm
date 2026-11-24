#!/usr/bin/env bash
#SBATCH --job-name=km_cuda_threads
#SBATCH --partition=gpu_p100
#SBATCH --nodes=1
#SBATCH --gpus-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err
#SBATCH --time=00:20:00
#SBATCH --ntasks=1

source slurm/common.sh
need_bins "$BIN_CUDA"
ensure_datasets

init_cuda_csv "sweep_threads"

for mode in $CUDA_MODES; do
	for t in $BLOCK_LIST; do
		run_timed_cuda "threads_sweep" "$BIN_CUDA" "$t" "$mode" "$K"
	done
done

echo "Results in $CSV"
