#!/usr/bin/env bash
#SBATCH --job-name=km_build
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err
#SBATCH --time=00:10:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=2G
# Builds the serial binary and OpenMP binary into build/bin/.

#source /data/leuven/303/vsc30380/slurmhooks
source slurm/common.sh

echo "== build =="
make clean
make -j"${SLURM_CPUS_PER_TASK:-4}" all

ls -l build/bin/
# Sanity: OMP binary must link libgomp, serial must not
ldd "$BIN_OMP"    | grep -q gomp && echo "OK: omp binary uses libgomp"
ldd "$BIN_SERIAL" | grep -q gomp && echo "WARNING: serial binary links libgomp" || echo "OK: serial binary has no OpenMP"
