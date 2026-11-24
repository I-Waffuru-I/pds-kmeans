#!/usr/bin/env bash
#SBATCH --job-name=km_build
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err
#SBATCH --time=00:10:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=4G

source slurm/common.sh

module --force purge
module load cluster/wice/gpu_p100
module load GCC/13.3.0 CUDA/12.6.0

echo "== build =="
make clean
make -j4 all CUDA_ARCH=sm_60
