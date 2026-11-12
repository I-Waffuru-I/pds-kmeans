set tempdir := "/tmp"

# Default variables (can be overridden on the CLI, e.g. `just threads=8 run-omp`)
# dataset := "datasets/100000x5.csv"
# dataset := "datasets/1M_1000000x4.csv"
dataset := "datasets/3M_3000000x6.csv"
output  := "output/output.csv"
# k       := "10"
k       := "10"
# reps    := "20"
reps    := "5"
seed    := "1337"
threads := "16"
blocks  := "1"
mode    := "omp"

# Executable paths produced by Makefile
serial_bin := "./build/bin/kmeans_serial"
omp_bin    := "./build/bin/kmeans_omp"
cuda_bin   := "./build/bin/kmeans_cuda"

# List all available recipes
default:
    @just --list

# Clean build artifacts
clean:
    make clean

# Build all executables (kmeans_serial and kmeans_omp)
build:
    make all

# Build only kmeans_serial
build-serial:
    make serial

# Build only kmeans_omp
build-omp:
    make omp

# Run kmeans_serial via Makefile with configurable parameters
run-serial submode="serial" *extra="":
    make run-serial ARGS="--input {{dataset}} --output {{output}} --repetitions {{reps}} --k {{k}} --seed {{seed}} --mode {{submode}}" EXTRAFLAGS="{{extra}}"

# Run kmeans_omp via Makefile with configurable mode & thread count
# Available omp modes: omp, omp-naive, omp-outeronly
run-omp submode=mode num_threads=threads *extra="":
    make run-omp ARGS="--input {{dataset}} --output {{output}} --repetitions {{reps}} --k {{k}} --seed {{seed}} --threads {{num_threads}} --mode {{submode}}" EXTRAFLAGS="{{extra}}"

# Run debug trace configuration (mouse_500x2.csv) for serial executable
debug-serial submode="serial" *extra="":
    make debug-serial EXTRAFLAGS="--mode {{submode}} {{extra}}"

# Run debug trace configuration (mouse_500x2.csv) for OpenMP executable
debug-omp submode=mode num_threads="4" *extra="":
    make debug-omp EXTRAFLAGS="--mode {{submode}} --threads {{num_threads}} {{extra}}"

# Run debug trace configuration, automatically picking kmeans_serial or kmeans_omp based on mode
debug submode="serial" num_threads="1":
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ "{{submode}}" =~ ^omp ]]; then
        make debug-omp EXTRAFLAGS="--mode {{submode}} --threads {{num_threads}}"
    else
        make debug-serial EXTRAFLAGS="--mode {{submode}}"
    fi

# Compare kmeans_serial and kmeans_omp using compare.py
compare num_threads=threads: build
    @mkdir -p output
    ./compare.py {{serial_bin}} {{omp_bin}} \
        --input {{dataset}} \
        --output {{output}} \
        --k {{k}} \
        --repetitions {{reps}} \
        --seed {{seed}} \
        --threads {{num_threads}}

# Compare any two modes (across kmeans_serial and/or kmeans_omp) and diff their outputs
compare-modes mode1="serial" mode2="omp" num_threads=threads: build
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p output
    bin_for() {
        if [[ "$1" =~ ^omp ]]; then
            echo "{{omp_bin}}"
        else
            echo "{{serial_bin}}"
        fi
    }
    bin1=$(bin_for "{{mode1}}")
    bin2=$(bin_for "{{mode2}}")
    "$bin1" --input {{dataset}} --output output/out_{{mode1}}.csv --repetitions {{reps}} --k {{k}} --seed {{seed}} --threads {{num_threads}} --mode {{mode1}}
    "$bin2" --input {{dataset}} --output output/out_{{mode2}}.csv --repetitions {{reps}} --k {{k}} --seed {{seed}} --threads {{num_threads}} --mode {{mode2}}
    diff -u output/out_{{mode1}}.csv output/out_{{mode2}}.csv && echo "Outputs for {{mode1}} and {{mode2}} match!"

# Benchmark multiple modes side-by-side (automatically picks the right executable per mode)
bench-modes *modes="serial omp-naive omp omp-outeronly": build
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p output
    for m in {{modes}}; do
        echo "=== Mode: $m (threads={{threads}}) ==="
        if [[ "$m" =~ ^omp ]]; then
            bin="{{omp_bin}}"
        else
            bin="{{serial_bin}}"
        fi
        "$bin" --input {{dataset}} --output output/bench_${m}.csv --repetitions {{reps}} --k {{k}} --seed {{seed}} --threads {{threads}} --mode "$m"
    done

# Benchmark thread scaling for a given OpenMP mode (e.g. `just bench-threads omp "1 2 4 8 16"`)
bench-threads submode=mode thread_list="1 2 4 8 16": build-omp
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p output
    for t in {{thread_list}}; do
        echo "=== Mode: {{submode}} | Threads: $t ==="
        {{omp_bin}} --input {{dataset}} --output output/bench_{{submode}}_t${t}.csv --repetitions {{reps}} --k {{k}} --seed {{seed}} --threads "$t" --mode "{{submode}}"
    done
