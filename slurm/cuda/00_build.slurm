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

module purge
module load GCC/10.3.0
module load CUDA/11.7.0

echo "== build =="
make clean
make cuda
