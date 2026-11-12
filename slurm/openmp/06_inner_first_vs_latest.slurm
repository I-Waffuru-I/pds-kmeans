#!/usr/bin/env bash
#SBATCH --job-name=km_impl
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err
#SBATCH --time=01:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=8G
#SBATCH --exclusive
# Notebook: "Test Inner para latest vs Inner para first".
#   first  = omp-naive (implementation 1: critical/atomic on shared variables)
#   latest = omp       (implementation 2: reductions + localCentroidMap)
# Also sweeps schedule/problem-size to show how the contention grows with #points.

#source /data/leuven/303/vsc30380/slurmhooks
source slurm/common.sh

need_bins "$BIN_OMP"; ensure_datasets
init_csv inner_first_vs_latest

for mode in omp-naive omp; do
  run_timed inner_first_vs_latest "$BIN_OMP" "$MAX_THREADS" "$mode"
done

# Larger K => more work per point, fewer relative conflicts; smaller K => more contention
for k in 2 10 50; do
  K_SAVE=$K; K=$k
  for mode in omp-naive omp; do
    run_timed "inner_k${k}" "$BIN_OMP" "$MAX_THREADS" "$mode"
  done
  K=$K_SAVE
done
echo "Results in $CSV"
