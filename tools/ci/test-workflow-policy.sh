#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
VERIFIER="$PROJECT_DIR/tools/ci/verify-workflow-policy.sh"
WORKFLOW="$PROJECT_DIR/.github/workflows/ci.yml"
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/flyology-workflow-policy.XXXXXX")
trap 'case "$TEMP_ROOT" in */flyology-workflow-policy.*) rm -rf "$TEMP_ROOT" ;; esac' EXIT INT TERM

expect_rejection() {
  name=$1
  expected=$2
  fixture="$TEMP_ROOT/$name.yml"
  output="$TEMP_ROOT/$name.log"
  shift 2
  "$@" >"$fixture"
  if "$VERIFIER" "$fixture" >"$output" 2>&1; then
    echo "workflow policy accepted $name mutation" >&2
    exit 1
  fi
  if ! grep -Fq "$expected" "$output"; then
    echo "workflow policy rejected $name for the wrong reason" >&2
    cat "$output" >&2
    exit 1
  fi
}

expect_rejection mutable-action \
  'GitHub Action is not pinned to a full commit: actions/checkout@v6' \
  sed -E \
    's#actions/checkout@[0-9a-f]{40}#actions/checkout@v6#g' "$WORKFLOW"

expect_rejection missing-proof-tool \
  'proof job must install exact gnatprove=16.1.0 once' \
  sed \
    's/run: alr install gnatprove=16.1.0/run: alr install gnatprove=16.0.0/' \
    "$WORKFLOW"

expect_rejection missing-docs-tool \
  'docs job must install exact gnatdoc_bin=26.0.0 once' \
  sed \
    's/run: alr install gnatdoc_bin=26.0.0/run: alr install gnatdoc_bin=25.0.0/' \
    "$WORKFLOW"

expect_rejection wrong-uv-version \
  'integrity, test, and docs jobs must install exact uv 0.11.28' \
  sed 's/version: "0.11.28"/version: "0.11.27"/g' "$WORKFLOW"

expect_rejection missing-docs-uv \
  'integrity, test, and docs jobs must install exact setup-uv v9.0.0' \
  awk '
    /uses: astral-sh\/setup-uv@/ { installs++ }
    installs == 3 && /uses: astral-sh\/setup-uv@/ {
      sub(/astral-sh\/setup-uv@/, "astral-sh/setup-not-uv@")
    }
    { print }
  ' "$WORKFLOW"

expect_rejection missing-docs-operation \
  'docs job must select the stable ListBuckets API once' \
  sed '/--operation ListBuckets/d' "$WORKFLOW"

expect_rejection relocated-docs-uv \
  'docs job must install exact setup-uv v9.0.0 once' \
  awk '
    /^  test:$/ { job="test" }
    /^  docs:$/ { job="docs" }
    job == "test" && !inserted && /- name: Install Alire/ {
      print "      - name: Install uv"
      print "        uses: astral-sh/setup-uv@c771a70e6277c0a99b617c7a806ffedaca235ff9 # v9.0.0"
      print "        with:"
      print "          version: \"0.11.28\""
      inserted=1
    }
    job == "docs" && /- name: Install uv/ { skip=4 }
    skip > 0 { skip--; next }
    { print }
  ' "$WORKFLOW"

expect_rejection relocated-docs-command \
  'docs job must invoke the maintained GNATdoc wrapper once' \
  awk '
    /^  integrity:$/ { job="integrity" }
    /^  docs:$/ { job="docs" }
    job == "integrity" && !inserted && /- name: Upload integrity log/ {
      print "      - name: Build API reference"
      print "        run: >-"
      print "          ./tools/build-api-docs.sh \"$PWD/obj/docs/api\""
      print "          --operation ListBuckets"
      inserted=1
    }
    job == "docs" && /- name: Build API reference/ { skip=4 }
    skip > 0 { skip--; next }
    { print }
  ' "$WORKFLOW"

expect_rejection persisted-credentials \
  'every checkout must disable persisted credentials' \
  awk '
    !changed && /persist-credentials: false/ {
      sub(/persist-credentials: false/, "persist-credentials: true")
      changed=1
    }
    { print }
  ' "$WORKFLOW"

echo "workflow policy negative oracle: 9 unsafe mutations rejected"
