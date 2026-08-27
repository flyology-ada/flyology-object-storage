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
  'integrity and test jobs must install exact uv 0.11.28' \
  sed 's/version: "0.11.28"/version: "0.11.27"/g' "$WORKFLOW"

expect_rejection persisted-credentials \
  'every checkout must disable persisted credentials' \
  awk '
    !changed && /persist-credentials: false/ {
      sub(/persist-credentials: false/, "persist-credentials: true")
      changed=1
    }
    { print }
  ' "$WORKFLOW"

echo "workflow policy negative oracle: 5 unsafe mutations rejected"
