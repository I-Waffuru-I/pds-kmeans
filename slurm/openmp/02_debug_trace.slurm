#!/usr/bin/env bash
#SBATCH --job-name=km_trace
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err
#SBATCH --time=00:15:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=2G
# Notebook: trace files are collected in vectors during the parallel loop and written
# afterwards (only repetition 0). Check --trace / --centroidtrace are identical to serial
# (mirrors `make debug` / `just debug`).

#source /data/leuven/303/vsc30380/slurmhooks
source slurm/common.sh

need_bins "$BIN_SERIAL" "$BIN_OMP"; ensure_datasets
T="$OUT/trace"; mkdir -p "$T"

run() { # bin mode threads tag
  "$1" --input "$DEBUG_DATASET" --output "$T/$4.out.csv" --repetitions 10 --k 3 --seed 1338 \
       --centroidtrace "$T/$4.centroids.csv" --trace "$T/$4.clusters.csv" \
       --threads "$3" --mode "$2" >/dev/null 2>>"$RESULTS/stderr_trace.log"
}
run "$BIN_SERIAL" serial 1 serial
for mode in omp omp-naive omp-outer omp-nested; do
  for t in 1 4 8; do
    tag="${mode}_t$t"; run "$BIN_OMP" "$mode" "$t" "$tag"
    for f in out centroids clusters; do
      if diff -q "$T/serial.$f.csv" "$T/$tag.$f.csv" >/dev/null; then echo "PASS  $tag $f"
      else echo "FAIL  $tag $f";fi
    done
  done
done
