#!/usr/bin/env bash
set -euo pipefail

mkdir -p logs logs/old results/cuda
mv logs/*.err logs/old/ 2>/dev/null || true
mv logs/*.out logs/old/ 2>/dev/null || true

CLUSTER="wice"
ACC="llp_h_pds"

submit() { sbatch -M "$CLUSTER" --account "$ACC" --parsable "$@" | cut -d';' -f1; }

b=$(submit slurm/cuda/00_build.slurm)
j_threads=$(submit --dependency=afterok:"$b" slurm/cuda/02_sweep_threads.slurm)
j_k=$(submit --dependency=afterok:"$b" slurm/cuda/03_sweep_k.slurm)
j_ds=$(submit --dependency=afterok:"$b" slurm/cuda/04_sweep_datasets.slurm)

echo "Build job:    $b"
echo "Sweep jobs:   threads=$j_threads, k=$j_k, datasets=$j_ds"
echo "Watch with:   squeue -u \$USER -M $CLUSTER"
