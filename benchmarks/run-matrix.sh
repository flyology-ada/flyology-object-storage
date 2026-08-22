#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
PROFILE=${FLYOLOGY_BENCH_PROFILE:-smoke}
CAMPAIGN=${FLYOLOGY_BENCH_CAMPAIGN:-"$(date -u +%Y%m%dT%H%M%SZ)-$$"}
OUTPUT_ROOT=${1:-"$SCRIPT_DIR/results/$CAMPAIGN"}
RUNNER="$SCRIPT_DIR/run-endpoint.sh"

case "$PROFILE" in
  smoke|full) ;;
  *) echo "FLYOLOGY_BENCH_PROFILE must be smoke or full" >&2; exit 2 ;;
esac

if [ "$PROFILE" = full ]; then
  : "${FLYOLOGY_BENCH_HOST_LABEL:?full campaign requires FLYOLOGY_BENCH_HOST_LABEL}"
  : "${FLYOLOGY_BENCH_POWER_MODE:?full campaign requires FLYOLOGY_BENCH_POWER_MODE}"
  : "${FLYOLOGY_BENCH_CPU_POLICY:?full campaign requires FLYOLOGY_BENCH_CPU_POLICY}"
fi

if ! grep -Fq 'flyology_http = "=0.1.2"' "$PROJECT_DIR/alire.toml"; then
  echo "benchmark comparison requires indexed flyology_http=0.1.2 fixed responses" >&2
  exit 1
fi

"$PROJECT_DIR/tools/verify-benchmark-plan.sh"
mkdir -p "$OUTPUT_ROOT"

SOURCE_REVISION=$(git -C "$PROJECT_DIR" rev-parse --verify HEAD 2>/dev/null \
  || true)
if [ -z "$SOURCE_REVISION" ]; then
  SOURCE_REVISION=uncommitted
fi

if command -v sha256sum >/dev/null 2>&1; then
  hash_file() { sha256sum "$1" | awk '{print $1}'; }
elif command -v shasum >/dev/null 2>&1; then
  hash_file() { shasum -a 256 "$1" | awk '{print $1}'; }
else
  echo "neither sha256sum nor shasum is available" >&2
  exit 1
fi

{
  echo "campaign=$CAMPAIGN"
  echo "profile=$PROFILE"
  echo "host_label=${FLYOLOGY_BENCH_HOST_LABEL:-unqualified-smoke-host}"
  echo "power_mode=${FLYOLOGY_BENCH_POWER_MODE:-unqualified}"
  echo "cpu_policy=${FLYOLOGY_BENCH_CPU_POLICY:-unqualified}"
  echo "started_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "uname=$(uname -a)"
  echo "docker=$(docker version --format '{{.Client.Version}}/{{.Server.Version}}')"
  echo "alr=$(alr version | head -1)"
  echo "gnat=$(alr -n exec -- gnatls --version | head -1)"
  echo "source_revision=$SOURCE_REVISION"
  echo "corpora_lock_sha256=$(hash_file "$PROJECT_DIR/coverage/corpora.lock.toml")"
  echo "scenario_sha256=$(hash_file "$SCRIPT_DIR/scenarios.tsv")"
  echo "implementation_sha256=$(hash_file "$SCRIPT_DIR/implementations.tsv")"
  echo "eligibility_sha256=$(hash_file "$SCRIPT_DIR/eligibility.tsv")"
  echo "exclusions_sha256=$(hash_file "$SCRIPT_DIR/exclusions.tsv")"
} >"$OUTPUT_ROOT/metadata.txt"

run_implementation() {
  local implementation=$1
  echo "benchmark matrix: $implementation ($PROFILE)"
  FLYOLOGY_S3_SERVER_RUNNER="$RUNNER" \
  FLYOLOGY_BENCH_PROFILE="$PROFILE" \
  FLYOLOGY_BENCH_CAMPAIGN="$CAMPAIGN" \
  FLYOLOGY_BENCH_OUTPUT="$OUTPUT_ROOT" \
    "$2" ${3:+"$3"}
}

run_implementation rustfs "$PROJECT_DIR/tests/scripts/test-rustfs.sh"
run_implementation seaweedfs "$PROJECT_DIR/tests/scripts/test-seaweedfs.sh"
run_implementation flyology-memory \
  "$PROJECT_DIR/tests/scripts/test-flyology-server.sh" memory
run_implementation flyology-files \
  "$PROJECT_DIR/tests/scripts/test-flyology-server.sh" files
run_implementation flyology-sqlite \
  "$PROJECT_DIR/tests/scripts/test-flyology-server.sh" sqlite

"$SCRIPT_DIR/summarize.sh" "$OUTPUT_ROOT/samples.tsv" \
  "$OUTPUT_ROOT/summary.tsv"
echo "finished_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  >>"$OUTPUT_ROOT/metadata.txt"
echo "benchmark matrix output: $OUTPUT_ROOT"
