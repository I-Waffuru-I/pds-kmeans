set tempdir := "/tmp"

# Default variables (can be overridden on the CLI, e.g. `just threads=8 run-omp`)
dataset := "datasets/100000x5.csv"
output  := "output/output.csv"
k       := "10"
reps    := "20"
seed    := "1337"
threads := "4"
mode    := "omp-naive"

# List all available recipes
default:
    @just --list

# Clean build artifacts
clean:
    make clean

# Build all versions (serial and OpenMP)
build:
    make all

# Build serial version
build-serial:
    make serial

# Build OpenMP version
build-omp:
    make omp

# Run serial mode with configurable parameters
run-serial submode="serial-naive" *extra="": build-serial
    ./build/bin/kmeans_serial --input {{dataset}} --output {{output}} --repetitions {{reps}} --k {{k}} --seed {{seed}} --mode {{submode}} {{extra}}

# Run OpenMP mode with configurable mode & thread count
run-omp submode=mode num_threads=threads *extra="": build-omp
    ./build/bin/kmeans_omp --input {{dataset}} --output {{output}} --repetitions {{reps}} --k {{k}} --seed {{seed}} --threads {{num_threads}} --mode {{submode}} {{extra}}

# Run debug trace configuration (mouse_500x2.csv) for any mode
debug submode="serial" num_threads="1": build
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p output
    if [[ "{{submode}}" =~ ^omp ]]; then
        bin="./build/bin/kmeans_omp"
    else
        bin="./build/bin/kmeans_serial"
    fi
    "$bin" --input datasets/mouse_500x2.csv \
        --output output/output.csv \
        --repetitions 10 --k 3 \
        --centroidtrace output/centroidtrace.csv \
        --trace output/clustertrace.csv --seed 1338 \
        --mode "{{submode}}" --threads "{{num_threads}}"

# Compare two modes (e.g. `just compare-modes serial-naive omp-naive 4`)
compare-modes mode1="serial" mode2="omp-naive" num_threads=threads: build
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p output
    bin_for() {
        if [[ "$1" =~ ^omp ]]; then
            echo "./build/bin/kmeans_omp"
        else
            echo "./build/bin/kmeans_serial"
        fi
    }
    bin1=$(bin_for "{{mode1}}")
    bin2=$(bin_for "{{mode2}}")
    "$bin1" --input {{dataset}} --output output/out_{{mode1}}.csv --repetitions {{reps}} --k {{k}} --seed {{seed}} --threads {{num_threads}} --mode {{mode1}}
    "$bin2" --input {{dataset}} --output output/out_{{mode2}}.csv --repetitions {{reps}} --k {{k}} --seed {{seed}} --threads {{num_threads}} --mode {{mode2}}
    #diff -u output/out_{{mode1}}.csv output/out_{{mode2}}.csv && echo "Outputs for {{mode1}} and {{mode2}} match!"

# Benchmark multiple modes side-by-side on the same dataset
bench-modes *modes="serial-naive serial-cache omp-naive omp-2": build
    #!/usr/bin/env bash
    set -euo pipefail
    for m in {{modes}}; do
        echo "=== Mode: $m (threads={{threads}}) ==="
        if [[ "$m" =~ ^omp ]]; then
            bin="./build/bin/kmeans_omp"
        else
            bin="./build/bin/kmeans_serial"
        fi
        "$bin" --input {{dataset}} --output output/bench_${m}.csv --repetitions {{reps}} --k {{k}} --seed {{seed}} --threads {{threads}} --mode "$m"
    done

# Benchmark thread scaling for a given OpenMP mode (e.g. `just bench-threads omp-naive "1 2 4 8 16"`)
bench-threads submode=mode thread_list="1 2 4 8": build-omp
    #!/usr/bin/env bash
    set -euo pipefail
    for t in {{thread_list}}; do
        echo "=== Mode: {{submode}} | Threads: $t ==="
        ./build/bin/kmeans_omp --input {{dataset}} --output output/bench_{{submode}}_t${t}.csv --repetitions {{reps}} --k {{k}} --seed {{seed}} --threads "$t" --mode "{{submode}}"
    done
