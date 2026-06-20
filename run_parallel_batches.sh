#!/usr/bin/env bash
set -euo pipefail

# Parallel batch generation.
#
# The NUMBER OF BATCHES and the FAULT SCHEDULE are defined in exactly one place:
#   get_fault_batch_run_flags.m  (edit the Batch_fault_order_reference line)
# This script reads the batch count from that file so the two can never drift
# out of sync. To change how many batches run, edit get_fault_batch_run_flags.m
# only -- do NOT hardcode a number here.
#
# Usage:
#   ./run_parallel_batches.sh [workers] [output_dir]
#     workers     - number of parallel Octave processes (default: logical CPU count).
#                   On a cloud VM, set this to the number of cores you provisioned.
#     output_dir  - where the per-batch CSVs are written
#                   (default: output_<num_batches>/batch_csv).

num_batches="$(octave --quiet --eval "[~, n] = get_fault_batch_run_flags(); printf('%d', n);")"

workers="${1:-$(sysctl -n hw.logicalcpu 2>/dev/null || nproc 2>/dev/null || echo 4)}"
output_dir="${2:-output_${num_batches}/batch_csv}"

mkdir -p "$output_dir"
find "$output_dir" -maxdepth 1 -type f -name 'Batch_*.csv' -delete

seq 1 "$num_batches" | xargs -P "$workers" -I {} \
    octave --quiet --eval "Generate_Single_Batch_CSV({}, '$output_dir');"

count="$(find "$output_dir" -maxdepth 1 -type f -name 'Batch_*.csv' | wc -l | tr -d ' ')"
echo "Generated $count of $num_batches batch CSVs in $output_dir"
test "$count" = "$num_batches"
