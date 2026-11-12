#!/usr/bin/env bash
#SBATCH --job-name=km_serial_vs_omp
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err
#SBATCH --time=00:40:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=8G
#SBATCH --exclusive
# Notebook: "Seriel vs OMP implementaties", "Speedup berekenen",
#           "Seriele imp vs OMP implementatie op 1 thread" (overhead of OpenMP itself).

#source /data/leuven/303/vsc30380/slurmhooks
source slurm/common.sh

need_bins "$BIN_SERIAL" "$BIN_OMP"
ensure_datasets
init_csv serial_vs_omp

run_timed serial_vs_omp "$BIN_SERIAL" 1 serial
run_timed serial_vs_omp "$BIN_SERIAL" 1 serial-naive
# OpenMP-compiled binary on one thread: pure overhead compared with the serial build
for mode in omp-naive omp; do run_timed serial_vs_omp "$BIN_OMP" 1 "$mode"; done
# And the OpenMP binary at full thread count: speedup
for mode in omp-naive omp; do run_timed serial_vs_omp "$BIN_OMP" "$MAX_THREADS" "$mode"; done
echo "Results in $CSV"
