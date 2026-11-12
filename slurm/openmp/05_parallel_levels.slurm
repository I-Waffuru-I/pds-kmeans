#!/usr/bin/env bash
#SBATCH --job-name=km_levels
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err
#SBATCH --time=00:50:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=64
#SBATCH --mem=8G
#SBATCH --exclusive
# Notebook: "Test nested vs Only outer para vs Only inner para" and the OMP_NESTED problem.
#   omp            -> inner loop parallel only
#   omp-outer      -> outer (repetitions) parallel + inner parallel  (nested)
#   omp-nested     -> same code path as omp-outer; run with nesting enabled
#   omp-outeronly  -> outer parallel, serial inner (see NOTE)
# NOTE: in src/kmeans.cpp the outer pragma is `if (mode == "omp-outer" || mode == "omp-nested")`,
# so "omp-outeronly" does NOT enable the outer parallel loop and will behave like serial.
# Compare its timing with omp-outer to confirm; fix the `if` clause if that is not intended.

#source /data/leuven/303/vsc30380/slurmhooks
source slurm/common.sh

need_bins "$BIN_OMP"
ensure_datasets
init_csv parallel_levels

for t in $THREAD_LIST; do
	((t > MAX_THREADS)) && continue
	# inner only
	OMP_MAX_ACTIVE_LEVELS=1 run_timed parallel_levels "$BIN_OMP" "$t" omp
	# outer only (serial inner)
	OMP_MAX_ACTIVE_LEVELS=1 run_timed parallel_levels "$BIN_OMP" "$t" omp-outeronly
	# outer + inner, nesting OFF (default: inner region silently runs on 1 thread) - Probleem 1
	OMP_MAX_ACTIVE_LEVELS=1 run_timed parallel_levels "$BIN_OMP" "$t" omp-outer
	# outer + inner, nesting ON (`OMP_NESTED=true` in the notebook; modern equivalent below)
	OMP_NESTED=true OMP_MAX_ACTIVE_LEVELS=2 run_timed parallel_levels "$BIN_OMP" "$t" omp-nested
done
echo "Results in $CSV"
