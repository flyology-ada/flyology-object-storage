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

expect_rejection commented-test-model-url \
  'test model fetch must execute the exact pinned download command' \
  awk '
    /raw.githubusercontent.com\/boto\/botocore/ { models++ }
    models == 2 && /raw.githubusercontent.com\/boto\/botocore/ {
      print "            # " $0
      sub(/raw.githubusercontent.com/, "invalid.example")
    }
    { print }
  ' "$WORKFLOW"

expect_rejection commented-test-model-output \
  'test model fetch must execute the exact pinned download command' \
  awk '
    /--output obj\/ci\/service-2.json/ { outputs++ }
    outputs == 2 && /--output obj\/ci\/service-2.json/ {
      print "            # " $0
      sub(/obj\/ci\/service-2.json/, "obj/ci/wrong-model.json")
    }
    { print }
  ' "$WORKFLOW"

expect_rejection commented-test-model-export \
  'root and SQLite gate environment must be a mapping' \
  awk '
    /FLYOLOGY_S3_SERVICE_MODEL:/ {
      print "          # " $0
      next
    }
    { print }
  ' "$WORKFLOW"

expect_rejection disabled-test-model-fetch \
  'test model fetch step must be unconditional' \
  awk '
    /- name: Fetch pinned botocore S3 model/ { fetches++ }
    { print }
    fetches == 2 && !inserted && /- name: Fetch pinned botocore S3 model/ {
      print "        if: ${{ false }}"
      inserted=1
    }
  ' "$WORKFLOW"

expect_rejection disabled-root-sqlite-gate \
  'root and SQLite gate step must be unconditional' \
  awk '
    { print }
    !inserted && /- name: Run root and SQLite gates/ {
      print "        if: ${{ false }}"
      inserted=1
    }
  ' "$WORKFLOW"

expect_rejection commented-test-command \
  'root and SQLite gate must execute the maintained test wrapper' \
  awk '
    /run: \.\/tools\/ci\/run-tests.sh/ {
      print "        run: |"
      print "          # ./tools/ci/run-tests.sh"
      print "          echo tests skipped"
      next
    }
    { print }
  ' "$WORKFLOW"

expect_rejection test-job-continues-on-error \
  'test job must fail the workflow on error' \
  awk '
    { print }
    !inserted && /^  test:$/ {
      print "    continue-on-error: true"
      inserted=1
    }
  ' "$WORKFLOW"

expect_rejection test-job-shell-default \
  'test job run defaults are forbidden' \
  awk '
    { print }
    !inserted && /^  test:$/ {
      print "    defaults:"
      print "      run:"
      print "        shell: echo {0}"
      inserted=1
    }
  ' "$WORKFLOW"

expect_rejection workflow-shell-default \
  'workflow run defaults are forbidden' \
  awk '
    !inserted && /^jobs:$/ {
      print "defaults:"
      print "  run:"
      print "    shell: echo {0}"
      print ""
      inserted=1
    }
    { print }
  ' "$WORKFLOW"

expect_rejection test-step-working-directory \
  'test model fetch and root/SQLite gate must run from the repository root' \
  awk '
    { print }
    !inserted && /- name: Run root and SQLite gates/ {
      print "        working-directory: tests"
      inserted=1
    }
  ' "$WORKFLOW"

expect_rejection workflow-shellopts \
  'workflow environment is forbidden' \
  awk '
    !inserted && /^jobs:$/ {
      print "env:"
      print "  SHELLOPTS: noexec"
      print ""
      inserted=1
    }
    { print }
  ' "$WORKFLOW"

expect_rejection test-job-shellopts \
  'test job environment is forbidden' \
  awk '
    { print }
    !inserted && /^  test:$/ {
      print "    env:"
      print "      SHELLOPTS: noexec"
      inserted=1
    }
  ' "$WORKFLOW"

expect_rejection test-model-fetch-shellopts \
  'test model fetch environment is forbidden' \
  awk '
    /- name: Fetch pinned botocore S3 model/ { fetches++ }
    { print }
    fetches == 2 && !inserted && /- name: Fetch pinned botocore S3 model/ {
      print "        env:"
      print "          SHELLOPTS: noexec"
      inserted=1
    }
  ' "$WORKFLOW"

expect_rejection root-sqlite-gate-shellopts \
  'root and SQLite gate environment must contain only the model path' \
  awk '
    { print }
    !inserted && /FLYOLOGY_S3_SERVICE_MODEL:/ {
      print "          SHELLOPTS: noexec"
      inserted=1
    }
  ' "$WORKFLOW"

expect_rejection preceding-step-persists-shellopts \
  'test job steps must match the reviewed sequence and definitions' \
  awk '
    /- name: Fetch pinned botocore S3 model/ { fetches++ }
    fetches == 2 && !inserted && /- name: Fetch pinned botocore S3 model/ {
      print "      - name: Persist no-execution shell option"
      print "        run: echo SHELLOPTS=noexec >> \"$GITHUB_ENV\""
      inserted=1
    }
    { print }
  ' "$WORKFLOW"

expect_rejection preceding-step-persists-bash-env \
  'test job steps must match the reviewed sequence and definitions' \
  awk '
    /- name: Fetch pinned botocore S3 model/ { fetches++ }
    fetches == 2 && !inserted && /- name: Fetch pinned botocore S3 model/ {
      print "      - name: Persist early-exit Bash environment"
      print "        run: |"
      print "          printf \047exit 0\\n\047 > obj/ci/bash-env"
      print "          echo BASH_ENV=$PWD/obj/ci/bash-env >> \"$GITHUB_ENV\""
      inserted=1
    }
    { print }
  ' "$WORKFLOW"

expect_rejection preceding-step-replaces-wrapper \
  'test job steps must match the reviewed sequence and definitions' \
  awk '
    !inserted && /- name: Run root and SQLite gates/ {
      print "      - name: Replace maintained test wrapper"
      print "        run: |"
      print "          printf \047#!/bin/sh\\nexit 0\\n\047 > tools/ci/run-tests.sh"
      print "          chmod +x tools/ci/run-tests.sh"
      inserted=1
    }
    { print }
  ' "$WORKFLOW"

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
  'test job steps must match the reviewed sequence and definitions' \
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

echo "workflow policy negative oracle: 26 unsafe mutations rejected"
