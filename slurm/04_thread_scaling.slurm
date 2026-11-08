#!/usr/bin/env bash
#SBATCH --job-name=km_scaling
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err
#SBATCH --time=00:40:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=8G
#SBATCH --exclusive
# Notebook: "Test voor verschillende hoeveelheden threads", speedup + efficiency
# (like `just bench-threads`). Covers the inner-loop implementations:
#   omp-naive : implementation 1 (critical/atomic on shared state)
#   omp / omp-2 : implementation 2 (reduction + per-thread localCentroidMap)

#source /data/leuven/303/vsc30380/slurmhooks
source slurm/common.sh

need_bins "$BIN_SERIAL" "$BIN_OMP"; ensure_datasets
init_csv thread_scaling

run_timed thread_scaling "$BIN_SERIAL" 1 serial          # baseline T_serial for speedup
for mode in omp-naive omp omp-2; do
  for t in $THREAD_LIST; do
    (( t > MAX_THREADS )) && continue
    run_timed thread_scaling "$BIN_OMP" "$t" "$mode"
  done
done
echo "Results in $CSV"
