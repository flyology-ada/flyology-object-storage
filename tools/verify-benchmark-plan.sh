#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
PLAN="$PROJECT_DIR/benchmarks/scenarios.tsv"
IMPLEMENTATIONS="$PROJECT_DIR/benchmarks/implementations.tsv"
ELIGIBILITY="$PROJECT_DIR/benchmarks/eligibility.tsv"
EXCLUSIONS="$PROJECT_DIR/benchmarks/exclusions.tsv"

awk -F '\t' '
  NR == 1 {
    expected = "scenario\toperation\tobject_bytes\tobjects\tconcurrency\tduration_seconds\twarmup_seconds"
    if ($0 != expected) {
      print "invalid benchmark scenario header" > "/dev/stderr"
      exit 1
    }
    next
  }
  NF != 7 {
    print "invalid benchmark scenario column count at line " NR > "/dev/stderr"
    exit 1
  }
  seen[$1]++ {
    print "duplicate benchmark scenario: " $1 > "/dev/stderr"
    exit 1
  }
  $2 !~ /^(put|get|copy|multipart-put|list|list-v1|list-multipart-uploads|delete|mixed)$/ {
    print "invalid benchmark operation at line " NR > "/dev/stderr"
    exit 1
  }
  $3 !~ /^[0-9]+$/ || $4 !~ /^[1-9][0-9]*$/ ||
  $5 !~ /^[1-9][0-9]*$/ || $6 !~ /^[1-9][0-9]*$/ ||
  $7 !~ /^[1-9][0-9]*$/ {
    print "invalid benchmark numeric field at line " NR > "/dev/stderr"
    exit 1
  }
  END {
    if (NR != 13) {
      print "benchmark plan must contain exactly twelve scenarios" > "/dev/stderr"
      exit 1
    }
  }
' "$PLAN"

echo "benchmark plan: 12 deterministic scenarios"

awk -F '\t' '
  NR == 1 {
    expected = "implementation\trole\tbackend\tdurability"
    if ($0 != expected) {
      print "invalid benchmark implementation header" > "/dev/stderr"
      exit 1
    }
    next
  }
  NF != 4 {
    print "invalid benchmark implementation column count at line " NR > "/dev/stderr"
    exit 1
  }
  seen[$1]++ {
    print "duplicate benchmark implementation: " $1 > "/dev/stderr"
    exit 1
  }
  $2 !~ /^(permissive-reference|candidate)$/ {
    print "invalid benchmark implementation role at line " NR > "/dev/stderr"
    exit 1
  }
  { rows[$1] = $2 "\t" $3 "\t" $4 }
  END {
    if (NR != 6 ||
        rows["rustfs"] !~ /^permissive-reference\texternal\t/ ||
        rows["seaweedfs"] !~ /^permissive-reference\texternal\t/ ||
        rows["flyology-memory"] != "candidate\tmemory\tvolatile" ||
        rows["flyology-files"] != "candidate\tfiles\tatomic-not-power-durable" ||
        rows["flyology-sqlite"] != "candidate\tsqlite\twal-synchronous-full") {
      print "benchmark matrix must contain two references and three Flyology backends" > "/dev/stderr"
      exit 1
    }
  }
' "$IMPLEMENTATIONS"

echo "benchmark matrix: 2 permissive references, 3 Flyology backends"

awk -F '\t' '
  NR == FNR {
    if (FNR > 1) plan[$1] = 1
    next
  }
  FNR == 1 {
    if ($0 != "scenario\tcommon_status\treason") {
      print "invalid benchmark eligibility header" > "/dev/stderr"
      exit 1
    }
    next
  }
  NF != 3 || !($1 in plan) || $2 !~ /^(supported|blocked)$/ || $3 == "" {
    print "invalid benchmark eligibility row at line " FNR > "/dev/stderr"
    exit 1
  }
  { counts[$2]++ }
  seen[$1]++ {
    print "duplicate benchmark eligibility: " $1 > "/dev/stderr"
    exit 1
  }
  END {
    for (scenario in plan) {
      if (!(scenario in seen)) {
        print "missing benchmark eligibility: " scenario > "/dev/stderr"
        exit 1
      }
    }
    if (counts["supported"] != 11 || counts["blocked"] != 1) {
      print "benchmark eligibility must contain eleven supported and one blocked scenario" > "/dev/stderr"
      exit 1
    }
  }
' "$PLAN" "$ELIGIBILITY"

echo "benchmark eligibility: 11 supported, 1 globally blocked"

awk -F '\t' '
  FILENAME == ARGV[1] {
    if (FNR > 1) plan[$1] = 1
    next
  }
  FILENAME == ARGV[2] {
    if (FNR > 1) implementations[$1] = 1
    next
  }
  FNR == 1 {
    if ($0 != "scenario\timplementation\tstatus\treason") {
      print "invalid benchmark exclusion header" > "/dev/stderr"
      exit 1
    }
    next
  }
  NF != 4 || !($1 in plan) || !($2 in implementations) ||
  $3 != "blocked" || $4 == "" {
    print "invalid benchmark exclusion row at line " FNR > "/dev/stderr"
    exit 1
  }
  seen[$1 SUBSEP $2]++ {
    print "duplicate benchmark exclusion: " $1 " / " $2 > "/dev/stderr"
    exit 1
  }
  { exclusions++ }
  END {
    if (exclusions != 1 ||
        !("multipart-upload-list" SUBSEP "seaweedfs" in seen)) {
      print "benchmark exclusions must capture the pinned SeaweedFS listing defect" > "/dev/stderr"
      exit 1
    }
  }
' "$PLAN" "$IMPLEMENTATIONS" "$EXCLUSIONS"

echo "benchmark exclusions: SeaweedFS multipart listing defect is explicit"

test -x "$PROJECT_DIR/benchmarks/run-endpoint.sh"
test -x "$PROJECT_DIR/benchmarks/run-matrix.sh"
test -x "$PROJECT_DIR/benchmarks/summarize.sh"
bash -n "$PROJECT_DIR/benchmarks/run-endpoint.sh" \
  "$PROJECT_DIR/benchmarks/run-matrix.sh" \
  "$PROJECT_DIR/benchmarks/summarize.sh"

echo "benchmark launchers: executable and syntax-clean"
