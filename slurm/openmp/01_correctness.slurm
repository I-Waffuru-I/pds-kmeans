#!/usr/bin/env bash
#SBATCH --job-name=km_correct
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err
#SBATCH --time=00:30:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=4G
# Notebook: "Seriel vs OMP implementaties" + race-condition concerns.
# Every OMP mode must give output identical to serial (same seed => same centroid init,
# since centroids are pre-initialised outside the parallel loop). Run on the small dataset
# several times with many threads to expose races, then once on the big dataset.

#source /data/leuven/303/vsc30380/slurmhooks
source slurm/common.sh

need_bins "$BIN_SERIAL" "$BIN_OMP"; ensure_datasets

fail=0
check() { # check <ref> <other> <desc>
  if diff -q "$1" "$2" >/dev/null; then echo "PASS  $3"; else echo "FAIL  $3"; fail=1; fi
}

run() { # run <bin> <dataset> <out> <threads> <mode> [extra]
  local bin=$1 data=$2 out=$3 t=$4 mode=$5; shift 5
  "$bin" --input "$data" --output "$out" --repetitions "$REPS" --k "$K" --seed "$SEED" \
         --threads "$t" --mode "$mode" "$@" >/dev/null 2>>"$RESULTS/stderr_correct.log"
}

for DS in "$DEBUG_DATASET" "$DATASET"; do
  tag=$(basename "$DS" .csv)
  echo "=== dataset $tag ==="
  run "$BIN_SERIAL" "$DS" "$OUT/ref_${tag}.csv" 1 serial
  run "$BIN_SERIAL" "$DS" "$OUT/ref2_${tag}.csv" 1 serial-naive
  check "$OUT/ref_${tag}.csv" "$OUT/ref2_${tag}.csv" "$tag: serial == serial-naive"

  # repeat on small data to catch intermittent races; big data once to save time
  reps_outer=5; [[ "$DS" == "$DATASET" ]] && reps_outer=1
  for mode in omp omp-naive omp-2 omp-outer omp-nested omp-outeronly; do
    for t in 1 2 4 "$MAX_THREADS"; do
      for i in $(seq 1 $reps_outer); do
        run "$BIN_OMP" "$DS" "$OUT/chk_${tag}_${mode}_t${t}_$i.csv" "$t" "$mode"
        check "$OUT/ref_${tag}.csv" "$OUT/chk_${tag}_${mode}_t${t}_$i.csv" "$tag: $mode threads=$t try=$i vs serial"
      done
    done
  done
done

if python3 compare.py "$BIN_SERIAL" "$BIN_OMP" --input "$DEBUG_DATASET" \
--output "$OUT/cmp_$mode.csv" --k 3 --repetitions 10 --seed 1338 --threads 4 2>&1; then
echo "PASS  compare.py serial vs omp"
else echo "FAIL  compare.py serial vs omp"; fail=1; fi

# Same check using the course's compare.py (serial binary vs omp binary via a wrapper)
# echo "=== compare.py (omp-naive and omp, 4 threads) ==="
# for mode in omp-naive omp; do
  # cat > "$OUT/wrap_$mode.sh" <<W
# #!/usr/bin/env bash
# exec "$BIN_OMP" "\$@" --mode $mode
# W
  # chmod +x "$OUT/wrap_$mode.sh"
  # if python3 compare.py "$BIN_SERIAL"  "$OUT/wrap_$mode.sh" --input "$DEBUG_DATASET" \
       # --output "$OUT/cmp_$mode.csv" --k 3 --repetitions 10 --seed 1338 --threads 4 2>&1; then
    # echo "PASS  compare.py serial vs $mode"
  # else echo "FAIL  compare.py serial vs $mode"; fail=1; fi
# done

# [[ $fail -eq 0 ]] && echo "ALL CORRECTNESS CHECKS PASSED" || { echo "SOME CHECKS FAILED"; exit 1; }

