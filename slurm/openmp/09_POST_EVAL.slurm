#!/usr/bin/env bash
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err
#SBATCH --time=01:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=16G
#SBATCH --exclusive
#SBATCH --job-name=km_omp_in_depth

#source /data/leuven/303/vsc30380/slurmhooks

source slurm/common.sh

need_bins "$BIN_SERIAL" "$BIN_OMP"
ensure_datasets
init_csv_k speedup

for run in $(seq 1 5); do
	for k in $(seq 5 15); do
		run_timed_with_k speedup "$BIN_SERIAL" 1 serial "$k"

		run_timed_with_k speedup "$BIN_SERIAL" 1 omp "$k"

		# speedup at max threads
		run_timed_with_k speedup "$BIN_OMP" "$MAX_THREADS" omp "$k"
	done
done
echo "Results in $CSV"
