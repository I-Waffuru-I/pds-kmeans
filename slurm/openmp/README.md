# SLURM tests for the k-means OpenMP notebook

Extract at the project root (next to `Makefile`), then: `bash slurm/submit_all.sh`
(or `sbatch` the scripts individually; always run `00_build.slurm` first).

| Script | Notebook item |
|---|---|
| `00_build` | serial and OpenMP binaries -> `build/bin/` |
| `01_correctness` | serial vs every OMP mode, many thread counts, repeated on small data to expose races; `compare.py` |
| `02_debug_trace` | `--trace` / `--centroidtrace` written after the parallel loop must equal serial |
| `03_serial_vs_omp` | serial vs OMP, speedup, serial vs OMP build on 1 thread (overhead) |
| `04_thread_scaling` | thread sweep for `omp-naive`, `omp`, `omp-2` -> speedup/efficiency |
| `05_parallel_levels` | inner only vs outer only vs nested (nesting on/off, `OMP_NESTED` problem) |
| `06_inner_first_vs_latest` | `omp-naive` (critical/atomic) vs `omp` (reduction + localCentroidMap), several K |
| `07_analyze` | speedup, efficiency, Amdahl fit, plots in `results/` |

Overrides: `sbatch --export=ALL,DATASET=datasets/x.csv,REPS=20,RUNS=5,THREAD_LIST="1 2 4 8 16 32",MODULES="GCC/12.3.0" slurm/04_thread_scaling.slurm`.
Adjust `--cpus-per-task`/`--partition`/`--account` in the `#SBATCH` headers for your cluster.
If `datasets/` is missing, `gen_datasets.py` creates synthetic stand-ins (replace with the real ones).

Things worth knowing
- `omp-outeronly`: the outer pragma in `src/kmeans.cpp` is `if (mode == "omp-outer" || mode == "omp-nested")`, so
  `omp-outeronly` never gets an outer parallel loop and will time like serial. `05` makes this visible.
- `omp-2` has no dedicated branch; it falls into the default `naiveOMPClustering` (same as `omp`).
- `serial-cache` (justfile) is not a real mode; it runs the same code as `serial`.
- The Amdahl "theoretical" p in `07` is fitted from the max-thread run, so it matches that point by construction;
  measure the real serial fraction (file read, init, merge) for an independent estimate.
- Tested locally only on a 1-core machine (correctness passes; timings there are meaningless).
