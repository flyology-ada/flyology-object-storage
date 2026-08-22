#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 4 ]; then
  echo "usage: $0 ENDPOINT BUCKET ACCESS_KEY SECRET_KEY" >&2
  exit 2
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ENDPOINT=${1//host.docker.internal/127.0.0.1}
BUCKET=$2
ACCESS_KEY=$3
SECRET_KEY=$4
IMPLEMENTATION=${FLYOLOGY_S3_IMPLEMENTATION:?FLYOLOGY_S3_IMPLEMENTATION is required}
SERVER_REVISION=${FLYOLOGY_S3_SERVER_REVISION:-unrecorded}
PROFILE=${FLYOLOGY_BUCKET_TAG_BENCH_PROFILE:-smoke}
CAMPAIGN=${FLYOLOGY_BUCKET_TAG_BENCH_CAMPAIGN:-standalone-$$}
OUTPUT_ROOT=${FLYOLOGY_BUCKET_TAG_BENCH_OUTPUT:-"/tmp/flyology-bucket-tag-benchmark-$CAMPAIGN"}

if [[ "$IMPLEMENTATION" == flyology-* ]] \
  && [ -n "$(git -C "$PROJECT_DIR" status --porcelain)" ]
then
  SERVER_REVISION="$SERVER_REVISION-dirty"
fi

case "$PROFILE" in
  smoke)
    CYCLES=${FLYOLOGY_BUCKET_TAG_BENCH_CYCLES:-64}
    REPETITIONS=${FLYOLOGY_BUCKET_TAG_BENCH_REPETITIONS:-3}
    WARMUP=${FLYOLOGY_BUCKET_TAG_BENCH_WARMUP:-8}
    ;;
  full)
    CYCLES=${FLYOLOGY_BUCKET_TAG_BENCH_CYCLES:-2000}
    REPETITIONS=${FLYOLOGY_BUCKET_TAG_BENCH_REPETITIONS:-7}
    WARMUP=${FLYOLOGY_BUCKET_TAG_BENCH_WARMUP:-100}
    ;;
  *) echo "FLYOLOGY_BUCKET_TAG_BENCH_PROFILE must be smoke or full" >&2; exit 2 ;;
esac

for value in "$CYCLES" "$REPETITIONS" "$WARMUP"; do
  case "$value" in
    ''|*[!0-9]*) echo "benchmark counts must be nonnegative integers" >&2; exit 2 ;;
  esac
done
if [ "$CYCLES" -lt 1 ] || [ "$REPETITIONS" -lt 1 ]; then
  echo "cycles and repetitions must be positive" >&2
  exit 2
fi

mkdir -p "$OUTPUT_ROOT/raw"
(cd "$PROJECT_DIR/tests" && alr -n build -- -j1)
RAW="$OUTPUT_ROOT/raw/$IMPLEMENTATION.tsv"
CONVERTED="$OUTPUT_ROOT/raw/$IMPLEMENTATION.samples.tsv"
if [ -e "$RAW" ] || [ -e "$CONVERTED" ]; then
  echo "bucket tagging benchmark artifacts already exist for $IMPLEMENTATION" >&2
  exit 1
fi
"$PROJECT_DIR/tests/bin/s3_bucket_tagging_benchmark" \
  "$ENDPOINT" "$BUCKET" "$ACCESS_KEY" "$SECRET_KEY" \
  "$CYCLES" "$REPETITIONS" "$WARMUP" >"$RAW"

EXPECTED_HEADER=$'repetition\tcycles\toperations\tseconds\tlifecycles_per_second\toperations_per_second'
if [ "$(head -1 "$RAW")" != "$EXPECTED_HEADER" ]; then
  echo "bucket tagging benchmark emitted an invalid header" >&2
  exit 1
fi
if [ "$(($(wc -l <"$RAW") - 1))" -ne "$REPETITIONS" ]; then
  echo "bucket tagging benchmark emitted the wrong repetition count" >&2
  exit 1
fi

SAMPLES="$OUTPUT_ROOT/samples.tsv"
awk -F '\t' -v OFS='\t' -v campaign="$CAMPAIGN" \
  -v implementation="$IMPLEMENTATION" -v revision="$SERVER_REVISION" '
  NR > 1 {
    for (field = 1; field <= NF; field++) {
      gsub(/^ +| +$/, "", $field)
    }
    if ($1 !~ /^[0-9]+$/ || $2 !~ /^[0-9]+$/ || $3 != 4 * $2 ||
        $4 <= 0 || $5 <= 0 || $6 <= 0) {
      print "invalid bucket tagging benchmark sample" > "/dev/stderr"
      exit 1
    }
    print campaign, implementation, "put-get-delete-get-absent-lifecycle",
      $1, $2,
      $3, $4, $5, $6, revision,
      "persistent-client-sequential-correctness-checked"
  }
' "$RAW" >"$CONVERTED"
if [ "$(wc -l <"$CONVERTED" | tr -d ' ')" -ne "$REPETITIONS" ]; then
  echo "bucket tagging benchmark conversion lost samples" >&2
  exit 1
fi
SAMPLES_TEMP=$(mktemp "$OUTPUT_ROOT/.samples.$IMPLEMENTATION.XXXXXX")
cleanup_samples_temp() {
  case "$SAMPLES_TEMP" in
    "$OUTPUT_ROOT/.samples.$IMPLEMENTATION."*) rm -f "$SAMPLES_TEMP" ;;
    *) echo "refusing unexpected benchmark sample temporary" >&2 ;;
  esac
}
trap cleanup_samples_temp EXIT INT TERM
if [ -e "$SAMPLES" ]; then
  cp "$SAMPLES" "$SAMPLES_TEMP"
else
  printf 'campaign\timplementation\tscenario\trepetition\tcycles\toperations\tseconds\tlifecycles_per_second\toperations_per_second\tserver_revision\tnote\n' >"$SAMPLES_TEMP"
fi
cat "$CONVERTED" >>"$SAMPLES_TEMP"
mv "$SAMPLES_TEMP" "$SAMPLES"
trap - EXIT INT TERM

echo "bucket tagging benchmark endpoint $IMPLEMENTATION: OK"
