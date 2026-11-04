#!/usr/bin/env bash
# Usage (from project root): bash slurm/submit_all.sh
# Build first; correctness next; timing jobs run one at a time (exclusive nodes) after correctness succeeds.

mkdir -p logs
mkdir -p logs/old
e=$(mv logs/*.err logs/old/)
o=$(mv logs/*.out logs/old/)

CLUSTER="mindwell"
ACC="llp_h_pds"

# --parsable prints "jobid;cluster" when -M is used; keep only the job id
submit() { sbatch -M "$CLUSTER" --account "$ACC" --parsable "$@" | cut -d';' -f1; }

b=$(submit slurm/00_build.slurm)
c=$(submit --dependency=afterok:$b slurm/01_correctness.slurm)
t=$(submit --dependency=afterok:$c slurm/02_debug_trace.slurm)
p1=$(submit --dependency=afterok:$t slurm/03_serial_vs_omp.slurm)
p2=$(submit --dependency=afterok:$p1 slurm/04_thread_scaling.slurm)
p3=$(submit --dependency=afterok:$p2 slurm/05_parallel_levels.slurm)
p4=$(submit --dependency=afterok:$p3 slurm/06_inner_first_vs_latest.slurm)
#submit --dependency=afterany:$p4 slurm/07_analyze.slurm

echo "Submitted: build=$b correct=$c trace=$t timing=$p1,$p2,$p3,$p4"

echo "Submitted. Watch with: squeue -u \$USER -M $CLUSTER"
