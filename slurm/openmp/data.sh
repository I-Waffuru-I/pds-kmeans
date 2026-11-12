#!/usr/bin/env bash

mkdir -p logs
mkdir -p logs/old
_=$(mv logs/*.err logs/old/)
_=$(mv logs/*.out logs/old/)

CLUSTER="wice"
ACC="llp_h_pds"

# --parsable prints "jobid;cluster" when -M is used; keep only the job id
submit() { sbatch -M "$CLUSTER" --account "$ACC" --parsable "$@" | cut -d';' -f1; }

b=$(submit slurm/openmp/00_build.slurm)
c=$(submit --dependency=afterok:"$b" slurm/openmp/09_POST_EVAL.slurm)

echo "$c"
echo "Submitted. Watch with: squeue -u \$USER -M $CLUSTER"
