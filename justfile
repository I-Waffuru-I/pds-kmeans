# Default variables (can be overridden on the CLI, e.g. `just threads=8 run-omp`)
# dataset := "datasets/100000x5.csv"
dataset := "datasets/1M_1000000x4.csv"
output  := "output/output.csv"
k       := "5"
reps    := "10"
seed    := "1337"
threads := "16"
mode    := "omp-naive"

# List all available recipes
default:
    @just --list

# Clean build artifacts
clean:
    make clean

# Build serial version
build-serial:
    make

# Build OpenMP version (rebuilds cleanly with -fopenmp -DHAVE_OMP)
build-omp:
    make clean omp

# Run serial mode via Makefile with configurable parameters
run-serial submode="serial-naive" *extra="":
    make run ARGS="--input {{dataset}} --output {{output}} --repetitions {{reps}} --k {{k}} --seed {{seed}} --mode {{submode}}" EXTRAFLAGS="{{extra}}"

# Run OpenMP mode via Makefile with configurable mode & thread count
run-omp submode=mode num_threads=threads *extra="":
    make omp run ARGS="--input {{dataset}} --output {{output}} --repetitions {{reps}} --k {{k}} --seed {{seed}} --threads {{num_threads}} --mode {{submode}}" EXTRAFLAGS="{{extra}}"

# Run debug trace configuration (mouse_500x2.csv) for any mode
debug submode="serial" num_threads="1":
    make omp debug EXTRAFLAGS="--mode {{submode}} --threads {{num_threads}}"

# Compare two modes (e.g. `just compare-modes serial-naive omp-naive 4`)
compare-modes mode1="serial-naive" mode2="omp-naive" num_threads=threads: build-omp
    @mkdir -p output
    ./kmeans --input {{dataset}} --output output/out_{{mode1}}.csv --repetitions {{reps}} --k {{k}} --seed {{seed}} --threads {{num_threads}} --mode {{mode1}}
    ./kmeans --input {{dataset}} --output output/out_{{mode2}}.csv --repetitions {{reps}} --k {{k}} --seed {{seed}} --threads {{num_threads}} --mode {{mode2}}
    diff -u output/out_{{mode1}}.csv output/out_{{mode2}}.csv && echo "Outputs for {{mode1}} and {{mode2}} match!"

# Benchmark multiple modes side-by-side on the same dataset
bench-modes *modes="serial-naive serial-cache omp-naive omp-2": build-omp
    #!/usr/bin/env bash
    set -euo pipefail
    for m in {{modes}}; do
        echo "=== Mode: $m (threads={{threads}}) ==="
        ./kmeans --input {{dataset}} --output output/bench_${m}.csv --repetitions {{reps}} --k {{k}} --seed {{seed}} --threads {{threads}} --mode "$m"
    done

# Benchmark thread scaling for a given OpenMP mode (e.g. `just bench-threads omp-naive "1 2 4 8 16"`)
bench-threads submode=mode thread_list="1 2 4 8": build-omp
    #!/usr/bin/env bash
    set -euo pipefail
    for t in {{thread_list}}; do
        echo "=== Mode: {{submode}} | Threads: $t ==="
        ./kmeans --input {{dataset}} --output output/bench_{{submode}}_t${t}.csv --repetitions {{reps}} --k {{k}} --seed {{seed}} --threads "$t" --mode "{{submode}}"
    done
