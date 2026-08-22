#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 4 ]; then
  echo "usage: $0 ENDPOINT BUCKET ACCESS_KEY SECRET_KEY" >&2
  exit 2
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
PLAN="$PROJECT_DIR/benchmarks/scenarios.tsv"
ELIGIBILITY="$PROJECT_DIR/benchmarks/eligibility.tsv"
S5CMD_IMAGE="docker.io/peakcom/s5cmd@sha256:2ff939e2ee3c76adcadd78dbfc3e2569b18a3743ed9dcfccb1ec589af7fb9903"
ENDPOINT=$1
BUCKET=$2
ACCESS_KEY=$3
SECRET_KEY=$4
IMPLEMENTATION=${FLYOLOGY_S3_IMPLEMENTATION:?FLYOLOGY_S3_IMPLEMENTATION is required}
SERVER_REVISION=${FLYOLOGY_S3_SERVER_REVISION:-unrecorded}
PROFILE=${FLYOLOGY_BENCH_PROFILE:-smoke}
REQUESTED_REPETITIONS=${FLYOLOGY_BENCH_REPETITIONS:-5}
ONLY_SCENARIO=${FLYOLOGY_BENCH_SCENARIO:-}
CAMPAIGN=${FLYOLOGY_BENCH_CAMPAIGN:-standalone-$$}
OUTPUT_ROOT=${FLYOLOGY_BENCH_OUTPUT:-"/tmp/flyology-benchmark-$CAMPAIGN"}
WORK_ROOT=$(mktemp -d "/tmp/flyology-bench-endpoint-$IMPLEMENTATION.XXXXXX")
PAYLOAD_ROOT="$WORK_ROOT/payloads"
DOWNLOAD_ROOT="$WORK_ROOT/downloads"
COMMAND_ROOT="$WORK_ROOT/commands"
CLIENT="flyology-bench-client-$$"

case "$PROFILE" in
  smoke|full) ;;
  *) echo "FLYOLOGY_BENCH_PROFILE must be smoke or full" >&2; exit 2 ;;
esac
case "$REQUESTED_REPETITIONS" in
  ''|*[!0-9]*) echo "FLYOLOGY_BENCH_REPETITIONS must be a positive integer" >&2; exit 2 ;;
esac
case "$SERVER_REVISION" in
  ''|*$'\n'*|*$'\t'*)
    echo "server revision must be one nonempty TSV-safe line" >&2
    exit 2
    ;;
esac
if [ "$REQUESTED_REPETITIONS" -lt 1 ]; then
  echo "FLYOLOGY_BENCH_REPETITIONS must be at least 1" >&2
  exit 2
fi
if [ "$PROFILE" = full ] \
  && { [ "$SERVER_REVISION" = unrecorded ] \
    || [ "$SERVER_REVISION" = working-tree ]; }
then
  echo "full campaign requires an immutable server revision" >&2
  exit 1
fi

cleanup() {
  if docker inspect "$CLIENT" >/dev/null 2>&1; then
    docker stop --timeout 2 "$CLIENT" >/dev/null 2>&1 || true
  fi
  case "$WORK_ROOT" in
    "/tmp/flyology-bench-endpoint-$IMPLEMENTATION."*) rm -rf "$WORK_ROOT" ;;
    *) echo "refusing unexpected benchmark cleanup path" >&2 ;;
  esac
}
trap cleanup EXIT INT TERM

mkdir -p "$PAYLOAD_ROOT" "$DOWNLOAD_ROOT" "$COMMAND_ROOT" \
  "$OUTPUT_ROOT/raw/$IMPLEMENTATION"
RESULTS="$OUTPUT_ROOT/samples.tsv"
if [ ! -e "$RESULTS" ]; then
  printf '%s\n' 'campaign	implementation	scenario	repetition	status	objects_per_batch	object_bytes	concurrency	batches	duration_ns	operations	bytes	ops_per_second	bytes_per_second	note' >"$RESULTS"
fi
REVISIONS="$OUTPUT_ROOT/server-revisions.tsv"
if [ ! -e "$REVISIONS" ]; then
  printf 'implementation\tserver_revision\tclient_revision\n' >"$REVISIONS"
fi
EXISTING_REVISION=$(awk -F '\t' -v implementation="$IMPLEMENTATION" \
  'NR > 1 && $1 == implementation { print $2; exit }' "$REVISIONS")
if [ -z "$EXISTING_REVISION" ]; then
  printf '%s\t%s\t%s\n' "$IMPLEMENTATION" "$SERVER_REVISION" \
    "$S5CMD_IMAGE" >>"$REVISIONS"
elif [ "$EXISTING_REVISION" != "$SERVER_REVISION" ]; then
  echo "server revision changed within benchmark campaign: $IMPLEMENTATION" >&2
  exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
  hash_file() { sha256sum "$1" | awk '{print $1}'; }
  hash_stream() { sha256sum | awk '{print $1}'; }
elif command -v shasum >/dev/null 2>&1; then
  hash_file() { shasum -a 256 "$1" | awk '{print $1}'; }
  hash_stream() { shasum -a 256 | awk '{print $1}'; }
else
  echo "neither sha256sum nor shasum is available" >&2
  exit 1
fi

now_ns() {
  perl -MTime::HiRes=clock_gettime,CLOCK_MONOTONIC \
    -e 'printf "%.0f\n", clock_gettime(CLOCK_MONOTONIC) * 1_000_000_000'
}

docker pull "$S5CMD_IMAGE" >/dev/null
docker run --detach --rm --name "$CLIENT" \
  --add-host host.docker.internal:host-gateway \
  --volume "$PAYLOAD_ROOT:/data:ro" \
  --volume "$DOWNLOAD_ROOT:/out" \
  --volume "$COMMAND_ROOT:/commands:ro" \
  --env "AWS_ACCESS_KEY_ID=$ACCESS_KEY" \
  --env "AWS_SECRET_ACCESS_KEY=$SECRET_KEY" \
  --env AWS_REGION=us-east-1 \
  --entrypoint /bin/sleep "$S5CMD_IMAGE" 86400 >/dev/null

s5cmd() {
  docker exec "$CLIENT" /s5cmd --retry-count 0 \
    --endpoint-url "$ENDPOINT" "$@"
}

s5cmd_batch() {
  local concurrency=$1
  local commands=$2
  docker exec "$CLIENT" /s5cmd --log error --json --stat \
    --retry-count 0 --numworkers "$concurrency" \
    --endpoint-url "$ENDPOINT" run "/commands/$commands"
}

s5cmd mb "s3://$BUCKET" >/dev/null

make_payload() {
  local bytes=$1
  local path="$PAYLOAD_ROOT/$bytes.bin"
  if [ ! -e "$path" ]; then
    dd if=/dev/zero of="$path" bs=1048576 count=$((bytes / 1048576)) 2>/dev/null
    if [ $((bytes % 1048576)) -ne 0 ]; then
      dd if=/dev/zero of="$path" bs=1 count=$((bytes % 1048576)) \
        seek=$((bytes - (bytes % 1048576))) conv=notrunc 2>/dev/null
    fi
  fi
  test "$(wc -c <"$path" | tr -d ' ')" = "$bytes"
}

write_put_commands() {
  local file=$1 prefix=$2 bytes=$3 objects=$4
  : >"$COMMAND_ROOT/$file"
  local index=1
  while [ "$index" -le "$objects" ]; do
    #  Every currently eligible setup and measured upload is at most 64 MiB.
    #  Keep it on PutObject so a GET scenario never silently depends on the
    #  separately blocked multipart-server surface.
    printf 'cp --part-size 128 /data/%s.bin s3://%s/%s-%08d\n' \
      "$bytes" "$BUCKET" "$prefix" "$index" >>"$COMMAND_ROOT/$file"
    index=$((index + 1))
  done
}

write_multipart_put_commands() {
  local file=$1 prefix=$2 bytes=$3 objects=$4
  : >"$COMMAND_ROOT/$file"
  local index=1
  while [ "$index" -le "$objects" ]; do
    printf 'cp --part-size 8 /data/%s.bin s3://%s/%s-%08d\n' \
      "$bytes" "$BUCKET" "$prefix" "$index" >>"$COMMAND_ROOT/$file"
    index=$((index + 1))
  done
}

write_get_commands() {
  local file=$1 prefix=$2 objects=$3
  : >"$COMMAND_ROOT/$file"
  local index=1
  while [ "$index" -le "$objects" ]; do
    printf 'cp s3://%s/%s-%08d /out/%s-%08d\n' \
      "$BUCKET" "$prefix" "$index" "$prefix" "$index" \
      >>"$COMMAND_ROOT/$file"
    index=$((index + 1))
  done
}

write_copy_commands() {
  local file=$1 source_prefix=$2 destination_prefix=$3 objects=$4
  : >"$COMMAND_ROOT/$file"
  local index=1
  while [ "$index" -le "$objects" ]; do
    printf 'cp s3://%s/%s-%08d s3://%s/%s-%08d\n' \
      "$BUCKET" "$source_prefix" "$index" \
      "$BUCKET" "$destination_prefix" "$index" \
      >>"$COMMAND_ROOT/$file"
    index=$((index + 1))
  done
}

write_delete_commands() {
  local file=$1 prefix=$2 objects=$3
  : >"$COMMAND_ROOT/$file"
  local index=1
  while [ "$index" -le "$objects" ]; do
    printf 'rm s3://%s/%s-%08d\n' \
      "$BUCKET" "$prefix" "$index" >>"$COMMAND_ROOT/$file"
    index=$((index + 1))
  done
}

write_list_commands() {
  local file=$1 prefix=$2
  : >"$COMMAND_ROOT/$file"
  printf 'ls s3://%s/%s-\n' "$BUCKET" "$prefix" >>"$COMMAND_ROOT/$file"
}

clear_downloads() {
  find "$DOWNLOAD_ROOT" -type f -delete
}

prepare_objects() {
  local prefix=$1 bytes=$2 objects=$3 concurrency=$4
  local setup_log="$WORK_ROOT/setup-$prefix.jsonl"
  make_payload "$bytes"
  write_put_commands setup.txt "$prefix" "$bytes" "$objects"
  if ! s5cmd_batch "$concurrency" setup.txt >"$setup_log"; then
    echo "object setup failed for $prefix" >&2
    tail -50 "$setup_log" >&2
    return 1
  fi
}

verify_remote_pair() {
  local prefix=$1 bytes=$2 objects=$3
  local expected observed
  expected=$(hash_file "$PAYLOAD_ROOT/$bytes.bin")
  s5cmd head "s3://$BUCKET/$prefix-00000001" >/dev/null
  s5cmd head "s3://$BUCKET/$prefix-$(printf '%08d' "$objects")" >/dev/null
  observed=$(s5cmd cat "s3://$BUCKET/$prefix-00000001" | hash_stream)
  test "$observed" = "$expected"
  observed=$(s5cmd cat \
    "s3://$BUCKET/$prefix-$(printf '%08d' "$objects")" | hash_stream)
  test "$observed" = "$expected"
}

verify_download_pair() {
  local prefix=$1 bytes=$2 objects=$3
  local expected last
  expected=$(hash_file "$PAYLOAD_ROOT/$bytes.bin")
  last=$(printf '%08d' "$objects")
  test "$(find "$DOWNLOAD_ROOT" -type f | wc -l | tr -d ' ')" = "$objects"
  test "$(hash_file "$DOWNLOAD_ROOT/$prefix-00000001")" = "$expected"
  test "$(hash_file "$DOWNLOAD_ROOT/$prefix-$last")" = "$expected"
}

verify_deleted_pair() {
  local prefix=$1 objects=$2 last
  last=$(printf '%08d' "$objects")
  if s5cmd head "s3://$BUCKET/$prefix-00000001" >/dev/null 2>&1; then
    echo "DeleteObject benchmark left its first object visible" >&2
    exit 1
  fi
  if s5cmd head "s3://$BUCKET/$prefix-$last" >/dev/null 2>&1; then
    echo "DeleteObject benchmark left its last object visible" >&2
    exit 1
  fi
}

verify_list_count() {
  local prefix=$1 objects=$2 observed
  local list_log="$WORK_ROOT/list-$prefix.txt"
  if ! s5cmd ls "s3://$BUCKET/$prefix-" >"$list_log"; then
    echo "namespace listing failed for $prefix" >&2
    tail -50 "$list_log" >&2
    return 1
  fi
  observed=$(wc -l <"$list_log" | tr -d ' ')
  if [ "$observed" != "$objects" ]; then
    echo "namespace listing count mismatch for $prefix: expected $objects, observed $observed" >&2
    tail -50 "$list_log" >&2
    return 1
  fi
}

cleanup_objects() {
  local prefix=$1 objects=$2 concurrency=$3
  local cleanup_log="$WORK_ROOT/cleanup-$prefix.jsonl"
  write_delete_commands cleanup.txt "$prefix" "$objects"
  if ! s5cmd_batch "$concurrency" cleanup.txt >"$cleanup_log"; then
    echo "namespace cleanup failed for $prefix" >&2
    tail -50 "$cleanup_log" >&2
    return 1
  fi
  verify_deleted_pair "$prefix" "$objects"
}

run_scenario() {
  local scenario=$1 operation=$2 bytes=$3 objects=$4 concurrency=$5
  local duration=$6 warmup=$7
  local prefix commands byte_factor source_prefix
  prefix=$scenario
  commands="$scenario.txt"
  byte_factor=$bytes
  source_prefix=""

  case "$operation" in
    put)
      make_payload "$bytes"
      write_put_commands "$commands" "$prefix" "$bytes" "$objects"
      ;;
    multipart-put)
      make_payload "$bytes"
      write_multipart_put_commands "$commands" "$prefix" "$bytes" "$objects"
      ;;
    get)
      case "$scenario" in
        small-get) prefix=small-put ;;
        medium-get) prefix=medium-put ;;
        large-get) prefix=large-get; prepare_objects "$prefix" "$bytes" "$objects" "$concurrency" ;;
      esac
      write_get_commands "$commands" "$prefix" "$objects"
      ;;
    copy)
      source_prefix="$scenario-source"
      prepare_objects "$source_prefix" "$bytes" "$objects" "$concurrency"
      write_copy_commands "$commands" "$source_prefix" "$prefix" "$objects"
      ;;
    delete)
      prefix=namespace-delete
      make_payload "$bytes"
      write_delete_commands "$commands" "$prefix" "$objects"
      byte_factor=0
      ;;
    list)
      prepare_objects "$prefix" "$bytes" "$objects" "$concurrency"
      write_list_commands "$commands" "$prefix"
      byte_factor=0
      verify_list_count "$prefix" "$objects"
      ;;
    *) echo "unsupported eligible benchmark operation: $operation" >&2; exit 1 ;;
  esac

  if [ "$warmup" -gt 0 ]; then
    local warm_start warm_now
    warm_start=$(now_ns)
    while :; do
      if [ "$operation" = delete ]; then
        prepare_objects "$prefix" "$bytes" "$objects" "$concurrency"
      elif [ "$operation" = get ]; then
        clear_downloads
      fi
      s5cmd_batch "$concurrency" "$commands" >/dev/null
      warm_now=$(now_ns)
      if [ $(((warm_now - warm_start) / 1000000000)) -ge "$warmup" ]; then
        break
      fi
    done
  fi

  local repetitions=$REQUESTED_REPETITIONS
  if [ "$PROFILE" = smoke ]; then repetitions=1; duration=0; fi
  local repetition=1
  while [ "$repetition" -le "$repetitions" ]; do
    local start finish current batches total_operations total_bytes
    local ops_rate bytes_rate log
    log="$OUTPUT_ROOT/raw/$IMPLEMENTATION/$scenario-$repetition.jsonl"
    : >"$log"
    start=$(now_ns)
    batches=0
    while :; do
      if [ "$operation" = delete ]; then
        prepare_objects "$prefix" "$bytes" "$objects" "$concurrency"
      elif [ "$operation" = get ]; then
        clear_downloads
      fi
      s5cmd_batch "$concurrency" "$commands" >>"$log"
      batches=$((batches + 1))
      current=$(now_ns)
      if [ "$duration" -eq 0 ] \
        || [ $(((current - start) / 1000000000)) -ge "$duration" ]; then
        break
      fi
    done
    finish=$(now_ns)
    case "$operation" in
      put|multipart-put|copy) verify_remote_pair "$prefix" "$bytes" "$objects" ;;
      get) verify_download_pair "$prefix" "$bytes" "$objects" ;;
      delete) verify_deleted_pair "$prefix" "$objects" ;;
      list) verify_list_count "$prefix" "$objects" ;;
    esac
    total_operations=$((objects * batches))
    total_bytes=$((byte_factor * total_operations))
    ops_rate=$(awk -v n="$total_operations" -v d="$((finish - start))" \
      'BEGIN { printf "%.6f", n * 1000000000 / d }')
    bytes_rate=$(awk -v n="$total_bytes" -v d="$((finish - start))" \
      'BEGIN { printf "%.6f", n * 1000000000 / d }')
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$CAMPAIGN" "$IMPLEMENTATION" "$scenario" "$repetition" passed \
      "$objects" "$bytes" "$concurrency" "$batches" "$((finish - start))" \
      "$total_operations" "$total_bytes" "$ops_rate" "$bytes_rate" \
      "aggregate-s5cmd-no-latency-percentiles" >>"$RESULTS"
    repetition=$((repetition + 1))
  done
  if [ "$operation" = list ]; then
    cleanup_objects "$prefix" "$objects" "$concurrency"
  fi
  clear_downloads
}

while IFS=$'\t' read -r scenario operation bytes objects concurrency duration warmup; do
  [ "$scenario" = scenario ] && continue
  if [ -n "$ONLY_SCENARIO" ] && [ "$scenario" != "$ONLY_SCENARIO" ]; then
    continue
  fi
  status=$(awk -F '\t' -v name="$scenario" '$1 == name { print $2 }' "$ELIGIBILITY")
  if [ "$status" = blocked ]; then
    reason=$(awk -F '\t' -v name="$scenario" '$1 == name { print $3 }' "$ELIGIBILITY")
    printf '%s\t%s\t%s\t0\tblocked\t%s\t%s\t%s\t0\t0\t0\t0\t0\t0\t%s\n' \
      "$CAMPAIGN" "$IMPLEMENTATION" "$scenario" "$objects" "$bytes" \
      "$concurrency" "$reason" >>"$RESULTS"
    continue
  fi
  if [ "$PROFILE" = smoke ]; then
    case "$scenario" in
      small-*) objects=64; concurrency=4 ;;
      medium-*) objects=8; concurrency=4 ;;
      large-get) objects=2; concurrency=2 ;;
      large-multipart-put) objects=2; concurrency=2 ;;
      large-copy) objects=2; concurrency=2 ;;
      namespace-delete) objects=64; concurrency=4 ;;
      namespace-list) objects=64; concurrency=4 ;;
    esac
    warmup=0
  fi
  echo "benchmark $IMPLEMENTATION $scenario ($PROFILE)"
  run_scenario "$scenario" "$operation" "$bytes" "$objects" \
    "$concurrency" "$duration" "$warmup"
done <"$PLAN"

echo "aggregate benchmark endpoint $IMPLEMENTATION: OK"
