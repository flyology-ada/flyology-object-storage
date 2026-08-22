#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
EVIDENCE=${1:-"$PROJECT_DIR/benchmarks/evidence/20260822-bucket-tagging-smoke"}
METADATA="$EVIDENCE/metadata.txt"
SAMPLES="$EVIDENCE/samples.tsv"
SUMMARY="$EVIDENCE/summary.tsv"
HASHES="$EVIDENCE/hashes.sha256"

fail() {
  echo "bucket-tagging benchmark evidence: $*" >&2
  exit 1
}

for required in "$METADATA" "$SAMPLES" "$SUMMARY" "$HASHES"; do
  test -f "$required" || fail "missing ${required#$EVIDENCE/}"
done

implementations=(
  rustfs
  seaweedfs
  minio
  flyology-memory
  flyology-files
  flyology-sqlite
)

for implementation in "${implementations[@]}"; do
  test -f "$EVIDENCE/raw/$implementation.tsv" \
    || fail "missing raw/$implementation.tsv"
  test -f "$EVIDENCE/raw/$implementation.samples.tsv" \
    || fail "missing raw/$implementation.samples.tsv"
done

awk '
  BEGIN {
    expected["metadata.txt"] = 1
    expected["samples.tsv"] = 1
    expected["summary.tsv"] = 1
    split("rustfs seaweedfs minio flyology-memory flyology-files flyology-sqlite", names, " ")
    for (idx in names) {
      expected["raw/" names[idx] ".tsv"] = 1
      expected["raw/" names[idx] ".samples.tsv"] = 1
    }
  }
  NF != 2 || length($1) != 64 || $1 !~ /^[0-9a-f]+$/ || !($2 in expected) {
    print "invalid hash manifest row at line " NR > "/dev/stderr"
    exit 1
  }
  seen[$2]++ {
    print "duplicate hash manifest path: " $2 > "/dev/stderr"
    exit 1
  }
  END {
    if (NR != 15) {
      print "hash manifest must cover exactly fifteen retained artifacts" > "/dev/stderr"
      exit 1
    }
    for (path in expected) {
      if (!(path in seen)) {
        print "hash manifest is missing " path > "/dev/stderr"
        exit 1
      }
    }
  }
' "$HASHES" || fail "invalid hash manifest"

(
  cd "$EVIDENCE"
  shasum -a 256 -c hashes.sha256 >/dev/null
) || fail "artifact hash mismatch"

awk -F '=' '
  BEGIN {
    split("campaign profile host_label power_mode cpu_policy started_utc uname docker alr provenance_correction gnat source_revision cycles repetitions warmup_cycles client corpora_lock_sha256 workload finished_utc", keys, " ")
    for (idx in keys) expected[keys[idx]] = 1
  }
  NF < 2 || !($1 in expected) || substr($0, length($1) + 2) == "" {
    print "invalid metadata row at line " NR > "/dev/stderr"
    exit 1
  }
  seen[$1]++ {
    print "duplicate metadata key: " $1 > "/dev/stderr"
    exit 1
  }
  END {
    if (NR != 19) {
      print "metadata must contain exactly nineteen fields" > "/dev/stderr"
      exit 1
    }
    for (key in expected) {
      if (!(key in seen)) {
        print "metadata is missing " key > "/dev/stderr"
        exit 1
      }
    }
  }
' "$METADATA" || fail "invalid metadata schema"

metadata_value() {
  awk -F '=' -v key="$1" '$1 == key { print substr($0, length($1) + 2) }' "$METADATA"
}

campaign=$(metadata_value campaign)
profile=$(metadata_value profile)
source_revision=$(metadata_value source_revision)
corpora_lock=$(metadata_value corpora_lock_sha256)
alr_version=$(metadata_value alr)

test "$campaign" = "20260822Tbucket-tagging-clean" \
  || fail "unexpected campaign identity"
test "$profile" = "smoke" || fail "retained campaign must be labeled smoke"
test "$(metadata_value cycles)" = "64" || fail "expected 64 cycles"
test "$(metadata_value repetitions)" = "3" || fail "expected 3 repetitions"
test "$(metadata_value warmup_cycles)" = "8" || fail "expected 8 warmup cycles"
test "$(metadata_value client)" = "persistent-flyology-http-0.1.2" \
  || fail "unexpected benchmark client"
test "$(metadata_value workload)" \
  = "sequential-put-get-delete-get-absent-with-alternating-values" \
  || fail "unexpected workload"
test "$alr_version" = "alr 2.1.1" \
  || fail "retained Alire provenance must be the actual 'alr 2.1.1' version"
printf '%s\n' "$alr_version" \
  | grep -Eq '^alr [0-9]+\.[0-9]+\.[0-9]+([+~-][0-9A-Za-z.-]+)?$' \
  || fail "invalid Alire version provenance"
test "$(metadata_value provenance_correction)" \
  = "alr-field-only-from-same-host-tool-alr-2.1.1-measured-rows-and-source-revision-unchanged" \
  || fail "missing or invalid post-campaign provenance correction disclosure"

case "$source_revision" in
  *[!0-9a-f]*|'') fail "source revision is not a clean hexadecimal commit" ;;
esac
test "${#source_revision}" = 40 \
  || fail "source revision is not a full clean commit"
git -C "$PROJECT_DIR" cat-file -e "$source_revision^{commit}" 2>/dev/null \
  || fail "source revision is unavailable"
git -C "$PROJECT_DIR" merge-base --is-ancestor "$source_revision" HEAD \
  || fail "source revision is not an ancestor of this checkout"

current_corpora_lock=$(shasum -a 256 "$PROJECT_DIR/coverage/corpora.lock.toml" | awk '{print $1}')
test "$corpora_lock" = "$current_corpora_lock" \
  || fail "corpora lock no longer matches retained provenance"

awk -F '\t' -v campaign="$campaign" -v revision="$source_revision" '
  function abs(value) { return value < 0 ? -value : value }
  function rate_valid(count, seconds, rate, lower, upper) {
    if (seconds <= 0.0000005) return 0
    lower = count / (seconds + 0.0000005) - 0.0000005
    upper = count / (seconds - 0.0000005) + 0.0000005
    return rate >= lower && rate <= upper
  }
  BEGIN {
    expected_header = "campaign\timplementation\tscenario\trepetition\tcycles\toperations\tseconds\tlifecycles_per_second\toperations_per_second\tserver_revision\tnote"
    reference["rustfs"] = "ghcr.io/rustfs/rustfs@sha256:800cf3f352a0a27e3275ca854a51f0027975d7acc7a0d52089a35bcc9fcbf0b5"
    reference["seaweedfs"] = "docker.io/chrislusf/seaweedfs@sha256:7bea581f48155c069d3c725e60c386c88210c67cde8bce412344ff6ebea264da"
    reference["minio"] = "quay.io/minio/minio@sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e"
    reference["flyology-memory"] = revision
    reference["flyology-files"] = revision
    reference["flyology-sqlite"] = revision
  }
  NR == 1 {
    if ($0 != expected_header) {
      print "invalid samples header" > "/dev/stderr"
      exit 1
    }
    next
  }
  NF != 11 || $1 != campaign || !($2 in reference) ||
  $3 != "put-get-delete-get-absent-lifecycle" || $4 !~ /^[1-3]$/ ||
  $5 != 64 || $6 != 4 * $5 ||
  $7 !~ /^[0-9]+\.[0-9]+$/ || $7 <= 0 ||
  $8 !~ /^[0-9]+\.[0-9]+$/ || $8 <= 0 ||
  $9 !~ /^[0-9]+\.[0-9]+$/ || $9 <= 0 ||
  !rate_valid($5, $7, $8) || !rate_valid($6, $7, $9) ||
  abs($9 - 4 * $8) > 0.00001 ||
  $10 != reference[$2] ||
  $11 != "persistent-client-sequential-correctness-checked" {
    print "invalid sample row at line " NR > "/dev/stderr"
    exit 1
  }
  seen[$2 SUBSEP $4]++ {
    print "duplicate sample for " $2 " repetition " $4 > "/dev/stderr"
    exit 1
  }
  { count[$2]++ }
  END {
    if (NR != 19) {
      print "samples must contain exactly eighteen rows" > "/dev/stderr"
      exit 1
    }
    for (implementation in reference) {
      if (count[implementation] != 3) {
        print "expected three samples for " implementation > "/dev/stderr"
        exit 1
      }
    }
  }
' "$SAMPLES" || fail "invalid samples"

awk -F '\t' '
  BEGIN {
    role["rustfs"] = "permissive-reference"
    role["seaweedfs"] = "permissive-reference"
    role["minio"] = "supplemental-compatibility"
    role["flyology-memory"] = "candidate"
    role["flyology-files"] = "candidate"
    role["flyology-sqlite"] = "candidate"
  }
  NR == FNR {
    if (FNR > 1) {
      sample_count[$2]++
      lifecycle_sum[$2] += $8
      operation_sum[$2] += $9
    }
    next
  }
  FNR == 1 {
    if ($0 != "implementation\tsamples\tmean_lifecycles_per_second\tmean_operations_per_second\trole") {
      print "invalid summary header" > "/dev/stderr"
      exit 1
    }
    next
  }
  NF != 5 || !($1 in role) || $2 != 3 || $2 != sample_count[$1] ||
  $3 !~ /^[0-9]+\.[0-9]+$/ || $3 <= 0 ||
  $4 !~ /^[0-9]+\.[0-9]+$/ || $4 <= 0 ||
  $3 != sprintf("%.6f", lifecycle_sum[$1] / sample_count[$1]) ||
  $4 != sprintf("%.6f", operation_sum[$1] / sample_count[$1]) ||
  $5 != role[$1] {
    print "invalid summary row at line " NR > "/dev/stderr"
    exit 1
  }
  seen[$1]++ {
    print "duplicate summary implementation: " $1 > "/dev/stderr"
    exit 1
  }
  END {
    if (FNR != 7) {
      print "summary must contain exactly six implementations" > "/dev/stderr"
      exit 1
    }
    for (implementation in role) {
      if (!(implementation in seen)) {
        print "summary is missing " implementation > "/dev/stderr"
        exit 1
      }
    }
  }
' "$SAMPLES" "$SUMMARY" || fail "invalid summary or summary derivation"

for implementation in "${implementations[@]}"; do
  awk -F '\t' -v implementation="$implementation" '
    NR == FNR {
      if (FNR > 1 && $2 == implementation) expected[++count] = $0
      next
    }
    $0 != expected[FNR] {
      print "converted sample does not match aggregate sample at line " FNR > "/dev/stderr"
      exit 1
    }
    END {
      if (count != 3 || FNR != 3) {
        print "converted samples must contain exactly three aggregate rows" > "/dev/stderr"
        exit 1
      }
    }
  ' "$SAMPLES" "$EVIDENCE/raw/$implementation.samples.tsv" \
    || fail "invalid raw/$implementation.samples.tsv derivation"

  awk -F '\t' -v implementation="$implementation" '
    function rate_valid(count, seconds, rate, lower, upper) {
      if (seconds <= 0.0000005) return 0
      lower = count / (seconds + 0.0000005) - 0.0000005
      upper = count / (seconds - 0.0000005) + 0.0000005
      return rate >= lower && rate <= upper
    }
    NR == FNR {
      if (FNR > 1 && $2 == implementation) {
        count++
        cycles[$4 + 0] = $5
        operations[$4 + 0] = $6
        seconds[$4 + 0] = $7
        lifecycle_rate[$4 + 0] = $8
        operation_rate[$4 + 0] = $9
      }
      next
    }
    FNR == 1 {
      if ($0 != "repetition\tcycles\toperations\tseconds\tlifecycles_per_second\toperations_per_second") {
        print "invalid raw header" > "/dev/stderr"
        exit 1
      }
      next
    }
    {
      repetition = $1 + 0
    }
    NF != 6 || repetition != FNR - 1 || count != 3 ||
    $2 + 0 != cycles[repetition] + 0 ||
    $3 + 0 != operations[repetition] + 0 ||
    $4 != seconds[repetition] || $5 != lifecycle_rate[repetition] ||
    $6 != operation_rate[repetition] ||
    !rate_valid($2 + 0, $4 + 0, $5 + 0) ||
    !rate_valid($3 + 0, $4 + 0, $6 + 0) {
      print "invalid raw row at line " NR > "/dev/stderr"
      exit 1
    }
    END {
      if (FNR != 4) {
        print "raw file must contain exactly three repetitions" > "/dev/stderr"
        exit 1
      }
    }
  ' "$SAMPLES" "$EVIDENCE/raw/$implementation.tsv" \
    || fail "invalid raw/$implementation.tsv derivation"
done

if [ "${FLYOLOGY_BUCKET_TAG_EVIDENCE_SKIP_MUTANT:-0}" != 1 ]; then
  mutant_root=$(mktemp -d "${TMPDIR:-/tmp}/flyology-bucket-tag-evidence-mutant.XXXXXX")
  trap 'rm -rf -- "$mutant_root"' EXIT INT TERM
  cp -R "$EVIDENCE/." "$mutant_root/"

  # Keep hashes, raw/normalized derivation, the four-times relation, and the
  # summary internally consistent while making the rate materially impossible
  # for the retained cycles and elapsed time. The semantic rate gate, rather
  # than a shallower integrity check, must reject this bundle.
  perl -pi -e \
    's/\t4\.498277\t14\.227670\t56\.910680\t/\t4.498277\t15.227670\t60.910680\t/' \
    "$mutant_root/samples.tsv" \
    "$mutant_root/raw/rustfs.samples.tsv"
  perl -pi -e \
    's/\t4\.498277\t14\.227670\t56\.910680$/\t4.498277\t15.227670\t60.910680/' \
    "$mutant_root/raw/rustfs.tsv"
  perl -pi -e \
    's/\t23\.163126\t92\.652503\t/\t23.496459\t93.985836\t/' \
    "$mutant_root/summary.tsv"

  mutant_hashes=$(mktemp "$mutant_root/hashes.sha256.XXXXXX")
  while read -r _ relative; do
    digest=$(shasum -a 256 "$mutant_root/$relative" | awk '{print $1}')
    printf '%s  %s\n' "$digest" "$relative" >>"$mutant_hashes"
  done <"$mutant_root/hashes.sha256"
  mv "$mutant_hashes" "$mutant_root/hashes.sha256"

  mutant_output="$mutant_root/verifier-output.txt"
  if FLYOLOGY_BUCKET_TAG_EVIDENCE_SKIP_MUTANT=1 \
    "$0" "$mutant_root" >"$mutant_output" 2>&1
  then
    fail "materially inconsistent rate mutation was accepted"
  fi
  grep -Fq "invalid sample row at line 2" "$mutant_output" \
    || fail "rate mutation was rejected for an unexpected reason"
fi

echo "bucket-tagging benchmark evidence: 6 roles, 18 samples, 4 requests/lifecycle, derivation/rate mutant rejected, hashes OK"
