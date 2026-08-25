#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
PROFILE=${FLYOLOGY_BUCKET_TAG_BENCH_PROFILE:-smoke}
CAMPAIGN=${FLYOLOGY_BUCKET_TAG_BENCH_CAMPAIGN:-"$(date -u +%Y%m%dT%H%M%SZ)-$$"}
OUTPUT_ROOT=${1:-"$SCRIPT_DIR/results/$CAMPAIGN-bucket-tagging"}
RUNNER="$SCRIPT_DIR/run-bucket-tagging-endpoint.sh"

if command -v sha256sum >/dev/null 2>&1; then
  hash_file() { sha256sum "$1" | awk '{print $1}'; }
elif command -v shasum >/dev/null 2>&1; then
  hash_file() { shasum -a 256 "$1" | awk '{print $1}'; }
else
  echo "neither sha256sum nor shasum is available" >&2
  exit 1
fi

case "$PROFILE" in
  smoke|full) ;;
  *) echo "FLYOLOGY_BUCKET_TAG_BENCH_PROFILE must be smoke or full" >&2; exit 2 ;;
esac
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
esac
if [ "$PROFILE" = full ]; then
  : "${FLYOLOGY_BENCH_HOST_LABEL:?full campaign requires FLYOLOGY_BENCH_HOST_LABEL}"
  : "${FLYOLOGY_BENCH_POWER_MODE:?full campaign requires FLYOLOGY_BENCH_POWER_MODE}"
  : "${FLYOLOGY_BENCH_CPU_POLICY:?full campaign requires FLYOLOGY_BENCH_CPU_POLICY}"
fi

SOURCE_REVISION=$(git -C "$PROJECT_DIR" rev-parse --verify HEAD 2>/dev/null || true)
if [ -z "$SOURCE_REVISION" ]; then SOURCE_REVISION=uncommitted; fi
if [ -n "$(git -C "$PROJECT_DIR" status --porcelain)" ]; then
  SOURCE_REVISION="$SOURCE_REVISION-dirty"
fi
if [ "$PROFILE" = full ] && [[ "$SOURCE_REVISION" == *-dirty ]]; then
  echo "full bucket tagging campaign requires a clean source revision" >&2
  exit 1
fi
mkdir -p "$OUTPUT_ROOT"
if [ -e "$OUTPUT_ROOT/metadata.txt" ] \
  || [ -e "$OUTPUT_ROOT/samples.tsv" ] \
  || [ -e "$OUTPUT_ROOT/summary.tsv" ]
then
  echo "bucket tagging benchmark output already contains a campaign" >&2
  exit 1
fi
{
  echo "campaign=$CAMPAIGN"
  echo "profile=$PROFILE"
  echo "host_label=${FLYOLOGY_BENCH_HOST_LABEL:-unqualified-smoke-host}"
  echo "power_mode=${FLYOLOGY_BENCH_POWER_MODE:-unqualified}"
  echo "cpu_policy=${FLYOLOGY_BENCH_CPU_POLICY:-unqualified}"
  # The files server selects this exact Ada commit policy explicitly; retain
  # it with every campaign so durability provenance is not inferred later.
  echo "flyology_files_commit_policy=Power_Loss_Durable"
  echo "started_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "uname=$(uname -a)"
  echo "docker=$(docker version --format '{{.Client.Version}}/{{.Server.Version}}')"
  echo "alr=$(alr --version)"
  echo "gnat=$(alr -n exec -- gnatls --version | head -1)"
  echo "source_revision=$SOURCE_REVISION"
  echo "cycles=$CYCLES"
  echo "repetitions=$REPETITIONS"
  echo "warmup_cycles=$WARMUP"
  echo "client=persistent-flyology-http-pr33-41471605"
  echo "corpora_lock_sha256=$(hash_file "$PROJECT_DIR/coverage/corpora.lock.toml")"
  echo "workload=sequential-put-get-delete-get-absent-with-alternating-values"
} >"$OUTPUT_ROOT/metadata.txt"

run_implementation() {
  local implementation=$1 launcher=$2 argument=${3:-}
  echo "bucket tagging benchmark matrix: $implementation ($PROFILE)"
  FLYOLOGY_S3_SERVER_RUNNER="$RUNNER" \
  FLYOLOGY_BUCKET_TAG_BENCH_PROFILE="$PROFILE" \
  FLYOLOGY_BUCKET_TAG_BENCH_CAMPAIGN="$CAMPAIGN" \
  FLYOLOGY_BUCKET_TAG_BENCH_OUTPUT="$OUTPUT_ROOT" \
    "$launcher" ${argument:+"$argument"}
}

run_implementation rustfs "$PROJECT_DIR/tests/scripts/test-rustfs.sh"
run_implementation seaweedfs "$PROJECT_DIR/tests/scripts/test-seaweedfs.sh"
run_implementation minio "$PROJECT_DIR/tests/scripts/test-minio.sh"
run_implementation flyology-memory \
  "$PROJECT_DIR/tests/scripts/test-flyology-server.sh" memory
run_implementation flyology-files \
  "$PROJECT_DIR/tests/scripts/test-flyology-server.sh" files
run_implementation flyology-sqlite \
  "$PROJECT_DIR/tests/scripts/test-flyology-server.sh" sqlite

SUMMARY="$OUTPUT_ROOT/summary.tsv"
printf 'implementation\tsamples\tmean_lifecycles_per_second\tmean_operations_per_second\trole\n' >"$SUMMARY"
awk -F '\t' -v OFS='\t' '
  NR > 1 {
    count[$2]++
    lifecycle[$2] += $8
    operations[$2] += $9
  }
  END {
    for (implementation in count) {
      role = "candidate"
      if (implementation == "rustfs" || implementation == "seaweedfs") {
        role = "permissive-reference"
      } else if (implementation == "minio") {
        role = "supplemental-compatibility"
      }
      printf "%s\t%d\t%.6f\t%.6f\t%s\n", implementation,
        count[implementation], lifecycle[implementation] / count[implementation],
        operations[implementation] / count[implementation], role
    }
  }
' "$OUTPUT_ROOT/samples.tsv" | LC_ALL=C sort >>"$SUMMARY"
echo "finished_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$OUTPUT_ROOT/metadata.txt"
HASHES="$OUTPUT_ROOT/hashes.sha256"
: >"$HASHES"
while IFS= read -r relative; do
  printf '%s  %s\n' "$(hash_file "$OUTPUT_ROOT/$relative")" "$relative" \
    >>"$HASHES"
done < <(
  printf '%s\n' metadata.txt samples.tsv summary.tsv
  find "$OUTPUT_ROOT/raw" -type f -print \
    | sed "s#^$OUTPUT_ROOT/##" | LC_ALL=C sort
)
echo "bucket tagging benchmark matrix output: $OUTPUT_ROOT"
