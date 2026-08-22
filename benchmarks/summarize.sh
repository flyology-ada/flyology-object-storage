#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 SAMPLES_TSV SUMMARY_TSV" >&2
  exit 2
fi

SAMPLES=$1
SUMMARY=$2
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
IMPLEMENTATIONS="$SCRIPT_DIR/implementations.tsv"
ELIGIBILITY="$SCRIPT_DIR/eligibility.tsv"
TEMP_ROOT=$(mktemp -d /tmp/flyology-benchmark-summary.XXXXXX)

cleanup() {
  case "$TEMP_ROOT" in
    /tmp/flyology-benchmark-summary.*) rm -rf "$TEMP_ROOT" ;;
    *) echo "refusing unexpected summary cleanup path" >&2 ;;
  esac
}
trap cleanup EXIT INT TERM

median() {
  local input=$1 count lower upper
  count=$(wc -l <"$input" | tr -d ' ')
  test "$count" -gt 0
  if [ $((count % 2)) -eq 1 ]; then
    sed -n "$(((count + 1) / 2))p" "$input"
  else
    lower=$(sed -n "$((count / 2))p" "$input")
    upper=$(sed -n "$((count / 2 + 1))p" "$input")
    awk -v left="$lower" -v right="$upper" \
      'BEGIN { printf "%.6f", (left + right) / 2 }'
  fi
}

printf 'implementation\tscenario\trepetitions\tmedian_ops_per_second\tmedian_bytes_per_second\tops_ratio_rustfs\tops_ratio_seaweedfs\tbytes_ratio_rustfs\tbytes_ratio_seaweedfs\n' >"$SUMMARY"

tail -n +2 "$IMPLEMENTATIONS" | while IFS=$'\t' read -r implementation _; do
  tail -n +2 "$ELIGIBILITY" | while IFS=$'\t' read -r scenario status _; do
    [ "$status" = supported ] || continue
    ops="$TEMP_ROOT/$implementation-$scenario-ops"
    bytes="$TEMP_ROOT/$implementation-$scenario-bytes"
    awk -F '\t' -v impl="$implementation" -v name="$scenario" \
      '$2 == impl && $3 == name && $5 == "passed" { print $13 }' \
      "$SAMPLES" | sort -n >"$ops"
    awk -F '\t' -v impl="$implementation" -v name="$scenario" \
      '$2 == impl && $3 == name && $5 == "passed" { print $14 }' \
      "$SAMPLES" | sort -n >"$bytes"
    if [ ! -s "$ops" ]; then
      continue
    fi
    repetitions=$(wc -l <"$ops" | tr -d ' ')
    median_ops=$(median "$ops")
    median_bytes=$(median "$bytes")
    printf '%s\t%s\t%s\t%s\t%s\n' \
      "$implementation" "$scenario" "$repetitions" \
      "$median_ops" "$median_bytes" >>"$TEMP_ROOT/medians.tsv"
  done
done

if [ ! -s "$TEMP_ROOT/medians.tsv" ]; then
  echo "benchmark samples contain no passed supported scenario" >&2
  exit 1
fi

while IFS=$'\t' read -r implementation scenario repetitions median_ops median_bytes; do
  rustfs_ops=$(awk -F '\t' -v name="$scenario" \
    '$1 == "rustfs" && $2 == name { print $4 }' "$TEMP_ROOT/medians.tsv")
  seaweedfs_ops=$(awk -F '\t' -v name="$scenario" \
    '$1 == "seaweedfs" && $2 == name { print $4 }' "$TEMP_ROOT/medians.tsv")
  rustfs_bytes=$(awk -F '\t' -v name="$scenario" \
    '$1 == "rustfs" && $2 == name { print $5 }' "$TEMP_ROOT/medians.tsv")
  seaweedfs_bytes=$(awk -F '\t' -v name="$scenario" \
    '$1 == "seaweedfs" && $2 == name { print $5 }' "$TEMP_ROOT/medians.tsv")
  ops_rustfs=$(awk -v value="$median_ops" -v reference="$rustfs_ops" \
    'BEGIN { if (reference > 0) printf "%.6f", value / reference }')
  ops_seaweedfs=$(awk -v value="$median_ops" -v reference="$seaweedfs_ops" \
    'BEGIN { if (reference > 0) printf "%.6f", value / reference }')
  bytes_rustfs=$(awk -v value="$median_bytes" -v reference="$rustfs_bytes" \
    'BEGIN { if (reference > 0) printf "%.6f", value / reference }')
  bytes_seaweedfs=$(awk -v value="$median_bytes" -v reference="$seaweedfs_bytes" \
    'BEGIN { if (reference > 0) printf "%.6f", value / reference }')
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$implementation" "$scenario" "$repetitions" "$median_ops" \
    "$median_bytes" "$ops_rustfs" "$ops_seaweedfs" \
    "$bytes_rustfs" "$bytes_seaweedfs" >>"$SUMMARY"
done <"$TEMP_ROOT/medians.tsv"

echo "aggregate benchmark summary: $SUMMARY"
