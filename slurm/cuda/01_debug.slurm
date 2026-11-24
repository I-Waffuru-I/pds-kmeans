#!/usr/bin/env bash
#SBATCH --job-name=km_cuda_dbg

#SBATCH --partition=gpu_p100
#SBATCH --nodes=1
#SBATCH --gpus-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G

#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err

#SBATCH --time=00:05:00
#SBATCH --ntasks=1

#source /data/leuven/303/vsc30380/slurmhooks

source slurm/common.sh

need_bins "$BIN_CUDA"
echo $DEBUG_DATASET
DATASET="$DEBUG_DATASET"
ensure_datasets
init_csv cudadbg

run_timed cudadbg "$BIN_CUDA" 1 serial

echo "Results in $CSV"
