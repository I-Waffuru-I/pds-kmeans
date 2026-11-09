#!/usr/bin/env bash
#SBATCH --job-name=km_analyze
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err
#SBATCH --time=00:10:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=2G
# Notebook: speedup, efficiency, theoretical (Amdahl) vs measured speedup, plots.
source slurm/common.sh
python3 slurm/analyze.py "$RESULTS"
